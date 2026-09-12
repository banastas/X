# X for macOS: Personal Desktop Reader

Status: implementation specification. No application has been built or validated yet.

## 1. Purpose

Build a small macOS desktop app that stays open throughout the day and presents X's real **For you** and **Following** feeds. The app periodically reloads the selected feed so the user can glance at updated content.

This is a personal application for Bill's Mac. It uses X's website inside a native window, with no paid X API and no application backend.

The experience should be compact and restrained. Preserving the last-read post or scroll position is not required.

## 2. Agreed requirements

| Item | Requirement |
| --- | --- |
| App name | X |
| Icon | Use the familiar X website icon for this personal build, subject to obtaining a suitable asset. |
| Platform | Native macOS application. |
| Language and frameworks | Swift, SwiftUI, WebKit, and AppKit where required. |
| Content | The authenticated X website in `WKWebView`. |
| Feeds | Switch between the actual For you and Following tabs. |
| Automatic refresh | A fixed 60-second interval. No randomized scheduling. |
| Pull-to-refresh | Pull down at the top of the timeline and release past a threshold to refresh. |
| Reading position | May reset when refreshing. No unread tracking or resume-position requirement. |
| Controls | Pause/resume automatic refresh and refresh immediately. |
| Persistence | Retain website login and window dimensions across launches, subject to X session expiry. |
| Interruption protection | Pause refresh while composing, viewing a post, or playing video. |
| API cost | No X developer account, API key, or paid API calls. |

The remaining details below are proposed implementation defaults. They make the agreed behavior testable and can be adjusted during the prototype.

## 3. Scope

### Included

- One main application window displaying one X website session.
- X's own feed selector, login, and content rendering.
- Native refresh controls, timer, lightweight status, and pull feedback.
- Saved window geometry and automatic-refresh preference.
- Navigation handling for external links and authentication windows.
- Loading, offline, session-expiry, and recoverable-error handling.
- A local build and installation workflow documented with the implementation.

### Excluded from the first release

- A native reconstruction of posts or of X's recommendation algorithm.
- Paid API integration, scraping posts into a database, or direct calls to undocumented X endpoints.
- Automated posting, liking, following, messaging, or engagement.
- Multiple accounts, multiple feed columns, multiple main windows, and a menu-bar-only mode.
- Unread counts, history synchronization, notifications, or Dock badges for new posts.
- Offline feed storage, server infrastructure, telemetry, or an automatic updater.
- App Store submission, public distribution, and a custom branding project.
- An always-on-top mode. This can be considered separately after the core behavior works.

Manual interactions provided by X's website remain available where compatible with WebKit. The app does not promise full website feature parity until tested.

## 4. User experience

### Launch and login

1. Open X from the Dock or Applications folder.
2. Restore the last valid window size and position.
3. Load `https://x.com/home` using a persistent website data store.
4. If X requires authentication, display its normal login flow and suspend timed refresh.
5. Start the refresh schedule only after an authenticated home feed has loaded successfully.

First-run window target: approximately 460 by 820 points, constrained to the available display. The supported minimum size must be established through responsive testing rather than assumed from source code.

The app should use standard macOS window controls and support light/dark system appearance. Website appearance follows X's settings initially.

### Feed switching

Use X's existing **For you** and **Following** tabs. Do not add a duplicate native feed selector in the first release.

Refresh the currently selected feed only. Switching tabs starts a new 60-second countdown once the destination feed is ready.

The selected tab must survive an automatic or manual reload within the running session. Whether X preserves this itself is an early compatibility test. If it does not, a narrowly scoped restoration mechanism must be implemented and tested before this requirement is considered complete.

Cross-launch tab restoration should use X's own saved state where reliable. If necessary, store only the last selected tab locally. Do not silently substitute Following for For you.

For you remains an algorithmically ranked feed. A successful reload does not guarantee new recommendations or chronological results. Following remains the feed rendered by X, not a separate API approximation.

### Native controls

Use a compact toolbar containing:

- Back navigation, enabled when available.
- Refresh, with `Command-R`.
- Pause/resume automatic refresh, with a clear accessible state.

Provide a standard menu command for returning to Home. Navigation away from the home timeline suspends the automatic timer.

Show quiet status such as `Auto-refresh on · 60s`, `Auto-refresh paused`, or a concise error. Avoid a continuously changing countdown or prominent success banners. Label timestamps as page refresh times, never as proof that new posts arrived.

Default automatic refresh to on. Persist an explicit user pause across launches. Temporary pauses must not overwrite that preference.

## 5. Refresh behavior

### Scheduling

- Schedule one refresh 60 seconds after the last successful eligible feed load.
- Use a single scheduler shared by timed refresh, toolbar refresh, keyboard refresh, and pull-to-refresh.
- Allow only one reload at a time. Coalesce additional triggers during a pending reload.
- A successful refresh starts a fresh 60-second countdown.
- Manual and pull refresh work while automatic refresh is explicitly paused, but do not turn it back on.
- Use monotonic timing while awake and handle system sleep/wake explicitly.
- Do not accumulate missed refreshes or run catch-up bursts.

### Automatic refresh eligibility

Automatic refresh requires all of the following:

- The user has enabled it.
- The main window is visible and not minimized or closed.
- The Mac is awake and its session is unlocked.
- The authenticated home timeline is active and sufficiently loaded.
- No navigation, reload, authentication challenge, or recoverable error is unresolved.
- The user is not composing text, viewing an individual post, watching video, or using a modal that reload would interrupt.
- No active pull gesture or scroll interaction is underway.

A visible window may continue refreshing while another app has keyboard focus. Being a background app alone does not pause refresh, because the intended use is a feed left visible beside other work.

After scrolling, wait for at least five seconds without scrolling before an overdue refresh can run. After an interruption such as composing, video playback, minimization, or sleep ends, begin a fresh 60-second countdown. Do not refresh immediately on wake or restore.

If a draft remains open after focus moves away, continue suspending automatic refresh. Do not infer that editing has finished solely from loss of keyboard focus.

### Reload semantics

Use WebKit's standard page reload. Do not clear website data, log the user out, or force a cache bypass on every cycle.

Refreshing may return the timeline to the top. No last-read position restoration is required. If WebKit preserves a lower scroll position, explicitly returning to the top is acceptable only after confirming that the same home feed is still active.

No timed reload is permitted during login or an account challenge. There is no claim that a fixed interval is approved by X or avoids enforcement.

## 6. Pull-to-refresh

### Interaction contract

1. The active home timeline must already be at its top boundary.
2. An intentional downward pull reveals a small native indicator above the content.
3. At approximately 70 points of visual pull, show `Release to refresh` and mark the gesture as armed. This is a starting value to tune on a real trackpad.
4. Releasing an armed gesture requests exactly one reload.
5. Releasing below the threshold cancels the gesture.
6. While loading, show a compact progress indicator and reject duplicate refresh triggers.
7. On completion, dismiss the indicator and restart the timer if automatic refresh is enabled.

### Gesture constraints

- Trigger only on the active timeline's actual scrolling container. The page's outer scroll offset alone may be insufficient.
- Reaching the top through momentum must not trigger a refresh. Require direct user input at the top and ignore momentum-only overscroll.
- Preserve normal scrolling, horizontal navigation gestures, text selection, and interactions with embedded media.
- Cancel if the user switches feeds, navigates away, opens a modal, or the app loses the gesture before release.
- Do not trigger on login screens, profiles, search results, individual posts, messages, or other non-home views.
- If a protected activity or unsaved draft is active, show a brief paused explanation instead of reloading.
- Ordinary mouse-wheel scrolling must not accidentally refresh. Toolbar and keyboard refresh remain available for devices without a suitable gesture.

### Implementation approach

Prototype AppKit scroll-event observation around `WKWebView`, combined with a minimal website-state bridge if required to identify the actual scroll container. Use public APIs only.

Test whether X already handles the gesture in the target configuration before adding competing behavior. Reuse functioning website behavior when it satisfies the requirements.

Pull-to-refresh is a required feature, but its reliability is unverified. If it cannot be implemented without breaking normal scrolling, report the exact failure and leave the release unaccepted rather than silently substituting the toolbar button.

## 7. Architecture

Proposed deployment target: macOS 14 or later, confirmed against the installed SDK and target Mac before implementation. Validate Apple Silicon first. Intel support is not required for the first personal build.

Use a small, dependency-free architecture:

| Component | Responsibility |
| --- | --- |
| SwiftUI app and window | App lifecycle, toolbar, menus, preferences, and native status. |
| WebView host | Own one long-lived `WKWebView`; bridge it into SwiftUI without recreating it during view updates. |
| Navigation coordinator | Route navigation, handle pop-ups, track load failures, and identify home-feed eligibility. |
| Refresh controller | Own the state machine, timer, trigger coalescing, pause reasons, and retry schedule. |
| Pull gesture coordinator | Track top-boundary pulls and render progress feedback. |
| Website-state adapter | Isolate any necessary DOM observations for feed selection, scrolling, composing, and playback. |

Use explicit refresh states such as idle, waiting, refreshing, temporarily suspended, user paused, and error. Keep pause reasons separate so dismissing one interruption cannot resume refresh while another remains active.

Web navigation completion alone may not establish that X's dynamically rendered feed is ready. The implementation must distinguish document load from eligible timeline readiness and prevent indefinite loading states with a bounded timeout.

### Website-state adapter rules

- First use public WebKit navigation/lifecycle APIs and website behavior already available.
- Add DOM observation only where necessary for the agreed UI features and interruption protection.
- Keep selectors and assumptions in one small adapter, with no scattered website scripts.
- Prefer semantic roles and stable attributes where available. Verify against the actual authenticated page.
- Observe route changes within X's single-page application as well as full navigations.
- Send only minimal state values to Swift, such as selected feed, at-top status, modal state, or playback status.
- Never extract passwords, cookies, tokens, messages, or timeline content into the native application.
- Validate bridge messages and restrict their handling to the expected X origin and frame.
- If required page structure becomes unrecognizable, disable automatic and pull refresh with an explanation. Keep normal website browsing and explicit toolbar refresh available.

## 8. Navigation, storage, and privacy

- Use `WKWebsiteDataStore.default()` or an equivalent persistent store supported by the chosen deployment target.
- Let WebKit manage authentication cookies and website storage. Do not copy a Safari profile or import credentials.
- Store app preferences in standard local preferences. Store no app-managed feed database.
- Keep X navigation in the main WebView. Open ordinary external article links in the default browser.
- Handle authentication-related redirects and pop-ups separately from ordinary external links. Verify the complete sign-in path without broadly trusting unrelated domains.
- Use normal macOS permission handling for requested file or media access. No blanket permissions.
- Do not bypass certificate errors or disable transport security globally.
- Do not add analytics, crash-upload services, or remote logging.
- Keep diagnostic logs free of account identifiers, authenticated URLs with sensitive parameters, post content, and credentials.

X itself remains a remote website with its own network requests, cookies, and data practices. The absence of app-added telemetry does not make X's website local or private.

Provide a clearly labeled website-data reset in Settings only if needed for session recovery. Require confirmation because it signs the user out. Never clear data as an automatic error-recovery step.

## 9. Failure handling

| Condition | Required behavior |
| --- | --- |
| Offline or transient navigation failure | Show concise status, retain usable existing content when possible, and offer Retry. |
| Repeated transient failures | Back off to 120, 240, then at most 300 seconds between automatic attempts. Reset after success. |
| Explicit rate-limit response | Suspend normal polling and honor a provided retry time; otherwise require manual retry. |
| Login expiry or account challenge | Suspend automatic refresh and allow the user to complete the website flow. |
| Web content process termination | Show a recoverable error and a Reload action; avoid an infinite relaunch loop. |
| Feed structure or state detection failure | Suspend automation and explain the compatibility issue. |
| Loading exceeds a bounded timeout | End the indefinite progress state and expose Retry; do not start another concurrent reload. |
| X returns unchanged recommendations | Treat as a successful page refresh, without claiming new content. |

Do not promise detection of every X-side rate limit. Some failures may be rendered inside the website rather than exposed through main-document navigation responses. Verify the observable cases and document limits.

## 10. Accessibility and presentation

- All native controls must have VoiceOver labels, appropriate roles, and visible keyboard focus.
- Pause/resume state must be conveyed in text or accessibility state, not only color.
- Pull feedback must respect Reduce Motion and never be the only refresh mechanism.
- Keep the underlying WebKit accessibility tree intact.
- Test keyboard navigation, increased text sizing where supported, and narrow-window layouts.
- Do not hide website navigation or alter its layout in the first implementation unless the unmodified narrow view fails the core use case and a scoped adjustment is verified.
- Use the X icon consistently for the application bundle and Dock. Obtain a suitable asset from an official source and record its origin. No hotlinked icon dependency at runtime.

## 11. Validation and acceptance criteria

### Stage 1: Feasibility prototype

Before substantial visual polish, validate:

1. X loads in a persistent `WKWebView` on the target Mac.
2. The user can sign in, complete any normal authentication challenge, quit, and reopen without an unnecessary new login.
3. Both actual feed tabs work and the selected tab survives repeated reloads.
4. A fixed 60-second refresh updates the active feed without overlapping requests.
5. Pull-to-refresh works at the correct top boundary and does not trigger from momentum.
6. Composing, post-detail navigation, and video playback reliably suspend refresh.

Any failure here is a named compatibility blocker. A shell that merely loads x.com does not establish viability of the whole specification.

### Automated checks

- Unit-test the refresh state machine with an injected clock, including pause precedence, completion-based scheduling, failure backoff, sleep/resume, and simultaneous triggers.
- Test pull recognition with gesture sequences covering below-threshold release, armed release, momentum-only input, cancellation, and non-top scrolling.
- Use controlled local HTML fixtures to test scrolling containers, route transitions, draft detection, media playback, and website-adapter failure behavior where practical.
- Build with the project's supported Xcode command and run the relevant test target. Record exact commands and results in the implementation report.
- Treat fixture results as evidence for app logic only, not proof of current X compatibility.

### Live acceptance on the target Mac

| Test | Pass condition |
| --- | --- |
| Login persistence | Relaunch restores the website session when X has not expired it. |
| Feed selection | Both tabs render correctly and remain selected through at least five successive refreshes each. |
| Automatic interval | Under idle eligible conditions, a new reload begins approximately 60 seconds after the preceding successful feed load. |
| Pull threshold | Below-threshold pulls cancel; an armed release produces one reload. |
| Accidental gesture prevention | Momentum, ordinary scrolling, and non-home views never trigger pull refresh. |
| Draft protection | No timed or pull reload interrupts an active composer or retained unsent draft. |
| Video and post detail | Timed refresh stays suspended until the user returns to an eligible feed state. |
| Pause persistence | User pause survives relaunch; manual refresh does not unpause it. |
| Minimize and sleep | No accumulated refresh burst; resume starts a fresh countdown. |
| Background visibility | A visible eligible window continues refreshing while another app has focus. |
| Offline recovery | Failure is visible, retries are bounded, and successful recovery restores normal scheduling. |
| External navigation | Article links open in the default browser without replacing the home feed. |
| Accessibility | Native controls work with keyboard and VoiceOver; refresh has a non-gesture alternative. |
| Soak test | A two-hour session shows no overlapping reloads, app crashes, unbounded app-owned resource growth, or repeated app-injected script errors. |

Inspect console output and distinguish app errors from third-party website errors. Report any website errors that materially affect the required behavior. Do not describe an uninspected console as clean.

## 12. Deliverables and completion

- Swift source and a maintainable Xcode project or another justified native build configuration.
- A local runnable `X.app` using an appropriate personal bundle identifier, such as `as.banast.xdesktop`, rather than impersonating X's official bundle identifier.
- Bundled icon asset with its source recorded.
- Tests for the scheduler and gesture behavior.
- README covering requirements, building, running, local installation, controls, storage, and known limitations.
- A verification report containing exact commands, live test results, and unresolved issues.

The repository location must be established when implementation begins. This document does not authorize a commit, push, public release, paid service enrollment, or Apple Developer purchase.

Code signing and local installation must be verified on the target Mac. Do not assume that public distribution or notarization is included in a local personal build.

Completion requires the core acceptance criteria to pass or a clearly identified blocking limitation to be reported. Do not call the app complete based on compilation alone.

## 13. Costs, policy, and confidence

The design makes no paid X API calls and requires no hosted backend. Any optional Apple distribution or signing expense is outside this specification.

X's rules broadly prohibit non-API website automation. The published rule does not specifically approve a personal WebView's timed page reloads. A 60-second interval is a user-experience choice, not a documented safe interval. Randomization is not part of the design and is not an enforcement-risk mitigation.

Using the X name and icon is the chosen identity for this personal build, not a finding of trademark permission. Reassess branding and platform terms before any distribution.

| Judgment | Confidence |
| --- | --- |
| SwiftUI and WebKit can provide the native shell and scheduled reload mechanism. | High |
| The design avoids X API usage charges. | High |
| Both actual website feeds, persistent login, and selected-tab reload behavior will work reliably in this specific app. | Moderate, pending prototype validation |
| Pull-to-refresh can coexist reliably with X's current scrolling behavior. | Moderate, pending trackpad testing |
| X will permit or tolerate this automated-refresh use without account enforcement. | Unknown |

## 14. Reference documentation

- [Apple: WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)
- [Apple: WKWebView reload](https://developer.apple.com/documentation/webkit/wkwebview/reload())
- [X: Supported browsers](https://help.x.com/en/using-x/x-supported-browsers)
- [X: Automation rules](https://help.x.com/en/rules-and-policies/x-automation)
- [X: API timelines, including the chronological home feed](https://docs.x.com/x-api/posts/timelines/introduction)
- [X: API pricing](https://docs.x.com/x-api/getting-started/pricing)

External website behavior and policies can change. Recheck the relevant documentation and test the real website when implementation begins.
