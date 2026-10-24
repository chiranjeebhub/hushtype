# Contributing to Hushtype

Thanks for helping out. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug or idea

Open an [issue](https://github.com/chiranjeebhub/hushtype/issues). For a bug, include your macOS version, the
Hushtype version (Settings › General), the app you were dictating into, and what you expected to happen.
Please don't paste your Anthropic API key or private dictation text.

## Building

You need macOS 26 or later and Xcode 26 (or the Swift 6.2+ toolchain).

```sh
swift build                   # compile
swift test                    # run the HushtypeCore tests
scripts/build-app.sh debug    # build dist/Hushtype.app with Info.plist, icon and signature
open dist/Hushtype.app
```

Run the app from the bundle the script builds, not the bare executable: microphone and Accessibility permissions
need the `Info.plist`. To keep those grants across rebuilds, sign with a stable identity (see the top of
`scripts/build-app.sh`):

```sh
HUSHTYPE_SIGN_IDENTITY="Your Cert Name" scripts/build-app.sh debug
```

If permissions get stuck after switching identities, reset them with `tccutil reset All app.hushtype.Hushtype`
and relaunch.

## Where things live

- `Sources/HushtypeCore/` holds the pipeline logic (speech-to-text, Claude cleanup). Keep it free of UI code and
  cover changes with tests in `Tests/`.
- `Sources/Hushtype/` is the menu bar app: hotkey, recorder, overlay, paste, settings.
- `docs/` is the website at hushtype.chiranjeeb.dev.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Keep each PR to one change, and match the style of the code around it.
3. Run `swift test` and try the change in the built app. For UI changes, add a screenshot to the PR.
4. Open the PR against `main` and describe what changed and why.

CI builds, tests and packages the app on a macOS 26 runner for every PR (`.github/workflows/ci.yml`), and a PR
needs a green build before it is merged. Releases are cut by the maintainer (see [RELEASING.md](RELEASING.md)).

## Privacy

Hushtype reads audio and text near the cursor, so changes that send data off the Mac get extra scrutiny. Today
Hushtype itself only talks to Anthropic (cleanup) and the Sparkle update feed, plus iCloud key-value sync when
enabled. Call out any new network call clearly in
your PR.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
