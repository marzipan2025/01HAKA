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

class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyWindowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 저장된 윈도우 프레임 초기화
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame") {
            defaults.removeObject(forKey: key)
        }

        // 창 생성 타이밍과 무관하게, 키 윈도우가 될 때마다 스타일을 보장
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.applyStyle(window)
        }

        NSApplication.shared.windows.forEach(applyStyle)
    }

    private func applyStyle(_ window: NSWindow) {
        // styleMask가 어떤 이유로 되돌아가도 시스템 신호등이 다시 보이지 않도록 명시적으로 숨김
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

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

        // 투명 창의 잔상(이전 프레임 그림자) 제거
        window.invalidateShadow()
    }

    private func clearFrameMask(for window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }
        frameView.wantsLayer = true
        frameView.layer?.cornerRadius = 0
        frameView.layer?.masksToBounds = false
        frameView.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
