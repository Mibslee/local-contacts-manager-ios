import SwiftUI

@main
struct _______App: App {
    @StateObject private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appVM)
                .onAppear {
                    appVM.checkAuthorization()
                }
        }
    }
}
