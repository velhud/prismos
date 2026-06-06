import PrismModels

public enum RuntimeEffect: Equatable, Sendable {
    case captureAudio(appID: PrismAppID, requestID: PrismRequestID)
    case captureImage(appID: PrismAppID, requestID: PrismRequestID)
    case callOracle(prompt: String, requestID: PrismRequestID)
    case translateText(text: String, from: String, to: String, requestID: PrismRequestID)
    case saveVisionNote(text: String, requestID: PrismRequestID)
    case copyToClipboard(text: String)
    case openHandoff(urlString: String)
    case scheduleNotification(identifier: String, title: String, body: String)
    case sendDrawNow(appID: PrismAppID)
    case sendOrbitDrawNow
    case logDiagnostics(category: String, message: String)
}
