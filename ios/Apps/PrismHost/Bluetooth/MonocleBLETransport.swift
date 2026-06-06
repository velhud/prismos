import Foundation
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

enum MonocleBLEUUIDs {
    static let rawDataService = "e5700001-7bac-429a-b4ce-57ff900f479d"
    static let rawDataRX = "e5700002-7bac-429a-b4ce-57ff900f479d"
    static let rawDataTX = "e5700003-7bac-429a-b4ce-57ff900f479d"

    static let nusService = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
    static let nusRX = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
    static let nusTX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
}

enum MonocleBLERestoration {
    static let centralManagerIdentifier = "com.prismos.PrismOS.monocle.central"

    static var centralManagerOptions: [String: Any] {
        #if canImport(CoreBluetooth)
        [CBCentralManagerOptionRestoreIdentifierKey: centralManagerIdentifier]
        #else
        [:]
        #endif
    }
}

enum MonocleServiceRole: Equatable {
    case runtimeRawData
    case recoveryNUS
    case unrelated
}

struct MonocleServiceClassifier {
    func role(for uuidString: String) -> MonocleServiceRole {
        switch uuidString.lowercased() {
        case MonocleBLEUUIDs.rawDataService:
            .runtimeRawData
        case MonocleBLEUUIDs.nusService:
            .recoveryNUS
        default:
            .unrelated
        }
    }
}

#if canImport(CoreBluetooth)
final class CoreBluetoothMonocleAdapter: NSObject {
    private let classifier = MonocleServiceClassifier()

    func scanServices() -> [CBUUID] {
        [CBUUID(string: MonocleBLEUUIDs.rawDataService)]
    }

    func centralManagerOptions() -> [String: Any] {
        MonocleBLERestoration.centralManagerOptions
    }

    func role(for service: CBService) -> MonocleServiceRole {
        classifier.role(for: service.uuid.uuidString)
    }
}
#endif
