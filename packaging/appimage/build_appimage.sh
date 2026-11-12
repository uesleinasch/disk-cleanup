#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?uso: build_appimage.sh <versão>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG="$ROOT/packaging/appimage"
APPDIR="$ROOT/AppDir"
APPIMAGETOOL_VERSION="1.9.1"
APPIMAGETOOL_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"
TOOL="$ROOT/.cache/appimagetool-$APPIMAGETOOL_VERSION-x86_64.AppImage"

cd "$ROOT"
flutter build linux --release

rm -rf "$APPDIR"
mkdir -p "$APPDIR"
cp -r build/linux/x64/release/bundle/. "$APPDIR/"
install -m 755 "$PKG/AppRun" "$APPDIR/AppRun"
cp "$PKG/disk-cleanup.desktop" "$APPDIR/"
cp "$PKG/disk-cleanup.svg" "$APPDIR/disk-cleanup.svg"
cp "$PKG/disk-cleanup.png" "$APPDIR/.DirIcon"
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp "$PKG/disk-cleanup.svg" "$APPDIR/usr/share/icons/hicolor/scalable/apps/"
cp "$PKG/disk-cleanup.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/"

if [ ! -f "$TOOL" ]; then
  mkdir -p "$(dirname "$TOOL")"
  curl -fsSL -o "$TOOL.part" \
    "https://github.com/AppImage/appimagetool/releases/download/$APPIMAGETOOL_VERSION/appimagetool-x86_64.AppImage"
  mv "$TOOL.part" "$TOOL"
fi
if ! echo "$APPIMAGETOOL_SHA256  $TOOL" | sha256sum -c --status; then
  rm -f "$TOOL"
  echo "appimagetool: sha256 não confere" >&2
  exit 1
fi
chmod +x "$TOOL"

mkdir -p dist
rm -f "dist/disk-cleanup-$VERSION-x86_64.AppImage"
ARCH=x86_64 "$TOOL" --appimage-extract-and-run \
  "$APPDIR" "dist/disk-cleanup-$VERSION-x86_64.AppImage"
echo "dist/disk-cleanup-$VERSION-x86_64.AppImage"
