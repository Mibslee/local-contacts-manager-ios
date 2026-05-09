import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                OptimizedHomeView(appVM: appVM)
                    .tabItem {
                        Label("概览", systemImage: selectedTab == 0 ? "house.fill" : "house")
                    }
                    .tag(0)

                ImportView(appVM: appVM)
                    .tabItem {
                        Label("导入", systemImage: selectedTab == 1 ? "square.and.arrow.down.fill" : "square.and.arrow.down")
                    }
                    .tag(1)

                ExportView(appVM: appVM)
                    .tabItem {
                        Label("导出", systemImage: selectedTab == 2 ? "square.and.arrow.up.fill" : "square.and.arrow.up")
                    }
                    .tag(2)

                SettingsView()
                    .tabItem {
                        Label("设置", systemImage: selectedTab == 3 ? "gearshape.fill" : "gearshape")
                    }
                    .tag(3)
            }
            .tint(Color(hex: "4F7DF5"))
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
}
