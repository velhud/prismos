import SwiftUI

@MainActor
@main
struct PrismWatchApp: App {
    @StateObject private var store = WatchConnectivityClient()

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store)
        }
    }
}
