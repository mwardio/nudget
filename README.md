<p align="center">
  <img src="Assets/NudgetIcon.png" alt="Nudget icon" width="128">
</p>

<h1 align="center">Nudget</h1>

<p align="center">
  A tiny macOS menu-bar app that nudges the pointer so your Mac never looks idle.
</p>

---

Nudget moves your pointer one pixel to the right, one pixel back, and returns it
to where it started. It does this on a timer, anywhere from every 15 seconds to
every 5 minutes, from a little nugget in the menu bar. That is the entire
feature set.

I wrote it because I wanted a mouse jiggler I could read from top to bottom:
one Swift file, Apple frameworks only, nothing installed system-wide, and no
`sudo`. It never clicks, never types, and never touches anything other than the
pointer position.

## Install

Download the zip from the
[latest release](https://github.com/mwardio/nudget/releases/latest), unzip it,
and drop `Nudget.app` into `/Applications`. Release builds are universal,
signed with my Developer ID, and notarized, so macOS opens them without
complaint. Nudget needs macOS 13 or later.

Nudget has no Dock icon and no window; look for the nugget in your menu bar.

## Building from source

You need the Xcode Command Line Tools (`xcode-select --install`). There is no
Xcode project and no package manager.

```sh
git clone https://github.com/mwardio/nudget.git
cd nudget
./build.sh
open build/Nudget.app
```

`build.sh` compiles `NudgetApp.swift` for both Apple silicon and Intel, renders
the icon into an `.icns`, assembles the `.app` bundle, and signs it. Local
builds are ad-hoc signed, which is fine for your own Mac. Set
`CODESIGN_IDENTITY` to a Developer ID Application identity for a build you
can hand to someone else.

If you want **Launch at Login** to keep working across rebuilds, move
`Nudget.app` into `/Applications` (or `~/Applications`) before turning it on.

Releases are cut from my Mac with `./release.sh <version>`, which signs with
the Developer ID, notarizes and staples the app, and publishes the zip.

## Accessibility permission

Synthetic pointer movement sits behind the macOS Accessibility permission.
Nudget does not nag you for it on launch; its menu simply shows
**Grant Accessibility…** until it has been granted. Choose that, enable Nudget
under **System Settings → Privacy & Security → Accessibility**, then open the
menu again. Nudget notices and starts on its own.

This is a per-user setting, not an admin one. Release builds carry a stable
signing identity, so the permission survives updates. Local ad-hoc builds do
not: macOS treats every rebuild as a new app and asks again.

## The menu

- **Start Nudging / Stop Nudging** toggles the timer. The icon dims while paused.
- **Nudge Now** fires one immediately.
- **Interval** offers 15 s, 30 s, 1 min, 2 min, or 5 min.
- **Launch at Login** uses the native login-item service, `SMAppService`.
- **Open Accessibility Settings…** jumps straight to the privacy pane.

Your interval and running state persist between launches.

## How it works

Every tick, Nudget posts three `mouseMoved` events through Core Graphics at the
HID event tap: one pixel right, one pixel left, then the original position.
macOS treats these as real input and resets its idle timer. The pointer ends up
exactly where it was.

You can watch it happen. macOS exposes the time since the last input event as
`HIDIdleTime`, in nanoseconds:

```sh
ioreg -c IOHIDSystem | grep HIDIdleTime
```

With Nudget paused the number climbs. While it runs, it drops to near zero
after each nudge.

## Caveats

Nudget makes macOS register pointer activity. Presence indicators in chat and
monitoring apps can use other signals, so Nudget does not claim to control what
they show.

If all you need is to keep the display awake, macOS already ships
`caffeinate -d`, which does that without moving anything.

## License

[MIT](LICENSE)
