//
//  SalesEditProductDialog.swift
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

struct SalesEditProductDialog: View {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let onSave: (([PhoneItem]) -> Void)?
    let itemToEdit: PhoneItem // Required - this dialog is specifically for editing
    var existingCartItems: [PhoneItem] = [] // IMEIs already in cart to exclude
    
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
    @State private var filteredDevices: [SalesAddProductDialog.DeviceInfo] = []
    @State private var allDevices: [SalesAddProductDialog.DeviceInfo] = []
    @State private var isLoadingDevices = false
    
    // Loading and confirmation states
    @State private var showingConfirmation = false
    @State private var showingCloseConfirmation = false
    @State private var confirmationMessage = ""
    
    // Loading overlays
    @State private var isAddingBrand = false
    @State private var isAddingModel = false
    @State private var isAddingStorageLocation = false
    
    // Two-step process state
    @State private var currentStep: DialogStep = .imeiSelection
    @State private var selectedDevicesForPricing: [SalesAddProductDialog.DeviceInfo] = []
    @State private var deviceSellingPrices: [String: String] = [:] // IMEI -> Selling Price
    @State private var deviceProfitLoss: [String: Double] = [:] // IMEI -> Profit/Loss amount
    
    // Dialog step enum
    enum DialogStep {
        case imeiSelection
        case priceSetting
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
    
    // Always true for edit mode - we always have form data
    private var hasFormData: Bool {
        return true
    }
    
    // Enable Add Product when required fields are selected and prices are set
    private var isAddEnabled: Bool {
        switch currentStep {
        case .imeiSelection:
            return !selectedBrand.isEmpty &&
                   !selectedModel.isEmpty &&
                   !selectedStorageLocation.isEmpty &&
                   !selectedIMEIs.isEmpty
        case .priceSetting:
            // All selected devices must have selling prices set
            return !selectedDevicesForPricing.isEmpty &&
                   selectedDevicesForPricing.allSatisfy { device in
                       !deviceSellingPrices[device.imei, default: ""].isEmpty
                   }
        }
    }
    
    // Enable Next button when IMEIs are selected
    private var isNextEnabled: Bool {
        return currentStep == .imeiSelection && !selectedIMEIs.isEmpty
    }
    
    // Get IMEIs that are already in the cart (excluding the item being edited)
    private var cartIMEIs: Set<String> {
        Set(existingCartItems.filter { $0.id != itemToEdit.id }.flatMap { $0.imeis })
    }
    
    private var backgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(.systemBackground)
        #endif
    }
    
    // Computed property to get phone counts by location
    private var phoneCountsByLocation: [String: Int] {
        var counts: [String: Int] = [:]
        for device in allDevices {
            counts[device.storageLocation, default: 0] += 1
        }
        return counts
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
                                    Text("Edit Product")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Modify the product details")
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
                    if currentStep == .imeiSelection {
                        if !selectedBrand.isEmpty && !selectedModel.isEmpty && !selectedStorageLocation.isEmpty {
                            if isLoadingDevices {
                                // Loading indicator
                                VStack {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .padding(.bottom, 12)
                                    Text("Loading devices...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if !filteredDevices.isEmpty {
                                DeviceFilteringTable(
                                    devices: $filteredDevices,
                                    selectedBrand: $selectedBrand,
                                    selectedModel: $selectedModel,
                                    selectedCapacity: $selectedCapacity,
                                    selectedColor: $selectedColor,
                                    selectedIMEIs: $selectedIMEIs,
                                    showActiveOnly: $showActiveOnly,
                                    cartIMEIs: cartIMEIs
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 24)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                ))
                            } else {
                                // No devices found
                                VStack {
                                    Spacer()
                                    Text("No devices found")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
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
                    } else {
                        // Price setting interface
                        PriceSettingInterface(
                            selectedDevices: selectedDevicesForPricing,
                            deviceSellingPrices: $deviceSellingPrices,
                            deviceProfitLoss: $deviceProfitLoss
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
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
                    if currentStep == .imeiSelection {
                        Button("Next") {
                            proceedToPriceSetting()
                        }
                        .disabled(!isNextEnabled)
                    } else {
                        Button("Save") {
                            addProducts()
                        }
                        .disabled(!isAddEnabled)
                    }
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
        .onChange(of: selectedIMEIs.count) { count in
            // Restrict to only one IMEI in edit mode
            if count > 1 {
                // Keep only the first IMEI
                if let firstIMEI = selectedIMEIs.first {
                    selectedIMEIs = Set([firstIMEI])
                }
            }
        }
        .onAppear {
            prefillDataForEdit()
            fetchPhoneBrands()
        }
    }
    
    // MARK: - Desktop Dialog Components
    
    private var desktopDialogContent: some View {
        VStack(spacing: 0) {
            // Header
            desktopDialogHeader
            
            Divider()
            
            // Fixed Dropdown Row
            VStack(spacing: 24) {
                DesktopFormFields
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            
            Divider()
            
            // Fixed Table Area - fills remaining space
            desktopDialogTableArea
            
            Divider()
            
            // Footer
            desktopDialogFooter
        }
        .frame(width: 1200, height: 800) // Much larger dialog
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(radius: 20)
    }
    
    private var desktopDialogHeader: some View {
        HStack {
            Text("Edit Product")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            Button(action: {
                handleCloseAction()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
    
    private var desktopDialogTableArea: some View {
        Group {
            if currentStep == .imeiSelection {
                desktopImeiSelectionArea
            } else {
                desktopPriceSettingArea
            }
        }
    }
    
    private var desktopImeiSelectionArea: some View {
        Group {
            if !selectedBrand.isEmpty && !selectedModel.isEmpty && !selectedStorageLocation.isEmpty {
                if isLoadingDevices {
                    desktopLoadingView
                } else if !filteredDevices.isEmpty {
                    desktopDeviceTable
                } else {
                    desktopNoDevicesView
                }
            } else {
                desktopPlaceholderView
            }
        }
    }
    
    private var desktopPriceSettingArea: some View {
        PriceSettingInterface(
            selectedDevices: selectedDevicesForPricing,
            deviceSellingPrices: $deviceSellingPrices,
            deviceProfitLoss: $deviceProfitLoss
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        ))
    }
    
    private var desktopLoadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .padding(.bottom, 12)
            Text("Loading devices...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var desktopDeviceTable: some View {
        DeviceFilteringTable(
            devices: $filteredDevices,
            selectedBrand: $selectedBrand,
            selectedModel: $selectedModel,
            selectedCapacity: $selectedCapacity,
            selectedColor: $selectedColor,
            selectedIMEIs: $selectedIMEIs,
            showActiveOnly: $showActiveOnly,
            cartIMEIs: cartIMEIs
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        ))
    }
    
    private var desktopNoDevicesView: some View {
        VStack {
            Spacer()
            Text("No devices found")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var desktopPlaceholderView: some View {
        VStack {
            Spacer()
            Text("Select brand, model, and storage location to view devices")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var desktopDialogFooter: some View {
        HStack {
            if currentStep == .priceSetting {
                Button("Previous") {
                    goBackToImeiSelection()
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Button("Cancel") {
                    handleCloseAction()
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Spacer()
            
            if currentStep == .imeiSelection {
                Button("Next") {
                    proceedToPriceSetting()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isNextEnabled)
            } else {
                Button("Save Changes") {
                    addProducts()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isAddEnabled)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    var DesktopDialogView: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    handleCloseAction()
                }
            
            desktopDialogContent
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
        .onChange(of: selectedIMEIs.count) { count in
            // Restrict to only one IMEI in edit mode
            if count > 1 {
                // Keep only the first IMEI
                if let firstIMEI = selectedIMEIs.first {
                    selectedIMEIs = Set([firstIMEI])
                }
            }
        }
        .onAppear {
            print("DesktopDialogView appeared")
            prefillDataForEdit()
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
                    phoneCounts: phoneCountsByLocation,
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
                phoneCounts: phoneCountsByLocation,
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
                        phoneCounts: phoneCountsByLocation,
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
    
    private func prefillDataForEdit() {
        print("=== PREFILL DATA FOR EDIT ===")
        print("Brand: \(itemToEdit.brand)")
        print("Model: \(itemToEdit.model)")
        print("Storage: \(itemToEdit.storageLocation)")
        print("Capacity: \(itemToEdit.capacity)")
        print("Color: \(itemToEdit.color)")
        print("IMEI: \(itemToEdit.imeis.first ?? "none")")
        print("Selling Price (unitCost): \(itemToEdit.unitCost)")
        
        // Prefill the dialog with existing item data
        selectedBrand = itemToEdit.brand
        brandSearchText = itemToEdit.brand
        
        selectedModel = itemToEdit.model
        modelSearchText = itemToEdit.model
        
        selectedStorageLocation = itemToEdit.storageLocation
        storageLocationSearchText = itemToEdit.storageLocation
        
        // Set the selected IMEI(s)
        if let imei = itemToEdit.imeis.first {
            selectedIMEIs = Set([imei])
        }
        
        // Prefill capacity and color immediately
        selectedCapacity = itemToEdit.capacity
        selectedColor = itemToEdit.color
        
        // Fetch models for the selected brand, then fetch storage locations, then load devices
        fetchPhoneModelsForEdit()
    }
    
    private func fetchPhoneModelsForEdit() {
        guard !selectedBrand.isEmpty else { return }
        
        isLoadingModels = true
        let brandName = selectedBrand
        
        getBrandDocumentId(for: brandName) { brandDocId in
            let db = Firestore.firestore()
            DispatchQueue.main.async {
                guard let brandDocId = brandDocId else {
                    self.isLoadingModels = false
                    return
                }
                
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
                                self.phoneModels = []
                                return
                            }
                            
                            let modelNames = documents.compactMap { document in
                                document.data()["model"] as? String
                            }
                            
                            self.phoneModels = modelNames.sorted()
                            
                            // After models are loaded, fetch storage locations
                            self.fetchStorageLocationsForEdit()
                        }
                    }
            }
        }
    }
    
    private func fetchStorageLocationsForEdit() {
        guard !selectedBrand.isEmpty && !selectedModel.isEmpty else { return }
        
        isLoadingStorageLocations = true
        let brandName = selectedBrand
        let modelName = selectedModel
        
        getBrandDocumentId(for: brandName) { brandDocId in
            let db = Firestore.firestore()
            DispatchQueue.main.async {
                guard let brandDocId = brandDocId else {
                    self.isLoadingStorageLocations = false
                    return
                }
                
                db.collection("PhoneBrands")
                    .document(brandDocId)
                    .collection("Models")
                    .whereField("model", isEqualTo: modelName)
                    .limit(to: 1)
                    .getDocuments { modelSnapshot, modelError in
                        DispatchQueue.main.async {
                            guard let modelDocId = modelSnapshot?.documents.first?.documentID else {
                                self.isLoadingStorageLocations = false
                                return
                            }
                            
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
                                            self.storageLocations = []
                                            return
                                        }
                                        
                                        let locationNames = Set(phoneDocuments.compactMap { document in
                                            let storageLocationData = document.data()["storageLocation"]
                                            
                                            if let storageLocationString = storageLocationData as? String {
                                                if storageLocationString.hasPrefix("/StorageLocations/") {
                                                    let pathComponents = storageLocationString.components(separatedBy: "/")
                                                    if pathComponents.count >= 3 {
                                                        return pathComponents[2]
                                                    }
                                                }
                                                return storageLocationString
                                            }
                                            
                                            if let storageLocationRef = storageLocationData as? DocumentReference {
                                                return storageLocationRef.documentID
                                            }
                                            
                                            return nil
                                        })
                                        
                                        self.fetchStorageLocationNamesForEdit(from: Array(locationNames))
                                    }
                                }
                        }
                    }
            }
        }
    }
    
    private func fetchStorageLocationNamesForEdit(from locationIds: [String]) {
        guard !locationIds.isEmpty else {
            self.storageLocations = []
            self.isLoadingDevices = false
            return
        }
        
        // Start loading devices indicator
        self.isLoadingDevices = true
        
        let db = Firestore.firestore()
        let dispatchGroup = DispatchGroup()
        var locationNames: [String: String] = [:]
        
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
                        return
                    }
                    
                    let data = document.data()
                    if let name = data?["storageLocation"] as? String {
                        locationNames[locationId] = name
                    }
                }
        }
        
        dispatchGroup.notify(queue: .main) {
            let sortedNames = locationIds.compactMap { locationNames[$0] }.sorted()
            self.storageLocations = sortedNames
            self.storageLocationIdToName = locationNames
            
            // After storage locations are loaded, load devices
            self.loadDevices()
        }
    }
    
    private func proceedToPriceSetting() {
        print("=== PROCEED TO PRICE SETTING ===")
        print("itemToEdit IMEI: \(itemToEdit.imeis.first ?? "none")")
        print("itemToEdit unitCost: \(itemToEdit.unitCost)")
        
        // Get selected devices for pricing
        selectedDevicesForPricing = filteredDevices.filter { device in
            selectedIMEIs.contains(device.imei)
        }
        
        print("Selected devices for pricing count: \(selectedDevicesForPricing.count)")
        for device in selectedDevicesForPricing {
            print("  Device IMEI: \(device.imei), Cost: \(device.unitPrice)")
        }
        
        // Initialize selling prices
        deviceSellingPrices.removeAll()
        deviceProfitLoss.removeAll()
        
        for device in selectedDevicesForPricing {
            print("Processing device IMEI: \(device.imei), comparing with itemToEdit IMEI: \(itemToEdit.imeis.first ?? "none")")
            // If this is the original device being edited, prefill its selling price
            if device.imei == itemToEdit.imeis.first {
                let sellingPrice = itemToEdit.unitCost
                // Format the price, removing trailing zeros if it's a whole number
                let priceString: String
                if sellingPrice.truncatingRemainder(dividingBy: 1) == 0 {
                    priceString = String(format: "%.0f", sellingPrice)
                } else {
                    priceString = String(format: "%.2f", sellingPrice)
                }
                deviceSellingPrices[device.imei] = priceString
                deviceProfitLoss[device.imei] = itemToEdit.unitCost - device.unitPrice
                print("✅ Prefilled selling price for IMEI \(device.imei): \(priceString)")
            } else {
                deviceSellingPrices[device.imei] = ""
                deviceProfitLoss[device.imei] = 0.0
                print("❌ Not the original device, leaving empty for IMEI: \(device.imei)")
            }
        }
        
        print("Final deviceSellingPrices: \(deviceSellingPrices)")
        print("=== END PROCEED TO PRICE SETTING ===")
        
        // Animate to price setting step
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            currentStep = .priceSetting
        }
    }
    
    private func goBackToImeiSelection() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            currentStep = .imeiSelection
        }
    }
    
    private func addProducts() {
        // Create PhoneItem objects from selected devices with selling prices
        var items: [PhoneItem] = []
        
        for device in selectedDevicesForPricing {
            let sellingPriceString = deviceSellingPrices[device.imei, default: ""]
            let sellingPrice = Double(sellingPriceString) ?? 0.0
            
            // Use the initializer that preserves the original ID for editing
            let item = PhoneItem(
                id: itemToEdit.id, // Preserve the original item's ID
                brand: selectedBrand,
                model: selectedModel,
                capacity: device.capacity,
                capacityUnit: device.capacityUnit,
                color: device.color,
                carrier: device.carrier,
                status: device.status, // Use actual device status from database
                storageLocation: selectedStorageLocation,
                imeis: [device.imei],
                unitCost: sellingPrice, // Use selling price as unitCost for sales
                actualCost: device.unitPrice // Store actual purchase cost from phone document
            )
            items.append(item)
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
                
                return SalesAddProductDialog.DeviceInfo(
                    brand: selectedBrand,
                    model: selectedModel,
                    capacity: capacityName,
                    capacityUnit: capacityUnit,
                    color: colorName,
                    imei: imei,
                    carrier: carrierName,
                    status: status,
                    unitPrice: unitPrice,
                    storageLocation: selectedStorageLocation
                )
            }
                    
                    // Don't filter - we'll show all devices but mark the ones in cart
                    self.filteredDevices = self.allDevices
                    
                    // For edit mode, preserve the pre-selected values
                    // Don't clear selectedCapacity, selectedColor, or selectedIMEIs
                    
                    self.isLoadingDevices = false
            
            print("loadDevices: Created \(self.allDevices.count) devices with resolved names")
        }
    }
    
    private func loadDevices() {
        guard !selectedBrand.isEmpty && !selectedModel.isEmpty && !selectedStorageLocation.isEmpty else {
            allDevices = []
            filteredDevices = []
            isLoadingDevices = false
            return
        }
        
        isLoadingDevices = true
        print("loadDevices: Starting load for brand: \(selectedBrand), model: \(selectedModel), storage: \(selectedStorageLocation)")
        
        // Convert storage location name back to ID for filtering
        guard let selectedStorageLocationId = storageLocationIdToName.first(where: { $0.value == selectedStorageLocation })?.key else {
            print("loadDevices: Could not find storage location ID for name: \(selectedStorageLocation)")
            allDevices = []
            filteredDevices = []
            isLoadingDevices = false
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
                    self.isLoadingDevices = false
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
                                self.isLoadingDevices = false
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
                                            self.isLoadingDevices = false
                                            return
                                        }
                                        
                                        guard let phoneDocuments = phonesSnapshot?.documents else {
                                            print("No phones found for brand \(self.selectedBrand) and model \(self.selectedModel)")
                                            self.allDevices = []
                                            self.filteredDevices = []
                                            self.isLoadingDevices = false
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
