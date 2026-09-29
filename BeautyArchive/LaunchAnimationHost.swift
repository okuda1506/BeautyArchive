import SwiftUI
import UIKit

struct LaunchAnimationHost<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationTask: Task<Void, Never>?
    @State private var transitionProgress: Double = 0
    private let presentation: LaunchPresentation
    private let content: Content

    init(presentation: LaunchPresentation? = nil, @ViewBuilder content: () -> Content) {
        self.presentation = presentation ?? .shared
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .allowsHitTesting(!presentation.isVisible)
                .accessibilityHidden(presentation.isVisible)

            if presentation.isVisible {
                launchOverlay
                    .ignoresSafeArea()
                    .zIndex(1)
            }
        }
        .onAppear {
            if UIApplication.shared.applicationState == .active || scenePhase == .active {
                startPresentation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            startPresentation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            finishForBackgroundTransition()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: startPresentation()
            case .background: finishForBackgroundTransition()
            case .inactive:
                // Startup can briefly become inactive. Only a real background
                // transition should discard an animation already in progress.
                break
            @unknown default: finishPresentation()
            }
        }
        .onDisappear { finishPresentation() }
    }

    private var launchOverlay: some View {
        GeometryReader { geometry in
            let coverScale = max(geometry.size.width, geometry.size.height)
                / LaunchPresentation.iconSize * 1.5

            ZStack {
                Color("LaunchBackground")
                    .opacity(1 - transitionProgress)

                Image("LaunchIcon")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: LaunchPresentation.iconSize, height: LaunchPresentation.iconSize)
                    .modifier(LaunchIconExpansion(
                        progress: transitionProgress,
                        maximumScale: coverScale,
                        reduceMotion: reduceMotion
                    ))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("B/ONEを起動中")
    }

    private func startPresentation() {
        guard presentation.beginForegroundPresentation() else { return }
        let shouldReduceMotion = reduceMotion
        let animation: Animation = shouldReduceMotion
            ? .easeOut(duration: LaunchPresentation.fadeDuration)
            : .timingCurve(0.18, 0.05, 0.32, 1, duration: LaunchPresentation.expansionDuration)
        animationTask = Task { @MainActor in
            await presentation.playForegroundPresentation(reduceMotion: shouldReduceMotion) {
                withAnimation(animation) {
                    transitionProgress = 1
                }
            }
        }
    }

    private func finishForBackgroundTransition() {
        guard presentation.finishOnBackgroundTransition() else { return }
        animationTask?.cancel()
        animationTask = nil
    }

    private func finishPresentation() {
        animationTask?.cancel()
        animationTask = nil
        presentation.finish()
    }
}

/// Interpolate scale and opacity together, retaining an opaque icon during the
/// first part of the zoom so the expansion is visible before it fades away.
private struct LaunchIconExpansion: AnimatableModifier {
    var progress: Double
    let maximumScale: CGFloat
    let reduceMotion: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let amount = min(max(progress, 0), 1)
        let fade = reduceMotion ? amount : min(max((amount - 0.35) / 0.65, 0), 1)
        content
            .scaleEffect(reduceMotion ? 1 : 1 + (maximumScale - 1) * amount)
            .opacity(1 - fade)
    }
}
