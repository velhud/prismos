import Foundation
import PrismAI
import PrismDiagnostics

@MainActor
final class ServiceConsoleModel: ObservableObject {
    enum ProviderKeyStatus: String {
        case missing = "Missing"
        case stored = "Stored in Keychain"
        case unavailable = "Keychain Unavailable"
        case error = "Error"
    }

    @Published var providerMode: ProviderMode = .offline
    @Published var transcriptionMode: ProviderMode = .offline
    @Published var visionMode: ProviderMode = .appleOnDevice
    @Published var translationMode: ProviderMode = .offline
    @Published var requireCloudApproval = true
    @Published var openAITextModelID = OpenAIServiceConfiguration.defaultTextModel
    @Published var openAIVisionModelID = OpenAIServiceConfiguration.defaultVisionModel
    @Published var openAITranslationModelID = OpenAIServiceConfiguration.defaultTranslationModel
    @Published var openAITranscriptionModelID = OpenAIServiceConfiguration.defaultTranscriptionModel
    @Published var openAIRealtimeSessionModelID = OpenAIServiceConfiguration.defaultRealtimeSessionModel
    @Published var openAIRealtimeTranscriptionDelay = OpenAIServiceConfiguration.defaultRealtimeTranscriptionDelay
    @Published var openAIReasoningEffort = "low"
    @Published var openAITextVerbosity = "low"
    @Published var openAIStoreResponses = false
    @Published var diagnosticsRawMode = false
    @Published private(set) var providerKeyStatus: ProviderKeyStatus = .missing
    @Published private(set) var diagnosticsPreview: [String] = []
    @Published private(set) var diagnosticsExportSummary = "No export created"

    private let secretStore: SecretStore
    private let redactor = DiagnosticsRedactor()
    private let providerKey = "openai.api_key"

    init(secretStore: SecretStore = KeychainSecretStore()) {
        self.secretStore = secretStore
        refreshProviderKeyStatus()
        refreshDiagnosticsPreview()
    }

    func saveProviderKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteProviderKey()
            return
        }
        do {
            try secretStore.save(trimmed, for: providerKey)
            providerKeyStatus = .stored
        } catch SecretStoreError.unexpectedStatus(errSecMissingEntitlement) {
            providerKeyStatus = .unavailable
        } catch {
            providerKeyStatus = .error
        }
        refreshDiagnosticsPreview()
    }

    func deleteProviderKey() {
        do {
            try secretStore.delete(providerKey)
            providerKeyStatus = .missing
        } catch {
            providerKeyStatus = .error
        }
        refreshDiagnosticsPreview()
    }

    func refreshProviderKeyStatus() {
        do {
            _ = try secretStore.read(providerKey)
            providerKeyStatus = .stored
        } catch SecretStoreError.notFound {
            providerKeyStatus = .missing
        } catch SecretStoreError.unexpectedStatus(errSecMissingEntitlement) {
            providerKeyStatus = .unavailable
        } catch {
            providerKeyStatus = .error
        }
    }

    func providerOfflineMessage() -> String {
        providerMode == .offline ? "Provider offline" : "Provider selectable"
    }

    func readProviderKey() throws -> String {
        try secretStore.read(providerKey)
    }

    func openAIConfiguration() -> OpenAIServiceConfiguration {
        OpenAIServiceConfiguration(
            textModel: openAITextModelID,
            visionModel: openAIVisionModelID,
            translationModel: openAITranslationModelID,
            transcriptionModel: openAITranscriptionModelID,
            realtimeSessionModel: openAIRealtimeSessionModelID,
            realtimeTranscriptionDelay: openAIRealtimeTranscriptionDelay,
            reasoningEffort: openAIReasoningEffort,
            textVerbosity: openAITextVerbosity,
            storeResponses: openAIStoreResponses
        )
    }

    func refreshDiagnosticsPreview() {
        let event = DiagnosticsEvent(
            category: .provider,
            redactedMessage: "Provider key: sk-preview",
            metadata: ["authorization": "Bearer sk-preview"]
        )
        diagnosticsPreview = redactor.export(events: [event], includePrivateContent: diagnosticsRawMode).previewLines
    }

    func createRedactedDiagnosticsExport() {
        let events = [
            DiagnosticsEvent(
                category: .bluetooth,
                redactedMessage: "Lifecycle: restoredByCoreBluetooth",
                metadata: ["state": "restored"]
            ),
            DiagnosticsEvent(
                category: .provider,
                redactedMessage: "Authorization: Bearer sk-preview",
                metadata: ["api_key": "sk-preview"]
            )
        ]
        let export = redactor.export(events: events, includePrivateContent: false)
        diagnosticsPreview = export.previewLines
        diagnosticsRawMode = false
        diagnosticsExportSummary = "Redacted export ready: \(export.entries.count) event(s)"
    }
}
