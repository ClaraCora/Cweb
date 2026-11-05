import SwiftUI

struct ProxyImportReportView: View {
    @Environment(\.dismiss) private var dismiss
    let report: ProxyImportReport
    var body: some View {
        NavigationStack {
            List {
                Section("导入结果") { Text(report.summary) }
                if !report.invalid.isEmpty {
                    Section("未导入的条目") {
                        ForEach(report.invalid) { issue in Text("第 \(issue.line) 行：\(issue.reason)") }
                    }
                }
            }
            .navigationTitle("导入明细").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
