//
//  AromexApp.swift
//  Aromex
//
//  Created by Ansh Bajaj on 29/08/25.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore

@main
struct AromexApp: App {
    init() {
        FirebaseApp.configure()
        
        // Configure Firestore settings before first access
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = false
        settings.isSSLEnabled = true
        settings.host = "firestore.googleapis.com"
        
        let db = Firestore.firestore()
        db.settings = settings
        
        print("🔧 Configured Firestore for online-only mode from AromexApp")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
