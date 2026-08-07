// AppLifecycleGate — pure decision logic for "should the app refresh its top-level
// lists on returning to the foreground" (issue #4's foreground-sync path). Extracted
// out of HyperGitApp's `.onChange(of: scenePhase)` closure so it's unit-testable
// without a running SwiftUI Scene — this module stays backend/UI-agnostic, so the
// signature takes plain Bools rather than SwiftUI's ScenePhase.
public enum AppLifecycleGate {
    public struct Decision: Equatable, Sendable {
        public let shouldRefresh: Bool
        public let hasEnteredBackground: Bool
    }

    /// `hasEnteredBackground` must be threaded back in as state by the caller — it's
    /// the one-shot "a real background happened, pending consumption" bit. Consuming it
    /// (resetting to false) on the triggering `.active` is what stops it from becoming a
    /// permanent sticky flag that fires on every later `.inactive -> .active` blip (a
    /// sheet presentation, e.g. the OAuth flow, control center) that never actually
    /// backgrounds the app.
    public static func onPhaseChange(
        hasEnteredBackground: Bool,
        isBackground: Bool,
        isActive: Bool
    ) -> Decision {
        if isBackground {
            return Decision(shouldRefresh: false, hasEnteredBackground: true)
        }
        guard isActive, hasEnteredBackground else {
            return Decision(shouldRefresh: false, hasEnteredBackground: hasEnteredBackground)
        }
        return Decision(shouldRefresh: true, hasEnteredBackground: false)
    }
}
