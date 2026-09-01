import Foundation
import WebKit

@MainActor
struct IPDetectionService {
    let session: BrowserSession

    func prepare() async throws {
        try await session.prepareForNetworkDiagnostics()
    }

    func detectIPv4() async throws -> String {
        try await fetchIPAddress(from: "https://api4.ipify.org?format=json")
    }

    func detectIPv6() async throws -> String {
        try await fetchIPAddress(from: "https://api6.ipify.org?format=json")
    }

    func detectWebRTC() async throws -> [WebRTCCandidate] {
        let script = """
        return await new Promise((resolve) => {
            const candidates = new Map();
            let finished = false;
            let peer;
            let timer;

            const finish = (error = '') => {
                if (finished) return;
                finished = true;
                clearTimeout(timer);
                peer?.close();
                resolve({ candidates: [...candidates.values()], error });
            };

            try {
                peer = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });
            } catch (error) {
                finish(error?.message || String(error));
                return;
            }

            timer = setTimeout(() => finish(), 10000);
            peer.onicecandidate = (event) => {
                const candidate = event.candidate;
                if (!candidate) {
                    finish();
                    return;
                }

                const parts = (candidate.candidate || '').split(/\\s+/);
                const typeIndex = parts.indexOf('typ');
                const address = candidate.address || parts[4] || '';
                const protocol = candidate.protocol || parts[2] || '';
                const type = candidate.type
                    || (typeIndex >= 0 ? parts[typeIndex + 1] : '')
                    || 'unknown';
                if (!address || address === '0.0.0.0' || address === '::') return;

                const value = { address, protocol, type };
                candidates.set(`${address}|${protocol}|${type}`, value);
            };
            peer.onicegatheringstatechange = () => {
                if (peer.iceGatheringState === 'complete') finish();
            };

            (async () => {
                try {
                    peer.createDataChannel('ip-check');
                    const offer = await peer.createOffer();
                    await peer.setLocalDescription(offer);
                } catch (error) {
                    finish(error?.message || String(error));
                }
            })();
        });
        """

        let value = try await session.page.callJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard let result = value as? [String: Any] else {
            throw IPDetectionError.emptyResponse
        }
        if let message = result["error"] as? String,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw IPDetectionError.requestFailed(message)
        }
        guard let records = result["candidates"] as? [[String: Any]] else {
            return []
        }

        return records.compactMap { record in
            guard let address = record["address"] as? String, !address.isEmpty else {
                return nil
            }
            return WebRTCCandidate(
                address: address,
                transport: (record["protocol"] as? String) ?? "",
                candidateType: (record["type"] as? String) ?? "unknown"
            )
        }
    }

    private func fetchIPAddress(from urlString: String) async throws -> String {
        let script = """
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 12000);
        try {
            const response = await fetch(url, {
                cache: 'no-store',
                credentials: 'omit',
                signal: controller.signal
            });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const payload = await response.json();
            return { ip: payload.ip || '', error: '' };
        } catch (error) {
            return {
                ip: '',
                error: error?.message || String(error) || '网络请求失败'
            };
        } finally {
            clearTimeout(timeout);
        }
        """

        let value = try await session.page.callJavaScript(
            script,
            arguments: ["url": urlString],
            in: nil,
            contentWorld: .page
        )
        guard let result = value as? [String: Any] else {
            throw IPDetectionError.emptyResponse
        }
        if let message = result["error"] as? String,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw IPDetectionError.requestFailed(message)
        }
        guard let address = result["ip"] as? String,
              !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IPDetectionError.emptyResponse
        }
        return address
    }
}

struct WebRTCCandidate: Hashable, Sendable {
    let address: String
    let transport: String
    let candidateType: String

    var detail: String {
        [addressFamily, localizedCandidateType, transport.uppercased()]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var addressFamily: String {
        if address.contains(":") { return "IPv6" }
        if address.split(separator: ".").count == 4 { return "IPv4" }
        if address.lowercased().hasSuffix(".local") { return "隐私主机名" }
        return ""
    }

    private var localizedCandidateType: String {
        switch candidateType.lowercased() {
        case "host": "本机"
        case "srflx": "公网映射"
        case "relay": "中继"
        case "prflx": "对端映射"
        default: candidateType
        }
    }
}

enum IPDetectionError: LocalizedError {
    case emptyResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            "检测服务没有返回 IP 地址。"
        case .requestFailed(let message):
            "检测请求失败：\(message)"
        }
    }
}
