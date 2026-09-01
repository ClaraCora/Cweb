import SwiftUI
import WebKit

@MainActor
struct IPDetectionView: View {
    @Environment(\.dismiss) private var dismiss

    private let profile: BrowserProfile
    @State private var session: BrowserSession
    @State private var ipv4: IPProbeState = .idle
    @State private var ipv6: IPProbeState = .idle
    @State private var webRTC: IPProbeState = .idle
    @State private var isRunning = false

    init(profile: BrowserProfile, socksProxy: SocksProxy?) {
        self.profile = profile
        _session = State(initialValue: BrowserSession(profile: profile, socksProxy: socksProxy))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("环境") {
                    LabeledContent("名称", value: profile.name)
                    LabeledContent("网络路径", value: networkPathDescription)
                }

                Section {
                    ProbeResultRow(title: "IPv4", systemImage: "4.circle", state: ipv4)
                    ProbeResultRow(title: "IPv6", systemImage: "6.circle", state: ipv6)
                    ProbeResultRow(title: "WebRTC", systemImage: "dot.radiowaves.left.and.right", state: webRTC)
                } header: {
                    Text("检测结果")
                } footer: {
                    Text("WebRTC 显示网页可见的候选地址；它与 IPv4、IPv6 出口不一致时，可能存在独立的网络路径。")
                }

                Section {
                    Button {
                        Task { await runDetection() }
                    } label: {
                        HStack {
                            Spacer()
                            if isRunning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(isRunning ? "正在检测" : hasResults ? "重新检测" : "开始检测")
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(isRunning)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("IP 检测")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .disabled(isRunning)
                }
            }
            .interactiveDismissDisabled(isRunning)
            .background {
                WebView(session.page)
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var hasResults: Bool {
        ipv4 != .idle || ipv6 != .idle || webRTC != .idle
    }

    private var networkPathDescription: String {
        if let number = profile.socksProxyNumber {
            if let proxy = session.socksProxy {
                return "SOCKS 第 \(number) 号 · \(proxy.displayCode ?? proxy.displayAddress)"
            }
            return "SOCKS 第 \(number) 号（当前缺失）"
        }
        return "设备网络"
    }

    private func runDetection() async {
        guard !isRunning else { return }
        isRunning = true
        ipv4 = .testing
        ipv6 = .testing
        webRTC = .testing
        defer { isRunning = false }

        let service = IPDetectionService(session: session)
        do {
            try await service.prepare()
        } catch {
            let message = error.localizedDescription
            ipv4 = .failed(message)
            ipv6 = .failed(message)
            webRTC = .failed(message)
            return
        }

        async let ipv4Result = probeAddress { try await service.detectIPv4() }
        async let ipv6Result = probeAddress { try await service.detectIPv6() }
        async let webRTCResult = probeWebRTC { try await service.detectWebRTC() }
        let results = await (ipv4Result, ipv6Result, webRTCResult)
        ipv4 = results.0
        ipv6 = results.1
        webRTC = results.2
    }

    private func probeAddress(
        _ operation: @MainActor () async throws -> String
    ) async -> IPProbeState {
        do {
            return .succeeded(try await operation())
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func probeWebRTC(
        _ operation: @MainActor () async throws -> [WebRTCCandidate]
    ) async -> IPProbeState {
        do {
            let candidates = try await operation()
            guard !candidates.isEmpty else {
                return .failed("未检测到候选地址，可能是 WebKit 隐私保护或 UDP 不可用。")
            }
            let value = candidates.map { candidate in
                candidate.detail.isEmpty
                    ? candidate.address
                    : "\(candidate.address)  \(candidate.detail)"
            }.joined(separator: "\n")
            return .succeeded(value)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

private enum IPProbeState: Equatable {
    case idle
    case testing
    case succeeded(String)
    case failed(String)
}

private struct ProbeResultRow: View {
    let title: String
    let systemImage: String
    let state: IPProbeState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(detailFont)
                    .foregroundStyle(detailColor)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            if case .testing = state {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在检测 \(title)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch state {
        case .idle: "尚未检测"
        case .testing: "正在连接"
        case .succeeded(let value), .failed(let value): value
        }
    }

    private var iconColor: Color {
        switch state {
        case .succeeded: .green
        case .failed: .orange
        case .idle, .testing: .secondary
        }
    }

    private var detailColor: Color {
        switch state {
        case .failed: .primary
        case .idle, .testing, .succeeded: .secondary
        }
    }

    private var detailFont: Font {
        switch state {
        case .succeeded: .subheadline.monospaced()
        case .idle, .testing, .failed: .subheadline
        }
    }
}
