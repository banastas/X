# X for macOS

An unofficial macOS desktop app that keeps X's **For you** and **Following** feeds in a dedicated window. It uses the real X website, with a compact native toolbar, keyboard shortcuts, automatic refresh, and pull-to-refresh for trackpads and mouse wheels.

Built with Swift, SwiftUI, AppKit, and WebKit. This project is independent of X Corp. and is not an official X client.

## What it does

- Opens X in its own resizable window, with your login and window size retained between launches.
- Reloads the selected home feed every 60 seconds after an eligible load completes.
- Pauses automatic refresh during detected drafts, actively watched or audible media, dialogs, and navigation away from Home.
- Adds native Home, Back, refresh, and pause controls, plus trackpad and mouse-wheel refresh gestures.
- Opens external article links in your default browser.

The app displays X's website inside Apple's `WKWebView`; it does not recreate the timeline or fetch posts through the X API. There is no hosted backend, API key, or app-managed post database. You sign into your own X account, and X controls the content and recommendations you see. A reload may reset your reading position and does not guarantee new posts.

**Current version: 0.1.3.** The build and 42 automated tests have passed on Apple Silicon. Core browsing and refresh behavior have also been checked against the live website. This is a locally built app, not an App Store or notarized release. See [verification](docs/VERIFICATION.md) for coverage and limitations.

## Requirements

- A Mac running **macOS 14 Sonoma or later**. Apple Silicon has been tested; Intel Macs and older supported macOS versions have not been validated.
- **Full Xcode with Swift 6 or later**, in a version compatible with your macOS. The app's minimum runtime version does not mean every Xcode release runs on macOS 14.
- An internet connection and your own X account for the signed-in feeds.
- Terminal for the build steps below. Git and the other required build tools are supplied by Xcode.

There are no external Swift package dependencies. Node.js, Python, Homebrew, an X developer account, and a paid Apple Developer membership are not required for this local build.

## Set up your own copy

### 1. Install and initialize Xcode

Install [Xcode from Apple](https://developer.apple.com/xcode/), then open it once. Complete its first-launch setup, including any required license agreement and components.

Open Terminal and check the selected tools:

```sh
xcode-select -p
swift --version
```

The Swift version must be 6 or later. If the selected tools point to `/Library/Developer/CommandLineTools`, or to an older Xcode, select your full Xcode installation for this Terminal session:

```sh
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift --version
```

Adjust that path if you installed Xcode elsewhere. This setting applies only to the current shell; it does not change the Mac's global tool selection. See [Apple's command-line build guide](https://developer.apple.com/library/archive/technotes/tn2339/_index.html) for details.

### 2. Download the source

Choose a folder for your projects. For example:

```sh
mkdir -p ~/Developer
cd ~/Developer
git clone https://github.com/banastas/X.git
cd X
```

Run the remaining build commands from this `X` folder. You can use a different location; no particular username or checkout path is required.

### 3. Run the tests and build the app

```sh
swift test
scripts/build-app.sh
```

Wait for the tests to pass before building. The first build can take longer while Swift prepares its caches. WebKit tests run local fixtures in a logged-in macOS desktop session; they do not sign into X or use your account.

The build script compiles the release app, includes the website adapter and icon, validates the app metadata, and applies a local **ad hoc signature**. It prints the location of the finished app:

```text
dist/X.app
```

The script does not install the app or upload anything. The signature supports local use; it is not Apple Developer ID signing or notarization.

### 4. Open it and sign in

```sh
open dist/X.app
```

Sign into X using the website displayed in the app. Complete any normal account verification yourself. Your browser's existing login is not imported automatically, and no other person's login is included in the repository.

Once Home loads, select **For you** or **Following**. Automatic refresh starts by default. Use the toolbar pause button or `Command-P` if you prefer to refresh manually.

If macOS blocks the app as an unidentified developer, first confirm you built it from source you trust. Follow [Apple's instructions for opening an app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac), including the per-app **Open Anyway** option in System Settings → Privacy & Security when available. There is no need to disable Gatekeeper globally.

### 5. Keep it in Applications

The generated `X.app` is self-contained. To install it:

1. Quit X with `Command-Q`.
2. In Finder, open the repository's `dist` folder and copy `X.app` into Applications. You can use your home folder's Applications folder if you prefer a per-user installation.
3. If an app with the same name already exists, check which app it is before replacing it. Keep a backup of an earlier build if you want to be able to return to it.
4. Open the installed copy. You can then keep that copy in the Dock.

You do not need to keep Terminal open. Keep the source folder if you want to build updates. Launch the packaged `X.app`, rather than the executable under `.build`, so the app has its bundled resources and stable identity.

## Everyday controls

| Action | Control |
| --- | --- |
| Switch feed | X's own For you / Following tabs |
| Refresh now | Toolbar refresh or `Command-R` |
| Pause/resume automatic refresh | Toolbar pause/play or `Command-P` |
| Home | Toolbar home or `Command-1` |
| Back | Toolbar back, trackpad back gesture, or `Command-[` |
| Trackpad refresh | At the top of the timeline, pull down until **Release to refresh** appears, then release |
| Mouse-wheel refresh | Reach the top and pause; scroll farther toward the top until **Stop scrolling to refresh** appears, then stop |

For mouse wheels, a pause of roughly half a second releases an armed pull. Both coarse wheel steps and precise smooth-wheel input are supported. A scroll that starts below the top cannot become a refresh halfway through: stop at the top, then begin a new upward burst. Short pulls, direction reversal, horizontal scrolling, and momentum do not trigger refresh.

Manual and pull refresh still work while automatic refresh is paused, and they do not turn it back on. Only one reload can be in flight at a time.

The thin status strip at the bottom explains what the app is doing. Automatic refresh waits during detected drafts, focused composers, dialogs, actively watched or audible media, and non-Home navigation. It also suspends while the app is hidden or minimized, or the desktop session is inactive. A visible window can continue refreshing while another app has focus. Scrolling delays an overdue refresh until at least five seconds after scrolling stops.

Muted autoplay previews alone do not pause refresh. Explicit playback, unmuting, full-screen video, and playing audio do. Native manual reload or navigation asks before interrupting detected protected activity; pull-to-refresh is disabled during that activity.

## Update an installed copy

Quit X first. Return to your source folder, then run:

```sh
git pull --ff-only
swift test
scripts/build-app.sh
```

If any step fails, stop and resolve it before replacing the installed app. Copy the new `dist/X.app` over your previous build in Finder, then open the installed copy. With the same bundle identifier, replacing the app normally preserves preferences and WebKit website data; X can still expire your login independently.

If you have local source changes and Git refuses the update, review and preserve them before retrying. There is no automatic updater.

To uninstall, quit X and move the installed app to Trash. Removing the app does not automatically erase its saved preferences or website data. Use X's own sign-out control first if you want to end the current login.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Git reports “Repository not found” | Confirm the URL and that you have access. A private repository requires authorization until its owner makes it public. |
| Swift version or SDK errors | Open Xcode to finish setup, check `swift --version`, and select the intended full Xcode installation as described above. |
| WebKit tests cannot load fixtures | Run the tests in a logged-in macOS desktop session with full Xcode selected. The tests are not validated for headless environments. |
| The website adapter is missing | Rebuild with `scripts/build-app.sh` and launch `dist/X.app`. Copy the entire app bundle when installing. |
| Reopening still shows an older build | Quit every running copy and open the one you replaced. Check **X → About X** for the version. |
| Automatic refresh appears stuck | Read the status strip. Return to Home, select For you or Following, and finish or close any composer, dialog, or active media. Resume the timer if it is paused. |
| Pull-to-refresh does nothing | Put the pointer over the timeline, reach its top, and begin a new pull after a short pause. Protected activity also disables the gesture. Toolbar refresh remains available. |
| Google or Apple sign-in does not complete | Embedded-browser login can be restricted by the provider. The full OAuth flows have not been acceptance-tested; use X's direct sign-in flow if available. |
| The feed stops loading after a website change | Try the toolbar's Retry/Refresh control. The adapter may need updating if X changes its markup; automatic refresh stops when it cannot recognize the feed. |

## Storage and privacy

Each installation uses its own local WebKit website data and the account signed in on that Mac. Preferences retain the automatic-refresh setting, selected feed, and window geometry. The app's bundle identifier is `as.banast.xdesktop`; it identifies the application and does not connect users to the maintainer's X account.

The app does not extract credentials, save posts to a database, add telemetry, or automate engagement. An isolated website script reports limited UI state—booleans, a feed index, and short status descriptions—to the native app. It also restores the selected feed when needed. X's website still makes its own network requests and follows X's own data practices.

The repository contains source, synthetic test fixtures, documentation, and icon assets. Build output and local app bundles are excluded from Git. Do not include website-data folders, cookies, credentials, or private screenshots in bug reports.

## Development

Open `Package.swift` in Xcode to inspect or edit the project. No separate `.xcodeproj` is required. For an app with Web Inspector enabled:

```sh
scripts/build-app.sh debug
```

For a visual test that does not use an X account, quit any running copy of the app, then run:

```sh
open dist/X.app --args --fixture "$PWD/Tests/XDesktopTests/Fixtures/home.html"
```

Fixture mode is available only in debug builds, uses nonpersistent website storage and separate preferences, and labels its window as a test. It does not validate X's current website markup. Rebuild without `debug` for normal release use.

Standard validation:

```sh
swift test
scripts/build-app.sh
codesign --verify --deep --strict dist/X.app
plutil -lint dist/X.app/Contents/Info.plist
git diff --check
```

The packaging script already treats compiler warnings as errors and verifies the generated signature. Tests cover refresh scheduling, gestures, URL handling, the real WebKit adapter with local fixtures, and browser-model reload behavior.

| Path | Purpose |
| --- | --- |
| `Sources/XCore` | Refresh scheduling, gesture recognition, and URL policy |
| `Sources/XDesktop` | Native interface, WebKit coordination, and isolated website adapter |
| `Tests` | Deterministic tests and WebKit fixture checks |
| `Resources` | App metadata and [icon provenance](Resources/ICON-SOURCE.md) |
| `scripts/build-app.sh` | Local app packaging and signature verification |
| `docs/SPEC.md` | Product behavior and acceptance criteria |
| `docs/VERIFICATION.md` | Tested behavior and remaining acceptance work |

## Limitations and project status

X can change its website or login requirements without notice. The app does not promise complete website feature parity, offline access, multiple accounts, or native notifications. Full upload, camera, microphone, and Google/Apple OAuth flows, comprehensive accessibility checks, older macOS/Intel compatibility, and an extended stability soak remain unverified. Physical mouse-wheel behavior can vary by device and driver. See the [verification report](docs/VERIFICATION.md) for details.

[X's automation rules](https://help.x.com/en/rules-and-policies/x-automation) prohibit non-API website automation. They do not explicitly approve this app's timed reloads. The 60-second interval is a usability choice, not a documented exemption or assurance against account enforcement.

X's name and marks belong to their respective owner. The included attribution does not establish permission to redistribute those marks. A source-code license has not yet been selected; making a repository viewable does not itself grant an open-source license. See [GitHub's licensing explanation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).
