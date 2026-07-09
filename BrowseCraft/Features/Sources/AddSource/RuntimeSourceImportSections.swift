import Foundation
import SwiftUI

struct RuntimeSourceImportInputSection: View {
    @Binding var entryURL: String
    let isWorking: Bool

    var body: some View {
        Section("Source") {
            TextField("URL", text: self.$entryURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .disabled(self.isWorking)
        }
    }
}

extension RuntimeSourceImportKind: Identifiable {
    var id: String {
        return self.rawValue
    }
}
