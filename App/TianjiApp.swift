import SwiftUI

@main
struct TianjiApp: App {
    @StateObject private var dataStorage = DataStorageManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStorage)
        }
    }
}