#!/bin/sh
# ./build.sh          build ./build/Rounded Corners.app (arm64, ad-hoc signed)
# ./build.sh install  build, replace /Applications/Rounded Corners.app and launch it
# ./build.sh zip      build and create ./build/RoundedCorners.zip to share
# ./build.sh test     build and run unit & UI lifecycle test suite
set -e
cd "$(dirname "$0")"
APP="build/Rounded Corners.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
clang -fobjc-arc -Os -arch arm64 -mmacosx-version-min=13.0 -Wall -Wextra -Werror \
  -framework AppKit -framework QuartzCore -framework ServiceManagement \
  -Wl,-dead_strip -o "$APP/Contents/MacOS/Rounded Corners" src/main.m
strip -x "$APP/Contents/MacOS/Rounded Corners"
cp src/Info.plist "$APP/Contents/Info.plist"
cp resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - --identifier com.roundedcorners.RoundedCorners "$APP"
codesign --verify --deep --strict "$APP"
case "$1" in
  test)
    clang -fobjc-arc -Os -arch arm64 -mmacosx-version-min=13.0 -Wall -Wextra -Werror \
      -framework AppKit -framework QuartzCore -framework ServiceManagement \
      tests/test_ui_lifecycle.m -o build/test_ui_lifecycle
    ./build/test_ui_lifecycle
    echo "All tests passed!" ;;
  install)
    pkill -f "Rounded Corners.app/Contents/MacOS" || true; sleep 1
    rm -rf "/Applications/Rounded Corners.app"
    ditto "$APP" "/Applications/Rounded Corners.app"
    open "/Applications/Rounded Corners.app" ;;
  zip)
    ditto -c -k --keepParent "$APP" build/RoundedCorners.zip
    echo "build/RoundedCorners.zip" ;;
esac
