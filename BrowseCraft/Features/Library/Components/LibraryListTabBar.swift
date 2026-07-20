import SwiftUI

struct LibraryListTabBar: View {
    let source: Source?
    let tabs: [LibraryListTabState]
    let isInteractionDisabled: Bool
    let isValidating: Bool
    let selectAction: (String) async -> Void

    private let comicTabSelectedColor: Color = Color(red: 133 / 255, green: 153 / 255, blue: 255 / 255)
    private let comicTabTextColor: Color = Color(red: 21 / 255, green: 30 / 255, blue: 71 / 255)
    private let comicTabStrokeColor: Color = Color(red: 233 / 255, green: 236 / 255, blue: 239 / 255)
    private let videoTabSelectedColor: Color = Color(red: 133 / 255, green: 153 / 255, blue: 255 / 255)
    private let videoTabTextColor: Color = Color(red: 21 / 255, green: 30 / 255, blue: 71 / 255)
    private let videoTabStrokeColor: Color = Color(red: 233 / 255, green: 236 / 255, blue: 239 / 255)

    var body: some View {
        if self.source?.configuration.kind == .comic {
            self.comicListTabBar
        } else if self.source?.configuration.kind == .video {
            self.videoListTabBar
        } else {
            self.defaultListTabBar
        }
    }

    private var comicListTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(self.tabs) { tab in
                    Button(
                        action: {
                            Task {
                                await self.selectAction(tab.id)
                            }
                        },
                        label: {
                            Text(tab.title)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(tab.isSelected ? Color.white : self.comicTabTextColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 2)
                                .frame(minHeight: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(tab.isSelected ? self.comicTabSelectedColor : Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(
                                            tab.isSelected ? Color.clear : self.comicTabStrokeColor,
                                            lineWidth: 1
                                        )
                                )
                        }
                    )
                    .buttonStyle(.plain)
                    .disabled(self.isInteractionDisabled)
                }

                if self.isValidating {
                    self.tabValidationIndicator
                }
            }
            .opacity(self.isValidating ? 0.58 : 1)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    private var videoListTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(self.tabs) { tab in
                    Button(
                        action: {
                            Task {
                                await self.selectAction(tab.id)
                            }
                        },
                        label: {
                            Text(tab.title)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(tab.isSelected ? Color.white : self.videoTabTextColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 2)
                                .frame(minHeight: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(tab.isSelected ? self.videoTabSelectedColor : Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(
                                            tab.isSelected ? Color.clear : self.videoTabStrokeColor,
                                            lineWidth: 1
                                        )
                                )
                        }
                    )
                    .buttonStyle(.plain)
                    .disabled(self.isInteractionDisabled)
                }

                if self.isValidating {
                    self.tabValidationIndicator
                }
            }
            .opacity(self.isValidating ? 0.58 : 1)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    private var defaultListTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(self.tabs) { tab in
                    Button(
                        action: {
                            Task {
                                await self.selectAction(tab.id)
                            }
                        },
                        label: {
                            VStack(spacing: 6) {
                                Text(tab.title)
                                    .font(.headline)
                                    .foregroundColor(
                                        tab.isSelected
                                        ? .primary
                                        : .secondary
                                    )
                                    .lineLimit(1)

                                Capsule()
                                    .fill(
                                        tab.isSelected
                                        ? Color.primary
                                        : Color.clear
                                    )
                                    .frame(height: 3)
                            }
                            .frame(minWidth: 52)
                            .padding(.vertical, 10)
                        }
                    )
                    .buttonStyle(.plain)
                    .disabled(self.isInteractionDisabled)
                }

                if self.isValidating {
                    self.tabValidationIndicator
                }
            }
            .opacity(self.isValidating ? 0.58 : 1)
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
    }

    private var tabValidationIndicator: some View {
        ProgressView()
            .controlSize(.small)
            .padding(.horizontal, 4)
            .accessibilityLabel("Validating Tabs")
    }
}
