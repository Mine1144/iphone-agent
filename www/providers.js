/* รายการผู้ให้บริการ AI — ใช้ทั้งตอนอยู่ในแอป (native) และตอนเปิดเป็นเว็บ (PWA)
   format: "openai" = POST {base}/chat/completions | "anthropic" = POST {base}/v1/messages */
window.PROVIDERS = [
  { id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", format: "openai",
    keyRequired: true, keyURL: "https://openrouter.ai/keys", note: "โมเดลฟรีเยอะ (id ลงท้าย :free)",
    models: [
      { id: "qwen/qwen3.8-27b:free", name: "Qwen3.8-27B (ฟรี)" },
      { id: "openai/gpt-oss-20b:free", name: "GPT-OSS 20B (ฟรี)" },
      { id: "cohere/north-mini-code:free", name: "North Mini Code (ฟรี)" },
      { id: "z-ai/glm-5.2:free", name: "GLM 5.2 (ฟรี)" },
      { id: "meta-llama/llama-3.3-70b-instruct:free", name: "Llama 3.3 70B (ฟรี)" },
      { id: "deepseek/deepseek-chat", name: "DeepSeek Chat" },
      { id: "google/gemini-2.5-flash", name: "Gemini 2.5 Flash" },
      { id: "anthropic/claude-sonnet-4.5", name: "Claude Sonnet 4.5" },
    ] },
  { id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", format: "openai",
    keyRequired: true, keyURL: "https://platform.openai.com/api-keys", note: "ต้องมี API key",
    models: [
      { id: "gpt-4o-mini", name: "GPT-4o mini" },
      { id: "gpt-4.1-mini", name: "GPT-4.1 mini" },
      { id: "gpt-4o", name: "GPT-4o" },
    ] },
  { id: "anthropic", name: "Anthropic (Claude)", baseURL: "https://api.anthropic.com/v1", format: "anthropic",
    keyRequired: true, keyURL: "https://console.anthropic.com/settings/keys", note: "ใช้ /v1/messages",
    models: [
      { id: "claude-sonnet-4-5", name: "Claude Sonnet 4.5" },
      { id: "claude-haiku-4-5", name: "Claude Haiku 4.5" },
    ] },
  { id: "typhoon", name: "Opentyphoon (ไทย)", baseURL: "https://api.opentyphoon.ai/v1", format: "openai",
    keyRequired: true, keyURL: "https://playground.opentyphoon.ai", note: "โมเดลไทย อ่านรูป/เสียงได้",
    models: [
      { id: "typhoon-v2.5-30b-a3b-instruct", name: "Typhoon v2.5 30B" },
      { id: "typhoon-v2.1-12b-instruct", name: "Typhoon v2.1 12B" },
    ] },
  { id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", format: "openai",
    keyRequired: true, keyURL: "https://console.groq.com/keys", note: "เร็วมาก",
    models: [
      { id: "openai/gpt-oss-20b", name: "GPT-OSS 20B" },
      { id: "qwen/qwen3-32b", name: "Qwen3 32B" },
    ] },
  { id: "nvidia", name: "NVIDIA NIM", baseURL: "https://integrate.api.nvidia.com/v1", format: "openai",
    keyRequired: true, keyURL: "https://build.nvidia.com", note: "มีโมเดลหลายร้อยตัว",
    models: [
      { id: "openai/gpt-oss-120b", name: "GPT-OSS 120B" },
      { id: "moonshotai/kimi-k3", name: "Kimi K3" },
      { id: "z-ai/glm-5.3-flash", name: "GLM 5.3 Flash" },
      { id: "meta/llama-3.2-90b-vision-instruct", name: "Llama 3.2 90B Vision" },
    ] },
  { id: "gemini", name: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", format: "openai",
    keyRequired: true, keyURL: "https://aistudio.google.com/apikey", note: "เร็ว มี free tier",
    models: [
      { id: "gemini-2.5-flash", name: "Gemini 2.5 Flash" },
      { id: "gemini-2.5-pro", name: "Gemini 2.5 Pro" },
    ] },
  { id: "zai", name: "Z.ai (GLM)", baseURL: "https://api.z.ai/api/paas/v4", format: "openai",
    keyRequired: true, keyURL: "https://z.ai/manage-apikey/apikey-list", note: "GLM รุ่นใหม่",
    models: [
      { id: "glm-4.7-flash", name: "GLM 4.7 Flash" },
      { id: "glm-4.6", name: "GLM 4.6" },
    ] },
  { id: "kilo", name: "Kilo (ฟรี ไม่ต้องใช้คีย์)", baseURL: "https://api.kilo.ai/api/gateway", format: "openai",
    keyRequired: false, keyURL: "-", note: "โมเดลฟรี ไม่ต้องมี API key",
    models: [
      { id: "poolside/laguna-s-2.1:free", name: "Laguna S 2.1 (ฟรี)" },
      { id: "qwen/qwen3.8-27b:free", name: "Qwen3.8-27B (ฟรี)" },
      { id: "kilo-auto/free", name: "Kilo Auto Router (ฟรี)" },
      { id: "cohere/north-mini-code:free", name: "North Mini Code (ฟรี)" },
      { id: "z-ai/glm-5.2:free", name: "GLM 5.2 (ฟรี)" },
    ] },
  { id: "tokenharbor", name: "TokenHarbor (ฟรี)", baseURL: "https://tokenharbor.ai/v1", format: "openai",
    keyRequired: true, keyURL: "https://tokenharbor.ai", note: "มีโมเดลฟรีหลายตัว",
    models: [
      { id: "qwen3.8-flash:free", name: "Qwen3.8 Flash (ฟรี)" },
      { id: "mimo-v2.5:free", name: "MiMo v2.5 (ฟรี)" },
      { id: "deepseek-v4-flash:free", name: "DeepSeek V4 Flash (ฟรี)" },
      { id: "th-orchestra", name: "TH Orchestra" },
    ] },
  { id: "nara", name: "NaraRouter", baseURL: "https://router.bynara.id/v1", format: "openai",
    keyRequired: true, keyURL: "https://router.bynara.id", note: "ตัวเลือกฟรีหลายตัว",
    models: [
      { id: "auto/bynara", name: "Auto (อัตโนมัติ)" },
      { id: "agnes-2.5-flash", name: "Agnes 2.5 Flash (ฟรี)" },
      { id: "agnes-3-flash", name: "Agnes 3 Flash (ฟรี)" },
    ] },
  { id: "pollinations", name: "Pollinations (ฟรี ไม่ต้องใช้คีย์)", baseURL: "https://text.pollinations.ai/openai", format: "openai",
    keyRequired: false, keyURL: "-", note: "ฟรี ไม่ต้องมีคีย์",
    models: [ { id: "openai", name: "GPT-OSS 20B (ฟรี)" } ] },
  { id: "ollama", name: "Ollama (ในเครื่อง)", baseURL: "http://localhost:11434/v1", format: "openai",
    keyRequired: false, keyURL: "-", note: "ต้องเปิด Ollama ไว้บนคอม",
    models: [
      { id: "gpt-oss:20b", name: "GPT-OSS 20B" },
      { id: "qwen3:8b", name: "Qwen3 8B" },
    ] },
  { id: "custom", name: "กำหนดเอง", baseURL: "", format: "openai",
    keyRequired: true, keyURL: "-", note: "ใส่ Base URL เอง (เช่น LiteLLM/proxy ที่คุณทำไว้)",
    models: [ { id: "", name: "พิมพ์ชื่อโมเดลเอง" } ] },
];

window.AGENT_INSTRUCTIONS = `คุณเป็นผู้ช่วย AI ที่ควบคุม iPhone ของผู้ใช้ได้จริง ๆ ผ่านเครื่องมือที่ให้มา

กฎสำคัญ:
1. ตอบภาษาไทยเสมอ
2. ถ้าต้องทำอะไรกับเครื่องหรือข้อมูลส่วนตัว ให้เรียกเครื่องมือจริง อย่าแค่บอกวิธีทำ
3. เรียกเครื่องมือทีละอัน แล้วดูผลลัพธ์ก่อนตัดสินใจขั้นต่อไป
4. ตอบสั้นกระชับเหมือนผู้ช่วยในแอป ไม่ต้องเขียนยาว`;
