import SwiftUI

struct RSSHistoryDetailView: View {
    let history: RSSReadingHistory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(self.history.title)
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    if let sourceName: String = self.history.sourceName {
                        Label(sourceName, systemImage: "dot.radiowaves.left.and.right")
                    }

                    Label(Self.dateFormatter.string(from: self.history.dataTime), systemImage: "calendar")
                    Label(Self.dateFormatter.string(from: self.history.visitedAt), systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                if let content: String = RSSContentTextFormatter.sanitized(self.history.dataContent) {
                    Text(content)
                        .font(.body)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let detailURL: URL = self.history.detailURL {
                    Link(destination: detailURL) {
                        Label("Open Original", systemImage: "safari")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .navigationTitle("RSS")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
