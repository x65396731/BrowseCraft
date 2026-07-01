import Combine
import Foundation

/// ViewModel for the Sources tab.
///
/// SwiftUI observes this object. Whenever an @Published value changes, SwiftUI
/// redraws the parts of SourcesView that read that value.
final class SourcesViewModel: ObservableObject {
    @Published private(set) var sources: [Source] = []
    @Published var selectedSourceID: String?
    @Published var errorMessage: String?
    @Published private(set) var isRefreshing: Bool = false

    private let loadSourcesUseCase: LoadSourcesUseCase
    private let addSourceUseCase: AddSourceUseCase
    private let refreshSourceUseCase: RefreshSourceUseCase

    init(
        loadSourcesUseCase: LoadSourcesUseCase,
        addSourceUseCase: AddSourceUseCase,
        refreshSourceUseCase: RefreshSourceUseCase
    ) {
        self.loadSourcesUseCase = loadSourcesUseCase
        self.addSourceUseCase = addSourceUseCase
        self.refreshSourceUseCase = refreshSourceUseCase
    }

    @MainActor
    func load() {
        do {
            let loadedSources: [Source] = try self.loadSourcesUseCase.execute()
            self.sources = loadedSources

            if self.selectedSourceID == nil {
                self.selectedSourceID = loadedSources.first?.id
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func addSource(name: String, baseURL: String, ruleJSON: String) -> Bool {
        do {
            let source: Source = try self.addSourceUseCase.execute(
                name: name,
                baseURL: baseURL,
                ruleJSON: ruleJSON
            )

            self.load()
            self.selectedSourceID = source.id
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func refreshSelectedSource() async {
        guard let selectedSource: Source = self.selectedSource else {
            return
        }

        self.isRefreshing = true

        do {
            _ = try await self.refreshSourceUseCase.execute(source: selectedSource)
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.isRefreshing = false
    }

    var selectedSource: Source? {
        return self.sources.first { source in
            return source.id == self.selectedSourceID
        }
    }
}
