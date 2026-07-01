import NukeUI
import SwiftUI

// 中文注释：ReaderPageImageView.swift 属于界面功能层，用于说明本文件承载的核心职责。

/// 中文注释：ReaderPageImageView 是 struct，负责本模块中的对应职责。
struct ReaderPageImageView: View {
    let pageURLString: String
    let pageNumber: Int
    let refererURLString: String?

    var body: some View {
        if let request: ImageRequest = ImageRequestFactory.makeRequest(
            urlString: self.pageURLString,
            refererURLString: self.refererURLString
        ) {
            LazyImage(source: request) { state in
                if let image = state.image {
                    image
                        .resizingMode(.aspectFit)
                        .aspectRatio(0.72, contentMode: .fit)
                } else if state.error != nil {
                    self.errorView
                } else {
                    self.loadingView
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .accessibilityLabel("Page \(self.pageNumber)")
        } else {
            self.errorView
        }
    }

    private var loadingView: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemFill))
                .aspectRatio(0.72, contentMode: .fit)

            ProgressView()
        }
    }

    private var errorView: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemFill))
                .aspectRatio(0.72, contentMode: .fit)

            VStack(spacing: 8) {
                SwiftUI.Image(systemName: "exclamationmark.triangle")
                    .font(.title2)

                Text("Page \(self.pageNumber)")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
    }
}
