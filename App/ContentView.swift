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
            VStack(spacing: 16) {
                HStack {
                    NavigationLink(destination: TemplateCenterView()) {
                        Label("模板中心", systemImage: "person.3")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    NavigationLink(destination: HistoryView()) {
                        Label("历史记录", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                NavigationLink(destination: CameraView()) {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 48, weight: .semibold))

                        Text("开始起课")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(24)
                    .padding(.horizontal, 24)
                    .shadow(color: Color.blue.opacity(0.3), radius: 12, x: 0, y: 6)
                }

                Spacer()

                if showDebugTools {
                    NavigationLink(destination: HexagramTestView()) {
                        Label("卦象测试", systemImage: "ladybug.fill")
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("起的课")
            .navigationBarHidden(true)
        }
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
