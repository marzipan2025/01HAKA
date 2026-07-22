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
    /// 커스텀 스타일(테두리 제거)을 입힐 메인 콘텐츠 창. About 패널 등 보조 창은 제외.
    private weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 저장된 윈도우 프레임 초기화
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame") {
            defaults.removeObject(forKey: key)
        }

        // 창 생성 타이밍과 무관하게, 키 윈도우가 될 때마다 스타일을 보장.
        // 단, 메인 창에만 적용 — About 패널 등 나중에 뜨는 보조 창은 건드리지 않음.
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.styleIfMainWindow(window)
        }

        NSApplication.shared.windows.forEach(styleIfMainWindow)
    }

    /// 첫 번째로 나타나는 콘텐츠 창을 메인 창으로 확정하고, 그 창에만 스타일 적용.
    /// About 패널은 사용자가 메뉴를 누른 뒤에야(메인 창이 이미 확정된 후) 뜨므로 제외됨.
    private func styleIfMainWindow(_ window: NSWindow) {
        // 표준 About 패널 등 보조 창은 후보에서 제외
        if mainWindow == nil, !(window is NSPanel) {
            mainWindow = window
        }
        guard window === mainWindow else { return }
        applyStyle(window)
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
