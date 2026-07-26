//
//  ContentView.swift
//  MeScreen
//
//  Created by Alex on 19.03.26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var cameraManager: CameraManager
    @EnvironmentObject private var settingsStore: OverlaySettingsStore

    var body: some View {
        let settings = settingsStore.settings
        let layout = OverlayLayout(settings: settings)

        VStack(spacing: 0) {
            if settings.label.isVisible,
               settings.label.position == .top {
                OverlayLabelView(
                    settings: settings.label,
                    maximumWidth: layout.cameraSize
                )
                Color.clear.frame(height: layout.labelGap)
            }

            CameraSurface(
                size: layout.cameraSize,
                settings: settings,
                cameraManager: cameraManager,
                showsShadow: settings.hasShadow,
                isTransitioning: settingsStore.isTransitioning
            )

            if settings.hasReflection {
                Color.clear.frame(height: layout.reflectionGap)
                CameraReflectionView(
                    size: layout.cameraSize,
                    height: layout.reflectionHeight,
                    settings: settings,
                    cameraManager: cameraManager,
                    isTransitioning: settingsStore.isTransitioning
                )
            }

            if settings.label.isVisible,
               settings.label.position == .bottom {
                Color.clear.frame(height: layout.labelGap)
                OverlayLabelView(
                    settings: settings.label,
                    maximumWidth: layout.cameraSize
                )
            }
        }
        .padding(layout.outerPadding)
        .frame(
            width: layout.contentSize.width,
            height: layout.contentSize.height
        )
        .animation(.easeInOut(duration: 0.2), value: settings)
    }
}

private struct CameraSurface: View {
    let size: CGFloat
    let settings: OverlaySettings
    @ObservedObject var cameraManager: CameraManager
    let showsShadow: Bool
    let isTransitioning: Bool

    var body: some View {
        let shape = settings.shape.shape(size: size)

        ZStack {
            shape.fill(Color.black)

            if let session = cameraManager.captureSession {
                CameraPreviewView(
                    session: session,
                    isFlippedHorizontally: settings.isFlippedHorizontally,
                    isFlippedVertically: settings.isFlippedVertically,
                    rotation: settings.rotation
                )
                .opacity(isTransitioning ? 0 : 1)
                .animation(
                    .easeInOut(duration: 0.16),
                    value: isTransitioning
                )
            } else {
                CameraPlaceholder(
                    size: size,
                    state: cameraManager.cameraState
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            shape.stroke(
                settings.borderColor.color,
                lineWidth: CGFloat(settings.borderWidth)
            )
        }
        .shadow(
            color: showsShadow
                ? Color.black.opacity(settings.shadowIntensity)
                : .clear,
            radius: showsShadow ? CGFloat(settings.shadowSoftness) : 0,
            y: showsShadow ? CGFloat(settings.shadowSoftness) * 0.22 : 0
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cameraManager.cameraState.overlayTitle)
    }
}

private struct CameraPlaceholder: View {
    let size: CGFloat
    let state: CameraState

    var body: some View {
        ZStack {
            Color.gray.opacity(0.3)
            VStack(spacing: 8) {
                Image(systemName: state.symbolName)
                    .font(.system(size: size * 0.24))
                Text(state.overlayTitle)
                    .font(.system(
                        size: max(10, size * 0.08),
                        weight: .medium
                    ))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
            }
            .foregroundStyle(.white)
        }
    }
}

private struct CameraReflectionView: View {
    let size: CGFloat
    let height: CGFloat
    let settings: OverlaySettings
    let cameraManager: CameraManager
    let isTransitioning: Bool

    var body: some View {
        CameraSurface(
            size: size,
            settings: settings,
            cameraManager: cameraManager,
            showsShadow: false,
            isTransitioning: isTransitioning
        )
        .scaleEffect(y: -1)
        .frame(width: size, height: size)
        .frame(width: size, height: height, alignment: .top)
        .clipped()
        .mask {
            LinearGradient(
                colors: [.black.opacity(0.42), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }
}

private struct OverlayLabelView: View {
    let settings: OverlayLabelSettings
    let maximumWidth: CGFloat

    var body: some View {
        Text(settings.text)
            .font(.system(
                size: CGFloat(settings.fontSize),
                weight: settings.weight.fontWeight
            ))
            .foregroundStyle(settings.textColor.color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(settings.backgroundColor.color.opacity(
                        settings.pillOpacity
                    ))
            }
            .frame(maxWidth: maximumWidth)
            .accessibilityLabel(settings.text)
    }
}

#Preview {
    ContentView()
        .environmentObject(CameraManager(startCamera: false))
        .environmentObject(OverlaySettingsStore(defaults: nil))
}
