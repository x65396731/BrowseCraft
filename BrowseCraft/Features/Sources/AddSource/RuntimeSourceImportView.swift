import Foundation
import SwiftUI

// 中文注释：RuntimeSourceImportView 是统一添加源外壳，添加流程只保留用户输入和保存动作。
struct RuntimeSourceImportView: View {
    private enum OperationState: Equatable {
        case idle
        case saving
        case saved
        case error(String)

        var isWorking: Bool {
            switch self {
            case .saving:
                return true
            case .idle, .saved, .error:
                return false
            }
        }
    }

    @ObservedObject var viewModel: SourcesViewModel
    let kind: RuntimeSourceImportKind
    let completion: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var entryURL: String = ""
    @State private var operationState: OperationState = .idle

    var body: some View {
        NavigationStack {
            Form {
                RuntimeSourceImportInputSection(
                    entryURL: self.$entryURL,
                    isWorking: self.operationState.isWorking
                )

                if let message: String = self.statusMessage {
                    Section("Status") {
                        Text(message)
                            .foregroundStyle(self.statusForegroundStyle)
                    }
                }
            }
            .navigationTitle("Add Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        self.dismiss()
                    }
                    .disabled(self.operationState.isWorking)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await self.save()
                        }
                    }
                    .disabled(self.canSave == false)
                }
            }
        }
    }

    private var trimmedEntryURL: String {
        return self.entryURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        return self.trimmedEntryURL.isEmpty == false
            && self.operationState.isWorking == false
    }

    private var statusMessage: String? {
        switch self.operationState {
        case .idle:
            return nil
        case .saving:
            return "Saving source..."
        case .saved:
            return "Source saved."
        case .error(let message):
            return message
        }
    }

    private var statusForegroundStyle: Color {
        switch self.operationState {
        case .error:
            return .red
        case .saved:
            return .green
        case .idle, .saving:
            return .secondary
        }
    }

    @MainActor
    private func save() async {
        self.operationState = .saving

        switch self.kind {
        case .comic:
            await self.saveComic()
        case .rss:
            await self.saveRSS()
        case .video:
            await self.saveVideo()
        }
    }

    @MainActor
    private func saveComic() async {
        let didSave: Bool = await self.viewModel.addRuleSource(
            name: self.defaultSourceName,
            baseURL: self.trimmedEntryURL,
            ruleJSON: Self.makeComicRuleDraftJSON(
                entryURLString: self.trimmedEntryURL,
                name: self.defaultSourceName
            )
        )

        guard didSave else {
            self.operationState = .error(self.viewModel.errorMessage ?? "Failed to save comic source.")
            return
        }

        self.finishSaved()
    }

    @MainActor
    private func saveRSS() async {
        let source: Source? = await self.viewModel.addRSSSource(
            feedURLString: self.entryURL,
            name: self.defaultSourceName
        )

        guard source != nil else {
            self.operationState = .error(self.viewModel.errorMessage ?? "Failed to save RSS source.")
            return
        }

        self.finishSaved()
    }

    @MainActor
    private func saveVideo() async {
        let source: Source? = await self.viewModel.addManualVideoSource(
            entryURLString: self.entryURL,
            name: self.defaultSourceName,
            configuration: ManualVideoSourceConfigurationDraft(
                adapter: .genericHTML,
                entryKind: .play
            )
        )

        guard source != nil else {
            self.operationState = .error(self.viewModel.errorMessage ?? "Failed to save video source.")
            return
        }

        self.finishSaved()
    }

    @MainActor
    private func finishSaved() {
        self.operationState = .saved
        self.completion()
        self.dismiss()
    }

    private var defaultSourceName: String {
        return URL(string: self.trimmedEntryURL)?.host ?? "Comic Source"
    }

    private static func makeComicRuleDraftJSON(entryURLString: String, name: String?) -> String {
        let baseURL: String = entryURLString
        let trimmedName: String? = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceName: String
        if let trimmedName: String, trimmedName.isEmpty == false {
            sourceName = trimmedName
        } else {
            sourceName = URL(string: baseURL)?.host ?? "Comic Source"
        }
        let draft: [String: Any] = [
            "name": sourceName,
            "baseUrl": baseURL,
            "list": [
                "url": baseURL,
                "item": ".comic-item",
                "title": ".title",
                "link": "a@href",
                "cover": "img@data-src|src",
                "type": "comic",
                "latestText": ".latest"
            ],
            "detail": [
                "title": "h1",
                "cover": ".cover img@data-src|src",
                "chapterContainer": ".chapter-list",
                "chapterItem": ".chapter-list a",
                "chapterTitle": "this",
                "chapterLink": "this@href"
            ],
            "gallery": [
                "imageItem": ".reader img",
                "imageUrl": "this@data-src|src"
            ]
        ]

        guard JSONSerialization.isValidJSONObject(draft),
              let data: Data = try? JSONSerialization.data(
                withJSONObject: draft,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let json: String = String(data: data, encoding: .utf8) else {
            return SiteRule.exampleJSON
        }

        return json
    }
}
