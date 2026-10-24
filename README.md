<p align="center"><img src="assets/hushtype-icon-512.png" width="128" alt="Hushtype"></p>

# Hushtype

Hold a key, speak, let go, and polished text appears in whatever app has focus. An open,
privacy-first alternative to Wispr Flow, built as a native macOS app in Swift and SwiftUI.

## What works today (MVP milestone 1)

- **Push-to-talk** on Right Option (default), Right Command, or Fn/🌐, captured system-wide with a `CGEventTap`.
  Pressing any other key while holding cancels, so normal shortcuts keep working.
- **Recording** from the default mic via `AVAudioEngine`, converted to 16 kHz mono WAV, with a floating
  "listening" pill and live level meter.
- **Speech to text** with Groq Whisper (`whisper-large-v3-turbo`), Deepgram Nova-3, or local
  [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for fully on-device dictation.
- **Cleanup** with Claude Haiku: removes fillers, fixes punctuation, applies self-corrections
  ("at 5, no, 6 pm" becomes "at 6 pm"). If cleanup fails, the raw transcript is inserted instead.
- **Insertion** by pasting into the focused app, then restoring your clipboard.
- **Personal dictionary** fed to both the speech engine and Claude.
- **Settings**: hotkey, language, engine, API keys (stored in the Keychain), permissions setup.
- Recent dictations in the menu bar (in memory for now), click to copy.

## Build and run

Requires macOS 14+ and Xcode 16 (or the Swift 5.10+ toolchain).

```sh
scripts/build-app.sh          # builds dist/Hushtype.app
open dist/Hushtype.app
```

You can also open `Package.swift` in Xcode to edit and debug, but permissions such as the microphone need the
bundled app from the script, since a bare executable has no `Info.plist`.

On first launch a short guided setup walks through **Microphone**, **Input Monitoring** and **Accessibility** (each
step notices the grant by itself and moves on, and restarts Hushtype for you when macOS requires it), checks your
Groq/Deepgram and Anthropic keys as you paste them, and ends with a practice field to try your first dictation.
Run it again any time from Settings › General.

macOS ties Accessibility and Input Monitoring grants to the code signature, and the default ad-hoc signature changes
with every build. To keep grants across rebuilds, create a self-signed code-signing certificate in Keychain Access
and build with `HUSHTYPE_SIGN_IDENTITY="Your Cert Name" scripts/build-app.sh`.

### Local mode

```sh
brew install whisper-cpp
mkdir -p ~/Library/Application\ Support/Hushtype/models
curl -L -o ~/Library/Application\ Support/Hushtype/models/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

Then pick "whisper.cpp (local, private)" under Engines. Turn off Claude cleanup too if nothing should leave your Mac.

## Layout

```
Sources/HushtypeCore/   pipeline logic: WAV encoding, STT engines, Claude cleanup (unit tested)
Sources/Hushtype/       the menu bar app: hotkey, recorder, overlay, paste, settings, Keychain
Tests/                  HushtypeCore tests (swift test)
Resources/Info.plist    app bundle metadata (LSUIElement, mic usage string)
scripts/build-app.sh    builds, icons and signs dist/Hushtype.app
```

## Next up

History persisted in SQLite, in-app model download for local mode, streaming STT to cut latency, per-app tone,
snippets, signed and notarized releases. See the project plan for the full roadmap.

## License

MIT
