import AppKit

@main
final class SnatchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // LSUIElement reinforcement
        app.run()
    }
}
