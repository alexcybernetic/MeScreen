@preconcurrency import AVFoundation
import Foundation

nonisolated struct CameraDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isExternal: Bool

    init(id: String, name: String, isExternal: Bool) {
        self.id = id
        self.name = name
        self.isExternal = isExternal
    }

    init(device: AVCaptureDevice) {
        id = device.uniqueID
        name = device.localizedName
        isExternal = device.deviceType == .external
    }
}

nonisolated struct CaptureSessionSnapshot: @unchecked Sendable {
    let session: AVCaptureSession
    let cameras: [CameraDescriptor]
    let selectedCamera: CameraDescriptor

    var sessionIdentifier: ObjectIdentifier {
        ObjectIdentifier(session)
    }
}

nonisolated enum CaptureSessionFailure: Error, Equatable, Sendable {
    case noCameras
    case cameraUnavailable
    case inputCreationFailed(String)
    case inputRejected
    case startupFailed

    var message: String {
        switch self {
        case .noCameras:
            "No camera is currently available."
        case .cameraUnavailable:
            "The selected camera is no longer available."
        case .inputCreationFailed(let message):
            "The camera could not be opened: \(message)"
        case .inputRejected:
            "The camera cannot be attached to the capture session."
        case .startupFailed:
            "The camera session failed to start."
        }
    }
}

nonisolated enum CaptureSessionStartOutcome: Sendable {
    case running(CaptureSessionSnapshot)
    case failed(CaptureSessionFailure, cameras: [CameraDescriptor])
}

nonisolated protocol CaptureSessionControlling: Sendable {
    func discoverCameras() async -> [CameraDescriptor]
    func start(preferredCameraID: String?) async -> CaptureSessionStartOutcome
    func stop(sessionIdentifier: ObjectIdentifier?) async
}

nonisolated final class AVCaptureSessionController: CaptureSessionControlling, @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        var session: AVCaptureSession?
    }

    private let queue = DispatchQueue(
        label: "Xaido.MeScreen.capture-session",
        qos: .userInitiated
    )
    private let storage = Storage()

    func discoverCameras() async -> [CameraDescriptor] {
        await perform { [self] in
            discoverDevices().map(CameraDescriptor.init)
        }
    }

    func start(preferredCameraID: String?) async -> CaptureSessionStartOutcome {
        await perform { [self] in
            startOnQueue(preferredCameraID: preferredCameraID)
        }
    }

    func stop(sessionIdentifier: ObjectIdentifier?) async {
        await perform { [self] in
            stopOnQueue(sessionIdentifier: sessionIdentifier)
        }
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: operation())
            }
        }
    }

    private func startOnQueue(preferredCameraID: String?) -> CaptureSessionStartOutcome {
        stopOnQueue(sessionIdentifier: nil)

        let devices = discoverDevices()
        let cameras = devices.map(CameraDescriptor.init)

        guard !devices.isEmpty else {
            return .failed(.noCameras, cameras: cameras)
        }

        let selectedDevice: AVCaptureDevice?
        if let preferredCameraID {
            selectedDevice = devices.first { $0.uniqueID == preferredCameraID }
        } else {
            selectedDevice = devices.first
        }

        guard let selectedDevice else {
            return .failed(.cameraUnavailable, cameras: cameras)
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .medium

        do {
            let input = try AVCaptureDeviceInput(device: selectedDevice)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return .failed(.inputRejected, cameras: cameras)
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            return .failed(
                .inputCreationFailed(error.localizedDescription),
                cameras: cameras
            )
        }

        session.commitConfiguration()
        session.startRunning()

        guard session.isRunning else {
            return .failed(.startupFailed, cameras: cameras)
        }

        storage.session = session

        return .running(
            CaptureSessionSnapshot(
                session: session,
                cameras: cameras,
                selectedCamera: CameraDescriptor(device: selectedDevice)
            )
        )
    }

    private func stopOnQueue(sessionIdentifier: ObjectIdentifier?) {
        guard let session = storage.session else { return }
        if let sessionIdentifier,
           ObjectIdentifier(session) != sessionIdentifier {
            return
        }

        storage.session = nil
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func discoverDevices() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )

        var devices = discoverySession.devices
        if let defaultCamera = AVCaptureDevice.default(for: .video),
           !devices.contains(where: { $0.uniqueID == defaultCamera.uniqueID }) {
            devices.append(defaultCamera)
        }

        return devices
    }
}
