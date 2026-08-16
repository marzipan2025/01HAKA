import SwiftUI
import AVFoundation

// MARK: - Overlay scroller (트랙 배경 숨김)

/// 트랙(slot)을 그리지 않는 스크롤러
class TransparentScroller: NSScroller {
    override static var isCompatibleWithOverlayScrollers: Bool { true }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // slot(트랙) 그리기 생략
    }
    override func draw(_ dirtyRect: NSRect) {
        drawKnob()
    }
}

struct OverlayScrollerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ScrollViewFinder()
                    .frame(width: 0, height: 0)
            )
    }
}

struct ScrollViewFinder: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applyStyle(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyStyle(from: nsView)
        }
    }

    private func applyStyle(from view: NSView) {
        guard let scrollView = findScrollView(in: view) else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        if let docView = scrollView.documentView {
            docView.wantsLayer = true
            docView.layer?.backgroundColor = .clear
        }

        // 세로 스크롤러 → 트랙 없는 커스텀 스크롤러로 교체
        if !(scrollView.verticalScroller is TransparentScroller) {
            let newScroller = TransparentScroller()
            newScroller.scrollerStyle = .overlay
            scrollView.verticalScroller = newScroller
        }
        scrollView.verticalScroller?.alphaValue = 0.5

        if !(scrollView.horizontalScroller is TransparentScroller) {
            let newScroller = TransparentScroller()
            newScroller.scrollerStyle = .overlay
            scrollView.horizontalScroller = newScroller
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let parent = current?.superview {
            if let scrollView = parent as? NSScrollView {
                return scrollView
            }
            current = parent
        }
        return nil
    }
}

extension Color {
    /// 본문 텍스트 색 (#8698B5 @ 0.6) — 리퀴드 모드 활성일 때 (기존 #8FA1BE에서 각 채널 -0x09)
    static let hanjaText = Color(red: 0x86/255, green: 0x98/255, blue: 0xB5/255).opacity(0.6)
    /// 비리퀴드(불투명/포커스아웃) 상태의 본문 텍스트 색 — 위 색보다 30% 어둡게 (#647185 @ 0.8)
    static let hanjaTextDim = Color(red: 0x64/255, green: 0x71/255, blue: 0x85/255).opacity(0.8)
}

// MARK: - Legacy background (pre-macOS 26 fallback)

final class PassthroughVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var alpha: CGFloat = 1.0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassthroughVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.alphaValue = alpha
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.alphaValue = alpha
    }
}

struct GlassBackgroundModifier: ViewModifier {
    private let cornerRadius: CGFloat = 26

    var useGlass: Bool
    /// 창이 활성 상태인지. 비활성이면 리퀴드 대신 불투명(legacy) 배경으로 내림
    var isWindowActive: Bool = true

    @ViewBuilder
    private func legacyBackground(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectBackground(material: .fullScreenUI, blendingMode: .behindWindow, alpha: 1.0)
                    Color(red: 0xF5/255, green: 0xF4/255, blue: 0xFF/255).opacity(0.85)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), useGlass, isWindowActive {
            content
                .background(
                    // 색면 없이 유리 밑 블러 레이어만으로 가독성 확보
                    VisualEffectBackground(material: .fullScreenUI, blendingMode: .behindWindow, alpha: 0.35)
                )
                .glassEffect(.clear, in: .rect(cornerRadius: 0))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            legacyBackground(content)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = HanjaViewModel()
    @AppStorage("useGlassEffect") private var useGlassEffect: Bool = true
    @FocusState private var isInputFocused: Bool
    @State private var isTrafficLightHovered = false
    @State private var isWindowActive = true

    /// 현재 마우스가 올라가 있어 스크롤 대상이 되는 영역 (상단 한자 / 중간 훈·음).
    /// 스크롤은 커서 아래 영역으로 가므로, 이 값으로 두 영역의 위치 감지기를 배타적으로 게이트한다.
    enum ScrollFocus { case none, top, middle }
    @State private var scrollFocus: ScrollFocus = .none

    /// 리퀴드 글래스가 실제로 보이는 상태 (배경 모디파이어 조건과 일치)
    private var isLiquidActive: Bool {
        if #available(macOS 26.0, *) {
            return useGlassEffect && isWindowActive
        }
        return false
    }

    /// 본문 텍스트 색 — 비리퀴드(불투명/포커스아웃)일 때 20% 어둡게
    private var textColor: Color {
        isLiquidActive ? Color.hanjaText : Color.hanjaTextDim
    }

    var body: some View {
        VStack(spacing: 0) {
            windowChromeArea
                .frame(maxWidth: .infinity)
                .frame(height: 26)

            // 상단: 한자 표시 (고정 높이)
            hanjaDisplayArea
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .onHover { if $0 { scrollFocus = .top } else if scrollFocus == .top { scrollFocus = .none } }

            // 중단: 훈/음 표시 (가변 높이). 설정 모드에서는 같은 자리를 설정 본문이 차지한다 —
            // 겹치면 훈/음 스크롤이 뒤에서 계속 잡히므로 덮지 않고 갈아끼운다.
            Group {
                if viewModel.isShowingSettings {
                    settingsArea
                } else {
                    hunEumArea
                        .onHover { if $0 { scrollFocus = .middle } else if scrollFocus == .middle { scrollFocus = .none } }
                        .overlay {
                            if showUpdatePrompt {
                                updateButton
                            } else if showUpdatedNotice {
                                updatedVersionBody
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)

            // 하단: 입력 영역 (고정 높이)
            inputArea
                .frame(height: 50)
        }
        .padding(0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 310, minHeight: 270)
        .modifier(GlassBackgroundModifier(useGlass: useGlassEffect, isWindowActive: isWindowActive))
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isWindowActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            isWindowActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .hanjaEraseRecords)) { _ in
            UserDefaults.standard.removeObject(forKey: "hanjaSearchHistory")
            SearchHistoryStore.deleteHistoryFile()
            viewModel.showEraseConfirmation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hanjaToggleAlwaysOnTop)) { _ in
            viewModel.isAlwaysOnTop.toggle()
            setWindowLevel(viewModel.isAlwaysOnTop ? .floating : .normal)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hanjaToggleGlassEffect)) { _ in
            useGlassEffect.toggle()
            refocusInputIfNeeded()
        }
        // ⌘, 는 토글 — 설정에 들어간 단축키로 그대로 나올 수 있다.
        .onReceive(NotificationCenter.default.publisher(for: .hanjaOpenSettings)) { _ in
            viewModel.toggleSettings()
            if viewModel.isShowingSettings {
                isInputFocused = false
            } else {
                refocusInputIfNeeded()
            }
        }
        .onAppear {
            refocusInputIfNeeded()
            viewModel.setupKeyMonitor { [weak viewModel] in
                viewModel?.resetToEditing()
                self.refocusInputIfNeeded()
            }
            viewModel.checkPostUpdate()
            viewModel.checkForUpdate()
        }
    }

    /// 초기 화면(검색 전) 여부
    private var isIdleScreen: Bool {
        viewModel.isEditing
            && !viewModel.hasSearched
            && viewModel.searchResult == nil
    }

    /// 업데이트 안내를 보여줄 조건: 새 버전 있음 + 초기 화면 + 미해제 + 방금 업데이트한 게 아님
    private var showUpdatePrompt: Bool {
        viewModel.updateAvailable && !viewModel.updateDismissed
            && !viewModel.justUpdated && isIdleScreen
    }

    /// 설치 후 재실행 안내를 보여줄 조건: 방금 업데이트됨 + 초기 화면 + 미해제
    private var showUpdatedNotice: Bool {
        viewModel.justUpdated && !viewModel.updateDismissed && isIdleScreen
    }

    private func setWindowLevel(_ level: NSWindow.Level) {
        NSApplication.shared.windows.first?.level = level
    }

    private var windowChromeArea: some View {
        HStack(alignment: .top) {
            trafficLightButtons
                .padding(.top, 27)
                .padding(.leading, 16)

            Spacer(minLength: 0)

            alwaysOnTopButton
                .padding(.top, 14)
                .padding(.trailing, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .contentShape(Rectangle())
    }

    private var trafficLightButtons: some View {
        HStack(spacing: 8) {
            trafficLightButton(
                color: Color(red: 1.0, green: 0.38, blue: 0.34),
                icon: AnyView(
                    Image("x_btn")
                        .resizable()
                        .frame(width: 14, height: 14)
                )
            ) {
                windowForActions()?.close()
            }
            trafficLightButton(
                color: Color(red: 1.0, green: 0.74, blue: 0.18),
                icon: AnyView(
                    Image("minus_btn")
                        .resizable()
                        .frame(width: 14, height: 14)
                )
            ) {
                windowForActions()?.miniaturize(nil)
            }
            trafficLightButton(
                color: Color(red: 0.16, green: 0.78, blue: 0.27),
                icon: AnyView(
                    Image("max_btn")
                        .resizable()
                        .frame(width: 14, height: 14)
                )
            ) {
                windowForActions()?.zoom(nil)
            }
        }
        .onHover { isTrafficLightHovered = $0 }
    }

    private func trafficLightButton(color: Color, icon: AnyView, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .overlay(Circle().stroke(Color.black.opacity(0.20), lineWidth: 0.6))

                icon
                    .opacity(isTrafficLightHovered ? 1 : 0)
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var alwaysOnTopButton: some View {
        Button(action: {
            viewModel.isAlwaysOnTop.toggle()
            setWindowLevel(viewModel.isAlwaysOnTop ? .floating : .normal)
        }) {
            Image("onTop")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                // 핀 됨: #181818 @0.8 / 안 됨: 글자색(#8FA1BE)에서 0.1 더 투명한 @0.5
                .foregroundColor(viewModel.isAlwaysOnTop
                    ? Color(red: 0x18/255, green: 0x18/255, blue: 0x18/255).opacity(0.8)
                    : Color(red: 0x8F/255, green: 0xA1/255, blue: 0xBE/255).opacity(0.5))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func windowForActions() -> NSWindow? {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first(where: { $0.isVisible })
    }

    private func refocusInputIfNeeded() {
        guard viewModel.isEditing, !viewModel.isShowingSettings else { return }

        for delay in [0.0, 0.05, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard viewModel.isEditing, !viewModel.isShowingSettings else { return }
                if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                    window.makeKeyAndOrderFront(nil)
                }
                isInputFocused = false
                DispatchQueue.main.async {
                    guard viewModel.isEditing, !viewModel.isShowingSettings else { return }
                    isInputFocused = true
                }
            }
        }
    }

    // MARK: - 업데이트 버튼 (가운데 패널)

    private var updateButton: some View {
        Button(action: { viewModel.startUpdate() }) {
            Text(viewModel.isUpdating ? "Updating…" : "Update to v \(viewModel.latestVersion)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(textColor)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isUpdating)
    }

    // 설치 후 버전 정보: 훈/음 영역과 같은 스타일로 바디 좌상단에 문장으로 표기
    private var updatedVersionBody: some View {
        Text("Version \(viewModel.updatedToVersion) has been installed.")
            .font(.system(size: 14))
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
    }

    // MARK: - 한자 표시 영역 (고정 높이)

    private var hanjaDisplayArea: some View {
        Group {
            if viewModel.isShowingSettings {
                // 설정 모드 표제 — 초기 화면의 "漢字"와 같은 자리·같은 규칙
                Text("設定")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 14)
                    .padding(.top, 12)
            } else if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = viewModel.searchResult, !result.words.isEmpty {
                hanjaTextView(result: result)
            } else if viewModel.hasSearched {
                Text(viewModel.failureMessage)
                    .foregroundColor(viewModel.isEraseMessage ? .black.opacity(0.3) : textColor)
                    .font(.system(size: 56, weight: .ultraLight))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 14)
                    .padding(.top, 10)
            } else if showUpdatedNotice {
                // 설치 후 재실행: 실패 메시지와 동일 규칙(56pt, 축소 없이 잘림)
                Text("Updated")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 14)
                    .padding(.top, 10)
            } else if showUpdatePrompt {
                // 실패 메시지와 동일 규칙: 한자와 같은 56pt, 축소 없이 넘치면 잘림
                Text(viewModel.isUpdating
                     ? (viewModel.updateStatusText.isEmpty ? "Updating…" : viewModel.updateStatusText)
                     : "New Update")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 14)
                    .padding(.top, 10)
            } else {
                Text("漢字")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 14)
                    .padding(.top, 12)
            }
        }
    }

    /// 단일 변형(variant) 하나의 Text 생성 (한자 글자들 + 인디케이터)
    private func buildVariantText(variant: String, vIdx: Int, isActive: Bool, hasMultipleVariants: Bool) -> Text {
        var text = Text("")
        for char in variant {
            let count = viewModel.previousSearchCount(for: char)
            let tier = count / 10
            let weights: [Font.Weight] = [.ultraLight, .light, .medium]
            let weight = weights[min(tier, weights.count - 1)]
            let color: Color = {
                if !isActive { return textColor }
                if tier >= 5 { return .black }
                else if tier >= 4 { return Color(red: 1, green: 1, blue: 0) }
                else if tier >= 3 { return Color(red: 1, green: 0xFC/255, blue: 0xCB/255) }
                return textColor
            }()
            text = text + Text(String(char))
                .font(.system(size: 56, weight: weight))
                .foregroundColor(color)
        }
        if hasMultipleVariants {
            if vIdx == 0 {
                text = text + Text(" ●")
                    .font(.system(size: 6))
                    .foregroundColor(.red)
                    .baselineOffset(42)
                text = text + Text(" ")
                    .font(.system(size: 6))
            } else {
                text = text + Text(" \(vIdx)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textColor)
                    .baselineOffset(38)
            }
        }
        return text
    }

    /// 비활성 단어 또는 단일 변형 단어 → 하나의 Text (텍스트 선택 전체 가능)
    private func buildSingleWordText(word: HanjaWord, wordIndex: Int) -> Text {
        let hasMultipleVariants = word.hanjaVariants.count > 1
        let isActive = wordIndex == viewModel.activeWordIndex
        var text = Text("")
        for (vIdx, variant) in word.hanjaVariants.enumerated() {
            if vIdx > 0 {
                text = text + Text(", ")
                    .font(.system(size: 42, weight: .ultraLight))
                    .baselineOffset(-10)
                    .foregroundColor(isActive ? textColor : textColor)
            }
            text = text + buildVariantText(variant: variant, vIdx: vIdx, isActive: isActive, hasMultipleVariants: hasMultipleVariants)
        }
        return text
    }

    /// 활성 단어 + 복수 변형 → 변형별 독립 뷰 (x좌표 감지용)
    @ViewBuilder
    private func hanjaActiveWordView(word: HanjaWord, wordIndex: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(word.hanjaVariants.enumerated()), id: \.offset) { vIdx, variant in
                if vIdx > 0 {
                    Text(", ")
                        .font(.system(size: 30, weight: .ultraLight))
                        .baselineOffset(-22)
                        .foregroundColor(textColor)
                }
                buildVariantText(variant: variant, vIdx: vIdx, isActive: true, hasMultipleVariants: true)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .fixedSize()
                    .background(
                        GeometryReader { geo in
                            let minX = geo.frame(in: .named("hanjaScroll")).minX
                            Color.clear
                                .onChange(of: minX) { _, x in
                                    // 상단을 스크롤 중일 때만 변형 감지 (중간 follow 중에는 무시)
                                    guard scrollFocus == .top else { return }
                                    if x >= 20 && x <= 40 {
                                        viewModel.activeVariantIndex = vIdx
                                    }
                                }
                        }
                    )
            }
        }
        .padding(.leading, 14)
        .id(wordIndex)
    }

    private func hanjaTextView(result: SearchResult) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(result.words.enumerated()), id: \.offset) { index, word in
                        if index == viewModel.activeWordIndex && word.hanjaVariants.count > 1 {
                            // 활성 단어 + 복수 변형: 변형별 뷰 분리 (variant x좌표 감지)
                            hanjaActiveWordView(word: word, wordIndex: index)
                                .background(wordPositionTracker(wordIndex: index))
                        } else {
                            // 비활성 단어 또는 단일 변형: 단일 Text (전체 선택 가능)
                            buildSingleWordText(word: word, wordIndex: index)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.leading, 14)
                                .background(wordPositionTracker(wordIndex: index))
                                .id(index)
                        }
                    }
                }
                .padding(.trailing, 16)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 12)
            }
            .coordinateSpace(name: "hanjaScroll")
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: viewModel.activeWordIndex) { _, newIndex in
                viewModel.activeVariantIndex = 0
                // 위치 감지로 변경된 경우 역방향 스크롤 생략
                guard !viewModel.isPositionTriggered else {
                    viewModel.isPositionTriggered = false
                    return
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newIndex, anchor: .leading)
                }
            }
        }
    }

    /// 모든 단어 공통: x좌표 감지 → activeWordIndex 변경 (스크롤 없이)
    private func wordPositionTracker(wordIndex: Int) -> some View {
        GeometryReader { geo in
            let minX = geo.frame(in: .named("hanjaScroll")).minX
            Color.clear
                .onChange(of: minX) { _, x in
                    // 사용자가 상단을 스크롤 중일 때만 감지 (중간 follow 스크롤/키보드는 무시)
                    guard scrollFocus == .top, !viewModel.isKeyTriggered else { return }
                    // 순방향: 다른 단어가 x=20~40 구간 진입 → 해당 단어 활성화
                    if x >= 20 && x <= 40 && viewModel.activeWordIndex != wordIndex {
                        viewModel.isPositionTriggered = true
                        viewModel.activeWordIndex = wordIndex
                        viewModel.activeVariantIndex = 0
                    }
                    // 역방향: 활성 단어가 오른쪽으로 화면 밖으로 빠지면 → 이전 단어 활성화
                    else if wordIndex == viewModel.activeWordIndex && x > 100 && wordIndex > 0 {
                        viewModel.isPositionTriggered = true
                        viewModel.activeWordIndex = wordIndex - 1
                        viewModel.activeVariantIndex = 0
                    }
                }
        }
    }

    // MARK: - 설정 영역 (⌘,)

    /// 설정 본문. 훈/음 영역과 같은 배경·스크롤러를 써서 같은 자리에 그대로 갈아끼워진다.
    private var settingsArea: some View {
        ScrollViewReader { proxy in
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                updateRow
                    .id("settingsTop")

                settingsSection("검색", [
                    ("한자", "한글 단어나 문장을 넣으면 두 글자 이상인 말을 한자로 바꿔 보여줍니다."),
                    ("모", "한 글자만 넣으면 그 음을 가진 한자를 모두 모아 보여줍니다."),
                    ("(어미 모)", "괄호 안에 훈과 음을 함께 넣으면 그 글자를 콕 집어 찾습니다."),
                    ("(어미)", "괄호 안에 훈만 넣으면 훈에 그 말이 들어간 한자를 모두 찾습니다."),
                ])

                settingsSection("읽는 법", [
                    ("❶ ⑧", "훈 앞의 원기호는 배정 급수입니다. ● 는 특급, 숫자가 클수록 쉬운 급수."),
                    ("●  1  2", "같은 말을 여러 한자로 쓸 때 ● 가 첫 번째, 숫자가 그 다음 표기입니다."),
                    ("+  −", "단어 뜻을 펼치고 접습니다."),
                    ("굵기", "자주 찾은 글자일수록 굵고 진해집니다. 열 번마다 한 단계씩."),
                ])

                settingsSection("단축키", [
                    ("⌘ ,", "설정 열고 닫기"),
                    ("⌘ O", "검색 기록 폴더 열기"),
                    ("⌘ E", "검색 기록 지우기"),
                    ("⌘ T", "창을 항상 위에"),
                    ("⌘ G", "유리 효과 켜고 끄기"),
                    ("← →", "결과에서 앞뒤 단어로 이동"),
                    ("↩", "새 검색 시작"),
                ])
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: .infinity)
        .modifier(OverlayScrollerModifier())
        .contentMargins(.top, 12, for: .scrollContent)
        .background(Color(red: 0xBA/255, green: 0xD0/255, blue: 0xE2/255).opacity(0.14))
        // 업데이트 줄이 버튼↔텍스트로 바뀌면 눌린 버튼이 사라지면서 스크롤이 튄다.
        // 결과는 맨 위에 나오므로 상태가 바뀔 때마다 위로 되돌린다.
        .onChange(of: viewModel.settingsUpdateState) { _, _ in
            proxy.scrollTo("settingsTop", anchor: .top)
        }
        }
    }

    /// 설정 본문의 섹션 제목 — 업데이트 줄과 각 섹션이 같이 움직이도록 한 곳에서만 정의한다.
    private func settingsTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.black.opacity(0.4))
    }

    /// 제목 + (보기, 설명) 줄들. 보기 칸을 고정 폭으로 잡아 설명 왼쪽을 맞춘다.
    private func settingsSection(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            settingsTitle(title)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.0)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)
                        .frame(width: 68, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// 업데이트 확인 줄 — 확인 전에는 버튼, 확인 뒤에는 결과. 새 버전이 있으면 그 자리에서 설치.
    @ViewBuilder
    private var updateRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingsTitle("업데이트")

            // 버튼과 텍스트의 높이가 달라 서로 바뀔 때 아래 목록이 밀린다 — 한 높이로 고정.
            Group {
                switch viewModel.settingsUpdateState {
                case .idle:
                    settingsButton("Check for Update") {
                        viewModel.checkForUpdateFromSettings()
                    }
                case .checking:
                    settingsStatusText("확인 중…")
                case .upToDate(let current):
                    settingsStatusText("최신 버전입니다 (v \(current))")
                case .available(let latest):
                    settingsButton(viewModel.isUpdating
                                   ? (viewModel.updateStatusText.isEmpty ? "Updating…" : viewModel.updateStatusText)
                                   : "Update to v \(latest)") {
                        viewModel.startUpdate()
                    }
                    .disabled(viewModel.isUpdating)
                case .failed:
                    settingsButton("확인하지 못했습니다. 다시 시도") {
                        viewModel.checkForUpdateFromSettings()
                    }
                }
            }
            .frame(height: 30, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsStatusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(textColor)
    }

    /// 기존 업데이트 안내 버튼과 같은 생김새 (좌측 정렬로만 바꿈)
    private func settingsButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 훈/음 영역 (가변 높이, 항상 표시)

    @State private var expandedDefinitions: Set<String> = []

    /// 급수 원기호 반환
    private func gradeSymbol(for char: Character) -> String {
        guard let grade = hanjaGradeMap[char] else { return "●" }
        let symbols = ["●", "❶", "❷", "❸", "❹", "❺", "⑥", "⑦", "⑧"]
        return symbols[min(grade, symbols.count - 1)]
    }

    /// 급수별 색상 반환
    private func gradeColor(for char: Character) -> Color {
        guard let grade = hanjaGradeMap[char] else {
            return textColor
        }
        switch grade {
        case 0: return .black
        case 1: return Color(red: 0.16, green: 0.60, blue: 0.82)
        case 2: return .yellow
        case 3: return Color(red: 0.7, green: 0.85, blue: 0.5)
        default: return textColor
        }
    }

    private var hunEumArea: some View {
        ScrollViewReader { hunProxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    // 상단 한자 리스트와 동일한 순서로 모든 단어의 훈/음 섹션을 쌓는다.
                    if let result = viewModel.searchResult {
                        ForEach(Array(result.words.enumerated()), id: \.offset) { wIdx, word in
                            hunEumWordSection(word: word, wordIndex: wIdx)
                                .id("w_\(wIdx)")
                                .background(hunWordTracker(wordIndex: wIdx))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .coordinateSpace(name: "hunScroll")
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: .infinity)
            .modifier(OverlayScrollerModifier())
            .contentMargins(.top, 12, for: .scrollContent)
            .background(Color(red: 0xBA/255, green: 0xD0/255, blue: 0xE2/255).opacity(0.14))
            // 상단 → 중간: 활성 단어가 (상단 스크롤/키보드로) 바뀌면 그 단어 섹션으로 스크롤.
            // 단, 지금 사용자가 중간을 스크롤 중이면(중간이 유발한 변경) 중간을 건드리지 않는다.
            .onChange(of: viewModel.activeWordIndex) { _, idx in
                guard scrollFocus != .middle else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    hunProxy.scrollTo("w_\(idx)_v_0", anchor: .top)
                }
            }
            // 상단 → 중간(변형 단위): 상단에서 같은 단어의 변형을 훑으면 그 변형으로 스크롤.
            .onChange(of: viewModel.activeVariantIndex) { _, vIdx in
                guard scrollFocus != .middle else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    hunProxy.scrollTo("w_\(viewModel.activeWordIndex)_v_\(vIdx)", anchor: .top)
                }
            }
            // 새 검색: 맨 위로 + 펼침 초기화
            .onChange(of: viewModel.resultToken) { _, _ in
                expandedDefinitions.removeAll()
                hunProxy.scrollTo("w_0", anchor: .top)
            }
            // 입력 상태로 돌아가면 펼침 초기화
            .onChange(of: viewModel.isEditing) { _, editing in
                if editing { expandedDefinitions.removeAll() }
            }
        }
    }

    /// 중간 → 상단: 각 단어 섹션의 상단(minY)을 감지해 뷰포트 상단에 걸린 단어를 활성화.
    /// 수동적 감지라 스크롤 자체는 전혀 제약하지 않는다(끝까지 스크롤 가능).
    private func hunWordTracker(wordIndex: Int) -> some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named("hunScroll")).minY
            Color.clear
                .onChange(of: minY) { _, y in
                    // 사용자가 중간을 스크롤 중일 때만 감지 (상단 follow 스크롤은 무시)
                    guard scrollFocus == .middle else { return }
                    // 아래로 스크롤: 뒤 단어 섹션 상단이 뷰포트 위쪽에 도달 → 활성화
                    if y < 40 && wordIndex > viewModel.activeWordIndex {
                        viewModel.middleDidReachWord(wordIndex)
                    }
                    // 위로 스크롤: 활성 단어 상단이 아래로 밀려나면 → 이전 단어 활성화
                    else if y > 60 && wordIndex == viewModel.activeWordIndex && wordIndex > 0 {
                        viewModel.middleDidReachWord(wordIndex - 1)
                    }
                }
        }
    }

    /// 단어 하나의 훈/음 섹션 (변형 나열)
    private func hunEumWordSection(word: HanjaWord, wordIndex: Int) -> some View {
        let hasMultipleVariants = word.hanjaVariants.count > 1
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(word.hanjaVariants.enumerated()), id: \.offset) { vIdx, variant in
                if vIdx > 0 {
                    Spacer().frame(height: 6)
                }
                // 변형 섹션 — 스크롤 앵커 ID 부여 (단어 인덱스 포함)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(variant.enumerated()), id: \.offset) { cIdx, char in
                        if let charInfo = word.characters.first(where: { $0.character == char }) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(charInfo.eum)
                                    .font(.system(size: 14))
                                    .foregroundColor(textColor)
                                Text(":")
                                    .font(.system(size: 14))
                                    .foregroundColor(textColor)
                                // 급수 원기호 + 훈 + 변형 인디케이터
                                Group {
                                    let gradePrefix: Text = {
                                        return Text(gradeSymbol(for: char) + " ")
                                            .foregroundColor(gradeColor(for: char))
                                    }()
                                    if hasMultipleVariants && cIdx == 0 {
                                        if vIdx == 0 {
                                            (gradePrefix
                                            + Text(charInfo.hun)
                                                .foregroundColor(textColor)
                                            + Text("   ●")
                                                .font(.system(size: 4))
                                                .foregroundColor(textColor)
                                                .baselineOffset(8))
                                        } else {
                                            (gradePrefix
                                            + Text(charInfo.hun)
                                                .foregroundColor(textColor)
                                            + Text(" \(vIdx)")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(textColor)
                                                .baselineOffset(6))
                                        }
                                    } else {
                                        (gradePrefix
                                        + Text(charInfo.hun)
                                            .foregroundColor(textColor))
                                    }
                                }
                                .font(.system(size: 14))
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    // 정의 표시 (2글자 이상 단어만)
                    if word.korean.count >= 2 {
                        definitionView(for: variant, korean: word.korean)
                    }
                }
                // 변형 단위 스크롤 앵커 (단어+변형 인덱스)
                .id("w_\(wordIndex)_v_\(vIdx)")
            }
        }
    }

    /// 단어 정의 표시 뷰 (+/- 토글)
    @ViewBuilder
    private func definitionView(for variant: String, korean: String) -> some View {
        let hanja = String(variant.filter { $0.isHanja })
        if let defs = viewModel.definitions[hanja], !defs.isEmpty {
            let isExpanded = expandedDefinitions.contains(hanja)
            let fullText = defs.enumerated().map { i, d in
                defs.count > 1 ? "\(i + 1). \(d)" : d
            }.joined(separator: "\n")
            // 한 줄에 다 들어가면 +/- 표시 불필요
            let needsTruncation = fullText.count > 25 || defs.count > 1

            Button(action: {
                guard needsTruncation else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedDefinitions.remove(hanja)
                    } else {
                        expandedDefinitions.insert(hanja)
                    }
                }
            }) {
                HStack(alignment: .top, spacing: 4) {
                    // +/-: 음 글자 폭에 맞춰 가운데 정렬
                    if needsTruncation {
                        Text(isExpanded ? "−" : "+")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black.opacity(0.4))
                            .frame(width: 14, alignment: .center)
                            .padding(.top, -1)
                    } else {
                        Spacer().frame(width: 14)
                    }
                    Text(fullText)
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.4))
                        .lineLimit(isExpanded ? nil : 1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 7)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    // MARK: - 입력 텍스트 스타일

    private func buildInputDisplayText() -> Text {
        guard let result = viewModel.searchResult else {
            return Text("")
        }
        let input = result.inputText
        let ranges = result.matchedRanges

        guard !ranges.isEmpty else {
            return Text(input)
                .font(.system(size: 16, weight: .light))
                .foregroundColor(textColor)
        }

        var text = Text("")
        var cursor = input.startIndex

        for range in ranges {
            // 매칭 전 비한자 부분
            if cursor < range.lowerBound {
                text = text + Text(input[cursor..<range.lowerBound])
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(textColor)
            }
            // 한자 단어 부분
            text = text + Text(input[range])
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(textColor)
            cursor = range.upperBound
        }

        // 마지막 비한자 부분
        if cursor < input.endIndex {
            text = text + Text(input[cursor..<input.endIndex])
                .font(.system(size: 16, weight: .light))
                .foregroundColor(textColor)
        }

        return text
    }

    // MARK: - 입력 영역 (고정 높이)

    private var inputArea: some View {
        ZStack(alignment: .trailing) {
            HStack {
                if viewModel.isShowingSettings {
                    // 설정 중에는 입력 비활성 — TextField 자체를 걷어내 포커스가 잡히지 않게 한다
                    Text(UpdateCheck.appVersion.isEmpty ? "" : "v \(UpdateCheck.appVersion)")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(textColor.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if viewModel.isEditing {
                    TextField("", text: $viewModel.inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(textColor)
                        .focused($isInputFocused)
                        .onSubmit {
                            viewModel.performSearch()
                        }
                } else {
                    buildInputDisplayText()
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 52)

            Button(action: {
                if viewModel.isShowingSettings {
                    viewModel.closeSettings()
                    refocusInputIfNeeded()
                } else if viewModel.isEditing {
                    viewModel.performSearch()
                } else {
                    viewModel.resetToEditing()
                    isInputFocused = true
                }
            }) {
                Image(viewModel.isEditing && !viewModel.isShowingSettings ? "vbtn" : "xbtn")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1.5)
                    .shadow(color: .black.opacity(0.10), radius: 5.5, y: 5.5)
                    .shadow(color: .black.opacity(0.06), radius: 7.5, y: 13)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
    }
}

// MARK: - ViewModel

@MainActor
class HanjaViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var searchResult: SearchResult?
    @Published var activeWordIndex: Int = 0
    @Published var activeVariantIndex: Int = 0
    var isPositionTriggered: Bool = false
    var isKeyTriggered: Bool = false

    /// 새 검색마다 갱신 — 중간 스크롤 위치를 맨 위로 되돌리는 트리거
    @Published var resultToken = UUID()

    /// 중간 스크롤 감지로 단어 도달 → 활성 단어 갱신 (상단이 따라 스크롤됨).
    /// 어느 영역을 스크롤 중인지는 hover(scrollFocus)로 중재하므로 별도 타이밍 플래그가 필요 없다.
    func middleDidReachWord(_ index: Int) {
        guard index != activeWordIndex else { return }
        activeWordIndex = index
    }
    @Published var definitions: [String: [String]] = [:] // 한자 → [정의]
    @Published var isLoading: Bool = false
    @Published var isEditing: Bool = true
    @Published var hasSearched: Bool = false
    @Published var isAlwaysOnTop: Bool = false
    @Published var failureMessage: String = ""
    @Published var isEraseMessage: Bool = false

    // MARK: 업데이트 상태
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var isUpdating: Bool = false
    @Published var updateStatusText: String = ""
    /// 검색을 한 번이라도 하면 이번 세션 동안 업데이트 안내를 숨김
    @Published var updateDismissed: Bool = false
    private var updateDMGURL: URL?
    private var didCheckUpdate = false

    /// 설치 후 재실행되었을 때만 true (설치 헬퍼가 -updatedTo 인자로 알림)
    @Published var justUpdated: Bool = false
    @Published var updatedToVersion: String = ""

    // MARK: 설정 모드

    /// 설정 화면 표시 여부. 검색 상태(isEditing/searchResult)는 그대로 두고 위에 겹치는
    /// 모드라서, 빠져나오면 보고 있던 화면이 그대로 돌아온다.
    @Published var isShowingSettings: Bool = false

    /// 설정 안 "Check for Update" 줄의 상태
    enum SettingsUpdateState: Equatable {
        case idle, checking, upToDate(String), available(String), failed
    }
    @Published var settingsUpdateState: SettingsUpdateState = .idle

    func toggleSettings() {
        isShowingSettings.toggle()
        settingsUpdateState = .idle
    }

    func closeSettings() {
        isShowingSettings = false
        settingsUpdateState = .idle
    }

    /// 설정에서 누르는 수동 확인 — 실행 시 1회 제한(didCheckUpdate)과 무관하게 매번 조회한다.
    func checkForUpdateFromSettings() {
        guard settingsUpdateState != .checking, !isUpdating else { return }
        settingsUpdateState = .checking
        Task {
            switch await UpdateCheck.fetchStatus() {
            case .available(let latest, _, let dmgURL):
                latestVersion = latest
                updateDMGURL = dmgURL
                updateAvailable = true
                settingsUpdateState = .available(latest)
            case .upToDate(let current):
                updateAvailable = false
                settingsUpdateState = .upToDate(current)
            case .failed:
                settingsUpdateState = .failed
            }
        }
    }

    private var keyMonitor: Any?
    private var resetAction: (() -> Void)?
    private var audioPlayer: AVAudioPlayer?

    private static let failureMessages = [
        "Our bad!",
        "Oops, we fumbled.",
        "Tried hard. Still broken.",
        "Well, this is awkward.",
        "We hit a wall.",
        "Nope, that failed."
    ]

    private func playSound(named name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {}
    }

    // 한자 검색 히스토리 (한자 글자 → 이전 검색 횟수)
    private static let historyKey = "hanjaSearchHistory"

    /// 이번 검색 시점의 이전 검색 횟수 (표시용 스냅샷)
    private(set) var searchCountSnapshot: [String: Int] = [:]

    private func loadHistory() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: Self.historyKey) as? [String: Int] ?? [:]
    }

    private func saveHistory(_ history: [String: Int]) {
        UserDefaults.standard.set(history, forKey: Self.historyKey)
    }

    func recordSearch(words: [HanjaWord]) {
        var history = loadHistory()
        searchCountSnapshot = [:]
        for word in words {
            for variant in word.hanjaVariants {
                for char in variant where char.isHanja {
                    let key = String(char)
                    if searchCountSnapshot[key] == nil {
                        searchCountSnapshot[key] = history[key] ?? 0
                    }
                    history[key, default: 0] += 1
                }
            }
        }
        saveHistory(history)
        SearchHistoryStore.append(words: words)
    }

    func previousSearchCount(for char: Character) -> Int {
        searchCountSnapshot[String(char)] ?? 0
    }

    var activeWord: HanjaWord? {
        guard let result = searchResult,
              activeWordIndex >= 0,
              activeWordIndex < result.words.count else {
            return nil
        }
        return result.words[activeWordIndex]
    }

    func setupKeyMonitor(resetAndFocus: @escaping () -> Void) {
        self.resetAction = resetAndFocus
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 설정 중에는 방향키·엔터가 뒤에 가려진 검색 결과를 건드리지 않게 흘려보낸다
            guard let self = self, !self.isEditing, !self.isShowingSettings else { return event }

            switch event.keyCode {
            case 123: // 왼쪽
                if self.activeWordIndex > 0 {
                    self.isKeyTriggered = true
                    self.activeWordIndex -= 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.isKeyTriggered = false
                    }
                }
                return nil
            case 124: // 오른쪽
                if let result = self.searchResult,
                   self.activeWordIndex < result.words.count - 1 {
                    self.isKeyTriggered = true
                    self.activeWordIndex += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.isKeyTriggered = false
                    }
                }
                return nil
            case 36: // 엔터
                self.resetAction?()
                return nil
            default:
                return event
            }
        }
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - 자동 업데이트

    /// 앱 실행 시 1회: GitHub 최신 릴리스를 확인해 새 버전이 있으면 안내 노출
    /// 설치 헬퍼가 `open --args -updatedTo <버전>`으로 재실행하면 그 버전을 읽어 "Updated" 표시.
    /// 인자 도메인 값이라 다음 일반 실행 때 자동으로 사라짐.
    func checkPostUpdate() {
        if let version = UserDefaults.standard.string(forKey: "updatedTo"), !version.isEmpty {
            updatedToVersion = version
            justUpdated = true
        }
    }

    func checkForUpdate() {
        guard !didCheckUpdate else { return }
        didCheckUpdate = true
        Task {
            if case .available(let latest, _, let dmgURL) = await UpdateCheck.fetchStatus() {
                self.latestVersion = latest
                self.updateDMGURL = dmgURL
                self.updateAvailable = true
            }
        }
    }

    /// Update 버튼: dmg 다운로드 → 설치 → 재실행 (dmg 자산이 없으면 릴리스 페이지로)
    func startUpdate() {
        guard !isUpdating else { return }
        guard let url = updateDMGURL else {
            UpdateCheck.openReleasesPage()
            return
        }
        isUpdating = true
        UpdateCheck.downloadAndInstall(
            url,
            version: latestVersion,
            onStatus: { [weak self] status in self?.updateStatusText = status },
            onFailure: { [weak self] in
                self?.isUpdating = false
                self?.updateStatusText = ""
                UpdateCheck.openReleasesPage()
            }
        )
    }

    func performSearch() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        updateDismissed = true
        isEditing = false
        hasSearched = true
        resultToken = UUID()   // 새 검색 → 중간 스크롤 맨 위로

        let result = HanjaService.shared.search(text: query)
        searchResult = result
        activeWordIndex = 0
        activeVariantIndex = 0
        if result.words.isEmpty {
            failureMessage = Self.failureMessages.randomElement() ?? "Nope, not here."
            searchResult = nil
            definitions = [:]
            playSound(named: "fail")
        } else {
            recordSearch(words: result.words)
            playSound(named: "succeed")
            // 정의 비동기 로딩
            fetchDefinitionsForResult(result)
        }
    }

    func resetToEditing() {
        inputText = ""
        searchResult = nil
        definitions = [:]
        isEditing = true
        hasSearched = false
        activeWordIndex = 0
        activeVariantIndex = 0
        isEraseMessage = false
    }

    /// 검색 결과의 모든 단어에 대해 정의를 비동기로 가져옴
    private func fetchDefinitionsForResult(_ result: SearchResult) {
        definitions = [:]
        for word in result.words {
            guard word.korean.count >= 2 else { continue }
            Task {
                let defs = await DefinitionService.shared.fetchDefinitions(
                    korean: word.korean,
                    hanjaVariants: word.hanjaVariants
                )
                if !defs.isEmpty {
                    for (hanja, senses) in defs {
                        self.definitions[hanja] = senses
                    }
                }
            }
        }
    }

    func showEraseConfirmation() {
        searchResult = nil
        isEditing = false
        hasSearched = true
        isEraseMessage = true
        failureMessage = "Data Erased"
    }
}

enum SearchHistoryStore {
    private static let fileName = "search_history.xls"
    private static let legacyCSVFileName = "search_history.csv"
    private static let tableClosingTag = "</table></body></html>"

    private static var historyFolderURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("01haka", isDirectory: true)
            .appendingPathComponent("SearchHistory", isDirectory: true)
    }

    private static var historyFileURL: URL? {
        historyFolderURL?.appendingPathComponent(fileName)
    }

    private static var legacyCSVFileURL: URL? {
        historyFolderURL?.appendingPathComponent(legacyCSVFileName)
    }

    static func append(words: [HanjaWord]) {
        guard let folderURL = historyFolderURL,
              let fileURL = historyFileURL else { return }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
            if !fileExists {
                try initialHTML().write(to: fileURL, atomically: true, encoding: .utf8)
            }

            let rowsHTML = words.map(historyRowsHTML(for:)).joined()
            guard !rowsHTML.isEmpty else { return }

            var html = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? initialHTML()
            if let range = html.range(of: tableClosingTag, options: .backwards) {
                html.replaceSubrange(range, with: rowsHTML + tableClosingTag)
            } else {
                html += rowsHTML + tableClosingTag
            }

            try html.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to append search history: \(error)")
        }
    }

    static func openHistoryFolder() {
        guard let folderURL = historyFolderURL else { return }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folderURL)
        } catch {
            print("Failed to open search history folder: \(error)")
        }
    }

    static func deleteHistoryFile() {
        for url in [historyFileURL, legacyCSVFileURL].compactMap({ $0 }) where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func historyRowsHTML(for word: HanjaWord) -> String {
        var characterInfo: [Character: HanjaChar] = [:]
        for char in word.characters {
            characterInfo[char.character] = char
        }

        let rowCount = max(word.hanjaVariants.count, 1)
        return word.hanjaVariants.enumerated().map { index, variant in
            let hunEum = variant.compactMap { char -> String? in
                guard let info = characterInfo[char] else { return nil }
                return "\(info.hun) \(info.eum)(\(gradeText(for: char)))"
            }
            .joined(separator: ", ")

            let koreanCell = index == 0 ? "<td rowspan=\"\(rowCount)\">\(htmlEscape(word.korean))</td>" : ""
            return "<tr>\(koreanCell)<td>\(htmlEscape(variant))</td><td>\(htmlEscape(hunEum))</td></tr>\n"
        }
        .joined()
    }

    private static func gradeText(for char: Character) -> String {
        guard let grade = hanjaGradeMap[char] else { return "미상" }
        return grade == 0 ? "특" : "\(grade)"
    }

    private static func initialHTML() -> String {
        """
        <html><head><meta charset="UTF-8"><style>
        table { border-collapse: collapse; font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 14px; }
        th, td { border: 1px solid #d9d9d9; padding: 8px 10px; vertical-align: middle; }
        th { font-weight: 600; text-align: left; }
        </style></head><body><table><tr><th>한글</th><th>한자</th><th>훈,음</th></tr>
        \(tableClosingTag)
        """
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
