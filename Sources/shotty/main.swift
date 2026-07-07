import AppKit
import Carbon.HIToolbox

// MARK: - Menu-bar agent

final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var editors: Set<EditorController> = []

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shotty")

        let menu = NSMenu()
        menu.addItem(withTitle: "Capture Full Screen  ⌘⇧3", action: #selector(captureFull), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Capture Region / Window  ⌘⇧4", action: #selector(captureRegion), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Shotty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        Updater.check(verbose: false) // silent check on launch

        // Take over the system screenshot keys (requires macOS's own ⌘⇧3/⌘⇧4 to be disabled — see
        // Scripts/macos-screenshots.sh). kVK_ANSI_3 = 0x14, kVK_ANSI_4 = 0x15.
        hotKeys = [
            HotKey(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in self?.capture(interactive: false) },
            HotKey(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in self?.capture(interactive: true) },
        ]
    }

    @objc private func captureFull() { capture(interactive: false) }
    @objc private func captureRegion() { capture(interactive: true) }
    @objc private func checkForUpdates() { Updater.check(verbose: true) }

    private func capture(interactive: Bool) {
        // screencapture blocks until the user finishes; run it off the main thread so open editors don't freeze.
        // -i = interactive region select (press Space to switch to window capture); no flag = whole screen.
        let tmp = NSTemporaryDirectory() + "shotty-\(ProcessInfo.processInfo.processIdentifier)-\(self.editors.count).png"
        let args = interactive ? ["-i", tmp] : [tmp]
        DispatchQueue.global(qos: .userInitiated).async {
            let cap = Process()
            cap.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            cap.arguments = args
            try? cap.run()
            cap.waitUntilExit()
            guard FileManager.default.fileExists(atPath: tmp),
                  let shot = NSImage(contentsOfFile: tmp) else { return } // user hit Esc
            try? FileManager.default.removeItem(atPath: tmp)
            DispatchQueue.main.async {
                let editor = EditorController(image: shot)
                editor.onClose = { [weak self] e in self?.editors.remove(e) }
                self.editors.insert(editor)
            }
        }
    }
}

// MARK: - Entry

if CommandLine.arguments.contains("--selfcheck") {
    runSelfCheck()
    exit(0)
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.run()
