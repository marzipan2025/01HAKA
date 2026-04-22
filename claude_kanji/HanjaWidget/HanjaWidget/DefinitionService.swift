import Foundation

/// 국립국어원 한국어기초사전 Open API를 사용한 단어 정의 서비스
class DefinitionService {
    static let shared = DefinitionService()

    private let apiKey = "7E36329C837372B4F8D927F8BF8B3DBD"
    private let baseURL = "https://krdict.korean.go.kr/api/search"

    /// 메모리 캐시: "korean:hanja" → [정의]
    private var cache: [String: [String]] = [:]

    /// 디스크 캐시 경로
    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("hanja_definitions_cache.json")
    }

    private init() {
        loadDiskCache()
    }

    // MARK: - Public API

    /// 한글 단어와 한자 변형들에 대한 정의를 비동기로 가져옴
    /// - Parameters:
    ///   - korean: 한글 단어 (e.g., "우수")
    ///   - hanjaVariants: 한자 변형 목록 (e.g., ["優秀", "雨水", "憂愁"])
    /// - Returns: [한자: [정의]] 딕셔너리
    func fetchDefinitions(korean: String, hanjaVariants: [String]) async -> [String: [String]] {
        // 캐시에서 먼저 확인
        var result: [String: [String]] = [:]
        var uncached: [String] = []

        for hanja in hanjaVariants {
            let key = "\(korean):\(hanja)"
            if let cached = cache[key] {
                result[hanja] = cached
            } else {
                uncached.append(hanja)
            }
        }

        // 모두 캐시에 있으면 바로 반환
        if uncached.isEmpty {
            return result
        }

        // API 호출
        guard let apiResult = await callAPI(korean: korean) else {
            return result
        }

        // API 결과에서 한자 매칭
        for hanja in hanjaVariants {
            let key = "\(korean):\(hanja)"
            if let definitions = apiResult[hanja], !definitions.isEmpty {
                cache[key] = definitions
                result[hanja] = definitions
            } else {
                // 매칭 안 된 것도 캐시 (빈 배열로 — 재호출 방지)
                cache[key] = []
            }
        }

        saveDiskCache()
        return result
    }

    // MARK: - API Call

    private func callAPI(korean: String) async -> [String: [String]]? {
        guard let encodedQuery = korean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let urlString = "\(baseURL)?key=\(apiKey)&q=\(encodedQuery)&part=word&sort=dict&num=10&method=exact"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let xmlString = String(data: data, encoding: .utf8) else { return nil }
            return parseXML(xmlString)
        } catch {
            return nil
        }
    }

    /// XML 응답 파싱 → [한자origin: [정의]]
    private func parseXML(_ xml: String) -> [String: [String]] {
        var result: [String: [String]] = [:]

        // 간단한 XML 파싱 (Foundation XMLParser 대신 문자열 파싱)
        let items = xml.components(separatedBy: "<item>").dropFirst()

        for item in items {
            guard let origin = extractTag("origin", from: item), !origin.isEmpty else {
                continue
            }

            var definitions: [String] = []
            let senses = item.components(separatedBy: "<sense>").dropFirst()
            for sense in senses {
                if let def = extractTag("definition", from: sense), !def.isEmpty {
                    definitions.append(def)
                }
            }

            if !definitions.isEmpty {
                result[origin] = definitions
            }
        }

        return result
    }

    private func extractTag(_ tag: String, from text: String) -> String? {
        guard let startRange = text.range(of: "<\(tag)>"),
              let endRange = text.range(of: "</\(tag)>") else {
            return nil
        }
        return String(text[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Disk Cache

    private func loadDiskCache() {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return
        }
        cache = loaded
    }

    private func saveDiskCache() {
        guard let url = cacheFileURL,
              let data = try? JSONEncoder().encode(cache) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
