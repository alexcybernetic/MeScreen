import AppKit
import Combine
import SwiftUI

enum WindowSize: CGFloat, CaseIterable, Codable, Identifiable {
    case small = 100
    case medium = 150
    case large = 200

    var id: Self { self }

    var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

enum OverlayShapeKind: String, CaseIterable, Codable, Identifiable {
    case circle
    case squircle
    case roundedSquare
    case square
    case octagon

    var id: Self { self }

    var displayName: String {
        switch self {
        case .circle: "Circle"
        case .squircle: "Squircle"
        case .roundedSquare: "Rounded"
        case .square: "Square"
        case .octagon: "Octagon"
        }
    }

    func shape(size: CGFloat) -> AnyShape {
        switch self {
        case .circle:
            AnyShape(Circle())
        case .squircle:
            AnyShape(RoundedRectangle(
                cornerRadius: size * 0.30,
                style: .continuous
            ))
        case .roundedSquare:
            AnyShape(RoundedRectangle(
                cornerRadius: size * 0.15,
                style: .circular
            ))
        case .square:
            AnyShape(Rectangle())
        case .octagon:
            AnyShape(OctagonShape())
        }
    }
}

struct OctagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = min(rect.width, rect.height) * 0.22
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + inset))
        path.closeSubpath()
        return path
    }
}

enum OverlayRotation: Int, CaseIterable, Codable, Identifiable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270

    var id: Self { self }
    var displayName: String { "\(rawValue)°" }
    var radians: CGFloat { CGFloat(rawValue) * .pi / 180 }
}

enum OverlayCorner: String, CaseIterable, Codable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: Self { self }

    var displayName: String {
        switch self {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        }
    }

    func origin(
        for contentSize: CGSize,
        in visibleFrame: CGRect,
        margin: CGFloat = 20
    ) -> CGPoint {
        let leftX = visibleFrame.minX + margin
        let rightX = visibleFrame.maxX - contentSize.width - margin
        let bottomY = visibleFrame.minY + margin
        let topY = visibleFrame.maxY - contentSize.height - margin

        switch self {
        case .topLeft:
            return CGPoint(x: leftX, y: topY)
        case .topRight:
            return CGPoint(x: rightX, y: topY)
        case .bottomLeft:
            return CGPoint(x: leftX, y: bottomY)
        case .bottomRight:
            return CGPoint(x: rightX, y: bottomY)
        }
    }
}

enum OverlayLabelPosition: String, CaseIterable, Codable, Identifiable {
    case top
    case bottom

    var id: Self { self }
    var displayName: String { rawValue.capitalized }
}

enum OverlayLabelWeight: String, CaseIterable, Codable, Identifiable {
    case regular
    case medium
    case semibold
    case bold

    var id: Self { self }
    var displayName: String { rawValue.capitalized }

    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    var nsFontWeight: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

struct StoredColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = StoredColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = StoredColor(red: 0, green: 0, blue: 0, alpha: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Double(resolved.redComponent)
        green = Double(resolved.greenComponent)
        blue = Double(resolved.blueComponent)
        alpha = Double(resolved.alphaComponent)
    }

    var color: Color {
        Color(
            .sRGB,
            red: red,
            green: green,
            blue: blue,
            opacity: alpha
        )
    }

    func normalized() -> StoredColor {
        StoredColor(
            red: red.clamped(to: 0...1),
            green: green.clamped(to: 0...1),
            blue: blue.clamped(to: 0...1),
            alpha: alpha.clamped(to: 0...1)
        )
    }
}

struct OverlayLabelSettings: Codable, Equatable {
    var isEnabled = false
    var text = ""
    var position: OverlayLabelPosition = .bottom
    var textColor = StoredColor.white
    var backgroundColor = StoredColor.black
    var fontSize = 14.0
    var weight: OverlayLabelWeight = .semibold
    var pillOpacity = 0.82

    var isVisible: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

struct OverlaySettings: Codable, Equatable {
    static let currentVersion = 1
    static let maximumLabelLength = 40

    var version = currentVersion
    var windowSize: WindowSize = .medium
    var shape: OverlayShapeKind = .circle
    var borderColor = StoredColor.white
    var borderWidth = 3.0
    var hasShadow = true
    var shadowSoftness = 6.0
    var shadowIntensity = 0.65
    var hasReflection = false
    var isFlippedHorizontally = false
    var isFlippedVertically = false
    var rotation: OverlayRotation = .degrees0
    var startingCorner: OverlayCorner = .topRight
    var label = OverlayLabelSettings()
    var isGlobalShortcutEnabled = true

    func normalized() -> OverlaySettings {
        var result = self
        result.version = Self.currentVersion
        result.borderWidth = borderWidth.clamped(to: 0...12)
        result.shadowSoftness = shadowSoftness.clamped(to: 2...30)
        result.shadowIntensity = shadowIntensity.clamped(to: 0.05...0.65)
        result.borderColor = borderColor.normalized()
        result.label.textColor = label.textColor.normalized()
        result.label.backgroundColor = label.backgroundColor.normalized()
        result.label.fontSize = label.fontSize.clamped(to: 10...24)
        result.label.pillOpacity = label.pillOpacity.clamped(to: 0.25...1)
        result.label.text = String(
            label.text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .prefix(Self.maximumLabelLength)
        )
        return result
    }
}

struct OverlayLayout: Equatable {
    let cameraSize: CGFloat
    let outerPadding: CGFloat
    let labelHeight: CGFloat
    let labelGap: CGFloat
    let reflectionHeight: CGFloat
    let reflectionGap: CGFloat
    let contentSize: CGSize

    init(settings: OverlaySettings) {
        cameraSize = settings.windowSize.rawValue

        let borderPadding = max(4, CGFloat(settings.borderWidth) / 2 + 2)
        if settings.hasShadow {
            outerPadding = max(
                borderPadding,
                ceil(CGFloat(settings.shadowSoftness) * 1.35 + 4)
            )
        } else {
            outerPadding = borderPadding
        }

        if settings.label.isVisible {
            let font = NSFont.systemFont(
                ofSize: CGFloat(settings.label.fontSize),
                weight: settings.label.weight.nsFontWeight
            )
            labelHeight = ceil(font.boundingRectForFont.height + 10)
            labelGap = 6
        } else {
            labelHeight = 0
            labelGap = 0
        }

        if settings.hasReflection {
            reflectionHeight = ceil(cameraSize * 0.25)
            reflectionGap = 4
        } else {
            reflectionHeight = 0
            reflectionGap = 0
        }

        contentSize = CGSize(
            width: cameraSize + outerPadding * 2,
            height: cameraSize
                + outerPadding * 2
                + labelHeight
                + labelGap
                + reflectionHeight
                + reflectionGap
        )
    }
}

@MainActor
final class OverlaySettingsStore: ObservableObject {
    private static let storageKey = "overlay.settings.v1"

    @Published private(set) var settings: OverlaySettings
    @Published private(set) var isTransitioning = false

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults

        if let data = defaults?.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(OverlaySettings.self, from: data) {
            settings = decoded.normalized()
        } else {
            settings = OverlaySettings()
        }
    }

    func binding<Value>(
        for keyPath: WritableKeyPath<OverlaySettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.set($0, for: keyPath) }
        )
    }

    func set<Value>(
        _ value: Value,
        for keyPath: WritableKeyPath<OverlaySettings, Value>
    ) {
        apply { settings in
            settings[keyPath: keyPath] = value
        }
    }

    func update(_ mutation: (inout OverlaySettings) -> Void) {
        apply(mutation)
    }

    func changeSize(to size: WindowSize) {
        guard size != settings.windowSize, !isTransitioning else { return }
        isTransitioning = true
        set(size, for: \.windowSize)
    }

    func finishTransition() {
        isTransitioning = false
    }

    func reset() {
        isTransitioning = settings.windowSize != OverlaySettings().windowSize
        settings = OverlaySettings()
        persist()
    }

    private func apply(_ mutation: (inout OverlaySettings) -> Void) {
        var updated = settings
        mutation(&updated)
        updated = updated.normalized()
        guard updated != settings else { return }
        settings = updated
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults?.set(data, forKey: Self.storageKey)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
