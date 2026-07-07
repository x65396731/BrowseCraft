import Foundation
import BrowseCraftCore

enum SourceListLoadValidationError: LocalizedError, Equatable {
    case emptyList

    var errorDescription: String? {
        switch self {
        case .emptyList:
            return "The source loaded successfully but returned no items."
        }
    }
}

struct ValidateSourceListLoadUseCase {
    func execute(_ output: SourceListOutput) throws {
        if output.items.isEmpty {
            throw SourceListLoadValidationError.emptyList
        }
    }
}
