import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let controller = MaccordionController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        controller.start()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "맥코디언"
        window.minSize = NSSize(width: 760, height: 540)
        window.contentView = PlayView(controller: controller)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "맥코디언 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
