import Foundation
import Testing
@testable import BrowseCraft

@MainActor
struct StartupCoordinatorTests {
    private enum StubError: Error {
        case failed
    }

    @Test func noSourcesUnlocksSourcesDestination() async {
        let coordinator: StartupCoordinator = StartupCoordinator(
            dependencies: StartupCoordinator.Dependencies(
                hasSources: { false },
                loadSelectedSource: { .loaded }
            )
        )

        coordinator.start()
        await Self.drainTasks()

        #expect(coordinator.phase == .noSources)
        #expect(coordinator.skip() == .sources)
        #expect(coordinator.phase == .dismissed(destination: .sources))
    }

    @Test func sourceCheckFailureUnlocksSourcesDestination() async {
        let coordinator: StartupCoordinator = StartupCoordinator(
            dependencies: StartupCoordinator.Dependencies(
                hasSources: { throw StubError.failed },
                loadSelectedSource: { .loaded }
            )
        )

        coordinator.start()
        await Self.drainTasks()

        #expect(coordinator.phase == .sourceCheckFailed)
    }

    @Test func loadedSourceUnlocksLibraryDestination() async {
        let coordinator: StartupCoordinator = StartupCoordinator(
            dependencies: StartupCoordinator.Dependencies(
                hasSources: { true },
                loadSelectedSource: { .loaded }
            )
        )

        coordinator.start()
        await Self.drainTasks()

        #expect(coordinator.phase == .sourceLoaded)
    }

    @Test func timeoutUnlocksWithoutCancellingSourceLoad() async throws {
        let coordinator: StartupCoordinator = StartupCoordinator(
            policy: StartupPolicy(sourceLoadTimeout: .milliseconds(1)),
            dependencies: StartupCoordinator.Dependencies(
                hasSources: { true },
                loadSelectedSource: {
                    try? await Task.sleep(for: .seconds(1))
                    return .loaded
                }
            )
        )

        coordinator.start()
        try await Task.sleep(for: .milliseconds(20))

        #expect(coordinator.phase == .sourceLoadTimedOut)
    }

    private static func drainTasks() async {
        for _ in 0..<12 {
            await Task.yield()
        }
    }
}
