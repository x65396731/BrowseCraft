import Foundation

final class LibraryTabValidationCoordinator {
    private let validateSourceTabsUseCase: ValidateSourceTabsUseCase?
    private var attemptedSourceIDs: Set<String> = []

    init(validateSourceTabsUseCase: ValidateSourceTabsUseCase?) {
        self.validateSourceTabsUseCase = validateSourceTabsUseCase
    }

    func claimValidation(for source: Source) -> Bool {
        guard self.validateSourceTabsUseCase != nil,
              source.configuration.kind != .plugin,
              self.attemptedSourceIDs.contains(source.id) == false else {
            return false
        }

        self.attemptedSourceIDs.insert(source.id)
        return true
    }

    func validate(source: Source) async -> SourceTabsValidationResult? {
        guard let validateSourceTabsUseCase: ValidateSourceTabsUseCase else {
            return nil
        }

        return await validateSourceTabsUseCase.execute(source: source)
    }
}
