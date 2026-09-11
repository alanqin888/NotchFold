#!/bin/bash
set -e

APP_NAME="NotchFold"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 正在编译 ${APP_NAME} (macOS 14.0+ / Metal GPU 管线)..."

mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 编译 Swift 源码
swiftc -O \
    -target arm64-apple-macos14.0 \
    -framework Cocoa \
    -framework QuartzCore \
    -framework IOKit \
    -framework AudioToolbox \
    -framework Metal \
    -framework MetalKit \
    -framework ScreenCaptureKit \
    -framework CoreVideo \
    -framework CoreMedia \
    Sources/FoldCore.swift \
    Sources/FoldShader.swift \
    Sources/FoldRenderer.swift \
    Sources/DesktopCapture.swift \
    Sources/Config.swift \
    Sources/LidMonitor.swift \
    Sources/NotchNotesManager.swift \
    Sources/FoldWindow.swift \
    Sources/NotchController.swift \
    Sources/main.swift \
    -o "${MACOS_DIR}/${APP_NAME}"

# 拷贝配置文件
cp Info.plist "${CONTENTS_DIR}/Info.plist"

# 本地 Ad-hoc 签名
codesign -s - --force --deep "${BUNDLE_DIR}" 2>/dev/null || true

echo "✅ 编译打包完成：${BUNDLE_DIR}"
