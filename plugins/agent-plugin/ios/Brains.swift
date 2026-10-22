import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// ช่องทางส่ง event กลับไปที่ UI
protocol BrainEvents: AnyObject {
    func emit(_ type: String, _ data: [String: Any])
}

/// คำสั่งระบบให้เอเจนต์ทำงานเป็น "ผู้คุมเครื่อง iPhone"
let agentInstructions = """
คุณเป็นผู้ช่วย AI ที่ควบคุม iPhone ของผู้ใช้ได้จริง ๆ ผ่านเครื่องมือที่ให้มา

กฎสำคัญ:
1. ตอบภาษาไทยเสมอ (เว้นแต่ผู้ใช้เขียนภาษาอื่น)
2. ถ้าต้องทำอะไรกับเครื่องหรือข้อมูลส่วนตัว ให้เรียกเครื่องมือจริง อย่าแค่บอกวิธีทำ
3. เรียกเครื่องมือทีละอัน แล้วดูผลลัพธ์ก่อนตัดสินใจขั้นต่อไป
4. ถ้าเครื่องมือล้มเหลวหรือผู้ใช้ปฏิเสธ ให้อธิบายสั้น ๆ ว่าทำอะไรไม่ได้ และเสนอทางเลือก
5. ตอบสั้นกระชับเหมือนผู้ช่วยในแอป ไม่ต้องเขียนยาว ไม่ต้องอธิบายว่าคุณใช้เครื่องมืออะไร
6. ถ้าผู้ใช้สั่งงานที่กระทบเงิน/สิทธิ/การติดต่อผู้อื่น ให้ใช้เครื่องมือที่ระบุว่า sensitive — ระบบจะถามผู้ใช้ยืนยันเอง
"""

// MARK: - สมองบนเครื่อง (Apple Foundation Models)

#if canImport(FoundationModels)

@available(iOS 26.0, *)
struct PhoneTool: Tool {
    let name: String
    let description: String
    let tools: DeviceTools
    let onEvent: @Sendable (String, [String: Any]) -> Void

    @Generable
    struct Arguments {
        @Guide(description: "ค่าที่ต้องการสั่งให้เครื่องมือทำ เช่น ชื่อแอป เบอร์โทร ข้อความ หรือตัวเลข")
        var value: String

        @Guide(description: "รายละเอียดเพิ่มเติมในรูปแบบ key=value, key2=value2 (ถ้าไม่มีใส่ว่างไว้)")
        var extra: String?
    }

    func call(arguments: Arguments) async throws -> String {
        onEvent("tool", [
            "name": name,
            "value": arguments.value,
            "extra": arguments.extra ?? "",
        ])
        let result = try await tools.run(name: name, value: arguments.value, extra: arguments.extra)
        onEvent("tool_result", [
            "name": name,
            "ok": true,
            "result": String(result.prefix(600)),
        ])
        return result
    }
}

@available(iOS 26.0, *)
final class OnDeviceBrain {

    private var session: LanguageModelSession?
    private let tools: DeviceTools
    private let events: BrainEvents

    init(tools: DeviceTools, events: BrainEvents) {
        self.tools = tools
        self.events = events
    }

    /// ตรวจว่าเครื่องรองรับโมเดลบนเครื่องหรือไม่
    static func availability() -> [String: Any] {
        let model = SystemLanguageModel.default
        let desc = String(describing: model.availability).lowercased()
        let available = desc.contains("available") && !desc.contains("unavailable")
        return [
            "available": available,
            "status": String(describing: model.availability),
            "note": available
                ? "พร้อมใช้งานโมเดลบนเครื่อง"
                : "เครื่องนี้ไม่รองรับโมเดลบนเครื่อง (ต้องเป็น iPhone 15 Pro ขึ้นไป + iOS 26) — ใช้โมเดลคลาวด์แทน",
        ]
    }

    func start() throws {
        let toolList: [any Tool] = ToolCatalog.specs.map { spec in
            PhoneTool(
                name: spec.name,
                description: "\(spec.summary) | วิธีใช้: \(spec.usage)",
                tools: tools,
                onEvent: { [weak events] type, data in
                    events?.emit(type, data)
                }
            )
        }
        session = LanguageModelSession(tools: toolList, instructions: agentInstructions)
        events.emit("status", ["state": "ready", "detail": "สมองบนเครื่องพร้อมใช้งาน"])
    }

    func respond(to text: String) async throws -> String {
        if session == nil { try start() }
        guard let session else {
            throw NSError(domain: "Agent", code: 1, userInfo: [NSLocalizedDescriptionKey: "เซสชันไม่พร้อมใช้งาน"])
        }
        events.emit("status", ["state": "thinking", "detail": "กำลังคิด…"])
        let response = try await session.respond(to: text)
        let content = response.content
        events.emit("status", ["state": "idle"])
        return content
    }

    func reset() {
        session = nil
    }
}

#endif

// MARK: - สมองคลาวด์ (รองรับ OpenAI-compatible และ Anthropic)

final class CloudBrain {

    /// ข้อความภายในที่แปลงตามรูปแบบ API ตอนส่ง
    private enum Turn {
        case user(String)
        case assistantText(String)
        case assistantToolCalls([(id: String, name: String, input: [String: Any])])
        case toolResult(id: String, name: String, content: String)
    }

    private let spec: ProviderSpec
    private let format: APIFormat
    private let baseURL: String
    private let apiKey: String
    private let model: String
    private let tools: DeviceTools
    private let events: BrainEvents

    private var turns: [Turn] = []
    private var isRunning = false

    init(spec: ProviderSpec, format: APIFormat? = nil, baseURL: String, apiKey: String, model: String, tools: DeviceTools, events: BrainEvents) {
        self.spec = spec
        self.format = format ?? spec.format
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.apiKey = apiKey
        self.model = model
        self.tools = tools
        self.events = events
    }

    func reset() {
        turns.removeAll()
    }

    // MARK: รูปแบบเครื่องมือ

    private var openAITools: [[String: Any]] {
        ToolCatalog.specs.map { spec in
            [
                "type": "function",
                "function": [
                    "name": spec.name,
                    "description": "\(spec.summary) | วิธีใช้: \(spec.usage)",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "value": ["type": "string", "description": spec.usage],
                            "extra": ["type": "string", "description": "รายละเอียดเพิ่มเติม key=value, key2=value2"],
                        ],
                        "required": ["value"],
                    ],
                ],
            ]
        }
    }

    private var anthropicTools: [[String: Any]] {
        ToolCatalog.specs.map { spec in
            [
                "name": spec.name,
                "description": "\(spec.summary) | วิธีใช้: \(spec.usage)",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "value": ["type": "string", "description": spec.usage],
                        "extra": ["type": "string", "description": "รายละเอียดเพิ่มเติม key=value, key2=value2"],
                    ],
                    "required": ["value"],
                ],
            ]
        }
    }

    // MARK: วน loop: โมเดลเรียกเครื่องมือ → รันบนเครื่อง → ส่งผลกลับ → โมเดลสรุป

    func respond(to text: String) async throws -> String {
        guard !isRunning else {
            throw NSError(domain: "Agent", code: 2, userInfo: [NSLocalizedDescriptionKey: "กำลังทำงานอยู่"])
        }
        isRunning = true
        defer { isRunning = false }

        turns.append(.user(text))

        var finalText = ""
        for _ in 0..<8 {
            let reply = try await callAPI(toolsAllowed: turns.count < 12)
            if let calls = reply.toolCalls, !calls.isEmpty {
                turns.append(.assistantToolCalls(calls))
                for call in calls {
                    events.emit("tool", [
                        "name": call.name,
                        "value": call.arguments["value"] ?? "",
                        "extra": call.arguments["extra"] ?? "",
                    ])
                    let result = (try? await tools.run(name: call.name,
                                                      value: (call.arguments["value"] as? String) ?? "",
                                                      extra: call.arguments["extra"] as? String)) ?? "เครื่องมือล้มเหลว"
                    events.emit("tool_result", [
                        "name": call.name,
                        "ok": true,
                        "result": String(result.prefix(600)),
                    ])
                    turns.append(.toolResult(id: call.id, name: call.name, content: result))
                }
                continue
            }
            finalText = reply.content
            break
        }

        if !finalText.isEmpty { turns.append(.assistantText(finalText)) }
        if turns.count > 30 { turns.removeFirst(turns.count - 30) }
        events.emit("status", ["state": "idle"])
        return finalText
    }

    private struct ToolCall {
        let id: String
        let name: String
        let arguments: [String: Any]
    }

    private struct Reply {
        var content: String = ""
        var toolCalls: [ToolCall]?
    }

    // MARK: ยิง API

    private func callAPI(toolsAllowed: Bool) async throws -> Reply {
        switch format {
        case .openai: return try await callOpenAI(toolsAllowed: toolsAllowed)
        case .anthropic: return try await callAnthropic(toolsAllowed: toolsAllowed)
        }
    }

    private func callOpenAI(toolsAllowed: Bool) async throws -> Reply {
        var messages: [[String: Any]] = [["role": "system", "content": agentInstructions]]
        for turn in turns {
            switch turn {
            case .user(let t):
                messages.append(["role": "user", "content": t])
            case .assistantText(let t):
                messages.append(["role": "assistant", "content": t])
            case .assistantToolCalls(let calls):
                let list: [[String: Any]] = calls.map { c in
                    [
                        "id": c.id,
                        "type": "function",
                        "function": [
                            "name": c.name,
                            "arguments": (try? JSONSerialization.data(withJSONObject: c.input))
                                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}",
                        ],
                    ]
                }
                messages.append(["role": "assistant", "content": NSNull(), "tool_calls": list])
            case .toolResult(let id, let name, let content):
                messages.append(["role": "tool", "tool_call_id": id, "name": name, "content": content])
            }
        }

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.4,
            "stream": false,
        ]
        if toolsAllowed { body["tools"] = openAITools; body["tool_choice"] = "auto" }

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw NSError(domain: "Agent", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Base URL ไม่ถูกต้อง: \(baseURL)",
            ])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        if spec.id == "openrouter" {
            request.setValue("https://github.com/natee/iphone-agent", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("iPhone Agent", forHTTPHeaderField: "X-Title")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] ?? [:]
        var reply = Reply()
        reply.content = (message["content"] as? String) ?? ""
        if let calls = message["tool_calls"] as? [[String: Any]] {
            reply.toolCalls = calls.compactMap { call in
                guard let fn = call["function"] as? [String: Any], let name = fn["name"] as? String else { return nil }
                var args: [String: Any] = [:]
                if let raw = fn["arguments"] as? String, let d = raw.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    args = obj
                }
                return ToolCall(id: (call["id"] as? String) ?? UUID().uuidString, name: name, arguments: args)
            }
        }
        return reply
    }

    private func callAnthropic(toolsAllowed: Bool) async throws -> Reply {
        var messages: [[String: Any]] = []
        for turn in turns {
            switch turn {
            case .user(let t):
                messages.append(["role": "user", "content": [[type: "text", text: t]]])
            case .assistantText(let t):
                messages.append(["role": "assistant", "content": [[type: "text", text: t]]])
            case .assistantToolCalls(let calls):
                let blocks: [[String: Any]] = calls.map { c in
                    ["type": "tool_use", "id": c.id, "name": c.name, "input": c.input]
                }
                messages.append(["role": "assistant", "content": blocks])
            case .toolResult(let id, _, let content):
                messages.append([
                    "role": "user",
                    "content": [["type": "tool_result", "tool_use_id": id, "content": content]],
                ])
            }
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": agentInstructions,
            "messages": messages,
        ]
        if toolsAllowed { body["tools"] = anthropicTools }

        let url = baseURL.hasSuffix("/v1") ? "\(baseURL)/messages" : "\(baseURL)/v1/messages"
        guard let endpoint = URL(string: url) else {
            throw NSError(domain: "Agent", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Base URL ไม่ถูกต้อง: \(baseURL)",
            ])
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var reply = Reply()
        let blocks = json["content"] as? [[String: Any]] ?? []
        var texts: [String] = []
        var calls: [ToolCall] = []
        for block in blocks {
            if block["type"] as? String == "text", let t = block["text"] as? String {
                texts.append(t)
            } else if block["type"] as? String == "tool_use",
                      let name = block["name"] as? String {
                calls.append(ToolCall(
                    id: (block["id"] as? String) ?? UUID().uuidString,
                    name: name,
                    arguments: (block["input"] as? [String: Any]) ?? [:]
                ))
            }
        }
        reply.content = texts.joined()
        if !calls.isEmpty { reply.toolCalls = calls }
        return reply
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Agent", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "API \(http.statusCode): \(String(text.prefix(240)))",
            ])
        }
    }
}
