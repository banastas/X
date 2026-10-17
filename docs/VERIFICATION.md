# Verification: X 0.2.1

## QA fixes and improvements (unreleased)

An October 17, 2026 code review found two adapter failure modes. Both were reproduced against local fixtures before they were fixed:

- **An unrecognized Following sort menu stayed open.** With localized options (“Recientes” / “Populares”), the adapter opened the menu, could not identify Recent, and left the menu open at its five-second deadline. An open menu reports recent activity on every heartbeat, which held automatic refresh back indefinitely. The adapter now closes a menu that appeared after its own click unless the reader has pressed something since. The Recent default can also be turned off (**View → Default Following to Recent**).
- **Feed restoration clicked only once.** If X ignored the first click on the saved feed's tab, for example before its handlers attached, the load never settled and failed at the 45-second timeout. Restoration now retries every half second for up to ten seconds. A feed the reader chooses during the load wins, and a restoration that gives up completes the load with a status message instead of an error.

Interface and functionality additions: Stop while loading (toolbar and `⌘.`), a full-window error state with **Try Again** when nothing has loaded, an immediate retry when a lost network connection returns, a refresh countdown in the status strip, **Save Image to Downloads** in the context menu (original size for X media), the unread count as a Dock badge, the page title as the window title, window-attached sheets for confirmations and website alerts, a Forward toolbar button, find-in-page (`⌘F`, `⌘G`, `⇧⌘G`), **Copy Link** and **Open in Browser**, For you / Following shortcuts (`⌥⌘1` / `⌥⌘2`), a slower adapter heartbeat while the window cannot be seen, and a status notice for clicked links with unsupported schemes.

- All **75 XCTest tests passed with zero failures** (46 desktop/WebKit and 29 core tests), including 12 new ones.
- New regressions cover the localized sort menu closing at its deadline, turning the Recent default off, restoration retrying through late tab hydration (adapter and model), menu feed selection counting as the reader's choice, image lookup beneath a point, Stop ending a stalled load without an error, the countdown appearing only while auto-refresh counts down, the unsupported-scheme notice, persistence of the Recent preference, Dock-badge title parsing, and original-size media URLs.
- Release and debug builds passed with warnings treated as errors.
- A debug fixture launch was inspected through window screenshots: the Forward button, the countdown (“Next refresh in 53s · Refreshed 06:31”), and the find bar highlighting a match.

Not yet verified by hand: the “Not found” and Escape behavior of the find bar, `⌥⌘2`, Save Image against live X media, the Dock badge with real notifications, the confirmation sheets with a live draft, the Stop button, the offline launch state, and reconnect retry. None of these changes has been checked against the live website.

## Updates through Sparkle (unreleased)

Published builds now update the way Blit, Rune and Cue do: Sparkle 2.10.0, a daily check of `https://x.banast.as/appcast.xml`, and updates signed with the family's EdDSA key. `scripts/release.sh` makes them (Developer ID, hardened runtime, notarization, publishing to `site/`), and Cloudflare Pages serves `site/` at x.banast.as. Only builds made by `release.sh` carry the feed, and the updater starts only in a Release build installed in an Applications folder (`UpdatePolicy`, `Updates`).

- All **76 XCTest tests passed with zero failures** (46 desktop/WebKit and 30 core), including a new `UpdatePolicy` test: no feed, an `http` feed, or a copy outside Applications never updates.
- `scripts/build-app.sh` bundles `Sparkle.framework` and signs its helpers from the inside out. It removes SwiftPM's absolute rpaths into `.build`, leaving `@executable_path/../Frameworks`. A source build has no `SUFeedURL` and an ad hoc signature, and passes `codesign --verify --deep --strict`.
- The debug bundle launched in fixture mode and loaded Sparkle from its own `Contents/Frameworks`.
- `scripts/release.sh` signs with the family's cloud-managed Developer ID certificate. It builds with the team's Apple Development identity, wraps the app in an Xcode archive, and exports it with `xcodebuild -exportArchive` (developer-id, automatic signing), as Cue does. A run with `SKIP_NOTARIZE=1 SKIP_TESTS=1 VERSION=0.3.0` exported an app signed `Developer ID Application: William T Anastas (F87BNUZAVJ)`. The app, the framework, and Sparkle's Installer and Downloader services, Autoupdate and Updater.app each kept the hardened runtime and a secure timestamp. The app kept the camera and microphone entitlements, `SUFeedURL`, `SUPublicEDKey`, version 0.3.0 and a time-based build number. The script checks each of these before it notarizes.
- The site page was checked in a browser from the file. Its Download button stays off until `appcast.xml` exists.

Not yet done: notarization, the first published release, and a real update from one published build to the next.

## Following sort default (0.2.1)

On September 30, 2026, the live Following view showed the welcome empty state while the account remained signed in. Selecting Recent restored posts, but a manual page reload changed the sort back to Popular. Version 0.2.1 selects Recent once per document through X's own dropdown when Following opens. Later manual choices remain effective until the next document load.

The adapter waits for late dropdown markup, retries a closed control for up to five seconds while its handlers attach, defers during drafts/media/dialogs or an already open menu, and requires both Popular and Recent options before choosing anything. An unrecognized menu reports a manual-selection status instead of clicking unrelated actions.

- All **63 XCTest tests passed with zero failures** (36 desktop/WebKit and 27 core tests).
- Five new adapter regressions cover repeated document loads, late controls and handlers, later manual sort choices, draft/menu deferral, and an unrecognized menu deadline.
- The arm64 release build passed with warnings treated as errors, plist validation, and ad hoc signature verification.
- Live validation on October 1, 2026 confirmed the installed release selects Recent on launch, after ⌘R, and after the 60-second automatic refresh. Following displayed posts in each case. Selection was verified by the blue checkmark beside Recent; the accessibility menu reports keyboard focus on Popular separately from the actual checked sort.
- The installed `/Applications/X.app` passed signature verification, and its bundled adapter matched the source file. Temporary diagnostic status and experimental pointer handling were removed.

## Earlier verification (0.2.0 and 0.1.x)

Core browsing and refresh behavior have passed automated and live checks. The 0.2.0 changes have passed automated fixture checks only; they have not yet been rechecked against the live website. This report distinguishes tested behavior from remaining acceptance work; it does not claim full website compatibility or App Store readiness.

Live 0.1.x checks used Apple Silicon with macOS 26 and Swift 6. The 0.2.0 automated checks ran on Apple Silicon with macOS 27 and Swift 6.4. The deployment target is macOS 14, but older supported macOS versions and Intel Macs have not been validated.

## Automated checks

The version 0.2.0 suite passed **58 XCTest tests with zero failures** in two consecutive full runs. Tests use synthetic content and nonpersistent WebKit sessions; they do not require an X account or include credentials.

| Area | Tests | Coverage |
| --- | --- | --- |
| Refresh scheduler | 13 | Completion-based 60-second timing, trigger coalescing, user pause, temporary suspension, input deferral, reading-position deferral, backoff, retry deadlines, and cancelled navigations |
| Gesture recognition | 13 | Trackpad threshold and release, top boundary, wheel burst timing, reversal, horizontal motion, momentum, protected activity, and cancellation |
| URL policy | 1 | Expected origins, deceptive hostnames, ports, schemes, and external navigation |
| Website adapter | 16 | Real WebKit fixtures for feed recognition/restoration, drafts versus focus, dialogs, menus, media, nested scrolling, reading position, input activity, isolated scripts, malformed messages, pinned tabs, sign-in and feed-error reporting, and pagination readiness |
| Browser model | 3 | Repeated reloads of both feeds, selection and pause persistence, and same-document Back navigation |
| Wheel integration | 3 | Coarse and precise native event inputs, exactly one reload after a pause, feed/pause persistence, cancellation, momentum, and fresh renderer protection |
| Navigation recovery | 9 | Back between non-Home single-page routes, Retry after a failed first load, timeout retry versus unrecognized-feed suspension, blocked script redirects, sign-in status, draft-gated swipe navigation, pinned-tab restoration, zoom persistence, and idle interface invalidation |

Wheel integration tests deliver native event inputs directly to the production event handler in local fixture windows. They do not post system events or use a live account. Their success establishes the input-handling and reload path, not physical device feel.

## Build and packaging

Run these checks from the repository root:

| Command | Verified result |
| --- | --- |
| `swift test` | 58 tests passed with zero failures |
| `scripts/build-app.sh` | Release build passed with warnings treated as errors; produced an `arm64` `dist/X.app` |
| `scripts/build-app.sh release universal` | Passed; produced `x86_64 arm64`, both slices with a macOS 14 minimum. Xcode warns that x86_64 is deprecated |
| `scripts/build-app.sh debug` | Passed; the fixture-mode app launched and stayed running |
| `codesign --verify --deep --strict dist/X.app` | Local ad hoc signature passed verification |
| `plutil -lint dist/X.app/Contents/Info.plist` | App metadata passed validation |
| `bash -n scripts/build-app.sh` | Shell syntax passed validation |
| `git diff --check` | No whitespace errors |

The built executable is `arm64` on the tested Apple Silicon Mac. Packaging includes the website adapter, application metadata, and generated icon. The app was also copied outside the build folder and its executable and signature verified. App signing is local and ad hoc; no Developer ID signing, notarization, or App Store distribution has been validated.

## Source setup verification

For 0.2.0, tests ran in the working checkout and all three packaging modes ran in a separate copy of the working tree. The clean tracked-files-only check below was last performed for 0.1.3.

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

### 0.2.0: QA fixes

A full QA pass found stuck states, refresh behavior that interrupted reading, and missing desktop conventions. Reproductions were written as tests before fixing.

- **Stuck navigation.** Native Back between two non-Home single-page routes previously left the app loading for 45 seconds with the toolbar disabled, then required manual Retry. Same-document traversals now settle once WebKit is idle. Retry after a failed first load previously called WebKit's no-op `reload()` on an empty web view; it now loads Home, and automatic retries apply to that state.
- **Unattended recovery.** Load timeouts and unavailable website state now retry with backoff instead of stopping automatic refresh until a click. An unrecognized feed still suspends automation. X's own feed error ends a reload and clears when X recovers. A web-process crash reloads once automatically.
- **Reading and visibility.** Any direct input defers a due refresh; a scrolled-down feed waits for the top or two idle minutes. Refresh no longer runs while the window is on another Space, fully covered, or behind the lock screen.
- **Drafts.** Explicit navigation and quitting confirm only for detected unsent text or attachments. Swipe navigation is disabled while a draft exists.
- **Desktop conventions.** Redo, spelling and substitution menus, Forward, text zoom, full screen, menu validation, window reopening, sheet-attached file panels, downloads to the Downloads folder, and removal of WebKit context-menu download items that cannot work without private API.
- **Status and efficiency.** Signed-out users see `Sign in to load your feeds`; pause reasons name the paused refresh; the refresh time appears inline. An idle window no longer republishes unchanged state 12 times per second, and the website adapter no longer runs a document-wide mutation observer whose results were unused.

The WebKit fullscreen preference, occlusion and lock-screen suspension, download handling, crash recovery, sign-in hand-back, context-menu cleanup, and focus-at-launch behavior have no automated coverage and need live checks.

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

- Live recheck of the 0.2.0 changes: reading deferral, occlusion and lock-screen suspension, full-screen video, downloads, draft confirmations, context-menu cleanup, and sign-in hand-back.
- A two-hour stability soak with resource measurements and console inspection.
- Comprehensive VoiceOver, Reduce Motion, minimum-window-size, multiple-display, older-macOS, and Intel coverage.
- Broader real sleep, lock, session switching, minimize/restore, and network-loss checks.
- Full Google/Apple sign-in, uploads, camera, microphone, and explicit media/full-screen flows.
- Physical wheel-device and driver coverage beyond automated input.
- An audit of the complete live website console; console cleanliness is not claimed.

The app's website recognition and draft protection depend on X's markup, which can change. X's automation rules do not explicitly approve the timed-refresh behavior; account-enforcement risk remains unresolved.
