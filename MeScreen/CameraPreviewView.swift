//
//  CameraPreviewView.swift
//  MeScreen
//
//  Created by Alex on 19.03.26.
//

@preconcurrency import AVFoundation
import SwiftUI

enum CameraImageTransform {
    static func make(
        isFlippedHorizontally: Bool,
        isFlippedVertically: Bool,
        rotation: OverlayRotation
    ) -> CGAffineTransform {
        CGAffineTransform(
            scaleX: isFlippedHorizontally ? -1 : 1,
            y: isFlippedVertically ? -1 : 1
        )
        .rotated(by: rotation.radians)
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let isFlippedHorizontally: Bool
    let isFlippedVertically: Bool
    let rotation: OverlayRotation

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.update(
            session: session,
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            rotation: rotation
        )
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.update(
            session: session,
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            rotation: rotation
        )
    }

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) {
        nsView.removePreviewLayer()
    }
}

final class CameraPreviewNSView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var previewTransform = CGAffineTransform.identity

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "transform": NSNull(),
        ]
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        session: AVCaptureSession,
        isFlippedHorizontally: Bool,
        isFlippedVertically: Bool,
        rotation: OverlayRotation
    ) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }

        previewTransform = CameraImageTransform.make(
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            rotation: rotation
        )
        needsLayout = true
    }

    func removePreviewLayer() {
        previewLayer.session = nil
        previewLayer.removeFromSuperlayer()
    }

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        previewLayer.setAffineTransform(previewTransform)
        CATransaction.commit()
    }
}
