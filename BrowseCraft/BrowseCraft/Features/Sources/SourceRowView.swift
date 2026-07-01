import SwiftUI

struct SourceRowView: View {
    let source: Source
    let isSelected: Bool
    let selectAction: () -> Void

    var body: some View {
        Button(
            action: {
                self.selectAction()
            },
            label: {
                HStack(spacing: 12) {
                    Image(systemName: self.isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(self.isSelected ? .green : .secondary)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(self.source.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(self.source.baseURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        )
        .buttonStyle(.plain)
    }
}
