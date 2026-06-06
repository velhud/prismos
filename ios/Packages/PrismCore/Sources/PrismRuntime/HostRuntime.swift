import Foundation
import PrismDiagnostics
import PrismDraw
import PrismModels

public struct RuntimeContext: Equatable, Sendable {
    public var now: Date
    public var requestID: PrismRequestID?
    public var fallback: RuntimeFallbackState?

    public init(now: Date = Date(), requestID: PrismRequestID? = nil, fallback: RuntimeFallbackState? = nil) {
        self.now = now
        self.requestID = requestID
        self.fallback = fallback
    }
}

public enum RuntimeFallbackState: String, CaseIterable, Sendable, Codable {
    case noDeviceConnected
    case waitingForHost
    case providerOffline
    case permissionMissing
    case capturePending
    case captureTimeout
    case noData
    case shortCodeError
    case recoveryOnly

    public var displayText: String {
        switch self {
        case .noDeviceConnected:
            "NO DEVICE"
        case .waitingForHost:
            "WAITING"
        case .providerOffline:
            "OFFLINE"
        case .permissionMissing:
            "PERMISSION"
        case .capturePending:
            "CAPTURE"
        case .captureTimeout:
            "TIMEOUT"
        case .noData:
            "NO DATA"
        case .shortCodeError:
            "ERROR"
        case .recoveryOnly:
            "RECOVERY"
        }
    }
}

public struct RuntimeWidget: Equatable, Sendable {
    public var appID: PrismAppID
    public var label: String
    public var status: String

    public init(appID: PrismAppID, label: String, status: String) {
        self.appID = appID
        self.label = label
        self.status = status
    }
}

public protocol HostAppRuntime: Sendable {
    var appID: PrismAppID { get }
    var label: String { get }

    mutating func onEnter(context: RuntimeContext) -> RuntimeEffect?
    mutating func onExit(context: RuntimeContext) -> RuntimeEffect?
    mutating func onButton(_ event: ButtonEvent, context: RuntimeContext) -> RuntimeEffect?
    mutating func onTick(_ now: Date, context: RuntimeContext) -> RuntimeEffect?
    mutating func onMedia(_ event: MediaEvent, context: RuntimeContext) -> RuntimeEffect?
    func widget(context: RuntimeContext) -> RuntimeWidget
    func render(context: RuntimeContext) -> DrawViewport
}

public struct DefaultHostAppRuntime: HostAppRuntime, Equatable {
    public var appID: PrismAppID
    public var label: String
    public private(set) var buttonCount: Int
    public private(set) var mediaCount: Int

    public init(appID: PrismAppID, label: String, buttonCount: Int = 0, mediaCount: Int = 0) {
        self.appID = appID
        self.label = label
        self.buttonCount = buttonCount
        self.mediaCount = mediaCount
    }

    public mutating func onEnter(context: RuntimeContext) -> RuntimeEffect? {
        .sendDrawNow(appID: appID)
    }

    public mutating func onExit(context: RuntimeContext) -> RuntimeEffect? {
        .logDiagnostics(category: "app", message: "\(label) exit")
    }

    public mutating func onButton(_ event: ButtonEvent, context: RuntimeContext) -> RuntimeEffect? {
        buttonCount += 1
        return .sendDrawNow(appID: appID)
    }

    public mutating func onTick(_ now: Date, context: RuntimeContext) -> RuntimeEffect? {
        nil
    }

    public mutating func onMedia(_ event: MediaEvent, context: RuntimeContext) -> RuntimeEffect? {
        mediaCount += 1
        return .sendDrawNow(appID: appID)
    }

    public func widget(context: RuntimeContext) -> RuntimeWidget {
        RuntimeWidget(appID: appID, label: label, status: context.fallback?.displayText ?? "READY")
    }

    public func render(context: RuntimeContext) -> DrawViewport {
        let status = context.fallback?.displayText ?? defaultStatus
        return MonocleLensLayout.viewport(
            appID: appID,
            title: label.uppercased(),
            lines: [status],
            command: "LONG L EXIT",
            right: fallbackRight(context.fallback),
            accent: accent
        )
    }

    private var accent: UInt32 {
        switch appID {
        case .oracle, .babel, .teleprompter:
            MonocleLensLayout.cyan
        case .vision, .signal:
            MonocleLensLayout.green
        case .chronos:
            MonocleLensLayout.yellow
        }
    }

    private func fallbackRight(_ fallback: RuntimeFallbackState?) -> String {
        switch fallback {
        case .recoveryOnly:
            "NUS"
        case .waitingForHost:
            "WAIT"
        case .providerOffline:
            "OFF"
        case .permissionMissing:
            "PERM"
        case .capturePending:
            "CAP"
        case .captureTimeout:
            "TIME"
        case .noData:
            "NONE"
        case .shortCodeError:
            "ERR"
        case .noDeviceConnected:
            "NO"
        case nil:
            "HOST"
        }
    }

    private var defaultStatus: String {
        switch appID {
        case .oracle:
            "ASK READY"
        case .vision:
            "CAPTURE READY"
        case .signal:
            "NO CARDS"
        case .chronos:
            "TIMER READY"
        case .teleprompter:
            "NO SCRIPT"
        case .babel:
            "TRANSLATE READY"
        }
    }
}

public struct HostRuntimeRegistry: Sendable {
    private var runtimes: [PrismAppID: DefaultHostAppRuntime]

    public init(runtimes: [DefaultHostAppRuntime] = HostRuntimeRegistry.defaultRuntimes) {
        self.runtimes = Dictionary(uniqueKeysWithValues: runtimes.map { ($0.appID, $0) })
    }

    public static let defaultRuntimes: [DefaultHostAppRuntime] = [
        DefaultHostAppRuntime(appID: .oracle, label: "Oracle"),
        DefaultHostAppRuntime(appID: .vision, label: "Vision"),
        DefaultHostAppRuntime(appID: .signal, label: "Signal"),
        DefaultHostAppRuntime(appID: .chronos, label: "Chronos"),
        DefaultHostAppRuntime(appID: .teleprompter, label: "Teleprompter"),
        DefaultHostAppRuntime(appID: .babel, label: "Babel")
    ]

    public var activeAppIDs: [PrismAppID] {
        PrismAppID.allCases.filter { runtimes[$0] != nil }
    }

    public func widgetSnapshot(context: RuntimeContext = RuntimeContext()) -> [RuntimeWidget] {
        activeAppIDs.compactMap { runtimes[$0]?.widget(context: context) }
    }

    public func renderOrbit(context: RuntimeContext = RuntimeContext()) -> DrawViewport {
        let widgets = widgetSnapshot(context: context)
        let appLine = widgets.prefix(3).map { MonocleDisplayTextStyle.system($0.label, limit: 8) }.joined(separator: " ")
        let nextLine = widgets.dropFirst(3).prefix(3).map { MonocleDisplayTextStyle.system($0.label, limit: 8) }.joined(separator: " ")
        return MonocleLensLayout.viewport(
            appID: "orbit",
            title: "PRISM OS",
            lines: [appLine, nextLine, "DOUBLE R ORACLE"],
            command: "L/R SELECT  HOLD R",
            left: "1/\(max(widgets.count, 1))",
            right: "HOST",
            accent: MonocleLensLayout.yellow
        )
    }

    public func render(appID: PrismAppID, context: RuntimeContext = RuntimeContext()) -> DrawViewport? {
        runtimes[appID]?.render(context: context)
    }

    public func runtimeState(appID: PrismAppID) -> DefaultHostAppRuntime? {
        runtimes[appID]
    }

    public mutating func enter(appID: PrismAppID, context: RuntimeContext) -> RuntimeEffect? {
        runtimes[appID]?.onEnter(context: context)
    }

    public mutating func exit(appID: PrismAppID, context: RuntimeContext) -> RuntimeEffect? {
        runtimes[appID]?.onExit(context: context)
    }

    public mutating func button(_ event: ButtonEvent, focusedAppID: PrismAppID, context: RuntimeContext) -> RuntimeEffect? {
        runtimes[focusedAppID]?.onButton(event, context: context)
    }

    public mutating func media(_ event: MediaEvent, focusedAppID: PrismAppID, context: RuntimeContext) -> RuntimeEffect? {
        runtimes[focusedAppID]?.onMedia(event, context: context)
    }
}

public enum RuntimeSurface: Equatable, Sendable {
    case orbit
    case focused(PrismAppID)
}

public struct RuntimeSnapshot: Equatable, Sendable {
    public var surface: RuntimeSurface
    public var widgets: [RuntimeWidget]
    public var latestDraw: DrawViewport
    public var diagnostics: [DiagnosticsEvent]

    public init(
        surface: RuntimeSurface,
        widgets: [RuntimeWidget],
        latestDraw: DrawViewport,
        diagnostics: [DiagnosticsEvent]
    ) {
        self.surface = surface
        self.widgets = widgets
        self.latestDraw = latestDraw
        self.diagnostics = diagnostics
    }
}

public struct RuntimeRequestTracker: Sendable {
    private var currentByApp: [PrismAppID: PrismRequestID] = [:]

    public init() {}

    public mutating func begin(appID: PrismAppID, requestID: PrismRequestID = PrismRequestID()) -> PrismRequestID {
        currentByApp[appID] = requestID
        return requestID
    }

    public func accepts(appID: PrismAppID, requestID: PrismRequestID) -> Bool {
        requestID.isCurrent(comparedTo: currentByApp[appID])
    }
}

public struct DrawCoalescer: Sendable {
    private var pending: DrawViewport?

    public init() {}

    public var hasPending: Bool {
        pending != nil
    }

    public mutating func enqueue(_ viewport: DrawViewport) {
        pending = viewport
    }

    public mutating func drain() -> DrawViewport? {
        defer { pending = nil }
        return pending
    }
}

public struct ReservedGestureInterceptor: Sendable {
    public init() {}

    public func shouldIntercept(_ event: ButtonEvent) -> Bool {
        event.gesture.isOSReserved(on: event.side)
    }
}

public struct AppCoordinatorCore: Sendable {
    private var registry: HostRuntimeRegistry
    private var surface: RuntimeSurface
    private var diagnostics: [DiagnosticsEvent]
    private var coalescer: DrawCoalescer
    private let reservedGestures: ReservedGestureInterceptor

    public init(
        registry: HostRuntimeRegistry = HostRuntimeRegistry(),
        initialContext: RuntimeContext = RuntimeContext()
    ) {
        self.registry = registry
        self.surface = .orbit
        self.diagnostics = []
        self.coalescer = DrawCoalescer()
        self.reservedGestures = ReservedGestureInterceptor()
        self.coalescer.enqueue(registry.renderOrbit(context: initialContext))
    }

    public func snapshot(context: RuntimeContext = RuntimeContext()) -> RuntimeSnapshot {
        let draw: DrawViewport
        switch surface {
        case .orbit:
            draw = registry.renderOrbit(context: context)
        case let .focused(appID):
            draw = registry.render(appID: appID, context: context) ?? registry.renderOrbit(context: context)
        }
        return RuntimeSnapshot(
            surface: surface,
            widgets: registry.widgetSnapshot(context: context),
            latestDraw: draw,
            diagnostics: diagnostics
        )
    }

    public mutating func focus(appID: PrismAppID, context: RuntimeContext = RuntimeContext()) -> RuntimeEffect? {
        if case let .focused(current) = surface, current == appID {
            return nil
        }
        if case let .focused(current) = surface {
            _ = registry.exit(appID: current, context: context)
        }
        surface = .focused(appID)
        let viewport = registry.render(appID: appID, context: context) ?? registry.renderOrbit(context: context)
        coalescer.enqueue(viewport)
        appendDiagnostic(category: .app, message: "Focused \(appID.rawValue)")
        return registry.enter(appID: appID, context: context)
    }

    public mutating func exitToOrbit(context: RuntimeContext = RuntimeContext()) -> RuntimeEffect? {
        if case let .focused(appID) = surface {
            _ = registry.exit(appID: appID, context: context)
        }
        surface = .orbit
        coalescer.enqueue(registry.renderOrbit(context: context))
        appendDiagnostic(category: .app, message: "Returned to orbit")
        return .sendOrbitDrawNow
    }

    public mutating func handleButton(_ event: ButtonEvent, context: RuntimeContext = RuntimeContext()) -> RuntimeEffect? {
        guard !reservedGestures.shouldIntercept(event) else {
            appendDiagnostic(category: .app, message: "Reserved gesture intercepted")
            if event.side == .left, event.gesture == .longPress {
                return exitToOrbit(context: context)
            }
            if event.side == .right, event.gesture == .doubleTap {
                return focus(appID: .oracle, context: context)
            }
            return nil
        }
        guard case let .focused(appID) = surface else {
            appendDiagnostic(category: .app, message: "Orbit button ignored")
            return nil
        }
        let effect = registry.button(event, focusedAppID: appID, context: context)
        if registry.render(appID: appID, context: context).map({ coalescer.enqueue($0) }) == nil {
            coalescer.enqueue(registry.renderOrbit(context: context))
        }
        appendDiagnostic(category: .app, message: "Button routed to \(appID.rawValue)")
        return effect
    }

    public mutating func handleMedia(_ event: MediaEvent, context: RuntimeContext = RuntimeContext()) -> RuntimeEffect? {
        guard case let .focused(appID) = surface else {
            appendDiagnostic(category: .media, message: "Media ignored without focused app")
            return nil
        }
        let effect = registry.media(event, focusedAppID: appID, context: context)
        if let viewport = registry.render(appID: appID, context: context) {
            coalescer.enqueue(viewport)
        }
        appendDiagnostic(category: .media, message: "Media routed to \(appID.rawValue)")
        return effect
    }

    public mutating func nextDraw() -> DrawViewport? {
        coalescer.drain()
    }

    private mutating func appendDiagnostic(category: DiagnosticsEvent.Category, message: String) {
        diagnostics.insert(DiagnosticsEvent(category: category, redactedMessage: message), at: 0)
        diagnostics = Array(diagnostics.prefix(200))
    }
}
