import Foundation

/// รูปแบบ API ที่ผู้ให้บริการรองรับ
enum APIFormat: String {
    case openai      // POST {base}/chat/completions
    case anthropic   // POST {base}/v1/messages
}

struct ModelSpec {
    let id: String
    let name: String
}

struct ProviderSpec {
    let id: String
    let name: String
    let baseURL: String
    let format: APIFormat
    let keyRequired: Bool
    let keyURL: String
    let note: String
    let models: [ModelSpec]
}

enum ProviderCatalog {

    static let all: [ProviderSpec] = [
        ProviderSpec(
            id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", format: .openai,
            keyRequired: true, keyURL: "https://openrouter.ai/keys",
            note: "รวมโมเดลฟรีหลายสิบตัว (id ลงท้าย :free)",
            models: [
                ModelSpec(id: "qwen/qwen3.8-27b:free", name: "Qwen3.8-27B (ฟรี)"),
                ModelSpec(id: "openai/gpt-oss-20b:free", name: "GPT-OSS 20B (ฟรี)"),
                ModelSpec(id: "cohere/north-mini-code:free", name: "North Mini Code (ฟรี)"),
                ModelSpec(id: "z-ai/glm-5.2:free", name: "GLM 5.2 (ฟรี)"),
                ModelSpec(id: "deepseek/deepseek-chat", name: "DeepSeek Chat"),
                ModelSpec(id: "anthropic/claude-sonnet-4.5", name: "Claude Sonnet 4.5"),
                ModelSpec(id: "google/gemini-2.5-flash", name: "Gemini 2.5 Flash"),
                ModelSpec(id: "meta-llama/llama-3.3-70b-instruct:free", name: "Llama 3.3 70B (ฟรี)"),
            ]),

        ProviderSpec(
            id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", format: .openai,
            keyRequired: true, keyURL: "https://platform.openai.com/api-keys",
            note: "ต้องมี API key ของ OpenAI",
            models: [
                ModelSpec(id: "gpt-4o-mini", name: "GPT-4o mini"),
                ModelSpec(id: "gpt-4.1-mini", name: "GPT-4.1 mini"),
                ModelSpec(id: "gpt-4o", name: "GPT-4o"),
                ModelSpec(id: "o4-mini", name: "o4-mini"),
            ]),

        ProviderSpec(
            id: "anthropic", name: "Anthropic (Claude)", baseURL: "https://api.anthropic.com/v1", format: .anthropic,
            keyRequired: true, keyURL: "https://console.anthropic.com/settings/keys",
            note: "ใช้รูปแบบ /v1/messages",
            models: [
                ModelSpec(id: "claude-sonnet-4-5", name: "Claude Sonnet 4.5"),
                ModelSpec(id: "claude-haiku-4-5", name: "Claude Haiku 4.5"),
                ModelSpec(id: "claude-opus-4-1", name: "Claude Opus 4.1"),
            ]),

        ProviderSpec(
            id: "typhoon", name: "Opentyphoon (ไทย)", baseURL: "https://api.opentyphoon.ai/v1", format: .openai,
            keyRequired: true, keyURL: "https://playground.opentyphoon.ai",
            note: "โมเดลไทย และ OCR / ASR ได้",
            models: [
                ModelSpec(id: "typhoon-v2.5-30b-a3b-instruct", name: "Typhoon v2.5 30B"),
                ModelSpec(id: "typhoon-v2.1-12b-instruct", name: "Typhoon v2.1 12B"),
                ModelSpec(id: "typhoon-ocr", name: "Typhoon OCR"),
            ]),

        ProviderSpec(
            id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", format: .openai,
            keyRequired: true, keyURL: "https://console.groq.com/keys",
            note: "เร็วมาก",
            models: [
                ModelSpec(id: "openai/gpt-oss-20b", name: "GPT-OSS 20B"),
                ModelSpec(id: "qwen/qwen3-32b", name: "Qwen3 32B"),
            ]),

        ProviderSpec(
            id: "nvidia", name: "NVIDIA NIM", baseURL: "https://integrate.api.nvidia.com/v1", format: .openai,
            keyRequired: true, keyURL: "https://build.nvidia.com",
            note: "มีโมเดลหลายร้อยตัว รวม OCR/ASR/TTS",
            models: [
                ModelSpec(id: "openai/gpt-oss-120b", name: "GPT-OSS 120B"),
                ModelSpec(id: "moonshotai/kimi-k3", name: "Kimi K3"),
                ModelSpec(id: "z-ai/glm-5.3-flash", name: "GLM 5.3 Flash"),
                ModelSpec(id: "nvidia/nemotron-3-nano-omni-30b", name: "Nemotron Nano Omni (ภาพ+เสียง)"),
                ModelSpec(id: "nvidia/nemotron-3-ocr-v2", name: "Nemotron OCR v2"),
                ModelSpec(id: "meta/llama-3.2-90b-vision-instruct", name: "Llama 3.2 90B Vision"),
            ]),

        ProviderSpec(
            id: "gemini", name: "Google Gemini (OpenAI-compatible)", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", format: .openai,
            keyRequired: true, keyURL: "https://aistudio.google.com/apikey",
            note: "รองรับ tool calling",
            models: [
                ModelSpec(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash"),
                ModelSpec(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro"),
            ]),

        ProviderSpec(
            id: "zai", name: "Z.ai (GLM)", baseURL: "https://api.z.ai/api/paas/v4", format: .openai,
            keyRequired: true, keyURL: "https://z.ai/manage-apikey/apikey-list",
            note: "GLM รุ่นใหม่",
            models: [
                ModelSpec(id: "glm-4.7-flash", name: "GLM 4.7 Flash"),
                ModelSpec(id: "glm-4.6", name: "GLM 4.6"),
            ]),

        ProviderSpec(
            id: "kilo", name: "Kilo (ฟรี ไม่ต้องใช้คีย์)", baseURL: "https://api.kilo.ai/api/gateway", format: .openai,
            keyRequired: false, keyURL: "-",
            note: "โมเดลฟรี ไม่ต้องมี API key",
            models: [
                ModelSpec(id: "poolside/laguna-s-2.1:free", name: "Laguna S 2.1 (ฟรี)"),
                ModelSpec(id: "qwen/qwen3.8-27b:free", name: "Qwen3.8-27B (ฟรี)"),
                ModelSpec(id: "kilo-auto/free", name: "Kilo Auto Router (ฟรี)"),
                ModelSpec(id: "cohere/north-mini-code:free", name: "North Mini Code (ฟรี)"),
                ModelSpec(id: "z-ai/glm-5.2:free", name: "GLM 5.2 (ฟรี)"),
            ]),

        ProviderSpec(
            id: "tokenharbor", name: "TokenHarbor (ฟรี)", baseURL: "https://tokenharbor.ai/v1", format: .openai,
            keyRequired: true, keyURL: "https://tokenharbor.ai",
            note: "มีโมเดลฟรีหลายตัว",
            models: [
                ModelSpec(id: "qwen3.8-flash:free", name: "Qwen3.8 Flash (ฟรี)"),
                ModelSpec(id: "mimo-v2.5:free", name: "MiMo v2.5 (ฟรี)"),
                ModelSpec(id: "deepseek-v4-flash:free", name: "DeepSeek V4 Flash (ฟรี)"),
                ModelSpec(id: "deepseek-v4.1-flash:free", name: "DeepSeek V4.1 Flash (ฟรี)"),
                ModelSpec(id: "th-orchestra", name: "TH Orchestra"),
            ]),

        ProviderSpec(
            id: "nara", name: "NaraRouter", baseURL: "https://router.bynara.id/v1", format: .openai,
            keyRequired: true, keyURL: "https://router.bynara.id",
            note: "ตัวเลือกฟรีหลายตัว",
            models: [
                ModelSpec(id: "auto/bynara", name: "Auto (เลือกอัตโนมัติ)"),
                ModelSpec(id: "agnes-2.5-flash", name: "Agnes 2.5 Flash (ฟรี)"),
                ModelSpec(id: "agnes-3-flash", name: "Agnes 3 Flash (ฟรี)"),
                ModelSpec(id: "poolside/laguna-s-2.1", name: "Laguna S 2.1"),
                ModelSpec(id: "gpt-5.6-luna", name: "GPT-5.6 Luna"),
            ]),

        ProviderSpec(
            id: "pollinations", name: "Pollinations (ฟรี ไม่ต้องใช้คีย์)", baseURL: "https://text.pollinations.ai/openai", format: .openai,
            keyRequired: false, keyURL: "-",
            note: "ฟรี ไม่ต้องมีคีย์",
            models: [
                ModelSpec(id: "openai", name: "GPT-OSS 20B (ฟรี)"),
            ]),

        ProviderSpec(
            id: "ollama", name: "Ollama (ในเครื่อง)", baseURL: "http://localhost:11434/v1", format: .openai,
            keyRequired: false, keyURL: "-",
            note: "ต้องเปิด Ollama ไว้บนคอมแล้วให้มือถือเข้าถึง LAN",
            models: [
                ModelSpec(id: "gpt-oss:20b", name: "GPT-OSS 20B"),
                ModelSpec(id: "qwen3:8b", name: "Qwen3 8B"),
            ]),

        ProviderSpec(
            id: "custom", name: "กำหนดเอง (OpenAI-compatible)", baseURL: "", format: .openai,
            keyRequired: true, keyURL: "-",
            note: "ใส่ Base URL เอง เช่น LiteLLM หรือ proxy ที่คุณทำไว้",
            models: [
                ModelSpec(id: "", name: "พิมพ์ชื่อโมเดลเอง"),
            ]),
    ]

    static func provider(_ id: String) -> ProviderSpec? {
        all.first { $0.id == id }
    }

    static func providersJSON() -> [[String: Any]] {
        all.map { p in
            [
                "id": p.id,
                "name": p.name,
                "baseURL": p.baseURL,
                "format": p.format.rawValue,
                "keyRequired": p.keyRequired,
                "keyURL": p.keyURL,
                "note": p.note,
                "models": p.models.map { ["id": $0.id, "name": $0.name] },
            ]
        }
    }
}

/// ตั้งค่าที่ผู้ใช้เลือก (เก็บบนเครื่อง)
enum ProviderStore {
    private static let selectedKey = "agent.provider"
    private static let modelPrefix = "agent.model."
    private static let customBaseKey = "agent.customBaseURL"

    static var selected: String {
        get { UserDefaults.standard.string(forKey: selectedKey) ?? "openrouter" }
        set { UserDefaults.standard.set(newValue, forKey: selectedKey) }
    }

    static func model(for provider: String) -> String {
        if let saved = UserDefaults.standard.string(forKey: modelPrefix + provider), !saved.isEmpty {
            return saved
        }
        return ProviderCatalog.provider(provider)?.models.first?.id ?? ""
    }

    static func setModel(_ model: String, for provider: String) {
        UserDefaults.standard.set(model, forKey: modelPrefix + provider)
    }

    static var customBaseURL: String {
        get { UserDefaults.standard.string(forKey: customBaseKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: customBaseKey) }
    }

    /// API key ของแต่ละผู้ให้บริการเก็บใน Keychain แยกกัน
    static func key(for provider: String) -> String {
        KeychainStore.get(account: "agent.key.\(provider)") ?? ""
    }

    static func setKey(_ key: String, for provider: String) {
        if key.isEmpty {
            KeychainStore.remove(account: "agent.key.\(provider)")
        } else {
            KeychainStore.set(key, account: "agent.key.\(provider)")
        }
    }

    /// ประกอบค่าที่ใช้ติดต่อ API จริง
    static func resolve(_ providerID: String) -> (spec: ProviderSpec, baseURL: String, apiKey: String, model: String)? {
        guard let spec = ProviderCatalog.provider(providerID) else { return nil }
        var base = spec.baseURL
        if providerID == "custom" { base = customBaseURL }
        let key = key(for: providerID).isEmpty ? (spec.keyRequired ? "" : "free") : key(for: providerID)
        let model = model(for: providerID).isEmpty ? (spec.models.first?.id ?? "") : model(for: providerID)
        return (spec, base, key, model)
    }
}
