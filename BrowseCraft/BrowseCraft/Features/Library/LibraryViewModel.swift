import Combine
import Foundation

final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [ContentItem] = []
    @Published private(set) var sources: [Source] = []
    @Published private(set) var favoriteItemIDs: Set<String> = []
    @Published var errorMessage: String?

    private let loadLibraryUseCase: LoadLibraryUseCase
    private let loadSourcesUseCase: LoadSourcesUseCase
    private let toggleFavoriteUseCase: ToggleFavoriteUseCase
    private let recordOpenItemUseCase: RecordOpenItemUseCase

    init(
        loadLibraryUseCase: LoadLibraryUseCase,
        loadSourcesUseCase: LoadSourcesUseCase,
        toggleFavoriteUseCase: ToggleFavoriteUseCase,
        recordOpenItemUseCase: RecordOpenItemUseCase
    ) {
        self.loadLibraryUseCase = loadLibraryUseCase
        self.loadSourcesUseCase = loadSourcesUseCase
        self.toggleFavoriteUseCase = toggleFavoriteUseCase
        self.recordOpenItemUseCase = recordOpenItemUseCase
    }

    @MainActor
    func load() {
        do {
            self.items = try self.loadLibraryUseCase.execute()
            self.sources = try self.loadSourcesUseCase.execute()
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.loadFavoriteItemIDs()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func toggleFavorite(item: ContentItem) {
        do {
            self.favoriteItemIDs = try self.toggleFavoriteUseCase.execute(itemId: item.id)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func recordOpened(item: ContentItem) {
        do {
            try self.recordOpenItemUseCase.execute(itemId: item.id)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func sourceName(for sourceId: String) -> String {
        let source: Source? = self.sources.first { source in
            return source.id == sourceId
        }

        return source?.name ?? "Unknown Source"
    }
}
