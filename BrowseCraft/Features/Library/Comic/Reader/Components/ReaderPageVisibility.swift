import SwiftUI
import UIKit

struct ReaderPageVisibility: Equatable {
    let pageIndex: Int
    let pageURLString: String
    let distanceToScreenCenter: CGFloat
}

struct ReaderPageVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [ReaderPageVisibility] = []

    static func reduce(value: inout [ReaderPageVisibility], nextValue: () -> [ReaderPageVisibility]) {
        value.append(contentsOf: nextValue())
    }
}

struct ReaderPageVisibilityReporter: View {
    let pageIndex: Int
    let pageURLString: String

    var body: some View {
        GeometryReader { proxy in
            let frame: CGRect = proxy.frame(in: .global)
            let screenCenterY: CGFloat = UIScreen.main.bounds.midY
            let pageCenterY: CGFloat = frame.midY
            Color.clear.preference(
                key: ReaderPageVisibilityPreferenceKey.self,
                value: [
                    ReaderPageVisibility(
                        pageIndex: self.pageIndex,
                        pageURLString: self.pageURLString,
                        distanceToScreenCenter: abs(pageCenterY - screenCenterY)
                    )
                ]
            )
        }
    }
}
