#!/bin/zsh
# 엑셀자.app 빌드 후 ~/Applications 에 설치
set -e
cd "$(dirname "$0")"
A=~/Applications/엑셀자.app
mkdir -p "$A/Contents/MacOS"
cp Info.plist "$A/Contents/Info.plist"
swiftc -O -swift-version 5 main.swift -o "$A/Contents/MacOS/ExcelRuler" -framework Cocoa -framework Carbon
codesign -s - --force "$A"
echo "설치 완료: $A"
