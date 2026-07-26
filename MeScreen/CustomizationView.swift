import AppKit
import SwiftUI

struct CustomizationView: View {
    @EnvironmentObject private var settingsStore: OverlaySettingsStore
    @State private var isShowingResetConfirmation = false

    var body: some View {
        Form {
            Section("Appearance") {
                LabeledContent("Shape") {
                    ShapePicker(
                        selection: settingsStore.binding(for: \.shape)
                    )
                }

                ColorPicker(
                    "Border color",
                    selection: colorBinding(for: \.borderColor),
                    supportsOpacity: false
                )

                ValueSlider(
                    title: "Border width",
                    value: settingsStore.binding(for: \.borderWidth),
                    range: 0...12,
                    step: 1,
                    valueLabel: { "\(Int($0)) pt" }
                )

                Toggle(
                    "Drop shadow",
                    isOn: settingsStore.binding(for: \.hasShadow)
                )

                if settingsStore.settings.hasShadow {
                    ValueSlider(
                        title: "Softness",
                        value: settingsStore.binding(for: \.shadowSoftness),
                        range: 2...30,
                        step: 1,
                        valueLabel: { "\(Int($0)) pt" }
                    )

                    ValueSlider(
                        title: "Intensity",
                        value: settingsStore.binding(for: \.shadowIntensity),
                        range: 0.05...0.65,
                        step: 0.05,
                        valueLabel: { "\(Int($0 * 100))%" }
                    )
                }

                Toggle(
                    "Reflection",
                    isOn: settingsStore.binding(for: \.hasReflection)
                )

                HStack(spacing: 18) {
                    Toggle(
                        "Flip horizontally",
                        isOn: settingsStore.binding(
                            for: \.isFlippedHorizontally
                        )
                    )
                    Toggle(
                        "Flip vertically",
                        isOn: settingsStore.binding(
                            for: \.isFlippedVertically
                        )
                    )
                }

                Picker(
                    "Rotation",
                    selection: settingsStore.binding(for: \.rotation)
                ) {
                    ForEach(OverlayRotation.allCases) { rotation in
                        Text(rotation.displayName).tag(rotation)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Starting corner") {
                        CornerPicker(
                            selection: settingsStore.binding(
                                for: \.startingCorner
                            )
                        )
                    }

                    Text("Applied the next time MeScreen opens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Label") {
                Toggle(
                    "Show label",
                    isOn: settingsStore.binding(for: \.label.isEnabled)
                )

                if settingsStore.settings.label.isEnabled {
                    LabeledContent("Name") {
                        VStack(alignment: .trailing, spacing: 4) {
                            TextField(
                                "Label text",
                                text: settingsStore.binding(for: \.label.text)
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)

                            Text(
                                "\(settingsStore.settings.label.text.count)/\(OverlaySettings.maximumLabelLength)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }
                    }

                    Picker(
                        "Position",
                        selection: settingsStore.binding(
                            for: \.label.position
                        )
                    ) {
                        ForEach(OverlayLabelPosition.allCases) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)

                    ColorPicker(
                        "Text color",
                        selection: colorBinding(for: \.label.textColor),
                        supportsOpacity: false
                    )

                    ColorPicker(
                        "Background color",
                        selection: colorBinding(
                            for: \.label.backgroundColor
                        ),
                        supportsOpacity: false
                    )

                    ValueSlider(
                        title: "Font size",
                        value: settingsStore.binding(for: \.label.fontSize),
                        range: 10...24,
                        step: 1,
                        valueLabel: { "\(Int($0)) pt" }
                    )

                    Picker(
                        "Weight",
                        selection: settingsStore.binding(for: \.label.weight)
                    ) {
                        ForEach(OverlayLabelWeight.allCases) { weight in
                            Text(weight.displayName).tag(weight)
                        }
                    }

                    ValueSlider(
                        title: "Pill opacity",
                        value: settingsStore.binding(
                            for: \.label.pillOpacity
                        ),
                        range: 0.25...1,
                        step: 0.05,
                        valueLabel: { "\(Int($0 * 100))%" }
                    )

                }
            }

            Section("Controls") {
                Toggle(
                    "Global show/hide shortcut",
                    isOn: settingsStore.binding(
                        for: \.isGlobalShortcutEnabled
                    )
                )

                LabeledContent("Shortcut") {
                    Text(GlobalShortcutDefinition.displayName)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(
                            cornerRadius: 6,
                            style: .continuous
                        ))
                }
            }

            Section {
                HStack {
                    Label("Stored only on this Mac", systemImage: "lock")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset All…", role: .destructive) {
                        isShowingResetConfirmation = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 680)
        .animation(.easeInOut(duration: 0.16), value: settingsStore.settings)
        .alert("Reset all customization?", isPresented: $isShowingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settingsStore.reset()
            }
        } message: {
            Text("This restores the default appearance, label, position, and shortcut settings.")
        }
    }

    private func colorBinding(
        for keyPath: WritableKeyPath<OverlaySettings, StoredColor>
    ) -> Binding<Color> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath].color },
            set: { color in
                settingsStore.set(StoredColor(color: color), for: keyPath)
            }
        )
    }
}

private struct ShapePicker: View {
    @Binding var selection: OverlayShapeKind

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 6),
        count: OverlayShapeKind.allCases.count
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(OverlayShapeKind.allCases) { shapeKind in
                Button {
                    selection = shapeKind
                } label: {
                    VStack(spacing: 5) {
                        shapeKind.shape(size: 30)
                            .fill(selection == shapeKind
                                ? Color.accentColor
                                : Color.secondary.opacity(0.55))
                            .frame(width: 30, height: 30)
                        Text(shapeKind.displayName)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selection == shapeKind
                                ? Color.accentColor.opacity(0.12)
                                : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selection == shapeKind
                                ? Color.accentColor.opacity(0.55)
                                : Color.secondary.opacity(0.16))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shapeKind.displayName)
                .accessibilityAddTraits(
                    selection == shapeKind ? .isSelected : []
                )
            }
        }
        .frame(minWidth: 300)
    }
}

private struct CornerPicker: View {
    @Binding var selection: OverlayCorner

    var body: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            GridRow {
                cornerButton(.topLeft, symbol: "arrow.up.left")
                cornerButton(.topRight, symbol: "arrow.up.right")
            }
            GridRow {
                cornerButton(.bottomLeft, symbol: "arrow.down.left")
                cornerButton(.bottomRight, symbol: "arrow.down.right")
            }
        }
    }

    private func cornerButton(
        _ corner: OverlayCorner,
        symbol: String
    ) -> some View {
        Button {
            selection = corner
        } label: {
            Image(systemName: symbol)
                .frame(width: 34, height: 24)
                .background(
                    selection == corner
                        ? Color.accentColor.opacity(0.18)
                        : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == corner ? Color.accentColor : .secondary)
        .accessibilityLabel(corner.displayName)
        .accessibilityAddTraits(selection == corner ? .isSelected : [])
    }
}

private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueLabel: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: step)
                    .frame(minWidth: 150)
                Text(valueLabel(value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }
}

@MainActor
final class CustomizationWindowController: NSWindowController {
    init(settingsStore: OverlaySettingsStore) {
        let rootView = CustomizationView()
            .environmentObject(settingsStore)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Customize MeScreen"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 700))
        window.setFrameAutosaveName("MeScreen.CustomizationWindow")
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
