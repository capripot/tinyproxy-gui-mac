<p align="center">
  <img src="Resources/AppIcon.svg" width="128" height="128" alt="Tinyproxy GUI icon">
</p>

<h1 align="center">Tinyproxy GUI</h1>

<p align="center">
  A tiny macOS window for keeping an eye on <a href="https://tinyproxy.github.io/">tinyproxy</a>:
  is it running, which version is installed, is there an update, and a button to start or stop it.
</p>

---

## About tinyproxy

[**tinyproxy**](https://tinyproxy.github.io/) is a light-weight HTTP/HTTPS proxy daemon for POSIX systems, designed to be fast and small. It's well suited to running locally, for example to route traffic through a single exit point, filter domains, or test how an app behaves behind a proxy. See the [tinyproxy website](https://tinyproxy.github.io/) for its documentation and configuration reference.

Tinyproxy GUI doesn't replace or modify tinyproxy. It installs the official build through [Homebrew](https://formulae.brew.sh/formula/tinyproxy) and gives you a small native window to monitor and control it.

## Features

- **Status at a glance**: a green/red indicator shows whether tinyproxy is running, plus its PID or the last exit code if it crashed.
- **Version and updates**: shows the installed version and whether Homebrew has a newer one. When an update is available, an **Upgrade** button upgrades tinyproxy and restarts it if it was running.
- **Start / Stop**: a single button that starts or stops the Homebrew service. A spinner shows while the change is in progress, and the button stays disabled until tinyproxy is actually up (or down), for up to 30 seconds.
- **Guided install**: if tinyproxy isn't installed, the app offers to install it with Homebrew. It never installs anything without asking.
- **Homebrew check**: if Homebrew isn't installed, the app tells you and links to [brew.sh](https://brew.sh/).
- **Logs**: **View → Logs** (⌘L) opens tinyproxy's log file in Console.
- **Menu bar icon**: click it to open the window. Right-click it to hide or show the Dock icon, or to quit.
- **Live updates**: notices right away when tinyproxy exits or when the service is started or stopped from a terminal, and checks once a minute as a fallback. The time of the last check is shown at the bottom of the window.

## Requirements

- macOS 13 Ventura or later
- [Homebrew](https://brew.sh/). The app installs tinyproxy through it.
- To build: the Swift 6 toolchain. The Xcode Command Line Tools are enough (`xcode-select --install`); you don't need the full Xcode.

## Installation

There are no pre-built releases yet, so build the app from source:

```sh
git clone https://github.com/capripot/tinyproxy-gui.git
cd tinyproxy-gui
./scripts/build-app.sh
```

This produces `build/Tinyproxy.app`. Open it from there, or copy it to `/Applications`:

```sh
cp -R build/Tinyproxy.app /Applications/
open /Applications/Tinyproxy.app
```

The app is signed ad hoc (a local signature, not an Apple developer certificate), which is fine for apps you build yourself. If you copy it to another Mac or download it, Gatekeeper blocks it the first time. Try to open it, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Usage

Launch the app. On first run, if tinyproxy isn't installed, you'll be asked whether to install it with `brew install tinyproxy`.

| Where | Action | Shortcut |
| --- | --- | --- |
| Window | **Start** / **Stop** the tinyproxy service | Return |
| Window | **Upgrade** (shown only when an update is available) | |
| Window | ⟳ Check now | |
| Tinyproxy menu | Start / Stop | ⇧⌘S |
| Tinyproxy menu | Refresh | ⌘R |
| View menu | Logs | ⌘L |
| View menu | Show Dock Icon | |
| Menu bar icon | Click: open the window | |
| Menu bar icon | Right-click: Open, Show Dock Icon, Quit | |

Closing the window keeps the app running in the menu bar; click the menu bar icon (or the Dock icon) to bring the window back. With the Dock icon hidden, the app has no menu bar of its own, so quit it from the menu bar icon's right-click menu.

Quitting the app doesn't affect tinyproxy: it keeps running (or stays stopped), because it's managed by macOS's launchd, not by this app.

### Configuring tinyproxy

The app doesn't edit tinyproxy's configuration. Edit it directly:

```sh
open -e "$(brew --prefix)/etc/tinyproxy/tinyproxy.conf"
```

Then stop and start tinyproxy from the app to apply the changes. By default tinyproxy listens on port `8888`.

## How it works

The app is a thin layer over Homebrew. Everything it does goes through `brew`:

| What | Command |
| --- | --- |
| Installed / latest version, outdated | `brew info --json=v2 tinyproxy` |
| Running state, PID, exit code | `brew services info --json tinyproxy` |
| Start / Stop | `brew services start\|stop tinyproxy` |
| Install / Upgrade | `brew install tinyproxy` / `brew upgrade tinyproxy` |

tinyproxy's Homebrew formula includes a launchd service (label `sh.brew.tinyproxy`), so `brew services` manages it like any other Homebrew service. It's registered in `~/Library/LaunchAgents`, so it runs as your user and starts again at login.

Neither launchd nor Homebrew has an API to subscribe to another service's state, so the app watches two things instead:

1. **The tinyproxy process**: a kqueue exit watcher (`DispatchSource.makeProcessSource`) on its PID tells the app the moment tinyproxy exits.
2. **`~/Library/LaunchAgents`**: `brew services start/stop` adds or removes the service's plist there, so changes made from a terminal are noticed within a couple of seconds.

On top of these, the app checks every 60 seconds, which also keeps the update status current.

**Logs**: the app reads the `LogFile` setting from `$(brew --prefix)/etc/tinyproxy/tinyproxy.conf` (by default `$(brew --prefix)/var/log/tinyproxy/tinyproxy.log`) and opens that file in Console. If the config has `Syslog On`, it opens Console itself, since the logs then go to the system log.

## Troubleshooting

**"Homebrew is not installed" but it is.** The app looks for `brew` in `/opt/homebrew/bin`, `/usr/local/bin` and `/home/linuxbrew/.linuxbrew/bin`, and then on `PATH`. Apps opened from Finder don't get your shell's `PATH`, so a Homebrew in any other location won't be found.

**Start goes back to "Start" after 30 seconds.** `brew services start` succeeded, but tinyproxy exited right away. A common cause is another process already using the port. Check **View → Logs**, or run tinyproxy in the foreground to see the error:

```sh
"$(brew --prefix)/opt/tinyproxy/bin/tinyproxy" -d
```

**View → Logs says there's no log file.** tinyproxy creates the log file the first time it starts. Start it once, then try again.

**"Last exit: code N" in the window.** tinyproxy stopped with an error. The formula doesn't restart it automatically, so look at the logs, fix the cause, then press **Start**.

## Uninstall

Quit the app and delete `Tinyproxy.app`. To also remove tinyproxy itself:

```sh
brew services stop tinyproxy
brew uninstall tinyproxy
```

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to build, test and submit changes.

## Acknowledgements

This project isn't affiliated with tinyproxy. [tinyproxy](https://github.com/tinyproxy/tinyproxy) is developed by its own maintainers, and the [Homebrew formula](https://formulae.brew.sh/formula/tinyproxy) by the Homebrew community.
