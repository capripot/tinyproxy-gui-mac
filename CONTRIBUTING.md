# Contributing to Tinyproxy GUI

Thanks for helping out! Tinyproxy GUI is a small native macOS front end for [tinyproxy](https://tinyproxy.github.io/), the light-weight HTTP/HTTPS proxy daemon, as installed through Homebrew.

Bugs in tinyproxy itself (proxying, filtering, configuration directives) belong in the [tinyproxy project](https://github.com/tinyproxy/tinyproxy/issues), not here. This repository is only about the macOS app that monitors and controls it.

The app is deliberately small. The guidelines below are meant to keep it small, predictable and easy to understand.

## Getting started

You need macOS 13+, [Homebrew](https://brew.sh/), and the Swift 6 toolchain. The Xcode Command Line Tools are enough (`xcode-select --install`); you don't need the full Xcode.

```sh
git clone https://github.com/capripot/tinyproxy-gui.git
cd tinyproxy-gui

swift build                 # debug build, quick compile check
swift run                   # run the debug build without an .app bundle
./scripts/build-app.sh      # universal release build packaged as build/Tinyproxy.app
open build/Tinyproxy.app
./scripts/make-dmg.sh       # build/Tinyproxy-<version>.dmg for distribution
```

`swift run` works for quick iterations, but test the final behavior with the `.app` from `build-app.sh`. That's the only setup where the icon, `Info.plist` and the Finder launch environment (no shell `PATH`) apply.

There's no Xcode project. If you prefer Xcode, open `Package.swift` with it. Don't commit generated `.xcodeproj` or `.swiftpm` files; they're in `.gitignore`.

## Project layout

```
Package.swift                     SwiftPM manifest (one executable target, no dependencies)
Sources/TinyproxyGUI/
  TinyproxyGUIApp.swift           App entry point, window scene, menu commands
  ContentView.swift               The window's UI
  TinyproxyMonitor.swift          State, refresh logic, watchers, actions, log lookup
  Brew.swift                      Locating and running `brew`, decoding its JSON
Resources/
  Info.plist                      Bundle metadata, copied in by build-app.sh
  AppIcon.svg                     Icon source
  AppIcon.icns                    Generated icon, committed
  StatusIcon.svg                  Menu bar icon source (monochrome outline of the AppIcon character)
  StatusIcon.tiff                 Generated menu bar icon (1x and 2x), committed
scripts/
  build-app.sh                    Builds the universal release .app bundle into build/
  make-dmg.sh                     Runs build-app.sh, then packages the app as a .dmg
  make-icon.sh                    Regenerates AppIcon.icns and StatusIcon.tiff from their SVGs
```

## How the code fits together

- **`Brew`** is the only code that runs external commands. It finds the `brew` executable (Finder-launched apps don't inherit the shell `PATH`), runs commands off the main thread, and decodes `brew info --json=v2` and `brew services info --json`. Read both stdout and stderr fully before waiting for exit, so that verbose commands like `brew install` can't fill a pipe buffer and hang.
- **`TinyproxyMonitor`** is a `@MainActor` `ObservableObject` and the single source of truth for the UI. `refresh()` handles overlapping calls: if a refresh is already in progress, it queues exactly one follow-up instead of running two at once.
- **Change detection** has three layers. Keep all three if you change it:
  1. A kqueue process-exit watcher on tinyproxy's PID, for an immediate refresh when it dies.
  2. A watcher on `~/Library/LaunchAgents`, with a 1.5s debounce, to catch `brew services` run from a terminal.
  3. A 60-second fallback poll. Don't poll more often than once a minute; each check starts two Ruby `brew` processes.
- **Start/Stop** waits for the service to actually reach the target state, because `brew services` returns as soon as launchd has loaded or unloaded the job. The wait times out after `serviceChangeTimeout` (30s).

## Guidelines

- **Ask before changing the system.** The app must never install, upgrade or uninstall anything without an explicit user action, whether that's a confirmation alert or a button press. Starting and stopping the service only happens from the button or the menu.
- **Use Homebrew for everything.** Manage tinyproxy only through `brew` and `brew services`, not by calling `launchctl` directly or editing files Homebrew owns. Reading `tinyproxy.conf` is fine; writing it is out of scope.
- **No third-party dependencies.** SwiftUI, AppKit and Foundation are enough.
- **Keep the deployment target at macOS 13** unless a change really needs something newer. If it does, explain why in the PR.
- **Swift 6 language mode with strict concurrency.** The package must build with no compiler warnings (the linker's "search path not found" warnings from Command Line Tools are expected).
- **Match the surrounding style.** Four-space indentation, small focused types, and short comments that explain *why* rather than *what*.
- **Keep the UI steady.** Controls shouldn't jump around or disappear while something is in progress. Disable them and show the spinner instead.

## Testing your changes

There's no automated test suite yet. Before opening a PR, run through these scenarios with the `.app` build:

- [ ] **Running → Stop**: the button greys out with a spinner, then reads **Start**. The status shows Stopped.
- [ ] **Stopped → Start**: the same in reverse. The status shows Running with a PID.
- [ ] **Changes from a terminal**: with the app open, run `brew services stop tinyproxy` (then `start`). The window updates within a few seconds, without waiting for the 60s poll.
- [ ] **Crash detection**: `kill $(pgrep -x tinyproxy)` turns the status to Stopped immediately.
- [ ] **View → Logs** opens the log file in Console.
- [ ] **Not installed**: the app asks before installing. **Not Now** leaves an **Install tinyproxy** button.
- [ ] **Update available**: **Upgrade** works, and restarts tinyproxy if it was running (see below for how to set this up).

> [!WARNING]
> Always set `HOMEBREW_NO_AUTOREMOVE=1` when uninstalling or downgrading tinyproxy for testing. Otherwise `brew uninstall` also removes any dependency formulae that nothing needs anymore, even ones unrelated to tinyproxy.

### Simulating "not installed"

```sh
brew services stop tinyproxy
HOMEBREW_NO_AUTOREMOVE=1 brew uninstall tinyproxy   # tinyproxy.conf is kept
```

### Simulating "update available"

Homebrew only ships the current tinyproxy version, so you build an older one from the formula's git history. Find the last commit for the version you want with:

```sh
curl -s "https://api.github.com/repos/Homebrew/homebrew-core/commits?path=Formula/t/tinyproxy.rb" \
  | python3 -c 'import json,sys; [print(c["sha"][:12], c["commit"]["message"].splitlines()[0]) for c in json.load(sys.stdin)]'
```

Then (shown here for 1.11.2, commit `bd2a66a427e7`):

```sh
export HOMEBREW_NO_AUTOREMOVE=1
brew services stop tinyproxy
brew uninstall tinyproxy

# 1. Put the old formula in a throwaway local tap, without its (outdated) bottles.
brew tap-new --no-git "$USER/local"
TAP="$(brew --repository)/Library/Taps/$USER/homebrew-local"
curl -sf https://raw.githubusercontent.com/Homebrew/homebrew-core/bd2a66a427e7/Formula/t/tinyproxy.rb \
  -o "$TAP/Formula/tinyproxy.rb"
sed -i '' '/^  bottle do/,/^  end/d' "$TAP/Formula/tinyproxy.rb"

# 2. Build it. It installs into the regular Cellar/tinyproxy/<version>.
brew install --build-from-source "$USER/local/tinyproxy"

# 3. Mark the keg as coming from homebrew/core, so `tinyproxy` resolves to the core formula again.
python3 - "$(brew --cellar)/tinyproxy/1.11.2/INSTALL_RECEIPT.json" <<'PY'
import json, sys
path = sys.argv[1]
receipt = json.load(open(path))
receipt["source"]["tap"] = "homebrew/core"
receipt["source"]["path"] = None
json.dump(receipt, open(path, "w"), indent=2)
PY
brew untap "$USER/local"

brew outdated tinyproxy   # should list tinyproxy
```

The build also installs `asciidoc` and `docbook-xsl` as build dependencies.

## Changing the icon

Edit `Resources/AppIcon.svg`, then regenerate the icons (needs `brew install librsvg`):

```sh
./scripts/make-icon.sh
```

Commit both the SVG and the regenerated `AppIcon.icns`. Keep the macOS icon proportions: the rounded square spans 824×824 in a 1024×1024 canvas, leaving room for the drop shadow. Also check that the icon still reads at 32px.

The menu bar icon, `Resources/StatusIcon.svg`, is a monochrome outline of the same character. If you change the character, update it too. The app uses it as a template image, so macOS tints it to match the menu bar and only its shapes and transparency matter: draw it in solid black and cut details out with transparency, not with other colors. Keep its 4:3 viewBox and tight crop, since the script renders it at 24×18pt, and keep lines thick enough to survive that size. Commit the regenerated `StatusIcon.tiff`.

## Submitting changes

1. Fork the repo and create a branch from `main` (`fix/log-path-parsing`, `feature/port-display`, …).
2. Keep each PR focused on one change. Separate refactors from behavior changes.
3. Write commit messages in the imperative mood, with a short subject line and a body explaining *why* if it isn't obvious (`Wait for the service to reach its target state before re-enabling the button`).
4. Make sure `swift build` succeeds with no warnings and `./scripts/build-app.sh` produces a working app.
5. In the PR description, say what changed, why, and which of the testing scenarios above you ran. For UI changes, include a screenshot.

## Reporting issues

Please include:

- Your macOS version and Mac (Apple silicon or Intel)
- The output of `brew --version` and `brew services info tinyproxy --json`
- What you expected, what happened, and the steps to reproduce it
- Relevant lines from **View → Logs**, if tinyproxy itself misbehaved
