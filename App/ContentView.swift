import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataStorage: DataStorageManager
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                
                Text("起的课")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                
                Text("金钱卦识别")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .padding()
                
                Spacer()
                
                VStack(spacing: 15) {
                    NavigationLink(destination: SetupProfileView()) {
                        Label("设置铜钱模板", systemImage: "person.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink(destination: CameraView()) {
                        Label("开始起课", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)

                    NavigationLink(destination: ManualInputView()) {
                        Label("手动输入", systemImage: "hand.tap")
                    }
                    .buttonStyle(.bordered)

                    NavigationLink(destination: HexagramTestView()) {
                        Label("卦象测试", systemImage: "ladybug.fill")
                    }
                    .buttonStyle(.bordered)

                    NavigationLink(destination: HistoryView()) {
                        Label("历史记录", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("起的课")
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DataStorageManager.shared)
}
