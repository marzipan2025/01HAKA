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

    /// 사전에 존재하는 모든 단어 길이 (최적화용)
    private var maxWordLength: Int = 6

    private init() {
        loadDictionary()
    }

    // MARK: - Public API

    func search(text: String) -> SearchResult {
        // (훈 음) 패턴 감지
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            let parts = inner.components(separatedBy: " ").filter { !$0.isEmpty }
            if parts.count >= 2 {
                // 공백 있음 → (훈 음) 검색
                let eum = parts.last!
                let hun = parts.dropLast().joined(separator: " ")
                return searchByHunEum(hun: hun, eum: eum, inputText: trimmed)
            } else if parts.count == 1 {
                // 공백 없음 → 훈 substring 검색
                return searchByHun(hun: parts[0], inputText: trimmed)
            }
        }

        // 단일 한글 음절 → 해당 음가의 한자들 조회
        if trimmed.count == 1, let char = trimmed.first, char.isHangul {
            return searchByEum(eum: trimmed, inputText: trimmed)
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
        let characters = candidates.compactMap { candidate -> HanjaChar? in
            guard let info = charToHunEum[candidate.char] else { return nil }
            return HanjaChar(character: candidate.char, hun: info.hun, eum: info.eum)
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
                    if charToHunEum[hanjaChar] == nil {
                        let (hun, eum) = parseHunEum(description: description, eum: korean)
                        charToHunEum[hanjaChar] = (hun: hun, eum: eum)
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
                    // 모든 variant의 고유 한자 글자에 대해 훈/음 조회
                    var allCharsSet: Set<Character> = []
                    var allCharsOrdered: [Character] = []
                    for v in variants {
                        for c in v where c.isHanja && !allCharsSet.contains(c) {
                            allCharsSet.insert(c)
                            allCharsOrdered.append(c)
                        }
                    }
                    let characters = allCharsOrdered.compactMap { lookupCharacter($0) }

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
