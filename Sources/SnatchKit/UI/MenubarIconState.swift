import Foundation

/// Three icon states the menubar can display, decoupled from any
/// AppKit / NSImage construction. `MenubarIconState.icon` is the pure
/// mapping function over the session and permission state machines;
/// the App target builds an `NSImage` from a `MenubarIcon` separately.
public enum MenubarIcon: Equatable {
    case idle
    case recording
    case permissionDenied
}

public enum MenubarIconState {
    /// Pure mapping function. Permission denied takes priority; otherwise
    /// session.recording → recording icon; everything else → idle.
    public static func icon(permission: PermissionsCoordinator.PermissionState,
                            session: RecordingSession.State) -> MenubarIcon {
        if permission == .denied { return .permissionDenied }
        return session == .recording ? .recording : .idle
    }
}
