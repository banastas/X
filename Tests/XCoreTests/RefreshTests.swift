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
