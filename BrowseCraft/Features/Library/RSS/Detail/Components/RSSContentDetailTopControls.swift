import SwiftUI

struct RSSContentDetailTopControls: View {
    let backAction: () -> Void

    var body: some View {
        HStack {
            Button(
                action: self.backAction,
                label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white, lineWidth: 2)
                        )
                }
            )
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 72)
    }
}
