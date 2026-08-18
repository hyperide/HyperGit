// AppLifecycleGate tests — the foreground-refresh gate's state machine, including the
// regression this was extracted to catch: `hasEnteredBackground` must be a one-shot
// flag, not a permanent sticky bit that refires on every later `.inactive` blip.
import Testing
@testable import HyperGitCore

@Suite("AppLifecycleGate")
struct AppLifecycleGateTests {
    @Test("cold launch (no prior background) does not refresh")
    func coldLaunchDoesNotRefresh() {
        let decision = AppLifecycleGate.onPhaseChange(hasEnteredBackground: false, isBackground: false, isActive: true)
        #expect(decision.shouldRefresh == false)
        #expect(decision.hasEnteredBackground == false)
    }

    @Test("entering background sets the flag without refreshing")
    func backgroundSetsFlagWithoutRefreshing() {
        let decision = AppLifecycleGate.onPhaseChange(hasEnteredBackground: false, isBackground: true, isActive: false)
        #expect(decision.shouldRefresh == false)
        #expect(decision.hasEnteredBackground == true)
    }

    @Test("becoming active after a real background refreshes and resets the flag")
    func activeAfterBackgroundRefreshesAndResets() {
        let decision = AppLifecycleGate.onPhaseChange(hasEnteredBackground: true, isBackground: false, isActive: true)
        #expect(decision.shouldRefresh == true)
        #expect(decision.hasEnteredBackground == false)
    }

    @Test("a second active transition without an intervening background does not refresh again")
    func repeatedActiveWithoutNewBackgroundDoesNotRefresh() {
        let first = AppLifecycleGate.onPhaseChange(hasEnteredBackground: true, isBackground: false, isActive: true)
        let second = AppLifecycleGate.onPhaseChange(hasEnteredBackground: first.hasEnteredBackground, isBackground: false, isActive: true)
        #expect(second.shouldRefresh == false)
        #expect(second.hasEnteredBackground == false)
    }

    @Test("an inactive blip that never reaches background (e.g. an OAuth sheet) does not refresh")
    func inactiveBlipDoesNotRefresh() {
        let decision = AppLifecycleGate.onPhaseChange(hasEnteredBackground: false, isBackground: false, isActive: false)
        #expect(decision.shouldRefresh == false)
        #expect(decision.hasEnteredBackground == false)
    }

    @Test("the real device sequence (.background -> .inactive -> .active) preserves the flag through .inactive, then refreshes on .active")
    func realBackgroundToForegroundSequence() {
        let backgrounded = AppLifecycleGate.onPhaseChange(hasEnteredBackground: false, isBackground: true, isActive: false)
        #expect(backgrounded.hasEnteredBackground == true)

        // iOS always routes through .inactive on the way back to .active — the flag must
        // survive this step, since it isn't itself .active and isn't .background either.
        let inactive = AppLifecycleGate.onPhaseChange(hasEnteredBackground: backgrounded.hasEnteredBackground, isBackground: false, isActive: false)
        #expect(inactive.shouldRefresh == false)
        #expect(inactive.hasEnteredBackground == true)

        let active = AppLifecycleGate.onPhaseChange(hasEnteredBackground: inactive.hasEnteredBackground, isBackground: false, isActive: true)
        #expect(active.shouldRefresh == true)
        #expect(active.hasEnteredBackground == false)
    }
}
