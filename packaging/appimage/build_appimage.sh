#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?uso: build_appimage.sh <versão>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG="$ROOT/packaging/appimage"
APPDIR="$ROOT/AppDir"
TOOL="$ROOT/.cache/appimagetool-x86_64.AppImage"

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

if [ ! -x "$TOOL" ]; then
  mkdir -p "$(dirname "$TOOL")"
  curl -fsSL -o "$TOOL" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$TOOL"
fi

mkdir -p dist
rm -f "dist/disk-cleanup-$VERSION-x86_64.AppImage"
ARCH=x86_64 "$TOOL" --appimage-extract-and-run \
  "$APPDIR" "dist/disk-cleanup-$VERSION-x86_64.AppImage"
echo "dist/disk-cleanup-$VERSION-x86_64.AppImage"
