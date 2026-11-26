# Hello-IT 1.7 deployment hardening

Notes for building, signing, notarizing, and deploying Hello IT on modern macOS.

ScriptedItem remains on the **main queue** (the earlier 1.7 experiment that moved it to a background queue is not used here).

## Configurator Mode

**Configurator Mode…** stays hidden until the user **⇧⌥-clicks** the Hello IT status item. After unlock it remains available for that user (`configuratorModeUnlocked`). Use **Apply & Reload** for a local preview, or **Export** for plist / `.mobileconfig` / bash (`defaults import`), including **All three…** under one name.

Fleet hide (blocks unlock):

```bash
defaults write com.github.ygini.Hello-IT disableConfiguratorMode -bool YES
```

Or deploy `example/HelloIT-DisableConfigurator.mobileconfig`.

Details: [configurator.md](configurator.md).

## Packaging changes

- Packaging uses `notarytool` + keychain profile (replaces deprecated `altool`)
- Universal build of HITDevKit then Hello IT (`x86_64` + `arm64`)
- Minimum macOS **12.0** (intentional vs older 1.7 betas that targeted 10.14.6 — required by current Xcode / SDKs)
- Entitlements trimmed to Apple Events + `disable-library-validation` (needed for `.hitp` plugins under Application Support)
- Default preference `denyUserWritableScript` = **YES** (refuse user-writable scripts/commands)
- OpenResource: optional `hideIfNotAvailable` for `file://` URLs
- ScriptedItem logs include the script basename

## Signing / notarization

Store credentials once:

```bash
xcrun notarytool store-credentials
```

Override vendor defaults when building your own copy:

```bash
export CUSTOM_DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
export CUSTOM_DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAMID)"
export CUSTOM_NOTARIZATION_KEYCHAIN_PROFILE="your-profile-name"
# optional local Team ID for Xcode (gitignored):
# src/CustomSettings.xcconfig → DEVELOPMENT_TEAM / CODE_SIGN_IDENTITY
./package/BuildAndPackage.command
```

Local test helpers (not for shipping):

```bash
export FORCE_SKIP_REPO_STATE=1   # allow dirty tree
export FORCE_RELEASE=1           # Release config on feature branches
export SKIP_NOTARIZATION=1       # skip notarytool/stapler
```

Packaging stages under `/tmp` then copies the finished pkg into `package/build/…`. That avoids Desktop/iCloud File Provider re-stamping `com.apple.FinderInfo`, which breaks `codesign --options runtime`.

## Fleet preference: writable scripts

Default is deny. To allow (not recommended on managed Macs):

```bash
defaults write com.github.ygini.Hello-IT denyUserWritableScript -bool NO
```

Keep CustomScripts root-owned and not user-writable:

```text
/Library/Application Support/com.github.ygini.hello-it/CustomScripts
```

## App Transport Security

`NSAllowsArbitraryLoads` remains enabled so **TestHTTP** / **CachetHQ** can hit admin-configured HTTP(S) endpoints. If your fleet never uses those plugins, you can rebuild with ATS tightened.

## MDM: PPPC (Privacy Preferences Policy Control)

Grant only what your scripts actually need. Typical Hello IT itself needs:

| Service | Subject | Why |
|---|---|---|
| AppleEvents | Hello IT → System Events / other apps | Only if your items/scripts drive UI or other apps |
| SystemPolicyAllFiles / FDA | Usually **not** for Hello IT.app | Prefer granting FDA to the **shell/interpreter** your scripts call, if required |
| Accessibility | Only if a script needs it | Prefer scoping to the script helper, not the menu-bar app |

Bundle ID (upstream): `com.github.ygini.Hello-IT`  
LaunchAgent label: `com.github.ygini.hello-it`  
Install path: `/Applications/Utilities/Hello IT.app`

After you re-sign with your Team ID, use **your** TeamID / CDHash in profiles — not Yoann’s `CRXPBZF3N4` unless you ship his notarized build unchanged.

## MDM: AllowedBinaries / execution policy

On recent macOS releases that enforce allowed binaries, allow Hello IT and every interpreter your ScriptedItem / Command items invoke, for example:

- `/Applications/Utilities/Hello IT.app/Contents/MacOS/Hello IT` (TeamID or CDHash)
- `/bin/bash`, `/bin/zsh`, `/usr/bin/python3`, etc. as used by your CustomScripts
- Any helper tools scripts call (`networksetup`, `system_profiler`, MSC helpers, …)

Mismatch here often looks like “menu item does nothing” rather than a Hello IT crash.

## Smoke test checklist

1. Status item appears; menu opens
2. MDM/profile change rebuilds menu (`com.apple.MCX._managementStatusChangedForDomains`)
3. ScriptedItem title + periodic-run + click `run`
4. Command item
5. OpenApplication / OpenResource (and `hideIfNotAvailable` for a missing `file://` path)
6. ADPass only if you use it
7. Configurator unlock (⇧⌥-click), Apply & Reload, Export
8. Confirm writable-script denial: temporarily make a CustomScript user-writable and ensure it is refused with `denyUserWritableScript` left at default
