import SwiftUI
import WebKit
import WebUI

// 中文注释：SourceLoginView 是漫画、影视、RSS 共用的站点登录 WebUI，并在用户确认后采集当前 Source 会话。
struct SourceLoginView: View {
    @StateObject private var coordinator: SourceLoginWebCoordinator = SourceLoginWebCoordinator()
    @State private var didLoadInitialURL: Bool = false
    @State private var isCapturingCredential: Bool = false
    @State private var captureErrorMessage: String?

    let state: LibrarySourceLoginState
    let cancelAction: () -> Void
    let completeAction: (SourceCredential) -> Void

    var body: some View {
        WebViewReader { proxy in
            VStack(spacing: 0) {
                self.toolbar(proxy: proxy)

                ProgressView(value: proxy.estimatedProgress)
                    .opacity(proxy.isLoading ? 1 : 0.12)

                WebView(configuration: self.coordinator.configuration)
                    .uiDelegate(self.coordinator)
                    .navigationDelegate(self.coordinator)
                    .allowsBackForwardNavigationGestures(true)
                    .allowsLinkPreview(false)
                    .contentInsetAdjustmentBehavior(.never)
                    .refreshable()
                    .onAppear {
                        guard self.didLoadInitialURL == false else {
                            return
                        }

                        self.didLoadInitialURL = true
                        proxy.load(request: URLRequest(url: self.state.loginURL))
                    }
                    .ignoresSafeArea(edges: .bottom)
            }
            .background(Color(.systemBackground))
        }
        .interactiveDismissDisabled()
        .alert("Login Session", isPresented: self.captureErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(self.captureErrorMessage ?? "Unable to save the login session.")
        }
    }

    private func toolbar(proxy: WebViewProxy) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button("Close") {
                    self.cancelAction()
                }
                .disabled(self.isCapturingCredential)

                VStack(alignment: .leading, spacing: 2) {
                    Text(proxy.title?.isEmpty == false ? proxy.title ?? self.state.sourceName : self.state.sourceName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text((proxy.url ?? self.state.loginURL).host() ?? self.state.loginURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task {
                        await self.captureCredential()
                    }
                } label: {
                    if self.isCapturingCredential {
                        ProgressView()
                    } else {
                        Text("Done")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.isCapturingCredential)
            }

            HStack(spacing: 18) {
                Button {
                    proxy.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                }
                .disabled(proxy.canGoBack == false)

                Button {
                    proxy.goForward()
                } label: {
                    Label("Forward", systemImage: "chevron.forward")
                        .labelStyle(.iconOnly)
                }
                .disabled(proxy.canGoForward == false)

                Button {
                    proxy.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }

                Spacer(minLength: 0)

                Text("Sign in to this source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @MainActor
    private func captureCredential() async {
        self.isCapturingCredential = true
        defer { self.isCapturingCredential = false }

        do {
            let credential: SourceCredential = try await self.coordinator.captureCredential(for: self.state)
            self.completeAction(credential)
        } catch {
            self.captureErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var captureErrorBinding: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return self.captureErrorMessage != nil
            },
            set: { isPresented in
                if isPresented == false {
                    self.captureErrorMessage = nil
                }
            }
        )
    }
}
