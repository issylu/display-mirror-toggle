#!/bin/bash
set -e
cd "$(dirname "$0")"

swiftc -O -o DisplayToggle main.swift -framework Cocoa

rm -rf DisplayToggle.app
mkdir -p DisplayToggle.app/Contents/MacOS
cp DisplayToggle DisplayToggle.app/Contents/MacOS/DisplayToggle
cp Info.plist DisplayToggle.app/Contents/Info.plist

echo "編譯完成：$(pwd)/DisplayToggle.app"
echo "執行 open DisplayToggle.app 測試，或 cp -R DisplayToggle.app /Applications/ 安裝"
