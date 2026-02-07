import SwiftUI

struct HexagramTestView: View {
    @State private var testResults: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("卦象测试")
                    .font(.title)
                    .padding()

                Button("测试加载所有卦象") {
                    testLoadAll()
                }
                .padding()

                Button("测试乾卦（全阳）") {
                    testQian()
                }
                .padding()

                Button("测试坤卦（全阴）") {
                    testKun()
                }
                .padding()

                Button("测试地天泰") {
                    testDiTianTai()
                }
                .padding()

                Text(testResults)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    private func testLoadAll() {
        let hexagrams = HexagramProvider.loadHexagramData()
        testResults = "✅ 加载了 \(hexagrams.count) 个卦象\n\n"
        testResults += hexagrams.prefix(3).map { "\($0.id). \($0.name) - \($0.yaos.joined(separator: ", "))" }.joined(separator: "\n")
    }

    private func testQian() {
        let yaos: [YinYang] = [.yang, .yang, .yang, .yang, .yang, .yang]
        testResults = "测试卦象: 全阳\n"
        testResults += "输入: \(yaos.map { $0.rawValue }.joined(separator: ", "))\n\n"

        if let hexagram = HexagramProvider.findHexagram(by: yaos) {
            testResults += "✅ 找到: \(hexagram.name)\n"
            testResults += "卦象: \(hexagram.hexagramSymbol)\n"
            testResults += "六爻: \(hexagram.yaos.joined(separator: ", "))"
        } else {
            testResults += "❌ 未找到匹配的卦象"
        }
    }

    private func testKun() {
        let yaos: [YinYang] = [.yin, .yin, .yin, .yin, .yin, .yin]
        testResults = "测试卦象: 全阴\n"
        testResults += "输入: \(yaos.map { $0.rawValue }.joined(separator: ", "))\n\n"

        if let hexagram = HexagramProvider.findHexagram(by: yaos) {
            testResults += "✅ 找到: \(hexagram.name)\n"
            testResults += "卦象: \(hexagram.hexagramSymbol)\n"
            testResults += "六爻: \(hexagram.yaos.joined(separator: ", "))"
        } else {
            testResults += "❌ 未找到匹配的卦象"
        }
    }

    private func testDiTianTai() {
        // 地天泰：上坤下乾，从下到上应该是 阳、阳、阳、阴、阴、阴
        let yaos: [YinYang] = [.yang, .yang, .yang, .yin, .yin, .yin]
        testResults = "测试卦象: 地天泰\n"
        testResults += "输入: \(yaos.map { $0.rawValue }.joined(separator: ", "))\n\n"

        if let hexagram = HexagramProvider.findHexagram(by: yaos) {
            testResults += "✅ 找到: \(hexagram.name)\n"
            testResults += "卦象: \(hexagram.hexagramSymbol)\n"
            testResults += "JSON中的yaos: \(hexagram.yaos.joined(separator: ", "))"
        } else {
            testResults += "❌ 未找到匹配的卦象\n\n"
            testResults += "尝试反向数组..."

            // 尝试反向数组
            let reversedYaos: [YinYang] = [.yin, .yin, .yin, .yang, .yang, .yang]
            if let hexagram2 = HexagramProvider.findHexagram(by: reversedYaos) {
                testResults += "\n✅ 反向数组找到: \(hexagram2.name)\n"
                testResults += "JSON中的yaos: \(hexagram2.yaos.joined(separator: ", "))"
            }
        }
    }
}

#if DEBUG
struct HexagramTestView_Previews: PreviewProvider {
    static var previews: some View {
        HexagramTestView()
    }
}
#endif
