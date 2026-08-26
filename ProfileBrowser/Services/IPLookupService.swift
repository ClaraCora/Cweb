import Foundation

struct IPLookupService {
    private struct Response: Decodable {
        let ip: String
    }

    func currentIPAddress() async throws -> String {
        let url = URL(string: "https://api.ipify.org?format=json")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw IPLookupError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: data).ip
    }
}

enum IPLookupError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "无法查询当前公网 IP。"
    }
}
