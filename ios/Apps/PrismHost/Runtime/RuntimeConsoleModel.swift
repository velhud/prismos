import Foundation
import PrismDraw
import PrismModels
import PrismRuntime
import PrismWatchModels

@MainActor
final class RuntimeConsoleModel: ObservableObject {
    @Published private(set) var snapshot: RuntimeSnapshot

    private var coordinator = AppCoordinatorCore()
    var runtimeDidChange: (@MainActor (RuntimeSnapshot) -> Void)?

    init() {
        self.snapshot = coordinator.snapshot()
    }

    var activeAppRows: [RuntimeWidget] {
        snapshot.widgets
    }

    var activeAppLabel: String {
        switch snapshot.surface {
        case .orbit:
            "Orbit"
        case let .focused(appID):
            appID.rawValue.capitalized
        }
    }

    var previewViewport: DrawViewport {
        snapshot.latestDraw
    }

    func focus(_ appID: PrismAppID) {
        _ = coordinator.focus(appID: appID)
        refresh(notify: true)
    }

    func exitToOrbit() {
        _ = coordinator.exitToOrbit()
        refresh(notify: true)
    }

    func sendMockTapRight() {
        _ = coordinator.handleButton(ButtonEvent(side: .right, gesture: .tap, durationMilliseconds: 80))
        refresh(notify: true)
    }

    func sendReservedGesture() {
        _ = coordinator.handleButton(ButtonEvent(side: .right, gesture: .doubleTap, durationMilliseconds: 160))
        refresh(notify: true)
    }

    func syncFromWatchSnapshot(_ watchSnapshot: WatchSnapshot) {
        switch watchSnapshot.activeSurface {
        case .orbit:
            _ = coordinator.exitToOrbit()
        case let .app(appID):
            _ = coordinator.focus(appID: appID)
        }
        refresh(notify: false)
    }

    private func refresh(notify: Bool) {
        snapshot = coordinator.snapshot()
        if notify {
            runtimeDidChange?(snapshot)
        }
    }
}
