import Foundation

struct Hexagram: Codable, Identifiable {
    let id: Int
    let name: String
    let hexagramSymbol: String
    let yaos: [String]
    let yaoci: [String]
    let divinationDiagramName: String
    let divinationDiagram: String
    let explanation: String
}

struct HexagramProvider {
    private static var cachedHexagrams: [Hexagram]?

    static func loadHexagramData() -> [Hexagram] {
        // 使用缓存提高性能
        if let cached = cachedHexagrams {
            return cached
        }

        guard let url = Bundle.main.url(forResource: "HexagramData", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let hexagrams = try? JSONDecoder().decode([Hexagram].self, from: data) else {
            print("❌ 加载HexagramData.json失败")
            return []
        }

        print("✅ 成功加载 \(hexagrams.count) 个卦象")
        cachedHexagrams = hexagrams
        return hexagrams
    }

    static func findHexagram(by yaos: [YinYang]) -> Hexagram? {
        guard yaos.count == 6 else {
            print("❌ yaos数组长度不为6: \(yaos.count)")
            return nil
        }

        let hexagrams = loadHexagramData()

        // 打印输入的yaos用于调试
        let yaosString = yaos.map { $0.rawValue }.joined(separator: ", ")
        print("🔍 查找卦象: [\(yaosString)]")

        let result = hexagrams.first { hexagram in
            let hexagramYaos = hexagram.yaos.map { yaosString -> YinYang in
                yaosString == "阳" ? .yang : .yin
            }
            let match = hexagramYaos == yaos
            if match {
                print("✅ 找到匹配: \(hexagram.name)")
            }
            return match
        }

        if result == nil {
            print("❌ 未找到对应的卦象")
        }

        return result
    }
}