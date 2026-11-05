import Foundation

struct BuildIdentity {
    let version: String
    let build: String
    let commit: String
    init(bundle: Bundle = .main) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "本地"
        let value = bundle.object(forInfoDictionaryKey: "CwebGitCommit") as? String ?? ""
        commit = value.isEmpty || value == "local" || value.contains("$(") ? "本地构建" : String(value.prefix(7))
    }
    var description: String { "Cweb \(version) (\(build)) · \(commit)" }
}
