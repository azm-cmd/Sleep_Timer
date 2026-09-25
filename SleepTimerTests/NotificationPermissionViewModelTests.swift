import XCTest
@testable import SleepTimer

/// Lets onboarding's notification-permission step be tested without a real
/// notification center — records what was asked and returns a status the
/// test controls, the same pattern as SpyMediaController/SpyActivityController.
final class SpyNotificationAuthorizer: NotificationAuthorizing {
    var statusToReturn: NotificationAuthStatus = .notDetermined
    var requestResult: NotificationAuthStatus = .authorized
    private(set) var currentStatusCallCount = 0
    private(set) var requestAuthorizationCallCount = 0

    func currentStatus(completion: @escaping (NotificationAuthStatus) -> Void) {
        currentStatusCallCount += 1
        completion(statusToReturn)
    }

    func requestAuthorization(completion: @escaping (NotificationAuthStatus) -> Void) {
        requestAuthorizationCallCount += 1
        completion(requestResult)
    }
}

@MainActor
final class NotificationPermissionViewModelTests: XCTestCase {
    func testInitialStatusIsNotDetermined() {
        let viewModel = NotificationPermissionViewModel(authorizer: SpyNotificationAuthorizer())
        XCTAssertEqual(viewModel.status, .notDetermined)
    }

    func testRefreshStatusAdoptsAuthorizersCurrentStatus() {
        let spy = SpyNotificationAuthorizer()
        spy.statusToReturn = .denied
        let viewModel = NotificationPermissionViewModel(authorizer: spy)

        viewModel.refreshStatus()

        XCTAssertEqual(viewModel.status, .denied)
        XCTAssertEqual(spy.currentStatusCallCount, 1)
    }

    func testRequestPermissionUpdatesStatusFromResult() {
        let spy = SpyNotificationAuthorizer()
        spy.requestResult = .authorized
        let viewModel = NotificationPermissionViewModel(authorizer: spy)

        viewModel.requestPermission()

        XCTAssertEqual(viewModel.status, .authorized)
        XCTAssertEqual(spy.requestAuthorizationCallCount, 1)
    }

    func testRequestPermissionReflectsDenial() {
        let spy = SpyNotificationAuthorizer()
        spy.requestResult = .denied
        let viewModel = NotificationPermissionViewModel(authorizer: spy)

        viewModel.requestPermission()

        XCTAssertEqual(viewModel.status, .denied)
    }
}
