# Accessibility permission & persisted state (dev notes)

Two things that surprise people running **locally built** Mos. Neither is a bug
in Mos's detection logic — both come from how macOS keys permissions and caches
preferences.

## 1. "I granted Accessibility but Mos still won't get past the welcome screen"

### What's happening
Mos detects permission with the canonical API `AXIsProcessTrusted()`
(`Mos/Utils/Utils.swift`), polled from the welcome / introduction windows and
`AppDelegate.startWithAccessibilityPermissionsChecker`. That call returns
`false` until the **exact code signature** of the running binary has been
granted Accessibility.

macOS TCC keys an Accessibility grant by *(bundle id + code-signing
requirement)*, **not** by bundle id alone:

| Build | Bundle id | Signature |
|-------|-----------|-----------|
| Homebrew cask `brew install --cask mos` | `com.caldis.Mos` | Developer ID + **notarized** |
| Your local **Release** archive | `com.caldis.Mos` | "Apple Development" / ad-hoc |
| Your local **Debug** build | `com.caldis.Mos.debug` | "Apple Development" / ad-hoc |

So a local **Release** build has the *same bundle id* as the cask but a
*different signature*. System Settings shows a single "Mos" entry; the grant
behind it matches the notarized signature, so your locally built `com.caldis.Mos`
is **not** actually trusted and `AXIsProcessTrusted()` stays `false` — exactly
the "granted but not detected" symptom. Rebuilding can also rotate the cdhash,
leaving a *stale* checked-but-untrusted entry.

This is why the cask works and a local build of the **same tag** does not — the
difference is signing/notarization, not the source.

### What to do
- **Prefer the Debug build for development.** It already uses a distinct bundle
  id (`com.caldis.Mos.debug`, product name "Mos Debug"), so its permission and
  settings never collide with an officially installed cask. Grant Accessibility
  to **"Mos Debug"** once and it sticks.
- If you must test a **Release** archive alongside the cask, either uninstall the
  cask first, or notarize your archive so its signature matches release
  expectations (see the `release-preparation` skill).
- When a grant goes stale ("checked but not trusted"), reset it:
  ```sh
  bash scripts/dev/reset-mos-state.sh
  ```
  then relaunch and re-grant. (Manual equivalent:
  `tccutil reset Accessibility com.caldis.Mos` / `...Mos.debug`, then toggle the
  entry off/on in System Settings.)

> Note: there is no Swift-side workaround. An app cannot make
> `AXIsProcessTrusted()` return `true` for a signature TCC hasn't trusted —
> that's the security model working as intended.

## 2. "App Cleaner / `brew zap` won't fully remove my settings / button config"

### Where the data lives
**Everything** Mos persists — scroll options *and* the button bindings — is in
`UserDefaults.standard` (`Mos/Options/Options.swift`; bindings are a JSON blob
under the `Button.Bindings` key). There is no separate config file. On disk that
is one plist per build:

```
~/Library/Preferences/com.caldis.Mos.plist          # Release / cask
~/Library/Preferences/com.caldis.Mos.debug.plist    # Debug build
```

Mos is **not** sandboxed (it needs Accessibility), so there is no
`~/Library/Containers/...` copy.

### Why deleting the file doesn't stick
`UserDefaults` is fronted by the `cfprefsd` daemon, which keeps each domain
cached in memory and rewrites the `.plist` on its own schedule. If you `rm` the
file (which is what App Cleaner / `brew zap` do) while cfprefsd still holds the
domain, it simply writes your settings back — so after reinstall your button
config "reappears".

### Clean removal
Quit Mos, then go through cfprefsd and flush it:
```sh
bash scripts/dev/reset-mos-state.sh
```
which runs, for both `com.caldis.Mos` and `com.caldis.Mos.debug`:
```sh
defaults delete <id>                                   # clears via cfprefsd
rm -f ~/Library/Preferences/<id>.plist                 # + ByHost variant
killall cfprefsd                                        # respawns clean
```
Doing `defaults delete` + `killall cfprefsd` (not just `rm`) is the part App
Cleaner / `brew zap` miss.
