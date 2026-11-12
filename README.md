# Rounded Corners

Rounds the corners of a Mac's display with four small black panels. A MacBook's top corners are already rounded
by the glass, so there only the bottom ones are drawn up to 23 pt; above that all four are drawn. External
displays get every selected corner. One Objective-C file, system frameworks only, no icon in the menu bar or
Dock, 0% CPU at rest.

Opening the app shows a small window: launch at login, which corners to round, corner radius, quit. The same
settings can apply to every connected display, or each display can be configured on its own. Closing the window
keeps the corners active; quit with cmd+Q or "Quit Rounded Corners". Started at login it stays in the background. Once the window
is closed there is no Dock or menu bar icon: double-click the app in Applications to reopen it.

Corners stay fixed during Space swipes and show over full-screen apps and the lock screen via private SkyLight
calls; without them the app falls back to ordinary all-Spaces windows. macOS 13+, Apple Silicon only.

## Build

    ./build.sh            # build/Rounded Corners.app (arm64, ad-hoc signed)
    ./build.sh install    # also install in /Applications and launch
    ./build.sh zip        # build/RoundedCorners.zip, ready to share
    ./build.sh dmg        # build/RoundedCorners.dmg, ready to share (drag to Applications)
    ./build.sh test       # build and run the test suite

Use `./build.sh install` before ticking "Launch at login": the login item points at the bundle it was registered
from, so enabling it from `build/` leaves a broken entry as soon as `build/` is rebuilt.

The app is not notarized. On another Mac, after unzipping and moving it to /Applications, the first launch needs
right-click > Open, or: `xattr -dr com.apple.quarantine "/Applications/Rounded Corners.app"`.

## License

MIT.
