import Foundation
import UserNotifications

/// Presents save-success and failure notifications via UNUserNotificationCenter.
@MainActor
final class NotificationPresenter {
    init() {}

    func requestAuthorizationIfNeeded() async {
        // Task 21.
    }

    func present(savedURL: URL) {
        // Task 21.
    }

    func presentFailure(_ message: String) {
        // Task 21.
    }
}
