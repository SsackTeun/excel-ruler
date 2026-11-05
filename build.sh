#!/bin/zsh
# 엑셀자.app 빌드 (애플 실리콘 + 인텔, macOS 12 이상)
#   ./build.sh            → ~/Applications 에 설치
#   OUT=dist ./build.sh   → dist/ 에만 만듦 (배포용)
set -e
cd "$(dirname "$0")"
OUT_DIR=${OUT:-~/Applications}
A="$OUT_DIR/엑셀자.app"
TMP=$(mktemp -d)
mkdir -p "$A/Contents/MacOS"
cp Info.plist "$A/Contents/Info.plist"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos12.0 main.swift -o "$TMP/ExcelRuler-$arch" -framework Cocoa -framework Carbon
done
lipo -create "$TMP"/ExcelRuler-* -output "$A/Contents/MacOS/ExcelRuler"
rm -rf "$TMP"
# 개발자 인증서가 있으면 그걸로 서명 (다시 빌드해도 macOS 권한이 유지됨), 없으면 임시 서명
ID=$(security find-identity -v -p codesigning 2>/dev/null | awk -F\" '/Apple Development|Developer ID/ {print $2; exit}')
codesign -s "${ID:--}" --force "$A"
echo "완료: $A"
