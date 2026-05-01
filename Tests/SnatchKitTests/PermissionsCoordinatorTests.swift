import XCTest
@testable import SnatchKit

@MainActor
final class PermissionsCoordinatorTests: XCTestCase {

    final class FakeAdapter: CGScreenCapturePermissionAdapter, @unchecked Sendable {
        var preflightResult: Bool = false
        var requestResult: Bool = false
        var preflightCallCount = 0
        var requestCallCount = 0

        func preflight() -> Bool {
            preflightCallCount += 1
            return preflightResult
        }
        func request() -> Bool {
            requestCallCount += 1
            return requestResult
        }
    }

    func test_preflight_grantedAdapter_yieldsGrantedState() {
        let a = FakeAdapter(); a.preflightResult = true
        let coord = PermissionsCoordinator(adapter: a)
        let state = coord.preflight()
        XCTAssertEqual(state, .granted)
        XCTAssertEqual(coord.cachedState, .granted)
    }

    func test_preflight_falseAdapter_yieldsNotDeterminedInitially() {
        let a = FakeAdapter(); a.preflightResult = false
        let coord = PermissionsCoordinator(adapter: a)
        XCTAssertEqual(coord.preflight(), .notDetermined)
    }

    func test_request_grantsThenStateIsGranted() async {
        let a = FakeAdapter(); a.preflightResult = false; a.requestResult = true
        let coord = PermissionsCoordinator(adapter: a)
        _ = coord.preflight()
        let result = await coord.request()
        XCTAssertEqual(result, .granted)
        XCTAssertEqual(coord.cachedState, .granted)
        XCTAssertEqual(a.requestCallCount, 1)
    }

    func test_request_deniedThenStateIsDenied() async {
        let a = FakeAdapter(); a.preflightResult = false; a.requestResult = false
        let coord = PermissionsCoordinator(adapter: a)
        _ = coord.preflight()
        let result = await coord.request()
        XCTAssertEqual(result, .denied)
        XCTAssertEqual(coord.cachedState, .denied)
    }

    func test_grantedCache_shortCircuitsSubsequentPreflights() {
        let a = FakeAdapter(); a.preflightResult = true
        let coord = PermissionsCoordinator(adapter: a)
        _ = coord.preflight()
        a.preflightResult = false  // adapter changes underneath; cache should win

        XCTAssertEqual(coord.preflight(), .granted)
        XCTAssertEqual(a.preflightCallCount, 1)  // second call short-circuits
    }

    func test_revocationObserver_transitionsGrantedToDenied() {
        let a = FakeAdapter(); a.preflightResult = true
        let coord = PermissionsCoordinator(adapter: a)
        _ = coord.preflight()
        XCTAssertEqual(coord.cachedState, .granted)

        a.preflightResult = false
        coord.observeRevocation()  // simulates didBecomeActive re-check

        XCTAssertEqual(coord.cachedState, .denied)
    }

    func test_PermissionsCoordinator_publishesStateChanges() {
        let a = FakeAdapter(); a.preflightResult = false
        let coord = PermissionsCoordinator(adapter: a)
        var observed: [PermissionsCoordinator.PermissionState] = []
        let cancellable = coord.$state.sink { observed.append($0) }
        defer { cancellable.cancel() }

        _ = coord.preflight()
        a.preflightResult = true
        coord.observeRevocation()

        // Initial value, then after preflight (.notDetermined), then granted.
        XCTAssertTrue(observed.contains(.notDetermined))
        XCTAssertTrue(observed.contains(.granted))
    }
}
