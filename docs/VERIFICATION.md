# Verification: X 0.1.3

Date: September 12, 2026. Platform: Apple Silicon, macOS 26.6.2, Xcode 26.6, Swift 6.3.3. Deployment target: macOS 14.

## Version 0.1.3 mouse-wheel refresh

The previous native handler deliberately cancelled unphased scroll events, so the Logitech MX Ergo wheel could scroll but could not pull to refresh. The app now recognizes a wheel burst that starts at the top, converts coarse line deltas to points following [AppKit’s documented delta units](https://developer.apple.com/documentation/appkit/nsevent/scrollingdeltay), and releases after 350 ms of wheel inactivity, checked by the existing 250 ms timer. The armed indicator reads `Stop scrolling to refresh`. Trackpad release behavior remains supported. Scrolling from below the top, short separate bursts, direction reversal, horizontal movement, momentum, cancellation, and protected activity do not trigger a wheel refresh. Pull reloads additionally verify the renderer's current top boundary immediately before reloading.

At 10:01 Pacific, `swift test` passed all 42 tests with zero failures in 20.1 seconds. Seven new deterministic tests cover wheel recognition and cancellation. Three new integration tests deliver native event inputs directly to the production handler with real WebKit fixtures: coarse and precise deltas reload exactly once after stopping, Following selection and the paused automatic timer survive, cancellation/momentum do not reload, and scrolling away or creating a draft before release blocks refresh. These tests do not post system events or use the authenticated account.

`scripts/build-app.sh` passed the release build with warnings treated as errors, plist validation, and signature verification. Version 0.1.3 (4) was copied to `/Applications/X.app`; its executable matches `dist/X.app`, and its installed signature verifies. The previous installed version was backed up at `.build/install-backups/X-0.1.2.app`. The app was relaunched and the authenticated For you feed loaded at 10:02:59 Pacific with automatic refresh enabled.

Live automated scroll input first returned the feed to its top, then a separate upward burst displayed `Stop scrolling to refresh`. After input stopped, the refresh timestamp advanced to 10:03:41 Pacific, For you remained selected, and automatic refresh remained enabled. This was before the next 60-second timer deadline.

Physical MX Ergo hardware acceptance remains pending; automated input does not establish the exact feel or driver settings of that device. No commit or push was performed. Earlier acceptance limitations remain applicable.

## Version 0.1.2 icon sizing

The full-bleed gold artwork previously filled the entire Dock icon slot. Packaging now renders it within transparent margins with rounded corners, preserving the original artwork. At 1024 pixels, the visible tile occupies bounds `(100, 100, 924, 924)`, or 80.5% of each dimension. All ten packaged PNG representations were inspected with Pillow: expected square dimensions, reduced alpha bounds, and fully transparent canvas corners passed. The 128-pixel representation was visually inspected for clean edges and logo legibility.

`scripts/build-app.sh` passed the release build, plist validation, and local signature verification. The app was restarted and retained its authenticated session with automatic refresh enabled. The About panel showed version 0.1.2 (3) and the rounded gold icon. Direct Dock inspection timed out, so a live side-by-side Dock size comparison was not independently verified. No new application behavior changed; the prior 32-test result is retained rather than reported as rerun for this asset-packaging change.

Changed files: `scripts/render-icon.swift`, `scripts/build-app.sh`, `Resources/Info.plist`, README, specification, icon provenance, and this report. No commit or push was performed.

## Version 0.1.1 update

The separate title and toolbar rows are combined into a compact native title bar. The footer uses 3-point vertical padding and 10-point status text, with extra room for errors. The application icon now shows a black X on photoreal gold. Changed implementation files: `Sources/XDesktop/App.swift`, `Resources/Info.plist`, `Resources/x-gold-icon.png`, and `scripts/build-app.sh`; README, specification, and icon provenance were updated.

On September 12 at 08:17 Pacific, `swift test` passed all 32 tests with zero failures (12.983 seconds), and `scripts/build-app.sh` passed the release build with warnings treated as errors and signature verification. The rebuilt app was relaunched with the existing authenticated session. A screenshot confirmed the compact layout in the user's actual window. Toolbar clicks paused and resumed automatic refresh; the new refresh control completed a page reload at 08:20:56. The About panel visibly showed the gold icon and version 0.1.1 (2). The app was left on Home with automatic refresh enabled.

The checks below were performed for the original build unless repeated above. Prior acceptance limitations remain applicable.

## Outcome

A working local app is built at `dist/X.app` and has been opened against the user's authenticated X account. Core reading and refresh behavior has been verified. This is not a claim that every release acceptance item in the specification is complete.

No commit, push, public distribution, paid API enrollment, or automatic installation was performed.

## Commands and results

Run from `/Users/banastas/GitHub/X`:

| Command | Result |
| --- | --- |
| `swift test` | Passed: 32 XCTest tests, zero failures. Final run took approximately 12.9 seconds after compilation. |
| `scripts/build-app.sh` | Passed: release build with compiler warnings treated as errors; produced `dist/X.app`. |
| `codesign --verify --deep --strict dist/X.app` | Passed for the local ad hoc signature. |
| `plutil -lint dist/X.app/Contents/Info.plist` | Passed. |
| `bash -n scripts/build-app.sh` | Passed. |
| `node --check Sources/XDesktop/Resources/Website.js` | Passed. Node is a development check only, not a build or runtime dependency. |
| `lipo -archs dist/X.app/Contents/MacOS/XDesktop` | `arm64`. |
| `git diff --check` | Passed. |

The original 0.1.0 app bundle was approximately 504 KiB before filesystem-dependent packaging overhead; the gold raster asset increases the current bundle size. WebKit is provided by macOS; its runtime memory usage is not represented by this bundle size.

## Automated coverage

- Ten deterministic scheduler tests: 60-second timing, completion-based rescheduling, trigger coalescing, user pause, temporary suspension, five-second scroll deferral, failure backoff, manual-only recovery, and retry/resume deadlines.
- Six gesture-recognizer tests: threshold, short pull, top-boundary requirement, momentum and mouse-wheel exclusion, protected activity, horizontal movement, and cancellation.
- One URL-policy test covering expected origins, deceptive hostnames, port and scheme restrictions, and external navigation schemes.
- Twelve tests running the actual isolated adapter in WebKit: feed switching/restoration, a draft remaining protected after blur, modal protection, markup failure, media pause/unmute transitions, nested scrolling, script isolation, malformed messages, extra pinned tabs, and pagination readiness.
- Three browser-model integration tests: five reloads each of the two fixture feeds, stored selection and pause state, and returning through same-document history without a full-document load event.

Fixture tests use a nonpersistent website data store and contain no account credentials. They support the application logic findings but do not substitute for live X checks.

## Live checks

| Check | Evidence and result |
| --- | --- |
| Native rendering | X's login entry page and authenticated timeline rendered in the packaged app. Native controls remained visible at the user's compact window size. |
| Login persistence | The signed-in home feed survived multiple app quits and launches, including moving from the staging build to the repository build with the same bundle identifier. |
| Following reloads | Five consecutive manual reloads preserved Following. Completion timestamps: 08:01:57, 08:02:10, 08:02:12, 08:02:14, and 08:02:16 Pacific. |
| For you reloads | Five consecutive manual reloads preserved For you. Completion timestamps: 08:02:48, 08:02:51, 08:02:53, 08:02:55, and 08:02:57 Pacific. |
| Composer protection | Focusing the empty native website composer changed status to `Finish composing`. Moving keyboard focus away restored automatic refresh. No test post was submitted. Retained-text protection was separately tested in fixtures. |
| Pull-to-refresh | The user explicitly confirmed that the indicator appears and releasing triggers a reload on their physical trackpad. The gesture's recognition rules also pass automated tests. |
| Post-detail pause | Navigating to a post changed status to `Open Home to auto-refresh`. |
| Native Back | After the navigation fix, returning to Home completed successfully at 08:07:55 with automatic refresh enabled. |
| Automatic timer | Without another refresh action by the agent, the completion timestamp advanced from 08:07:55 to 08:08:57 while For you remained selected. This is consistent with a 60-second interval plus page-load latency. |
| Icon | The downloaded official-site PNG was visually checked: a white X on black. The build bundles its generated ICNS locally. |

The ten consecutive feed reload checks preceded the final same-document navigation fix. The final build then passed the entire test suite, the live native-Back retest, and the automatic-timer observation.

## Compatibility issues found and repaired

1. The real account includes a third pinned `Projects` tab. Recognition now examines the first home tab group and permits additional tabs, while enabling refresh only for For you and Following. Media carousels no longer affect feed recognition.
2. X can retain a pagination spinner after posts have rendered. Existing timeline content now establishes readiness without waiting indefinitely for that spinner to disappear.
3. A periodic observer alone could miss a newly focused composer just before the timer fires. Automatic and pull reloads now query the renderer's current state immediately before proceeding.
4. Muted autoplay videos can run continuously. They no longer suspend refresh unless the user explicitly interacts with their playback, unmutes them, or enters full screen. Playing audio remains protected.
5. Returning through X's single-page history need not produce a full-document `didFinish` event. Adapter readiness can now complete that traversal once native navigation is idle.

## Remaining acceptance work

- A supervised two-hour soak with bounded-resource measurements and console inspection has not been completed. No long-duration stability or memory-growth claim is made.
- Comprehensive VoiceOver, Reduce Motion, minimum-height/width, multiple-display, and older-macOS coverage remains incomplete.
- Actual sleep, lock, session switching, minimize/restore, and network-loss transitions still need broader live coverage. Their scheduling rules have automated coverage.
- Full Google/Apple sign-in, uploads, camera/microphone use, and explicit video-control/full-screen variations have not been exhaustively tested.
- JavaScript syntax and functional checks passed. The complete live website console has not been audited, so console cleanliness is not claimed.
- Timed website refresh is not explicitly approved by X's published automation rules. Account-enforcement risk remains unknown.

Confidence is high in the observed core behavior and build results, moderate in general compatibility as X changes, and unknown for platform enforcement and untested long-duration operation.
