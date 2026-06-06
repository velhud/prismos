import Foundation
import PrismAI

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

struct OpenAIServiceConfiguration: Equatable, Sendable {
    static let defaultTextModel = "gpt-5.5"
    static let defaultVisionModel = "gpt-5.5"
    static let defaultTranslationModel = "gpt-5.5"
    static let defaultBatchTranscriptionModel = "gpt-4o-mini-transcribe"
    static let defaultRealtimeTranscriptionModel = "gpt-realtime-whisper"
    static let defaultRealtimeSessionModel = "gpt-realtime-2"
    static let defaultTranscriptionModel = defaultRealtimeTranscriptionModel
    static let defaultRealtimeTranscriptionDelay = "low"
    static let realtimeTranscriptionSampleRate = 24_000

    var textModel: String
    var visionModel: String
    var translationModel: String
    var transcriptionModel: String
    var realtimeSessionModel: String
    var realtimeTranscriptionDelay: String
    var reasoningEffort: String
    var textVerbosity: String
    var storeResponses: Bool

    init(
        textModel: String = Self.defaultTextModel,
        visionModel: String = Self.defaultVisionModel,
        translationModel: String = Self.defaultTranslationModel,
        transcriptionModel: String = Self.defaultTranscriptionModel,
        realtimeSessionModel: String = Self.defaultRealtimeSessionModel,
        realtimeTranscriptionDelay: String = Self.defaultRealtimeTranscriptionDelay,
        reasoningEffort: String = "low",
        textVerbosity: String = "low",
        storeResponses: Bool = false
    ) {
        self.textModel = Self.normalized(textModel, fallback: Self.defaultTextModel)
        self.visionModel = Self.normalized(visionModel, fallback: Self.defaultVisionModel)
        self.translationModel = Self.normalized(translationModel, fallback: Self.defaultTranslationModel)
        self.transcriptionModel = Self.normalized(transcriptionModel, fallback: Self.defaultTranscriptionModel)
        self.realtimeSessionModel = Self.normalized(realtimeSessionModel, fallback: Self.defaultRealtimeSessionModel)
        self.realtimeTranscriptionDelay = Self.normalizedRealtimeDelay(realtimeTranscriptionDelay)
        self.reasoningEffort = Self.normalized(reasoningEffort, fallback: "low")
        self.textVerbosity = Self.normalized(textVerbosity, fallback: "low")
        self.storeResponses = storeResponses
    }

    private static func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func normalizedRealtimeDelay(_ value: String) -> String {
        let normalized = normalized(value, fallback: defaultRealtimeTranscriptionDelay).lowercased()
        let supported = ["minimal", "low", "medium", "high", "xhigh"]
        return supported.contains(normalized) ? normalized : defaultRealtimeTranscriptionDelay
    }

    var usesRealtimeTranscription: Bool {
        transcriptionModel == Self.defaultRealtimeTranscriptionModel || transcriptionModel.hasPrefix("gpt-realtime-")
    }
}

struct OpenAIResponsesClient: AIClient {
    var configuration: OpenAIServiceConfiguration
    var endpoint: URL
    var timeout: TimeInterval
    var apiKeyProvider: @Sendable () throws -> String
    var userApprovedCloudProcessing: @Sendable () -> Bool
    var transport: HTTPTransport

    init(
        model: String = OpenAIServiceConfiguration.defaultTextModel,
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        timeout: TimeInterval = 20,
        apiKeyProvider: @escaping @Sendable () throws -> String,
        userApprovedCloudProcessing: @escaping @Sendable () -> Bool,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.init(
            configuration: OpenAIServiceConfiguration(textModel: model),
            endpoint: endpoint,
            timeout: timeout,
            apiKeyProvider: apiKeyProvider,
            userApprovedCloudProcessing: userApprovedCloudProcessing,
            transport: transport
        )
    }

    init(
        configuration: OpenAIServiceConfiguration,
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        timeout: TimeInterval = 20,
        apiKeyProvider: @escaping @Sendable () throws -> String,
        userApprovedCloudProcessing: @escaping @Sendable () -> Bool,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.configuration = configuration
        self.endpoint = endpoint
        self.timeout = timeout
        self.apiKeyProvider = apiKeyProvider
        self.userApprovedCloudProcessing = userApprovedCloudProcessing
        self.transport = transport
    }

    func respond(to request: AIRequest) async throws -> AIResponse {
        if request.requiresCloudApproval {
            let decision = ApprovalGate().cloudProcessingDecision(
                isCloudProvider: true,
                userApproved: userApprovedCloudProcessing()
            )
            guard decision == .allowed else {
                throw ProviderError.missingApproval
            }
        }

        let apiKey = try readAPIKey()
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(
            OpenAIResponsesRequest(
                model: configuration.textModel,
                input: .text(request.prompt),
                store: configuration.storeResponses,
                reasoning: .init(effort: configuration.reasoningEffort),
                text: .init(verbosity: configuration.textVerbosity)
            )
        )

        let responseData: Data
        let response: URLResponse
        (responseData, response) = try await Self.perform(urlRequest, transport: transport)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.providerRejected
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.providerRejected
        }

        let envelope = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: responseData)
        guard let text = envelope.responseText, !text.isEmpty else {
            throw ProviderError.providerRejected
        }
        return AIResponse(requestID: request.id, text: text, providerName: "openai:\(configuration.textModel)")
    }

    private func readAPIKey() throws -> String {
        let key = try apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw ProviderError.missingSecret
        }
        return key
    }

    fileprivate static func perform(_ request: URLRequest, transport: HTTPTransport) async throws -> (Data, URLResponse) {
        do {
            return try await transport.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ProviderError.timeout
        } catch {
            throw ProviderError.offline
        }
    }
}

struct OpenAITranslationClient: TranslationClient {
    var configuration: OpenAIServiceConfiguration
    var endpoint: URL
    var timeout: TimeInterval
    var apiKeyProvider: @Sendable () throws -> String
    var userApprovedCloudProcessing: @Sendable () -> Bool
    var transport: HTTPTransport

    init(
        configuration: OpenAIServiceConfiguration = OpenAIServiceConfiguration(),
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        timeout: TimeInterval = 20,
        apiKeyProvider: @escaping @Sendable () throws -> String,
        userApprovedCloudProcessing: @escaping @Sendable () -> Bool,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.configuration = configuration
        self.endpoint = endpoint
        self.timeout = timeout
        self.apiKeyProvider = apiKeyProvider
        self.userApprovedCloudProcessing = userApprovedCloudProcessing
        self.transport = transport
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let prompt = """
        Translate the text from \(request.sourceLanguage) to \(request.targetLanguage).
        Return only the translated text.

        \(request.text)
        """
        let response = try await responsesClient.respond(
            to: AIRequest(
                id: request.requestID,
                appID: .babel,
                prompt: prompt,
                source: .transcript,
                requiresCloudApproval: true
            )
        )
        return TranslationResult(requestID: request.requestID, text: response.text)
    }

    private var responsesClient: OpenAIResponsesClient {
        OpenAIResponsesClient(
            configuration: OpenAIServiceConfiguration(
                textModel: configuration.translationModel,
                visionModel: configuration.visionModel,
                translationModel: configuration.translationModel,
                transcriptionModel: configuration.transcriptionModel,
                realtimeSessionModel: configuration.realtimeSessionModel,
                realtimeTranscriptionDelay: configuration.realtimeTranscriptionDelay,
                reasoningEffort: configuration.reasoningEffort,
                textVerbosity: configuration.textVerbosity,
                storeResponses: configuration.storeResponses
            ),
            endpoint: endpoint,
            timeout: timeout,
            apiKeyProvider: apiKeyProvider,
            userApprovedCloudProcessing: userApprovedCloudProcessing,
            transport: transport
        )
    }
}

struct OpenAIVisionProcessor: VisionProcessor {
    var configuration: OpenAIServiceConfiguration
    var endpoint: URL
    var timeout: TimeInterval
    var apiKeyProvider: @Sendable () throws -> String
    var userApprovedCloudProcessing: @Sendable () -> Bool
    var transport: HTTPTransport

    init(
        configuration: OpenAIServiceConfiguration = OpenAIServiceConfiguration(),
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        timeout: TimeInterval = 20,
        apiKeyProvider: @escaping @Sendable () throws -> String,
        userApprovedCloudProcessing: @escaping @Sendable () -> Bool,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.configuration = configuration
        self.endpoint = endpoint
        self.timeout = timeout
        self.apiKeyProvider = apiKeyProvider
        self.userApprovedCloudProcessing = userApprovedCloudProcessing
        self.transport = transport
    }

    func recognizeText(in image: VisionInput) async throws -> VisionTextResult {
        guard userApprovedCloudProcessing() else {
            throw ProviderError.missingApproval
        }
        let apiKey = try readAPIKey()
        let imageURL = "data:image/jpeg;base64,\(image.jpegData.base64EncodedString())"
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(
            OpenAIResponsesRequest(
                model: configuration.visionModel,
                input: .content([
                    .init(type: "input_text", text: "Read visible text and summarize the scene for a 640 by 400 monochrome HUD.", imageURL: nil),
                    .init(type: "input_image", text: nil, imageURL: imageURL)
                ]),
                store: configuration.storeResponses,
                reasoning: .init(effort: configuration.reasoningEffort),
                text: .init(verbosity: configuration.textVerbosity)
            )
        )

        let (responseData, response) = try await OpenAIResponsesClient.perform(urlRequest, transport: transport)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.providerRejected
        }
        let envelope = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: responseData)
        guard let text = envelope.responseText, !text.isEmpty else {
            throw ProviderError.providerRejected
        }
        return VisionTextResult(requestID: image.requestID, text: text, confidence: 1)
    }

    private func readAPIKey() throws -> String {
        let key = try apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw ProviderError.missingSecret
        }
        return key
    }
}

struct OpenAIAudioTranscriptionClient: SpeechClient {
    var configuration: OpenAIServiceConfiguration
    var endpoint: URL
    var timeout: TimeInterval
    var apiKeyProvider: @Sendable () throws -> String
    var userApprovedCloudProcessing: @Sendable () -> Bool
    var transport: HTTPTransport

    init(
        configuration: OpenAIServiceConfiguration = OpenAIServiceConfiguration(),
        endpoint: URL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        timeout: TimeInterval = 30,
        apiKeyProvider: @escaping @Sendable () throws -> String,
        userApprovedCloudProcessing: @escaping @Sendable () -> Bool,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.configuration = configuration
        self.endpoint = endpoint
        self.timeout = timeout
        self.apiKeyProvider = apiKeyProvider
        self.userApprovedCloudProcessing = userApprovedCloudProcessing
        self.transport = transport
    }

    func transcribe(_ audio: TranscriptionInput) async throws -> TranscriptionResult {
        guard !configuration.usesRealtimeTranscription else {
            throw ProviderError.unsupportedMode
        }
        guard userApprovedCloudProcessing() else {
            throw ProviderError.missingApproval
        }
        let apiKey = try readAPIKey()
        var urlRequest = URLRequest(url: endpoint)
        let boundary = "PrismOSOpenAI-\(audio.requestID.rawValue.uuidString)"
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = MultipartFormData(boundary: boundary)
            .addingField(named: "model", value: configuration.transcriptionModel)
            .addingFile(
                named: "file",
                filename: "monocle.wav",
                mimeType: "audio/wav",
                data: WAVEncoder().encodePCM16Mono(audio.pcm16MonoLittleEndian, sampleRate: audio.sampleRate)
            )
            .finished()

        let (responseData, response) = try await OpenAIResponsesClient.perform(urlRequest, transport: transport)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.providerRejected
        }
        let envelope = try JSONDecoder().decode(OpenAITranscriptionEnvelope.self, from: responseData)
        guard !envelope.text.isEmpty else {
            throw ProviderError.providerRejected
        }
        return TranscriptionResult(requestID: audio.requestID, text: envelope.text)
    }

    private func readAPIKey() throws -> String {
        let key = try apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw ProviderError.missingSecret
        }
        return key
    }
}

protocol RealtimeWebSocket: AnyObject, Sendable {
    func sendString(_ text: String) async throws
    func receiveString() async throws -> String
    func cancel()
}

protocol RealtimeWebSocketFactory: Sendable {
    func makeWebSocket(request: URLRequest) -> RealtimeWebSocket
}

final class URLSessionRealtimeWebSocketFactory: RealtimeWebSocketFactory, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func makeWebSocket(request: URLRequest) -> RealtimeWebSocket {
        URLSessionRealtimeWebSocket(task: session.webSocketTask(with: request))
    }
}

private final class URLSessionRealtimeWebSocket: RealtimeWebSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
        task.resume()
    }

    func sendString(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receiveString() async throws -> String {
        switch try await task.receive() {
        case .string(let text):
            return text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw ProviderError.providerRejected
            }
            return text
        @unknown default:
            throw ProviderError.providerRejected
        }
    }

    func cancel() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

struct OpenAIRealtimeWhisperTranscriptionClient: SpeechClient {
    var configuration: OpenAIServiceConfiguration
    var endpoint: URL
    var timeout: TimeInterval
    var apiKeyProvider: @Sendable () throws -> String
    var userApprovedCloudProcessing: @Sendable () -> Bool
    var webSocketFactory: any RealtimeWebSocketFactory

    init(
        configuration: OpenAIServiceConfiguration = OpenAIServiceConfiguration(),
        endpoint: URL? = nil,
        timeout: TimeInterval = 30,
        apiKeyProvider: @escaping @Sendable () throws -> String,
        userApprovedCloudProcessing: @escaping @Sendable () -> Bool,
        webSocketFactory: any RealtimeWebSocketFactory = URLSessionRealtimeWebSocketFactory()
    ) {
        self.configuration = configuration
        self.endpoint = endpoint ?? URL(string: "wss://api.openai.com/v1/realtime?model=\(configuration.realtimeSessionModel)")!
        self.timeout = timeout
        self.apiKeyProvider = apiKeyProvider
        self.userApprovedCloudProcessing = userApprovedCloudProcessing
        self.webSocketFactory = webSocketFactory
    }

    func transcribe(_ audio: TranscriptionInput) async throws -> TranscriptionResult {
        guard userApprovedCloudProcessing() else {
            throw ProviderError.missingApproval
        }
        guard configuration.usesRealtimeTranscription else {
            throw ProviderError.unsupportedMode
        }

        let apiKey = try readAPIKey()
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("prismos-ios-babel", forHTTPHeaderField: "OpenAI-Safety-Identifier")

        let socket = webSocketFactory.makeWebSocket(request: request)
        defer {
            socket.cancel()
        }

        let pcm24k = PCM16Resampler().resample(
            audio.pcm16MonoLittleEndian,
            from: audio.sampleRate,
            to: OpenAIServiceConfiguration.realtimeTranscriptionSampleRate
        )

        try await socket.sendString(RealtimeTranscriptionEventFactory.sessionUpdateJSON(
            model: configuration.transcriptionModel,
            language: audio.language,
            delay: configuration.realtimeTranscriptionDelay
        ))
        try await socket.sendString(RealtimeTranscriptionEventFactory.appendAudioJSON(pcm24k))
        try await socket.sendString(RealtimeTranscriptionEventFactory.commitAudioJSON())

        let transcript = try await receiveCompletedTranscript(from: socket)
        guard !transcript.isEmpty else {
            throw ProviderError.providerRejected
        }
        return TranscriptionResult(requestID: audio.requestID, text: transcript)
    }

    private func readAPIKey() throws -> String {
        let key = try apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw ProviderError.missingSecret
        }
        return key
    }

    private func receiveCompletedTranscript(from socket: RealtimeWebSocket) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var deltaText = ""
                for _ in 0..<128 {
                    let message = try await socket.receiveString()
                    let data = Data(message.utf8)
                    let event = try JSONDecoder().decode(RealtimeTranscriptionServerEvent.self, from: data)
                    switch event.type {
                    case "conversation.item.input_audio_transcription.delta":
                        deltaText += event.delta ?? ""
                    case "conversation.item.input_audio_transcription.completed":
                        return event.transcript ?? deltaText
                    case "error":
                        throw ProviderError.providerRejected
                    default:
                        break
                    }
                }
                throw ProviderError.timeout
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ProviderError.timeout
            }
            let result = try await group.next() ?? ""
            group.cancelAll()
            return result
        }
    }
}

enum RealtimeTranscriptionEventFactory {
    static func sessionUpdateJSON(model: String, language: String?, delay: String) throws -> String {
        let request = RealtimeTranscriptionSessionUpdateEvent(
            session: .init(
                audio: .init(
                    input: .init(
                        format: .init(
                            rate: OpenAIServiceConfiguration.realtimeTranscriptionSampleRate
                        ),
                        transcription: .init(
                            model: model,
                            language: language,
                            delay: delay
                        )
                    )
                )
            )
        )
        return try encode(request)
    }

    static func appendAudioJSON(_ pcm16: Data) throws -> String {
        try encode(RealtimeTranscriptionAppendAudioEvent(audio: pcm16.base64EncodedString()))
    }

    static func commitAudioJSON() throws -> String {
        try encode(RealtimeTranscriptionCommitAudioEvent())
    }

    private static func encode(_ event: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ProviderError.providerRejected
        }
        return json
    }
}

private struct RealtimeTranscriptionSessionUpdateEvent: Encodable {
    let type = "session.update"
    var session: Session

    struct Session: Encodable {
        let type = "realtime"
        var audio: Audio
    }

    struct Audio: Encodable {
        var input: Input
    }

    struct Input: Encodable {
        var format: Format
        var transcription: Transcription
    }

    struct Format: Encodable {
        let type = "audio/pcm"
        var rate: Int
    }

    struct Transcription: Encodable {
        var model: String
        var language: String?
        var delay: String?
    }
}

private struct RealtimeTranscriptionAppendAudioEvent: Encodable {
    let type = "input_audio_buffer.append"
    var audio: String
}

private struct RealtimeTranscriptionCommitAudioEvent: Encodable {
    let type = "input_audio_buffer.commit"
}

private struct RealtimeTranscriptionServerEvent: Decodable {
    var type: String
    var delta: String?
    var transcript: String?
}

private struct PCM16Resampler {
    func resample(_ pcmData: Data, from inputRate: Int, to outputRate: Int) -> Data {
        guard inputRate > 0, outputRate > 0, inputRate != outputRate else {
            return pcmData
        }
        let inputSampleCount = pcmData.count / 2
        guard inputSampleCount > 0 else {
            return pcmData
        }
        let outputSampleCount = max(1, Int((Double(inputSampleCount) * Double(outputRate) / Double(inputRate)).rounded()))
        var output = Data()
        output.reserveCapacity(outputSampleCount * 2)
        for outputIndex in 0..<outputSampleCount {
            let sourceIndex = min(
                inputSampleCount - 1,
                Int(Double(outputIndex) * Double(inputRate) / Double(outputRate))
            )
            let byteIndex = sourceIndex * 2
            output.append(pcmData[byteIndex])
            output.append(pcmData[byteIndex + 1])
        }
        return output
    }
}

private struct OpenAIResponsesRequest: Encodable {
    var model: String
    var input: OpenAIResponsesInput
    var store: Bool
    var reasoning: OpenAIResponsesReasoning
    var text: OpenAIResponsesText
}

private enum OpenAIResponsesInput: Encodable {
    case text(String)
    case content([OpenAIResponsesContentInput])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .content(let content):
            try container.encode([OpenAIResponsesContentMessage(role: "user", content: content)])
        }
    }
}

private struct OpenAIResponsesContentMessage: Encodable {
    var role: String
    var content: [OpenAIResponsesContentInput]
}

private struct OpenAIResponsesContentInput: Encodable {
    var type: String
    var text: String?
    var imageURL: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct OpenAIResponsesReasoning: Encodable {
    var effort: String
}

private struct OpenAIResponsesText: Encodable {
    var verbosity: String
}

private struct OpenAIResponsesEnvelope: Decodable {
    var outputText: String?
    var output: [OpenAIResponsesOutput]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var responseText: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }
        let contentText = output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
        return contentText?.isEmpty == false ? contentText : nil
    }
}

private struct OpenAIResponsesOutput: Decodable {
    var content: [OpenAIResponsesContent]?
}

private struct OpenAIResponsesContent: Decodable {
    var type: String?
    var text: String?
}

private struct OpenAITranscriptionEnvelope: Decodable {
    var text: String
}

private struct WAVEncoder {
    func encodePCM16Mono(_ pcmData: Data, sampleRate: Int) -> Data {
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.appendUInt32LittleEndian(UInt32(36 + pcmData.count))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendUInt32LittleEndian(16)
        data.appendUInt16LittleEndian(1)
        data.appendUInt16LittleEndian(1)
        data.appendUInt32LittleEndian(UInt32(sampleRate))
        data.appendUInt32LittleEndian(UInt32(sampleRate * 2))
        data.appendUInt16LittleEndian(2)
        data.appendUInt16LittleEndian(16)
        data.append(contentsOf: "data".utf8)
        data.appendUInt32LittleEndian(UInt32(pcmData.count))
        data.append(pcmData)
        return data
    }
}

private struct MultipartFormData {
    var boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func addingField(named name: String, value: String) -> Self {
        var copy = self
        copy.data.append(contentsOf: "--\(boundary)\r\n".utf8)
        copy.data.append(contentsOf: "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8)
        copy.data.append(contentsOf: "\(value)\r\n".utf8)
        return copy
    }

    func addingFile(named name: String, filename: String, mimeType: String, data fileData: Data) -> Self {
        var copy = self
        copy.data.append(contentsOf: "--\(boundary)\r\n".utf8)
        copy.data.append(contentsOf: "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8)
        copy.data.append(contentsOf: "Content-Type: \(mimeType)\r\n\r\n".utf8)
        copy.data.append(fileData)
        copy.data.append(contentsOf: "\r\n".utf8)
        return copy
    }

    func finished() -> Data {
        var copy = data
        copy.append(contentsOf: "--\(boundary)--\r\n".utf8)
        return copy
    }
}

private extension Data {
    mutating func appendUInt16LittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
