import WatchKit
import PrismWatchModels

@MainActor
final class WatchHaptics {
    func playSelection() {
        play(WKHapticType.click)
    }

    func play(_ hint: WatchHapticHint) {
        switch hint {
        case .none:
            break
        case .success:
            play(WKHapticType.success)
        case .warning:
            play(WKHapticType.retry)
        case .failure:
            play(WKHapticType.failure)
        case .retry:
            play(WKHapticType.retry)
        case .alarm:
            play(WKHapticType.notification)
        }
    }

    private func play(_ feedback: WKHapticType) {
        WKInterfaceDevice.current().play(feedback)
    }
}
