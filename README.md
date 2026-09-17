# Pier

Project: `pier-app`. A personal macOS dock. App launcher plus live tiles for Cursor (with running
agents as a subtitle) and weather. It is a separate overlay, not an addition
to Apple's Dock.

## Build

```bash
./build.sh --install     # build, copy to /Applications, launch
./build.sh               # build only, into ./build
./build.sh --release     # notarize, staple, write ./build/Pier-0.1.0.zip
./build.sh --publish     # --release, then upload that zip to GitHub Releases
```

On a machine without `/Applications` write access or a Swift toolchain,
download the zip from [Releases](https://github.com/thewhatmatters/pier/releases)
and extract it with Archive Utility or `ditto` — not `unzip`, which breaks
the signature:

```bash
mkdir -p ~/Applications
ditto -x -k Pier-0.1.0.zip ~/Applications
open ~/Applications/Pier.app
```

While Pier is running, Apple's Dock is hidden by default (auto-hide plus a
long hover delay so it does not pop up over our tiles). The menu bar extra
(the half-filled rectangle) has **Quit Pier** — that restores Apple's Dock
and exits. **Hide macOS Dock** turns the replacement off if you want both
while Pier stays open.

A copy of the strip appears on every connected display, and follows
displays as they are plugged in or removed.

The bar uses a 16pt corner radius. Drag the top edge to grow or
shrink the tiles. Drag an app or widget sideways to mix them in
any order.

Widgets are glass tiles on the glass bar — same stippled glyphs,
horizontal and minimal. Type is Geist / Geist Mono; glyphs flip
with the bar so they stay readable on the frost.

The strip defaults to dark glass. The menu bar toggle **Dark Mode**
switches to a light bar.

## What the tiles show

| Tile | Source |
| --- | --- |
| Apps | Seeded from your current macOS Dock pins; click to launch or activate. Right-click for Open, Hide, Quit (Option for Force Quit), Show in Finder, and Remove from Pier |
| Cursor | Running or off, plus the open project. Subtitle lists repos with a live turn under `~/.cursor/projects/*/agent-transcripts` — never the first prompt. The tile refreshes on the dock pulse; transcripts are rescanned at most every ~8s. A session is working until Cursor writes `turn_ended`. Cloud sessions (`bc-` ids) are included when they write locally |
| Docker | Container name from `docker ps -a`. Subtitle is how long a running container has been up (`Up 4h`), otherwise Stopped. Arrows cycle containers. The Docker Desktop pin folds into this tile. Hidden if Docker Desktop and the `docker` CLI are both missing. Click opens Docker Desktop |
| Activity | System / User / Idle from `HOST_CPU_LOAD_INFO`, plus a sparkline of load over the last ~30s. Activity Monitor’s pin folds into this tile. Click opens Activity Monitor |
| Calendar | Today's events from EventKit. Shows the meeting in progress or the next one, plus how many more. Click opens Calendar.app |
| Weather | Refreshes every 15 minutes. Prefers Apple Weather via WeatherKit (500k calls/month included with the Developer Program). Location from Core Location, IP if that is denied. Falls back to Open-Meteo until App ID `so.whatmatters.pier` has the WeatherKit capability enabled — that fallback can sit a few degrees off Weather.app. Click opens Weather.app |

Cloud agents that never write a local transcript still will not appear.

## Command line

```bash
./build.sh
.build/release/Pier --selftest
.build/release/Pier --status
.build/release/Pier --render /tmp/pier
```
