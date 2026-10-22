#!/bin/bash
# build-ipa.sh — สร้าง .ipa ของ iPhone Agent บนเครื่อง Mac (Xcode 15+ / iOS 26 SDK)
# ใช้:  cd iphone-agent && bash build-ipa.sh
set -euo pipefail

cd "$(dirname "$0")"
echo "==> ตรวจ Xcode"
xcodebuild -version

echo "==> ติดตั้ง dependency"
npm ci

echo "==> cap sync (www -> ios)"
npx cap sync ios

grep -q "AgentPlugin" ios/App/App/capacitor.config.json || { echo "❌ AgentPlugin ไม่ได้ register"; exit 1; }
grep -q "AgentPlugin" ios/App/CapApp-SPM/Package.swift || { echo "❌ AgentPlugin ไม่ได้อยู่ใน Package.swift"; exit 1; }

echo "==> build (Release / device)"
xcodebuild \
  -project ios/App/App.xcodeproj \
  -scheme App \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$HOME/dd-iphone-agent" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> ห่อเป็น .ipa"
APP_DIR="$HOME/dd-iphone-agent/Build/Products/Release-iphoneos/App.app"
[ -d "$APP_DIR" ] || { echo "❌ ไม่พบ App.app"; exit 1; }
rm -rf dist && mkdir -p dist/Payload
cp -R "$APP_DIR" dist/Payload/iPhoneAgent.app
(cd dist && zip -qry iPhoneAgent-unsigned.ipa Payload)
ls -lh dist/iPhoneAgent-unsigned.ipa

echo ""
echo "✅ ได้ไฟล์: $(pwd)/dist/iPhoneAgent-unsigned.ipa"
echo "   ติดตั้งผ่าน LiveContainer / SideStore / AltStore"
echo "   (ถ้าอยากได้ .ipa ที่ลงลายเซ็นชื่อคุณ ให้เปิดด้วย Xcode แล้ว Archive > Distribute App > Any iOS Device > Ad Hoc)"
