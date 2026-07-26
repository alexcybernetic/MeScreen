@preconcurrency import AVFoundation
import Foundation
import XCTest
@testable import MeScreen

nonisolated private final class FakeAuthorizationProvider:
    CameraAuthorizationProviding,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var status: CameraAuthorization
    private let accessResult: Bool
    private var storedRequestCount = 0

    init(status: CameraAuthorization, accessResult: Bool = false) {
        self.status = status
        self.accessResult = accessResult
    }

    var requestCount: Int {
        lock.withLock { storedRequestCount }
    }

    func authorizationStatus() -> CameraAuthorization {
        lock.withLock { status }
    }

    func requestAccess() async -> Bool {
        lock.withLock {
            storedRequestCount += 1
        }
        return accessResult
    }
}

nonisolated private final class FakeSessionController:
    CaptureSessionControlling,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var outcomes: [CaptureSessionStartOutcome]
    private var discoveryResult: [CameraDescriptor]
    private var storedRequestedCameraIDs: [String?] = []
    private var storedStoppedSessionIDs: [ObjectIdentifier?] = []

    init(
        outcomes: [CaptureSessionStartOutcome],
        discoveryResult: [CameraDescriptor] = []
    ) {
        self.outcomes = outcomes
        self.discoveryResult = discoveryResult
    }

    var requestedCameraIDs: [String?] {
        lock.withLock { storedRequestedCameraIDs }
    }

    var stoppedSessionIDs: [ObjectIdentifier?] {
        lock.withLock { storedStoppedSessionIDs }
    }

    func discoverCameras() async -> [CameraDescriptor] {
        lock.withLock { discoveryResult }
    }

    func start(preferredCameraID: String?) async -> CaptureSessionStartOutcome {
        lock.withLock {
            storedRequestedCameraIDs.append(preferredCameraID)
            precondition(!outcomes.isEmpty, "Missing fake capture-session outcome")
            return outcomes.removeFirst()
        }
    }

    func stop(sessionIdentifier: ObjectIdentifier?) async {
        lock.withLock {
            storedStoppedSessionIDs.append(sessionIdentifier)
        }
    }
}

private actor ControlledSessionController: CaptureSessionControlling {
    private struct PendingStart {
        let continuation: CheckedContinuation<CaptureSessionStartOutcome, Never>
    }

    private var pendingStarts: [PendingStart] = []

    func discoverCameras() async -> [CameraDescriptor] {
        []
    }

    func start(preferredCameraID: String?) async -> CaptureSessionStartOutcome {
        await withCheckedContinuation { continuation in
            pendingStarts.append(PendingStart(continuation: continuation))
        }
    }

    func stop(sessionIdentifier: ObjectIdentifier?) async {}

    func waitForPendingStartCount(_ expectedCount: Int) async {
        while pendingStarts.count < expectedCount {
            await Task.yield()
        }
    }

    func resumeNextStart(with outcome: CaptureSessionStartOutcome) {
        precondition(!pendingStarts.isEmpty, "No pending fake capture-session start")
        pendingStarts.removeFirst().continuation.resume(returning: outcome)
    }
}

nonisolated final class CameraManagerStateTests: XCTestCase {
    @MainActor
    func testDeniedPermissionDoesNotStartCaptureSession() async {
        let authorization = FakeAuthorizationProvider(status: .denied)
        let sessions = FakeSessionController(outcomes: [])
        let manager = makeManager(
            authorization: authorization,
            sessions: sessions
        )

        await manager.checkPermissions()

        XCTAssertEqual(manager.cameraState, .permissionDenied)
        XCTAssertNil(manager.currentCamera)
        XCTAssertNil(manager.previewLayer)
        XCTAssertTrue(sessions.requestedCameraIDs.isEmpty)
        XCTAssertEqual(sessions.stoppedSessionIDs.count, 1)
    }

    @MainActor
    func testRejectedPermissionRequestIsExposed() async {
        let authorization = FakeAuthorizationProvider(
            status: .notDetermined,
            accessResult: false
        )
        let sessions = FakeSessionController(outcomes: [])
        let manager = makeManager(
            authorization: authorization,
            sessions: sessions
        )

        await manager.checkPermissions()

        XCTAssertEqual(authorization.requestCount, 1)
        XCTAssertEqual(manager.cameraState, .permissionDenied)
        XCTAssertTrue(sessions.requestedCameraIDs.isEmpty)
    }

    @MainActor
    func testCameraIsPublishedOnlyAfterSuccessfulStartup() async {
        let camera = camera(id: "built-in", name: "Built-in Camera")
        let snapshot = snapshot(camera: camera, cameras: [camera])
        let authorization = FakeAuthorizationProvider(status: .authorized)
        let sessions = FakeSessionController(outcomes: [.running(snapshot)])
        let manager = makeManager(
            authorization: authorization,
            sessions: sessions
        )

        await manager.checkPermissions()

        XCTAssertEqual(manager.cameraState, .running)
        XCTAssertEqual(manager.currentCamera, camera)
        XCTAssertEqual(manager.availableCameras, [camera])
        XCTAssertIdentical(manager.previewLayer?.session, snapshot.session)
    }

    @MainActor
    func testStartupFailureDoesNotPublishSelectedCamera() async {
        let camera = camera(id: "external", name: "External Camera")
        let authorization = FakeAuthorizationProvider(status: .authorized)
        let sessions = FakeSessionController(
            outcomes: [.failed(.inputRejected, cameras: [camera])]
        )
        let manager = makeManager(
            authorization: authorization,
            sessions: sessions
        )

        await manager.checkPermissions()

        XCTAssertEqual(
            manager.cameraState,
            .failed(CaptureSessionFailure.inputRejected.message)
        )
        XCTAssertNil(manager.currentCamera)
        XCTAssertNil(manager.previewLayer)
        XCTAssertEqual(manager.availableCameras, [camera])
    }

    @MainActor
    func testSupersededStartupCannotPublishStaleSession() async {
        let firstCamera = camera(id: "first", name: "First Camera")
        let secondCamera = camera(id: "second", name: "Second Camera")
        let firstSnapshot = snapshot(camera: firstCamera, cameras: [firstCamera, secondCamera])
        let secondSnapshot = snapshot(camera: secondCamera, cameras: [firstCamera, secondCamera])
        let sessions = ControlledSessionController()
        let manager = makeManager(
            authorization: FakeAuthorizationProvider(status: .authorized),
            sessions: sessions
        )

        manager.switchCamera(to: firstCamera)
        await sessions.waitForPendingStartCount(1)
        manager.switchCamera(to: secondCamera)
        await sessions.waitForPendingStartCount(2)

        await sessions.resumeNextStart(with: .running(firstSnapshot))
        await Task.yield()
        XCTAssertNil(manager.currentCamera)

        await sessions.resumeNextStart(with: .running(secondSnapshot))
        await waitUntil { manager.currentCamera == secondCamera }

        XCTAssertEqual(manager.cameraState, .running)
        XCTAssertIdentical(manager.previewLayer?.session, secondSnapshot.session)
    }

    @MainActor
    func testDisconnectingCurrentCameraStartsAvailableFallback() async {
        let disconnectedCamera = camera(id: "external", name: "External Camera")
        let fallbackCamera = camera(id: "built-in", name: "Built-in Camera")
        let sessions = FakeSessionController(
            outcomes: [
                .running(snapshot(
                    camera: disconnectedCamera,
                    cameras: [disconnectedCamera, fallbackCamera]
                )),
                .running(snapshot(
                    camera: fallbackCamera,
                    cameras: [fallbackCamera]
                )),
            ]
        )
        let manager = makeManager(
            authorization: FakeAuthorizationProvider(status: .authorized),
            sessions: sessions
        )

        await manager.checkPermissions()
        manager.handleDeviceChange(
            .disconnected(cameraID: disconnectedCamera.id)
        )
        await waitUntil { manager.currentCamera == fallbackCamera }

        XCTAssertEqual(manager.availableCameras, [fallbackCamera])
        XCTAssertEqual(sessions.requestedCameraIDs, [nil, nil])
    }

    @MainActor
    func testRuntimeErrorClearsOnlyMatchingActiveSession() async {
        let camera = camera(id: "built-in", name: "Built-in Camera")
        let activeSnapshot = snapshot(camera: camera, cameras: [camera])
        let unrelatedSnapshot = snapshot(camera: camera, cameras: [camera])
        let sessions = FakeSessionController(outcomes: [.running(activeSnapshot)])
        let manager = makeManager(
            authorization: FakeAuthorizationProvider(status: .authorized),
            sessions: sessions
        )

        await manager.checkPermissions()
        manager.handleRuntimeError(
            sessionIdentifier: unrelatedSnapshot.sessionIdentifier,
            message: "Unrelated failure"
        )
        XCTAssertEqual(manager.cameraState, .running)

        manager.handleRuntimeError(
            sessionIdentifier: activeSnapshot.sessionIdentifier,
            message: "Camera disconnected"
        )
        await waitUntil { !sessions.stoppedSessionIDs.isEmpty }

        XCTAssertEqual(manager.cameraState, .failed("Camera disconnected"))
        XCTAssertNil(manager.currentCamera)
        XCTAssertNil(manager.previewLayer)
        XCTAssertEqual(
            sessions.stoppedSessionIDs,
            [activeSnapshot.sessionIdentifier]
        )
    }

    @MainActor
    private func makeManager(
        authorization: CameraAuthorizationProviding,
        sessions: CaptureSessionControlling
    ) -> CameraManager {
        CameraManager(
            startCamera: false,
            authorizationProvider: authorization,
            sessionController: sessions,
            notificationCenter: NotificationCenter()
        )
    }

    @MainActor
    private func camera(
        id: String,
        name: String,
        isExternal: Bool = false
    ) -> CameraDescriptor {
        CameraDescriptor(id: id, name: name, isExternal: isExternal)
    }

    @MainActor
    private func snapshot(
        camera: CameraDescriptor,
        cameras: [CameraDescriptor]
    ) -> CaptureSessionSnapshot {
        let session = AVCaptureSession()
        return CaptureSessionSnapshot(
            session: session,
            cameras: cameras,
            selectedCamera: camera
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied", file: file, line: line)
    }
}
