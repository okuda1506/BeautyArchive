import Foundation

@main
struct LaunchPresentationContract {
    @MainActor
    static func main() {
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
        print("Launch presentation contract passed (\(checks) checks)")
    }
}
