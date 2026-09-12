# Verification: X 0.1.3

Core browsing and refresh behavior have passed automated and live checks. This report distinguishes tested behavior from remaining acceptance work; it does not claim full website compatibility or App Store readiness.

The tested platform is Apple Silicon with macOS 26 and Swift 6. The deployment target is macOS 14, but older supported macOS versions and Intel Macs have not been validated.

## Automated checks

The version 0.1.3 suite passed **42 XCTest tests with zero failures**. Tests use synthetic content and nonpersistent WebKit sessions; they do not require an X account or include credentials.

| Area | Tests | Coverage |
| --- | --- | --- |
| Refresh scheduler | 10 | Completion-based 60-second timing, trigger coalescing, user pause, temporary suspension, scroll deferral, backoff, and retry deadlines |
| Gesture recognition | 13 | Trackpad threshold and release, top boundary, wheel burst timing, reversal, horizontal motion, momentum, protected activity, and cancellation |
| URL policy | 1 | Expected origins, deceptive hostnames, ports, schemes, and external navigation |
| Website adapter | 12 | Real WebKit fixtures for feed recognition/restoration, drafts, dialogs, media, nested scrolling, isolated scripts, malformed messages, extra pinned tabs, and pagination readiness |
| Browser model | 3 | Repeated reloads of both feeds, selection and pause persistence, and same-document Back navigation |
| Wheel integration | 3 | Coarse and precise native event inputs, exactly one reload after a pause, feed/pause persistence, cancellation, momentum, and fresh renderer protection |

Wheel integration tests deliver native event inputs directly to the production event handler in local fixture windows. They do not post system events or use a live account. Their success establishes the input-handling and reload path, not physical device feel.

## Build and packaging

Run these checks from the repository root:

| Command | Verified result |
| --- | --- |
| `swift test` | 42 tests passed with zero failures |
| `scripts/build-app.sh` | Release build passed with warnings treated as errors; produced `dist/X.app` |
| `codesign --verify --deep --strict dist/X.app` | Local ad hoc signature passed verification |
| `plutil -lint dist/X.app/Contents/Info.plist` | App metadata passed validation |
| `bash -n scripts/build-app.sh` | Shell syntax passed validation |
| `git diff --check` | No whitespace errors |

The built executable is `arm64` on the tested Apple Silicon Mac. Packaging includes the website adapter, application metadata, and generated icon. The app was also copied outside the build folder and its executable and signature verified. App signing is local and ad hoc; no Developer ID signing, notarization, or App Store distribution has been validated.

## Source setup verification

The documented test and release-build steps were repeated from a clean temporary copy containing only tracked source files, with no pre-existing build output. All 42 tests passed, the release build completed, and the generated app passed signature and plist validation. This checks that the setup does not depend on the original checkout path or ignored local artifacts; it is still a test on the same Apple Silicon development Mac, not a separate-machine compatibility claim.

All nine README shell examples passed syntax checks, relative documentation links resolved, and build/editor artifacts remained excluded by `.gitignore`.

## Live behavior checked

These observations come from the initial build and subsequent 0.1.x updates. They are not claims that every item was repeated for every documentation or packaging change.

| Check | Result |
| --- | --- |
| Native rendering | Login and authenticated timelines rendered in the packaged app; native controls remained accessible in a compact window |
| Login persistence | The signed-in home feed survived multiple quits, launches, and app replacements using the same bundle identifier |
| Feed selection | Five consecutive manual reloads of each home feed preserved the selected feed |
| Composer protection | Focusing the website composer paused automatic refresh; leaving the empty composer restored eligibility. Retained-text protection was tested separately in fixtures |
| Trackpad refresh | A physical trackpad pull displayed the indicator and triggered a reload after release |
| Wheel refresh | Automated scroll input at the top displayed `Stop scrolling to refresh`; stopping completed a reload before the automatic timer deadline and preserved the feed selection |
| Navigation | Opening a post suspended automatic refresh; native Back returned to Home and restored eligibility |
| Automatic timer | An otherwise idle home feed completed its next refresh after approximately 62 seconds, consistent with the interval plus loading time |
| Pause controls | Native pause/resume controls changed automatic-refresh state as expected |
| App identity | The About panel displayed the expected version and gold icon |

Physical Logitech MX Ergo acceptance remains pending. Automated wheel input does not establish behavior under every device's driver or scroll settings.

## Changes verified by version

### 0.1.3: Mouse-wheel refresh

The previous handler cancelled unphased scroll events. Wheel input now starts a pull only when the timeline is already at its top. Coarse line deltas are converted to points following [AppKit's documented units](https://developer.apple.com/documentation/appkit/nsevent/scrollingdeltay). The 250 ms native timer detects release after at least 350 ms without wheel input.

The armed indicator reads `Stop scrolling to refresh`. A scroll that began below the top stays rejected until the burst ends. Short separate bursts, reversal, horizontal movement, momentum, protected activity, and cancellation do not trigger refresh. Pull reloads also verify the renderer's current top boundary before proceeding. Seven deterministic tests and three native-event integration tests were added; all 42 tests passed.

### 0.1.2: Icon sizing

Packaging draws the gold artwork within transparent margins and rounded corners. At 1024 pixels, the tile occupies bounds `(100, 100, 924, 924)`. All ten packaged image representations passed dimension, alpha-bound, and transparent-corner checks. The 128-pixel representation was visually inspected. A direct side-by-side Dock size comparison was not independently verified.

The release build, plist validation, and local signature verification passed. No application behavior changed; the prior 32-test result was retained rather than represented as rerun for the icon-only change.

### 0.1.1: Compact native controls

Navigation and refresh controls moved into a unified compact title bar, with a thin status strip below the website. The gold X artwork replaced the initial icon. All 32 tests passed, the release build and signature verified, and native pause/resume and manual refresh were checked live.

### Initial build: Website compatibility

Live checks identified and resolved these integration issues:

- Additional pinned home tabs no longer prevent recognition of For you and Following. Unrelated media tab groups are excluded.
- Existing posts establish readiness even when a pagination spinner remains visible.
- Automatic and pull reloads query the renderer immediately before proceeding to catch newly protected activity.
- Muted autoplay previews do not indefinitely suspend refresh; explicit playback and audible media remain protected.
- Returning through same-document history can complete without a full-document load event.

The final initial-build suite passed, followed by live native-Back and automatic-timer checks.

## Remaining acceptance work

- A two-hour stability soak with resource measurements and console inspection.
- Comprehensive VoiceOver, Reduce Motion, minimum-window-size, multiple-display, older-macOS, and Intel coverage.
- Broader real sleep, lock, session switching, minimize/restore, and network-loss checks.
- Full Google/Apple sign-in, uploads, camera, microphone, and explicit media/full-screen flows.
- Physical wheel-device and driver coverage beyond automated input.
- An audit of the complete live website console; console cleanliness is not claimed.

The app's website recognition and draft protection depend on X's markup, which can change. X's automation rules do not explicitly approve the timed-refresh behavior; account-enforcement risk remains unresolved.
