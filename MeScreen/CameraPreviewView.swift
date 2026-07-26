//
//  CameraPreviewView.swift
//  MeScreen
//
//  Created by Alex on 19.03.26.
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.wantsLayer = true
        view.install(previewLayer)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.install(previewLayer)
    }

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) {
        nsView.removePreviewLayer()
    }
}

// Custom NSView to handle layout
final class CameraPreviewNSView: NSView {
    private let circleMask = CAShapeLayer()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func install(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard self.previewLayer !== previewLayer else { return }

        removePreviewLayer()
        previewLayer.removeFromSuperlayer()
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
        ]
        layer?.addSublayer(previewLayer)
        self.previewLayer = previewLayer
        needsLayout = true
    }

    func removePreviewLayer() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    override func layout() {
        super.layout()

        previewLayer?.frame = bounds

        // Apply a circular mask so the preview is always round,
        // even during animated frame changes.
        circleMask.frame = bounds
        circleMask.path = CGPath(ellipseIn: bounds, transform: nil)
        if layer?.mask !== circleMask {
            layer?.mask = circleMask
        }
    }
}
