import SwiftUI

@MainActor
@main
struct PrismHostApp: App {
    @StateObject private var host = ShellHostModel()
    var body: some Scene {
        WindowGroup { PrismShellView().environmentObject(host).defaultAppStorage(host.preferences) }
    }
}
