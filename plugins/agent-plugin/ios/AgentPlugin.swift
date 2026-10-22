import Foundation
import Capacitor
import UIKit
import AVFoundation
import Speech
import Security

/// ประสานการขออนุมัติจาก UI (ผู้ใช้ต้องกดยืนยันในแอป)
final class ApprovalCoordinator: ApprovalGate, @unchecked Sendable {

    private let lock = NSLock()
    private var pending: [String: CheckedContinuation<Bool, Never>] = [:]
    private var onRequest: ((String, String, String) -> Void)?

    func setHandler(_ handler: @escaping (String, String, String) -> Void) {
        lock.lock(); onRequest = handler; lock.unlock()
    }

    func requestApproval(tool: String, summary: String) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let id = UUID().uuidString
            lock.lock()
            pending[id] = cont
            let handler = onRequest
            lock.unlock()
            handler?(id, tool, summary)
            // กันค้างถ้าผู้ใช้ไม่ตอบ — 60 วินาทีแล้วถือว่าไม่อนุมัติ
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                self?.resolve(id, approved: false)
            }
        }
    }

    func resolve(_ id: String, approved: Bool) {
        lock.lock()
        let cont = pending.removeValue(forKey: id)
        lock.unlock()
        cont?.resume(returning: approved)
    }}

/// คีย์ API เก็บใน Keychain (ไม่เก็บใน UserDefaults)
enum KeychainStore {
    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@objc(AgentPlugin)
public class AgentPlugin: CAPPlugin, CAPBridgedPlugin, BrainEvents {

    public var identifier = "AgentPlugin"
    public var jsName = "AgentPlugin"
    public var pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "availability", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "listTools", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "send", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "approve", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "speak", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopSpeak", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setApiKey", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getConfig", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "selectProvider", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "listen", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopListen", returnType: CAPPluginReturnPromise),
    ]

    // MARK: - State

    private let gate = ApprovalCoordinator()
    private lazy var tools = DeviceTools(gate: gate)
    private var respondFn: ((String) async throws -> String)?
    private var resetFn: (() -> Void)?
    private var brainKind = "none"
    private var busy = false
    private var dictation: DictationController?

    override public func load() {
        super.load()
        gate.setHandler { [weak self] id, tool, summary in
            self?.notifyListeners("approval", data: ["id": id, "tool": tool, "summary": summary])
        }
    }

    func emit(_ type: String, _ data: [String: Any]) {
        var payload = data
        payload["type"] = type
        // notifyListeners ต้องเรียกบน main thread
        if Thread.isMainThread {
            notifyListeners("agent", data: payload)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.notifyListeners("agent", data: payload)
            }
        }
    }

    // MARK: - ความพร้อม

    @objc func availability(_ call: CAPPluginCall) {
        var result: [String: Any] = [
            "ios": UIDevice.current.systemVersion,
            "device": UIDevice.current.model,
            "brain": brainKind,
            "busy": busy,
        ]
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            result["onDevice"] = OnDeviceBrain.availability()
        } else {
            result["onDevice"] = ["available": false, "status": "iOS ต่ำกว่า 26", "note": "ต้องใช้โมเดลคลาวด์"]
        }
        #else
        result["onDevice"] = ["available": false, "status": "ไม่รองรับ", "note": "ต้องใช้โมเดลคลาวด์"]
        #endif
        call.resolve(result)
    }

    @objc func listTools(_ call: CAPPluginCall) {
        call.resolve(["tools": ToolCatalog.specsJSON()])
    }

    // MARK: - เริ่ม / ส่งข้อความ

    @objc func start(_ call: CAPPluginCall) {
        let kind = (call.getString("brain") ?? "ondevice").lowercased()

        if kind == "cloud" {
            let providerID = call.getString("provider") ?? ProviderStore.selected
            if let model = call.getString("model"), !model.isEmpty {
                ProviderStore.setModel(model, for: providerID)
            }
            if let base = call.getString("baseUrl"), !base.isEmpty, providerID == "custom" {
                ProviderStore.customBaseURL = base
            }
            if let key = call.getString("apiKey") {
                ProviderStore.setKey(key, for: providerID)
            }
            ProviderStore.selected = providerID

            guard let resolved = ProviderStore.resolve(providerID) else {
                call.reject("ไม่พบผู้ให้บริการ \(providerID)")
                return
            }
            // ค่าจาก UI (รายการผู้ให้บริการในแอป) มีความสำคัญกว่า — ใช้ค่านั้นถ้าส่งมา
            let baseURL = call.getString("baseUrl") ?? resolved.baseURL
            let formatRaw = call.getString("format") ?? resolved.spec.format.rawValue
            let format = APIFormat(rawValue: formatRaw) ?? resolved.spec.format
            let apiKey = call.getString("apiKey").flatMap { $0.isEmpty ? nil : $0 } ?? resolved.apiKey
            let model = call.getString("model").flatMap { $0.isEmpty ? nil : $0 } ?? resolved.model

            if resolved.spec.keyRequired && apiKey.isEmpty {
                call.reject("ผู้ให้บริการ \(resolved.spec.name) ต้องใส่ API key ก่อน")
                return
            }
            if baseURL.isEmpty {
                call.reject("ยังไม่ได้ใส่ Base URL ของผู้ให้บริการ")
                return
            }
            let brain = CloudBrain(spec: resolved.spec,
                                  format: format,
                                  baseURL: baseURL,
                                  apiKey: apiKey,
                                  model: model,
                                  tools: tools,
                                  events: self)
            respondFn = { [weak brain] text in try await brain?.respond(to: text) ?? "" }
            resetFn = { [weak brain] in brain?.reset() }
            brainKind = "cloud"
            emit("status", ["state": "ready", "detail": "\(resolved.spec.name) · \(resolved.model)"])
            call.resolve(["ok": true, "brain": brainKind, "provider": providerID, "model": resolved.model])
            return
        }

        // โมเดลบนเครื่อง
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let brain = OnDeviceBrain(tools: tools, events: self)
            do {
                try brain.start()
                respondFn = { [weak brain] text in try await brain?.respond(to: text) ?? "" }
                resetFn = { [weak brain] in brain?.reset() }
                brainKind = "ondevice"
                call.resolve(["ok": true, "brain": brainKind])
                return
            } catch {
                call.reject("เปิดโมเดลบนเครื่องไม่สำเร็จ: \(error.localizedDescription)")
                return
            }
        }
        #endif
        call.reject("เครื่องนี้ไม่รองรับโมเดลบนเครื่อง — เลือกโหมดคลาวด์แทน")
    }

    @objc func send(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            call.reject("ข้อความว่าง")
            return
        }
        guard let respondFn else {
            call.reject("ยังไม่ได้เริ่มสมอง — เรียก start() ก่อน")
            return
        }
        guard !busy else {
            call.reject("เอเจนต์กำลังทำงานอยู่")
            return
        }
        busy = true
        emit("status", ["state": "thinking", "detail": "กำลังคิด…"])

        let runner = respondFn
        Task {
            var finalText = ""
            do {
                finalText = try await runner(text)
            } catch {
                self.busy = false
                self.emit("error", ["message": error.localizedDescription])
                call.reject(error.localizedDescription)
                return
            }
            self.busy = false
            self.emit("done", ["text": finalText])
            call.resolve(["text": finalText])
        }
    }

    @objc func cancel(_ call: CAPPluginCall) {
        busy = false
        emit("status", ["state": "idle", "detail": "หยุดโดยผู้ใช้"])
        call.resolve(["ok": true])
    }

    @objc func approve(_ call: CAPPluginCall) {
        let id = call.getString("id") ?? ""
        let approved = call.getBool("approved") ?? false
        gate.resolve(id, approved: approved)
        call.resolve(["ok": true])
    }

    // MARK: - เสียง

    @objc func speak(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        DispatchQueue.main.async { SpeechCenter.shared.speak(text) }
        call.resolve(["ok": true])
    }

    @objc func stopSpeak(_ call: CAPPluginCall) {
        DispatchQueue.main.async { SpeechCenter.shared.stop() }
        call.resolve(["ok": true])
    }

    @objc func listen(_ call: CAPPluginCall) {
        let lang = call.getString("lang") ?? "th-TH"
        let controller = DictationController(locale: lang)
        self.dictation = controller
        controller.onPartial = { [weak self] text in
            self?.emit("dictation", ["text": text, "final": false])
        }
        controller.onFinish = { [weak self] text, error in
            self?.dictation = nil
            if let error {
                self?.emit("dictation", ["text": "", "final": true, "error": error])
                call.reject(error)
            } else {
                self?.emit("dictation", ["text": text, "final": true])
                call.resolve(["text": text])
            }
        }
        controller.start()
    }

    @objc func stopListen(_ call: CAPPluginCall) {
        dictation?.stop()
        dictation = nil
        call.resolve(["ok": true])
    }

    // MARK: - ตั้งค่า

    @objc func setApiKey(_ call: CAPPluginCall) {
        let provider = call.getString("provider") ?? ProviderStore.selected
        let key = call.getString("apiKey") ?? ""
        ProviderStore.setKey(key, for: provider)
        call.resolve(["ok": true, "provider": provider, "hasKey": !key.isEmpty])
    }

    @objc func getConfig(_ call: CAPPluginCall) {
        let selected = ProviderStore.selected
        var providers: [[String: Any]] = []
        for p in ProviderCatalog.providersJSON() {
            var item = p
            let pid = (p["id"] as? String) ?? ""
            item["hasKey"] = !ProviderStore.key(for: pid).isEmpty
            item["currentModel"] = ProviderStore.model(for: pid)
            providers.append(item)
        }
        call.resolve([
            "providers": providers,
            "selected": selected,
            "selectedModel": ProviderStore.model(for: selected),
            "customBaseURL": ProviderStore.customBaseURL,
            "brain": brainKind,
        ])
    }

    /// บันทึกตัวเลือกผู้ให้บริการ + โมเดล
    @objc func selectProvider(_ call: CAPPluginCall) {
        let provider = call.getString("provider") ?? ""
        if !provider.isEmpty { ProviderStore.selected = provider }
        if let model = call.getString("model"), !model.isEmpty {
            ProviderStore.setModel(model, for: provider.isEmpty ? ProviderStore.selected : provider)
        }
        if let base = call.getString("baseUrl") {
            ProviderStore.customBaseURL = base
        }
        call.resolve(["ok": true, "selected": ProviderStore.selected])
    }
}

// MARK: - แปลงเสียงเป็นข้อความ (dictation)

final class DictationController: NSObject, SFSpeechRecognizerDelegate {

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var finished = false
    private var tapInstalled = false

    var onPartial: ((String) -> Void)?
    var onFinish: ((String, String?) -> Void)?

    init(locale: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
        super.init()
    }

    func start() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                self.finish("", error: "ไม่ได้รับสิทธิ์การอ่านเสียงพูด")
                return
            }
            DispatchQueue.main.async { self.beginRecording() }
        }
    }

    private func beginRecording() {
        guard let recognizer, recognizer.isAvailable else {
            finish("", error: "การอ่านเสียงพูดยังไม่พร้อมใช้งาน")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            finish("", error: "เปิดไมโครโฟนไม่สำเร็จ: \(error.localizedDescription)")
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.onPartial?(result.bestTranscription.formattedString)
                if result.isFinal {
                    self.finish(result.bestTranscription.formattedString, error: nil)
                }
            } else if let error {
                self.finish("", error: error.localizedDescription)
            }
        }
    }

    func stop() {
        finish("", error: nil)
    }

    private func inputRemoval() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func finish(_ text: String, error: String?) {
        lock.lock()
        if finished { lock.unlock(); return }
        finished = true
        lock.unlock()
        inputRemoval()
        request?.endAudio()
        task?.cancel()
        onFinish?(text, error)
    }
}
