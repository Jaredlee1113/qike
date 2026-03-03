import SwiftUI

@main
struct TianjiApp: App {
    @StateObject private var dataStorage = DataStorageManager.shared
    @StateObject private var templateStorage = CoinTemplateStorageManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStorage)
                .environmentObject(templateStorage)
        }
    }
}