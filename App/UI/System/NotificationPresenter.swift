import Foundation
import AppKit
import os
import SnatchKit
import UserNotifications

/// Presents save-success and failure notifications via
/// UNUserNotificationCenter. Save notifications carry a "Reveal in
/// Finder" action that opens Finder selecting the saved GIF.
@MainActor
final class NotificationPresenter: NSObject {
    static let revealActionId = "co.snatch.notification.reveal"
    static let savedCategoryId = "co.snatch.notification.saved"
    static let failureCategoryId = "co.snatch.notification.failure"

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self

        let revealAction = UNNotificationAction(
            identifier: Self.revealActionId,
            title: "Reveal in Finder",
            options: []
        )
        let savedCategory = UNNotificationCategory(
            identifier: Self.savedCategoryId,
            actions: [revealAction],
            intentIdentifiers: [],
            options: []
        )
        let failureCategory = UNNotificationCategory(
            identifier: Self.failureCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([savedCategory, failureCategory])
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.system.error("notification authorization failed: \(String(describing: error), privacy: .public)")
        }
    }

    func present(savedURL: URL, onAdded: (() -> Void)? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "GIF saved"
        content.body = savedURL.lastPathComponent
        content.sound = .default
        content.categoryIdentifier = Self.savedCategoryId
        content.userInfo = ["path": savedURL.path]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.system.error("notification add failed: \(String(describing: error), privacy: .public)")
            }
            onAdded?()
        }
    }

    func presentFailure(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Snatch — recording failed"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = Self.failureCategoryId

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

extension NotificationPresenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let path = response.notification.request.content.userInfo["path"] as? String
        let isReveal = response.actionIdentifier == Self.revealActionId
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        if isReveal, let path {
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
