import Foundation

/// `PersonalRuleReceiptStoring` 的 UserDefaults 实现：每个用户一份 JSON。
final class UserDefaultsPersonalRuleReceiptStore: PersonalRuleReceiptStoring, @unchecked Sendable {
    private struct Payload: Codable {
        var receipts: [String: Date] = [:]
        var hidden: [String] = []
    }

    private let userDefaults: UserDefaults
    private let keyPrefix: String
    private let lock: NSLock = NSLock()

    init(userDefaults: UserDefaults = .standard, keyPrefix: String = "generation.personalRules") {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    func receipts(userID: String) -> [PersonalRuleReceipt] {
        return self.load(userID: userID).receipts.map { entry in
            return PersonalRuleReceipt(catalogSourceID: entry.key, receivedAt: entry.value)
        }
    }

    func recordReceiptIfAbsent(catalogSourceID: String, userID: String, receivedAt: Date) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var payload: Payload = self.load(userID: userID)
        guard payload.receipts[catalogSourceID] == nil else {
            return
        }
        payload.receipts[catalogSourceID] = receivedAt
        self.save(payload, userID: userID)
    }

    func hiddenIDs(userID: String) -> Set<String> {
        return Set(self.load(userID: userID).hidden)
    }

    func hide(id: String, userID: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var payload: Payload = self.load(userID: userID)
        if payload.hidden.contains(id) == false {
            payload.hidden.append(id)
        }
        payload.receipts.removeValue(forKey: id)
        self.save(payload, userID: userID)
    }

    private func key(userID: String) -> String {
        return "\(self.keyPrefix).\(userID)"
    }

    private func load(userID: String) -> Payload {
        guard let data: Data = self.userDefaults.data(forKey: self.key(userID: userID)),
              let payload: Payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Payload()
        }
        return payload
    }

    private func save(_ payload: Payload, userID: String) {
        guard let data: Data = try? JSONEncoder().encode(payload) else {
            return
        }
        self.userDefaults.set(data, forKey: self.key(userID: userID))
    }
}
