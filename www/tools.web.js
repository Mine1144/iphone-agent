/* เครื่องมือฝั่งเว็บ (ใช้เมื่อเปิดเป็น PWA ใน Safari — ไม่มี native plugin)
   ในแอป native จะใช้ชุดเครื่องมือเต็มจาก Swift แทน */
window.WEB_TOOLS = [
  { name: "device_info", summary: "ข้อมูลเครื่องและเบราว์เซอร์", usage: "ไม่ต้องใส่ค่า", risk: "safe" },
  { name: "open_url", summary: "เปิดลิงก์เว็บไซต์", usage: "value = URL", risk: "normal" },
  { name: "search_web", summary: "ค้นหาข้อมูลบนเว็บ", usage: "value = คำค้น", risk: "safe" },
  { name: "speak", summary: "พูดออกเสียง", usage: "value = ข้อความ", risk: "normal" },
  { name: "read_clipboard", summary: "อ่านคลิปบอร์ด", usage: "ไม่ต้องใส่ค่า", risk: "safe" },
  { name: "write_clipboard", summary: "คัดลอกข้อความลงคลิปบอร์ด", usage: "value = ข้อความ", risk: "normal" },
  { name: "share_text", summary: "แชร์ข้อความ", usage: "value = ข้อความ", risk: "normal" },
  { name: "take_photo", summary: "เลือกรูปจากเครื่องเพื่อวิเคราะห์", usage: "value = คำถามเกี่ยวกับรูป", risk: "normal" },
];

window.WebTools = (() => {
  const catalog = window.WEB_TOOLS;

  function pickFile(question) {
    return new Promise((resolve) => {
      const input = document.createElement("input");
      input.type = "file";
      input.accept = "image/*";
      input.onchange = async () => {
        const file = input.files && input.files[0];
        if (!file) return resolve({ ok: false, result: "ผู้ใช้ยกเลิกการเลือกรูป" });
        const dataUrl = await new Promise((res) => {
          const fr = new FileReader();
          fr.onload = () => res(fr.result);
          fr.readAsDataURL(file);
        });
        resolve({ ok: true, result: `เลือกรูป ${file.name} แล้ว (${(file.size / 1024).toFixed(0)} KB)`, dataUrl });
      };
      input.click();
    });
  }

  async function run(name, value) {
    const v = (value || "").trim();
    switch (name) {
      case "device_info":
        return `เบราว์เซอร์: ${navigator.userAgent}\nภาษา: ${navigator.language}\nออนไลน์: ${navigator.onLine}`;
      case "open_url": {
        let url = v;
        if (!/^https?:\/\//i.test(url)) url = "https://" + url;
        window.open(url, "_blank");
        return `เปิด ${url} แล้ว`;
      }
      case "search_web": {
        const url = "https://duckduckgo.com/?q=" + encodeURIComponent(v);
        window.open(url, "_blank");
        return `เปิดการค้นหา “${v}” แล้ว`;
      }
      case "speak": {
        if (!("speechSynthesis" in window)) return "เบราว์เซอร์นี้พูดไม่ได้";
        const u = new SpeechSynthesisUtterance(v);
        u.lang = "th-TH";
        speechSynthesis.cancel();
        speechSynthesis.speak(u);
        return `กำลังพูด: ${v.slice(0, 80)}`;
      }
      case "read_clipboard":
        try {
          const text = await navigator.clipboard.readText();
          return "คลิปบอร์ด: " + (text || "(ว่าง)");
        } catch (e) {
          return "อ่านคลิปบอร์ดไม่ได้ (เบราว์เซอร์ขอสิทธิ์ก่อน)";
        }
      case "write_clipboard":
        try {
          await navigator.clipboard.writeText(v);
          return "คัดลอกข้อความลงคลิปบอร์ดแล้ว";
        } catch (e) {
          return "เขียนคลิปบอร์ดไม่ได้";
        }
      case "share_text":
        if (navigator.share) {
          try { await navigator.share({ text: v }); return "แชร์แล้ว"; }
          catch (e) { return "ผู้ใช้ยกเลิกการแชร์"; }
        }
        return "เบราว์เซอร์นี้แชร์ไม่ได้";
      case "take_photo": {
        const res = await pickFile(v);
        if (res.dataUrl) {
          window.__lastImage = res.dataUrl;
          return res.result + " — ใช้วิเคราะห์ต่อได้";
        }
        return res.result;
      }
      default:
        return "เครื่องมือนี้ต้องใช้ในแอป (native)";
    }
  }

  function schemas() {
    return catalog.map((t) => ({
      type: "function",
      function: {
        name: t.name,
        description: `${t.summary} | วิธีใช้: ${t.usage}`,
        parameters: {
          type: "object",
          properties: { value: { type: "string", description: t.usage } },
          required: ["value"],
        },
      },
    }));
  }

  return { catalog, run, schemas };
})();
