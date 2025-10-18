//
//  SharedStubs.swift
//  StikJIT
//
//  Created by Stephen on 09/12/2025.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Shared glass card wrapper (renamed to avoid conflicts)
struct MaterialCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }
}

@ViewBuilder
func appGlassCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    MaterialCard {
        content()
    }
}

// MARK: - Open App Folder helper

func openAppFolder() {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let controller = UIActivityViewController(activityItems: [docs], applicationActivities: nil)
    controller.excludedActivityTypes = [.assignToContact, .saveToCameraRoll, .postToFacebook, .postToTwitter]
    DispatchQueue.main.async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        root.present(controller, animated: true)
    }
}
