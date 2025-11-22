//
//  QuickAddProductDialog.swift
//  Aromex
//
//  Created for Quick Actions on Home Screen
//  This dialog reuses UI components from AddProductDialog but saves directly to inventory
//

import SwiftUI
import FirebaseFirestore
import AVFoundation
import Vision
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct QuickAddProductDialog: View {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isSavingToInventory = false
    @State private var showSaveSuccessAlert = false
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""
    
    var body: some View {
        ZStack {
            AddProductDialog(
                isPresented: $isPresented,
                onDismiss: onDismiss,
                onSave: { phoneItems in
                    // Save directly to inventory
                    Task {
                        await saveToInventory(phoneItems: phoneItems)
                    }
                }
            )
            
            // Loading overlay
            if isSavingToInventory {
                loadingOverlay
            }
        }
        .alert("Success", isPresented: $showSaveSuccessAlert) {
            Button("OK") {
                isPresented = false
                onDismiss?()
            }
        } message: {
            Text("Product has been added to inventory successfully!")
        }
        .alert("Error", isPresented: $showSaveErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text("Saving to inventory...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
    }
    
    private func saveToInventory(phoneItems: [PhoneItem]) async {
        isSavingToInventory = true
        
        do {
            let db = Firestore.firestore()
            let batch = db.batch()
            let selectedDate = Date()
            
            // Process each phone item
            for phoneItem in phoneItems {
                // Find or create brand document
                let brandQuery = db.collection("PhoneBrands").whereField("brand", isEqualTo: phoneItem.brand).limit(to: 1)
                let brandSnapshot = try await brandQuery.getDocuments()
                
                let brandDocRef: DocumentReference
                if let existingBrand = brandSnapshot.documents.first {
                    brandDocRef = existingBrand.reference
                } else {
                    brandDocRef = db.collection("PhoneBrands").document()
                    batch.setData([
                        "brand": phoneItem.brand,
                        "createdAt": selectedDate
                    ], forDocument: brandDocRef)
                }
                
                // Find or create model document
                let modelQuery = brandDocRef.collection("Models").whereField("model", isEqualTo: phoneItem.model).limit(to: 1)
                let modelSnapshot = try await modelQuery.getDocuments()
                
                let modelDocRef: DocumentReference
                if let existingModel = modelSnapshot.documents.first {
                    modelDocRef = existingModel.reference
                } else {
                    modelDocRef = brandDocRef.collection("Models").document()
                    batch.setData([
                        "model": phoneItem.model,
                        "brand": phoneItem.brand,
                        "createdAt": selectedDate
                    ], forDocument: modelDocRef)
                }
                
                // Get or create storage location reference ONCE per phone item (not per IMEI)
                var storageLocationRef: DocumentReference? = nil
                if !phoneItem.storageLocation.isEmpty {
                    let locationQuery = db.collection("StorageLocations").whereField("storageLocation", isEqualTo: phoneItem.storageLocation).limit(to: 1)
                    let locationSnapshot = try await locationQuery.getDocuments()
                    
                    if let locationDoc = locationSnapshot.documents.first {
                        storageLocationRef = locationDoc.reference
        } else {
                        let newLocationRef = db.collection("StorageLocations").document()
                        batch.setData([
                            "storageLocation": phoneItem.storageLocation,
                            "createdAt": selectedDate
                        ], forDocument: newLocationRef)
                        storageLocationRef = newLocationRef
                    }
                }
                
                // Get or create carrier reference ONCE per phone item (not per IMEI)
                var carrierRef: DocumentReference? = nil
                if !phoneItem.carrier.isEmpty {
                    let carrierQuery = db.collection("Carriers").whereField("name", isEqualTo: phoneItem.carrier).limit(to: 1)
                    let carrierSnapshot = try await carrierQuery.getDocuments()
                    
                    if let carrierDoc = carrierSnapshot.documents.first {
                        carrierRef = carrierDoc.reference
        } else {
                        let newCarrierRef = db.collection("Carriers").document()
                        batch.setData([
                            "name": phoneItem.carrier,
                            "createdAt": selectedDate
                        ], forDocument: newCarrierRef)
                        carrierRef = newCarrierRef
                    }
                }
                
                // Get or create color reference ONCE per phone item (not per IMEI)
                var colorRef: DocumentReference? = nil
                if !phoneItem.color.isEmpty {
                    let colorQuery = db.collection("Colors").whereField("name", isEqualTo: phoneItem.color).limit(to: 1)
                    let colorSnapshot = try await colorQuery.getDocuments()
                    
                    if let colorDoc = colorSnapshot.documents.first {
                        colorRef = colorDoc.reference
        } else {
                        let newColorRef = db.collection("Colors").document()
                        batch.setData([
                            "name": phoneItem.color,
                            "createdAt": selectedDate
                        ], forDocument: newColorRef)
                        colorRef = newColorRef
                    }
                }
                
                // Create separate phone documents for each IMEI
                for imei in phoneItem.imeis {
                    let phoneDocRef = modelDocRef.collection("Phones").document()
                    
                    // Build phone data with all references
                    var phoneData: [String: Any] = [
                        "brand": brandDocRef,
                        "model": modelDocRef,
                        "capacity": phoneItem.capacity,
                        "capacityUnit": phoneItem.capacityUnit,
                        "imei": imei,
                        "unitCost": phoneItem.unitCost,
                        "status": phoneItem.status,
                        "createdAt": selectedDate
                    ]
                    
                    // Add optional references if they exist
                    if let carrierRef = carrierRef {
                        phoneData["carrier"] = carrierRef
                    }
                    
                    if let colorRef = colorRef {
                        phoneData["color"] = colorRef
                    }
                    
                    if let storageLocationRef = storageLocationRef {
                        phoneData["storageLocation"] = storageLocationRef
                    }
                    
                    // Set phone document
                    batch.setData(phoneData, forDocument: phoneDocRef)
                    
                    // Add IMEI to separate IMEI collection
                    let imeiDocRef = db.collection("IMEI").document()
                    batch.setData([
                        "imei": imei,
                        "phoneReference": phoneDocRef,
                        "createdAt": selectedDate
                    ], forDocument: imeiDocRef)
                }
            }
            
            // Commit the batch
            try await batch.commit()
            
            // Show success alert (dialog will close when user clicks OK)
            await MainActor.run {
                isSavingToInventory = false
                showSaveSuccessAlert = true
            }
            
        } catch {
            await MainActor.run {
                isSavingToInventory = false
                saveErrorMessage = "Failed to save product: \(error.localizedDescription)"
                showSaveErrorAlert = true
            }
        }
    }
}

