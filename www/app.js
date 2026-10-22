/* ผู้ช่วย iPhone — UI + ตัวเชื่อมสมอง
   - ในแอป (Capacitor): เรียก native plugin (สมองบนเครื่อง + เครื่องมือคุมเครื่องเต็ม)
   - ในเว็บ (PWA/Safari): เรียก API ตรงจากมือถือ มีเครื่องมือเว็บพื้นฐาน */
(() => {
  const $ = (s) => document.querySelector(s);
  const el = {
    chat: $("#chat"),
    statusText: $("#statusText"),
    brainBtn: $("#brainBtn"),
    orb: $("#orb"),
    input: $("#input"),
    sendBtn: $("#sendBtn"),
    micBtn: $("#micBtn"),
    attachBtn: $("#attachBtn"),
    fileInput: $("#fileInput"),
    settingsBtn: $("#settingsBtn"),
    settings: $("#settings"),
    settingsClose: $("#settingsClose"),
    cfgProvider: $("#cfgProvider"),
    cfgModel: $("#cfgModel"),
    cfgModelCustom: $("#cfgModelCustom"),
    cfgBaseUrl: $("#cfgBaseUrl"),
    baseUrlField: $("#baseUrlField"),
    cfgApiKey: $("#cfgApiKey"),
    keyHint: $("#keyHint"),
    cfgOnDevice: $("#cfgOnDevice"),
    cfgTTS: $("#cfgTTS"),
    cfgSimple: $("#cfgSimple"),
    btnClear: $("#btnClear"),
    modeHint: $("#modeHint"),
    approvalHost: $("#approvalHost"),
    approvalTitle: $("#approvalTitle"),
    approvalSummary: $("#approvalSummary"),
    approvalAllow: $("#approvalAllow"),
    approvalDeny: $("#approvalDeny"),
  };

  const state = {
    native: false,
    plugin: null,
    brain: "cloud",          // cloud | ondevice
    providerId: "pollinations", // เริ่มต้นด้วยตัวที่ไม่ต้องใช้คีย์ → ใช้ได้ทันที
    model: "openai",
    onDeviceAvailable: false,
    onDeviceNote: "",
    tts: false,
    simple: false,
    keys: {},                // providerId -> key (เว็บโหมดเก็บใน localStorage)
    tools: [],               // catalog เครื่องมือจาก native
    nativeHasKey: false,     // native มีคีย์ของผู้ให้บริการนี้อยู่ใน Keychain แล้ว
    busy: false,
    pendingApproval: null,
  };

  const providers = window.PROVIDERS || [];
  const providerById = (id) => providers.find((p) => p.id === id) || providers[0];

  // ---------------------------------------------------------------- ตัวช่วย DOM

  function timeNow() {
    return new Date().toLocaleTimeString("th-TH", { hour: "2-digit", minute: "2-digit" });
  }

  function addBubble(role, text) {
    const div = document.createElement("div");
    div.className = "bubble " + role;
    const body = document.createElement("div");
    body.className = "bubble-body";
    body.textContent = text;
    div.appendChild(body);
    const meta = document.createElement("div");
    meta.className = "bubble-meta";
    meta.textContent = role === "user" ? "คุณ" : "ผู้ช่วย";
    div.appendChild(meta);
    el.chat.appendChild(div);
    scrollDown();
    return div;
  }

  function addTyping() {
    const div = document.createElement("div");
    div.className = "bubble agent";
    div.id = "typing";
    div.innerHTML = '<div class="bubble-body typing"><i></i><i></i><i></i></div>';
    el.chat.appendChild(div);
    scrollDown();
    return div;
  }

  function removeTyping() {
    const t = document.getElementById("typing");
    if (t) t.remove();
  }

  function addToolCard(name, args) {
    if (state.simple) return null;
    const spec = (state.tools || []).find((t) => t.name === name)
      || (window.WEB_TOOLS || []).find((t) => t.name === name);
    const div = document.createElement("div");
    div.className = "tool-card";
    div.innerHTML = `
      <div class="tool-head"><span class="tool-icon">⚙︎</span>
        <span class="tool-name"></span><span class="tool-state">กำลังทำ…</span></div>
      <div class="tool-args"></div>`;
    div.querySelector(".tool-name").textContent = spec ? (spec.summary || name) : name;
    div.querySelector(".tool-args").textContent = args || "";
    el.chat.appendChild(div);
    scrollDown();
    return div;
  }

  function finishToolCard(name, result) {
    if (state.simple) return;
    const cards = el.chat.querySelectorAll(".tool-card");
    const card = cards[cards.length - 1];
    if (!card) return;
    card.classList.add("done");
    card.querySelector(".tool-state").textContent = "เสร็จ";
    if (result) {
      const out = document.createElement("div");
      out.className = "tool-out";
      out.textContent = result;
      card.appendChild(out);
    }
  }

  function scrollDown() {
    requestAnimationFrame(() => { el.chat.scrollTop = el.chat.scrollHeight; });
  }

  /** แถบแจ้งเตือนด้านบน (ใช้ตอน plugin ไม่โหลด หรือมี error) */
  function banner(text, tone) {
    let b = document.getElementById('banner');
    if (!b) {
      b = document.createElement('div');
      b.id = 'banner';
      b.className = 'banner';
      document.getElementById('app').prepend(b);
    }
    b.textContent = text;
    b.dataset.tone = tone || 'warn';
    b.hidden = false;
  }

  function setStatus(text, tone) {
    el.statusText.textContent = text;
    el.orb.dataset.tone = tone || "idle";
  }

  // ---------------------------------------------------------------- การอนุมัติ

  function showApproval(tool, summary) {
    state.pendingApproval = { tool, summary };
    el.approvalTitle.textContent = "ขออนุมัติ: " + tool;
    el.approvalSummary.textContent = summary || "";
    el.approvalHost.hidden = false;
  }

  function hideApproval() {
    el.approvalHost.hidden = true;
    state.pendingApproval = null;
  }

  el.approvalAllow.addEventListener("click", async () => {
    const p = state.pendingApproval;
    hideApproval();
    if (state.native) await state.plugin.approve({ id: p.id, approved: true });
  });
  el.approvalDeny.addEventListener("click", async () => {
    const p = state.pendingApproval;
    hideApproval();
    if (state.native) await state.plugin.approve({ id: p.id, approved: false });
  });

  // ---------------------------------------------------------------- ตั้งค่า UI

  function buildProviderSelect() {
    el.cfgProvider.innerHTML = "";
    providers.forEach((p) => {
      const o = document.createElement("option");
      o.value = p.id;
      o.textContent = p.name;
      el.cfgProvider.appendChild(o);
    });
    el.cfgProvider.value = state.providerId;
  }

  function buildModelSelect() {
    const p = providerById(state.providerId);
    el.cfgModel.innerHTML = "";
    p.models.forEach((m) => {
      const o = document.createElement("option");
      o.value = m.id;
      o.textContent = m.name + (m.id ? ` — ${m.id}` : "");
      el.cfgModel.appendChild(o);
    });
    const custom = state.model && !p.models.some((m) => m.id === state.model);
    el.cfgModelCustom.hidden = !(custom || state.providerId === "custom");
    if (custom || state.providerId === "custom") el.cfgModelCustom.value = state.model || "";
    el.cfgModel.value = p.models.some((m) => m.id === state.model) ? state.model : (p.models[0]?.id || "");
    state.model = el.cfgModel.value || state.model;
    el.baseUrlField.hidden = state.providerId !== "custom";
    el.cfgBaseUrl.value = p.baseURL || "";
    el.keyHint.textContent = p.keyRequired
      ? `ต้องใส่คีย์ — สมัครที่ ${p.keyURL} · ${p.note || ""}`
      : `ไม่ต้องใส่คีย์ · ${p.note || ""}`;
    if (p.cors === false) {
      el.keyHint.textContent += " · ⚠️ เบราว์เซอร์บล็อก CORS ของผู้ให้บริการนี้ (ใช้ได้ในแอป native เท่านั้น)";
    }
    if (state.native && state.nativeHasKey && p.keyRequired) {
      el.keyHint.textContent = "มีคีย์บันทึกไว้ใน Keychain ของเครื่องแล้ว — พิมพ์ทับถ้าจะเปลี่ยน";
    }
  }

  function refreshBrainLabel() {
    if (state.brain === "ondevice") {
      el.brainBtn.textContent = "สมอง: บนเครื่อง";
    } else {
      const p = providerById(state.providerId);
      el.brainBtn.textContent = "สมอง: " + p.name;
    }
  }

  function loadLocalPrefs() {
    try {
      const saved = JSON.parse(localStorage.getItem("agent.prefs") || "{}");
      state.providerId = saved.providerId || state.providerId;
      state.model = saved.model || "";
      state.tts = !!saved.tts;
      state.simple = !!saved.simple;
      state.keys = saved.keys || {};
      state.brain = saved.brain || "cloud";
    } catch (_) { /* ignore */ }
  }

  function saveLocalPrefs() {
    localStorage.setItem("agent.prefs", JSON.stringify({
      providerId: state.providerId,
      model: state.model,
      tts: state.tts,
      simple: state.simple,
      brain: state.brain,
      keys: state.keys,
    }));
  }

  // ---------------------------------------------------------------- เริ่มสมอง

  async function startBrain() {
    const p = providerById(state.providerId);
    const key = state.keys[state.providerId] || "";
    try {
      if (state.native) {
        if (state.brain === "ondevice") {
          await state.plugin.start({ brain: "ondevice" });
          setStatus("สมองบนเครื่องพร้อมใช้งาน", "ok");
        } else {
          const payload = {
            brain: "cloud",
            provider: state.providerId,
            baseUrl: p.baseURL,
            format: p.format,
            model: state.model,
          };
          // ถ้าไม่มีคีย์ในฝั่งเว็บ ให้ native ใช้คีย์ที่บันทึกไว้ใน Keychain แทน
          if (key) payload.apiKey = key;
          await state.plugin.start(payload);
          setStatus(`${p.name} · ${state.model}`, "ok");
        }
      } else {
        if (state.brain === "ondevice") {
          setStatus("เว็บโหมดใช้โมเดลคลาวด์เท่านั้น", "warn");
          state.brain = "cloud";
        }
        if (p.keyRequired && !key) {
          setStatus("ยังไม่ได้ใส่ API key ของ " + p.name, "warn");
          return false;
        }
        setStatus(`${p.name} · ${state.model}`, "ok");
      }
      return true;
    } catch (err) {
      setStatus(String(err.message || err).slice(0, 120), "err");
      addBubble("agent", "เปิดสมองไม่สำเร็จ: " + (err.message || err));
      return false;
    }
  }

  // ---------------------------------------------------------------- โหมดเว็บ (PWA)

  function webKey() {
    return state.keys[state.providerId] || "";
  }

  async function webCallAPI(messages, withTools) {
    const p = providerById(state.providerId);
    const key = webKey();
    const headers = { "Content-Type": "application/json" };
    if (key) headers["Authorization"] = "Bearer " + key;
    if (p.id === "openrouter") {
      headers["HTTP-Referer"] = "https://github.com/natee/iphone-agent";
      headers["X-Title"] = "iPhone Agent";
    }

    if (p.format === "anthropic") {
      const system = messages.find((m) => m.role === "system");
      const rest = messages.filter((m) => m.role !== "system");
      const body = {
        model: state.model,
        max_tokens: 2048,
        system: system ? system.content : "",
        messages: rest.map(convAnthropic),
      };
      if (withTools) {
        body.tools = window.WebTools.catalog.map((t) => ({
          name: t.name,
          description: `${t.summary} | วิธีใช้: ${t.usage}`,
          input_schema: {
            type: "object",
            properties: { value: { type: "string", description: t.usage } },
            required: ["value"],
          },
        }));
      }
      headers["anthropic-version"] = "2023-06-01";
      if (key) headers["x-api-key"] = key;
      const res = await fetch(p.baseURL.replace(/\/$/, "") + (/\/v1$/.test(p.baseURL) ? "/messages" : "/v1/messages"), {
        method: "POST", headers, body: JSON.stringify(body),
      });
      if (!res.ok) throw new Error("API " + res.status + ": " + (await res.text()).slice(0, 200));
      const json = await res.json();
      const blocks = json.content || [];
      const text = blocks.filter((b) => b.type === "text").map((b) => b.text).join("");
      const calls = blocks.filter((b) => b.type === "tool_use").map((b) => ({
        id: b.id, name: b.name, args: b.input || {},
      }));
      return { text, calls };
    }

    const body = { model: state.model, messages, temperature: 0.4, stream: false };
    if (withTools) { body.tools = window.WebTools.schemas(); body.tool_choice = "auto"; }
    const res = await fetch(p.baseURL.replace(/\/$/, "") + "/chat/completions", {
      method: "POST", headers, body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error("API " + res.status + ": " + (await res.text()).slice(0, 200));
    const json = await res.json();
    const msg = (json.choices && json.choices[0] && json.choices[0].message) || {};
    const calls = (msg.tool_calls || []).map((c) => ({
      id: c.id, name: c.function.name, args: safeParse(c.function.arguments),
    }));
    return { text: msg.content || "", calls };
  }

  function convAnthropic(m) {
    if (m.role === "user") return { role: "user", content: [{ type: "text", text: m.content }] };
    if (m.role === "tool") {
      return { role: "user", content: [{ type: "tool_result", tool_use_id: m.tool_call_id, content: m.content }] };
    }
    if (m.role === "assistant" && m.tool_calls) {
      return {
        role: "assistant",
        content: m.tool_calls.map((c) => ({ type: "tool_use", id: c.id, name: c.name, input: c.args })),
      };
    }
    return { role: "assistant", content: [{ type: "text", text: m.content || "" }] };
  }

  function safeParse(text) {
    try { return JSON.parse(text || "{}"); } catch (_) { return {}; }
  }

  async function webChat(text) {
    const messages = [
      { role: "system", content: window.AGENT_INSTRUCTIONS },
      { role: "user", content: text },
    ];
    for (let i = 0; i < 6; i++) {
      const reply = await webCallAPI(messages, i < 5);
      if (reply.calls && reply.calls.length) {
        messages.push({ role: "assistant", content: reply.text || null, tool_calls: reply.calls.map((c) => ({
          id: c.id, type: "function", function: { name: c.name, arguments: JSON.stringify(c.args) },
        })) });
        for (const c of reply.calls) {
          addToolCard(c.name, c.args.value || "");
          const out = await window.WebTools.run(c.name, c.args.value);
          finishToolCard(c.name, out);
          messages.push({ role: "tool", tool_call_id: c.id, name: c.name, content: out });
        }
        continue;
      }
      return reply.text;
    }
    return "ทำงานหลายรอบเกินไป — ลองถามให้เจาะจงกว่านี้";
  }

  // ---------------------------------------------------------------- ส่งข้อความ

  async function send(text) {
    if (state.busy) return;
    const t = (text || "").trim();
    if (!t) return;
    state.busy = true;
    el.sendBtn.disabled = true;
    addBubble("user", t);
    el.input.value = "";
    const typing = addTyping();

    try {
      if (state.native) {
        // ผลลัพธ์มาจาก event ของ plugin (มี timeout กันค้าง)
        const res = await Promise.race([
          state.plugin.send({ text: t }),
          new Promise((_, rej) => setTimeout(() => rej(new Error("สมองไม่ตอบใน 2 นาที — ลองเปลี่ยนผู้ให้บริการหรือโมเดล")), 120000)),
        ]);
        removeTyping();
        if (res && res.text) addBubble("agent", res.text);
        speakOut(res && res.text);
      } else {
        const out = await webChat(t);
        removeTyping();
        addBubble("agent", out);
        speakOut(out);
      }
    } catch (err) {
      removeTyping();
      addBubble("agent", "⚠️ " + (err.message || err));
      setStatus("ผิดพลาด", "err");
    } finally {
      state.busy = false;
      el.sendBtn.disabled = false;
      typing.remove();
    }
  }

  function speakOut(text) {
    if (!state.tts || !text) return;
    if (state.native) state.plugin.speak({ text });
    else if ("speechSynthesis" in window) {
      const u = new SpeechSynthesisUtterance(text);
      u.lang = "th-TH";
      speechSynthesis.speak(u);
    }
  }

  // ---------------------------------------------------------------- event ของ native

  function bindNativeEvents() {
    state.plugin.addListener("agent", (ev) => {
      switch (ev.type) {
        case "status":
          setStatus(ev.detail || ev.state || "", ev.state === "thinking" ? "busy" : "ok");
          break;
        case "tool":
          addToolCard(ev.name, [ev.value, ev.extra].filter(Boolean).join(" · "));
          break;
        case "tool_result":
          finishToolCard(ev.name, ev.result);
          break;
        case "done":
          break;
        case "error":
          setStatus("ผิดพลาด", "err");
          addBubble("agent", "⚠️ " + ev.message);
          break;
        default:
          break;
      }
    });

    state.plugin.addListener("approval", (ev) => {
      state.pendingApproval = { id: ev.id, tool: ev.tool, summary: ev.summary };
      showApproval(ev.tool, ev.summary);
    });

    state.plugin.addListener("dictation", (ev) => {
      if (ev.final) {
        el.input.value = ev.text || "";
        if (ev.text) send(ev.text);
      } else {
        el.input.value = ev.text || "";
      }
    });
  }

  // ---------------------------------------------------------------- ปุ่มต่าง ๆ

  el.sendBtn.addEventListener("click", () => send(el.input.value));
  el.input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") { e.preventDefault(); send(el.input.value); }
  });

  el.micBtn.addEventListener("click", async () => {
    if (state.native) {
      el.micBtn.classList.add("rec");
      try { await state.plugin.listen({ lang: "th-TH" }); }
      catch (err) { addBubble("agent", "⚠️ " + (err.message || err)); }
      finally { el.micBtn.classList.remove("rec"); }
    } else if ("webkitSpeechRecognition" in window) {
      const rec = new webkitSpeechRecognition();
      rec.lang = "th-TH"; rec.interimResults = true;
      rec.onresult = (e) => { el.input.value = e.results[e.results.length - 1][0].transcript; };
      rec.onend = () => el.micBtn.classList.remove("rec");
      rec.start();
      el.micBtn.classList.add("rec");
    } else {
      addBubble("agent", "เบราว์เซอร์นี้ไม่รองรับการพูด — ใช้ในแอปแทน");
    }
  });

  el.attachBtn.addEventListener("click", () => {
    if (state.native) {
      el.fileInput.click();
    } else {
      window.WebTools.run("take_photo", "");
    }
  });

  el.fileInput.addEventListener("change", async () => {
    const file = el.fileInput.files && el.fileInput.files[0];
    if (!file) return;
    const dataUrl = await new Promise((res) => {
      const fr = new FileReader();
      fr.onload = () => res(fr.result);
      fr.readAsDataURL(file);
    });
    addBubble("user", "📷 แนบรูป: " + file.name);
    if (state.native) {
      const res = await state.plugin.send({ text: "วิเคราะห์รูปที่ผู้ใช้แนบมา: " + file.name + " (base64: " + dataUrl.slice(0, 40000) + ")" });
      if (res && res.text) addBubble("agent", res.text);
    } else {
      const out = await webChat("ผู้ใช้แนบรูป " + file.name + " ช่วยวิเคราะห์รูปนี้ได้อะไร");
      addBubble("agent", out);
    }
    el.fileInput.value = "";
  });

  el.brainBtn.addEventListener("click", () => {
    el.settings.hidden = false;
  });

  el.settingsBtn.addEventListener("click", () => { el.settings.hidden = false; });
  el.settingsClose.addEventListener("click", () => { el.settings.hidden = true; });
  el.settings.addEventListener("click", (e) => { if (e.target === el.settings) el.settings.hidden = true; });

  el.cfgProvider.addEventListener("change", async () => {
    state.providerId = el.cfgProvider.value;
    state.model = providerById(state.providerId).models[0]?.id || "";
    buildModelSelect();
    el.cfgApiKey.value = state.keys[state.providerId] || "";
    refreshBrainLabel();
    saveLocalPrefs();
    await startBrain();
  });

  el.cfgModel.addEventListener("change", async () => {
    state.model = el.cfgModel.value;
    el.cfgModelCustom.hidden = true;
    saveLocalPrefs();
    await startBrain();
  });

  el.cfgModelCustom.addEventListener("change", async () => {
    state.model = el.cfgModelCustom.value.trim();
    saveLocalPrefs();
    await startBrain();
  });

  el.cfgBaseUrl.addEventListener("change", async () => {
    providerById(state.providerId).baseURL = el.cfgBaseUrl.value.trim();
    saveLocalPrefs();
    await startBrain();
  });

  el.cfgApiKey.addEventListener("change", async () => {
    const key = el.cfgApiKey.value.trim();
    state.keys[state.providerId] = key;
    saveLocalPrefs();
    if (state.native) await state.plugin.setApiKey({ provider: state.providerId, apiKey: key });
    await startBrain();
  });

  el.cfgOnDevice.addEventListener("change", async () => {
    state.brain = el.cfgOnDevice.checked ? "ondevice" : "cloud";
    saveLocalPrefs();
    refreshBrainLabel();
    await startBrain();
  });

  el.cfgTTS.addEventListener("change", () => {
    state.tts = el.cfgTTS.checked;
    saveLocalPrefs();
  });

  el.cfgSimple.addEventListener("change", () => {
    state.simple = el.cfgSimple.checked;
    saveLocalPrefs();
  });

  el.btnClear.addEventListener("click", () => {
    el.chat.innerHTML = "";
    addBubble("agent", "ล้างประวัติแล้ว — สั่งงานได้เลย");
  });

  // ---------------------------------------------------------------- เริ่ม

  (async function init() {
    if ("serviceWorker" in navigator && location.protocol.startsWith("http")) {
      navigator.serviceWorker.register("./sw.js").catch(() => {});
    }
    loadLocalPrefs();
    buildProviderSelect();
    buildModelSelect();
    el.cfgTTS.checked = state.tts;
    el.cfgSimple.checked = state.simple;
    el.cfgApiKey.value = state.keys[state.providerId] || "";

    const cap = window.Capacitor;
    if (cap && cap.Plugins && cap.Plugins.AgentPlugin) {
      state.native = true;
      state.plugin = cap.Plugins.AgentPlugin;
      bindNativeEvents();
      try {
        const tl = await state.plugin.listTools();
        state.tools = tl.tools || [];
      } catch (_) { /* ignore */ }

      try {
        const cfg = await state.plugin.getConfig();
        if (cfg.selected && providers.some((p) => p.id === cfg.selected)) {
          state.providerId = cfg.selected;
          state.model = cfg.selectedModel || state.model;
          buildProviderSelect();
          buildModelSelect();
        }
        state.nativeHasKey = (cfg.providers || []).some((p) => p.id === state.providerId && p.hasKey);
      } catch (_) { /* ignore */ }

      try {
        const av = await state.plugin.availability();
        state.onDeviceAvailable = !!(av.onDevice && av.onDevice.available);
        state.onDeviceNote = (av.onDevice && av.onDevice.note) || "";
        el.cfgOnDevice.disabled = !state.onDeviceAvailable;
        if (!state.onDeviceAvailable) {
          el.cfgOnDevice.closest(".switch").style.opacity = "0.5";
        }
      } catch (_) { /* ignore */ }

      el.modeHint.textContent = state.onDeviceAvailable
        ? "โหมดแอป: ใช้เครื่องมือคุม iPhone ได้ครบ — " + state.onDeviceNote
        : "โหมดแอป: " + (state.onDeviceNote || "เครื่องนี้ใช้เฉพาะโมเดลคลาวด์");
    } else {
      const hasCapacitor = !!(cap && cap.Plugins);
      el.modeHint.textContent = hasCapacitor
        ? "⚠️ เปิดเป็นแอป แต่ native plugin ไม่ได้โหลด — กำลังใช้โหมดเว็บ (เครื่องมือคุมเครื่องจะใช้ไม่ได้)"
        : "โหมดเว็บ (PWA): เรียก API ตรงจากมือถือ — เครื่องมือคุมเครื่องจะใช้ได้เต็มเมื่อติดตั้งเป็นแอป";
      el.cfgOnDevice.disabled = true;
      if (hasCapacitor) banner("native plugin ไม่ได้โหลด — ใช้โหมดเว็บชั่วคราว", "err");
    }

    el.cfgOnDevice.checked = state.brain === "ondevice";
    refreshBrainLabel();
    await startBrain();

    addBubble("agent", state.native
      ? "พร้อมคุยครับ — สั่งผมควบคุมเครื่องได้ เช่น “ตั้งเตือนความจำว่าไปซื้อข้าว”, “เปิด YouTube”, “อ่านข้อความในรูปนี้”"
      : "พร้อมคุยครับ (โหมดเว็บ — ใส่ API key ในตั้งค่าเพื่อเริ่มคุย)");
  })();
})();
