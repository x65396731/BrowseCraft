import SwiftUI

struct ReaderChapterNavigationBar: View {
    let previousChapterURL: String?
    let nextChapterURL: String?
    let loadPrevious: () async -> Void
    let loadNext: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await self.loadPrevious()
                }
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(self.isBlank(self.previousChapterURL))

            Button {
                Task {
                    await self.loadNext()
                }
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.isBlank(self.nextChapterURL))
        }
    }

    private func isBlank(_ value: String?) -> Bool {
        guard let value: String = value else {
            return true
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
