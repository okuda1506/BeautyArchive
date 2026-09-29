import SwiftUI
import UIKit

struct LaunchAnimationHost<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationTask: Task<Void, Never>?
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
            if UIApplication.shared.applicationState == .background || scenePhase == .background {
                finishPresentation()
            } else if scenePhase == .active {
                startPresentation()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: startPresentation()
            case .background: finishPresentation()
            case .inactive:
                if presentation.phase == .holding || presentation.phase == .expanding {
                    finishPresentation()
                }
            @unknown default: finishPresentation()
            }
        }
        .onDisappear { finishPresentation() }
    }

    private var launchOverlay: some View {
        GeometryReader { geometry in
            let expanding = presentation.phase == .expanding
            let coverScale = max(geometry.size.width, geometry.size.height)
                / LaunchPresentation.iconSize * 1.5

            ZStack {
                Color("LaunchBackground")
                    .opacity(expanding ? 0 : 1)
                    .animation(.easeOut(duration: LaunchPresentation.fadeDuration), value: expanding)

                Image("LaunchIcon")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: LaunchPresentation.iconSize, height: LaunchPresentation.iconSize)
                    .opacity(expanding ? 0 : 1)
                    .animation(
                        .easeIn(duration: reduceMotion ? LaunchPresentation.fadeDuration : 0.24)
                            .delay(reduceMotion ? 0 : 0.08),
                        value: expanding
                    )
                    .scaleEffect(expanding && !reduceMotion ? coverScale : 1)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("B/ONEを起動中")
    }

    private func startPresentation() {
        guard presentation.beginForegroundPresentation() else { return }
        animationTask = Task { @MainActor in
            do { try await Task.sleep(for: LaunchPresentation.holdDuration) }
            catch { return }
            guard !Task.isCancelled, presentation.phase == .holding else { return }

            let animation: Animation = reduceMotion
                ? .easeOut(duration: LaunchPresentation.fadeDuration)
                : .timingCurve(0.18, 0.05, 0.32, 1, duration: LaunchPresentation.expansionDuration)
            withAnimation(animation, completionCriteria: .removed) {
                presentation.expand()
            } completion: {
                presentation.finish()
            }
        }
    }

    private func finishPresentation() {
        animationTask?.cancel()
        animationTask = nil
        presentation.finish()
    }
}
