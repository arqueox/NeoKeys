<p align="center">
  <img src="Resources/NeoKeys.png" width="180" alt="NeoKeys icon">
</p>

# NeoKeys

[![Downloads](https://img.shields.io/github/downloads/arqueox/NeoKeys/total?style=for-the-badge&logo=github&label=Downloads)](https://github.com/arqueox/NeoKeys/releases)
[![Latest release](https://img.shields.io/github/v/release/arqueox/NeoKeys?style=for-the-badge&label=Version)](https://github.com/arqueox/NeoKeys/releases/latest)
[![License](https://img.shields.io/github/license/arqueox/NeoKeys?style=for-the-badge)](LICENSE)

Satisfying keyboard sounds, built exclusively for the **MacBook Neo**.

NeoKeys is a small native macOS menu bar app that plays recordings of physical keyboards as you type. It never stores or transmits what you type.

> Official compatibility: MacBook Neo `Mac17,5`, macOS 14 or later. MacBook Air, MacBook Pro, iMac, Mac mini, and other Mac models are not supported.

## Features

- Discreet menu bar app with no Dock icon
- **Cherry Real:** 12 recordings of physical key presses
- **Real Typewriter:** distinct sounds for regular keys, Space, Return, and Backspace
- Additional Butterfly, Thock, Clicky, Creamy, Typewriter, and Soft profiles
- **Pain Mode (Fun Lab):** cartoon groans on every key and a dramatic scream on Enter
- Overlapping playback that keeps up with fast typing
- Persistent sound profile, volume, and enabled state
- Optional launch at login
- Fully local operation with no analytics or network access

### Fun Lab

Pain Mode is an intentionally silly, family-friendly sound profile. Regular keys produce varied cartoon "ow" sounds, Space groans, Delete sighs, and Enter screams dramatically. Its session-only counters track `Keys hurt`, `Enters traumatized`, and the keyboard's fictional wellbeing. No key content or counters are stored.

> Every key suffers. Enter screams the loudest. **Support your keys. Type gently.**

## Installation

1. Download `NeoKeys.zip` from the [latest release](../../releases/latest).
2. Extract it and move `NeoKeys.app` to `/Applications`.
3. Open the app. This is a community build without Apple notarization, so you may need to right-click it and select **Open** the first time.
4. Grant access under **System Settings → Privacy & Security → Input Monitoring**.
5. Quit and reopen the app if requested by macOS.

The menu should display **Global detection active**. Use **Test sound** to verify your audio output.

## Privacy

NeoKeys uses a read-only `CGEventTap` to receive each key's physical code and select a matching sound. It does not reconstruct words, store keystrokes, use the network, or collect data. See [PRIVACY.md](PRIVACY.md).

## Build from source

Requires Xcode Command Line Tools and Swift 6 or later.

```sh
git clone https://github.com/arqueox/NeoKeys.git
cd NeoKeys
chmod +x build-app.sh
./build-app.sh
```

The application will be created at `dist/NeoKeys.app`.

## Sounds and licenses

NeoKeys source code is released under the MIT License. Bundled recordings retain their respective CC0 and MIT licenses. Review [Resources/Sounds/ATTRIBUTION.md](Resources/Sounds/ATTRIBUTION.md) before redistributing the audio assets.

## Project status

NeoKeys is a community project designed exclusively for the MacBook Neo. Bug reports and contributions are welcome through GitHub Issues.

View live public statistics on the [NeoKeys dashboard](https://arqueox.github.io/NeoKeys/).
