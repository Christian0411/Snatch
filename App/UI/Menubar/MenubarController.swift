import AppKit
import Combine
import SnatchKit

@MainActor
final class MenubarController: NSObject {

    private let session: RecordingSession
    private let scaleStore: ScalePresetStore
    private let rememberRegionStore: RememberRegionPreferenceStore
    private let autoStartStore: AutoStartRecordingPreferenceStore
    private let recentsStore: RecentRecordingsStore
    private let permissions: PermissionsCoordinator
    private let onStartRecording: () -> Void
    private let onStop: () -> Void

    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()

    init(session: RecordingSession,
         scaleStore: ScalePresetStore,
         rememberRegionStore: RememberRegionPreferenceStore,
         autoStartStore: AutoStartRecordingPreferenceStore,
         recentsStore: RecentRecordingsStore,
         permissions: PermissionsCoordinator,
         onStartRecording: @escaping () -> Void,
         onStop: @escaping () -> Void) {
        self.session = session
        self.scaleStore = scaleStore
        self.rememberRegionStore = rememberRegionStore
        self.autoStartStore = autoStartStore
        self.recentsStore = recentsStore
        self.permissions = permissions
        self.onStartRecording = onStartRecording
        self.onStop = onStop
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp])

        installIconSubscription()
    }

    private func installIconSubscription() {
        permissions.$state
            .combineLatest(session.$state)
            .receive(on: RunLoop.main)
            .sink { [weak self] perm, sess in
                guard let self, let button = self.statusItem.button else { return }
                let icon = MenubarIconState.icon(permission: perm, session: sess)
                button.image = icon.nsImage
            }
            .store(in: &cancellables)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // While recording, click stops immediately — no menu.
        if session.state == .recording {
            onStop()
            return
        }
        // Otherwise show the dropdown.
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // detach so the next single-click works
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let start = NSMenuItem(title: "Start Recording", action: #selector(startRecordingAction), keyEquivalent: "6")
        start.keyEquivalentModifierMask = [.shift, .command]
        start.target = self
        menu.addItem(start)

        menu.addItem(NSMenuItem.separator())

        // Scale ▸
        let scaleItem = NSMenuItem(title: "Scale", action: nil, keyEquivalent: "")
        let scaleSub = NSMenu()
        for preset in [ScalePreset.retina, .standard, .compact] {
            let item = NSMenuItem(title: scaleLabel(preset), action: #selector(setScaleAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            item.state = (scaleStore.current == preset) ? .on : .off
            scaleSub.addItem(item)
        }
        scaleItem.submenu = scaleSub
        menu.addItem(scaleItem)

        let remember = NSMenuItem(
            title: "Remember Last Capture Area",
            action: #selector(toggleRememberAction),
            keyEquivalent: ""
        )
        remember.target = self
        remember.state = rememberRegionStore.isEnabled ? .on : .off
        menu.addItem(remember)

        let autoStart = NSMenuItem(
            title: "Auto-Start Recording on Selection",
            action: #selector(toggleAutoStartAction),
            keyEquivalent: ""
        )
        autoStart.target = self
        autoStart.state = autoStartStore.isEnabled ? .on : .off
        autoStart.isEnabled = !rememberRegionStore.isEnabled
        menu.addItem(autoStart)

        // Recent Recordings ▸  (built lazily in menuWillOpen via delegate)
        let recentItem = NSMenuItem(title: "Recent Recordings", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        recentItem.tag = MenubarController.recentsTag
        menu.addItem(recentItem)

        menu.addItem(NSMenuItem.separator())

        let about = NSMenuItem(title: "About Snatch", action: #selector(aboutAction), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Snatch", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func scaleLabel(_ preset: ScalePreset) -> String {
        switch preset {
        case .retina:   return "Retina (2×)"
        case .standard: return "Standard (1×)"
        case .compact:  return "Compact (0.5×)"
        }
    }

    private static let recentsTag = 4242

    @objc private func startRecordingAction() {
        onStartRecording()
    }

    @objc private func setScaleAction(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? ScalePreset else { return }
        scaleStore.persist(preset)
    }

    @objc private func toggleRememberAction() {
        rememberRegionStore.setEnabled(!rememberRegionStore.isEnabled)
    }

    @objc private func toggleAutoStartAction() {
        autoStartStore.setEnabled(!autoStartStore.isEnabled)
    }

    @objc private func aboutAction() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    @objc private func openRecentAction(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

extension MenubarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Rebuild Recent Recordings ▸ submenu from current store.
        guard let recentItem = menu.item(withTag: Self.recentsTag),
              let sub = recentItem.submenu else { return }
        sub.removeAllItems()

        let recents = recentsStore.recents()
        if recents.isEmpty {
            let none = NSMenuItem(title: "(none)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        } else {
            for url in recents {
                let it = NSMenuItem(title: url.lastPathComponent,
                                    action: #selector(openRecentAction(_:)),
                                    keyEquivalent: "")
                it.target = self
                it.representedObject = url
                sub.addItem(it)
            }
        }
    }
}
