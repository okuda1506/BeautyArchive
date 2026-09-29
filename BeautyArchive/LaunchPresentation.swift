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

    func finish() {
        phase = .finished
    }
}
