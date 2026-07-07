import Foundation
import SwiftUI

struct RuntimeSourceImportInputSection: View {
    @Binding var entryURL: String
    @Binding var sourceName: String
    let requestButtonTitle: String
    let isWorking: Bool
    let canRequest: Bool
    let requestAction: () -> Void

    var body: some View {
        Section("Source") {
            TextField("URL", text: self.$entryURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .disabled(self.isWorking)

            TextField("Name (Optional)", text: self.$sourceName)
                .disabled(self.isWorking)

            Button(self.requestButtonTitle, action: self.requestAction)
                .disabled(self.canRequest == false)
        }
    }
}

struct RuntimeSourceImportSummarySection: View {
    let kind: RuntimeSourceImportKind

    var body: some View {
        Section("Runtime") {
            LabeledContent("Type", value: self.kind.displayTitle)
            Text(self.kind.addSummary)
                .foregroundStyle(.secondary)
        }
    }
}

struct RuntimeSourceImportDebugEntrySection: View {
    let canOpenDebug: Bool
    let openAction: () -> Void

    var body: some View {
        Section("Debug") {
            Button("Debug", action: self.openAction)
                .disabled(self.canOpenDebug == false)
        }
    }
}

struct RuntimeSourceImportRequestResultSection: View {
    let preview: RuntimeSourcePreviewResult

    var body: some View {
        Section("Request Result") {
            Text(self.preview.summary)
            ForEach(self.preview.logLines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

extension RuntimeSourceImportKind: Identifiable {
    var id: String {
        return self.rawValue
    }
}

extension RuntimeSourceImportKind {
    var displayTitle: String {
        switch self {
        case .comic:
            return "Comics"
        case .rss:
            return "RSS"
        case .video:
            return "Video"
        }
    }

    var addSummary: String {
        switch self {
        case .comic:
            return "Request a website, edit Rule JSON, then save after library list load succeeds."
        case .rss:
            return "Request a feed URL, then save after library list load succeeds."
        case .video:
            return "Request a video URL and inspect logs. Saving requires a valid manual video rule."
        }
    }

    var debugSummary: String {
        switch self {
        case .comic:
            return "Debug current Rule JSON with the rule list pipeline."
        case .rss:
            return "Debug feed request and RSS/Atom parser output."
        case .video:
            return "Inspect video URL facts and logs without adapter inference."
        }
    }
}
