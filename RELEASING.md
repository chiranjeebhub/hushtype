# Releasing Hushtype

Running `.github/workflows/release.yml` by hand (Actions › Release › Run workflow) builds Hushtype, signs it with your
Developer ID, notarizes it with Apple, and publishes a GitHub release with:

- `Hushtype-<version>.dmg` for people downloading it,
- `Hushtype-<version>.zip` and `appcast.xml` for Sparkle, which installed copies check for updates.

Installed copies read `https://github.com/chiranjeebhub/hushtype/releases/latest/download/appcast.xml`, so the
newest release is always the update.

## One-time setup

You need a paid Apple Developer Program membership (Developer ID certificates and notarization aren't available
on a free account).

1. **Developer ID certificate.** In Xcode › Settings › Accounts › Manage Certificates, click + and choose
   *Developer ID Application*. Then in Keychain Access, find "Developer ID Application: …", right-click ›
   Export, and save it as a `.p12` with a password.
2. **App Store Connect API key** for notarization. At
   [App Store Connect › Users and Access › Integrations › Team Keys](https://appstoreconnect.apple.com/access/integrations/api),
   create a key with the *Developer* role. Download the `.p8` (you can only download it once) and note the
   Key ID and Issuer ID.
3. **Sparkle signing keys.** After any `swift build`, run
   `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account hushtype`. It saves the private key in your login
   keychain under its own `hushtype` account (so it isn't shared with other apps) and prints the public key.
   Export the private key with `generate_keys --account hushtype -x sparkle-private-key.txt`.
4. **GitHub settings** (repository › Settings › Secrets and variables › Actions):

   | Kind | Name | Value |
   |---|---|---|
   | Secret | `DEVELOPER_ID_P12_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy`, then paste |
   | Secret | `DEVELOPER_ID_P12_PASSWORD` | the `.p12` password |
   | Secret | `ASC_KEY_P8` | contents of the `.p8` file |
   | Secret | `ASC_KEY_ID` | the key ID |
   | Secret | `ASC_ISSUER_ID` | the issuer ID |
   | Secret | `SPARKLE_PRIVATE_KEY` | contents of `sparkle-private-key.txt` (then delete the file) |
   | Variable | `SPARKLE_PUBLIC_KEY` | the public key from `generate_keys` |

Keep the Sparkle private key safe: every future update must be signed with it, or installed copies will refuse it.

## Cutting a release

Releases are usually made from your Mac (below), which also embeds the iCloud provisioning profile. Pushing a tag
no longer starts the workflow, so a release made on the Mac doesn't trigger a duplicate run. To release from GitHub
instead, open Actions › Release › Run workflow and enter the version, e.g. `0.3.3`; the build number comes from the
workflow run.

## Releasing from your Mac instead

```sh
xcrun notarytool store-credentials hushtype   # once; asks for the API key or an app-specific password
HUSHTYPE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
HUSHTYPE_NOTARY_PROFILE=hushtype \
HUSHTYPE_SPARKLE_PUBLIC_KEY="<public key>" \
HUSHTYPE_PROVISIONING_PROFILE=path/to/Hushtype_DeveloperID.provisionprofile \
scripts/release.sh 0.2.0
```

Without `SPARKLE_PRIVATE_KEY`, `sign_update` uses the key stored in your keychain by
`generate_keys --account hushtype` (the script passes `--account hushtype`; set `HUSHTYPE_SPARKLE_ACCOUNT` to use
another account). Upload the
three files in `dist/` to a GitHub release tagged `v0.2.0`.

## Development builds

`scripts/build-app.sh` builds without the hardened runtime and without a Sparkle key, so auto-updates stay off
and Settings shows "Development build". Sign with any stable identity to keep macOS permission grants across
rebuilds.
