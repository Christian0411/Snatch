import XCTest
@testable import SnatchKit

@MainActor
final class MenubarIconStateTests: XCTestCase {

    private let allSessionStates: [RecordingSession.State] = [
        .idle, .cropping, .recording, .finalizing, .cancelling
    ]

    func test_denied_returnsPermissionDenied_regardlessOfSession() {
        for session in allSessionStates {
            XCTAssertEqual(
                MenubarIconState.icon(permission: .denied, session: session),
                .permissionDenied,
                "denied + \(session) should be .permissionDenied"
            )
        }
    }

    func test_recording_withGrantedOrNotDetermined_returnsRecording() {
        XCTAssertEqual(MenubarIconState.icon(permission: .granted, session: .recording), .recording)
        XCTAssertEqual(MenubarIconState.icon(permission: .notDetermined, session: .recording), .recording)
    }

    func test_idleStates_returnIdle() {
        let nonRecording: [RecordingSession.State] = [.idle, .cropping, .finalizing, .cancelling]
        for permission in [PermissionsCoordinator.PermissionState.granted, .notDetermined] {
            for session in nonRecording {
                XCTAssertEqual(
                    MenubarIconState.icon(permission: permission, session: session),
                    .idle,
                    "\(permission) + \(session) should be .idle"
                )
            }
        }
    }
}
