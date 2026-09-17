import SwiftUI
import UniformTypeIdentifiers

// 中文注释：BookShelfView 是 Library 里的本地书架：导入入口、书列表、删除、进入阅读器。

struct BookShelfView: View {
    @Bindable var viewModel: BookShelfViewModel
    @State private var isImporterPresented: Bool = false

    private static let allowedContentTypes: [UTType] = [
        .epub,
        .mp3,
        .mpeg4Audio,
        .zip,
    ]

    var body: some View {
        List {
            ForEach(self.viewModel.items, id: \.book.id) { item in
                NavigationLink(value: LibraryBookRoute.book(item.book)) {
                    BookShelfRowView(item: item, coverURL: self.viewModel.coverURL(for: item.book))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task {
                            await self.viewModel.delete(item.book)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .overlay {
            if self.viewModel.items.isEmpty && self.viewModel.isImporting == false {
                EmptyStateView(
                    systemImage: "books.vertical",
                    title: NSLocalizedString("No books yet", comment: "书架空态标题"),
                    message: NSLocalizedString("Import EPUB or audiobook files from Files.", comment: "书架空态说明")
                )
            } else if self.viewModel.isImporting {
                ProgressView("Importing…")
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle("Books")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    self.isImporterPresented = true
                } label: {
                    Label("Import Book", systemImage: "plus")
                }
                .disabled(self.viewModel.isImporting)
            }
        }
        .fileImporter(
            isPresented: self.$isImporterPresented,
            allowedContentTypes: Self.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await self.viewModel.importBooks(from: urls)
                }
            case .failure(let error):
                self.viewModel.errorMessage = error.localizedDescription
            }
        }
        .alert("Import failed", isPresented: self.errorAlertBinding) {
            Button("OK", role: .cancel) {
                self.viewModel.errorMessage = nil
            }
        } message: {
            Text(self.viewModel.errorMessage ?? "")
        }
        .task {
            await self.viewModel.load()
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        return Binding<Bool>(
            get: { self.viewModel.errorMessage != nil },
            set: { newValue in
                if newValue == false {
                    self.viewModel.errorMessage = nil
                }
            }
        )
    }
}

private struct BookShelfRowView: View {
    let item: LocalBookShelfItem
    let coverURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            self.cover
                .frame(width: 44, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 4) {
                Text(self.item.book.title)
                    .font(.body)
                    .lineLimit(2)
                if let author: String = self.item.book.author, author.isEmpty == false {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(self.item.book.format == .epub ? "EPUB" : "Audiobook")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let progression: Double = self.item.totalProgression {
                        ProgressView(value: progression)
                            .frame(maxWidth: 120)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var cover: some View {
        if let url: URL = self.coverURL, let image: UIImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.secondary.opacity(0.15)
                Image(systemName: self.item.book.format == .epub ? "book.closed" : "headphones")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
