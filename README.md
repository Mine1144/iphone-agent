# ผู้ช่วย iPhone (iPhone Agent)

**AI Agent ที่รันอยู่บน iPhone และควบคุม iPhone ได้จริง** — ไม่ต้องใช้คอมเลย
สมองมี 2 แบบ (สลับได้ตลอด) และคุยกับผู้ให้บริการ AI ได้หลายเจ้า

| สมอง | ข้อดี | ข้อจำกัด |
|---|---|---|
| **บนเครื่อง** (Apple Foundation Models) | เร็ว ไม่ต้องเน็ต ไม่ส่งข้อมูลออกเครื่อง | ต้อง iOS 26 + iPhone 15 Pro ขึ้นไป — โมเดลเล็ก คิดลึกไม่ได้เท่าโมเดลใหญ่ |
| **คลาวด์** (OpenRouter / OpenAI / Anthropic / Groq / NVIDIA / Typhoon / Kilo / TokenHarbor / Nara / Ollama / กำหนดเอง) | ฉลาดกว่า เร็วกว่า รองรับ tool calling เต็มรูปแบบ | ต้องมีเน็ต + API key (บางเจ้าไม่ต้องใช้คีย์) |

---

## 1. สถาปัตยกรรม

```
┌──────────────── iPhone (แอปนี้) ────────────────┐
│  UI (www/)  แชท · การ์ดเครื่องมือ · ขออนุมัติ      │
│        ↕  Capacitor                              │
│  plugins/agent-plugin (Swift)                    │
│    ├─ OnDeviceBrain  (FoundationModels + tools)  │
│    ├─ CloudBrain     (OpenAI / Anthropic format) │
│    └─ DeviceTools    (คุมเครื่องจริง 27 ตัว)      │
└──────────────────────────────────────────────────┘
```

- **เครื่องมือฝั่งสมอง** = เรียกผ่าน Foundation Models `Tool` protocol (บนเครื่อง) หรือ function-calling (คลาวด์)
- **เครื่องมือฝั่งเครื่อง** = Swift ทำงานจริงบน iOS (EventKit, CoreLocation, Photos, Contacts, AVFoundation, UIPasteboard, Shortcuts …)
- **การอนุมัติ**: เครื่องมือที่เสี่ยง (โทร ส่งข้อความ เรียก Shortcut) จะขึ้นการ์ดให้ผู้ใช้กดอนุมัติก่อนเสมอ
- **คีย์ API** เก็บใน **Keychain** ของเครื่อง ไม่ใช่ไฟล์ธรรมดา

---

## 2. เครื่องมือที่ควบคุม iPhone ได้ (25 ตัว)

| กลุ่ม | เครื่องมือ |
|---|---|
| ข้อมูลเครื่อง | `device_info` `wifi_info` |
| จอ/เสียง | `set_volume` `set_brightness` `speak` `stop_speak` |
| เปิดแอป/เว็บ | `open_app` `open_url` `search_web` |
| **Shortcut** | `run_shortcut` `list_shortcuts` |
| งานประจำวัน | `set_reminder` `list_reminders` `add_calendar` `list_calendar` |
| รูปภาพ | `take_photo` `ocr_image` `list_photos` |
| ติดต่อ/สื่อสาร | `search_contacts` `make_call` `send_message` `share_text` |
| อื่น ๆ | `get_location` `read_clipboard` `write_clipboard` |

`run_shortcut` คือหัวใจของการ "คุมทั้งเครื่อง" — เชื่อมไปยัง Shortcut ที่ผู้ใช้สร้างไว้
(เช่น เปิดไฟ, สั่งรถ, เปิดแอปใดก็ได้, โพสต์โซเชียล) เพราะ Shortcut เป็นช่องทางที่ Apple อนุญาตให้แอป
ควบคุมความสามารถของแอปอื่นอย่างเป็นทางการ

---

## 3. ข้อจำกัดของ iOS (อ่านก่อนใช้ — สำคัญ)

1. **iOS ไม่มี API ให้แอปไปควบคุม UI ของแอปอื่น** (เหมือน Accessibility ของ Android ที่แอปอื่นใช้ tap ได้)
   → การคุมแอปอื่นต้องผ่าน **Shortcut / App Intents / URL scheme** ซึ่งบางอย่าง iOS จะถามยืนยันผู้ใช้
2. **สมองบนเครื่อง** ต้องเป็น iOS 26 + ชิป A17 Pro ขึ้นไป (iPhone 15 Pro/16/17) — เครื่องรุ่นเก่าต้องใช้โมเดลคลาวด์
3. **ชื่อ SSID ของ Wi-Fi** อ่านไม่ได้ ถ้าแอปไม่มี entitlement *Access Wi-Fi Information* (แอปที่ติดตั้งเองจะไม่มี)
4. **เปิด/ปิด Wi-Fi, Bluetooth, AirDrop, ลบแอป, ตั้งค่าระบบ** ทำเองไม่ได้ (ต้องผ่าน Shortcut หรือ MDM)
5. การอ่านคลิปบอร์ดของแอปอื่น iOS 16+ จะขึ้นขออนุญาต
6. `list_shortcuts` **อ่านรายชื่อ Shortcut ไม่ได้** (Apple ไม่เปิด API) — ให้ผู้ใช้บอกชื่อเองแล้วเรียกผ่าน `run_shortcut`

---

## 4. วิธีติดตั้ง (ทำบน Windows ได้ ไม่ต้องมี Mac)

### 4.1 แบบ PWA — ใช้ได้เลย ไม่ต้อง build

```powershell
cd "C:\Users\natee\OneDrive\เอกสาร\Default Project\iphone-agent"
npm install
npx http-server www -p 5173 -c-1
```

เปิด `http://<ip-คอม>:5173` บน iPhone (ต้องอยู่ LAN เดียวกัน) → Safari → **แชร์ → เพิ่มไปยังหน้าจอโฮม**
→ ได้แอปเต็มจอแบบ PWA

> โหมดนี้คุยกับ API ได้ครบ แต่**เครื่องมือคุมเครื่องจะจำกัด** (เว็บเปิด URL/ค้นเว็บ/พูด/คลิปบอร์ด/แชร์)
> เครื่องมือเต็ม (Reminder, ปฏิทิน, กล้อง, OCR, Shortcut …) ต้องติดตั้งเป็นแอป

### 4.2 แบบแอป native — ได้เครื่องมือครบ

**✅ ไฟล์ .ipa พร้อมแล้ว** → `iphone-agent/dist/iPhoneAgent-unsigned.ipa` (782 KB, arm64, minOS 26.0)

ติดตั้ง:
1. **LiveContainer** → Settings → Import Certificate from AltStore/SideStore → เลือกไฟล์ `.ipa` → กด **+** เพื่อเพิ่มแอป
2. **SideStore/AltStore** → กด + → เลือกไฟล์ `.ipa` → รอ re-sign
3. เปิดแอป **iPhoneAgent** → ⚙︎ → เลือกผู้ให้บริการ AI (เช่น Pollinations = ไม่ต้องใช้คีย์) → คุยได้เลย

**สร้าง .ipa ใหม่เอง (คำสั่งเดียว):**

```powershell
cd "C:\Users\natee\OneDrive\เอกสาร\Default Project"
powershell -ExecutionPolicy Bypass -File tools\push-build.ps1 iphone-agent
```

→ commit & push → สั่ง build ที่ Codemagic (macOS runner) → รอ → ดาวน์โหลด `.ipa` กลับมาไว้ใน `iphone-agent/dist/`
(ต้องมี `tools\.gh-token` และ `tools\.codemagic-key` — เก็บ token ไว้ในเครื่อง ไม่ได้อยู่ใน repo)

**ถ้าอยากใช้ GitHub Actions แทน** (workflow พร้อมแล้วใน `.github/workflows/`):
ต้องแก้บัญชีก่อน — Settings → Billing and licensing → Budgets and alerts → ลบ/เพิ่ม budget ของ **Actions**
ที่เป็น `$0.00 · 100% Usage blocked` (GitHub ต้องการ payment method จึงจะแก้ได้) แล้ว build ได้ผ่าน `build-ios-ipa.yml`

> runner คือ macos-26 (Xcode 26) — โปรเจกต์ตั้ง deployment target เป็น **iOS 26.0**

### 4.3 ถ้ามี Mac

```bash
npm install && npx cap sync ios && npx cap open ios
# Xcode → Product → Archive → Distribute App → Debugging (Any iOS Device)
```

---

## 5. ผู้ให้บริการ AI ที่ใช้ได้

เปิดในแอป → ⚙︎ → เลือกผู้ให้บริการ + โมเดล + ใส่คีย์

| ผู้ให้บริการ | baseURL | format | คีย์ |
|---|---|---|---|
| OpenRouter | `https://openrouter.ai/api/v1` | OpenAI | ต้องใช้ (มีโมเดล `:free` หลายตัว) |
| OpenAI | `https://api.openai.com/v1` | OpenAI | ต้องใช้ |
| Anthropic | `https://api.anthropic.com/v1` | **Anthropic** | ต้องใช้ |
| Opentyphoon | `https://api.opentyphoon.ai/v1` | OpenAI | ต้องใช้ (โมเดลไทย) |
| Groq | `https://api.groq.com/openai/v1` | OpenAI | ต้องใช้ |
| NVIDIA NIM | `https://integrate.api.nvidia.com/v1` | OpenAI | ต้องใช้ |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | OpenAI | ต้องใช้ |
| Z.ai (GLM) | `https://api.z.ai/api/paas/v4` | OpenAI | ต้องใช้ |
| Kilo | `https://api.kilo.ai/api/gateway` | OpenAI | **ไม่ต้องใช้** |
| TokenHarbor | `https://tokenharbor.ai/v1` | OpenAI | ต้องใช้ |
| NaraRouter | `https://router.bynara.id/v1` | OpenAI | ต้องใช้ |
| Pollinations | `https://text.pollinations.ai/openai` | OpenAI | **ไม่ต้องใช้** |
| Ollama (บนคอม) | `http://<ip-คอม>:11434/v1` | OpenAI | ไม่ต้องใช้ |
| กำหนดเอง | ใส่เอง | OpenAI | ตามต้องการ |

รองรับทั้ง **OpenAI-compatible** (`/chat/completions`) และ **Anthropic** (`/v1/messages`) — เช่นถ้าคุณมี
LiteLLM proxy อยู่ที่ `http://127.0.0.1:4000` ให้เลือก "กำหนดเอง" แล้วใส่ URL นั้น

> โหมด "กำหนดเอง" ยังใช้ **โมเดลคลาวด์บนมือถือ** เท่านั้น — ถ้าอยากให้มือถือเรียก proxy บนคอม
> ให้เปิด `http://<ip-คอม>:4000` (ต้อง bind 0.0.0.0 + อนุญาต firewall)

---

## 6. ตัวอย่างคำสั่ง

- "ตั้งเตือนความจำว่าไปซื้อข้าวพรุ่งนี้ตอน 7 โมง"
- "เปิด YouTube"
- "ค้นเว็บว่าอากาศวันนี้เป็นยังไง"
- "ผมอยู่ตรงไหน"
- "อ่านข้อความในรูปนี้ให้หน่อย"
- "เพิ่มนัดหมาย 'ประชุม' พรุ่งนี้ 10:00 น. 1 ชั่วโมง"
- "สั่ง Shortcut 'เปิดไฟ' ด้วย input 'ห้องนอน'"
- "โทรหา 081-234-5678" → ระบบจะขออนุมัติก่อน
- "ลดเสียงลง 30%"

---

## 7. โครงสร้างโค้ด

```
iphone-agent/
├── www/                     UI (มือถือ-first) + PWA
│   ├── index.html  app.js  style.css
│   ├── providers.js         รายการผู้ให้บริการ AI
│   └── tools.web.js         เครื่องมือเวอร์ชัน PWA
├── plugins/agent-plugin/ios/
│   ├── AgentPlugin.swift    จุดเข้า Capacitor + Keychain + dictation
│   ├── Brains.swift         OnDeviceBrain (FoundationModels) + CloudBrain
│   ├── DeviceTools.swift    เครื่องมือควบคุม iPhone 25 ตัว
│   ├── ToolCatalog.swift    ข้อมูลเครื่องมือ + ระดับความเสี่ยง
│   └── Providers.swift      ตั้งค่าผู้ให้บริการ (UserDefaults + Keychain)
└── .github/workflows/       build .ipa อัตโนมัติ
```

### เพิ่มเครื่องมือใหม่

1. เพิ่มรายการใน `ToolCatalog.swift` (name, summary, usage, risk)
2. เพิ่ม `case "ชื่อเครื่องมือ":` ใน `DeviceTools.run()`
3. (ถ้าใช้กับ PWA ด้วย) เพิ่มใน `www/tools.web.js`
4. `npx cap sync ios` แล้ว build ใหม่

---

## 8. ทดสอบ

```powershell
node tmp\mock-agent-server.mjs     # เสิร์ฟ www/ + API จำลอง (ตอบแบบมี tool call)
# เปิด http://127.0.0.1:5173
```
