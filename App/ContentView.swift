import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataStorage: DataStorageManager

    private var showDebugTools: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("起的课")
                            .font(.largeTitle.bold())
                        Text("手动输入，快速得到卦象结果")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    startSessionBlock

                    NavigationLink(destination: HistoryView()) {
                        quickActionCard(
                            title: "历史记录",
                            subtitle: "查看过去起课结果与详情",
                            symbolName: "clock.arrow.circlepath"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("历史记录")

                    if showDebugTools {
                        NavigationLink(destination: HexagramTestView()) {
                            Label("卦象测试", systemImage: "ladybug.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color.blue.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("起的课")
            .navigationBarHidden(true)
        }
    }

    private var startSessionBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("开始起课")
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))

            NavigationLink(destination: CameraView()) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("手动输入")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)

                        Text("选择六爻阴阳")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.75))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(12)
                .background(Color.white.opacity(0.15))
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开始起课")
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.blue, Color.blue.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(24)
        .shadow(color: Color.blue.opacity(0.3), radius: 12, x: 0, y: 6)
    }

    private func quickActionCard(title: String, subtitle: String, symbolName: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DataStorageManager.shared)
    }
}
#endif
