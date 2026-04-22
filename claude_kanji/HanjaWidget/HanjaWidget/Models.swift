import Foundation

/// 개별 한자 글자의 훈과 음
struct HanjaChar: Identifiable {
    let id = UUID()
    let character: Character  // 한자 글자 (e.g., 萬)
    let hun: String           // 훈 (e.g., 일만)
    let eum: String           // 음 (e.g., 만)
}

/// 한자 단어 (여러 글자로 구성, 동음이의어 포함)
struct HanjaWord: Identifiable {
    let id = UUID()
    let korean: String        // 한글 (e.g., 만우절)
    let hanjaVariants: [String] // 동음이의어 한자들 (e.g., ["連敗", "連覇"])
    var characters: [HanjaChar] // 모든 variant의 고유 글자 훈/음

    var hanja: String {
        hanjaVariants.joined(separator: ", ")
    }
}

/// 검색 결과 전체
struct SearchResult {
    let inputText: String     // 원래 입력 텍스트
    var words: [HanjaWord]    // 찾아진 한자 단어들
    var matchedRanges: [Range<String.Index>] = [] // 입력 텍스트 중 한자 단어로 매칭된 범위들
}
