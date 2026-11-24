import SwiftUI

/// One stationary field per workspace. The glass controls sample it as the list moves.
struct WorkspaceBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let paper = Color(uiColor: .systemGroupedBackground)
        Group {
            if reduceTransparency || contrast == .increased {
                paper
            } else {
                let strength = scheme == .dark ? 0.36 : 0.32
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.35], [0.52, 0.43], [1, 0.55],
                        [0, 1], [0.5, 1], [1, 1]
                    ] as [SIMD2<Float>],
                    colors: [
                        paper.mix(with: Color(uiColor: .systemCyan), by: strength),
                        paper.mix(with: Color(uiColor: .systemBlue), by: strength * 0.55),
                        paper.mix(with: Color(uiColor: .systemIndigo), by: strength),
                        paper.mix(with: Color(uiColor: .systemMint), by: strength * 0.38),
                        paper,
                        paper.mix(with: Color(uiColor: .systemIndigo), by: strength * 0.20),
                        paper, paper, paper
                    ]
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct ControlGlass: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
        if reduceTransparency || contrast == .increased {
            outline.fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay { outline.strokeBorder(Color(uiColor: .separator), lineWidth: 1) }
        } else {
            Color.clear.glassEffect(.regular, in: outline)
        }
    }
}
