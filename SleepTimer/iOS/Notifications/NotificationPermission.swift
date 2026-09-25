import Foundation
import Combine
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Whether Sleep Timer is allowed to send local notifications. This is the
/// permission onboarding asks for explicitly, since the completion
/// notification isn't just a courtesy while the app is locked/backgrounded —
/// it's the only thing that can trigger the person's own Shortcuts
/// automation to pause their media. A small protocol, mirroring
/// `MediaPausing`/`ActivityControlling`, so the onboarding step is testable
/// without a real notification center.
enum NotificationAuthStatus: Equatable {
    case notDetermined
    case authorized
    case denied
}

protocol NotificationAuthorizing {
    func currentStatus(completion: @escaping (NotificationAuthStatus) -> Void)
    func requestAuthorization(completion: @escaping (NotificationAuthStatus) -> Void)
}

#if canImport(UserNotifications)
final class SystemNotificationAuthorizer: NotificationAuthorizing {
    func currentStatus(completion: @escaping (NotificationAuthStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = Self.map(settings.authorizationStatus)
            DispatchQueue.main.async { completion(status) }
        }
    }

    func requestAuthorization(completion: @escaping (NotificationAuthStatus) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted ? .authorized : .denied) }
        }
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthStatus {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}
#else
final class SystemNotificationAuthorizer: NotificationAuthorizing {
    func currentStatus(completion: @escaping (NotificationAuthStatus) -> Void) {
        completion(.notDetermined)
    }

    func requestAuthorization(completion: @escaping (NotificationAuthStatus) -> Void) {
        completion(.notDetermined)
    }
}
#endif

/// Backs the onboarding permission step. Kept separate from
/// `SleepTimerManager` (which still requests authorization lazily on first
/// `start()`, harmlessly re-asking nothing once a decision exists) since
/// this one drives its own screen and needs to observe/refresh status.
@MainActor
final class NotificationPermissionViewModel: ObservableObject {
    @Published private(set) var status: NotificationAuthStatus = .notDetermined

    private let authorizer: NotificationAuthorizing

    init(authorizer: NotificationAuthorizing = SystemNotificationAuthorizer()) {
        self.authorizer = authorizer
    }

    func refreshStatus() {
        authorizer.currentStatus { [weak self] status in
            self?.status = status
        }
    }

    func requestPermission() {
        authorizer.requestAuthorization { [weak self] status in
            self?.status = status
        }
    }
}
