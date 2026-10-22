<#
  build-ipa.ps1 — สร้าง .ipa ของ iPhone Agent ผ่าน GitHub Actions (macOS 26 / Xcode 26)
  ใช้บน Windows ได้ ไม่ต้องมี Mac

  โหมดอัตโนมัติ (ต้องมี git + GITHUB_TOKEN):
      $env:GITHUB_TOKEN = "ghp_xxx"
      .\build-ipa.ps1 -Repo "natee/iphone-agent" -Create

  โหมดแนะนำ (มี gh CLI อยู่แล้ว):
      gh auth login
      .\build-ipa.ps1 -Repo "natee/iphone-agent" -Create

  โหมดแมนวล (ไม่มี git/gh):
      .\build-ipa.ps1 -Manual
#>
param(
  [string]$Repo = "",          # owner/name
  [string]$Token = "",         # PAT (ถ้าไม่ระบุจะอ่านจาก $env:GITHUB_TOKEN หรือขอใส่)
  [switch]$Create,             # สร้าง repo ใหม่บน GitHub
  [switch]$Manual,             # แสดงขั้นตอนสำหรับทำเอง
  [switch]$SkipPush,
  [switch]$SkipFetch
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$workflow = "build-ios-ipa.yml"
$api = "https://api.github.com"

function Write-Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "  ✓ $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "  ✗ $m" -ForegroundColor Red }

# ---------------------------------------------------------------- โหมดแมนวล
if ($Manual) {
  Write-Step "ขั้นตอนสร้าง .ipa แบบแมนวล"
  Write-Host @"
  1) ติดตั้ง Git for Windows  (ถ้ายังไม่มี)
       winget install --id Git.Git -e
  2) สร้าง repo บน GitHub (ชื่ออะไรก็ได้ เช่น iphone-agent) แล้วรันในโฟลเดอร์นี้:
       git init -b main
       git add .
       git commit -m "iPhone Agent v1"
       git remote add origin https://github.com/<owner>/<repo>.git
       git push -u origin main
  3) ไปที่แท็บ Actions > workflow "Build IPA (iPhone Agent)" > Run workflow > เลือก main > Run
  4) รอจนเสร็จ แล้วดาวน์โหลด artifact ชื่อ "ios-ipa" (ไฟล์ iPhoneAgent-unsigned.ipa)
  5) ติดตั้งผ่าน LiveContainer / SideStore / AltStore
"@ -ForegroundColor Yellow
  exit 0
}

# ---------------------------------------------------------------- ตรวจเครื่องมือ
Write-Step "ตรวจเครื่องมือ"
$git = Get-Command git -ErrorAction SilentlyContinue
$gh  = Get-Command gh  -ErrorAction SilentlyContinue
if ($git) { Write-Ok "git: $($git.Source)" } else { Write-Warn2 "ไม่พบ git — ติดตั้งด้วย: winget install --id Git.Git -e" }
if ($gh)  { Write-Ok "gh:  $($gh.Source)" }  else { Write-Warn2 "ไม่พบ gh CLI (ไม่บังคับ — จะใช้ REST API แทน)" }

if (-not $Token) { $Token = $env:GITHUB_TOKEN }
if (-not $Token -and $gh) {
  try {
    $tok = gh auth token 2>$null
    if ($tok) { $Token = $tok; Write-Ok "ใช้โทเคนจาก gh auth" }
  } catch { }
}
if (-not $Token) {
  Write-Err "ไม่พบ GitHub token — ตั้งค่าก่อน: `$env:GITHUB_TOKEN = 'ghp_xxx'  (หรือใช้ -Manual)"
  exit 1
}
if (-not $Repo) {
  $Repo = Read-Host "ระบุ repo ในรูป owner/name (เช่น natee/iphone-agent)"
}
Write-Ok "repo: $Repo"

$headers = @{
  "Authorization"  = "Bearer $Token"
  "Accept"         = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
  "User-Agent"     = "iphone-agent-build"
}

# ---------------------------------------------------------------- สร้าง repo (ถ้าต้องการ)
if ($Create) {
  Write-Step "สร้าง repo บน GitHub"
  $name = ($Repo -split "/")[-1]
  try {
    $body = @{ name = $name; private = $false; description = "AI Agent ที่ควบคุม iPhone ได้ทั้งเครื่อง"; auto_init = $false } | ConvertTo-Json
    Invoke-RestMethod -Uri "$api/user/repos" -Method Post -Headers $headers -Body $body -ContentType "application/json" | Out-Null
    Write-Ok "สร้าง repo $Repo แล้ว"
  } catch {
    $msg = $_.Exception.Message
    if ($msg -match "already exists" -or $msg -match "422") { Write-Warn2 "repo มีอยู่แล้ว (ข้ามการสร้าง)" }
    else { Write-Err "สร้าง repo ไม่สำเร็จ: $msg"; exit 1 }
  }
}

# ---------------------------------------------------------------- commit + push
if (-not $SkipPush) {
  if (-not $git) { Write-Err "ต้องมี git ก่อน (หรือใช้ -Manual)"; exit 1 }
  Write-Step "commit + push"
  Push-Location $root
  try {
    if (-not (Test-Path ".git")) {
      & git init -b main | Out-Null
      Write-Ok "git init (branch main)"
    }
    & git add -A
    & git -c user.name="iPhone Agent Build" -c user.email="build@local" commit -m "iPhone Agent: AI agent ที่ควบคุม iPhone ได้ทั้งเครื่อง" 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Warn2 "ไม่มีอะไรให้ commit (อยู่ในสถานะเดิม)" }

    $remote = (& git remote) 2>$null
    if ($remote -notcontains "origin") {
      & git remote add origin "https://github.com/$Repo.git"
      Write-Ok "ตั้ง remote origin"
    }
    $pushUrl = "https://x-access-token:$Token@github.com/$Repo.git"
    & git push $pushUrl HEAD:main 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) { Write-Err "push ไม่สำเร็จ"; exit 1 }
    Write-Ok "push ขึ้น $Repo แล้ว"
  } finally { Pop-Location }
}

if ($SkipFetch) { exit 0 }

# ---------------------------------------------------------------- สั่ง workflow
Write-Step "สั่ง workflow build"
$dispatch = @{ ref = "main" } | ConvertTo-Json
try {
  Invoke-RestMethod -Uri "$api/repos/$Repo/actions/workflows/$workflow/dispatches" -Method Post -Headers $headers -Body $dispatch -ContentType "application/json" | Out-Null
  Write-Ok "สั่ง build แล้ว (macos-26 / Xcode 26)"
} catch {
  Write-Warn2 "สั่งผ่าน API ไม่ได้: $($_.Exception.Message)"
  Write-Host "    ไปกด Run workflow เองที่: https://github.com/$Repo/actions/workflows/$workflow" -ForegroundColor Yellow
  exit 0
}

# ---------------------------------------------------------------- รอ + ดาวน์โหลด
Write-Step "รอผล build (ปกติ 5-15 นาที)"
$runId = $null
for ($i = 0; $i -lt 120; $i++) {
  Start-Sleep -Seconds 20
  try {
    $runs = Invoke-RestMethod -Uri "$api/repos/$Repo/actions/workflows/$workflow/runs?event=workflow_dispatch&per_page=1" -Headers $headers
    $run = $runs.workflow_runs | Select-Object -First 1
    if ($run -and $run.status -eq "completed") {
      $runId = $run.id
      if ($run.conclusion -eq "success") { Write-Ok "build สำเร็จ (run #$runId)" }
      else { Write-Err "build ล้มเหลว: $($run.conclusion)"; exit 1 }
      break
    }
    if ($run) { Write-Host "    ... $($run.status) / $($run.conclusion ?? 'running')" }
  } catch {
    Write-Host "    ... รออยู่"
  }
}
if (-not $runId) { Write-Err "หมดเวลารอ — เช็คใน Actions ด้วยตัวเอง"; exit 1 }

Write-Step "ดาวน์โหลด .ipa"
$art = Invoke-RestMethod -Uri "$api/repos/$Repo/actions/runs/$runId/artifacts" -Headers $headers
$ipaArtifact = $art.artifacts | Where-Object { $_.name -eq "ios-ipa" } | Select-Object -First 1
if (-not $ipaArtifact) { Write-Err "ไม่พบ artifact ios-ipa"; exit 1 }

$tmp = Join-Path $env:TEMP "ipa-$runId"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Path $tmp | Out-Null
$zip = Join-Path $tmp "artifact.zip"
Invoke-WebRequest -Uri "$api/repos/$Repo/actions/artifacts/$($ipaArtifact.id)/zip" -Headers $headers -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $tmp -Force

$ipa = Get-ChildItem -Path $tmp -Filter "*.ipa" -Recurse | Select-Object -First 1
if ($ipa) {
  $dest = Join-Path $root $ipa.Name
  Copy-Item $ipa.FullName $dest -Force
  Write-Ok "ได้ไฟล์: $dest"
  Write-Host ""
  Write-Host "  ติดตั้ง: เปิดด้วย LiveContainer / SideStore / AltStore" -ForegroundColor Cyan
  Write-Host "  (LiveContainer: Settings > Import Certificate > เลือกไฟล์ .ipa)" -ForegroundColor Cyan
} else {
  Write-Warn2 "ไม่พบไฟล์ .ipa ใน artifact"
}
