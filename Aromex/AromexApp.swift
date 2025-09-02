//
//  AromexApp.swift
//  Aromex
//
//  Created by Ansh Bajaj on 29/08/25.
//

import SwiftUI
import FirebaseCore

@main
struct AromexApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
