# Releasing

How to cut a new release DMG. (Owner-facing — users just download from [Releases](https://github.com/nhershy/Grok-macOS/releases).)

## One-time setup

Notarization needs stored credentials. Create an **app-specific password** at
[account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords, then run:

```sh
xcrun notarytool store-credentials "grok-notary" --apple-id <your-apple-id> --team-id 9AZ9MMS68X
```

Paste the app-specific password when prompted. This stores it in the keychain; the release script references it as `grok-notary`.

## Cutting a release

1. Bump **MARKETING_VERSION** (and **CURRENT_PROJECT_VERSION**) in Xcode: target *Grok-macOS* → Build Settings → Versioning.
2. Run the release script from the repo root:

   ```sh
   ./scripts/release.sh
   ```

   It archives a Release build, signs it with the Developer ID certificate, notarizes the app and the DMG with Apple (two waits of ~1–5 minutes each), staples the tickets, and verifies everything with `stapler validate` and `spctl`. Output lands at `dist/Grok-<version>.dmg`.

3. Publish it:

   ```sh
   gh release create v<version> dist/Grok-<version>.dmg --title "Grok <version>" --notes "What changed"
   ```

## Notes

- The first `xcodebuild ... -allowProvisioningUpdates` run may prompt for keychain access to the signing key — click **Always Allow**.
- If notarization is rejected, the script prints the `xcrun notarytool log <id>` command that shows Apple's reasons.
- If the credential check fails (e.g. the app-specific password was revoked), redo the one-time setup above.
