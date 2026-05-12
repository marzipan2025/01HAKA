import SwiftUI

@main
struct HanjaWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 310, height: 270)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open History") {
                    SearchHistoryStore.openHistoryFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button("Erase Records") {
                    NotificationCenter.default.post(name: .hanjaEraseRecords, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Always on Top") {
                    NotificationCenter.default.post(name: .hanjaToggleAlwaysOnTop, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Toggle Glass Effect") {
                    NotificationCenter.default.post(name: .hanjaToggleGlassEffect, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let hanjaEraseRecords = Notification.Name("hanjaEraseRecords")
    static let hanjaToggleAlwaysOnTop = Notification.Name("hanjaToggleAlwaysOnTop")
    static let hanjaToggleGlassEffect = Notification.Name("hanjaToggleGlassEffect")
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var didSetup = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 저장된 윈도우 프레임 초기화
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame") {
            defaults.removeObject(forKey: key)
        }

        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            window.delegate = self
            self.applyStyle(window)
            self.didSetup = true
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            applyStyle(window)
        }
    }

    private func applyStyle(_ window: NSWindow) {
        window.styleMask = [.borderless, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.minSize = NSSize(width: 310, height: 270)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        clearFrameMask(for: window)

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 0
            contentView.layer?.masksToBounds = false
            contentView.layer?.backgroundColor = .clear
        }
    }

    private func clearFrameMask(for window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }
        frameView.wantsLayer = true
        frameView.layer?.cornerRadius = 0
        frameView.layer?.masksToBounds = false
        frameView.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
