import Foundation
import UIKit
import AVFoundation
import EventKit
import CoreLocation
import Contacts
import Photos
import Vision
import MediaPlayer
import Network
import SystemConfiguration

/// ขออนุมัติจากผู้ใช้ก่อนทำ action ที่เสี่ยง
protocol ApprovalGate: AnyObject {
    func requestApproval(tool: String, summary: String) async -> Bool
}

/// ตัวรันเครื่องมือทั้งหมด — ทำงานบน iPhone จริง
final class DeviceTools: @unchecked Sendable {

    private let gate: ApprovalGate?
    private let lock = NSLock()
    private var _lastImageData: Data?
    private var _locationHelper: LocationHelper?
    private var _photoDelegate: PhotoPickerDelegate?

    private var photoDelegate: PhotoPickerDelegate? {
        get { lock.lock(); defer { lock.unlock() }; return _photoDelegate }
        set { lock.lock(); _photoDelegate = newValue; lock.unlock() }
    }

    init(gate: ApprovalGate?) {
        self.gate = gate
    }

    private var lastImageData: Data? {
        get { lock.lock(); defer { lock.unlock() }; return _lastImageData }
        set { lock.lock(); _lastImageData = newValue; lock.unlock() }
    }

    private var locationHelper: LocationHelper? {
        get { lock.lock(); defer { lock.unlock() }; return _locationHelper }
        set { lock.lock(); _locationHelper = newValue; lock.unlock() }
    }

    // MARK: - จุดเข้าหลัก

    func run(name: String, value: String, extra: String?) async throws -> String {
        let spec = ToolCatalog.spec(named: name)
        guard let spec else {
            return "ไม่พบเครื่องมือชื่อ \(name) — เครื่องมือที่ใช้ได้: " + ToolCatalog.specs.map(\.name).joined(separator: ", ")
        }

        if spec.risk == .sensitive {
            let summary = humanSummary(tool: name, value: value, extra: extra)
            let ok = await gate?.requestApproval(tool: name, summary: summary) ?? false
            if !ok {
                return "ผู้ใช้ปฏิเสธการทำงานของเครื่องมือ \(name) — หยุดทำงาน ไม่ต้องทำซ้ำ"
            }
        }

        switch name {
        case "device_info": return deviceInfo()
        case "set_volume": return setVolume(value)
        case "set_brightness": return setBrightness(value)
        case "open_app": return openApp(value)
        case "open_url": return openURL(value)
        case "search_web": return searchWeb(value)
        case "run_shortcut": return runShortcut(value: value, extra: extra)
        case "speak": return speak(value)
        case "stop_speak": return stopSpeak()
        case "set_reminder": return await setReminder(value: value, extra: extra)
        case "list_reminders": return await listReminders()
        case "add_calendar": return await addCalendar(value: value, extra: extra)
        case "list_calendar": return await listCalendar()
        case "get_location": return await currentLocation()
        case "search_contacts": return await searchContacts(value)
        case "list_photos": return await listPhotos(count: value)
        case "take_photo": return await takePhoto(question: value)
        case "ocr_image": return await ocrImage(question: value)
        case "read_clipboard": return readClipboard()
        case "write_clipboard": return writeClipboard(value)
        case "make_call": return makeCall(value)
        case "send_message": return sendMessage(value)
        case "share_text": return shareText(value)
        case "wifi_info": return wifiInfo()
        case "list_shortcuts": return listShortcuts()
        default: return "เครื่องมือ \(name) ยังไม่ได้ทำในรุ่นนี้"
        }
    }

    private func humanSummary(tool: String, value: String, extra: String?) -> String {
        switch tool {
        case "run_shortcut": return "เอเจนต์จะสั่ง Shortcut ชื่อ “\(value)”"
        case "make_call": return "เอเจนต์จะโทรหา \(value)"
        case "send_message":
            let parts = value.components(separatedBy: "|")
            return "เอเจนต์จะส่งข้อความให้ \(parts.first ?? value) ว่า “\(parts.count > 1 ? parts[1] : "")”"
        default: return "เอเจนต์จะใช้เครื่องมือ \(tool): \(value)"
        }
    }

    // MARK: - ข้อมูลเครื่อง

    private func deviceInfo() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let battery = UIDevice.current.batteryLevel >= 0
            ? String(format: "%.0f%%", UIDevice.current.batteryLevel * 100) : "ไม่ทราบ"
        let fm = FileManager.default
        let free = (try? fm.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber)?.intValue ?? 0
        let freeGB = String(format: "%.1f GB", Double(free) / 1_073_741_824)
        let mem = (ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        return """
        ข้อมูลเครื่อง:
        - รุ่น: \(UIDevice.current.model) (\(UIDevice.current.name))
        - iOS: \(UIDevice.current.systemVersion)
        - แบต: \(battery) \(UIDevice.current.batteryState == .charging ? "(กำลังชาร์จ)" : "")
        - พื้นที่ว่าง: \(freeGB)
        - หน่วยความจำ: \(mem) GB
        """
    }

    // MARK: - ระดับเสียง / ความสว่าง

    private func setVolume(_ value: String) -> String {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        if v == "mute" || v == "ปิดเสียง" || v == "เงียบ" {
            setSystemVolume(0)
            return "ปิดเสียงเรียบร้อย"
        }
        guard let level = Float(v) else { return "ค่าระดับเสียงไม่ถูกต้อง (ต้องเป็น 0.0-1.0)" }
        setSystemVolume(min(max(level, 0), 1))
        return String(format: "ตั้งระดับเสียงเป็น %.0f%%", level * 100)
    }

    private func setSystemVolume(_ level: Float) {
        let work = {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)
            let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
            if let window = Self.keyWindow() {
                window.addSubview(volumeView)
            }
            if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
                slider.value = level
                slider.sendActions(for: .valueChanged)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { volumeView.removeFromSuperview() }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
    }

    private func setBrightness(_ value: String) -> String {
        guard let level = Float(value.trimmingCharacters(in: .whitespaces)) else {
            return "ค่าความสว่างไม่ถูกต้อง (ต้องเป็น 0.0-1.0)"
        }
        let clamped = min(max(level, 0), 1)
        let work = { UIScreen.main.brightness = CGFloat(clamped) }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        return String(format: "ตั้งความสว่างจอเป็น %.0f%%", clamped * 100)
    }

    // MARK: - เปิดแอป / เว็บ

    private static let appSchemes: [String: String] = [
        "youtube": "youtubebot://", "yt": "youtubebot://",
        "line": "line://", "ไลน์": "line://",
        "facebook": "fb://", "fb": "fb://",
        "messenger": "fb-messenger://",
        "instagram": "instagram://", "ig": "instagram://",
        "tiktok": "snssdk1233://", "ติ๊กต๊อก": "snssdk1233://",
        "spotify": "spotify://",
        "twitter": "twitter://", "x": "twitter://",
        "maps": "comgooglemaps://", "googlemaps": "comgooglemaps://", "แผนที่": "comgooglemaps://",
        "applemaps": "maps://",
        "netflix": "nflx://",
        "disneyplus": "disneyplus://",
        "grab": "grab://",
        "shopee": "shopee://", "ช้อป": "shopee://",
        "lazada": "lazada://",
        "foodpanda": "foodpanda://",
        "music": "music://",
        "podcasts": "podcasts://",
        "wallet": "shoebox://",
        "promptpay": "promptpay://",
        "health": "x-apple-health://",
        "settings": "App-Prefs://", "ตั้งค่า": "App-Prefs://",
        "safari": "safari://",
        "shortcuts": "shortcuts://", "ทางลัด": "shortcuts://",
        "clock": "clock-alarm://", "นาฬิกา": "clock-alarm://",
        "calculator": "calc://", "เครื่องคิดเลข": "calc://",
        "reminders": "x-apple-reminderkit://",
        "notes": "x-apple-notes://",
        "files": "shareddocuments://",
        "contacts": "x-apple-contacts://",
    ]

    private func openApp(_ value: String) -> String {
        let key = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard let scheme = Self.appSchemes[key] else {
            let names = Self.appSchemes.keys.sorted().joined(separator: ", ")
            return "ไม่รู้จักแอป “\(value)” — แอปที่เปิดได้: \(names) (ถ้าต้องการเปิดเว็บให้ใช้ open_url)"
        }
        guard let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) else {
            return "เปิดแอป “\(value)” ไม่ได้ — ดูเหมือนยังไม่ได้ติดตั้งแอปนี้ในเครื่อง"
        }
        Self.openOnMain(url)
        return "เปิดแอป \(value) แล้ว"
    }

    private func openURL(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
        if !text.lowercased().hasPrefix("http") && !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text) else { return "URL ไม่ถูกต้อง: \(value)" }
        Self.openOnMain(url)
        return "เปิด \(url.absoluteString) แล้ว"
    }

    private func searchWeb(_ value: String) -> String {
        let q = value.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return "ไม่ได้ใส่คำค้น" }
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        guard let url = URL(string: "https://duckduckgo.com/?q=\(encoded)") else { return "สร้าง URL ค้นหาไม่สำเร็จ" }
        Self.openOnMain(url)
        return "เปิดการค้นหา “\(q)” ในเบราว์เซอร์แล้ว"
    }

    // MARK: - Shortcut (ทางลัดเข้าถึงทุกแอป)

    private func runShortcut(value: String, extra: String?) -> String {
        let name = value.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "ไม่ได้ระบุชื่อ Shortcut" }
        var comps = URLComponents()
        comps.scheme = "shortcuts"
        comps.host = "run-shortcut"
        comps.queryItems = [URLQueryItem(name: "name", value: name)]
        if let extra, let input = Self.parseExtra(extra)["input"] {
            comps.queryItems?.append(URLQueryItem(name: "input", value: input))
            comps.queryItems?.append(URLQueryItem(name: "text", value: input))
        }
        guard let url = comps.url else { return "สร้าง URL ของ Shortcut ไม่สำเร็จ" }
        Self.openOnMain(url) { success in
            if !success { print("[AgentPlugin] เปิด Shortcut ไม่สำเร็จ: \(name)") }
        }
        return "สั่ง Shortcut “\(name)” แล้ว (ถ้า Shortcut ต้องการการยืนยัน iOS จะถามผู้ใช้)"
    }

    private func listShortcuts() -> String {
        return "iOS ไม่เปิดให้แอปอ่านรายชื่อ Shortcut ของผู้ใช้ได้ (ข้อจำกัดของระบบ) — "
            + "ให้ผู้ใช้บอกชื่อ Shortcut ที่ต้องการเรียกโดยตรง แล้วเรียกผ่าน run_shortcut "
            + "เช่น run_shortcut value='เปิดไฟ' extra='input=ห้องนอน'"
    }

    // MARK: - เสียงพูด

    private func speak(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return "ไม่มีข้อความให้พูด" }
        DispatchQueue.main.async { SpeechCenter.shared.speak(text) }
        return "กำลังพูด: \(text.prefix(120))"
    }

    private func stopSpeak() -> String {
        DispatchQueue.main.async { SpeechCenter.shared.stop() }
        return "หยุดการพูดแล้ว"
    }

    // MARK: - Reminders

    private func setReminder(value: String, extra: String?) async -> String {
        let title = value.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return "ไม่ได้ระบุข้อความเตือนความจำ" }
        let store = EKEventStore()
        let granted = await Self.requestReminders(store)
        guard granted else { return "ผู้ใช้ไม่ได้อนุญาตให้เข้าถึง Reminders" }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let extra, let at = Self.parseExtra(extra)["at"], let date = Self.parseDate(at) {
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }
        do {
            try store.save(reminder, commit: true)
            let when = Self.parseExtra(extra ?? "")["at"] ?? "ไม่กำหนดเวลา"
            return "สร้างเตือนความจำ “\(title)” แล้ว (ตั้งเวลา: \(when))"
        } catch {
            return "สร้างเตือนความจำไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    private func listReminders() async -> String {
        let store = EKEventStore()
        guard await Self.requestReminders(store) else { return "ผู้ใช้ไม่ได้อนุญาตให้เข้าถึง Reminders" }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let pred = store.predicateForReminders(in: [EKReminder.self], startDate: start, endDate: end)
        var titles: [String] = []
        let sem = DispatchSemaphore(value: 0)
        store.fetchReminders(matching: pred) { reminders in
            for r in reminders ?? [] {
                let due = r.dueDateComponents?.date.map { Self.fmt($0) } ?? "ไม่กำหนดเวลา"
                titles.append("• \(r.title ?? "(ไม่มีชื่อ)") — \(due)")
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 5)
        if titles.isEmpty { return "วันนี้ไม่มีเตือนความจำที่ครบกำหนด" }
        return "เตือนความจำวันนี้:\n" + titles.joined(separator: "\n")
    }

    private static func requestReminders(_ store: EKEventStore) async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    private static func requestEvents(_ store: EKEventStore) async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    private static func requestContacts(_ store: CNContactStore) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let work = {
                store.requestAccess(for: .contacts) { ok, _ in
                    cont.resume(returning: ok)
                }
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
        }
    }

    // MARK: - ปฏิทิน

    private func addCalendar(value: String, extra: String?) async -> String {
        let title = value.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return "ไม่ได้ระบุหัวข้อนัดหมาย" }
        let store = EKEventStore()
        guard await Self.requestEvents(store) else { return "ผู้ใช้ไม่ได้อนุญาตให้เข้าถึงปฏิทิน" }

        let params = Self.parseExtra(extra ?? "")
        let start = params["start"].flatMap(Self.parseDate) ?? Date().addingTimeInterval(3600)
        let duration = Double(params["duration"] ?? "") ?? 60
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(duration * 60)
        event.calendar = store.defaultCalendarForNewEvents()
        if let notes = params["notes"] { event.notes = notes }
        do {
            try store.save(event, commit: true)
            return "เพิ่มนัดหมาย “\(title)” เรีย่อวันที่ \(Self.fmt(start)) ยาว \(Int(duration)) นาที แล้ว"
        } catch {
            return "เพิ่มนัดหมายไม่สำเร็จ: \(error.localizedDescription)"
        }
    }

    private func listCalendar() async -> String {
        let store = EKEventStore()
        guard await Self.requestEvents(store) else { return "ผู้ใช้ไม่ได้อนุญาตให้เข้าถึงปฏิทิน" }
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: pred)
        if events.isEmpty { return "ไม่มีนัดหมายใน 7 วันข้างหน้า" }
        return "นัดหมาย 7 วันข้างหน้า:\n" + events.prefix(20).map { e in
            "• \(e.title ?? "(ไม่มีชื่อ)") — \(Self.fmt(e.startDate))"
        }.joined(separator: "\n")
    }

    // MARK: - ตำแหน่ง

    private func currentLocation() async -> String {
        let helper = LocationHelper()
        self.locationHelper = helper
        let location: CLLocation? = await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            helper.request { loc in cont.resume(returning: loc) }
        }
        guard let location else { return "ไม่สามารถอ่านตำแหน่งได้" }
        let place: CLPlacemark? = await withCheckedContinuation { (cont: CheckedContinuation<CLPlacemark?, Never>) in
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                cont.resume(returning: placemarks?.first)
            }
        }
        let coords = String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude)
        return "ตำแหน่งปัจจุบัน: \(place?.locality ?? place?.administrativeArea ?? "ไม่ทราบพื้นที่), \(place?.country ?? "") พิกัด \(coords)"
    }

    // MARK: - รายชื่อผู้ติดต่อ

    private func searchContacts(_ value: String) async -> String {
        let store = CNContactStore()
        guard await Self.requestContacts(store) else { return "ผู้ใช้ไม่ได้อนุญาตให้เข้าถึงรายชื่อผู้ติดต่อ" }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        let query = value.trimmingCharacters(in: .whitespaces)
        var results: [String] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            if results.count >= 10 { return }
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            if query.isEmpty || name.localizedCaseInsensitiveContains(query) {
                let phone = contact.phoneNumbers.first?.value.stringValue ?? "ไม่มีเบอร์"
                results.append("• \(name) — \(phone)")
            }
        }
        if results.isEmpty { return "ไม่พบรายชื่อที่ตรงกับ “\(query)”" }
        return "รายชื่อผู้ติดต่อ:\n" + results.joined(separator: "\n")
    }

    // MARK: - รูปภาพ

    private func listPhotos(count value: String) async -> String {
        let n = max(1, min(Int(value.trimmingCharacters(in: .whitespaces)) ?? 10, 50))
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return "ผู้ใช้ไม่ได้อนุญาตให้เข้าถึงคลังรูป" }
        let fetch = PHAsset.fetchAssets(with: .image, options: nil)
        var lines: [String] = []
        let count = min(fetch.count, n)
        for i in 0..<count {
            let asset = fetch.object(at: i)
            let d = asset.creationDate.map(Self.fmt) ?? "ไม่ทราบวันที่"
            lines.append("• รูปที่ \(i + 1) — \(d) (\(asset.pixelWidth)x\(asset.pixelHeight))")
        }
        return "รูปล่าสุด \(count) ใบ:\n" + lines.joined(separator: "\n")
    }

    private func takePhoto(question: String) async -> String {
        let result = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            let once = OneShot<String>(cont)
            DispatchQueue.main.async {
                guard let presenter = Self.topViewController() else {
                    once.resume("ไม่พบหน้าต่างของแอป")
                    return
                }
                // ใช้ delegate คนละตัวต่อการเรียก — picker.delegate เป็น weak จึงต้องมีใครถือไว้
                let delegate = PhotoPickerDelegate()
                self.photoDelegate = delegate
                let picker = UIImagePickerController()
                picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
                picker.delegate = delegate
                delegate.completion = { image in
                    guard delegate.completion != nil else { return }
                    delegate.completion = nil
                    self.photoDelegate = nil
                    guard let image else {
                        once.resume("ผู้ใช้ยกเลิกการถ่ายรูป")
                        return
                    }
                    let data = Self.jpegData(from: image, maxDimension: 1400)
                    self.lastImageData = data
                    once.resume("ถ่ายรูปสำเร็จ (base64 \(data?.count ?? 0) bytes)")
                }
                presenter.present(picker, animated: true)
                // กันค้าง ถ้า picker ไม่เปิดหรือถูกปิดเองโดยไม่เรียก delegate
                DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
                    guard delegate.completion != nil else { return }
                    delegate.completion = nil
                    self?.photoDelegate = nil
                    once.resume("ถ่ายรูปไม่สำเร็จ: ไม่ได้รับภาพ")
                }
            }
        }
        return result + (question.isEmpty ? "" : " — คำถาม: \(question)")
    }

    private func ocrImage(question: String) async -> String {
        var data = lastImageData
        if data == nil {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else {
                return "ผู้ใช้ไม่ได้อนุญาตให้เข้าถึงคลังรูป"
            }
            let fetch = PHAsset.fetchAssets(with: .image, options: nil)
            guard fetch.count > 0 else { return "ไม่มีรูปให้อ่าน" }
            let asset = fetch.object(at: 0)
            data = await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                let options = PHImageRequestOptions()
                options.isSynchronous = false
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { d, _, _, _ in
                    cont.resume(returning: d)
                }
            }
        }
        guard let data, let image = UIImage(data: data), let cg = image.cgImage else {
            return "อ่านรูปไม่สำเร็จ (ไม่พบรูป)"
        }
        let text: String
        do {
            text = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                let request = VNRecognizeTextRequest { req, _ in
                    let obs = req.results as? [VNRecognizedTextObservation] ?? []
                    cont.resume(returning: obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["th-TH", "en-US"]
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try handler.perform([request])
                    } catch {
                        // Vision เรียก completion เฉพาะตอน perform สำเร็จ — ต้อง resume เองในกรณี error
                        cont.resume(throwing: error)
                    }
                }
            }
        } catch {
            return "อ่านรูปไม่สำเร็จ: \(error.localizedDescription)"
        }
        if text.isEmpty { return "ไม่พบข้อความในรูป" + (question.isEmpty ? "" : " (คำถาม: \(question))") }
        return "ข้อความในรูป:\n\(text)"
    }

    // MARK: - คลิปบอร์ด / โทร / ข้อความ / แชร์

    private func readClipboard() -> String {
        if UIPasteboard.general.hasStrings {
            return "คลิปบอร์ด: \(UIPasteboard.general.string ?? "")"
        }
        return "คลิปบอร์ดว่างอยู่"
    }

    private func writeClipboard(_ value: String) -> String {
        UIPasteboard.general.string = value
        return "คัดลอกข้อความลงคลิปบอร์ดแล้ว"
    }

    private func makeCall(_ value: String) -> String {
        let number = value.trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty else { return "ไม่ได้ระบุเบอร์" }
        let cleaned = number.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(cleaned)") else { return "เบอร์ไม่ถูกต้อง" }
        Self.openOnMain(url)
        return "เปิดหน้าต่างโทรหา \(cleaned) แล้ว (iOS จะให้ผู้ใช้กดยืนยันการโทร)"
    }

    private func sendMessage(_ value: String) -> String {
        let parts = value.components(separatedBy: "|")
        let number = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let body = parts.count > 1 ? parts[1] : ""
        guard !number.isEmpty else { return "รูปแบบต้องเป็น 'เบอร์|ข้อความ'" }
        var comps = URLComponents()
        comps.scheme = "sms"
        comps.path = number.filter { $0.isNumber || $0 == "+" }
        if !body.isEmpty {
            comps.queryItems = [URLQueryItem(name: "body", value: body)]
        }
        guard let url = comps.url else { return "สร้าง URL ข้อความไม่สำเร็จ" }
        Self.openOnMain(url)
        return "เปิดแอป Messages พร้อมข้อความให้ \(number) แล้ว (ผู้ใช้ต้องกดส่งเอง)"
    }

    private func shareText(_ value: String) -> String {
        DispatchQueue.main.async {
            guard let presenter = Self.topViewController() else { return }
            let items: [Any] = [value]
            let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let pop = vc.popoverPresentationController {
                pop.sourceView = presenter.view
                pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
                pop.permittedArrowDirections = []
            }
            presenter.present(vc, animated: true)
        }
        return "เปิดหน้าต่างแชร์ข้อความแล้ว"
    }

    // MARK: - เครือข่าย

    private func wifiInfo() -> String {
        let monitor = PathMonitor()
        let sem = DispatchSemaphore(value: 0)
        var kind = "ไม่ทราบ"
        monitor.start { path in
            if path.usesInterfaceType(.wifi) { kind = "Wi-Fi" }
            else if path.usesInterfaceType(.cellular) { kind = "เซลลูลาร์" }
            else if path.usesInterfaceType(.wiredEthernet) { kind = "สายแลน" }
            else if path.status == .satisfied { kind = "อื่น ๆ" }
            else { kind = "ไม่มีสัญญาณ" }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 5)
        monitor.stop()
        var ssid = "อ่านชื่อ Wi-Fi ไม่ได้ (ต้องมีสิทธิ์ Access Wi-Fi Information ซึ่งแอปที่ติดตั้งเองจะไม่ได้)"
        if let info = CNCopyCurrentNetworkInfo() as? [String: Any],
           let name = info["SSID"] as? String, !name.isEmpty {
            ssid = name
        }
        return "ประเภทเครือข่าย: \(kind)\nชื่อ Wi-Fi: \(ssid)"
    }

    // MARK: - ตัวช่วย

    static func parseExtra(_ extra: String) -> [String: String] {
        var out: [String: String] = [:]
        for part in extra.components(separatedBy: ",") {
            let kv = part.components(separatedBy: "=")
            if kv.count >= 2 {
                let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = kv.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { out[key] = value }
            }
        }
        return out
    }

    static func parseDate(_ text: String) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "HH:mm", "dd/MM/yyyy HH:mm", "dd MMM yyyy HH:mm"]
        let locale = Locale(identifier: "en_US_POSIX")
        for f in formats {
            let df = DateFormatter()
            df.locale = locale
            df.timeZone = .current
            df.dateFormat = f
            if let d = df.date(from: text.trimmingCharacters(in: .whitespaces)) { return d }
        }
        return nil
    }

    static func fmt(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "th_TH")
        df.dateFormat = "d MMM yyyy เวลา HH:mm"
        return df.string(from: date)
    }

    /// เปิด URL/แอป — ต้องเรียกบน main thread
    static func openOnMain(_ url: URL, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { ok in
                completion?(ok)
            }
        }
    }

    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    static func topViewController() -> UIViewController? {
        var vc = keyWindow()?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }

    static func jpegData(from image: UIImage, maxDimension: CGFloat) -> Data? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.75)
    }
}

// MARK: - ตัวช่วยภายนอก

/// พูดออกเสียง (มีตัวคุมเสียงรวมไว้ที่เดียว)
final class SpeechCenter: @unchecked Sendable {
    static let shared = SpeechCenter()
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "th-TH") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}

/// ขอตำแหน่งครั้งเดียว
final class LocationHelper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocation?) -> Void)?
    private var done = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
        DispatchQueue.main.async {
            let status = self.manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            } else if status == .denied || status == .restricted {
                self.finish(nil)
            } else {
                // ขอสิทธิ์ — จะได้ตำแหน่งใน locationManagerDidChangeAuthorization
                self.manager.requestWhenInUseAuthorization()
            }
        }
        // กันค้างถ้าผู้ใช้ไม่ตอบกล่องขอสิทธิ์
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.finish(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    /// iOS จะขอสิทธิ์ก่อน — ต้องเรียก requestLocation() หลังจากได้รับอนุญาต
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    private func finish(_ location: CLLocation?) {
        guard !done else { return }
        done = true
        completion?(location)
    }
}

/// ตัวเลือกภาพ (กล้อง/อัลบั้ม) — ใช้คนละตัวต่อการเรียก
final class PhotoPickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var completion: ((UIImage?) -> Void)?

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.originalImage] as? UIImage
        picker.dismiss(animated: true) { self.completion?(image) }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { self.completion?(nil) }
    }
}

/// กัน resume ซ้ำของ CheckedContinuation
final class OneShot<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Never>?

    init(_ cont: CheckedContinuation<T, Never>) {
        self.cont = cont
    }

    func resume(_ value: T) {
        lock.lock()
        let c = cont
        cont = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}

/// ตรวจประเภทเครือข่ายแบบครั้งเดียว
final class PathMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "agent.path.monitor")

    func start(_ handler: @escaping (NWPath) -> Void) {
        monitor.pathUpdateHandler = handler
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
