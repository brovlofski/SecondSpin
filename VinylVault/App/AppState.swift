//  AppState.swift
//  SecondSpin
//
//  Global app state for tab navigation and toast messages
//

import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var showAddRecord: Bool = false
    @Published var toastMessage: String? = nil

    private var toastTimer: Timer?

    /// Show a toast notification that auto-dismisses after a given duration
    func showToast(_ message: String, duration: TimeInterval = 2.5) {
        toastTimer?.invalidate()
        toastMessage = message
        toastTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                withAnimation {
                    self?.toastMessage = nil
                }
            }
        }
    }

    /// Navigate to the Collection tab and dismiss the add-record sheet
    func navigateToCollection(toast: String? = nil) {
        showAddRecord = false
        selectedTab = 1
        if let toast = toast {
            // Slight delay so the sheet dismiss animation completes first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showToast(toast)
            }
        }
    }
}