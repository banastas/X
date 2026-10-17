import XCTest
@testable import XCore

final class RefreshTests: XCTestCase {
    func testSixtySecondsFromReadiness() {
        var s = RefreshSchedule(); s.setEligible(true, now: 10)
        XCTAssertFalse(s.isDue(now: 69.99, mayRetry: true))
        XCTAssertTrue(s.isDue(now: 70, mayRetry: true))
    }
    func testCompletionResetsTimerAndCoalescesTriggers() {
        var s = RefreshSchedule(); s.setEligible(true, now: 0)
        XCTAssertTrue(s.begin()); XCTAssertFalse(s.begin())
        XCTAssertFalse(s.isDue(now: 100, mayRetry: true))
        s.succeeded(now: 100)
        XCTAssertFalse(s.isDue(now: 159, mayRetry: true))
        XCTAssertTrue(s.isDue(now: 160, mayRetry: true))
    }
    func testUserPauseSurvivesManualRefresh() {
        var s = RefreshSchedule(); s.setEligible(true, now: 0); s.setEnabled(false, now: 1)
        XCTAssertTrue(s.begin()); s.succeeded(now: 2)
        XCTAssertFalse(s.isDue(now: 100, mayRetry: true))
        s.setEnabled(true, now: 100)
        XCTAssertFalse(s.isDue(now: 159, mayRetry: true))
        XCTAssertTrue(s.isDue(now: 160, mayRetry: true))
    }
    func testSuspensionAndWakeNeverCatchUp() {
        var s = RefreshSchedule(); s.setEligible(true, now: 0); s.setEligible(false, now: 30)
        XCTAssertFalse(s.isDue(now: 10_000, mayRetry: false))
        s.setEligible(true, now: 10_000)
        XCTAssertFalse(s.isDue(now: 10_059, mayRetry: true))
        XCTAssertTrue(s.isDue(now: 10_060, mayRetry: true))
    }
    func testMultipleReasonsMustAllClearBeforeCallerRestoresEligibility() {
        var reasons: Set<String> = ["draft", "video"]
        var s = RefreshSchedule(); s.setEligible(reasons.isEmpty, now: 0)
        reasons.remove("draft"); s.setEligible(reasons.isEmpty, now: 60)
        XCTAssertFalse(s.isDue(now: 120, mayRetry: true))
        reasons.remove("video"); s.setEligible(reasons.isEmpty, now: 120)
        XCTAssertEqual(s.deadline, 180)
    }
    func testInteractionDefersOverdueRefreshFiveSeconds() {
        var s = RefreshSchedule(); s.setEligible(true, now: 0); s.interacted(now: 59)
        XCTAssertFalse(s.isDue(now: 63.9, mayRetry: true))
        XCTAssertTrue(s.isDue(now: 64, mayRetry: true))
    }
    func testReadingAwayFromTopWaitsForIdleReader() {
        var s = RefreshSchedule(); s.setEligible(true, now: 0); s.interacted(now: 50)
        XCTAssertFalse(s.isDue(now: 100, mayRetry: true, reading: true))
        XCTAssertFalse(s.isDue(now: 169.9, mayRetry: true, reading: true))
        XCTAssertTrue(s.isDue(now: 170, mayRetry: true, reading: true))
        // Returning to the top releases the overdue refresh once input settles.
        XCTAssertTrue(s.isDue(now: 100, mayRetry: true, reading: false))
    }
    func testReadingDoesNotHoldBackFailureRetries() {
        var s = RefreshSchedule(); s.setEligible(true, now: 0); s.interacted(now: 10)
        _ = s.begin(); s.failed(now: 10)
        XCTAssertTrue(s.isDue(now: 130, mayRetry: true, reading: true))
    }
    func testCancelledNavigationRestartsInterval() {
        var s = RefreshSchedule(); s.setEligible(true, now: 0)
        _ = s.begin(); s.cancelled(now: 30)
        XCTAssertFalse(s.loading)
        XCTAssertEqual(s.deadline, 90)
    }
    func testBackoffAndReset() {
        var s = RefreshSchedule()
        for expected in [120.0, 240.0, 300.0, 300.0] {
            _ = s.begin(); s.failed(now: 100)
            XCTAssertEqual(s.retryAt, 100 + expected)
            XCTAssertFalse(s.isDue(now: 100 + expected, mayRetry: false))
            XCTAssertTrue(s.isDue(now: 100 + expected, mayRetry: true))
        }
        _ = s.begin(); s.succeeded(now: 500)
        XCTAssertEqual(s.failures, 0); XCTAssertNil(s.retryAt)
    }
    func testChallengeAndManualRetryBlockPolling() {
        var s = RefreshSchedule(); s.setEligible(true, now: 0)
        _ = s.begin(); s.failed(now: 0, requiresManual: true)
        XCTAssertFalse(s.isDue(now: 100_000, mayRetry: true))
        XCTAssertTrue(s.begin()); s.succeeded(now: 100_000)
        XCTAssertFalse(s.manualRetryRequired)
    }
    func testRetryAfterAndResumeRespectBothDeadlines() {
        var s = RefreshSchedule(); _ = s.begin(); s.failed(now: 0, retryAfter: 900)
        s.postpone(now: 100)
        XCTAssertEqual(s.retryAt, 900)
        s.postpone(now: 1000)
        XCTAssertEqual(s.retryAt, 1060)
    }
    func testFeedSwitchRestartsInterval() {
        var s = RefreshSchedule(); s.setEligible(true, now: 0); s.postpone(now: 50)
        XCTAssertEqual(s.deadline, 110)
    }
}

final class PullTests: XCTestCase {
    func testReleasePastThresholdOnce() {
        var p = PullGesture()
        p.handle(phase: .began, dy: 5, atTop: true, eligible: true)
        p.handle(phase: .changed, dy: 66, atTop: true, eligible: true)
        XCTAssertTrue(p.armed)
        XCTAssertTrue(p.handle(phase: .ended, atTop: true, eligible: true))
        XCTAssertFalse(p.handle(phase: .ended, atTop: true, eligible: true))
    }
    func testShortPullCancels() {
        var p = PullGesture(); p.handle(phase: .began, dy: 30, atTop: true, eligible: true)
        XCTAssertFalse(p.handle(phase: .ended, atTop: true, eligible: true))
        XCTAssertEqual(p.distance, 0)
    }
    func testMustBeginAtTop() {
        var p = PullGesture(); p.handle(phase: .began, dy: 30, atTop: false, eligible: true)
        p.handle(phase: .changed, dy: 100, atTop: true, eligible: true)
        XCTAssertFalse(p.handle(phase: .ended, atTop: true, eligible: true))
    }
    func testMomentumNeverArms() {
        var p = PullGesture(); p.handle(phase: .momentum, dy: 300, atTop: true, eligible: true)
        XCTAssertFalse(p.handle(phase: .ended, atTop: true, eligible: true))
    }
    func testWheelRefreshesOnceAfterPause() {
        var p = PullGesture()
        for time in [0.0, 0.1, 0.2] {
            p.handleWheel(dy: 32, now: time, atTop: true, eligible: true)
        }
        XCTAssertTrue(p.armed)
        XCTAssertFalse(p.finishWheelIfIdle(now: 0.5, atTop: true, eligible: true))
        XCTAssertTrue(p.finishWheelIfIdle(now: 0.6, atTop: true, eligible: true))
        XCTAssertFalse(p.finishWheelIfIdle(now: 1, atTop: true, eligible: true))
        XCTAssertEqual(p.distance, 0)
    }
    func testWheelReachingTopCannotArmUntilANewBurst() {
        var p = PullGesture()
        p.handleWheel(dy: 32, now: 0, atTop: false, eligible: true)
        p.handleWheel(dy: 100, now: 0.1, atTop: true, eligible: true)
        XCTAssertFalse(p.armed)
        XCTAssertFalse(p.finishWheelIfIdle(now: 0.5, atTop: true, eligible: true))
        p.handleWheel(dy: 100, now: 0.6, atTop: true, eligible: true)
        XCTAssertTrue(p.finishWheelIfIdle(now: 1, atTop: true, eligible: true))
    }
    func testWheelShortBurstsDoNotAccumulate() {
        var p = PullGesture()
        p.handleWheel(dy: 40, now: 0, atTop: true, eligible: true)
        // Even if the UI timer was delayed, a new burst cannot inherit old distance.
        p.handleWheel(dy: 40, now: 1, atTop: true, eligible: true)
        XCTAssertEqual(p.distance, 40)
        XCTAssertFalse(p.finishWheelIfIdle(now: 1.4, atTop: true, eligible: true))
    }
    func testWheelReversalAndHorizontalMovementRejectRestOfBurst() {
        for (dx, dy) in [(0.0, -1.0), (100.0, 10.0)] {
            var p = PullGesture()
            p.handleWheel(dy: 100, now: 0, atTop: true, eligible: true)
            p.handleWheel(dx: dx, dy: dy, now: 0.1, atTop: true, eligible: true)
            p.handleWheel(dy: 100, now: 0.2, atTop: true, eligible: true)
            XCTAssertFalse(p.finishWheelIfIdle(now: 0.6, atTop: true, eligible: true))
        }
    }
    func testWheelProtectionAndLeavingTopCancel() {
        for (atTop, eligible) in [(true, false), (false, true)] {
            var p = PullGesture()
            p.handleWheel(dy: 100, now: 0, atTop: true, eligible: true)
            XCTAssertFalse(p.finishWheelIfIdle(now: 0.4, atTop: atTop, eligible: eligible))
            XCTAssertFalse(p.tracking)
        }
    }
    func testWheelBlockedAtStartCannotArmMidBurst() {
        var p = PullGesture()
        p.handleWheel(dy: 100, now: 0, atTop: true, eligible: false)
        p.handleWheel(dy: 100, now: 0.1, atTop: true, eligible: true)
        XCTAssertFalse(p.finishWheelIfIdle(now: 0.5, atTop: true, eligible: true))
    }
    func testMomentumAndCancellationDiscardPendingWheelRelease() {
        var p = PullGesture()
        p.handleWheel(dy: 100, now: 0, atTop: true, eligible: true)
        p.handle(phase: .momentum, dy: 300, atTop: true, eligible: true)
        XCTAssertFalse(p.finishWheelIfIdle(now: 1, atTop: true, eligible: true))
        p.handleWheel(dy: 100, now: 2, atTop: true, eligible: true)
        p.cancel()
        XCTAssertFalse(p.finishWheelIfIdle(now: 3, atTop: true, eligible: true))
    }
    func testProtectedActivityCancelsArmedGesture() {
        var p = PullGesture(); p.handle(phase: .began, dy: 100, atTop: true, eligible: true)
        XCTAssertFalse(p.handle(phase: .ended, atTop: true, eligible: false))
    }
    func testHorizontalAndCancelledGestures() {
        var p = PullGesture(); p.handle(phase: .began, dx: 100, dy: 10, atTop: true, eligible: true)
        XCTAssertFalse(p.tracking)
        p.handle(phase: .began, dy: 100, atTop: true, eligible: true)
        p.handle(phase: .cancelled, atTop: true, eligible: true)
        XCTAssertFalse(p.handle(phase: .ended, atTop: true, eligible: true))
    }
}

final class NavigationTests: XCTestCase {
    func testOriginsAndSchemesAreExact() {
        XCTAssertTrue(NavigationPolicy.isHome(URL(string: "https://x.com/home")))
        for value in ["http://x.com/home", "https://x.com.evil.test/home", "https://x.com:444/home", "file:///home"] {
            XCTAssertFalse(NavigationPolicy.isX(URL(string: value)))
        }
        XCTAssertFalse(NavigationPolicy.isAuthentication(URL(string: "https://accounts.google.com.evil.test/")))
        XCTAssertTrue(NavigationPolicy.isAuthentication(URL(string: "https://accounts.google.com/")))
        XCTAssertFalse(NavigationPolicy.mayOpenExternally(URL(string: "javascript:alert(1)")!))
    }
}

final class PageTitleTests: XCTestCase {
    func testUnreadCountBecomesBadgeAndIsStrippedFromTitle() {
        XCTAssertEqual(PageTitle.badge("(3) Home / X"), "3")
        XCTAssertEqual(PageTitle.badge("(20+) Home / X"), "20+")
        XCTAssertNil(PageTitle.badge("Home / X"))
        XCTAssertNil(PageTitle.badge("(0) Home / X"))
        XCTAssertNil(PageTitle.badge("Home (3) / X"), "Only a leading count is X's badge")
        XCTAssertNil(PageTitle.badge(nil))
        XCTAssertEqual(PageTitle.text("(3) Home / X"), "Home / X")
        XCTAssertEqual(PageTitle.text("Home / X"), "Home / X")
        XCTAssertEqual(PageTitle.text(""), "X")
        XCTAssertEqual(PageTitle.text(nil), "X")
    }

    func testFeedImagesUpgradeToOriginalSizeOnly() {
        let small = URL(string: "https://pbs.twimg.com/media/ABC123?format=jpg&name=small")!
        XCTAssertEqual(NavigationPolicy.fullSizeImage(small).absoluteString, "https://pbs.twimg.com/media/ABC123?format=jpg&name=orig")
        let bare = URL(string: "https://pbs.twimg.com/media/ABC123.jpg")!
        XCTAssertEqual(NavigationPolicy.fullSizeImage(bare).absoluteString, "https://pbs.twimg.com/media/ABC123.jpg?name=orig")
        for value in ["https://pbs.twimg.com/profile_images/1/a_normal.jpg?name=small", "https://example.com/media/a?name=small"] {
            XCTAssertEqual(NavigationPolicy.fullSizeImage(URL(string: value)!).absoluteString, value)
        }
    }
}

final class UpdatePolicyTests: XCTestCase {
    private let feed = "https://x.banast.as/appcast.xml"

    func testOnlyPublishedBuildsInApplicationsUpdate() {
        XCTAssertTrue(UpdatePolicy.runsUpdater(bundlePath: "/Applications/X.app", feedURL: feed, homeDirectory: "/Users/a"))
        XCTAssertTrue(UpdatePolicy.runsUpdater(bundlePath: "/Users/a/Applications/X.app", feedURL: feed, homeDirectory: "/Users/a/"))
        XCTAssertFalse(UpdatePolicy.runsUpdater(bundlePath: "/Applications/X.app", feedURL: nil, homeDirectory: "/Users/a"),
                       "A copy built from source has no feed")
        XCTAssertFalse(UpdatePolicy.runsUpdater(bundlePath: "/Applications/X.app", feedURL: "http://x.banast.as/appcast.xml", homeDirectory: "/Users/a"))
        for path in ["/Users/a/Developer/X/dist/X.app", "/Applications Old/X.app", "/Users/b/Applications/X.app"] {
            XCTAssertFalse(UpdatePolicy.runsUpdater(bundlePath: path, feedURL: feed, homeDirectory: "/Users/a"), path)
        }
    }
}

final class RefreshIntervalTests: XCTestCase {
    func testChangingTheIntervalRestartsAPendingDeadlineOnly() {
        var s = RefreshSchedule(enabled: true)
        s.setEligible(true, now: 0)
        XCTAssertEqual(s.deadline, 60)
        s.setInterval(300, now: 50)
        XCTAssertEqual(s.interval, 300)
        XCTAssertEqual(s.deadline, 350, "A longer interval restarts from now, not from the old deadline")
        XCTAssertFalse(s.isDue(now: 100, mayRetry: true))
        s.setInterval(120, now: 200)
        XCTAssertEqual(s.deadline, 320, "A shorter interval never fires at once")
        s.setEnabled(false, now: 210)
        s.setInterval(60, now: 220)
        XCTAssertNil(s.deadline, "No deadline appears while automatic refresh is off")
    }

    func testWordingAndValidation() {
        XCTAssertEqual(RefreshInterval.phrase(60), "every minute")
        XCTAssertEqual(RefreshInterval.phrase(300), "every 5 minutes")
        XCTAssertEqual(RefreshInterval.name(60), "1 minute")
        XCTAssertEqual(RefreshInterval.name(600), "10 minutes")
        XCTAssertEqual(RefreshInterval.remaining(42), "42s")
        XCTAssertEqual(RefreshInterval.remaining(245), "4:05")
        XCTAssertEqual(RefreshInterval.validated(120), 120)
        XCTAssertEqual(RefreshInterval.validated(7), 60)
        XCTAssertEqual(RefreshInterval.validated(0), 60)
    }
}

final class XLinkTests: XCTestCase {
    func testLinksFromOtherAppsAreNormalizedOrRefused() {
        XCTAssertEqual(NavigationPolicy.xLink(from: " https://x.com/someone/status/123 \n")?.absoluteString, "https://x.com/someone/status/123")
        XCTAssertEqual(NavigationPolicy.xLink(from: "x.com/home")?.absoluteString, "https://x.com/home")
        XCTAssertEqual(NavigationPolicy.xLink(from: "http://twitter.com/a")?.absoluteString, "https://twitter.com/a")
        for value in ["", "hello world", "https://example.com/x.com", "javascript:alert(1)", "https://x.com.evil.test/",
                      "file:///Users/a/x.com", "https://x.com:8443/home"] {
            XCTAssertNil(NavigationPolicy.xLink(from: value), value)
        }
    }
}

final class UnreadTrackerTests: XCTestCase {
    func testTheSameUnreadCountNotifiesOnceAcrossRefreshes() {
        var tracker = UnreadTracker()
        XCTAssertFalse(tracker.update(count: 1, loading: false, inBackground: true), "The first reading only sets the baseline")
        for _ in 0..<5 {
            // A refresh: the title loses its count while loading, then gets it back.
            XCTAssertFalse(tracker.update(count: 0, loading: true, inBackground: true))
            XCTAssertFalse(tracker.update(count: 1, loading: true, inBackground: true))
            XCTAssertFalse(tracker.update(count: 1, loading: false, inBackground: true))
        }
        // A bare title outside a load, in the background, doesn't lower the baseline either.
        XCTAssertFalse(tracker.update(count: 0, loading: false, inBackground: true))
        XCTAssertFalse(tracker.update(count: 1, loading: false, inBackground: true))
        XCTAssertTrue(tracker.update(count: 2, loading: false, inBackground: true), "A real increase notifies")
        XCTAssertFalse(tracker.update(count: 2, loading: false, inBackground: true))
    }

    func testForegroundReadingsAndActivationResetTheBaseline() {
        var tracker = UnreadTracker()
        _ = tracker.update(count: 3, loading: false, inBackground: false)
        XCTAssertFalse(tracker.update(count: 4, loading: false, inBackground: false), "No alert while the app is in front")
        XCTAssertEqual(tracker.baseline, 4)
        XCTAssertFalse(tracker.update(count: 0, loading: false, inBackground: false), "Read in front: the baseline drops")
        XCTAssertTrue(tracker.update(count: 1, loading: false, inBackground: true))
        tracker.seen(count: 0, loading: false)
        XCTAssertEqual(tracker.baseline, 0)
        tracker.seen(count: 5, loading: true)
        XCTAssertEqual(tracker.baseline, 0, "A reading during a load is not what the person saw")
        XCTAssertEqual(UnreadTracker.count(from: "20+"), 20)
        XCTAssertEqual(UnreadTracker.count(from: nil), 0)
    }
}
