import Foundation

/// libhangul hanja.txt 기반 오프라인 한자 검색 서비스
class HanjaService {
    static let shared = HanjaService()

    /// 한글 단어 → 한자 variant 목록 (e.g., "복수" → ["復讐", "腹水", ...])
    private var wordToHanja: [String: [String]] = [:]

    /// 한자 글자 → (hun, eum) (e.g., 恐 → ("두려울", "공"))
    private var charToHunEum: [Character: (hun: String, eum: String)] = [:]

    /// 음(eum) → [(한자, 원본 설명)] 역방향 조회 (e.g., "모" → [(母, "어미 모"), (毛, "털 모"), ...])
    private var eumToChars: [String: [(char: Character, rawDescription: String)]] = [:]

    /// (음 + 한자) → 그 음으로 읽을 때의 훈. 數 는 '수' 로 헤아릴·몇, '삭' 으로 자주다.
    /// 글자마다 훈음을 하나만 들고 있으면 數學 이 '삭학' 으로 선다.
    private var hunByReading: [String: String] = [:]

    /// (한글, 한자) 짝을 사전에 실린 차례대로. 한자로 되짚을 때 이 차례가 곧 순번이다.
    private var entries: [(ko: String, hanja: String)] = []

    /// 한자 글자 → 그 글자가 든 [entries] 자리. 첫 한자 검색 때 한 번만 짓는다.
    private var hanjaIndex: [Character: [Int]] = [:]

    /// 한자로 되짚을 때 세우는 낱말 수의 한도. 26HAKC 와 같은 값이다.
    private let hanjaMax = 120

    /// 사전에 존재하는 모든 단어 길이 (최적화용)
    private var maxWordLength: Int = 6

    private init() {
        loadDictionary()
    }

    // MARK: - Public API

    func search(text: String) -> SearchResult {
        // 훈·음으로 글자를 집는 입력. 여는 표시 하나면 된다 — / 든 ( 든.
        //
        // 닫는 괄호까지 기다리게 하면 그것을 칠 때까지 화면이 죽는다. 이 검색은
        // 글자마다 도는데 `(어미 모` 는 괄호 분기에 걸리지 못하고 평범한 한글
        // 문장으로 떨어지기 때문이다. 닫는 괄호가 가르는 것도 없다 — 훈만인지
        // 훈과 음인지는 안쪽의 띄어쓰기가 정한다.
        //
        // 26HAKC 와 같은 문법이다. 전각 괄호도 받아 준다.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
        var body: Substring?
        if trimmed.hasPrefix("/") {
            body = trimmed.dropFirst()
        } else if trimmed.hasPrefix("(") {
            var b = trimmed.dropFirst()
            if b.hasSuffix(")") { b = b.dropLast() }     // 닫아 두었으면 그것도 받는다
            body = b
        }
        if let body {
            let inner = body.trimmingCharacters(in: .whitespaces)
            let parts = inner.components(separatedBy: " ").filter { !$0.isEmpty }
            if parts.count >= 2 {
                // 띄어쓰기 있음 → 훈 음 검색
                let eum = parts.last!
                let hun = parts.dropLast().joined(separator: " ")
                return searchByHunEum(hun: hun, eum: eum, inputText: trimmed)
            } else if parts.count == 1 {
                // 띄어쓰기 없음 → 훈 substring 검색
                return searchByHun(hun: parts[0], inputText: trimmed)
            }
        }

        // 단일 한글 음절 → 해당 음가의 한자들 조회
        if trimmed.count == 1, let char = trimmed.first, char.isHangul {
            return searchByEum(eum: trimmed, inputText: trimmed)
        }

        // 한자를 그대로 넣으면 그 글자가 든 낱말을 모아 준다
        if trimmed.contains(where: { $0.isHanja }) {
            return searchByHanja(trimmed)
        }

        let (words, ranges) = findHanjaWords(in: text)
        return SearchResult(inputText: text, words: words, matchedRanges: ranges)
    }

    // MARK: - Eum Lookup (단일 음절)

    private func searchByEum(eum: String, inputText: String) -> SearchResult {
        guard let candidates = eumToChars[eum] else {
            return SearchResult(inputText: inputText, words: [])
        }

        let variants = candidates.map { String($0.char) }
        // 음을 알고 찾았으니 훈도 그 음의 것으로
        let characters = candidates.compactMap { candidate -> HanjaChar? in
            let hun = hunByReading["\(eum)\(candidate.char)"] ?? charToHunEum[candidate.char]?.hun
            guard let hun else { return nil }
            return HanjaChar(character: candidate.char, hun: hun, eum: eum)
        }

        let word = HanjaWord(
            korean: inputText,
            hanjaVariants: variants,
            characters: characters
        )
        return SearchResult(inputText: inputText, words: [word])
    }

    // MARK: - Hun Substring Search (훈 검색)

    private func searchByHun(hun: String, inputText: String) -> SearchResult {
        var matches: [(char: Character, hun: String, eum: String)] = []

        for (eum, candidates) in eumToChars {
            for candidate in candidates {
                guard let info = charToHunEum[candidate.char] else { continue }
                if info.hun.contains(hun) {
                    matches.append((candidate.char, info.hun, info.eum))
                }
            }
        }

        guard !matches.isEmpty else {
            return SearchResult(inputText: inputText, words: [])
        }

        let variants = matches.map { String($0.char) }
        let characters = matches.map { HanjaChar(character: $0.char, hun: $0.hun, eum: $0.eum) }

        let word = HanjaWord(
            korean: inputText,
            hanjaVariants: variants,
            characters: characters
        )
        return SearchResult(inputText: inputText, words: [word])
    }

    // MARK: - Hun/Eum Reverse Lookup

    private func searchByHunEum(hun: String, eum: String, inputText: String) -> SearchResult {
        guard let candidates = eumToChars[eum] else {
            return SearchResult(inputText: inputText, words: [])
        }

        // 훈 매칭: 정확 매칭 > 포함 매칭 순으로 정렬
        var exactMatches: [(Character, String)] = []
        var partialMatches: [(Character, String)] = []

        for candidate in candidates {
            let desc = candidate.rawDescription
            // 설명에서 훈 부분들 추출 (e.g., "어미 모, 근본 모" → ["어미", "근본"])
            let hunParts = desc.components(separatedBy: ", ").compactMap { part -> String? in
                let words = part.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
                return words.count > 1 ? words.dropLast().joined(separator: " ") : nil
            }

            if hunParts.contains(hun) {
                // 정확 매칭
                exactMatches.append((candidate.char, desc))
            } else if hunParts.contains(where: { $0.contains(hun) || hun.contains($0) }) {
                // 부분 매칭 (어머니↔어미)
                partialMatches.append((candidate.char, desc))
            }
        }

        let allMatches = exactMatches + partialMatches

        if allMatches.isEmpty {
            return SearchResult(inputText: inputText, words: [])
        }

        let variants = allMatches.map { String($0.0) }
        let characters = allMatches.compactMap { match -> HanjaChar? in
            guard let info = charToHunEum[match.0] else { return nil }
            return HanjaChar(character: match.0, hun: info.hun, eum: info.eum)
        }

        let word = HanjaWord(
            korean: inputText,
            hanjaVariants: variants,
            characters: characters
        )
        return SearchResult(inputText: inputText, words: [word])
    }

    // MARK: - Hanja Lookup (한자를 그대로 넣었을 때)

    /// 낱말 하나에 딸린 글자들의 訓音.
    ///
    /// 음은 낱말이 알려 준다. 낱말과 한자의 글자 수가 맞으면 자리끼리 짝을 지어
    /// 그 자리의 한글을 음으로 쓴다 — 數學 의 數 는 '삭' 이 아니라 '수' 이고,
    /// 龜裂 의 龜 는 '구' 가 아니라 '균' 이다.
    private func characters(of korean: String, variants: [String]) -> [HanjaChar] {
        let syllables = Array(korean)
        var seen: Set<Character> = []
        var characters: [HanjaChar] = []
        for v in variants {
            let letters = Array(v)
            let paired = letters.count == syllables.count
            for (i, c) in letters.enumerated() where c.isHanja && !seen.contains(c) {
                seen.insert(c)
                if paired {
                    let eum = String(syllables[i])
                    let hun = hunByReading["\(eum)\(c)"] ?? charToHunEum[c]?.hun ?? ""
                    characters.append(HanjaChar(character: c, hun: hun, eum: eum))
                } else if let known = lookupCharacter(c) {
                    characters.append(known)
                }
            }
        }
        return characters
    }

    /// 한자 → 그 글자가 든 낱말 자리. 30만 줄을 한 번 더 훑는 일이라 앱을 띄우는
    /// 길목에서 하지 않고, 한자를 처음 넣었을 때 짓는다.
    private func buildHanjaIndexIfNeeded() {
        guard hanjaIndex.isEmpty else { return }
        for (i, e) in entries.enumerated() {
            var seen: Set<Character> = []
            for c in e.hanja where c.isHanja && !seen.contains(c) {
                seen.insert(c)
                hanjaIndex[c, default: []].append(i)
            }
        }
    }

    /// 한자로 되짚기 — 그 한자가 든 낱말을 모아 준다. 26HAKC 의 규칙 그대로다.
    ///
    /// 한 글자만 넣으면 두 글자 낱말로 좁힌다. 한 글자가 든 낱말은 수천 개여서
    /// 다 세우면 무엇을 보러 왔는지 알 수 없어진다. 여러 글자를 넣으면 그 이음이
    /// 든 낱말을 찾는다. 걸리는 것이 없으면 글자마다 訓音만 돌려준다.
    private func searchByHanja(_ text: String) -> SearchResult {
        let han = String(text.filter { $0.isHanja })
        guard let first = han.first else {
            return SearchResult(inputText: text, words: [])
        }
        buildHanjaIndexIfNeeded()

        let single = han.count == 1
        var hits: [(idx: Int, len: Int)] = []
        for i in hanjaIndex[first] ?? [] {
            let e = entries[i]
            guard e.hanja.contains(han) else { continue }
            if single {
                guard e.hanja.count == 2,
                      !e.hanja.contains(where: { $0.isHangul }) else { continue }
            }
            hits.append((i, e.hanja.count))
        }
        // 짧은 낱말이 먼저, 같은 길이면 사전에 실린 차례대로
        hits.sort { $0.len != $1.len ? $0.len < $1.len : $0.idx < $1.idx }

        var words: [HanjaWord] = hits.prefix(hanjaMax).map { hit in
            let e = entries[hit.idx]
            return HanjaWord(korean: e.ko,
                             hanjaVariants: [e.hanja],
                             characters: characters(of: e.ko, variants: [e.hanja]))
        }
        if words.isEmpty {
            // 낱말이 걸리지 않아도 글자는 읽어 준다
            words = [HanjaWord(korean: han,
                               hanjaVariants: [han],
                               characters: han.compactMap { lookupCharacter($0) })]
        }
        return SearchResult(inputText: text, words: words)
    }

    // MARK: - Dictionary Loading

    private func loadDictionary() {
        guard let url = Bundle.main.url(forResource: "hanja", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        for line in content.components(separatedBy: .newlines) {
            guard !line.hasPrefix("#"), !line.isEmpty else { continue }

            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }

            let korean = parts[0]
            let hanja = parts[1]

            guard !korean.isEmpty, !hanja.isEmpty else { continue }

            // 단일 음절 → 한자 글자의 훈/음 데이터
            if korean.count == 1 && hanja.count == 1 {
                let description = parts.count >= 3 ? parts[2] : ""
                if !description.isEmpty {
                    let hanjaChar = hanja.first!
                    let (hun, eum) = parseHunEum(description: description, eum: korean)
                    if charToHunEum[hanjaChar] == nil {
                        charToHunEum[hanjaChar] = (hun: hun, eum: eum)
                    }
                    // 음마다 따로 적어 둔다 — 낱말이 음을 알려 주면 그 음의 훈을 쓴다
                    let reading = "\(korean)\(hanjaChar)"
                    if hunByReading[reading] == nil {
                        hunByReading[reading] = hun
                    }
                    // 역방향 조회용
                    if eumToChars[korean] == nil {
                        eumToChars[korean] = []
                    }
                    eumToChars[korean]!.append((char: hanjaChar, rawDescription: description))
                }
            }

            // 단어 → 한자 매핑 (한글 부분만 추출하여 비교)
            let koreanOnly = String(korean.filter { $0.isHangul })
            let hanjaOnly = String(hanja.filter { $0.isHanja || $0.isHangul })
            guard !koreanOnly.isEmpty, !hanjaOnly.isEmpty else { continue }
            guard koreanOnly.count >= 2 else { continue } // 2글자 이상 단어만

            if wordToHanja[koreanOnly] == nil {
                wordToHanja[koreanOnly] = []
            }
            if !wordToHanja[koreanOnly]!.contains(hanjaOnly) {
                wordToHanja[koreanOnly]!.append(hanjaOnly)
                entries.append((ko: koreanOnly, hanja: hanjaOnly))
            }
        }

        maxWordLength = min(wordToHanja.keys.map { $0.count }.max() ?? 6, 10)
    }

    /// "두려울 공" → hun: "두려울", eum: "공"
    /// "옷 복, 입을 복" → hun: "옷, 입을", eum: "복"
    private func parseHunEum(description: String, eum: String) -> (String, String) {
        let parts = description.components(separatedBy: ", ")
        let hunParts = parts.map { part -> String in
            let words = part.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            if words.count > 1 {
                return words.dropLast().joined(separator: " ")
            }
            return words.first ?? ""
        }
        let hun = hunParts.joined(separator: ", ")
        return (hun, eum)
    }

    // MARK: - Word Matching

    private func findHanjaWords(in text: String) -> ([HanjaWord], [Range<String.Index>]) {
        let chars = Array(text)
        var foundWords: [HanjaWord] = []
        var matchedRanges: [Range<String.Index>] = []
        var pos = 0

        while pos < chars.count {
            var matched = false

            let maxLen = min(chars.count - pos, maxWordLength)
            for length in stride(from: maxLen, through: 2, by: -1) {
                let substring = String(chars[pos..<(pos + length)])

                guard substring.allSatisfy({ $0.isHangul }) else { continue }

                if let variants = wordToHanja[substring] {
                    let characters = self.characters(of: substring, variants: variants)

                    let word = HanjaWord(
                        korean: substring,
                        hanjaVariants: variants,
                        characters: characters
                    )
                    foundWords.append(word)

                    // 매칭 범위 기록
                    let startIdx = text.index(text.startIndex, offsetBy: pos)
                    let endIdx = text.index(startIdx, offsetBy: length)
                    matchedRanges.append(startIdx..<endIdx)

                    pos += length
                    matched = true
                    break
                }
            }

            if !matched {
                pos += 1
            }
        }

        return (foundWords, matchedRanges)
    }

    private func lookupCharacter(_ char: Character) -> HanjaChar? {
        guard let info = charToHunEum[char] else { return nil }
        return HanjaChar(character: char, hun: info.hun, eum: info.eum)
    }
}

// MARK: - Character Extensions

extension Character {
    var isHanja: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value) ||
               (0x3400...0x4DBF).contains(value) ||
               (0x20000...0x2A6DF).contains(value) ||
               (0xF900...0xFAFF).contains(value)
    }

    var isHangul: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let value = scalar.value
        return (0xAC00...0xD7AF).contains(value) ||
               (0x1100...0x11FF).contains(value) ||
               (0x3130...0x318F).contains(value)
    }
}
