import Foundation

@main
struct LaunchPresentationContract {
    @MainActor
    static func main() async {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(value(), message)
        }

        let coldLaunch = LaunchPresentation()
        expect(coldLaunch.isVisible, "Cold launch must display the icon")
        expect(coldLaunch.beginForegroundPresentation(), "First foreground activation must start the hold")
        expect(!coldLaunch.beginForegroundPresentation(), "Repeated activation must not restart the timer")
        coldLaunch.expand()
        expect(coldLaunch.phase == .expanding && coldLaunch.isVisible, "The overlay must remain present during the expansion")
        coldLaunch.finish()
        expect(!coldLaunch.isVisible, "Animation completion must reveal interactive content")
        expect(!coldLaunch.beginForegroundPresentation(), "A warm resume must never replay the animation")

        let backgroundLaunch = LaunchPresentation()
        backgroundLaunch.finish()
        expect(!backgroundLaunch.beginForegroundPresentation(), "Background work must consume the process's launch presentation")
        backgroundLaunch.expand()
        expect(!backgroundLaunch.isVisible, "Late animation callbacks must not recreate a finished splash")

        let interruptedHold = LaunchPresentation()
        interruptedHold.beginForegroundPresentation()
        interruptedHold.finish()
        expect(!interruptedHold.beginForegroundPresentation(), "Resuming after an interrupted hold must show the app immediately")

        let interruptedExpansion = LaunchPresentation()
        interruptedExpansion.beginForegroundPresentation()
        interruptedExpansion.expand()
        interruptedExpansion.finish()
        expect(!interruptedExpansion.isVisible && !interruptedExpansion.beginForegroundPresentation(),
               "Resuming after an interrupted expansion must show the app immediately")

        let nextProcess = LaunchPresentation()
        expect(nextProcess.beginForegroundPresentation(), "A new process must receive its own launch animation")

        let initialBackgroundState = LaunchPresentation()
        expect(!initialBackgroundState.finishOnBackgroundTransition() && initialBackgroundState.isVisible,
               "An initial background state before activation must not consume a normal cold launch")
        expect(initialBackgroundState.beginForegroundPresentation(),
               "Activation after an initial background state must still start the animation")
        expect(initialBackgroundState.finishOnBackgroundTransition() && !initialBackgroundState.isVisible,
               "A real background transition after activation must finish the animation")
        expect(!initialBackgroundState.beginForegroundPresentation(),
               "A warm resume after a real background transition must not replay the animation")

        // A synchronous render callback must not remove the overlay before
        // the transition duration, even when SwiftUI registers no animation.
        let playback = LaunchPresentation()
        playback.beginForegroundPresentation()
        var waits = 0
        var renderCalls = 0
        await playback.playForegroundPresentation(reduceMotion: false, wait: { duration in
            waits += 1
            if waits == 1 {
                expect(duration == .milliseconds(1_700), "The icon must hold for 1.7 seconds")
                expect(playback.phase == .holding && playback.isVisible, "The icon must remain visible throughout the hold")
            } else {
                expect(duration == .milliseconds(320), "The overlay must allow the complete 0.32-second expansion")
                expect(playback.phase == .expanding && playback.isVisible && renderCalls == 1,
                       "A synchronous render callback must leave the overlay visible while expanding")
            }
        }, animateExpansion: { renderCalls += 1 })
        expect(waits == 2 && !playback.isVisible, "Only the elapsed transition may finish the presentation")

        let reducedMotion = LaunchPresentation()
        reducedMotion.beginForegroundPresentation()
        var reducedWaits: [Duration] = []
        await reducedMotion.playForegroundPresentation(reduceMotion: true, wait: { duration in
            reducedWaits.append(duration)
            expect(reducedMotion.isVisible, "Reduce Motion must retain the overlay until its fade finishes")
        }, animateExpansion: {})
        expect(reducedWaits == [.milliseconds(1_700), .milliseconds(180)],
               "Reduce Motion must retain the hold and use the short fade duration")
        expect(!reducedMotion.isVisible, "The short fade must reveal the app")

        let holdInterruption = LaunchPresentation()
        holdInterruption.beginForegroundPresentation()
        var interruptedRenderCalls = 0
        await holdInterruption.playForegroundPresentation(reduceMotion: false, wait: { _ in
            holdInterruption.finish()
        }, animateExpansion: { interruptedRenderCalls += 1 })
        expect(interruptedRenderCalls == 0 && !holdInterruption.isVisible,
               "Leaving during the hold must skip all expansion callbacks")

        let expansionInterruption = LaunchPresentation()
        expansionInterruption.beginForegroundPresentation()
        var interruptedWaits = 0
        await expansionInterruption.playForegroundPresentation(reduceMotion: false, wait: { _ in
            interruptedWaits += 1
            if interruptedWaits == 2 { expansionInterruption.finish() }
        }, animateExpansion: {})
        expect(!expansionInterruption.isVisible && !expansionInterruption.beginForegroundPresentation(),
               "Leaving during expansion must never restore the overlay on resume")

        let cancelledPlayback = LaunchPresentation()
        cancelledPlayback.beginForegroundPresentation()
        var cancelledRenderCalls = 0
        await cancelledPlayback.playForegroundPresentation(reduceMotion: false, wait: { _ in
            throw CancellationError()
        }, animateExpansion: { cancelledRenderCalls += 1 })
        expect(cancelledRenderCalls == 0 && !cancelledPlayback.isVisible,
               "Cancelling the timer must immediately reveal the app without expanding")
        print("Launch presentation contract passed (\(checks) checks)")
    }
}
