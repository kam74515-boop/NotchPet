<h1 align="center">NotchPet 🦀</h1>

<p align="center">
  <b>An AI efficiency-island for the macOS notch.</b><br>
  <sub>一个带 AI 任务同步的「效率岛 / 灵动岛」刘海工具 — 番茄钟、待办、天气、歌词、桌宠……</sub>
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-black">
  <img alt="license" src="https://img.shields.io/badge/license-AGPL--3.0-blue">
  <img alt="status" src="https://img.shields.io/badge/status-early%20WIP-orange">
</p>

---

NotchPet turns your MacBook notch (or a simulated notch on any display) into a small,
glanceable control center — and connects it to your **AI coding agents**. Start a long
task in Claude Code, walk away, and the notch (with a little crab living inside it) tells
you the moment it's done.

It is built on top of the excellent open-source [**boring.notch**](https://github.com/TheBoredTeam/boring.notch)
(music, calendar, file shelf, webcam, HUD replacement) and re-implements the AI-agent
task-sync idea from [**clawd-on-desk**](https://github.com/rullerzhou-afk/clawd-on-desk)
natively in Swift.

> ⚠️ **Status: early work-in-progress.** All features are implemented in source, but the
> project still needs a full-Xcode compile pass to shake out build issues before it runs.
> See [Building](#building) and [Roadmap](#roadmap).

## Features

Inherited from boring.notch:
- 🎵 Music control center + visualizer (Now Playing / Apple Music / Spotify / YouTube Music)
- 📅 Calendar · 🗂️ File shelf with AirDrop · 🪞 Webcam mirror · 🔆 System HUD replacement

Added by NotchPet (nook-x-style 效率岛):
- 🍅 **Pomodoro** (番茄钟) — focus/break cycles with an in-notch live countdown
- ✅ **To-Do** (待办) — local tasks with optional due reminders
- 📝 **Notes** (便签) — quick scratchpad
- 🎤 **Synced lyrics** (歌词) — full scrolling, time-synced view
- 🌤️ **Weather** (天气) — current + forecast via Open-Meteo (no API key) + CoreLocation, with manual-city fallback
- 🖼️ **Photos** (照片) — browse a chosen folder with Quick Look
- 🚀 **Launcher** (快速启动) — favorite-app grid
- ⚡ **Quick Actions** (系统快捷指令) — sandbox-safe system shortcuts
- 💧 **Health reminders** (提醒) — water / sit-up / sleep nudges
- 🎛️ Customizable tabs (enable/reorder modules)

AI agent task sync (the headline 🦀):
- Real-time **in-notch pet** (🦀) that reacts to **Claude Code** (and compatible CLIs) right
  inside the notch: thinking → working → subagents → compacting → **done / error**
- ✅ **Completion notification** so you can walk away during long tasks
- 🧰 One-click **Claude Code hook install** (merges into `~/.claude/settings.json`, preserving your own hooks)
- 🧩 Multi-session tracking, an **Agents** tab, and optional permission bubbles
- Implemented as a loopback HTTP listener (no third-party deps); **off by default** until you enable it

## Building

Requires **macOS 14+** and **full Xcode** (Command Line Tools alone cannot build a SwiftUI app).

```bash
# Point the toolchain at Xcode
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept && xcodebuild -runFirstLaunch

# Open once in Xcode to generate/share the scheme, then build:
cd boring.notch
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build
```

For local runs use **Automatic signing → "Sign to Run Locally"** with a free personal team.
This is a non-App-Store, self-distributed app; the App Sandbox stays on (out-of-container
`~/.claude` access is handled by the bundled non-sandboxed XPC helper).

## Enabling AI agent sync

1. Open **Settings → AI Agents** and turn on **Enable agent sync**.
2. Click **Install / Repair** to add the hooks to `~/.claude/settings.json`.
3. Run any task in Claude Code — the notch and pet react live, and you get a notification on completion.

Nothing is installed or listened for until you opt in.

## Roadmap

- [ ] First full-Xcode compile pass (fix remaining build issues)
- [ ] NotchPet app icon / branding art
- [ ] Simplified-Chinese (zh-Hans) localization of new strings
- [ ] In-notch pet: import clawd-on-desk SVG/APNG theme packs (currently a native crab)
- [ ] Module drag-to-reorder UI

## Credits & License

NotchPet is a **fork and modified version** of:

- [**boring.notch**](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam — licensed **GPL-3.0**
- AI-agent sync re-derived from [**clawd-on-desk**](https://github.com/rullerzhou-afk/clawd-on-desk) by rullerzhou — licensed **AGPL-3.0**
- Pixel-lobster lineage from **OpenClaw** (Peter Steinberger) — MIT

Because it combines GPL-3.0 and AGPL-3.0 code, **the combined work is distributed under the
GNU Affero General Public License v3.0 (AGPL-3.0-only)**. See [`NOTICE.md`](NOTICE.md),
[`LICENSE`](LICENSE) (GPL-3.0) and [`LICENSE.AGPL-3.0.txt`](LICENSE.AGPL-3.0.txt).

Huge thanks to the upstream authors — please support [boring.notch](https://github.com/TheBoredTeam/boring.notch)
and [clawd-on-desk](https://github.com/rullerzhou-afk/clawd-on-desk).
