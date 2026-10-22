/**
 * build-ipa.mjs — สร้าง .ipa ของ iPhone Agent โดยไม่ต้องมี git
 *   1) สร้าง repo บน GitHub (ถ้ายังไม่มี) ผ่าน REST API
 *   2) อัปโหลดไฟล์ทั้งหมดผ่าน Git Data API (blob → tree → commit → ref)
 *   3) push ไปที่ main → workflow "Build IPA (iPhone Agent)" ทำงานเอง (trigger: push)
 *   4) รอ build เสร็จ แล้วดาวน์โหลด artifact ios-ipa → แตกไฟล์ .ipa มาไว้ในโฟลเดอร์โปรเจกต์
 *
 * ใช้:
 *   $env:GITHUB_TOKEN = "ghp_xxx"
 *   node tools\build-ipa.mjs [--repo Mine1144/iphone-agent] [--wait]
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const API = 'https://api.github.com';
const WORKFLOW = 'build-ios-ipa.yml';

const args = process.argv.slice(2);
const argOf = (name, def) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
};
const REPO = argOf('--repo', 'Mine1144/iphone-agent');
const TOKEN = argOf('--token', process.env.GITHUB_TOKEN || '');
const WAIT = args.includes('--wait');

if (!TOKEN && !args.includes('--list')) {
  console.error('✗ ไม่พบ GITHUB_TOKEN — ตั้งค่าก่อน: $env:GITHUB_TOKEN = "ghp_xxx"');
  process.exit(1);
}

const headers = {
  Authorization: `Bearer ${TOKEN}`,
  Accept: 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
  'User-Agent': 'iphone-agent-build',
};

async function api(method, url, body, raw = false) {
  const res = await fetch(url.startsWith('http') ? url : API + url, {
    method,
    headers: raw ? { ...headers, Accept: 'application/vnd.github+json' } : headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = { raw: text }; }
  if (!res.ok) {
    const msg = json?.message || text?.slice(0, 300);
    const err = new Error(`${method} ${url} → ${res.status}: ${msg}`);
    err.status = res.status;
    throw err;
  }
  return json;
}

// ---------------------------------------------------------------- ไฟล์ที่จะอัปโหลด
const IGNORE_DIRS = new Set(['node_modules', '.git', 'tmp', 'public', 'capacitor-cordova-ios-plugins', 'DerivedData', 'build']);
// ไฟล์ที่ Capacitor สร้างใหม่ตอน cap sync (ของที่อยู่ใน ios/App/App เท่านั้น)
const GENERATED = new Set([
  'ios/App/App/capacitor.config.json',
  'ios/App/App/config.xml',
  'ios/App/Podfile.lock',
]);

function collect(dir, prefix = '') {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (IGNORE_DIRS.has(entry.name)) continue;
      if (rel.startsWith('ios/App/App/public')) continue;
      out.push(...collect(abs, rel));
    } else {
      if (GENERATED.has(rel)) continue;
      if (entry.name === '.DS_Store') continue;
      if (/\.(log|ipa|dSYM)$/i.test(entry.name)) continue;
      out.push({ path: rel, abs });
    }
  }
  return out;
}

// ---------------------------------------------------------------- 1) repo
async function ensureRepo() {
  try {
    const r = await api('GET', `/repos/${REPO}`);
    console.log(`✓ repo มีอยู่แล้ว: ${REPO} (${r.private ? 'private' : 'public'})`);
    return;
  } catch (e) {
    if (e.status !== 404) throw e;
  }
  const name = REPO.split('/')[1];
  await api('POST', '/user/repos', {
    name,
    private: false,
    description: 'AI Agent ที่ควบคุม iPhone ได้ทั้งเครื่อง (สมองบนเครื่อง + OpenRouter/OpenAI/...)',
    has_issues: false,
    auto_init: false,
  });
  console.log(`✓ สร้าง repo ใหม่: ${REPO}`);
}

// ---------------------------------------------------------------- 2) upload
async function pushFiles() {
  const files = collect(ROOT);
  console.log(`→ อัปโหลด ${files.length} ไฟล์...`);

  const tree = [];
  for (const f of files) {
    const buf = fs.readFileSync(f.abs);
    const blob = await api('POST', `/repos/${REPO}/git/blobs`, {
      content: buf.toString('base64'),
      encoding: 'base64',
    });
    tree.push({ path: f.path, mode: '100644', type: 'blob', sha: blob.sha });
  }

  const created = await api('POST', `/repos/${REPO}/git/trees`, { tree });
  console.log(`✓ สร้าง tree (${created.tree.length} ไฟล์)`);

  const commit = await api('POST', `/repos/${REPO}/git/commits`, {
    message: 'iPhone Agent — AI agent คุม iPhone ทั้งเครื่อง (สมองบนเครื่อง + คลาวด์หลายเจ้า)',
    tree: created.sha,
    parents: [],
  });
  console.log(`✓ commit ${commit.sha.slice(0, 8)}`);

  try {
    await api('POST', `/repos/${REPO}/git/refs`, { ref: 'refs/heads/main', sha: commit.sha });
    console.log('✓ สร้าง branch main');
  } catch (e) {
    if (e.status === 422) {
      await api('PATCH', `/repos/${REPO}/git/refs/heads/main`, { sha: commit.sha, force: true });
      console.log('✓ อัปเดต branch main (force)');
    } else throw e;
  }
}

// ---------------------------------------------------------------- 3) รอ + ดาวน์โหลด
async function waitAndDownload() {
  console.log('\n→ รอ workflow ทำงาน (macos-26 / Xcode 26) ...');
  let run = null;
  for (let i = 0; i < 150; i++) {
    await new Promise((r) => setTimeout(r, 20000));
    const runs = await api('GET', `/repos/${REPO}/actions/workflows/${WORKFLOW}/runs?per_page=5`);
    run = (runs.workflow_runs || []).find((r) => r.head_branch === 'main');
    if (!run) { console.log('   ... ยังไม่มี run'); continue; }
    console.log(`   ... ${run.status} / ${run.conclusion || 'running'} (run #${run.id})`);
    if (run.status === 'completed') {
      if (run.conclusion !== 'success') {
        console.error(`✗ build ล้มเหลว: ${run.conclusion}`);
        console.error(`  ดู log: ${run.html_url}`);
        process.exit(1);
      }
      break;
    }
  }
  if (!run || run.status !== 'completed') { console.error('✗ หมดเวลารอ'); process.exit(1); }

  console.log('✓ build สำเร็จ — ดาวน์โหลด artifact');
  const arts = await api('GET', `/repos/${REPO}/actions/runs/${run.id}/artifacts`);
  const art = (arts.artifacts || []).find((a) => a.name === 'ios-ipa');
  if (!art) { console.error('✗ ไม่พบ artifact ios-ipa'); process.exit(1); }

  const res = await fetch(`${API}/repos/${REPO}/actions/artifacts/${art.id}/zip`, {
    headers: { ...headers, Accept: 'application/vnd.github+json' },
  });
  if (!res.ok) { console.error('✗ ดาวน์โหลดไม่สำเร็จ'); process.exit(1); }
  const zip = Buffer.from(await res.arrayBuffer());

  const tmp = path.join(ROOT, 'tmp', 'ipa-dl');
  fs.mkdirSync(tmp, { recursive: true });
  const zipPath = path.join(tmp, 'artifact.zip');
  fs.writeFileSync(zipPath, zip);
  execFileSync('powershell', ['-NoProfile', '-Command', `Expand-Archive -Path '${zipPath}' -DestinationPath '${tmp}' -Force`], { stdio: 'inherit' });

  const findIpa = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { const r = findIpa(p); if (r) return r; }
      else if (e.name.endsWith('.ipa')) return p;
    }
    return null;
  };
  const ipa = findIpa(tmp);
  if (!ipa) { console.error('✗ ไม่พบไฟล์ .ipa ใน artifact'); process.exit(1); }
  const dest = path.join(ROOT, path.basename(ipa));
  fs.copyFileSync(ipa, dest);
  const kb = (fs.statSync(dest).size / 1024).toFixed(0);
  console.log(`\n🎉 ได้ไฟล์: ${dest} (${kb} KB)`);
  console.log('   ติดตั้งผ่าน LiveContainer / SideStore / AltStore');
}

// ---------------------------------------------------------------- main
(async () => {
  try {
    if (args.includes('--list')) {
      const files = collect(ROOT);
      console.log(`${files.length} ไฟล์ที่จะอัปโหลด:`);
      for (const f of files) console.log('  ' + f.path);
      return;
    }
    await ensureRepo();
    await pushFiles();
    console.log('✓ push สำเร็จ — workflow จะเริ่มทำงานอัตโนมัติ');
    if (WAIT) await waitAndDownload();
    else {
      console.log('\nดูผลได้ที่: https://github.com/' + REPO + '/actions');
      console.log('ดาวน์โหลด .ipa: รันซ้ำด้วย --wait');
    }
  } catch (e) {
    console.error('✗ ล้มเหลว:', e.message);
    process.exit(1);
  }
})();
