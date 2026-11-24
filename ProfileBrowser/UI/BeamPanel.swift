import BorderBeam
import SwiftUI

extension EnvironmentValues {
    @Entry var cwebLowPowerMode = false
}

extension View {
    func beamPanel(cornerRadius: CGFloat, active: Bool) -> some View {
        background {
            BeamPanelBackground(cornerRadius: cornerRadius, active: active)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct BeamPanelBackground: View {
    let cornerRadius: CGFloat
    let active: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cwebLowPowerMode) private var lowPowerMode
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isVisible = false
    @State private var inScrollViewport = true

    var body: some View {
        ControlGlass(cornerRadius: cornerRadius)
            .overlay {
                if active && isVisible && inScrollViewport && scenePhase == .active
                    && !lowPowerMode && !reduceTransparency && contrast != .increased {
                    PanelBeam(cornerRadius: cornerRadius, intensity: colorScheme == .dark ? 0.74 : 0.82)
                }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onGeometryChange(for: Bool.self) { geometry in
                guard let viewport = geometry.bounds(of: .scrollView) else { return true }
                return viewport.intersects(CGRect(origin: .zero, size: geometry.size))
            } action: { inScrollViewport = $0 }
    }
}

private struct PanelBeam: View {
    let cornerRadius: CGFloat
    let intensity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // BorderBeam 1.0.0 keeps its resource bundle internal. The release workflow
    // verifies this exact bundle and its compiled default.metallib in the IPA.
    private static let function = Bundle.main.url(forResource: "BorderBeam_BorderBeam", withExtension: "bundle")
        .flatMap(Bundle.init(url:))
        .map { ShaderFunction(library: .bundle($0), name: "borderBeam") }
    private static let palette = Shader.Argument.floatArray(BeamPalette.aurora.flatMap { color -> [Float] in
        let rgba = color.resolve(in: EnvironmentValues())
        return [rgba.red, rgba.green, rgba.blue, rgba.opacity]
    })
    private static let lapDuration: TimeInterval = 5.4

    var body: some View {
        if let function = Self.function {
            GeometryReader { geometry in
                if reduceMotion {
                    frame(function, size: geometry.size, phase: 0.15)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { tick in
                        let elapsed = tick.date.timeIntervalSinceReferenceDate
                        let phase = elapsed.truncatingRemainder(dividingBy: Self.lapDuration) / Self.lapDuration
                        frame(function, size: geometry.size, phase: phase)
                    }
                }
            }
        }
    }

    private func frame(_ function: ShaderFunction, size: CGSize, phase: Double) -> some View {
        // Arguments match the package's clockwise, large orbit preset.
        Rectangle().fill(.white).colorEffect(function(
            .float2(size), .float(cornerRadius), .float(phase),
            .float(1), .float(0), .float(2), // direction, orbit mode, unused line edge
            .float(0.36), .float(20), .float(intensity), Self.palette
        ))
    }
}
