import Foundation
import Observation

/// One presentation per app process. Background work also consumes the launch,
/// so a later foreground resume never starts another splash screen.
@MainActor
@Observable
final class LaunchPresentation {
    enum Phase {
        case waiting
        case holding
        case expanding
        case finished
    }

    static let shared = LaunchPresentation()
    static let holdDuration: Duration = .milliseconds(1_700)
    static let expansionDuration: TimeInterval = 0.32
    static let fadeDuration: TimeInterval = 0.18
    static let iconSize: CGFloat = 96

    private(set) var phase: Phase = .waiting
    var isVisible: Bool { phase != .finished }

    @discardableResult
    func beginForegroundPresentation() -> Bool {
        guard phase == .waiting else { return false }
        phase = .holding
        return true
    }

    func expand() {
        guard phase == .holding else { return }
        phase = .expanding
    }

    /// Keep the overlay alive for the entire transition. A SwiftUI completion
    /// can run immediately when its transaction has no registered animations.
    func playForegroundPresentation(
        reduceMotion: Bool,
        wait: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        animateExpansion: () -> Void
    ) async {
        guard phase == .holding else { return }
        do {
            try await wait(Self.holdDuration)
            guard !Task.isCancelled, phase == .holding else { return }
            expand()
            animateExpansion()

            let duration = reduceMotion ? Self.fadeDuration : Self.expansionDuration
            try await wait(.seconds(duration))
            guard !Task.isCancelled, phase == .expanding else { return }
            finish()
        } catch {
            finish()
        }
    }

    func finish() {
        phase = .finished
    }

    /// A not-yet-active scene can initially report background even on a normal
    /// launch. Only consume a background transition after foreground playback
    /// has started. Watch notification actions explicitly call finish().
    @discardableResult
    func finishOnBackgroundTransition() -> Bool {
        guard phase != .waiting else { return false }
        finish()
        return true
    }
}
