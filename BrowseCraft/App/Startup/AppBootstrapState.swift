import Foundation

enum AppBootstrapState {
    case loading
    case ready(AppContainer)
    case failed(AppBootstrapFailure)

    @MainActor
    static func bootstrap(
        loader: AppBootstrapLoader = AppBootstrapLoader()
    ) async -> AppBootstrapState {
        do {
            let dependencies: AppBootstrapDependencies = try await loader.load()
            return .ready(try AppContainer(bootstrap: dependencies))
        } catch {
            return .failed(AppBootstrapFailure(error: error))
        }
    }
}

struct AppBootstrapFailure: Equatable {
    let diagnosticCode: String
    let title: String
    let message: String
    let recoverySuggestion: String

    init(error: any Error) {
        self.diagnosticCode = Self.diagnosticCode(for: error)
        self.title = "BrowseCraft couldn’t start"
        self.message = "The app couldn’t open its local data safely. Your data was not deleted or reset."
        self.recoverySuggestion = "Quit and reopen the app. If the problem continues, include the diagnostic code when requesting support."
    }

    private static func diagnosticCode(for error: any Error) -> String {
        let typeName: String = String(reflecting: type(of: error))
        let stableValue: UInt64 = typeName.utf8.reduce(1_469_598_103_934_665_603) { partial, byte in
            return (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return "BOOT-\(String(stableValue, radix: 16, uppercase: true))"
    }
}
