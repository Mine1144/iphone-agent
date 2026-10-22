import Foundation

/// ข้อมูลเครื่องมือทุกตัวที่เอเจนต์เรียกใช้ได้ (catalog เดียว ใช้ทั้ง UI และ native)
enum ToolRisk: String {
    case safe      // อ่านอย่างเดียว ไม่เปลี่ยนอะไร
    case normal    // เปลี่ยนแปลงที่ย้อนกลับได้
    case sensitive // ต้องให้ผู้ใช้กดอนุมัติก่อน
}

struct ToolSpec {
    let name: String
    let summary: String        // คำอธิบายสั้นสำหรับโมเดล
    let usage: String          // วิธีใช้/รูปแบบค่า
    let risk: ToolRisk
    let permission: String?    // สิทธิ์ที่ต้องขอจากผู้ใช้
    let icon: String
}

enum ToolCatalog {

    static let specs: [ToolSpec] = [
        ToolSpec(name: "device_info",
                 summary: "ข้อมูลเครื่อง: รุ่น, เวอร์ชัน iOS, แบต, พื้นที่จัดเก็บ, หน่วยความจำ",
                 usage: "ไม่ต้องใส่ค่า",
                 risk: .safe, permission: nil, icon: "📱"),

        ToolSpec(name: "set_volume",
                 summary: "ปรับระดับเสียงของเครื่อง และ/หรือปิดเสียง",
                 usage: "value = ระดับ 0.0-1.0 (เช่น 0.3) หรือ 'mute'",
                 risk: .normal, permission: nil, icon: "🔊"),

        ToolSpec(name: "set_brightness",
                 summary: "ปรับความสว่างหน้าจอ",
                 usage: "value = ความสว่าง 0.0-1.0 (เช่น 0.6)",
                 risk: .normal, permission: nil, icon: "☀️"),

        ToolSpec(name: "open_app",
                 summary: "เปิดแอปอื่นบนเครื่อง (YouTube, LINE, TikTok, Maps, Camera, ธนาคาร ฯลฯ)",
                 usage: "value = ชื่อแอป เช่น 'youtube' หรือ 'line'",
                 risk: .normal, permission: nil, icon: "🚀"),

        ToolSpec(name: "open_url",
                 summary: "เปิดลิงก์เว็บไซต์หรือ URL ใดก็ได้",
                 usage: "value = URL เต็ม เช่น https://example.com",
                 risk: .normal, permission: nil, icon: "🌐"),

        ToolSpec(name: "search_web",
                 summary: "ค้นหาข้อมูลบนเว็บ (เปิด Safari พร้อมผลการค้น)",
                 usage: "value = คำค้น",
                 risk: .safe, permission: nil, icon: "🔍"),

        ToolSpec(name: "run_shortcut",
                 summary: "สั่ง Shortcut (ทางลัด) ของผู้ใช้ — เป็นทางเข้าถึงความสามารถของทุกแอปที่ผู้ใช้ตั้งค่าไว้",
                 usage: "value = ชื่อ Shortcut, extra = 'input=ข้อความที่ส่งเข้า'",
                 risk: .sensitive, permission: nil, icon: "⚡"),

        ToolSpec(name: "speak",
                 summary: "พูดออกเสียงภาษาไทยด้วยเสียงของเครื่อง",
                 usage: "value = ข้อความที่จะพูด",
                 risk: .normal, permission: nil, icon: "🗣️"),

        ToolSpec(name: "stop_speak",
                 summary: "หยุดการพูดทันที",
                 usage: "ไม่ต้องใส่ค่า",
                 risk: .safe, permission: nil, icon: "🤫"),

        ToolSpec(name: "set_reminder",
                 summary: "สร้างเตือนความจำ (Reminders)",
                 usage: "value = ข้อความที่ต้องจำ, extra = 'at=YYYY-MM-DD HH:MM' (ไม่บังคับ)",
                 risk: .normal, permission: "reminders", icon: "⏰"),

        ToolSpec(name: "list_reminders",
                 summary: "ดูรายการเตือนความจำที่ครบกำหนดวันนี้",
                 usage: "ไม่ต้องใส่ค่า",
                 risk: .safe, permission: "reminders", icon: "📋"),

        ToolSpec(name: "add_calendar",
                 summary: "เพิ่มนัดหมายลงปฏิทิน",
                 usage: "value = หัวข้อ, extra = 'start=YYYY-MM-DD HH:MM, duration=60(นาที)'",
                 risk: .normal, permission: "calendar", icon: "📅"),

        ToolSpec(name: "list_calendar",
                 summary: "ดูนัดหมายใน 7 วันข้างหน้า",
                 usage: "ไม่ต้องใส่ค่า",
                 risk: .safe, permission: "calendar", icon: "🗓️"),

        ToolSpec(name: "get_location",
                 summary: "ดูตำแหน่งปัจจุบันของผู้ใช้ (เมือง/พิกัด)",
                 usage: "ไม่ต้องใส่ค่า",
                 risk: .safe, permission: "location", icon: "📍"),

        ToolSpec(name: "search_contacts",
                 summary: "ค้นหาชื่อและเบอร์โทรในรายชื่อผู้ติดต่อ",
                 usage: "value = คำค้นชื่อ (เว้นว่างได้ = สุ่มมาบางคน)",
                 risk: .safe, permission: "contacts", icon: "👥"),

        ToolSpec(name: "list_photos",
                 summary: "ดูรูปล่าสุดในคลังรูป (วันที่ + จำนวน)",
                 usage: "value = จำนวนรูป (ค่าเริ่มต้น 10)",
                 risk: .safe, permission: "photos", icon: "🖼️"),

        ToolSpec(name: "take_photo",
                 summary: "เปิดกล้องให้ผู้ใช้ถ่ายรูป แล้ววิเคราะห์รูปนั้น",
                 usage: "value = คำถามที่ต้องการถามเกี่ยวกับรูป (เช่น 'อ่านข้อความในรูป')",
                 risk: .normal, permission: "camera", icon: "📷"),

        ToolSpec(name: "ocr_image",
                 summary: "อ่านข้อความในรูป (OCR รองรับภาษาไทย)",
                 usage: "value = คำถามเกี่ยวกับรูปล่าสุด",
                 risk: .safe, permission: "photos", icon: "🔍"),

        ToolSpec(name: "read_clipboard",
                 summary: "อ่านข้อความในคลิปบอร์ด",
                 usage: "ไม่ต้องใส่ค่า",
                 risk: .safe, permission: nil, icon: "📋"),

        ToolSpec(name: "write_clipboard",
                 summary: "คัดลอกข้อความลงคลิปบอร์ด",
                 usage: "value = ข้อความ",
                 risk: .normal, permission: nil, icon: "📌"),

        ToolSpec(name: "make_call",
                 summary: "โทรหาเบอร์ที่ระบุ",
                 usage: "value = เบอร์โทร",
                 risk: .sensitive, permission: nil, icon: "📞"),

        ToolSpec(name: "send_message",
                 summary: "ส่งข้อความ SMS ให้เบอร์ที่ระบุ",
                 usage: "value = 'เบอร์|ข้อความ'",
                 risk: .sensitive, permission: nil, icon: "💬"),

        ToolSpec(name: "share_text",
                 summary: "แชร์ข้อความออกไปยังแอปอื่น (AirDrop, Files, LINE ฯลฯ)",
                 usage: "value = ข้อความ",
                 risk: .normal, permission: nil, icon: "📤"),

        ToolSpec(name: "wifi_info",
                 summary: "ดูสถานะเครือข่าย Wi-Fi/เซลลูลาร์และชื่อเครือข่ายที่เชื่อมอยู่",
                 usage: "ไม่ต้องใส่ค่า",
                 risk: .safe, permission: "location", icon: "📶"),

        ToolSpec(name: "list_shortcuts",
                 summary: "แสดงรายชื่อ Shortcut ทั้งหมดที่ผู้ใช้มีในเครื่อง",
                 usage: "ไม่ต้องใส่ค่า",
                 risk: .safe, permission: nil, icon: "⚡"),
    ]

    static func specsJSON() -> [[String: Any]] {
        specs.map { spec in
            [
                "name": spec.name,
                "summary": spec.summary,
                "usage": spec.usage,
                "risk": spec.risk.rawValue,
                "permission": spec.permission ?? "",
                "icon": spec.icon,
            ]
        }
    }

    static func spec(named name: String) -> ToolSpec? {
        specs.first { $0.name == name }
    }
}
