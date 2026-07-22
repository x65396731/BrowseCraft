import Testing
@testable import BrowseCraft

struct CloudAccountScopeDeriverTests {
    @Test func derivationIsStableAndDoesNotExposeRecordName() {
        let deriver: CloudAccountScopeDeriver = CloudAccountScopeDeriver()
        let recordName: String = "opaque-user-record-name"

        let first: CloudAccountScope = deriver.derive(
            containerIdentifier: "iCloud.com.xiefei.AnyPortal",
            userRecordName: recordName
        )
        let second: CloudAccountScope = deriver.derive(
            containerIdentifier: "iCloud.com.xiefei.AnyPortal",
            userRecordName: recordName
        )

        #expect(first == second)
        #expect(first.isCloud)
        #expect(first.rawValue.hasPrefix("cloud:"))
        #expect(first.rawValue.count == "cloud:".count + 64)
        #expect(first.rawValue.contains(recordName) == false)
    }

    @Test func containerAndAccountBothParticipateInScope() {
        let deriver: CloudAccountScopeDeriver = CloudAccountScopeDeriver()
        let base: CloudAccountScope = deriver.derive(
            containerIdentifier: "iCloud.com.xiefei.AnyPortal",
            userRecordName: "account-a"
        )
        let differentAccount: CloudAccountScope = deriver.derive(
            containerIdentifier: "iCloud.com.xiefei.AnyPortal",
            userRecordName: "account-b"
        )
        let differentContainer: CloudAccountScope = deriver.derive(
            containerIdentifier: "iCloud.com.xiefei.Other",
            userRecordName: "account-a"
        )

        #expect(base != differentAccount)
        #expect(base != differentContainer)
    }
}
