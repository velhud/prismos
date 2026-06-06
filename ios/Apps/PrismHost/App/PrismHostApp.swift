import SwiftUI

@main
struct PrismHostApp: App {
    @StateObject private var deviceModel = DeviceConsoleModel()
    @StateObject private var runtimeModel: RuntimeConsoleModel
    @StateObject private var localModel: LocalConsoleModel
    @StateObject private var serviceModel: ServiceConsoleModel
    @StateObject private var providerModel: ProviderConsoleModel
    @StateObject private var watchConnectivityBridge: WatchConnectivityBridge

    init() {
        let runtimeModel = RuntimeConsoleModel()
        let localModel = LocalConsoleModel()
        let services = ServiceConsoleModel()
        _runtimeModel = StateObject(wrappedValue: runtimeModel)
        _localModel = StateObject(wrappedValue: localModel)
        _serviceModel = StateObject(wrappedValue: services)
        let providerModel = ProviderConsoleModel(services: services)
        _providerModel = StateObject(wrappedValue: providerModel)
        _watchConnectivityBridge = StateObject(
            wrappedValue: WatchConnectivityBridge(
                runtimeModel: runtimeModel,
                localModel: localModel,
                providerModel: providerModel
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootConsoleView()
                .environmentObject(deviceModel)
                .environmentObject(runtimeModel)
                .environmentObject(localModel)
                .environmentObject(serviceModel)
                .environmentObject(providerModel)
        }
    }
}
