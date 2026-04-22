import Foundation

/// 한국어문회 한자능력검정시험 배정한자 급수 (0=특급, 1~8=급수)
/// hanja_grades.txt에서 런타임 로드
let hanjaGradeMap: [Character: Int] = {
    var map: [Character: Int] = [:]
    guard let url = Bundle.main.url(forResource: "hanja_grades", withExtension: "txt"),
          let content = try? String(contentsOf: url, encoding: .utf8) else {
        return map
    }
    for line in content.components(separatedBy: "\n") {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let grade = Int(parts[0]) else { continue }
        for char in parts[1] {
            map[char] = grade
        }
    }
    return map
}()
