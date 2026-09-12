# X for macOS

A personal, unofficial desktop window for X, built with Swift, SwiftUI, AppKit, and WebKit. It displays the real **For you** and **Following** feeds without paid API access or a backend.

Status: **working local build**. All 32 automated tests pass. Both signed-in feeds, login persistence, manual reloads, the automatic timer, and native Back have been checked live. Pull-to-refresh was confirmed on the user's trackpad. Extended release acceptance is still incomplete. See [verification](docs/VERIFICATION.md) and the [full specification](docs/SPEC.md).

## Build and run

Requires macOS 14 or later and Xcode with Swift 6 or later. Tested on Apple Silicon with macOS 26.6.2 and Xcode 26.6. There are no external package dependencies.

```sh
swift test
scripts/build-app.sh
open dist/X.app
```

The script creates a release build, bundles the website adapter and gold X icon with transparent Dock margins and rounded corners, and applies a local ad hoc signature. It does not notarize, publish, or install the app. `dist/X.app` is self-contained and can be copied to Applications for personal use. Quit an existing copy before replacing it. Gatekeeper may treat an app transferred to another Mac differently; this build is for the local Mac.

Open `Package.swift` in Xcode to edit or debug. Use `scripts/build-app.sh debug` for a debug app with Web Inspector available. The packaged app is the supported launch path, because it supplies the app identity, permissions descriptions, icon, and stable website-data location.

## Controls

Navigation and refresh controls share one compact native title bar. A thin bottom strip shows refresh status and expands when needed for errors.

| Action | Control |
| --- | --- |
| Change feed | X's own For you / Following tabs |
| Automatic refresh | Every 60 seconds after the preceding eligible feed load |
| Refresh now | Toolbar refresh or `Command-R` |
| Pull-to-refresh | Pull down from the top of the timeline, cross the threshold, and release |
| Pause or resume | Toolbar pause/play or `Command-P` |
| Home | Toolbar home or `Command-1` |
| Back | Toolbar back, trackpad back gesture, or `Command-[` |

Manual refresh and pull-to-refresh work while the automatic timer is paused. They do not turn the timer back on. New refresh triggers are coalesced while a reload is in flight.

The timer suspends during a draft, actively watched or audible media, a modal, non-home navigation, login, minimization, app hiding, display sleep, or session inactivity. A visible window keeps refreshing while another application has focus. Scrolling delays an overdue refresh until at least five seconds after scrolling stops. Resuming from a temporary pause starts a fresh countdown.

Muted autoplay video previews do not suspend refresh. Explicit playback, unmuting, full-screen video, and playing audio do.

Native manual reload or navigation asks before interrupting a detected draft or media. Pull-to-refresh is disabled during protected activity. Refreshing may reset your scroll position. Reloading For you does not guarantee that X will supply different recommendations.

## Storage and privacy

WebKit manages the persistent X session and website storage. App preferences retain automatic-refresh state, selected feed, and window geometry. The bundle identifier is `as.banast.xdesktop`.

There is no app-managed post database, credential extraction, telemetry, backend, private-API integration, or automated engagement. A small isolated script observes UI state and restores the selected tab when needed. Only booleans, a feed index, and short state descriptions cross into Swift. X's website still makes its own normal network requests.

External article links open in the default browser. Google and Apple authentication use separate WebKit windows sharing the same website data store. These authentication providers can impose their own embedded-browser restrictions; their complete flows require live testing.

## Development checks

```sh
swift test
swift build -c release -Xswiftc -warnings-as-errors
scripts/build-app.sh
codesign --verify --deep --strict dist/X.app
plutil -lint Resources/Info.plist
git diff --check
```

The scheduler tests use explicit monotonic timestamps. WebKit tests load local fixtures and exercise the actual website adapter in an isolated content world. They do not contact X or use account credentials.

For a visual local fixture, build the debug app and launch:

```sh
open dist/X.app --args --fixture "$PWD/Tests/XDesktopTests/Fixtures/home.html"
```

Quit the existing app first. Fixture mode is compiled out of release builds and uses an isolated nonpersistent website session. It does not validate current X markup. A fixture window is explicitly titled as a test.

## Limitations

- The two-hour soak, comprehensive VoiceOver coverage, actual sleep/lock transitions, and full camera/microphone/upload/OAuth flows have not been acceptance-tested. The compact live window was checked visually; all minimum-size and display configurations have not been tested.
- DOM assumptions are centralized in `Website.js`. X can change them. If the home feed is not recognized, automatic and pull refresh stop rather than reloading blindly.
- Draft protection covers visible editable content, focused editors, file-input attachments, and open dialogs. X-specific attachment or composer changes still require live verification.
- The app detects main-document HTTP 429 responses. Limits rendered inside X's application may not expose an HTTP status to this layer.
- No downloaded-file workflow or full website feature parity is claimed. Camera, microphone, uploads, OAuth provider flows, and notifications are not acceptance-tested.
- macOS 14 is the deployment target, not a claim of runtime testing on that OS version.
- X's policy broadly prohibits non-API website automation. The chosen interval is not a documented exemption or a guarantee against enforcement.

## Project layout

- `Sources/XCore`: deterministic refresh scheduling, gesture recognition, and URL policy.
- `Sources/XDesktop`: native interface, WebKit coordinator, and isolated website adapter.
- `Tests`: scheduler, gesture, URL policy, and real-WebKit fixture checks.
- `Resources`: app metadata and [icon provenance](Resources/ICON-SOURCE.md).
- `scripts/build-app.sh`: local application packaging and signature verification.
- `docs/SPEC.md`: original product and acceptance specification.

No commit, push, public distribution, or paid enrollment is part of this implementation.
