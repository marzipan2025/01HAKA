import Foundation

/// 앱 안에 넣어 둔 뜻풀이. 낱말 하나에 한자 표기 하나씩 짝지어 들고 있다.
///
/// 그동안 뜻은 한국어기초사전 API 로 그때그때 물어 왔는데, 기초사전이라 흔한 두 글자
/// 낱말만 걸리고 사자성어는 아예 없었다. 국립국어원 우리말샘이 CC BY-SA 2.0 KR 로
/// 풀려 있어 그쪽에서 미리 길어 왔다 — 138,925개다. 이제 그물에 걸리지 않는 것만
/// 물어보면 된다.
///
/// 파일은 `한글 \t 한자 \t 뜻` 한 줄씩이고, 12.5MB 다. 앱이 뜨는 길을 막지 않도록
/// 딴 줄에서 읽어 들이고, 다 읽기 전에 물어 오면 없다고 답한다 — 그때는 예전처럼
/// 물어보러 나간다.
final class MeaningStore {
    static let shared = MeaningStore()

    private var table: [String: String] = [:]
    private var ready = false
    private let lock = NSLock()

    private init() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.load()
        }
    }

    /// 그 표기의 뜻. 아직 읽는 중이거나 없으면 nil.
    func meaning(korean: String, hanja: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return ready ? table["\(korean)\t\(hanja)"] : nil
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "meanings", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        var out: [String: String] = [:]
        out.reserveCapacity(140_000)
        text.enumerateLines { line, _ in
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, !parts[2].isEmpty else { return }
            out["\(parts[0])\t\(parts[1])"] = String(parts[2])
        }
        lock.lock()
        table = out
        ready = true
        lock.unlock()
    }
}
