import Foundation
import WebKit

@MainActor
struct SourceLoginSessionCleaner {
    func clear(state: LibrarySourceLoginState) async {
        let dataStore: WKWebsiteDataStore = .default()
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        for cookie: HTTPCookie in cookies where SourceLoginSessionDomainMatcher.matches(cookie: cookie, state: state) {
            await withCheckedContinuation { continuation in
                dataStore.httpCookieStore.delete(cookie) {
                    continuation.resume()
                }
            }
        }

        let dataTypes: Set<String> = [WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage]
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
                continuation.resume(returning: records)
            }
        }
        let matchingRecords: [WKWebsiteDataRecord] = records.filter {
            SourceLoginSessionDomainMatcher.matches(record: $0, state: state)
        }
        guard matchingRecords.isEmpty == false else {
            return
        }
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: dataTypes, for: matchingRecords) {
                continuation.resume()
            }
        }
    }
}
