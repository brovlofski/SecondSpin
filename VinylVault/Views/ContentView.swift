//  ContentView.swift
//  SecondSpin
//
//  Main tab navigation view
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("appearanceMode") private var appearanceMode = 0

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label(NSLocalizedString("Home", comment: ""), systemImage: "house.fill")
                }
                .tag(0)

            CollectionView()
                .tabItem {
                    Label(NSLocalizedString("Collection", comment: ""), systemImage: "square.stack.3d.up.fill")
                }
                .tag(1)

            // Center placeholder (invisible — actual button is overlaid below)
            Color.clear
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                }
                .tag(2)

            ListsView()
                .tabItem {
                    Label(NSLocalizedString("Lists", comment: ""), systemImage: "list.bullet")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label(NSLocalizedString("Settings", comment: ""), systemImage: "gear")
                }
                .tag(4)
        }
        .accentColor(.primary)
        .onChange(of: appState.selectedTab) { oldValue, newValue in
            // Intercept center tab tap to show add record
            if newValue == 2 {
                appState.showAddRecord = true
                // Reset to previous tab
                appState.selectedTab = oldValue
            }
        }
        .sheet(isPresented: $appState.showAddRecord) {
            AddRecordView()
        }
        .preferredColorScheme(
            appearanceMode == 1 ? .light : (appearanceMode == 2 ? .dark : nil)
        )
        .overlay(alignment: .bottom) {
            // Floating "+" button centred above the tab bar
            Button {
                appState.showAddRecord = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 60, height: 60)
                        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            // 49 pt tab bar; place button centre at ~same height as tab icons
            .padding(.bottom, 28)
        }
        .overlay(alignment: .bottom) {
            // Toast overlay
            if let message = appState.toastMessage {
                ToastView(message: message)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: appState.toastMessage)
            }
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .modelContainer(for: [Release.self, Copy.self, RecordList.self], inMemory: true)
}