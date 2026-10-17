# X for macOS

An unofficial macOS desktop app that keeps X's **For you** and **Following** feeds in a dedicated window. It uses the real X website, with a compact native toolbar, keyboard shortcuts, automatic refresh, and pull-to-refresh for trackpads and mouse wheels.

Built with Swift, SwiftUI, AppKit, and WebKit. This project is independent of X Corp. and is not an official X client.

## Install

1. Download X for macOS from [x.banast.as](https://x.banast.as).
2. Unzip it and move `X.app` to Applications (`/Applications`, or the Applications folder in your home folder).
3. Open it. macOS asks once to confirm opening an app downloaded from the internet.
4. Sign in to X in the window. Your browser's existing login is not imported, and you complete any account verification yourself.

It needs **macOS 14 Sonoma or later** and has been tested on Apple silicon. The download is signed with Developer ID and notarized by Apple, and it [updates itself](#updates).

Once Home loads, select **For you** or **Following**. Automatic refresh starts by default. Use the toolbar timer button or `Command-P` if you prefer to refresh manually.

To uninstall, quit X and move the installed app to Trash. Removing the app does not automatically erase its saved preferences or website data. Use X's own sign-out control first if you want to end the current login.

## What it does

- Opens X in its own resizable window, with your login and window size retained between launches.
- Defaults Following to **Recent** after each page load, including manual and automatic reloads. You can choose Popular for the current page from X’s sort menu, or turn the default off with **View → Default Following to Recent**.
- Reloads the selected home feed every 60 seconds, counted from when the feed finishes loading. While you are scrolled down reading, it waits until you return to the top or stop interacting for two minutes.
- Pauses automatic refresh during detected drafts, actively watched or audible media, dialogs, open menus, navigation away from Home, and whenever the window cannot be seen.
- Adds native Home, Back/Forward, refresh/stop, auto-refresh, find-in-page, and zoom controls, plus trackpad and mouse-wheel refresh gestures.
- Shows X's unread notification count on the Dock icon.
- Opens external article links in your default browser and saves downloads, including images saved from the context menu, to your Downloads folder.

The app displays X's website inside Apple's `WKWebView`; it does not recreate the timeline or fetch posts through the X API. There is no hosted backend, API key, or app-managed post database. You sign into your own X account, and X controls the content and recommendations you see. A reload may reset your reading position and does not guarantee new posts.

**Current version: 0.3.0.** See [verification](docs/VERIFICATION.md) for automated coverage and live checks of the Following sort default. Core browsing and refresh behavior were checked during 0.1.x; the other 0.2.0 fixes remain covered by local fixture tests. There is no App Store release; you can also [build it from source](#build-from-source).

## Everyday controls

| Action | Control |
| --- | --- |
| Switch feed | X's own For you / Following tabs |
| For you / Following | `Option-Command-1` / `Option-Command-2` (loads Home first if needed) |
| Refresh now | Toolbar refresh or `Command-R` |
| Stop a slow load | Toolbar stop (shown while loading) or `Command-.` |
| Pause/resume automatic refresh | Toolbar timer button (filled when on) or `Command-P` |
| Home | Toolbar home or `Command-1` |
| Back / Forward | Toolbar back/forward, trackpad swipe, `Command-[` / `Command-]` |
| Find on page | `Command-F`, then `Command-G` / `Shift-Command-G`; `Escape` closes |
| Copy or open the current page | **File → Copy Link** (`Shift-Command-C`) or **Open in Browser** (`Shift-Command-O`) |
| Save an image | Control-click it, then **Save Image to Downloads** (original size for X media) |
| Following sort default | **View → Default Following to Recent** |
| Text size | `Command-+`, `Command-−`, `Command-0` (remembered between launches) |
| Full screen | `Control-Command-F` |
| Reopen a closed window | Click the Dock icon, or **Window → Show Main Window** |
| Trackpad refresh | At the top of the timeline, pull down until **Release to refresh** appears, then release |
| Mouse-wheel refresh | Reach the top and pause; keep scrolling toward the top until **Stop scrolling to refresh** appears, then stop |

With a mouse wheel, once **Stop scrolling to refresh** appears, stopping for about half a second refreshes the feed. Both coarse wheel steps and precise smooth-wheel input are supported. A scroll that starts below the top cannot become a refresh halfway through: stop at the top, then start scrolling up again. Short pulls, direction reversal, horizontal scrolling, and momentum do not trigger refresh.

Manual and pull refresh still work while automatic refresh is paused, and they do not turn it back on. Only one reload runs at a time.

The thin status strip at the bottom explains what the app is doing and when the page last refreshed. While the next refresh is counting down, it shows the seconds remaining; “Refreshing once you pause” means it is due but waiting for scrolling, pointer movement, or typing to stop. Automatic refresh waits during detected drafts, focused composers, dialogs, open menus, actively watched or audible media, and non-Home navigation. It also suspends while the app is hidden, the window is minimized, closed, on another Space, or fully covered, and while the screen is locked or asleep. A visible window can continue refreshing while another app has focus.

Direct input in the page (scrolling, pointer movement, clicks, and keys) delays an overdue refresh until at least five seconds after it stops. While you are scrolled down the feed, a due refresh waits until you scroll back to the top or leave the page untouched for two minutes, so it does not replace what you are reading.

Muted autoplay previews alone do not pause refresh. Explicit playback, unmuting, full-screen video, and playing audio do. Closing the window pauses playing media. Reload, Home, Back, Forward, opening an X link meant for a new window, and quitting ask before discarding a detected unsent post, and trackpad swipe navigation is disabled while one exists. Pull-to-refresh is disabled while a draft, dialog, open menu, or playing media is detected.

If a load fails or stalls, the app retries after about 2, 4, and then 5 minutes while automatic refresh is on and the window is visible. A load that failed for lack of a network connection retries as soon as the connection returns. If nothing has loaded yet, the window shows the problem and a **Try Again** button instead of a blank page. If X's feed layout is not recognized, it stops and waits for you instead. A web-process crash reloads once automatically; a second crash within five minutes waits for **Retry**. When the page tries to redirect to another site without a click, the status strip offers **Open in Browser** instead of following it. Clicked links the app cannot open, such as `tel:`, say so in the status strip.

The Recent default looks for X's English “Recent” and “Popular” options. If X shows them in another language or renames them, the app closes the menu it opened and the status strip asks you to choose manually; you can also turn the default off.

Confirmation questions, such as discarding a draft, appear as sheets on the window.

## Updates

A copy downloaded from x.banast.as and installed in Applications checks `https://x.banast.as/appcast.xml` once a day and asks before installing an update. **X → Check for Updates…** checks now, and **X → Check for Updates Automatically** turns the daily check off. Updates use [Sparkle](https://sparkle-project.org): each download must carry an EdDSA signature from the maintainer's key, and the app must be signed by the same Developer ID team. Quitting to install still asks first if you have an unsent post.

Debug builds, and any copy built with `scripts/build-app.sh`, carry no update feed and never show those menu items. To update one of those, see [Update a source build](#update-a-source-build).

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Reopening still shows an older build | Quit every running copy and open the one you replaced. Check **X → About X** for the version. |
| Following isn't switched to Recent | Check that **View → Default Following to Recent** is on. If the status strip says it could not select Recent, X's sort menu wasn't recognized (for example, in another interface language); choose Recent from X's sort menu. |
| Automatic refresh appears stuck | Read the status strip. Return to Home, select For you or Following, scroll back to the top, and finish or close any composer, dialog, menu, or active media. Resume the timer if it is paused. Pinned list tabs are not auto-refreshed. |
| Pull-to-refresh does nothing | Put the pointer over the timeline, reach its top, and begin a new pull after a short pause. A draft, dialog, open menu, or playing media also disables the gesture. Toolbar refresh remains available. |
| Google or Apple sign-in does not complete | Embedded-browser login can be restricted by the provider. When the sign-in window returns to X, the app closes it and reloads Home in the main window. The full OAuth flows have not been acceptance-tested; use X's direct sign-in flow if available. |
| The feed stops loading after a website change | Try the toolbar's Retry/Refresh control. The adapter may need updating if X changes its markup; automatic refresh stops when it cannot recognize the feed. |

## Storage and privacy

Each installation uses its own local WebKit website data and the account signed in on that Mac. Preferences retain the automatic-refresh setting, the Following sort default, selected feed, page zoom, and window geometry. Downloads started from the website are saved to your Downloads folder. The app's bundle identifier is `as.banast.xdesktop`; it identifies the application and does not connect users to the maintainer's X account.

The app does not extract credentials, save posts to a database, add telemetry, or automate engagement. Published builds make one request of their own: a daily fetch of the update feed from x.banast.as, without Sparkle's optional system profile. An isolated website script reports limited UI state—booleans, a feed index, and short status descriptions—to the native app. It also restores the selected feed, chooses Recent once per document when Following opens (unless you turn that off), and, when you choose **Save Image to Downloads**, returns the address of the image under the pointer. The Dock badge and window title come from the page title that WebKit already exposes to the app. If X’s sort menu cannot be recognized, the status strip explains that you need to select Recent manually. X's website still makes its own network requests and follows X's own data practices.

The repository contains source, synthetic test fixtures, documentation, and icon assets. Build output and local app bundles are excluded from Git. Do not include website-data folders, cookies, credentials, or private screenshots in bug reports.

## Build from source

Copies you build yourself are ad hoc signed, carry no update feed, and never update themselves. They use the same bundle identifier as the download, so they share its sign-in and preferences.

### Requirements

- A Mac running **macOS 14 Sonoma or later**. Apple silicon has been tested; Intel Macs and older supported macOS versions have not been validated.
- **Full Xcode with Swift 6 or later**, in a version compatible with your macOS. The app's minimum runtime version does not mean every Xcode release runs on macOS 14.
- An internet connection and your own X account for the signed-in feeds.
- Terminal for the build steps below. Git and the other required build tools are supplied by Xcode.

The one external Swift package is [Sparkle](https://sparkle-project.org) 2.10.0, which SwiftPM fetches on the first build (pinned in `Package.resolved`); it is bundled for published builds' updates and stays inactive in source builds. Node.js, Python, Homebrew, an X developer account, and a paid Apple Developer membership are not required for this local build.

### 1. Install and initialize Xcode

Install [Xcode from Apple](https://developer.apple.com/xcode/), then open it once. Complete its first-launch setup, including any required license agreement and components.

Open Terminal and check the selected tools:

```sh
xcode-select -p
swift --version
```

The Swift version must be 6 or later. If the selected tools point to `/Library/Developer/CommandLineTools`, or to an older Xcode, select your full Xcode installation for this Terminal session. Command Line Tools alone cannot run the tests; `swift test` then fails with `unable to resolve module dependency: 'XCTest'`.

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

The app is built for the Mac you build on. To copy it to a Mac with the other processor type, build a universal app with `scripts/build-app.sh release universal`. Recent Xcode releases warn that the Intel architecture is deprecated; the Intel build still targets macOS 14 but has not been tested.

### 4. Open it and sign in

```sh
open dist/X.app
```

Sign in to X in the window, as in [Install](#install). No other person's login is included in the repository.

If macOS blocks the app as an unidentified developer, first confirm you built it from source you trust. Follow [Apple's instructions for opening an app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac), including the per-app **Open Anyway** option in System Settings → Privacy & Security when available. There is no need to disable Gatekeeper globally.

### 5. Keep it in Applications

The generated `X.app` is self-contained. To install it:

1. Quit X with `Command-Q`.
2. In Finder, open the repository's `dist` folder and copy `X.app` into Applications. You can use your home folder's Applications folder if you prefer a per-user installation.
3. If an app with the same name already exists, check which app it is before replacing it. Keep a backup of an earlier build if you want to be able to return to it. A source build replacing a downloaded copy keeps your sign-in and preferences, but it no longer updates itself.
4. Open the installed copy. You can then keep that copy in the Dock.

You do not need to keep Terminal open. Keep the source folder if you want to build updates. Launch the packaged `X.app`, rather than the executable under `.build`, so the app has its bundled resources and stable identity.

### Update a source build

Quit X first. Return to your source folder, then run:

```sh
git pull --ff-only
swift test
scripts/build-app.sh
```

If any step fails, stop and resolve it before replacing the installed app. Copy the new `dist/X.app` over your previous build in Finder, then open the installed copy. With the same bundle identifier, replacing the app normally preserves preferences and WebKit website data; X can still expire your login independently.

If you have local source changes and Git refuses the update, review and preserve them before retrying.

### Troubleshooting a build

| Symptom | What to check |
| --- | --- |
| Git reports “Repository not found” | Confirm the URL and that you have access. A private repository requires authorization until its owner makes it public. |
| Swift version or SDK errors | Open Xcode to finish setup, check `swift --version`, and select the intended full Xcode installation as described above. |
| `unable to resolve module dependency: 'XCTest'` | Command Line Tools are selected instead of Xcode. Set `DEVELOPER_DIR` as described in step 1, then rerun `swift test`. |
| WebKit tests cannot load fixtures | Run the tests in a logged-in macOS desktop session with full Xcode selected. The tests are not validated for headless environments. |
| The website adapter is missing | Rebuild with `scripts/build-app.sh` and launch `dist/X.app`. Copy the entire app bundle when installing. |

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

The packaging script already treats compiler warnings as errors, bundles Sparkle in `Contents/Frameworks`, and verifies the generated signature. Tests cover refresh scheduling, gestures, URL handling, the real WebKit adapter with local fixtures, and browser-model reload behavior.

### Releasing (maintainer)

`scripts/release.sh` makes a published build. It runs the tests, then builds and signs with the team's Apple Development identity (hardened runtime, `Resources/X.entitlements`) and adds the update feed and public key to Info.plist. Next it wraps the app in an Xcode archive, and Xcode's export signs it with the team's cloud-managed Developer ID certificate, the same one Blit, Rune and Cue use. Finally it notarizes with the `blit-notary` Keychain profile, staples the ticket, and zips into `dist/release/`. It numbers each build by the time (YYYYMMDDHHMM). The comments at the top of the script list the one-time setup: Xcode signed in to the team, the notary profile, the Sparkle key and the Cloudflare Pages project.

```sh
scripts/release.sh                                                    # build, notarize, staple
INSTALL=1 scripts/release.sh                                          # …and replace /Applications/X.app
PUBLISH=1 INSTALL=1 VERSION=0.3.0 NOTES="What changed" scripts/release.sh   # …and publish it
```

`PUBLISH=1` runs only on a clean `main`. It signs the zip with the family's Sparkle key (the same as Blit, Rune and Cue), writes `site/appcast.xml` and `site/downloads/`, commits them and pushes `main`; Cloudflare Pages then serves `site/` at x.banast.as. Publishing makes the download public. See [site/README.md](site/README.md) for hosting.

| Path | Purpose |
| --- | --- |
| `Sources/XCore` | Refresh scheduling, gesture recognition, and URL policy |
| `Sources/XDesktop` | Native interface, WebKit coordination, and isolated website adapter |
| `Tests` | Deterministic tests and WebKit fixture checks |
| `Resources` | App metadata and [icon provenance](Resources/ICON-SOURCE.md) |
| `scripts/build-app.sh` | Local app packaging and signature verification |
| `scripts/release.sh` | Developer ID build, notarization, and publishing an update |
| `site` | The x.banast.as page, update feed, and current download |
| `docs/SPEC.md` | Product behavior and acceptance criteria |
| `docs/VERIFICATION.md` | Tested behavior and remaining acceptance work |

## Limitations and project status

X can change its website or login requirements without notice. The app does not promise complete website feature parity, offline access, multiple accounts, or native notifications. Full upload, camera, microphone, and Google/Apple OAuth flows, comprehensive accessibility checks, older macOS/Intel compatibility, and an extended stability soak remain unverified. Physical mouse-wheel behavior can vary by device and driver. See the [verification report](docs/VERIFICATION.md) for details.

[X's automation rules](https://help.x.com/en/rules-and-policies/x-automation) prohibit non-API website automation. They do not explicitly approve this app's timed reloads. The 60-second interval is a usability choice, not a documented exemption or assurance against account enforcement.

X's name and marks belong to their respective owner. The included attribution does not establish permission to redistribute those marks. A source-code license has not yet been selected; making a repository viewable does not itself grant an open-source license. See [GitHub's licensing explanation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).
