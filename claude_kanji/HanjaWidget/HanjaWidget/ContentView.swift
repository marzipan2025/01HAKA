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

// MARK: - Legacy background (pre-macOS 26 fallback)

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var alpha: CGFloat = 1.0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
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
    var useGlass: Bool

    @ViewBuilder
    private func legacyBackground(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectBackground(material: .fullScreenUI, blendingMode: .behindWindow, alpha: 1.0)
                    Color(red: 0xE0/255, green: 0xE0/255, blue: 0xF0/255).opacity(0.48)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26))
            )
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(
                RoundedRectangle(cornerRadius: 26)
                    .stroke(Color(red: 0xC7/255, green: 0xCB/255, blue: 0xD9/255).opacity(0.10), lineWidth: 1)
            )
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), useGlass {
            content
                .background(
                    Color(red: 0x7B/255, green: 0x86/255, blue: 0x98/255).opacity(0.40)
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                )
                .glassEffect(.clear, in: .rect(cornerRadius: 26))
        } else {
            legacyBackground(content)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = HanjaViewModel()
    @FocusState private var isInputFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            // 상단: 한자 표시 (고정 높이)
            hanjaDisplayArea
                .frame(maxWidth: .infinity)
                .frame(height: 90)

            // 중단: 훈/음 표시 (가변 높이)
            hunEumArea
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

            // 하단: 입력 영역 (고정 높이)
            inputArea
                .frame(height: 50)
        }
        .padding(0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(GlassBackgroundModifier(useGlass: viewModel.useGlassEffect))
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
                Button(action: {
                    viewModel.isAlwaysOnTop.toggle()
                    setWindowLevel(viewModel.isAlwaysOnTop ? .floating : .normal)
                }) {
                    Image("onTop")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                        .opacity(viewModel.isAlwaysOnTop ? 1.0 : 0.5)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
        .frame(minWidth: 270, minHeight: 240)
        .onReceive(NotificationCenter.default.publisher(for: .hanjaEraseRecords)) { _ in
            UserDefaults.standard.removeObject(forKey: "hanjaSearchHistory")
            viewModel.showEraseConfirmation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hanjaToggleAlwaysOnTop)) { _ in
            viewModel.isAlwaysOnTop.toggle()
            setWindowLevel(viewModel.isAlwaysOnTop ? .floating : .normal)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hanjaToggleGlassEffect)) { _ in
            viewModel.useGlassEffect.toggle()
            UserDefaults.standard.set(viewModel.useGlassEffect, forKey: "useGlassEffect")
        }
        .onAppear {
            isInputFocused = true
            viewModel.setupKeyMonitor { [weak viewModel] in
                viewModel?.resetToEditing()
                DispatchQueue.main.async {
                    self.isInputFocused = true
                }
            }
        }
    }

    private func setWindowLevel(_ level: NSWindow.Level) {
        NSApplication.shared.windows.first?.level = level
    }

    // MARK: - 한자 표시 영역 (고정 높이)

    private var hanjaDisplayArea: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = viewModel.searchResult, !result.words.isEmpty {
                hanjaTextView(result: result)
            } else if viewModel.hasSearched {
                Text(viewModel.failureMessage)
                    .foregroundColor(viewModel.isEraseMessage ? .black.opacity(0.3) : .white.opacity(0.3))
                    .font(.system(size: 56, weight: .ultraLight))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 16)
                    .padding(.top, 12)
            } else {
                Text("漢字")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 16)
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
                if !isActive { return .white.opacity(0.3) }
                if tier >= 5 { return .black }
                else if tier >= 4 { return Color(red: 1, green: 1, blue: 0) }
                else if tier >= 3 { return Color(red: 1, green: 0xFC/255, blue: 0xCB/255) }
                return .white
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
                    .foregroundColor(.white.opacity(0.8))
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
                    .foregroundColor(isActive ? .white.opacity(0.5) : .white.opacity(0.15))
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
                        .foregroundColor(.white.opacity(0.5))
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
                                    if x >= 20 && x <= 40 {
                                        viewModel.activeVariantIndex = vIdx
                                    }
                                }
                        }
                    )
            }
        }
        .padding(.leading, 16)
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
                                .padding(.leading, 16)
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
                    // 키보드 방향키로 변경 중에는 위치 감지 무시
                    guard !viewModel.isKeyTriggered else { return }
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
            return .white.opacity(0.2)
        }
        switch grade {
        case 0: return .black
        case 1: return Color(red: 0.16, green: 0.60, blue: 0.82)
        case 2: return .yellow
        case 3: return Color(red: 0.7, green: 0.85, blue: 0.5)
        default: return .white.opacity(0.6)
        }
    }

    private var hunEumArea: some View {
        ScrollViewReader { hunProxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    if let activeWord = viewModel.activeWord {
                        let hasMultipleVariants = activeWord.hanjaVariants.count > 1
                        ForEach(Array(activeWord.hanjaVariants.enumerated()), id: \.offset) { vIdx, variant in
                            if vIdx > 0 {
                                Spacer().frame(height: 6)
                            }
                            // 변형 섹션 — 스크롤 앵커 ID 부여
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(variant.enumerated()), id: \.offset) { cIdx, char in
                                    if let charInfo = activeWord.characters.first(where: { $0.character == char }) {
                                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                                            Text(charInfo.eum)
                                                .font(.system(size: 14))
                                                .foregroundColor(.white.opacity(0.85))
                                            Text(":")
                                                .font(.system(size: 14))
                                                .foregroundColor(.white.opacity(0.85))
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
                                                            .foregroundColor(.white.opacity(0.85))
                                                        + Text("   ●")
                                                            .font(.system(size: 4))
                                                            .foregroundColor(.white)
                                                            .baselineOffset(8))
                                                    } else {
                                                        (gradePrefix
                                                        + Text(charInfo.hun)
                                                            .foregroundColor(.white.opacity(0.85))
                                                        + Text(" \(vIdx)")
                                                            .font(.system(size: 9, weight: .medium))
                                                            .foregroundColor(.white.opacity(0.8))
                                                            .baselineOffset(6))
                                                    }
                                                } else {
                                                    (gradePrefix
                                                    + Text(charInfo.hun)
                                                        .foregroundColor(.white.opacity(0.85)))
                                                }
                                            }
                                            .font(.system(size: 14))
                                            .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                // 정의 표시 (2글자 이상 단어만)
                                if activeWord.korean.count >= 2 {
                                    definitionView(for: variant, korean: activeWord.korean)
                                }
                            }
                            .id("v_\(vIdx)")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: .infinity)
            .modifier(OverlayScrollerModifier())
            .contentMargins(.top, 12, for: .scrollContent)
            .background(Color(red: 0xE4/255, green: 0xE8/255, blue: 0xFE/255).opacity(0.14))
            // 수평 스크롤로 변형이 x=20~40 진입 시 훈/음 스크롤
            .onChange(of: viewModel.activeVariantIndex) { _, newVIdx in
                withAnimation(.easeInOut(duration: 0.2)) {
                    hunProxy.scrollTo("v_\(newVIdx)", anchor: .top)
                }
            }
            // 단어 변경 시 항상 맨 위로, 펼침 상태 초기화
            .onChange(of: viewModel.activeWordIndex) { _, _ in
                expandedDefinitions.removeAll()
                withAnimation(.easeInOut(duration: 0.2)) {
                    hunProxy.scrollTo("v_0", anchor: .top)
                }
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
                .foregroundColor(.white.opacity(0.5))
        }

        var text = Text("")
        var cursor = input.startIndex

        for range in ranges {
            // 매칭 전 비한자 부분
            if cursor < range.lowerBound {
                text = text + Text(input[cursor..<range.lowerBound])
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(.white.opacity(0.5))
            }
            // 한자 단어 부분
            text = text + Text(input[range])
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
            cursor = range.upperBound
        }

        // 마지막 비한자 부분
        if cursor < input.endIndex {
            text = text + Text(input[cursor..<input.endIndex])
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.white.opacity(0.5))
        }

        return text
    }

    // MARK: - 입력 영역 (고정 높이)

    private var inputArea: some View {
        ZStack(alignment: .trailing) {
            HStack {
                if viewModel.isEditing {
                    TextField("", text: $viewModel.inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
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
                if viewModel.isEditing {
                    viewModel.performSearch()
                } else {
                    viewModel.resetToEditing()
                    isInputFocused = true
                }
            }) {
                Image(viewModel.isEditing ? "vbtn" : "xbtn")
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
    @Published var definitions: [String: [String]] = [:] // 한자 → [정의]
    @Published var isLoading: Bool = false
    @Published var isEditing: Bool = true
    @Published var hasSearched: Bool = false
    @Published var isAlwaysOnTop: Bool = false
    @Published var useGlassEffect: Bool = UserDefaults.standard.object(forKey: "useGlassEffect") as? Bool ?? true
    @Published var failureMessage: String = ""
    @Published var isEraseMessage: Bool = false

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
            guard let self = self, !self.isEditing else { return event }

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

    func performSearch() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isEditing = false
        hasSearched = true

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
