//
//  ContentView.swift
//  GoldenAcres
//
//  Created by Anton Danilov on 12/8/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Query private var farms: [Farm]

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .overlay(alignment: .top) {
            if let toast = appState.toast {
                SuccessToast(message: toast.message, detail: toast.detail)
                    .padding(.horizontal, Spacing.l)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
    }
}

// MARK: - Tabs

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var farms: [Farm]
    @State private var selection: Tab = .farm

    enum Tab: Hashable {
        case farm, fields, today, inventory, records
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                FarmDashboardView(onNavigate: { selection = $0 })
            }
            .tabItem { Label("Farm", systemImage: "house.fill") }
            .tag(Tab.farm)

            NavigationStack { FieldListView() }
                .tabItem { Label("Fields", systemImage: "square.dashed") }
                .tag(Tab.fields)

            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "checklist") }
                .tag(Tab.today)

            NavigationStack { InventoryView() }
                .tabItem { Label("Inventory", systemImage: "shippingbox.fill") }
                .tag(Tab.inventory)

            NavigationStack { RecordsView() }
                .tabItem { Label("Records", systemImage: "doc.text.magnifyingglass") }
                .tag(Tab.records)
        }
        .tint(Palette.gold)
        .onAppear(perform: styleBars)
        // Sync as soon as a session exists, and again whenever the app returns
        // to the foreground. Throttled inside SyncService.
        .task(id: auth.isSignedIn) {
            await SyncService.shared.autoSynchronize(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await SyncService.shared.autoSynchronize(context: context) }
        }
    }

    private func styleBars() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Palette.graphite)
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes =
            [.foregroundColor: UIColor(Palette.cream.opacity(0.45))]
        tabAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(Palette.cream.opacity(0.45))
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes =
            [.foregroundColor: UIColor(Palette.gold)]
        tabAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(Palette.gold)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Palette.graphite)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(Palette.cream)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Palette.cream)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .modelContainer(for: [Farm.self, FarmField.self], inMemory: true)
}
