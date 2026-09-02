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
    /// 한자로 찾아 한 벌로 줄지어 선 결과. 낱말 하나하나가 저마다 서지만 글 속에서
    /// 따로 집어낸 낱말이 아니라 한 물음에 딸린 한 벌이므로, 번호를 붙여 세운다.
    var series: Bool = false
}
