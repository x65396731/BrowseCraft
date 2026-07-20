import SwiftUI
import UIKit

struct ReaderPageVisibility: Equatable {
    let pageIndex: Int
    let pageURLString: String
    let distanceToScreenCenter: CGFloat
}

struct ReaderPageVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: ReaderPageVisibility?

    static func reduce(value: inout ReaderPageVisibility?, nextValue: () -> ReaderPageVisibility?) {
        guard let nextValue: ReaderPageVisibility = nextValue() else {
            return
        }

        guard let currentValue: ReaderPageVisibility = value else {
            value = nextValue
            return
        }

        if nextValue.distanceToScreenCenter < currentValue.distanceToScreenCenter {
            value = nextValue
        }
    }
}

struct ReaderPageVisibilityReporter: View {
    let pageIndex: Int
    let pageURLString: String

    var body: some View {
        GeometryReader { proxy in
            let frame: CGRect = proxy.frame(in: .global)
            let screenBounds: CGRect = UIScreen.main.bounds
            let screenCenterY: CGFloat = screenBounds.midY
            let pageCenterY: CGFloat = frame.midY
            Color.clear.preference(
                key: ReaderPageVisibilityPreferenceKey.self,
                value: frame.intersects(screenBounds)
                    ? ReaderPageVisibility(
                        pageIndex: self.pageIndex,
                        pageURLString: self.pageURLString,
                        distanceToScreenCenter: abs(pageCenterY - screenCenterY)
                    )
                    : nil
            )
        }
    }
}
