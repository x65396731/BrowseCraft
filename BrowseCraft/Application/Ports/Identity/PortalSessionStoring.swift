import Foundation

protocol PortalSessionStoring: Sendable {
    func load() throws -> PortalSessionPersistence?
    func save(_ session: PortalSessionPersistence) throws
}
