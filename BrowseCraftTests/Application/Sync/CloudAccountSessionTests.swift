import Foundation
import Testing
@testable import BrowseCraft

struct CloudAccountSessionTests {
    @Test func legacyEnabledAccountMigratesToExplicitStartupConsent() throws {
        let suiteName: String = "BrowseCraftCloudSyncPreferenceTests-\(UUID().uuidString)"
        let defaults: UserDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(true, forKey: "test.cloudSyncEnabled.cloud.legacy-account")
        let store: UserDefaultsCloudSyncPreferenceStore = UserDefaultsCloudSyncPreferenceStore(
            userDefaults: defaults,
            keyPrefix: "test.cloudSyncEnabled",
            consentKey: "test.cloudSyncUserConsent"
        )

        #expect(store.hasCloudSyncUserConsent())
        #expect(defaults.bool(forKey: "test.cloudSyncUserConsent"))

        store.setCloudSyncUserConsent(false)
        #expect(store.hasCloudSyncUserConsent() == false)
    }

    @Test func startupDefersAccountMonitoringUntilUserHasEnabledCloudSync() async {
        let provider: MockCloudAccountStateProvider = MockCloudAccountStateProvider()
        let preferences: MockCloudSyncPreferenceStore = MockCloudSyncPreferenceStore()
        let session: CloudAccountSession = CloudAccountSession(
            stateProvider: provider,
            preferenceStore: preferences
        )

        await session.startIfPreviouslyEnabled()
        let callsBeforeConsent: Int = await provider.startMonitoringCallCount()
        let snapshotBeforeConsent: CloudAccountSessionSnapshot = await session.snapshot()
        #expect(callsBeforeConsent == 0)
        #expect(snapshotBeforeConsent.state.availability == .notChecked)

        preferences.setCloudSyncUserConsent(true)
        await session.startIfPreviouslyEnabled()
        let callsAfterConsent: Int = await provider.startMonitoringCallCount()
        #expect(callsAfterConsent == 1)
    }

    @Test func availableAccountEnablesOnlyItsOwnPreference() async {
        let provider: MockCloudAccountStateProvider = MockCloudAccountStateProvider()
        let preferences: MockCloudSyncPreferenceStore = MockCloudSyncPreferenceStore()
        let session: CloudAccountSession = CloudAccountSession(
            stateProvider: provider,
            preferenceStore: preferences
        )
        let accountA: CloudAccountScope = .cloud(hash: "account-a")
        let accountB: CloudAccountScope = .cloud(hash: "account-b")

        await provider.setState(
            CloudAccountState(availability: .available, scope: accountA)
        )
        await session.refresh()
        await session.setCloudSyncEnabled(true)

        var snapshot: CloudAccountSessionSnapshot = await session.snapshot()
        #expect(snapshot.state.scope == accountA)
        #expect(snapshot.generation == 1)
        #expect(snapshot.isSynchronizationEnabled)
        #expect(preferences.hasCloudSyncUserConsent())

        await provider.setState(
            CloudAccountState(availability: .available, scope: accountB)
        )
        await session.refresh()

        snapshot = await session.snapshot()
        #expect(snapshot.state.scope == accountB)
        #expect(snapshot.generation == 2)
        #expect(snapshot.accountPreferenceEnabled == false)
        #expect(snapshot.isSynchronizationEnabled == false)

        await provider.setState(
            CloudAccountState(availability: .available, scope: accountA)
        )
        await session.refresh()

        snapshot = await session.snapshot()
        #expect(snapshot.accountPreferenceEnabled)
        #expect(snapshot.isSynchronizationEnabled)
    }

    @Test func temporarilyUnavailableInvalidatesSyncGenerationButRetainsScope() async {
        let provider: MockCloudAccountStateProvider = MockCloudAccountStateProvider()
        let preferences: MockCloudSyncPreferenceStore = MockCloudSyncPreferenceStore()
        let session: CloudAccountSession = CloudAccountSession(
            stateProvider: provider,
            preferenceStore: preferences
        )
        let scope: CloudAccountScope = .cloud(hash: "account-a")

        await provider.setState(
            CloudAccountState(availability: .available, scope: scope)
        )
        await session.refresh()
        await session.setCloudSyncEnabled(true)
        let availableSnapshot: CloudAccountSessionSnapshot = await session.snapshot()

        await provider.setState(
            CloudAccountState(availability: .temporarilyUnavailable, scope: scope)
        )
        await session.refresh()
        let unavailableSnapshot: CloudAccountSessionSnapshot = await session.snapshot()

        #expect(unavailableSnapshot.state.scope == scope)
        #expect(unavailableSnapshot.generation == availableSnapshot.generation + 1)
        #expect(unavailableSnapshot.accountPreferenceEnabled)
        #expect(unavailableSnapshot.isSynchronizationEnabled == false)
    }

    @Test func localDefaultCannotEnableCloudSync() async {
        let provider: MockCloudAccountStateProvider = MockCloudAccountStateProvider(
            state: CloudAccountState(availability: .noAccount, scope: .localDefault)
        )
        let preferences: MockCloudSyncPreferenceStore = MockCloudSyncPreferenceStore()
        let session: CloudAccountSession = CloudAccountSession(
            stateProvider: provider,
            preferenceStore: preferences
        )

        await session.refresh()
        await session.setCloudSyncEnabled(true)
        let snapshot: CloudAccountSessionSnapshot = await session.snapshot()

        #expect(snapshot.state.scope == .localDefault)
        #expect(snapshot.accountPreferenceEnabled == false)
        #expect(snapshot.isSynchronizationEnabled == false)
    }

    @Test func disablingCloudSyncClearsStartupConsentEvenDuringAnAccountOutage() async {
        let provider: MockCloudAccountStateProvider = MockCloudAccountStateProvider()
        let preferences: MockCloudSyncPreferenceStore = MockCloudSyncPreferenceStore()
        let session: CloudAccountSession = CloudAccountSession(
            stateProvider: provider,
            preferenceStore: preferences
        )
        let scope: CloudAccountScope = .cloud(hash: "account-a")

        await provider.setState(CloudAccountState(availability: .available, scope: scope))
        await session.refresh()
        await session.setCloudSyncEnabled(true)
        await provider.setState(
            CloudAccountState(availability: .temporarilyUnavailable, scope: scope)
        )
        await session.refresh()

        await session.setCloudSyncEnabled(false)
        let snapshot: CloudAccountSessionSnapshot = await session.snapshot()

        #expect(snapshot.accountPreferenceEnabled == false)
        #expect(preferences.hasCloudSyncUserConsent() == false)
    }

    @Test func accountStateUpdatesSynchronousRepositoryScopeSnapshot() async {
        let provider: MockCloudAccountStateProvider = MockCloudAccountStateProvider()
        let activeScopeStore: ActiveAccountScopeStore = ActiveAccountScopeStore()
        let session: CloudAccountSession = CloudAccountSession(
            stateProvider: provider,
            preferenceStore: MockCloudSyncPreferenceStore(),
            activeScopeStore: activeScopeStore
        )
        let cloudScope: CloudAccountScope = .cloud(hash: "account-a")

        await provider.setState(
            CloudAccountState(availability: .available, scope: cloudScope)
        )
        await session.refresh()

        #expect(activeScopeStore.currentScope == cloudScope)

        await provider.setState(
            CloudAccountState(availability: .noAccount, scope: .localDefault)
        )
        await session.refresh()

        #expect(activeScopeStore.currentScope == .localDefault)
    }
}
