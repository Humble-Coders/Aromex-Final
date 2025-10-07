//
//  SalesAddProductDialog.swift
//  Aromex
//
//  Created by Ansh on 20/09/25.
//

import SwiftUI
import FirebaseFirestore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct SalesAddProductDialog: View {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let onSave: (([PhoneItem]) -> Void)?
    
    // Brand dropdown state
    @State private var brandSearchText = ""
    @State private var selectedBrand = ""
    @State private var showingBrandDropdown = false
    @State private var brandButtonFrame: CGRect = .zero
    @State private var phoneBrands: [String] = []
    @State private var isLoadingBrands = false
    @FocusState private var isBrandFocused: Bool
    @State private var brandInternalSearchText = ""
    
    // Model dropdown state
    @State private var modelSearchText = ""
    @State private var selectedModel = ""
    @State private var showingModelDropdown = false
    @State private var modelButtonFrame: CGRect = .zero
    @State private var phoneModels: [String] = []
    @State private var isLoadingModels = false
    @FocusState private var isModelFocused: Bool
    @State private var modelInternalSearchText = ""
    
    // Storage Location dropdown state
    @State private var storageLocationSearchText = ""
    @State private var selectedStorageLocation = ""
    @State private var showingStorageLocationDropdown = false
    @State private var storageLocationButtonFrame: CGRect = .zero
    @State private var storageLocations: [String] = []
    @State private var storageLocationIdToName: [String: String] = [:]
    @State private var capacityIdToName: [String: String] = [:]
    @State private var colorIdToName: [String: String] = [:]
    @State private var carrierIdToName: [String: String] = [:]
    @State private var isLoadingStorageLocations = false
    @FocusState private var isStorageLocationFocused: Bool
    @State private var storageLocationInternalSearchText = ""
    
    // Table filtering state
    @State private var selectedCapacity: String = ""
    @State private var selectedColor: String = ""
    @State private var selectedIMEIs: Set<String> = []
    @State private var showActiveOnly: Bool = true
    @State private var filteredDevices: [DeviceInfo] = []
    @State private var allDevices: [DeviceInfo] = []
    
    // Loading and confirmation states
    @State private var showingConfirmation = false
    @State private var showingCloseConfirmation = false
    @State private var confirmationMessage = ""
    
    // Loading overlays
    @State private var isAddingBrand = false
    @State private var isAddingModel = false
    @State private var isAddingStorageLocation = false
    
    // Device info structure
    struct DeviceInfo: Identifiable, Hashable {
        let id = UUID()
        let capacity: String
        let capacityUnit: String
        let color: String
        let imei: String
        let carrier: String
        let status: String
        let unitPrice: Double
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(imei)
        }
        
        static func == (lhs: DeviceInfo, rhs: DeviceInfo) -> Bool {
            lhs.imei == rhs.imei
        }
    }
    
    @Environment(\.colorScheme) var colorScheme
    
    // Platform-specific colors
    private var backgroundGradientColor: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    private var secondaryGradientColor: Color {
        #if os(iOS)
        return Color(UIColor.systemGray6).opacity(0.3)
        #else
        return Color(NSColor.controlColor).opacity(0.3)
        #endif
    }
    
    // Check if form has any data
    private var hasFormData: Bool {
        return !selectedBrand.isEmpty ||
               !selectedModel.isEmpty ||
               !selectedStorageLocation.isEmpty ||
               !selectedIMEIs.isEmpty
    }
    
    // Enable Add Product when required fields are selected
    private var isAddEnabled: Bool {
        return !selectedBrand.isEmpty &&
               !selectedModel.isEmpty &&
               !selectedStorageLocation.isEmpty &&
               !selectedIMEIs.isEmpty
    }
    
    private var backgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(.systemBackground)
        #endif
    }
    
    var body: some View {
        if shouldShowiPhoneDialog {
            iPhoneDialogView
        } else {
            DesktopDialogView
        }
    }
    
    var iPhoneDialogView: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [backgroundGradientColor, secondaryGradientColor]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            NavigationView {
                    VStack(spacing: 0) {
                    // Fixed Header
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Add Product to Sale")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Select brand, model, and location to view available devices")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                        }
                        .padding(.bottom, 32)
                        
                    // Fixed Dropdown Row
                        VStack(spacing: 28) {
                            iPhoneFormFields
                        }
                        .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    
                    Divider()
                        .padding(.horizontal, 24)
                    
                    // Fixed Table Area - fills remaining space
                    if !selectedBrand.isEmpty && !selectedModel.isEmpty && !selectedStorageLocation.isEmpty && !filteredDevices.isEmpty {
                        DeviceFilteringTable(
                            devices: $filteredDevices,
                            selectedCapacity: $selectedCapacity,
                            selectedColor: $selectedColor,
                            selectedIMEIs: $selectedIMEIs,
                            showActiveOnly: $showActiveOnly
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    } else {
                        // Placeholder when no data
                        VStack {
                            Spacer()
                            Text("Select brand, model, and storage location to view devices")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        handleCloseAction()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addProducts()
                    }
                    .disabled(!isAddEnabled)
                }
            }
            #endif
        }
        .confirmationDialog("Close without saving?", isPresented: $showingCloseConfirmation) {
            Button("Discard Changes", role: .destructive) {
                closeDialog()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Are you sure you want to close?")
        }
        .overlay {
            if showingConfirmation {
                ConfirmationOverlay(message: confirmationMessage)
            }
        }
        .onAppear {
            fetchPhoneBrands()
        }
    }
    
    var DesktopDialogView: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    handleCloseAction()
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Add Product to Sale")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button(action: handleCloseAction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                Divider()
                
                // Fixed Dropdown Row
                    VStack(spacing: 24) {
                        DesktopFormFields
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                
                Divider()
                
                // Fixed Table Area - fills remaining space
                if !selectedBrand.isEmpty && !selectedModel.isEmpty && !selectedStorageLocation.isEmpty && !filteredDevices.isEmpty {
                    DeviceFilteringTable(
                        devices: $filteredDevices,
                        selectedCapacity: $selectedCapacity,
                        selectedColor: $selectedColor,
                        selectedIMEIs: $selectedIMEIs,
                        showActiveOnly: $showActiveOnly
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                } else {
                    // Placeholder when no data
                    VStack {
                        Spacer()
                        Text("Select brand, model, and storage location to view devices")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                Divider()
                
                // Footer
                HStack {
                    Button("Cancel") {
                        handleCloseAction()
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    Button("Add Products") {
                        addProducts()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isAddEnabled)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .frame(width: 1200, height: 800) // Much larger dialog
            .background(backgroundColor)
            .cornerRadius(12)
            .shadow(radius: 20)
        }
        .overlay(desktopBrandDropdownOverlay)
        .overlay(desktopModelDropdownOverlay)
        .overlay(desktopStorageLocationDropdownOverlay)
        .confirmationDialog("Close without saving?", isPresented: $showingCloseConfirmation) {
            Button("Discard Changes", role: .destructive) {
                closeDialog()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Are you sure you want to close?")
        }
        .overlay {
            if showingConfirmation {
                ConfirmationOverlay(message: confirmationMessage)
            }
        }
        .onAppear {
            print("DesktopDialogView appeared")
            fetchPhoneBrands()
        }
        .onChange(of: selectedBrand) { newBrand in
            print("selectedBrand changed to: '\(newBrand)'")
        }
        .onChange(of: phoneModels) { newModels in
            print("phoneModels changed - count: \(newModels.count), models: \(newModels)")
        }
    }
    
    // MARK: - Desktop Dropdown Overlays
    private var desktopBrandDropdownOverlay: some View {
        Group {
            #if os(macOS)
            if showingBrandDropdown {
                SalesBrandDropdownOverlay(
                    isOpen: $showingBrandDropdown,
                    selectedBrand: $selectedBrand,
                    searchText: $brandSearchText,
                    internalSearchText: $brandInternalSearchText,
                    brands: phoneBrands,
                    buttonFrame: brandButtonFrame,
                    onAddBrand: { brandName in
                        addNewBrand(brandName)
                    },
                    onRenameBrand: { oldName, newName in
                        // TODO: Implement rename functionality if needed
                    },
                    onBrandSelected: { brand in
                        selectedBrand = brand
                        brandSearchText = brand
                        selectedModel = ""
                        modelSearchText = ""
                        selectedStorageLocation = ""
                        storageLocationSearchText = ""
                        storageLocationIdToName = [:]
                        capacityIdToName = [:]
                        colorIdToName = [:]
                        carrierIdToName = [:]
                        filteredDevices = []
                        allDevices = []
                        selectedCapacity = ""
                        selectedColor = ""
                        selectedIMEIs.removeAll()
                        print("About to call fetchPhoneModels for brand: \(brand)")
                        fetchPhoneModels()
                    }
                )
            }
            #endif
        }
    }
    
    private var desktopModelDropdownOverlay: some View {
        Group {
            #if os(macOS)
            if showingModelDropdown {
                SalesModelDropdownOverlay(
                    isOpen: $showingModelDropdown,
                    selectedModel: $selectedModel,
                    models: phoneModels,
                    buttonFrame: modelButtonFrame,
                    searchText: $modelSearchText,
                    internalSearchText: $modelInternalSearchText,
                    isAddingModel: $isAddingModel,
                    onAddModel: addNewModel,
                    onModelSelected: { model in
                        print("Model selected (Desktop): \(model)")
                        selectedModel = model
                        modelSearchText = model
                        selectedStorageLocation = ""
                        storageLocationSearchText = ""
                        storageLocationIdToName = [:]
                        capacityIdToName = [:]
                        colorIdToName = [:]
                        carrierIdToName = [:]
                        filteredDevices = []
                        allDevices = []
                        selectedCapacity = ""
                        selectedColor = ""
                        selectedIMEIs.removeAll()
                        print("About to call fetchStorageLocations for model: \(model)")
                        fetchStorageLocations()
                    }
                )
            }
            #endif
        }
    }
    
    private var desktopStorageLocationDropdownOverlay: some View {
        Group {
            #if os(macOS)
            if showingStorageLocationDropdown {
                SalesStorageLocationDropdownOverlay(
                    isOpen: $showingStorageLocationDropdown,
                    selectedStorageLocation: $selectedStorageLocation,
                    searchText: $storageLocationSearchText,
                    internalSearchText: $storageLocationInternalSearchText,
                    storageLocations: storageLocations,
                    buttonFrame: storageLocationButtonFrame,
                    onAddStorageLocation: addNewStorageLocation,
                    onRenameStorageLocation: { oldName, newName in
                        // TODO: Implement rename functionality if needed
                    },
                    onStorageLocationSelected: { location in
                        selectedStorageLocation = location
                        storageLocationSearchText = location
                        loadDevices()
                    }
                )
            }
            #endif
        }
    }
    
    // MARK: - iPhone Form Fields
    var iPhoneFormFields: some View {
        VStack(spacing: 28) {
            // Brand dropdown
            BrandDropdownField(
                searchText: $brandSearchText,
                selectedBrand: $selectedBrand,
                showingDropdown: $showingBrandDropdown,
                buttonFrame: $brandButtonFrame,
                brands: phoneBrands,
                isLoading: isLoadingBrands,
                isFocused: $isBrandFocused,
                internalSearchText: $brandInternalSearchText,
                isAddingBrand: $isAddingBrand,
                onAddBrand: addNewBrand,
                onBrandSelected: { brand in
                    print("Brand selected: \(brand)")
                    selectedBrand = brand
                    brandSearchText = brand
                    selectedModel = ""
                    modelSearchText = ""
                    selectedStorageLocation = ""
                    storageLocationSearchText = ""
                    storageLocationIdToName = [:]
                    filteredDevices = []
                    allDevices = []
                    selectedCapacity = ""
                    selectedColor = ""
                    selectedIMEIs.removeAll()
                    print("About to call fetchPhoneModels for brand: \(brand)")
                    fetchPhoneModels()
                }
            )
            
            // Model dropdown
            ModelDropdownField(
                searchText: $modelSearchText,
                selectedModel: $selectedModel,
                showingDropdown: $showingModelDropdown,
                buttonFrame: $modelButtonFrame,
                models: phoneModels,
                isLoading: isLoadingModels,
                isFocused: $isModelFocused,
                internalSearchText: $modelInternalSearchText,
                isAddingModel: $isAddingModel,
                isEnabled: !selectedBrand.isEmpty,
                onAddModel: addNewModel,
                onModelSelected: { model in
                    selectedModel = model
                    modelSearchText = model
                    selectedStorageLocation = ""
                    storageLocationSearchText = ""
                    storageLocationIdToName = [:]
                    filteredDevices = []
                    allDevices = []
                    selectedCapacity = ""
                    selectedColor = ""
                    selectedIMEIs.removeAll()
                    fetchStorageLocations()
                }
            )
            
            // Storage Location dropdown
            StorageLocationDropdownField(
                searchText: $storageLocationSearchText,
                selectedStorageLocation: $selectedStorageLocation,
                showingDropdown: $showingStorageLocationDropdown,
                buttonFrame: $storageLocationButtonFrame,
                storageLocations: storageLocations,
                isLoading: isLoadingStorageLocations,
                isFocused: $isStorageLocationFocused,
                internalSearchText: $storageLocationInternalSearchText,
                isAddingStorageLocation: $isAddingStorageLocation,
                isEnabled: !selectedBrand.isEmpty && !selectedModel.isEmpty,
                onAddStorageLocation: addNewStorageLocation,
                onStorageLocationSelected: { location in
                    selectedStorageLocation = location
                    storageLocationSearchText = location
                    loadDevices()
                }
            )
        }
    }
    
    // MARK: - Desktop Form Fields
    var DesktopFormFields: some View {
        VStack(spacing: 24) {
            // Top row with brand, model, location
            HStack(spacing: 16) {
                // Brand dropdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("Brand")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    BrandDropdownField(
                        searchText: $brandSearchText,
                        selectedBrand: $selectedBrand,
                        showingDropdown: $showingBrandDropdown,
                        buttonFrame: $brandButtonFrame,
                        brands: phoneBrands,
                        isLoading: isLoadingBrands,
                        isFocused: $isBrandFocused,
                        internalSearchText: $brandInternalSearchText,
                        isAddingBrand: $isAddingBrand,
                        onAddBrand: addNewBrand,
                        onBrandSelected: { brand in
                            print("Brand selected (iPhone): \(brand)")
                            selectedBrand = brand
                            brandSearchText = brand
                            selectedModel = ""
                            modelSearchText = ""
                            selectedStorageLocation = ""
                            storageLocationSearchText = ""
                            storageLocationIdToName = [:]
                        capacityIdToName = [:]
                        colorIdToName = [:]
                        carrierIdToName = [:]
                            filteredDevices = []
                            allDevices = []
                            selectedCapacity = ""
                            selectedColor = ""
                            selectedIMEIs.removeAll()
                            print("About to call fetchPhoneModels for brand (iPhone): \(brand)")
                            fetchPhoneModels()
                        }
                    )
                }
                
                // Model dropdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    ModelDropdownField(
                        searchText: $modelSearchText,
                        selectedModel: $selectedModel,
                        showingDropdown: $showingModelDropdown,
                        buttonFrame: $modelButtonFrame,
                        models: phoneModels,
                        isLoading: isLoadingModels,
                        isFocused: $isModelFocused,
                        internalSearchText: $modelInternalSearchText,
                        isAddingModel: $isAddingModel,
                        isEnabled: !selectedBrand.isEmpty,
                        onAddModel: addNewModel,
                        onModelSelected: { model in
                            selectedModel = model
                            modelSearchText = model
                            selectedStorageLocation = ""
                            storageLocationSearchText = ""
                            storageLocationIdToName = [:]
                        capacityIdToName = [:]
                        colorIdToName = [:]
                        carrierIdToName = [:]
                            filteredDevices = []
                            allDevices = []
                            selectedCapacity = ""
                            selectedColor = ""
                            selectedIMEIs.removeAll()
                            fetchStorageLocations()
                        }
                    )
                }
                
                // Storage Location dropdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage Location")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    StorageLocationDropdownField(
                        searchText: $storageLocationSearchText,
                        selectedStorageLocation: $selectedStorageLocation,
                        showingDropdown: $showingStorageLocationDropdown,
                        buttonFrame: $storageLocationButtonFrame,
                        storageLocations: storageLocations,
                        isLoading: isLoadingStorageLocations,
                        isFocused: $isStorageLocationFocused,
                        internalSearchText: $storageLocationInternalSearchText,
                        isAddingStorageLocation: $isAddingStorageLocation,
                        isEnabled: !selectedBrand.isEmpty && !selectedModel.isEmpty,
                        onAddStorageLocation: addNewStorageLocation,
                        onStorageLocationSelected: { location in
                            selectedStorageLocation = location
                            storageLocationSearchText = location
                            loadDevices()
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var shouldShowiPhoneDialog: Bool {
        #if os(iOS)
        print("Platform: iOS - showing iPhone dialog")
        return true
        #else
        print("Platform: macOS - showing Desktop dialog")
        return false
        #endif
    }
    
    private func handleCloseAction() {
        if hasFormData {
            showingCloseConfirmation = true
        } else {
            closeDialog()
        }
    }
    
    private func closeDialog() {
        isPresented = false
        onDismiss?()
    }
    
    private func addProducts() {
        // Create PhoneItem objects from selected IMEIs
        var items: [PhoneItem] = []
        
        for imei in selectedIMEIs {
            if let device = filteredDevices.first(where: { $0.imei == imei }) {
                let item = PhoneItem(
                    brand: selectedBrand,
                    model: selectedModel,
                    capacity: device.capacity,
                    capacityUnit: "GB", // Default to GB
                    color: device.color,
                    carrier: device.carrier,
                    status: "Active",
                    storageLocation: selectedStorageLocation,
                    imeis: [device.imei],
                    unitCost: 0.0 // Price will be set in the sales view
                )
                items.append(item)
            }
        }
        
        onSave?(items)
        closeDialog()
    }
    
    // MARK: - Data Loading Methods (using same patterns as AddProductDialog)
    
    private func fetchPhoneBrands() {
        isLoadingBrands = true
        let db = Firestore.firestore()
        
        db.collection("PhoneBrands").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                self.isLoadingBrands = false
                
                if let error = error {
                    print("Error fetching phone brands: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { 
                    print("No documents found in PhoneBrands collection")
                    return 
                }
                
                let brandNames = documents.compactMap { document in
                    document.data()["brand"] as? String
                }
                print("Fetched \(brandNames.count) brands: \(brandNames)")
                
                self.phoneBrands = brandNames.sorted()
                print("Sorted brands: \(self.phoneBrands)")
            }
        }
    }
    
    private func fetchPhoneModels() {
        guard !selectedBrand.isEmpty else {
            print("fetchPhoneModels: No brand selected, clearing models")
            phoneModels = []
            return
        }
        
        print("fetchPhoneModels: Starting fetch for brand: \(selectedBrand)")
        isLoadingModels = true
        let brandName = selectedBrand
        
        getBrandDocumentId(for: brandName) { brandDocId in
            let db = Firestore.firestore()
            DispatchQueue.main.async {
                guard let brandDocId = brandDocId else {
                    print("fetchPhoneModels: No brand document ID found for \(brandName)")
                    self.isLoadingModels = false
                    self.phoneModels = []
                    return
                }
                print("fetchPhoneModels: Got brand document ID: \(brandDocId), now fetching models")
                db.collection("PhoneBrands")
                    .document(brandDocId)
                    .collection("Models")
                    .getDocuments { snapshot, error in
                        DispatchQueue.main.async {
                            self.isLoadingModels = false
                            
                            if let error = error {
                                print("Error fetching phone models for brand \(brandName): \(error)")
                                return
                            }
                            
                            guard let documents = snapshot?.documents else {
                                print("No model documents found for brand \(brandName)")
                                self.phoneModels = []
                                return
                            }
                            
                            let modelNames = documents.compactMap { document in
                                document.data()["model"] as? String
                            }
                            print("Fetched \(modelNames.count) models for brand \(brandName): \(modelNames)")
                            
                            self.phoneModels = modelNames.sorted()
                            print("Sorted models: \(self.phoneModels)")
                            print("phoneModels state updated - count: \(self.phoneModels.count)")
                        }
                    }
            }
        }
    }
    
    private func fetchStorageLocations() {
        guard !selectedBrand.isEmpty && !selectedModel.isEmpty else {
            print("fetchStorageLocations: Missing brand or model - brand: '\(selectedBrand)', model: '\(selectedModel)'")
            storageLocations = []
            return
        }
        
        print("fetchStorageLocations: Starting fetch for brand: \(selectedBrand), model: \(selectedModel)")
        isLoadingStorageLocations = true
        let brandName = selectedBrand
        let modelName = selectedModel
        
        // First get the brand document ID
        getBrandDocumentId(for: brandName) { brandDocId in
        let db = Firestore.firestore()
            DispatchQueue.main.async {
                guard let brandDocId = brandDocId else {
                    print("fetchStorageLocations: No brand document ID found for \(brandName)")
                    self.isLoadingStorageLocations = false
                    self.storageLocations = []
                    return
                }
                print("fetchStorageLocations: Got brand document ID: \(brandDocId)")
                
                // Now get the model document ID
                db.collection("PhoneBrands")
                    .document(brandDocId)
                    .collection("Models")
                    .whereField("model", isEqualTo: modelName)
                    .limit(to: 1)
                    .getDocuments { modelSnapshot, modelError in
            DispatchQueue.main.async {
                            guard let modelDocId = modelSnapshot?.documents.first?.documentID else {
                                print("fetchStorageLocations: No model document found for \(modelName)")
                self.isLoadingStorageLocations = false
                                self.storageLocations = []
                                return
                            }
                            print("fetchStorageLocations: Got model document ID: \(modelDocId)")
                            
                            // Now get all phones from the Phones subcollection
                            db.collection("PhoneBrands")
                                .document(brandDocId)
                                .collection("Models")
                                .document(modelDocId)
                                .collection("Phones")
                                .getDocuments { phonesSnapshot, phonesError in
                                    DispatchQueue.main.async {
                                        self.isLoadingStorageLocations = false
                                        
                                        if let phonesError = phonesError {
                                            print("Error fetching phones for model: \(phonesError)")
                    return
                }
                
                                        guard let phoneDocuments = phonesSnapshot?.documents else {
                                            print("No phones found for brand \(self.selectedBrand) and model \(self.selectedModel)")
                                            self.storageLocations = []
                    return 
                }
                
                                        print("Fetched \(phoneDocuments.count) phones for model \(self.selectedModel)")
                                        
                                        // Debug: Print the first phone's storage location data
                                        if let firstPhone = phoneDocuments.first {
                                            let firstPhoneData = firstPhone.data()
                                            let storageLocationData = firstPhoneData["storageLocation"]
                                            print("Debug: First phone storageLocation data: \(storageLocationData)")
                                            print("Debug: Storage location data type: \(type(of: storageLocationData))")
                                        }
                                        
                                        // Extract unique storage locations from the phones
                                        let locationNames = Set(phoneDocuments.compactMap { document in
                                            let storageLocationData = document.data()["storageLocation"]
                                            
                                            // Handle both string and reference formats
                                            if let storageLocationString = storageLocationData as? String {
                                                // If it's a reference path like "/StorageLocations/G2LwxanSfPHilqcBVWPg", extract the ID
                                                if storageLocationString.hasPrefix("/StorageLocations/") {
                                                    let pathComponents = storageLocationString.components(separatedBy: "/")
                                                    if pathComponents.count >= 3 {
                                                        return pathComponents[2] // Return the document ID part
                                                    }
                                                }
                                                return storageLocationString
                                            }
                                            
                                            // Handle Firestore reference objects
                                            if let storageLocationRef = storageLocationData as? DocumentReference {
                                                return storageLocationRef.documentID
                                            }
                                            
                                            return nil
                                        })
                
                                        print("Fetched \(locationNames.count) storage location IDs for model \(self.selectedModel): \(locationNames)")
                                        
                                        // Now fetch the actual storage location names from StorageLocations collection
                                        self.fetchStorageLocationNames(from: Array(locationNames))
                                    }
                                }
                        }
                    }
            }
        }
    }
    
    private func fetchStorageLocationNames(from locationIds: [String]) {
        guard !locationIds.isEmpty else {
            print("No storage location IDs to fetch")
            self.storageLocations = []
            return
        }
        
        print("fetchStorageLocationNames: Fetching names for \(locationIds.count) location IDs: \(locationIds)")
        let db = Firestore.firestore()
        
        // Fetch all storage location documents in parallel
        let dispatchGroup = DispatchGroup()
        var locationNames: [String: String] = [:] // ID -> Name mapping
        
        for locationId in locationIds {
            dispatchGroup.enter()
            
            db.collection("StorageLocations")
                .document(locationId)
                .getDocument { document, error in
                    defer { dispatchGroup.leave() }
                    
                    if let error = error {
                        print("Error fetching storage location \(locationId): \(error)")
                        return
                    }
                    
                    guard let document = document, document.exists else {
                        print("Storage location document \(locationId) does not exist")
                        return
                    }
                    
                    let data = document.data()
                    if let name = data?["name"] as? String {
                        locationNames[locationId] = name
                        print("Fetched storage location name: \(name) for ID: \(locationId)")
                    } else {
                        print("No name field found for storage location \(locationId)")
                    }
                }
        }
        
        // Wait for all fetches to complete
        dispatchGroup.notify(queue: .main) {
            let sortedNames = locationIds.compactMap { locationNames[$0] }.sorted()
            print("Final storage location names: \(sortedNames)")
            self.storageLocations = sortedNames
            
            // Update the mapping for later use
            self.storageLocationIdToName = locationNames
        }
    }
    
    private func fetchReferenceNames(
        capacityIds: [String],
        colorIds: [String],
        carrierIds: [String],
        phoneDocuments: [QueryDocumentSnapshot]
    ) {
        print("fetchReferenceNames: Starting async fetch for \(capacityIds.count) capacities, \(colorIds.count) colors, \(carrierIds.count) carriers")
        let db = Firestore.firestore()
        let dispatchGroup = DispatchGroup()
        
        var capacityIdToName: [String: String] = [:]
        var colorIdToName: [String: String] = [:]
        var carrierIdToName: [String: String] = [:]
        
        // Fetch capacity names
        for capacityId in capacityIds {
            dispatchGroup.enter()
            db.collection("Capacities")
                .document(capacityId)
                .getDocument { document, error in
                    defer { dispatchGroup.leave() }
                    
                    if let error = error {
                        print("Error fetching capacity \(capacityId): \(error)")
                        return
                    }
                    
                    guard let document = document, document.exists else {
                        print("Capacity document \(capacityId) does not exist")
                        return
                    }
                    
                    let data = document.data()
                    if let name = data?["name"] as? String {
                        capacityIdToName[capacityId] = name
                        print("Fetched capacity name: \(name) for ID: \(capacityId)")
                    } else {
                        print("No name field found for capacity \(capacityId)")
                    }
                }
        }
        
        // Fetch color names
        for colorId in colorIds {
            dispatchGroup.enter()
            db.collection("Colors")
                .document(colorId)
                .getDocument { document, error in
                    defer { dispatchGroup.leave() }
                    
                    if let error = error {
                        print("Error fetching color \(colorId): \(error)")
                        return
                    }
                    
                    guard let document = document, document.exists else {
                        print("Color document \(colorId) does not exist")
                        return
                    }
                    
                    let data = document.data()
                    if let name = data?["name"] as? String {
                        colorIdToName[colorId] = name
                        print("Fetched color name: \(name) for ID: \(colorId)")
                    } else {
                        print("No name field found for color \(colorId)")
                    }
                }
        }
        
        // Fetch carrier names
        for carrierId in carrierIds {
            dispatchGroup.enter()
            db.collection("Carriers")
                .document(carrierId)
                .getDocument { document, error in
                    defer { dispatchGroup.leave() }
                    
                    if let error = error {
                        print("Error fetching carrier \(carrierId): \(error)")
                        return
                    }
                    
                    guard let document = document, document.exists else {
                        print("Carrier document \(carrierId) does not exist")
                        return
                    }
                    
                    let data = document.data()
                    if let name = data?["name"] as? String {
                        carrierIdToName[carrierId] = name
                        print("Fetched carrier name: \(name) for ID: \(carrierId)")
                    } else {
                        print("No name field found for carrier \(carrierId)")
                    }
                }
        }
        
        // Wait for all fetches to complete
        dispatchGroup.notify(queue: .main) {
            print("fetchReferenceNames: All reference fetches completed")
            
            // Update the mappings
            self.capacityIdToName = capacityIdToName
            self.colorIdToName = colorIdToName
            self.carrierIdToName = carrierIdToName
            
            // Now create the DeviceInfo objects with resolved names
            self.allDevices = phoneDocuments.compactMap { doc in
                        let data = doc.data()
                guard let imei = data["imei"] as? String else {
                            return nil
                        }
                
                // Resolve capacity name
                var capacityName = "Unknown"
                if let capacityData = data["capacity"] {
                    if let capacityStr = capacityData as? String {
                        if capacityStr.hasPrefix("/Capacities/") {
                            let pathComponents = capacityStr.components(separatedBy: "/")
                            if pathComponents.count >= 3, let resolvedName = capacityIdToName[pathComponents[2]] {
                                capacityName = resolvedName
                            }
                        } else {
                            capacityName = capacityStr
                        }
                    } else if let capacityRef = capacityData as? DocumentReference,
                              let resolvedName = capacityIdToName[capacityRef.documentID] {
                        capacityName = resolvedName
                    }
                }
                
                // Resolve color name
                var colorName = "Unknown"
                if let colorData = data["color"] {
                    if let colorStr = colorData as? String {
                        if colorStr.hasPrefix("/Colors/") {
                            let pathComponents = colorStr.components(separatedBy: "/")
                            if pathComponents.count >= 3, let resolvedName = colorIdToName[pathComponents[2]] {
                                colorName = resolvedName
                            }
                        } else {
                            colorName = colorStr
                        }
                    } else if let colorRef = colorData as? DocumentReference,
                              let resolvedName = colorIdToName[colorRef.documentID] {
                        colorName = resolvedName
                    }
                }
                
                // Resolve carrier name
                var carrierName = "Unknown"
                if let carrierData = data["carrier"] {
                    if let carrierStr = carrierData as? String {
                        if carrierStr.hasPrefix("/Carriers/") {
                            let pathComponents = carrierStr.components(separatedBy: "/")
                            if pathComponents.count >= 3, let resolvedName = carrierIdToName[pathComponents[2]] {
                                carrierName = resolvedName
                            }
                        } else {
                            carrierName = carrierStr
                        }
                    } else if let carrierRef = carrierData as? DocumentReference,
                              let resolvedName = carrierIdToName[carrierRef.documentID] {
                        carrierName = resolvedName
                    }
                }
                
                // Get status
                let status = data["status"] as? String ?? "Unknown"
                
                // Get capacity unit
                let capacityUnit = data["capacityUnit"] as? String ?? ""
                
                // Get unit price
                let unitPrice = data["unitCost"] as? Double ?? 0.0
                
                return DeviceInfo(capacity: capacityName, capacityUnit: capacityUnit, color: colorName, imei: imei, carrier: carrierName, status: status, unitPrice: unitPrice)
            }
                    
                    self.filteredDevices = self.allDevices
                    self.selectedCapacity = ""
                    self.selectedColor = ""
                    self.selectedIMEIs.removeAll()
            
            print("loadDevices: Created \(self.allDevices.count) devices with resolved names")
        }
    }
    
    private func loadDevices() {
        guard !selectedBrand.isEmpty && !selectedModel.isEmpty && !selectedStorageLocation.isEmpty else {
            allDevices = []
            filteredDevices = []
            return
        }
        
        print("loadDevices: Starting load for brand: \(selectedBrand), model: \(selectedModel), storage: \(selectedStorageLocation)")
        
        // Convert storage location name back to ID for filtering
        guard let selectedStorageLocationId = storageLocationIdToName.first(where: { $0.value == selectedStorageLocation })?.key else {
            print("loadDevices: Could not find storage location ID for name: \(selectedStorageLocation)")
            allDevices = []
            filteredDevices = []
            return
        }
        
        print("loadDevices: Using storage location ID: \(selectedStorageLocationId) for name: \(selectedStorageLocation)")
        let brandName = selectedBrand
        let modelName = selectedModel
        
        // First get the brand document ID
        getBrandDocumentId(for: brandName) { brandDocId in
        let db = Firestore.firestore()
            DispatchQueue.main.async {
                guard let brandDocId = brandDocId else {
                    print("loadDevices: No brand document ID found for \(brandName)")
                    self.allDevices = []
                    self.filteredDevices = []
                    return
                }
                print("loadDevices: Got brand document ID: \(brandDocId)")
                
                // Now get the model document ID
                db.collection("PhoneBrands")
                    .document(brandDocId)
                    .collection("Models")
                    .whereField("model", isEqualTo: modelName)
                    .limit(to: 1)
                    .getDocuments { modelSnapshot, modelError in
                DispatchQueue.main.async {
                            guard let modelDocId = modelSnapshot?.documents.first?.documentID else {
                                print("loadDevices: No model document found for \(modelName)")
                                self.allDevices = []
                                self.filteredDevices = []
                        return
                    }
                            print("loadDevices: Got model document ID: \(modelDocId)")
                            
                            // Now get all phones from the Phones subcollection
                            db.collection("PhoneBrands")
                                .document(brandDocId)
                                .collection("Models")
                                .document(modelDocId)
                                .collection("Phones")
                                .getDocuments { phonesSnapshot, phonesError in
                                    DispatchQueue.main.async {
                                        if let phonesError = phonesError {
                                            print("Error loading devices: \(phonesError)")
                                            return
                                        }
                                        
                                        guard let phoneDocuments = phonesSnapshot?.documents else {
                                            print("No phones found for brand \(self.selectedBrand) and model \(self.selectedModel)")
                                            self.allDevices = []
                                            self.filteredDevices = []
                                            return
                                        }
                                        
                                        print("loadDevices: Fetched \(phoneDocuments.count) phones for model \(self.selectedModel)")
                                        
                                        // Debug: Print the first phone's data to see the structure
                                        if let firstPhone = phoneDocuments.first {
                                            let firstPhoneData = firstPhone.data()
                                            print("Debug: First phone data: \(firstPhoneData)")
                                        }
                                        
                                        // First, filter devices by storage location and collect all reference IDs
                                        var filteredPhoneDocuments: [QueryDocumentSnapshot] = []
                                        var capacityIds: Set<String> = []
                                        var colorIds: Set<String> = []
                                        var carrierIds: Set<String> = []
                                        
                                        for doc in phoneDocuments {
                                            let data = doc.data()
                                            
                                            // Handle storage location reference format
                                            let storageLocationData = data["storageLocation"]
                                            var storageLocationString: String?
                                            
                                            if let storageLocationStr = storageLocationData as? String {
                                                // If it's a reference path like "/StorageLocations/G2LwxanSfPHilqcBVWPg", extract the ID
                                                if storageLocationStr.hasPrefix("/StorageLocations/") {
                                                    let pathComponents = storageLocationStr.components(separatedBy: "/")
                                                    if pathComponents.count >= 3 {
                                                        storageLocationString = pathComponents[2] // Return the document ID part
                                                    }
                                                } else {
                                                    storageLocationString = storageLocationStr
                                                }
                                            } else if let storageLocationRef = storageLocationData as? DocumentReference {
                                                storageLocationString = storageLocationRef.documentID
                                            }
                                            
                                            guard let storageLocation = storageLocationString else {
                                                continue
                                            }
                                            
                                            // Only include devices from the selected storage location
                                            guard storageLocation == selectedStorageLocationId else {
                                                continue
                                            }
                                            
                                            filteredPhoneDocuments.append(doc)
                                            
                                            // Collect reference IDs for capacity, color, and carrier
                                            if let capacityData = data["capacity"] {
                                                if let capacityStr = capacityData as? String {
                                                    if capacityStr.hasPrefix("/Capacities/") {
                                                        let pathComponents = capacityStr.components(separatedBy: "/")
                                                        if pathComponents.count >= 3 {
                                                            capacityIds.insert(pathComponents[2])
                                                        }
                                                    } else {
                                                        capacityIds.insert(capacityStr)
                                                    }
                                                } else if let capacityRef = capacityData as? DocumentReference {
                                                    capacityIds.insert(capacityRef.documentID)
                                                }
                                            }
                                            
                                            if let colorData = data["color"] {
                                                if let colorStr = colorData as? String {
                                                    if colorStr.hasPrefix("/Colors/") {
                                                        let pathComponents = colorStr.components(separatedBy: "/")
                                                        if pathComponents.count >= 3 {
                                                            colorIds.insert(pathComponents[2])
                                                        }
                                                    } else {
                                                        colorIds.insert(colorStr)
                                                    }
                                                } else if let colorRef = colorData as? DocumentReference {
                                                    colorIds.insert(colorRef.documentID)
                                                }
                                            }
                                            
                                            if let carrierData = data["carrier"] {
                                                if let carrierStr = carrierData as? String {
                                                    if carrierStr.hasPrefix("/Carriers/") {
                                                        let pathComponents = carrierStr.components(separatedBy: "/")
                                                        if pathComponents.count >= 3 {
                                                            carrierIds.insert(pathComponents[2])
                                                        }
                                                    } else {
                                                        carrierIds.insert(carrierStr)
                                                    }
                                                } else if let carrierRef = carrierData as? DocumentReference {
                                                    carrierIds.insert(carrierRef.documentID)
                                                }
                                            }
                                        }
                                        
                                        print("loadDevices: Found \(filteredPhoneDocuments.count) devices at selected storage location")
                                        print("loadDevices: Collected \(capacityIds.count) capacity IDs, \(colorIds.count) color IDs, \(carrierIds.count) carrier IDs")
                                        
                                        // Fetch all reference names asynchronously
                                        self.fetchReferenceNames(
                                            capacityIds: Array(capacityIds),
                                            colorIds: Array(colorIds),
                                            carrierIds: Array(carrierIds),
                                            phoneDocuments: filteredPhoneDocuments
                                        )
                                    }
                                }
                        }
                    }
                }
            }
    }
    
    private func getBrandDocumentId(for brandName: String, completion: @escaping (String?) -> Void) {
        print("getBrandDocumentId: Looking for brand: \(brandName)")
        let db = Firestore.firestore()
        db.collection("PhoneBrands")
            .whereField("brand", isEqualTo: brandName)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error resolving brand document for '\(brandName)': \(error)")
                    completion(nil)
                    return
                }
                guard let doc = snapshot?.documents.first else {
                    print("No brand document found for name: \(brandName)")
                    completion(nil)
                    return
                }
                print("getBrandDocumentId: Found brand document ID: \(doc.documentID)")
                completion(doc.documentID)
            }
    }
    
    private func addNewBrand(_ name: String) {
        isAddingBrand = true
        let db = Firestore.firestore()
        
        db.collection("PhoneBrands").addDocument(data: ["brand": name]) { error in
            DispatchQueue.main.async {
                self.isAddingBrand = false
                if let error = error {
                    print("Error adding brand: \(error)")
                    return
                }
                
                self.phoneBrands.append(name)
                self.phoneBrands.sort()
                self.selectedBrand = name
                self.brandSearchText = name
                self.showingBrandDropdown = false
                
                // Load models for the new brand
                self.fetchPhoneModels()
            }
        }
    }
    
    private func addNewModel(_ name: String) {
        guard !selectedBrand.isEmpty else {
            print("Cannot add model: no brand selected")
            return
        }

        isAddingModel = true
        let modelName = name
        
        getBrandDocumentId(for: selectedBrand) { brandDocId in
            let db = Firestore.firestore()
            DispatchQueue.main.async {
                guard let brandDocId = brandDocId else {
                    self.isAddingModel = false
                    print("Cannot add model: brand document not found for \(self.selectedBrand)")
                    return
                }
                db.collection("PhoneBrands")
                    .document(brandDocId)
                    .collection("Models")
                    .addDocument(data: [
                        "model": modelName
                    ]) { error in
                        DispatchQueue.main.async {
                            // Hide loading overlay
                            self.isAddingModel = false
                            
                            if let error = error {
                                print("Error adding model: \(error)")
                                return
                            }
                            
                            // Add to local array
                            self.phoneModels.append(modelName)
                            self.phoneModels.sort()
                            self.selectedModel = modelName
                            self.modelSearchText = modelName
                            self.showingModelDropdown = false
                            
                            // Load storage locations for the new model
                            self.fetchStorageLocations()
                        }
                    }
            }
        }
    }
    
    private func addNewStorageLocation(_ name: String) {
        isAddingStorageLocation = true
        let db = Firestore.firestore()
        
        db.collection("StorageLocations").addDocument(data: ["storageLocation": name]) { error in
            DispatchQueue.main.async {
                self.isAddingStorageLocation = false
                if let error = error {
                    print("Error adding storage location: \(error)")
                    return
                }
                
                self.storageLocations.append(name)
                self.storageLocations.sort()
                self.selectedStorageLocation = name
                self.storageLocationSearchText = name
                self.showingStorageLocationDropdown = false
                
                // Load devices for the new location
                self.loadDevices()
            }
        }
    }
}

// MARK: - Device Filtering Table
struct DeviceFilteringTable: View {
    @Binding var devices: [SalesAddProductDialog.DeviceInfo]
    @Binding var selectedCapacity: String
    @Binding var selectedColor: String
    @Binding var selectedIMEIs: Set<String>
    @Binding var showActiveOnly: Bool
    
    private var uniqueCapacities: [String] {
        Array(Set(devices.map { $0.capacity })).sorted()
    }
    
    private var uniqueColors: [String] {
        Array(Set(devices.map { $0.color })).sorted()
    }
    
    private var filteredIMEIs: [SalesAddProductDialog.DeviceInfo] {
        var filtered = devices
        
        // Apply active filter first
        if showActiveOnly {
            filtered = filtered.filter { $0.status == "Active" }
        }
        
        // If both capacity and color are selected, show only IMEIs that match both
        if !selectedCapacity.isEmpty && !selectedColor.isEmpty {
            filtered = filtered.filter { $0.capacity == selectedCapacity && $0.color == selectedColor }
        } else if !selectedCapacity.isEmpty {
            filtered = filtered.filter { $0.capacity == selectedCapacity }
        } else if !selectedColor.isEmpty {
            filtered = filtered.filter { $0.color == selectedColor }
        }
        
        return filtered
    }
    
    private var filteredCapacities: [String] {
        if selectedColor.isEmpty {
            return uniqueCapacities
        } else {
            return Array(Set(devices.filter { $0.color == selectedColor }.map { $0.capacity })).sorted()
        }
    }
    
    private var filteredColors: [String] {
        if selectedCapacity.isEmpty {
            return uniqueColors
        } else {
            return Array(Set(devices.filter { $0.capacity == selectedCapacity }.map { $0.color })).sorted()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tableHeader
            tableContainer
        }
    }
    
    private var tableHeader: some View {
        HStack {
            Spacer()
            
            Text("Available Devices")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            if !selectedIMEIs.isEmpty {
                Text("\(selectedIMEIs.count) selected")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
    
    private var tableContainer: some View {
        HStack(alignment: .top, spacing: 0) {
            capacityColumn
            colorColumn
            imeiColumn
        }
        .background(tableBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    
    private var tableBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var capacityColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader(title: "Capacity")
            capacityContent
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1),
            alignment: .trailing
        )
    }
    
    private var colorColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader(title: "Color")
            colorContent
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1),
            alignment: .trailing
        )
    }
    
    private var imeiColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            deviceColumnHeader
            imeiContent
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
    
    private func columnHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(Color.secondary.opacity(0.08))
        )
    }
    
    private var deviceColumnHeader: some View {
        HStack {
            Text("Device (IMEI/Carrier)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                showActiveOnly.toggle()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: showActiveOnly ? "checkmark.square.fill" : "square")
                        .foregroundColor(showActiveOnly ? .blue : .secondary)
                        .font(.system(size: 12))
                    
                    Text("Active only")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(Color.secondary.opacity(0.08))
        )
    }
    
    private var capacityContent: some View {
                    ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredCapacities, id: \.self) { capacity in
                    let capacityUnit = devices.first(where: { $0.capacity == capacity })?.capacityUnit ?? ""
                                CapacityRow(
                                    capacity: capacity,
                        capacityUnit: capacityUnit,
                                    isSelected: selectedCapacity == capacity,
                                    onTap: {
                                        if selectedCapacity == capacity {
                                            selectedCapacity = ""
                                        } else {
                                            selectedCapacity = capacity
                                            selectedIMEIs.removeAll()
                                        }
                                    }
                                )
                            }
                        }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 400)
        .background(Color.primary.opacity(0.02))
    }
    
    private var colorContent: some View {
                    ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredColors, id: \.self) { color in
                                ColorRow(
                                    color: color,
                                    isSelected: selectedColor == color,
                                    onTap: {
                                        if selectedColor == color {
                                            selectedColor = ""
                                        } else {
                                            selectedColor = color
                                            selectedIMEIs.removeAll()
                                        }
                                    }
                                )
                            }
                        }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 400)
        .background(Color.primary.opacity(0.02))
    }
    
    private var imeiContent: some View {
                    ScrollView {
            LazyVStack(spacing: 2) {
                            ForEach(filteredIMEIs, id: \.imei) { device in
                                IMEIRow(
                                    device: device,
                                    isSelected: selectedIMEIs.contains(device.imei),
                                    onTap: {
                                        if selectedIMEIs.contains(device.imei) {
                                            selectedIMEIs.remove(device.imei)
                                        } else {
                                                selectedIMEIs.insert(device.imei)
                                        }
                                    }
                                )
                            }
                        }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 400)
        .background(Color.primary.opacity(0.02))
    }
}

// MARK: - Row Components
struct CapacityRow: View {
    let capacity: String
    let capacityUnit: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
            HStack {
            HStack(spacing: 4) {
                Text(capacity)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(capacityUnit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .medium))
                }
            }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

struct ColorRow: View {
    let color: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
            HStack {
                Text(color)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .medium))
                }
            }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.green : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.green : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

struct IMEIRow: View {
    let device: SalesAddProductDialog.DeviceInfo
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        mainContent
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
    }
    
    private var mainContent: some View {
        HStack(spacing: 12) {
            deviceInfoSection
            rightSection
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(backgroundView)
        .overlay(borderView)
        .shadow(color: shadowColor, radius: 2, x: 0, y: 1)
    }
    
    private var deviceInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            imeiText
            carrierText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var imeiText: some View {
                Text(device.imei)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundColor(isSelected ? .white : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
    
    private var carrierText: some View {
                Text(device.carrier)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            .lineLimit(1)
    }
    
    private var rightSection: some View {
        HStack(spacing: 8) {
            pricePill
            statusPill
            selectionIndicator
        }
    }
    
    private var pricePill: some View {
        Text("$\(String(format: "%.0f", device.unitPrice))")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(priceBackground)
            .overlay(priceBorder)
    }
    
    private var priceBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? Color.white.opacity(0.2) : Color.blue.opacity(0.15))
    }
    
    private var priceBorder: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(isSelected ? Color.white.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1)
    }
    
    private var statusPill: some View {
        Text(device.status)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(device.status == "Active" ? .white : .black)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(statusBackground)
    }
    
    private var statusBackground: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(device.status == "Active" ? Color.green : Color.orange)
    }
    
    @ViewBuilder
    private var selectionIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .medium))
        }
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.blue : Color.clear)
    }
    
    private var borderView: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: 0.5)
    }
    
    private var shadowColor: Color {
        isSelected ? Color.blue.opacity(0.3) : Color.clear
    }
}

// MARK: - Dropdown Field Components (using exact same implementation as AddProductDialog)
struct BrandDropdownField: View {
    @Binding var searchText: String
    @Binding var selectedBrand: String
    @Binding var showingDropdown: Bool
    @Binding var buttonFrame: CGRect
    let brands: [String]
    let isLoading: Bool
    @FocusState.Binding var isFocused: Bool
    @Binding var internalSearchText: String
    @Binding var isAddingBrand: Bool
    let onAddBrand: (String) -> Void
    let onBrandSelected: (String) -> Void
    
    var body: some View {
        ZStack {
            // Main TextField with padding for the button
            TextField("Choose an option", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 18, weight: .medium))
                .focused($isFocused)
                .padding(.horizontal, 20)
                .padding(.trailing, 120) // Extra padding for unit buttons and dropdown button area
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                )
                .submitLabel(.done)
                .onSubmit {
                    isFocused = false
                }
            
            // Separate button positioned on the right
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 20)
                } else {
                    Button(action: {
                        print("Brand dropdown button clicked, isOpen before: \(showingDropdown)")
                        withAnimation {
                            showingDropdown.toggle()
                        }
                        print("Brand dropdown button clicked, isOpen after: \(showingDropdown)")
                        if showingDropdown {
                            isFocused = false
                        }
                    }) {
                        Image(systemName: showingDropdown ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .frame(width: 40, height: 40) // Larger clickable area
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { isHovering in
                        #if os(macOS)
                        if isHovering {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                        #endif
                    }
                    .padding(.trailing, 10)
                }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame = geometry.frame(in: .global)
                        print("Brand button frame captured: \(buttonFrame)")
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        buttonFrame = newFrame
                    }
            }
        )
        .onTapGesture {
            withAnimation {
                showingDropdown.toggle()
            }
            if showingDropdown {
                isFocused = false
            }
        }
        .onChange(of: searchText) { newValue in
            // Sync internal search with display text
            internalSearchText = newValue
            if !newValue.isEmpty && !showingDropdown && newValue != selectedBrand {
                showingDropdown = true
            }
        }
        .onChange(of: showingDropdown) { newValue in
            // Clear internal search when opening dropdown to show full list
            if newValue {
                internalSearchText = ""
            }
        }
        .onChange(of: isFocused) { focused in
            print("Brand field focus changed: \(focused), isOpen: \(showingDropdown)")
            if focused && !showingDropdown {
                print("Setting isOpen to true due to focus")
                showingDropdown = true
            }
        }
        #if os(iOS)
        .overlay(
            Group {
                if showingDropdown {
                    SalesBrandDropdownOverlay(
                        isOpen: $showingDropdown,
                        selectedBrand: $selectedBrand,
                        searchText: $searchText,
                        internalSearchText: $internalSearchText,
                        brands: brands,
                        buttonFrame: buttonFrame,
                        onAddBrand: onAddBrand,
                        onRenameBrand: { _, _ in },
                        onBrandSelected: onBrandSelected
                    )
                }
            }
        )
        #endif
    }
}

struct ModelDropdownField: View {
    @Binding var searchText: String
    @Binding var selectedModel: String
    @Binding var showingDropdown: Bool
    @Binding var buttonFrame: CGRect
    let models: [String]
    let isLoading: Bool
    @FocusState.Binding var isFocused: Bool
    @Binding var internalSearchText: String
    @Binding var isAddingModel: Bool
    let isEnabled: Bool
    let onAddModel: (String) -> Void
    let onModelSelected: (String) -> Void
    
    var body: some View {
        ZStack {
            // Main TextField with padding for the button
            TextField("Choose a model", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 18, weight: .medium))
                .focused($isFocused)
                .padding(.horizontal, 20)
                .padding(.trailing, 120) // Extra padding for dropdown button area
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .opacity(isEnabled ? 1.0 : 0.5)
                )
                .disabled(!isEnabled)
                .submitLabel(.done)
                .onSubmit {
                    isFocused = false
                }
                .onChange(of: searchText) { newValue in
                    if !newValue.isEmpty && !showingDropdown && newValue != selectedModel && isEnabled {
                        showingDropdown = true
                    }
                    internalSearchText = newValue
                }
            
            // Separate button positioned on the right
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 20)
                } else {
                    Button(action: {
                        print("Model dropdown button clicked, isEnabled: \(isEnabled), isOpen before: \(showingDropdown)")
                        print("Models available: \(models.count), isLoading: \(isLoading)")
                        if isEnabled {
                            withAnimation {
                                showingDropdown.toggle()
                            }
                            print("Model dropdown button clicked, isOpen after: \(showingDropdown)")
                            if showingDropdown {
                                isFocused = false
                            }
                        } else {
                            print("Model dropdown button clicked but disabled")
                        }
                    }) {
                        Image(systemName: showingDropdown ? "chevron.up" : "chevron.down")
                            .foregroundColor(isEnabled ? .secondary : .secondary.opacity(0.5))
                            .font(.system(size: 14))
                            .frame(width: 40, height: 40) // Larger clickable area
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!isEnabled)
                    .onHover { isHovering in
                        #if os(macOS)
                        if isHovering && isEnabled {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                        #endif
                    }
                }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame = geometry.frame(in: .global)
                        print("Model button frame captured: \(buttonFrame)")
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        buttonFrame = newFrame
                    }
            }
        )
        .onTapGesture {
            if isEnabled {
                withAnimation {
                    showingDropdown.toggle()
                }
                if showingDropdown {
                    isFocused = false
                }
            }
        }
        .onChange(of: searchText) { newValue in
            // Sync internal search with display text
            internalSearchText = newValue
            if !newValue.isEmpty && !showingDropdown && newValue != selectedModel && isEnabled {
                showingDropdown = true
            }
        }
        .onChange(of: showingDropdown) { newValue in
            // Clear internal search when opening dropdown to show full list
            if newValue {
                internalSearchText = ""
            }
        }
        .onChange(of: isFocused) { focused in
            print("Model field focus changed: \(focused), isOpen: \(showingDropdown)")
            if focused && !showingDropdown && isEnabled {
                print("Setting isOpen to true due to focus")
                showingDropdown = true
            }
        }
        #if os(iOS)
        .overlay(
            Group {
                if showingDropdown && isEnabled {
                    SalesModelDropdownOverlay(
                        isOpen: $showingDropdown,
                        selectedModel: $selectedModel,
                        models: models,
                        buttonFrame: buttonFrame,
                        searchText: $searchText,
                        internalSearchText: $internalSearchText,
                        isAddingModel: $isAddingModel,
                        onAddModel: onAddModel,
                        onModelSelected: onModelSelected
                    )
                }
            }
        )
        #endif
        .onAppear {
            print("ModelDropdownField appeared - isEnabled: \(isEnabled), models count: \(models.count)")
        }
        .onChange(of: models) { newModels in
            print("ModelDropdownField - models changed: count = \(newModels.count), models = \(newModels)")
        }
    }
}

struct StorageLocationDropdownField: View {
    @Binding var searchText: String
    @Binding var selectedStorageLocation: String
    @Binding var showingDropdown: Bool
    @Binding var buttonFrame: CGRect
    let storageLocations: [String]
    let isLoading: Bool
    @FocusState.Binding var isFocused: Bool
    @Binding var internalSearchText: String
    @Binding var isAddingStorageLocation: Bool
    let isEnabled: Bool
    let onAddStorageLocation: (String) -> Void
    let onStorageLocationSelected: (String) -> Void
    
    var body: some View {
        ZStack {
            // Main TextField with padding for the button
            TextField("Choose storage location", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 18, weight: .medium))
                .focused($isFocused)
                .padding(.horizontal, 20)
                .padding(.trailing, 120) // Extra padding for dropdown button area
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .opacity(isEnabled ? 1.0 : 0.5)
                )
                .disabled(!isEnabled)
                .submitLabel(.done)
                .onSubmit {
                    isFocused = false
                }
                .onChange(of: searchText) { newValue in
                    if !newValue.isEmpty && !showingDropdown && newValue != selectedStorageLocation && isEnabled {
                        showingDropdown = true
                    }
                    internalSearchText = newValue
                }
            
            // Separate button positioned on the right
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 20)
                } else {
                    Button(action: {
                        if isEnabled {
                            print("Storage location dropdown button clicked, isOpen before: \(showingDropdown)")
                            withAnimation {
                                showingDropdown.toggle()
                            }
                            print("Storage location dropdown button clicked, isOpen after: \(showingDropdown)")
                            if showingDropdown {
                                isFocused = false
                            }
                        }
                    }) {
                        Image(systemName: showingDropdown ? "chevron.up" : "chevron.down")
                            .foregroundColor(isEnabled ? .secondary : .secondary.opacity(0.5))
                            .font(.system(size: 14))
                            .frame(width: 40, height: 40) // Larger clickable area
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!isEnabled)
                    .onHover { isHovering in
                        #if os(macOS)
                        if isHovering && isEnabled {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                        #endif
                    }
                }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame = geometry.frame(in: .global)
                        print("Storage location button frame captured: \(buttonFrame)")
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        buttonFrame = newFrame
                    }
            }
        )
        .onTapGesture {
            if isEnabled {
                withAnimation {
                    showingDropdown.toggle()
                }
                if showingDropdown {
                    isFocused = false
                }
            }
        }
        .onChange(of: searchText) { newValue in
            // Sync internal search with display text
            internalSearchText = newValue
            if !newValue.isEmpty && !showingDropdown && newValue != selectedStorageLocation && isEnabled {
                showingDropdown = true
            }
        }
        .onChange(of: showingDropdown) { newValue in
            // Clear internal search when opening dropdown to show full list
            if newValue {
                internalSearchText = ""
            }
        }
        .onChange(of: isFocused) { focused in
            print("Storage location field focus changed: \(focused), isOpen: \(showingDropdown)")
            if focused && !showingDropdown && isEnabled {
                print("Setting isOpen to true due to focus")
                showingDropdown = true
            }
        }
        #if os(iOS)
        .overlay(
            Group {
                if showingDropdown && isEnabled {
                    SalesStorageLocationDropdownOverlay(
                        isOpen: $showingDropdown,
                        selectedStorageLocation: $selectedStorageLocation,
                        searchText: $searchText,
                        internalSearchText: $internalSearchText,
                        storageLocations: storageLocations,
                        buttonFrame: buttonFrame,
                        onAddStorageLocation: onAddStorageLocation,
                        onRenameStorageLocation: { _, _ in },
                        onStorageLocationSelected: onStorageLocationSelected
                    )
                }
            }
        )
        #endif
    }
}

// MARK: - Brand Dropdown Overlay (exact copy from AddProductDialog)
struct SalesBrandDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedBrand: String
    @Binding var searchText: String
    @Binding var internalSearchText: String
    let brands: [String]
    let buttonFrame: CGRect
    let onAddBrand: (String) -> Void
    let onRenameBrand: (String, String) -> Void
    let onBrandSelected: (String) -> Void
    
    private var filteredBrands: [String] {
        print("BrandDropdownOverlay - Total brands: \(brands.count), brands: \(brands)")
        print("BrandDropdownOverlay - Internal search text: '\(internalSearchText)'")
        
        if internalSearchText.isEmpty {
            let allBrands = brands.sorted()
            print("BrandDropdownOverlay - Showing all brands: \(allBrands)")
            return allBrands // Show all brands sorted alphabetically when no search text
        } else {
            let filtered = brands.filter { brand in
                brand.localizedCaseInsensitiveContains(internalSearchText)
            }.sorted()
            print("BrandDropdownOverlay - Filtered brands: \(filtered)")
            return filtered
        }
    }
    
    private var shouldShowAddOption: Bool {
        return !internalSearchText.isEmpty && !brands.contains { $0.localizedCaseInsensitiveCompare(internalSearchText) == .orderedSame }
    }
    
    var body: some View {
        Group {
            #if os(iOS)
            // Inline dropdown that pushes content down (iOS only)
            inlineDropdown
                .sheet(isPresented: $showEditNameSheet) {
                    EditNameSheet(
                        title: "Edit Brand",
                        text: $editNewName,
                        onCancel: { showEditNameSheet = false },
                        onSave: { commitEdit() }
                    )
                }
            #else
            // Positioned dropdown for macOS
            positionedDropdown
                .sheet(isPresented: $showEditNameSheet) {
                    EditNameSheet(
                        title: "Edit Brand",
                        text: $editNewName,
                        onCancel: { showEditNameSheet = false },
                        onSave: { commitEdit() }
                    )
                }
            #endif
        }
        .onAppear {
            print("BrandDropdownOverlay appeared with \(brands.count) brands: \(brands)")
            print("BrandDropdownOverlay buttonFrame: \(buttonFrame)")
        }
    }
    
    // MARK: - Inline Dropdown
    private var inlineDropdown: some View {
        VStack(spacing: 0) {
            // Add brand option (if applicable)
            if shouldShowAddOption {
                VStack(spacing: 0) {
                    cleanBrandRow(
                        title: "Add '\(internalSearchText)'",
                        isAddOption: true,
                        action: {
                            isOpen = false
                            onAddBrand(internalSearchText)
                        }
                    )
                    
                    // Separator after add option
                    if !filteredBrands.isEmpty {
                        Divider()
                            .background(Color.secondary.opacity(0.4))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }
                }
            }
            
            // Existing brands - always use ScrollView for consistency
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredBrands.enumerated()), id: \.element) { index, brand in
                        VStack(spacing: 0) {
                            cleanBrandRow(
                                title: brand,
                                isAddOption: false,
                                action: {
                                    print("Selected brand: \(brand)")
                                    isOpen = false
                                    selectedBrand = brand
                                    searchText = brand
                                    onBrandSelected(brand)
                                }
                            )
                            .onAppear {
                                print("Rendering brand row: \(brand)")
                            }
                            
                            // Subtle separator between items
                            if index < filteredBrands.count - 1 {
                                Divider()
                                    .background(Color.secondary.opacity(0.4))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: dynamicDropdownHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isOpen)
    }
    
    private var dynamicDropdownHeight: CGFloat {
        let itemHeight: CGFloat = 50
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let brandCount = filteredBrands.count
        
        if brandCount <= 4 {
            // For small lists, calculate exact height
            let brandHeight = CGFloat(brandCount) * itemHeight
            let totalHeight = addOptionHeight + brandHeight
            return min(totalHeight, 240)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (4 * itemHeight), 240)
        }
    }
    
    // MARK: - Positioned Dropdown
    private var positionedDropdown: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Add brand option (if applicable)
                if shouldShowAddOption {
                    VStack(spacing: 0) {
                        cleanBrandRow(
                            title: "Add '\(internalSearchText)'",
                            isAddOption: true,
                            action: {
                                isOpen = false
                                onAddBrand(internalSearchText)
                            }
                        )
                        
                        // Separator after add option
                        if !filteredBrands.isEmpty {
                            Divider()
                                .background(Color.secondary.opacity(0.4))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                
                // Existing brands in ScrollView (macOS only)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredBrands.enumerated()), id: \.element) { index, brand in
                            VStack(spacing: 0) {
                                cleanBrandRow(
                                    title: brand,
                                    isAddOption: false,
                                    action: {
                                        print("Selected brand: \(brand)")
                                        isOpen = false
                                        selectedBrand = brand
                                        searchText = brand
                                        onBrandSelected(brand)
                                    }
                                )
                                .onAppear {
                                    print("Rendering brand row: \(brand)")
                                }
                                
                                // Divider between items
                                if index < filteredBrands.count - 1 {
                                    Divider()
                                        .background(Color.secondary.opacity(0.4))
                                        .frame(height: 0.5)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: dynamicMacOSDropdownHeight)
            .background(.regularMaterial)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .frame(width: buttonFrame.width)
            .offset(
                x: buttonFrame.minX,
                y: buttonFrame.maxY + 5
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(true)
    }
    
    // MARK: - Dynamic Height Calculation (macOS)
    private var dynamicMacOSDropdownHeight: CGFloat {
        let itemHeight: CGFloat = 48
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let brandCount = filteredBrands.count
        
        if brandCount <= 4 {
            // For small lists, calculate exact height
            let brandHeight = CGFloat(brandCount) * itemHeight
            let totalHeight = addOptionHeight + brandHeight
            return min(totalHeight, 240)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (4 * itemHeight), 240)
        }
    }
    
    // MARK: - Brand Row Views
    
    private func cleanBrandRow(title: String, isAddOption: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    if isAddOption {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40))
                            .font(.system(size: 16, weight: .medium))
                    }
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isAddOption ? Color(red: 0.20, green: 0.60, blue: 0.40) : .primary)
                        .fontWeight(isAddOption ? .semibold : .medium)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            
            if !isAddOption && selectedBrand == title {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40))
                    .font(.system(size: 16, weight: .medium))
            }
            if !isAddOption {
                Button(action: { presentEdit(for: title) }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.primary)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Edit item")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 50)
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }

    @State private var showEditNameSheet = false
    @State private var editOriginalName = ""
    @State private var editNewName = ""
    
    private func presentEdit(for name: String) {
        editOriginalName = name
        editNewName = name
        showEditNameSheet = true
    }
    
    private func commitEdit() {
        guard !editNewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let trimmedNew = editNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNew != editOriginalName {
            onRenameBrand(editOriginalName, trimmedNew)
        }
        showEditNameSheet = false
    }
}


// MARK: - Model Dropdown Overlay
struct SalesModelDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedModel: String
    let models: [String]
    let buttonFrame: CGRect
    @Binding var searchText: String
    @Binding var internalSearchText: String
    @Binding var isAddingModel: Bool
    let onAddModel: (String) -> Void
    let onModelSelected: (String) -> Void
    
    private var platformBackgroundColor: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    private var filteredModels: [String] {
        print("SalesModelDropdownOverlay - Total models: \(models.count), models: \(models)")
        print("SalesModelDropdownOverlay - Internal search text: '\(internalSearchText)'")
        
        if internalSearchText.isEmpty {
            let allModels = models.sorted()
            print("SalesModelDropdownOverlay - Showing all models: \(allModels)")
            return allModels
        } else {
            let filtered = models.filter { $0.localizedCaseInsensitiveContains(internalSearchText) }.sorted()
            print("SalesModelDropdownOverlay - Filtered models: \(filtered)")
            return filtered
        }
    }
    
    private var shouldShowAddOption: Bool {
        !internalSearchText.isEmpty && !filteredModels.contains(internalSearchText)
    }
    
    var body: some View {
        Group {
            #if os(iOS)
            // Inline dropdown that pushes content down (iOS only)
            inlineDropdown
            #else
            // Positioned dropdown for macOS
            positionedDropdown
            #endif
        }
        .onAppear {
            print("SalesModelDropdownOverlay appeared with \(models.count) models: \(models)")
            print("SalesModelDropdownOverlay buttonFrame: \(buttonFrame)")
        }
    }
    
    // MARK: - Inline Dropdown
    private var inlineDropdown: some View {
        VStack(spacing: 0) {
            // Add model option (if applicable)
            if shouldShowAddOption {
                VStack(spacing: 0) {
                    cleanModelRow(
                        title: "Add '\(internalSearchText)'",
                        isAddOption: true,
                        action: {
                        isOpen = false
                            onAddModel(internalSearchText)
                        }
                    )
                    
                    // Separator after add option
                    if !filteredModels.isEmpty {
                        Divider()
                            .background(Color.secondary.opacity(0.4))
                            .frame(height: 0.5)
                        .padding(.horizontal, 16)
                    }
                }
            }
            
            // Existing models - always use ScrollView for consistency
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredModels.enumerated()), id: \.element) { index, model in
                        VStack(spacing: 0) {
                            cleanModelRow(
                                title: model,
                                isAddOption: false,
                                action: {
                                    print("Selected model: \(model)")
                                    isOpen = false
                                    onModelSelected(model)
                                }
                            )
                            .onAppear {
                                print("Rendering model row: \(model)")
                            }
                            
                            // Subtle separator between items
                            if index < filteredModels.count - 1 {
                        Divider()
                                    .background(Color.secondary.opacity(0.4))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: dynamicDropdownHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isOpen)
    }
    
    // MARK: - Positioned Dropdown
    private var positionedDropdown: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Add model option (if applicable)
                if shouldShowAddOption {
                    VStack(spacing: 0) {
                        cleanModelRow(
                            title: "Add '\(internalSearchText)'",
                            isAddOption: true,
                            action: {
                    isOpen = false
                                onAddModel(internalSearchText)
                            }
                        )
                        
                        // Separator after add option
                        if !filteredModels.isEmpty {
                            Divider()
                                .background(Color.secondary.opacity(0.4))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                
                // Existing models in ScrollView (macOS only)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredModels.enumerated()), id: \.element) { index, model in
                            VStack(spacing: 0) {
                                cleanModelRow(
                                    title: model,
                                    isAddOption: false,
                                    action: {
                                        print("Selected model: \(model)")
                                        isOpen = false
                                        onModelSelected(model)
                                    }
                                )
                                .onAppear {
                                    print("Rendering model row: \(model)")
                                }
                                
                                // Divider between items
                                if index < filteredModels.count - 1 {
                                    Divider()
                                        .background(Color.secondary.opacity(0.4))
                                        .frame(height: 0.5)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: dynamicMacOSDropdownHeight)
            .background(.regularMaterial)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .frame(width: buttonFrame.width)
            .offset(
                x: buttonFrame.minX,
                y: buttonFrame.maxY + 5
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(true)
    }
    
    // MARK: - Dynamic Height Calculation
    private var dynamicDropdownHeight: CGFloat {
        let itemHeight: CGFloat = 50
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let modelCount = filteredModels.count
        
        if modelCount <= 4 {
            // For small lists, calculate exact height
            let modelHeight = CGFloat(modelCount) * itemHeight
            let totalHeight = addOptionHeight + modelHeight
            return min(totalHeight, 240)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (4 * itemHeight), 240)
        }
    }
    
    // MARK: - Dynamic Height Calculation (macOS)
    private var dynamicMacOSDropdownHeight: CGFloat {
        let itemHeight: CGFloat = 48
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let modelCount = filteredModels.count
        
        if modelCount <= 4 {
            // For small lists, calculate exact height
            let modelHeight = CGFloat(modelCount) * itemHeight
            let totalHeight = addOptionHeight + modelHeight
            return min(totalHeight, 240)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (4 * itemHeight), 240)
        }
    }
    
    // MARK: - Model Row Views
    
    private func cleanModelRow(title: String, isAddOption: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    if isAddOption {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40))
                            .font(.system(size: 16, weight: .medium))
                    }
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isAddOption ? Color(red: 0.20, green: 0.60, blue: 0.40) : .primary)
                        .fontWeight(isAddOption ? .semibold : .medium)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            
            if !isAddOption {
                Button(action: {
                    presentEdit(for: title)
                }) {
                    Image(systemName: "pencil")
                            .foregroundColor(.primary)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Edit item")
            }
                    }
                    .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 50)
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }

    @State private var showEditNameSheet = false
    @State private var editOriginalName = ""
    @State private var editNewName = ""
    
    private func presentEdit(for name: String) {
        editOriginalName = name
        editNewName = name
        showEditNameSheet = true
    }
    
    private func commitEdit() {
        guard !editNewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let trimmedNew = editNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // TODO: Implement model rename functionality
        print("Rename model from '\(editOriginalName)' to '\(trimmedNew)'")
        
        showEditNameSheet = false
    }
}

// MARK: - Storage Location Dropdown Overlay (exact copy from AddProductDialog pattern)
struct SalesStorageLocationDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedStorageLocation: String
    @Binding var searchText: String
    @Binding var internalSearchText: String
    let storageLocations: [String]
    let buttonFrame: CGRect
    let onAddStorageLocation: (String) -> Void
    let onRenameStorageLocation: (String, String) -> Void
    let onStorageLocationSelected: (String) -> Void
    
    private var filteredStorageLocations: [String] {
        print("StorageLocationDropdownOverlay - Total locations: \(storageLocations.count), locations: \(storageLocations)")
        print("StorageLocationDropdownOverlay - Internal search text: '\(internalSearchText)'")
        
        if internalSearchText.isEmpty {
            let allLocations = storageLocations.sorted()
            print("StorageLocationDropdownOverlay - Showing all locations: \(allLocations)")
            return allLocations // Show all locations sorted alphabetically when no search text
        } else {
            let filtered = storageLocations.filter { location in
                location.localizedCaseInsensitiveContains(internalSearchText)
            }.sorted()
            print("StorageLocationDropdownOverlay - Filtered locations: \(filtered)")
            return filtered
        }
    }
    
    private var shouldShowAddOption: Bool {
        return !internalSearchText.isEmpty && !storageLocations.contains { $0.localizedCaseInsensitiveCompare(internalSearchText) == .orderedSame }
    }
    
    var body: some View {
        Group {
            #if os(iOS)
            // Inline dropdown that pushes content down (iOS only)
            inlineDropdown
                .sheet(isPresented: $showEditNameSheet) {
                    EditNameSheet(
                        title: "Edit Storage Location",
                        text: $editNewName,
                        onCancel: { showEditNameSheet = false },
                        onSave: { commitEdit() }
                    )
                }
            #else
            // Positioned dropdown for macOS
            positionedDropdown
                .sheet(isPresented: $showEditNameSheet) {
                    EditNameSheet(
                        title: "Edit Storage Location",
                        text: $editNewName,
                        onCancel: { showEditNameSheet = false },
                        onSave: { commitEdit() }
                    )
                }
            #endif
        }
        .onAppear {
            print("StorageLocationDropdownOverlay appeared with \(storageLocations.count) locations: \(storageLocations)")
            print("StorageLocationDropdownOverlay buttonFrame: \(buttonFrame)")
        }
    }
    
    // MARK: - Inline Dropdown
    private var inlineDropdown: some View {
        VStack(spacing: 0) {
            // Add storage location option (if applicable)
            if shouldShowAddOption {
                VStack(spacing: 0) {
                    cleanStorageLocationRow(
                        title: "Add '\(internalSearchText)'",
                        isAddOption: true,
                        action: {
                            isOpen = false
                            onAddStorageLocation(internalSearchText)
                        }
                    )
                    
                    // Separator after add option
                    if !filteredStorageLocations.isEmpty {
                        Divider()
                            .background(Color.secondary.opacity(0.4))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }
                }
            }
            
            // Existing storage locations - always use ScrollView for consistency
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredStorageLocations.enumerated()), id: \.element) { index, location in
                        VStack(spacing: 0) {
                            cleanStorageLocationRow(
                                title: location,
                                isAddOption: false,
                                action: {
                                    print("Selected storage location: \(location)")
                                    isOpen = false
                                    selectedStorageLocation = location
                                    searchText = location
                                    onStorageLocationSelected(location)
                                }
                            )
                            .onAppear {
                                print("Rendering storage location row: \(location)")
                            }
                            
                            // Subtle separator between items
                            if index < filteredStorageLocations.count - 1 {
                                Divider()
                                    .background(Color.secondary.opacity(0.4))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: dynamicDropdownHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isOpen)
    }
    
    private var dynamicDropdownHeight: CGFloat {
        let itemHeight: CGFloat = 50
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let locationCount = filteredStorageLocations.count
        
        if locationCount <= 4 {
            // For small lists, calculate exact height
            let locationHeight = CGFloat(locationCount) * itemHeight
            let totalHeight = addOptionHeight + locationHeight
            return min(totalHeight, 240)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (4 * itemHeight), 240)
        }
    }
    
    // MARK: - Positioned Dropdown
    private var positionedDropdown: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Add storage location option (if applicable)
                if shouldShowAddOption {
                    VStack(spacing: 0) {
                        cleanStorageLocationRow(
                            title: "Add '\(internalSearchText)'",
                            isAddOption: true,
                            action: {
                                isOpen = false
                                onAddStorageLocation(internalSearchText)
                            }
                        )
                        
                        // Separator after add option
                        if !filteredStorageLocations.isEmpty {
                            Divider()
                                .background(Color.secondary.opacity(0.4))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                
                // Existing storage locations in ScrollView (macOS only)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredStorageLocations.enumerated()), id: \.element) { index, location in
                            VStack(spacing: 0) {
                                cleanStorageLocationRow(
                                    title: location,
                                    isAddOption: false,
                                    action: {
                                        print("Selected storage location: \(location)")
                                        isOpen = false
                                        selectedStorageLocation = location
                                        searchText = location
                                        onStorageLocationSelected(location)
                                    }
                                )
                                .onAppear {
                                    print("Rendering storage location row: \(location)")
                                }
                                
                                // Divider between items
                                if index < filteredStorageLocations.count - 1 {
                                    Divider()
                                        .background(Color.secondary.opacity(0.4))
                                        .frame(height: 0.5)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: dynamicMacOSDropdownHeight)
            .background(.regularMaterial)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .frame(width: buttonFrame.width)
            .offset(
                x: buttonFrame.minX,
                y: buttonFrame.maxY + 5
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(true)
    }
    
    // MARK: - Dynamic Height Calculation (macOS)
    private var dynamicMacOSDropdownHeight: CGFloat {
        let itemHeight: CGFloat = 48
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let locationCount = filteredStorageLocations.count
        
        if locationCount <= 4 {
            // For small lists, calculate exact height
            let locationHeight = CGFloat(locationCount) * itemHeight
            let totalHeight = addOptionHeight + locationHeight
            return min(totalHeight, 240)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (4 * itemHeight), 240)
        }
    }
    
    // MARK: - Storage Location Row Views
    
    private func cleanStorageLocationRow(title: String, isAddOption: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    if isAddOption {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40))
                            .font(.system(size: 16, weight: .medium))
                    }
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isAddOption ? Color(red: 0.20, green: 0.60, blue: 0.40) : .primary)
                        .fontWeight(isAddOption ? .semibold : .medium)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            
            if !isAddOption && selectedStorageLocation == title {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40))
                    .font(.system(size: 16, weight: .medium))
            }
            if !isAddOption {
                Button(action: { presentEdit(for: title) }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.primary)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Edit item")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 50)
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }

    @State private var showEditNameSheet = false
    @State private var editOriginalName = ""
    @State private var editNewName = ""
    
    private func presentEdit(for name: String) {
        editOriginalName = name
        editNewName = name
        showEditNameSheet = true
    }
    
    private func commitEdit() {
        guard !editNewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let trimmedNew = editNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNew != editOriginalName {
            onRenameStorageLocation(editOriginalName, trimmedNew)
        }
        showEditNameSheet = false
    }
}

// MARK: - Confirmation Overlay
struct ConfirmationOverlay: View {
    let message: String
    @State private var showingCheckmark = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 80, height: 80)
                    
                    if showingCheckmark {
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                Text(message)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingCheckmark = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                // Auto-dismiss after 2 seconds
            }
        }
    }
}

