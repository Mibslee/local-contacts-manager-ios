import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                OptimizedHomeView(appVM: appVM)
                    .tabItem {
                        Label("概览", systemImage: "house.fill")
                    }
                    .tag(0)

                ImportView(appVM: appVM)
                    .tabItem {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .tag(1)

                ExportView(appVM: appVM)
                    .tabItem {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .tag(2)

                SettingsView()
                    .tabItem {
                        Label("设置", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .tint(.blue)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
}
