//
//  AddProductDialog.swift
//  Aromex
//
//  Created by Ansh on 20/09/25.
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

struct EditProductDialog: View {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let onSave: (([PhoneItem]) -> Void)?
    let itemToEdit: PhoneItem
    
    
    // Brand dropdown state
    @State private var brandSearchText = ""
    @State private var selectedBrand = ""
    @State private var showingBrandDropdown = false
    @State private var brandButtonFrame: CGRect = .zero
    @State private var phoneBrands: [String] = []
    @State private var isLoadingBrands = false
    @FocusState private var isBrandFocused: Bool
    @State private var brandInternalSearchText = "" // Internal search for dropdown filtering
    
    // Model dropdown state
    @State private var modelSearchText = ""
    @State private var selectedModel = ""
    @State private var showingModelDropdown = false
    @State private var modelButtonFrame: CGRect = .zero
    @State private var phoneModels: [String] = []
    @State private var isLoadingModels = false
    @FocusState private var isModelFocused: Bool
    @State private var modelInternalSearchText = "" // Internal search for dropdown filtering
    
    // Carrier dropdown state
    @State private var carrierSearchText = ""
    @State private var selectedCarrier = ""
    @State private var showingCarrierDropdown = false
    @State private var carrierButtonFrame: CGRect = .zero
    @State private var carriers: [String] = []
    @State private var isLoadingCarriers = false
    @FocusState private var isCarrierFocused: Bool
    @State private var carrierInternalSearchText = "" // Internal search for dropdown filtering
    
    // Color dropdown state
    @State private var colors: [String] = []
    @State private var isLoadingColors = false
    @FocusState private var isColorFocused: Bool
    @State private var colorSearchText = "" // Display text in the field
    @State private var colorInternalSearchText = "" // Internal search for dropdown filtering
    
    // Color dropdown state
    @State private var showingColorDropdown = false
    @State private var colorButtonFrame: CGRect = .zero
    
    // Capacity dropdown state
    @State private var showingCapacityDropdown = false
    @State private var capacityButtonFrame: CGRect = .zero
    
    // Status dropdown state (hardcoded options)
    @State private var showingStatusDropdown = false
    @State private var statusButtonFrame: CGRect = .zero
    @FocusState private var isStatusFocused: Bool
    private let statusOptions = ["Active", "Inactive"]
    
    // Storage Location dropdown state
    @State private var storageLocationSearchText = ""
    @State private var selectedStorageLocation = ""
    @State private var showingStorageLocationDropdown = false
    @State private var storageLocationButtonFrame: CGRect = .zero
    @State private var storageLocations: [String] = []
    @State private var isLoadingStorageLocations = false
    @FocusState private var isStorageLocationFocused: Bool
    @State private var storageLocationInternalSearchText = "" // Internal search for dropdown filtering
    
    // Capacity dropdown state
    @State private var capacities: [String] = []
    @State private var isLoadingCapacities = false
    @FocusState private var isCapacityFocused: Bool
    @State private var capacitySearchText = "" // Display text in the field
    @State private var capacityInternalSearchText = "" // Internal search for dropdown filtering
    @FocusState private var isImeiFocused: Bool
    @FocusState private var isPriceFocused: Bool
    
    // Confirmation overlay
    @State private var showingConfirmation = false
    @State private var showingCloseConfirmation = false
    @State private var confirmationMessage = ""
    
    // Loading overlay
    @State private var isAddingBrand = false
    @State private var isAddingModel = false
    @State private var isAddingCarrier = false
    @State private var isAddingStorageLocation = false
    @State private var isAddingColor = false
    @State private var isAddingCapacity = false
    
    // Camera and barcode scanning
    @State private var showingCameraView = false
    @State private var showingiPhoneBarcodeScanner = false
    
    // Other fields (non-functional for now)
    @State private var capacity = ""
    @State private var capacityUnit = "GB" // Default to GB, options: GB, TB
    @State private var imeiSerial = ""
    @State private var storedImeis: [String] = []
    @State private var showingImeiDropdown = false
    @State private var imeiButtonFrame: CGRect = .zero
    @State private var showingDeleteConfirmation = false
    @State private var imeiToDelete: String = ""
    @State private var imeiSearchText = ""
    @State private var imeiInternalSearchText = ""
    
    // macOS barcode listener state
    #if os(macOS)
    @State private var barcodeListener: ListenerRegistration?
    @State private var showBarcodeAddedConfirmation = false
    @State private var addedBarcode = ""
    #endif
    
    @State private var color = ""
    @State private var selectedStatus = "Active"
    @State private var price = ""
    
    @Environment(\.colorScheme) var colorScheme
    
    // Check if form has any data
    private var hasFormData: Bool {
        return !selectedBrand.isEmpty ||
               !selectedModel.isEmpty ||
               !selectedCarrier.isEmpty ||
               !selectedStorageLocation.isEmpty ||
               !imeiSerial.isEmpty ||
               !storedImeis.isEmpty ||
               !capacity.isEmpty ||
               !color.isEmpty ||
               !price.isEmpty ||
               selectedStatus != "Active"
    }
    
    // Enable Add Product when required fields are valid (macOS and desktop UI)
    private var isAddEnabled: Bool {
        let hasBrand = !selectedBrand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasModel = !selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasCapacity = !capacity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasStorage = !selectedStorageLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let priceValue = Double(price.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let hasValidPrice = priceValue > 0
        return hasBrand && hasModel && hasCapacity && hasStorage && hasValidPrice
    }
    
    // Background gradient for iPhone dialog
    private var backgroundGradient: Gradient {
        #if os(iOS)
        return Gradient(colors: [Color(.systemBackground), Color(.systemGray6).opacity(0.3)])
        #else
        return Gradient(colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlColor).opacity(0.3)])
        #endif
    }
    
    // Platform-specific colors for form fields
    private var formFieldBackgroundColor: Color {
        #if os(iOS)
        return Color(.systemBackground)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    private var formFieldBorderColor: Color {
        #if os(iOS)
        return Color(.systemGray4)
        #else
        return Color(NSColor.separatorColor)
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
    
    private func handleSaveAndClose() {
        // Build PhoneItem from current form fields, preserving the original ID
        let unitCost = Double(price) ?? 0.0
        let phone = PhoneItem(
            id: itemToEdit.id, // Preserve the original ID for proper updating
            brand: selectedBrand,
            model: selectedModel,
            capacity: capacity,
            capacityUnit: capacityUnit,
            color: color,
            carrier: selectedCarrier,
            status: selectedStatus,
            storageLocation: selectedStorageLocation,
            imeis: storedImeis.isEmpty && !imeiSerial.isEmpty ? [imeiSerial] : storedImeis,
            unitCost: unitCost
        )
        onSave?([phone])
        isPresented = false
        onDismiss?()
    }
    
    var shouldShowiPhoneDialog: Bool {
        #if os(iOS)
        return true // Always show iPhone dialog on iOS (iPhone and iPad)
        #else
        return false // Show desktop dialog on macOS
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
            // Professional background with gradient
            LinearGradient(
                gradient: backgroundGradient,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            NavigationView {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Professional header section
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Add New Product")
                                            .font(.largeTitle)
                                            .fontWeight(.bold)
                                            .foregroundColor(.primary)
                                        
                                        Text("Enter product details to add to inventory")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                            }
                            .padding(.bottom, 32)
                            
                            // Form fields with professional spacing
                            VStack(spacing: 28) {
                                iPhoneFormFields
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                        }
                    }
                .onChange(of: isCapacityFocused) { focused in
                    if focused {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("capacity", anchor: .center)
                        }
                    }
                }
                .onChange(of: isImeiFocused) { focused in
                    if focused {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("imei", anchor: .center)
                        }
                    }
                }
                .onChange(of: isColorFocused) { focused in
                    if focused {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("color", anchor: .center)
                        }
                    }
                }
                .onChange(of: isPriceFocused) { focused in
                    if focused {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("price", anchor: .center)
                        }
                    }
                }
                .onChange(of: isStorageLocationFocused) { focused in
                    if focused {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("storageLocation", anchor: .center)
                        }
                    }
                }
                .onChange(of: isBrandFocused) { focused in
                    if focused {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("brand", anchor: .center)
                        }
                    }
                }
                .onChange(of: isModelFocused) { focused in
                    if focused {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("model", anchor: .center)
                        }
                    }
                }
                .onChange(of: isCarrierFocused) { focused in
                    if focused {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("carrier", anchor: .center)
                        }
                    }
                }
                .onChange(of: isStatusFocused) { focused in
                    if focused {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("status", anchor: .center)
                        }
                    }
                }
                } // ScrollViewReader
                .navigationTitle("Edit Product")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(content: {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            handleCloseAction()
                        }
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.blue)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            handleSaveAndClose()
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.blue)
                    }
                })
                .safeAreaInset(edge: .bottom) {
                    if isBrandFocused || isModelFocused || isCapacityFocused || isImeiFocused || isCarrierFocused || isColorFocused || isPriceFocused || isStatusFocused || isStorageLocationFocused {
                        HStack {
                            Spacer()
                            Button(isStorageLocationFocused ? "Add Product" : "Next") {
                                if isStorageLocationFocused {
                                    // Save and close
                                    handleSaveAndClose()
                                } else {
                                    // Navigate to next field based on current focus
                                    if isBrandFocused {
                                        isModelFocused = true
                                    } else if isModelFocused {
                                        isCapacityFocused = true
                                    } else if isCapacityFocused {
                                        isImeiFocused = true
                                    } else if isImeiFocused {
                                        isCarrierFocused = true
                                    } else if isCarrierFocused {
                                        isColorFocused = true
                                    } else if isColorFocused {
                                        isPriceFocused = true
                                    } else if isStatusFocused {
                                        isPriceFocused = true
                                    } else if isPriceFocused {
                                        isStorageLocationFocused = true
                                    }
                                }
                            }
                            .padding()
                        }
                        .background(Color(.systemBackground))
                    }
                }
                #endif
            }
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        handleCloseAction()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Product") {
                        handleSaveAndClose()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isAddEnabled)
                }
            }
            #endif
        .onAppear {
            print("iPhoneDialogView appeared - fetching brands, carriers, storage locations, colors, and capacities")
            fetchPhoneBrands()
            fetchCarriers()
            fetchStorageLocations()
            fetchColors()
            fetchCapacities()
            
            // Pre-fill fields with itemToEdit data
            selectedBrand = itemToEdit.brand
            brandSearchText = itemToEdit.brand
            selectedModel = itemToEdit.model
            modelSearchText = itemToEdit.model
            capacity = itemToEdit.capacity
            capacitySearchText = itemToEdit.capacity
            capacityUnit = itemToEdit.capacityUnit
            color = itemToEdit.color
            colorSearchText = itemToEdit.color
            selectedCarrier = itemToEdit.carrier
            carrierSearchText = itemToEdit.carrier
            selectedStatus = itemToEdit.status
            selectedStorageLocation = itemToEdit.storageLocation
            storageLocationSearchText = itemToEdit.storageLocation
            storedImeis = itemToEdit.imeis
            price = String(format: "%.2f", itemToEdit.unitCost)
        }
        .onChange(of: selectedBrand) { newBrand in
            // Clear model field whenever brand changes
            selectedModel = ""
            modelSearchText = ""
            
            if !newBrand.isEmpty {
                fetchPhoneModels()
            } else {
                phoneModels = []
            }
        }
            
            // Loading overlay
            if isLoading {
                loadingOverlay
            }
            
            // Confirmation overlay
            if showingConfirmation {
                confirmationOverlay
            }
            
            // (Removed) IMEI overlay – now inline like other dropdowns
        }
        .sheet(isPresented: $showingCameraView) {
            CameraView(imeiText: $imeiSerial)
        }
        #if os(iOS)
        .sheet(isPresented: $showingiPhoneBarcodeScanner) {
            iPhoneBarcodeScannerSheet(imeiText: $imeiSerial, storedImeis: $storedImeis)
        }
        #endif
        .alert("Delete IMEI", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let index = storedImeis.firstIndex(of: imeiToDelete) {
                    storedImeis.remove(at: index)
                }
                imeiToDelete = ""
            }
        } message: {
            Text("Are you sure you want to delete this IMEI? This action cannot be undone.")
        }
        .alert("Discard Changes", isPresented: $showingCloseConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                closeDialog()
            }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
    }
    
    private var iPhoneFormFields: some View {
        VStack(spacing: 24) {
            // Brand field (functional)
            brandField
                .id("brand")
            
            // Model field (functional)
            modelField
                .id("model")
            
            // Capacity field (functional)
            capacityField
                .id("capacity")
            
             // IMEI/Serial field with camera button
             imeiField
                .id("imei")
            
            // Carrier field (functional)
            carrierField
                .id("carrier")
            
            // Color field (functional)
            colorField
                .id("color")
            
            // Status field (functional)
            statusField
                .id("status")
            
            // Price field (functional)
            formField(
                title: "Price",
                isRequired: true,
                placeholder: "Enter price (e.g., 299.99)",
                text: $price,
                isEnabled: true,
                focus: $isPriceFocused,
                fieldId: "price",
                keyboardType: .decimalPad
            )
            
            // Storage Location field (functional)
            storageLocationField
                .id("storageLocation")
        }
    }
    
    var DesktopDialogView: some View {
        VStack(spacing: 0) {
            desktopHeader
            desktopDivider
            
            desktopContent
            desktopActionButtons
        }
        .frame(width: 1100, height: 630)
        .background(desktopBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(desktopLoadingOverlay)
        .overlay(desktopConfirmationOverlay)
        .overlay(desktopBrandDropdownOverlay)
        .overlay(desktopModelDropdownOverlay)
        .overlay(desktopCarrierDropdownOverlay)
        .overlay(desktopColorDropdownOverlay)
        .overlay(desktopCapacityDropdownOverlay)
        .overlay(desktopStatusDropdownOverlay)
        .overlay(desktopStorageLocationDropdownOverlay)
        .overlay(desktopImeiDropdownOverlay)
        #if os(macOS)
        .overlay(desktopBarcodeConfirmationOverlay)
        #endif
        .onAppear {
            print("DesktopDialogView appeared - fetching brands, carriers, storage locations, colors, and capacities")
            fetchPhoneBrands()
            fetchCarriers()
            fetchStorageLocations()
            fetchColors()
            fetchCapacities()
            
            // Pre-fill fields with itemToEdit data
            selectedBrand = itemToEdit.brand
            brandSearchText = itemToEdit.brand
            selectedModel = itemToEdit.model
            modelSearchText = itemToEdit.model
            capacity = itemToEdit.capacity
            capacitySearchText = itemToEdit.capacity
            capacityUnit = itemToEdit.capacityUnit
            color = itemToEdit.color
            colorSearchText = itemToEdit.color
            selectedCarrier = itemToEdit.carrier
            carrierSearchText = itemToEdit.carrier
            selectedStatus = itemToEdit.status
            selectedStorageLocation = itemToEdit.storageLocation
            storageLocationSearchText = itemToEdit.storageLocation
            storedImeis = itemToEdit.imeis
            price = String(format: "%.2f", itemToEdit.unitCost)
            
            #if os(macOS)
            setupBarcodeListener()
            #endif
        }
        .onDisappear {
            #if os(macOS)
            cleanupBarcodeListener()
            #endif
        }
        .onChange(of: selectedBrand) { newBrand in
            // Clear model field whenever brand changes
            selectedModel = ""
            modelSearchText = ""
            
            if !newBrand.isEmpty {
                fetchPhoneModels()
            } else {
                phoneModels = []
            }
        }
        .sheet(isPresented: $showingCameraView) {
            CameraView(imeiText: $imeiSerial)
        }
        .alert("Delete IMEI", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let index = storedImeis.firstIndex(of: imeiToDelete) {
                    storedImeis.remove(at: index)
                }
                imeiToDelete = ""
            }
        } message: {
            Text("Are you sure you want to delete this IMEI? This action cannot be undone.")
        }
        .alert("Discard Changes", isPresented: $showingCloseConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                closeDialog()
            }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
    }
    
    // MARK: - Custom IMEI Field with Camera Button
    
    private var imeiField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IMEI/Serial")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            
            // IMEI dropdown button using new component
            ImeiDropdownButton(
                searchText: $imeiSearchText,
                storedImeis: $storedImeis,
                isOpen: $showingImeiDropdown,
                buttonFrame: $imeiButtonFrame,
                isFocused: $isImeiFocused,
                internalSearchText: $imeiInternalSearchText
            )
            
            // Inline IMEI dropdown (iPhone/iPad) – expands and pushes content down
            #if os(iOS)
            if showingImeiDropdown {
                ImeiDropdownOverlay(
                    isOpen: $showingImeiDropdown,
                    storedImeis: $storedImeis,
                    searchText: $imeiSearchText,
                    internalSearchText: $imeiInternalSearchText,
                    buttonFrame: imeiButtonFrame,
                    onDelete: { imei in
                        imeiToDelete = imei
                        showingDeleteConfirmation = true
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    private var desktopImeiField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("IMEI/Serial")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
            }
            Spacer(minLength: 4)
            
            ZStack(alignment: .trailing) {
                TextField(storedImeis.isEmpty ? "Enter IMEI or Serial number" : "\(storedImeis.count) IMEI\(storedImeis.count == 1 ? "" : "s") added", text: $imeiSerial)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.trailing, 96)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                    )
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    imeiButtonFrame = geometry.frame(in: .global)
                                }
                                .onChange(of: geometry.frame(in: .global)) { newFrame in
                                    imeiButtonFrame = newFrame
                                }
                        }
                    )
                
                #if os(macOS)
                // macOS: Add typed IMEI into storedImeis using a checkmark button
                HStack {
                    Spacer()
                    if !imeiSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: {
                            let trimmed = imeiSerial.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && !storedImeis.contains(trimmed) {
                                storedImeis.append(trimmed)
                            }
                            imeiSerial = ""
                        }) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing, 8)
                    }
                    // Dropdown toggle button (to the right of checkmark, like iOS)
                    Button(action: {
                        withAnimation {
                            showingImeiDropdown.toggle()
                        }
                    }) {
                        Image(systemName: showingImeiDropdown ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 10)
                }
                #endif
            }

            #if os(macOS)
            // Remove inline list on macOS – overlay is used instead
            #endif
        }
    }
    
    private var desktopColorDropdownOverlay: some View {
        Group {
            #if os(macOS)
            if showingColorDropdown {
                // ADD THIS:
                ColorDropdownOverlay(
                    isOpen: $showingColorDropdown,
                    selectedColor: $color,
                    searchText: $colorSearchText,
                    internalSearchText: $colorInternalSearchText,
                    colors: colors,
                    buttonFrame: colorButtonFrame,
                    onAddColor: { colorName in
                        addNewColor(colorName)
                    },
                    onRenameColor: { oldName, newName in
                        renameColor(oldName: oldName, newName: newName)
                    }
                )
            }
            #endif
        }
    }
    
    private var desktopCapacityDropdownOverlay: some View {
        Group {
            #if os(macOS)
            if showingCapacityDropdown {
                // ADD THIS:
                CapacityDropdownOverlay(
                    isOpen: $showingCapacityDropdown,
                    selectedCapacity: $capacity,
                    searchText: $capacitySearchText,
                    internalSearchText: $capacityInternalSearchText,
                    capacities: capacities,
                    buttonFrame: capacityButtonFrame,
                    onAddCapacity: { capacityName in
                        addNewCapacity(capacityName)
                    },
                    onRenameCapacity: { oldName, newName in
                        renameCapacity(oldName: oldName, newName: newName)
                    }
                )
            }
            #endif
        }
    }
    
    // MARK: - Desktop IMEI Dropdown Overlay
    private var desktopImeiDropdownOverlay: some View {
        Group {
            #if os(macOS)
            if showingImeiDropdown {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        let list = storedImeis
                        let itemHeight: CGFloat = 50
                        let maxHeight: CGFloat = 250
                        let height = max(60, min(CGFloat(max(list.count, 1)) * itemHeight, maxHeight))

                        VStack(spacing: 0) {
                            if list.isEmpty {
                                HStack(spacing: 10) {
                                    Image(systemName: "barcode")
                                        .foregroundColor(.secondary)
                                    Text("No IMEIs added. Type and click ✓ to add.")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(12)
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(Array(list.enumerated()), id: \.offset) { index, imei in
                                            HStack(alignment: .center, spacing: 12) {
                                                Text(imei)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundColor(.primary)
                                                    .lineLimit(2)
                                                    .truncationMode(.tail)
                                                Spacer()
                                                Button(action: {
                                                    imeiToDelete = imei
                                                    showingDeleteConfirmation = true
                                                }) {
                                                    Image(systemName: "trash")
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(.red)
                                                        .frame(width: 30, height: 30)
                                                        .background(Circle().fill(Color.red.opacity(0.1)))
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                                .contentShape(Rectangle())
                                            }
                                            .padding(.horizontal, 12)
                                            .frame(height: itemHeight)

                                            if index < list.count - 1 {
                                                Divider().padding(.leading, 12)
                                            }
                                        }
                                    }
                                }
                                .frame(height: height)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                        )
                        .frame(maxHeight: height)
                        .frame(width: imeiButtonFrame.width)
                        .offset(x: imeiButtonFrame.minX, y: imeiButtonFrame.maxY + 5)
                    }
                    .ignoresSafeArea()
                }
                .transition(.opacity)
            }
            #endif
        }
    }
    
    // MARK: - Desktop Dialog Sub-Views
    private var desktopHeader: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Product")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Button(action: {
                handleCloseAction()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHovering in
                #if os(macOS)
                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
                #endif
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 28)
    }
    
    private var desktopDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(height: 1)
            .padding(.horizontal, 32)
    }
    
    private var desktopContent: some View {
        ScrollView {
            VStack(spacing: 32) {
                desktopFirstRow
                desktopSecondRow
                desktopThirdRow
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
        }
    }
    
    private var desktopFirstRow: some View {
        HStack(spacing: 28) {
            desktopBrandField
            desktopModelField
            desktopCapacityField
        }
    }
    
    private var desktopSecondRow: some View {
        HStack(spacing: 28) {
             desktopImeiField
            desktopCarrierField
            desktopColorField
        }
    }
    
    private var desktopThirdRow: some View {
        HStack(spacing: 28) {
            desktopStatusField
            desktopFormField(
                title: "Price",
                isRequired: true,
                placeholder: "Enter price (e.g., 299.99)",
                text: $price,
                isEnabled: true
            )
            desktopStorageLocationField
        }
    }
    
    private var desktopCarrierField: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Carrier")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
            }
            
            CarrierDropdownButton(
                searchText: $carrierSearchText,
                selectedCarrier: $selectedCarrier,
                isOpen: $showingCarrierDropdown,
                buttonFrame: $carrierButtonFrame,
                isFocused: $isCarrierFocused,
                internalSearchText: $carrierInternalSearchText,
                isLoading: isLoadingCarriers,
                isEnabled: true
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingCarrierDropdown {
                CarrierDropdownOverlay(
                    isOpen: $showingCarrierDropdown,
                    selectedCarrier: $selectedCarrier,
                    searchText: $carrierSearchText,
                    internalSearchText: $carrierInternalSearchText,
                    carriers: carriers,
                    buttonFrame: carrierButtonFrame,
                    onAddCarrier: { carrierName in
                        addNewCarrier(carrierName)
                    },
                    onRenameCarrier: { oldName, newName in
                        renameCarrier(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    private var desktopStatusField: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Status")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            StatusDropdownButton(
                selectedStatus: $selectedStatus,
                isOpen: $showingStatusDropdown,
                buttonFrame: $statusButtonFrame,
                isFocused: $isStatusFocused,
                statusOptions: statusOptions
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingStatusDropdown {
                StatusDropdownOverlay(
                    isOpen: $showingStatusDropdown,
                    selectedStatus: $selectedStatus,
                    statusOptions: statusOptions,
                    buttonFrame: statusButtonFrame
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    private var desktopModelField: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Model")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
            }
            
            ModelDropdownButton(
                searchText: $modelSearchText,
                selectedModel: $selectedModel,
                isOpen: $showingModelDropdown,
                buttonFrame: $modelButtonFrame,
                isFocused: $isModelFocused,
                internalSearchText: $modelInternalSearchText,
                isLoading: isLoadingModels,
                isEnabled: !selectedBrand.isEmpty
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingModelDropdown {
                ModelDropdownOverlay(
                    isOpen: $showingModelDropdown,
                    selectedModel: $selectedModel,
                    searchText: $modelSearchText,
                    internalSearchText: $modelInternalSearchText,
                    models: phoneModels,
                    buttonFrame: modelButtonFrame,
                    onAddModel: { modelName in
                        addNewModel(modelName)
                    },
                    onRenameModel: { oldName, newName in
                        renameModel(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    private var desktopBrandField: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Brand")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
            }
            
            BrandDropdownButton(
                searchText: $brandSearchText,
                selectedBrand: $selectedBrand,
                isOpen: $showingBrandDropdown,
                buttonFrame: $brandButtonFrame,
                isFocused: $isBrandFocused,
                internalSearchText: $brandInternalSearchText,
                isLoading: isLoadingBrands
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingBrandDropdown {
                BrandDropdownOverlay(
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
                        renameBrand(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    private var desktopColorField: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Color")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
            }
            
            ColorDropdownButton(
                searchText: $colorSearchText,
                selectedColor: $color,
                isOpen: $showingColorDropdown,
                buttonFrame: $colorButtonFrame,
                isFocused: $isColorFocused,
                internalSearchText: $colorInternalSearchText,
                isLoading: isLoadingColors
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingColorDropdown {
                ColorDropdownOverlay(
                    isOpen: $showingColorDropdown,
                    selectedColor: $color,
                    searchText: $colorSearchText,
                    internalSearchText: $colorInternalSearchText,
                    colors: colors,
                    buttonFrame: colorButtonFrame,
                    onAddColor: { colorName in
                        addNewColor(colorName)
                    },
                    onRenameColor: { oldName, newName in
                        renameColor(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    private var desktopCapacityField: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Capacity")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
            }
            
            CapacityDropdownButton(
                searchText: $capacitySearchText,
                selectedCapacity: $capacity,
                isOpen: $showingCapacityDropdown,
                buttonFrame: $capacityButtonFrame,
                isFocused: $isCapacityFocused,
                internalSearchText: $capacityInternalSearchText,
                capacityUnit: $capacityUnit,
                isLoading: isLoadingCapacities
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingCapacityDropdown {
                CapacityDropdownOverlay(
                    isOpen: $showingCapacityDropdown,
                    selectedCapacity: $capacity,
                    searchText: $capacitySearchText,
                    internalSearchText: $capacityInternalSearchText,
                    capacities: capacities,
                    buttonFrame: capacityButtonFrame,
                    onAddCapacity: { capacityName in
                        addNewCapacity(capacityName)
                    },
                    onRenameCapacity: { oldName, newName in
                        renameCapacity(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    private var desktopActionButtons: some View {
        HStack(spacing: 16) {
            Button(action: {
                handleCloseAction()
            }) {
                Text("Cancel")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.background))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHovering in
                #if os(macOS)
                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
                #endif
            }
            
            Button(action: {
                if isAddEnabled {
                    handleSaveAndClose()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                    Text("Edit Product")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.25, green: 0.33, blue: 0.54),
                                    Color(red: 0.20, green: 0.28, blue: 0.48)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .shadow(color: Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isAddEnabled)
            .opacity(isAddEnabled ? 1.0 : 0.7)
            .onHover { isHovering in
                #if os(macOS)
                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
                #endif
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }
    
    private var desktopBackground: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(.background)
            .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
    }
    
    private var desktopLoadingOverlay: some View {
        Group {
            if isLoading {
                loadingOverlay
            }
        }
    }
    
    private var desktopConfirmationOverlay: some View {
        Group {
            if showingConfirmation {
                confirmationOverlay
            }
        }
    }
    
    private var desktopBrandDropdownOverlay: some View {
        Group {
            #if os(macOS)
            if showingBrandDropdown {
                BrandDropdownOverlay(
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
                        renameBrand(oldName: oldName, newName: newName)
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
                ModelDropdownOverlay(
                    isOpen: $showingModelDropdown,
                    selectedModel: $selectedModel,
                    searchText: $modelSearchText,
                    internalSearchText: $modelInternalSearchText,
                    models: phoneModels,
                    buttonFrame: modelButtonFrame,
                    onAddModel: { modelName in
                        addNewModel(modelName)
                    },
                    onRenameModel: { oldName, newName in
                        renameModel(oldName: oldName, newName: newName)
                    }
                )
            }
            #endif
        }
    }
    
    private var desktopCarrierDropdownOverlay: some View {
        Group {
            #if os(macOS)
            if showingCarrierDropdown {
                // ADD THIS:
                CarrierDropdownOverlay(
                    isOpen: $showingCarrierDropdown,
                    selectedCarrier: $selectedCarrier,
                    searchText: $carrierSearchText,
                    internalSearchText: $carrierInternalSearchText,
                    carriers: carriers,
                    buttonFrame: carrierButtonFrame,
                    onAddCarrier: { carrierName in
                        addNewCarrier(carrierName)
                    },
                    onRenameCarrier: { oldName, newName in
                        renameCarrier(oldName: oldName, newName: newName)
                    }
                )
            }
            #endif
        }
    }
    
    private var desktopStatusDropdownOverlay: some View {
        Group {
            #if os(macOS)
            if showingStatusDropdown {
                StatusDropdownOverlay(
                    isOpen: $showingStatusDropdown,
                    selectedStatus: $selectedStatus,
                    statusOptions: statusOptions,
                    buttonFrame: statusButtonFrame
                )
            }
            #endif
        }
    }
    
    private var desktopStorageLocationField: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Storage Location")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
            }
            
            StorageLocationDropdownButton(
                searchText: $storageLocationSearchText,
                selectedStorageLocation: $selectedStorageLocation,
                isOpen: $showingStorageLocationDropdown,
                buttonFrame: $storageLocationButtonFrame,
                isFocused: $isStorageLocationFocused,
                internalSearchText: $storageLocationInternalSearchText,
                isLoading: isLoadingStorageLocations,
                isEnabled: true
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingStorageLocationDropdown {
                StorageLocationDropdownOverlay(
                    isOpen: $showingStorageLocationDropdown,
                    selectedStorageLocation: $selectedStorageLocation,
                    searchText: $storageLocationSearchText,
                    internalSearchText: $storageLocationInternalSearchText,
                    storageLocations: storageLocations,
                    buttonFrame: storageLocationButtonFrame,
                    onAddStorageLocation: { locationName in
                        addNewStorageLocation(locationName)
                    },
                    onRenameStorageLocation: { oldName, newName in
                        renameStorageLocation(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    private var desktopStorageLocationDropdownOverlay: some View {
        Group {
            #if os(macOS)
            if showingStorageLocationDropdown {
                // ADD THIS:
                StorageLocationDropdownOverlay(
                    isOpen: $showingStorageLocationDropdown,
                    selectedStorageLocation: $selectedStorageLocation,
                    searchText: $storageLocationSearchText,
                    internalSearchText: $storageLocationInternalSearchText,
                    storageLocations: storageLocations,
                    buttonFrame: storageLocationButtonFrame,
                    onAddStorageLocation: { locationName in
                        addNewStorageLocation(locationName)
                    },
                    onRenameStorageLocation: { oldName, newName in
                        renameStorageLocation(oldName: oldName, newName: newName)
                    }
                )
            }
            #endif
        }
    }
    
    // MARK: - Carrier Field
    private var carrierField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Carrier")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            
            CarrierDropdownButton(
                searchText: $carrierSearchText,
                selectedCarrier: $selectedCarrier,
                isOpen: $showingCarrierDropdown,
                buttonFrame: $carrierButtonFrame,
                isFocused: $isCarrierFocused,
                internalSearchText: $carrierInternalSearchText,
                isLoading: isLoadingCarriers,
                isEnabled: true
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingCarrierDropdown {
                CarrierDropdownOverlay(
                    isOpen: $showingCarrierDropdown,
                    selectedCarrier: $selectedCarrier,
                    searchText: $carrierSearchText,
                    internalSearchText: $carrierInternalSearchText,
                    carriers: carriers,
                    buttonFrame: carrierButtonFrame,
                    onAddCarrier: { carrierName in
                        addNewCarrier(carrierName)
                    },
                    onRenameCarrier: { oldName, newName in
                        renameCarrier(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    // MARK: - Model Field
    private var modelField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            
            ModelDropdownButton(
                searchText: $modelSearchText,
                selectedModel: $selectedModel,
                isOpen: $showingModelDropdown,
                buttonFrame: $modelButtonFrame,
                isFocused: $isModelFocused,
                internalSearchText: $modelInternalSearchText,
                isLoading: isLoadingModels,
                isEnabled: !selectedBrand.isEmpty
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingModelDropdown {
                ModelDropdownOverlay(
                    isOpen: $showingModelDropdown,
                    selectedModel: $selectedModel,
                    searchText: $modelSearchText,
                    internalSearchText: $modelInternalSearchText,
                    models: phoneModels,
                    buttonFrame: modelButtonFrame,
                    onAddModel: { modelName in
                        addNewModel(modelName)
                    },
                    onRenameModel: { oldName, newName in
                        renameModel(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    // MARK: - Brand Field
    private var brandField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Brand")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            
            BrandDropdownButton(
                searchText: $brandSearchText,
                selectedBrand: $selectedBrand,
                isOpen: $showingBrandDropdown,
                buttonFrame: $brandButtonFrame,
                isFocused: $isBrandFocused,
                internalSearchText: $brandInternalSearchText,
                isLoading: isLoadingBrands
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingBrandDropdown {
                BrandDropdownOverlay(
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
                        renameBrand(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    // MARK: - Status Field
    private var statusField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Status")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            
            StatusDropdownButton(
                selectedStatus: $selectedStatus,
                isOpen: $showingStatusDropdown,
                buttonFrame: $statusButtonFrame,
                isFocused: $isStatusFocused,
                statusOptions: statusOptions
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingStatusDropdown {
                StatusDropdownOverlay(
                    isOpen: $showingStatusDropdown,
                    selectedStatus: $selectedStatus,
                    statusOptions: statusOptions,
                    buttonFrame: statusButtonFrame
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    // MARK: - Color Field
    private var colorField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Color")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            
            ColorDropdownButton(
                searchText: $colorSearchText,
                selectedColor: $color,
                isOpen: $showingColorDropdown,
                buttonFrame: $colorButtonFrame,
                isFocused: $isColorFocused,
                internalSearchText: $colorInternalSearchText,
                isLoading: isLoadingColors
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingColorDropdown {
                CapacityDropdownOverlay(
                    isOpen: $showingCapacityDropdown,
                    selectedCapacity: $capacity,
                    searchText: $capacitySearchText,
                    internalSearchText: $capacityInternalSearchText,
                    capacities: capacities,
                    buttonFrame: capacityButtonFrame,
                    onAddCapacity: { capacityName in
                        addNewCapacity(capacityName)
                    },
                    onRenameCapacity: { oldName, newName in
                        renameCapacity(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    // MARK: - Capacity Field
    private var capacityField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Capacity")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            
            CapacityDropdownButton(
                searchText: $capacitySearchText,
                selectedCapacity: $capacity,
                isOpen: $showingCapacityDropdown,
                buttonFrame: $capacityButtonFrame,
                isFocused: $isCapacityFocused,
                internalSearchText: $capacityInternalSearchText,
                capacityUnit: $capacityUnit,
                isLoading: isLoadingCapacities
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingCapacityDropdown {
                CapacityDropdownOverlay(
                    isOpen: $showingCapacityDropdown,
                    selectedCapacity: $capacity,
                    searchText: $capacitySearchText,
                    internalSearchText: $capacityInternalSearchText,
                    capacities: capacities,
                    buttonFrame: capacityButtonFrame,
                    onAddCapacity: { capacityName in
                        addNewCapacity(capacityName)
                    },
                    onRenameCapacity: { oldName, newName in
                        renameCapacity(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    // MARK: - Storage Location Field
    private var storageLocationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Storage Location")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            
            StorageLocationDropdownButton(
                searchText: $storageLocationSearchText,
                selectedStorageLocation: $selectedStorageLocation,
                isOpen: $showingStorageLocationDropdown,
                buttonFrame: $storageLocationButtonFrame,
                isFocused: $isStorageLocationFocused,
                internalSearchText: $storageLocationInternalSearchText,
                isLoading: isLoadingStorageLocations,
                isEnabled: true
            )
            
            // Inline dropdown (iOS only)
            #if os(iOS)
            if showingStorageLocationDropdown {
                StorageLocationDropdownOverlay(
                    isOpen: $showingStorageLocationDropdown,
                    selectedStorageLocation: $selectedStorageLocation,
                    searchText: $storageLocationSearchText,
                    internalSearchText: $storageLocationInternalSearchText,
                    storageLocations: storageLocations,
                    buttonFrame: storageLocationButtonFrame,
                    onAddStorageLocation: { locationName in
                        addNewStorageLocation(locationName)
                    },
                    onRenameStorageLocation: { oldName, newName in
                        renameStorageLocation(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            #endif
        }
    }
    
    // MARK: - Helper Views
    private func formField(
        title: String,
        isRequired: Bool,
        placeholder: String,
        text: Binding<String>,
        isEnabled: Bool,
        focus: FocusState<Bool>.Binding,
        fieldId: String,
        keyboardType: KeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isEnabled ? .primary : .secondary)
                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                        .font(.system(size: 16, weight: .semibold))
                }
                Spacer()
            }
            
            TextField(placeholder, text: text)
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(formFieldBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(focus.wrappedValue ? Color.blue : formFieldBorderColor, lineWidth: focus.wrappedValue ? 2 : 1)
                        )
                        .shadow(color: focus.wrappedValue ? Color.blue.opacity(0.1) : Color.black.opacity(0.05), radius: focus.wrappedValue ? 8 : 4, x: 0, y: 2)
                )
                .disabled(!isEnabled)
                .focused(focus)
                .id(fieldId)
                #if os(iOS)
                .keyboardType(keyboardType)
                .submitLabel(.done)
                #endif
                .onSubmit {
                    focus.wrappedValue = false
                }
        }
    }
    
    private func dropdownField(
        title: String,
        isRequired: Bool,
        selectedValue: Binding<String>,
        placeholder: String,
        isEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }
            
            Button(action: {
                // Non-functional
            }) {
                HStack {
                    Text(selectedValue.wrappedValue.isEmpty ? placeholder : selectedValue.wrappedValue)
                        .foregroundColor(selectedValue.wrappedValue.isEmpty ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.white)
                        )
                )
            }
            .disabled(!isEnabled)
        }
    }
    
    // MARK: - Desktop Helper Views
    private func desktopFormField(
        title: String,
        isRequired: Bool,
        placeholder: String,
        text: Binding<String>,
        isEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isEnabled ? .primary : .secondary)
                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                        .font(.system(size: 18, weight: .bold))
                }
                Spacer()
            }
            
            TextField(placeholder, text: text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 18, weight: .medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                )
                .disabled(!isEnabled)
        }
    }
    
    private func desktopDropdownField(
        title: String,
        isRequired: Bool,
        selectedValue: Binding<String>,
        placeholder: String,
        isEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isEnabled ? .primary : .secondary)
                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                        .font(.system(size: 18, weight: .bold))
                }
                Spacer()
            }
            
            Button(action: {
                // Non-functional
            }) {
                HStack {
                    Text(selectedValue.wrappedValue.isEmpty ? placeholder : selectedValue.wrappedValue)
                        .foregroundColor(selectedValue.wrappedValue.isEmpty ? .secondary : .primary)
                        .font(.system(size: 18, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isEnabled)
            .onHover { isHovering in
                #if os(macOS)
                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
                #endif
            }
        }
    }
    
    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text(loadingMessage)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
            )
            .opacity(isLoading ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.3), value: isLoading)
        }
    }
    
    private var isLoading: Bool {
        return isAddingBrand || isAddingModel || isAddingCarrier || isAddingColor || isAddingCapacity
    }
    
    private var loadingMessage: String {
        if isAddingBrand {
            return "Adding brand..."
        } else if isAddingModel {
            return "Adding model..."
        } else if isAddingCarrier {
            return "Adding carrier..."
        } else if isAddingColor {
            return "Adding color..."
        } else if isAddingCapacity {
            return "Adding capacity..."
        } else {
            return "Loading..."
        }
    }
    
    // MARK: - Confirmation Overlay
    private var confirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "checkmark")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                Text(confirmationMessage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
            )
            .scaleEffect(showingConfirmation ? 1.0 : 0.8)
            .opacity(showingConfirmation ? 1.0 : 0.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showingConfirmation)
        }
    }
    
    // MARK: - Database Functions
    private func renameCarrier(oldName: String, newName: String) {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty, trimmedOld != trimmedNew else { return }
        let db = Firestore.firestore()
        db.collection("Carriers")
            .whereField("carrier", isEqualTo: trimmedOld)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error finding carrier to rename: \(error)")
                    return
                }
                guard let doc = snapshot?.documents.first else {
                    print("Carrier document not found for name: \(trimmedOld)")
                    return
                }
                doc.reference.setData(["carrier": trimmedNew], merge: true) { setError in
                    if let setError = setError {
                        print("Error renaming carrier: \(setError)")
                        return
                    }
                    DispatchQueue.main.async {
                        if let idx = self.carriers.firstIndex(where: { $0.caseInsensitiveCompare(trimmedOld) == .orderedSame }) {
                            self.carriers[idx] = trimmedNew
                            self.carriers.sort()
                        }
                        if self.selectedCarrier == trimmedOld {
                            self.selectedCarrier = trimmedNew
                            self.carrierSearchText = trimmedNew
                        }
                    }
                }
            }
    }

    private func renameColor(oldName: String, newName: String) {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty, trimmedOld != trimmedNew else { return }
        let db = Firestore.firestore()
        db.collection("Colors")
            .whereField("color", isEqualTo: trimmedOld)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error finding color to rename: \(error)")
                    return
                }
                guard let doc = snapshot?.documents.first else {
                    print("Color document not found for name: \(trimmedOld)")
                    return
                }
                doc.reference.setData(["color": trimmedNew], merge: true) { setError in
                    if let setError = setError {
                        print("Error renaming color: \(setError)")
                        return
                    }
                    DispatchQueue.main.async {
                        if let idx = self.colors.firstIndex(where: { $0.caseInsensitiveCompare(trimmedOld) == .orderedSame }) {
                            self.colors[idx] = trimmedNew
                            self.colors.sort()
                        }
                        if self.color == trimmedOld {
                            self.color = trimmedNew
                            self.colorSearchText = trimmedNew
                        }
                    }
                }
            }
    }

    private func renameCapacity(oldName: String, newName: String) {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty, trimmedOld != trimmedNew else { return }
        let db = Firestore.firestore()
        db.collection("Capacities")
            .whereField("capacity", isEqualTo: trimmedOld)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error finding capacity to rename: \(error)")
                    return
                }
                guard let doc = snapshot?.documents.first else {
                    print("Capacity document not found for name: \(trimmedOld)")
                    return
                }
                doc.reference.setData(["capacity": trimmedNew], merge: true) { setError in
                    if let setError = setError {
                        print("Error renaming capacity: \(setError)")
                        return
                    }
                    DispatchQueue.main.async {
                        if let idx = self.capacities.firstIndex(where: { $0.caseInsensitiveCompare(trimmedOld) == .orderedSame }) {
                            self.capacities[idx] = trimmedNew
                            self.capacities.sort()
                        }
                        if self.capacity == trimmedOld {
                            self.capacity = trimmedNew
                            self.capacitySearchText = trimmedNew
                        }
                    }
                }
            }
    }

    private func renameStorageLocation(oldName: String, newName: String) {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty, trimmedOld != trimmedNew else { return }
        let db = Firestore.firestore()
        db.collection("StorageLocations")
            .whereField("storageLocation", isEqualTo: trimmedOld)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error finding storage location to rename: \(error)")
                    return
                }
                guard let doc = snapshot?.documents.first else {
                    print("Storage location document not found for name: \(trimmedOld)")
                    return
                }
                doc.reference.setData(["storageLocation": trimmedNew], merge: true) { setError in
                    if let setError = setError {
                        print("Error renaming storage location: \(setError)")
                        return
                    }
                    DispatchQueue.main.async {
                        if let idx = self.storageLocations.firstIndex(where: { $0.caseInsensitiveCompare(trimmedOld) == .orderedSame }) {
                            self.storageLocations[idx] = trimmedNew
                            self.storageLocations.sort()
                        }
                        if self.selectedStorageLocation == trimmedOld {
                            self.selectedStorageLocation = trimmedNew
                            self.storageLocationSearchText = trimmedNew
                        }
                    }
                }
            }
    }
    private func fetchCarriers() {
        isLoadingCarriers = true
        let db = Firestore.firestore()
        
        db.collection("Carriers").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                self.isLoadingCarriers = false
                
                if let error = error {
                    print("Error fetching carriers: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { 
                    print("No documents found in Carriers collection")
                    return 
                }
                
                let carrierNames = documents.compactMap { document in
                    document.data()["carrier"] as? String
                }
                print("Fetched \(carrierNames.count) carriers: \(carrierNames)")
                
                self.carriers = carrierNames.sorted()
                print("Sorted carriers: \(self.carriers)")
            }
        }
    }
    
    private func fetchPhoneModels() {
        guard !selectedBrand.isEmpty else {
            phoneModels = []
            return
        }
        
        isLoadingModels = true
        let brandName = selectedBrand
        
        getBrandDocumentId(for: brandName) { brandDocId in
            let db = Firestore.firestore()
            DispatchQueue.main.async {
                guard let brandDocId = brandDocId else {
                    self.isLoadingModels = false
                    self.phoneModels = []
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
                        }
                    }
            }
        }
    }

    private func renameBrand(oldName: String, newName: String) {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty, trimmedOld != trimmedNew else { return }
        let db = Firestore.firestore()
        db.collection("PhoneBrands")
            .whereField("brand", isEqualTo: trimmedOld)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error finding brand to rename: \(error)")
                    return
                }
                guard let doc = snapshot?.documents.first else {
                    print("Brand document not found for name: \(trimmedOld)")
                    return
                }
                doc.reference.setData(["brand": trimmedNew], merge: true) { setError in
                    if let setError = setError {
                        print("Error renaming brand: \(setError)")
                        return
                    }
                    DispatchQueue.main.async {
                        if let idx = phoneBrands.firstIndex(where: { $0.caseInsensitiveCompare(trimmedOld) == .orderedSame }) {
                            phoneBrands[idx] = trimmedNew
                            phoneBrands.sort()
                        }
                        if selectedBrand == trimmedOld {
                            selectedBrand = trimmedNew
                            brandSearchText = trimmedNew
                        }
                    }
                }
            }
    }

    private func renameModel(oldName: String, newName: String) {
        guard !selectedBrand.isEmpty else {
            print("Cannot rename model: brand not selected")
            return
        }
        let brandName = selectedBrand
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty, trimmedOld != trimmedNew else { return }
        getBrandDocumentId(for: brandName) { brandDocId in
            let db = Firestore.firestore()
            DispatchQueue.main.async {
                guard let brandDocId = brandDocId else {
                    print("Cannot rename model: brand document not found for \(brandName)")
                    return
                }
                db.collection("PhoneBrands")
                    .document(brandDocId)
                    .collection("Models")
                    .whereField("model", isEqualTo: trimmedOld)
                    .limit(to: 1)
                    .getDocuments { snapshot, error in
                        if let error = error {
                            print("Error finding model to rename: \(error)")
                            return
                        }
                        guard let doc = snapshot?.documents.first else {
                            print("Model document not found for name: \(trimmedOld)")
                            return
                        }
                        doc.reference.setData(["model": trimmedNew], merge: true) { setError in
                            if let setError = setError {
                                print("Error renaming model: \(setError)")
                                return
                            }
                            DispatchQueue.main.async {
                                if let idx = phoneModels.firstIndex(where: { $0.caseInsensitiveCompare(trimmedOld) == .orderedSame }) {
                                    phoneModels[idx] = trimmedNew
                                    phoneModels.sort()
                                }
                                if selectedModel == trimmedOld {
                                    selectedModel = trimmedNew
                                    modelSearchText = trimmedNew
                                }
                            }
                        }
                    }
            }
        }
    }
    
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
    
    private func addNewBrand(_ brandName: String) {
        // Show loading overlay
        isAddingBrand = true
        
        let db = Firestore.firestore()
        
        db.collection("PhoneBrands").addDocument(data: ["brand": brandName]) { error in
            DispatchQueue.main.async {
                // Hide loading overlay
                self.isAddingBrand = false
                
                if let error = error {
                    print("Error adding brand: \(error)")
                    return
                }
                
                // Add to local array
                self.phoneBrands.append(brandName)
                self.phoneBrands.sort()
                
                // Select the new brand
                self.selectedBrand = brandName
                self.brandSearchText = brandName
                
                // Fetch models for the selected brand
                self.fetchPhoneModels()
                
                // Show confirmation
                self.confirmationMessage = "Brand '\(brandName)' added successfully!"
                self.showingConfirmation = true
                
                // Add haptic feedback
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                #endif
                
                // Hide confirmation after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.showingConfirmation = false
                }
            }
        }
    }
    
    private func addNewModel(_ modelName: String) {
        guard !selectedBrand.isEmpty else {
            print("Cannot add model: no brand selected")
            return
        }
        
        // Show loading overlay
        isAddingModel = true
        
        let brandName = selectedBrand
        getBrandDocumentId(for: brandName) { brandDocId in
            let db = Firestore.firestore()
            DispatchQueue.main.async {
                guard let brandDocId = brandDocId else {
                    self.isAddingModel = false
                    print("Cannot add model: brand document not found for \(brandName)")
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
                            
                            // Select the new model
                            self.selectedModel = modelName
                            self.modelSearchText = modelName
                            
                            // Show confirmation
                            self.confirmationMessage = "Model '\(modelName)' added successfully!"
                            self.showingConfirmation = true
                            
                            // Add haptic feedback
                            #if os(iOS)
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            #endif
                            
                            // Hide confirmation after delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self.showingConfirmation = false
                            }
                        }
                    }
            }
        }
    }
    
    private func addNewCarrier(_ carrierName: String) {
        // Show loading overlay
        isAddingCarrier = true
        
        let db = Firestore.firestore()
        
        db.collection("Carriers").addDocument(data: ["carrier": carrierName]) { error in
            DispatchQueue.main.async {
                // Hide loading overlay
                self.isAddingCarrier = false
                
                if let error = error {
                    print("Error adding carrier: \(error)")
                    return
                }
                
                // Add to local array
                self.carriers.append(carrierName)
                self.carriers.sort()
                
                // Select the new carrier
                self.selectedCarrier = carrierName
                self.carrierSearchText = carrierName
                
                // Show confirmation
                self.confirmationMessage = "Carrier '\(carrierName)' added successfully!"
                self.showingConfirmation = true
                
                // Add haptic feedback
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                #endif
                
                // Hide confirmation after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.showingConfirmation = false
                }
            }
        }
    }
    
    private func fetchStorageLocations() {
        isLoadingStorageLocations = true
        let db = Firestore.firestore()
        
        db.collection("StorageLocations").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                self.isLoadingStorageLocations = false
                
                if let error = error {
                    print("Error fetching storage locations: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { 
                    print("No documents found in StorageLocations collection")
                    return 
                }
                
                let locationNames = documents.compactMap { document in
                    document.data()["storageLocation"] as? String
                }
                print("Fetched \(locationNames.count) storage locations: \(locationNames)")
                
                self.storageLocations = locationNames.sorted()
                print("Sorted storage locations: \(self.storageLocations)")
            }
        }
    }
    
    private func fetchColors() {
        isLoadingColors = true
        let db = Firestore.firestore()
        
        db.collection("Colors").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                self.isLoadingColors = false
                
                if let error = error {
                    print("Error fetching colors: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { 
                    print("No documents found in Colors collection")
                    return 
                }
                
                let colorNames = documents.compactMap { document in
                    document.data()["color"] as? String
                }
                print("Fetched \(colorNames.count) colors: \(colorNames)")
                
                self.colors = colorNames.sorted()
                print("Sorted colors: \(self.colors)")
            }
        }
    }
    
    private func fetchCapacities() {
        isLoadingCapacities = true
        let db = Firestore.firestore()
        
        db.collection("Capacities").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                self.isLoadingCapacities = false
                
                if let error = error {
                    print("Error fetching capacities: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { 
                    print("No documents found in Capacities collection")
                    return 
                }
                
                let capacityNames = documents.compactMap { document in
                    document.data()["capacity"] as? String
                }
                print("Fetched \(capacityNames.count) capacities: \(capacityNames)")
                
                self.capacities = capacityNames.sorted()
                print("Sorted capacities: \(self.capacities)")
            }
        }
    }
    
    private func addNewStorageLocation(_ locationName: String) {
        // Show loading overlay
        isAddingStorageLocation = true
        
        let db = Firestore.firestore()
        
        db.collection("StorageLocations").addDocument(data: ["storageLocation": locationName]) { error in
            DispatchQueue.main.async {
                // Hide loading overlay
                self.isAddingStorageLocation = false
                
                if let error = error {
                    print("Error adding storage location: \(error)")
                    return
                }
                
                // Add to local array
                self.storageLocations.append(locationName)
                self.storageLocations.sort()
                
                // Select the new storage location
                self.selectedStorageLocation = locationName
                self.storageLocationSearchText = locationName
                
                // Show confirmation
                self.confirmationMessage = "Storage Location '\(locationName)' added successfully!"
                self.showingConfirmation = true
                
                // Add haptic feedback
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                #endif
                
                // Hide confirmation after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.showingConfirmation = false
                }
            }
        }
    }
    
    private func addNewColor(_ colorName: String) {
        // Show loading overlay
        isAddingColor = true
        
        let db = Firestore.firestore()
        
        db.collection("Colors").addDocument(data: ["color": colorName]) { error in
            DispatchQueue.main.async {
                // Hide loading overlay
                self.isAddingColor = false
                
                if let error = error {
                    print("Error adding color: \(error)")
                    return
                }
                
                // Add to local array
                self.colors.append(colorName)
                self.colors.sort()
                
                // Select the new color
                self.color = colorName
                self.colorSearchText = colorName
                
                // Show confirmation
                self.confirmationMessage = "Color '\(colorName)' added successfully!"
                self.showingConfirmation = true
                
                // Add haptic feedback
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                #endif
                
                // Hide confirmation after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.showingConfirmation = false
                }
            }
        }
    }
    
    private func addNewCapacity(_ capacityName: String) {
        // Show loading overlay
        isAddingCapacity = true
        
        let db = Firestore.firestore()
        
        db.collection("Capacities").addDocument(data: ["capacity": capacityName]) { error in
            DispatchQueue.main.async {
                // Hide loading overlay
                self.isAddingCapacity = false
                
                if let error = error {
                    print("Error adding capacity: \(error)")
                    return
                }
                
                // Add to local array
                self.capacities.append(capacityName)
                self.capacities.sort()
                
                // Select the new capacity
                self.capacity = capacityName
                self.capacitySearchText = capacityName
                
                // Show confirmation
                self.confirmationMessage = "Capacity '\(capacityName)' added successfully!"
                self.showingConfirmation = true
                
                // Add haptic feedback
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                #endif
                
                // Hide confirmation after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.showingConfirmation = false
                }
            }
        }
    }
    
    #if os(macOS)
    private func setupBarcodeListener() {
        let db = Firestore.firestore()
        
        barcodeListener = db.collection("Data").document("scanner")
            .addSnapshotListener { documentSnapshot, error in
                guard let document = documentSnapshot else {
                    print("Error fetching barcode document: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                guard let data = document.data(),
                      let barcode = data["barcode"] as? String,
                      !barcode.isEmpty else {
                    return
                }
                
                // Process the barcode atomically
                processBarcodeAtomically(barcode: barcode)
            }
    }
    
    private func cleanupBarcodeListener() {
        barcodeListener?.remove()
        barcodeListener = nil
    }
    
    private func processBarcodeAtomically(barcode: String) {
        let db = Firestore.firestore()
        
        // Add barcode to stored IMEIs
        if !storedImeis.contains(barcode) {
            storedImeis.append(barcode)
        }
        
        // Show confirmation to user
        DispatchQueue.main.async {
            self.addedBarcode = barcode
            self.showBarcodeAddedConfirmation = true
            
            // Auto-hide confirmation after 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.showBarcodeAddedConfirmation = false
            }
        }
        
        // Delete the barcode from the database
        db.collection("Data").document("scanner").updateData([
            "barcode": FieldValue.delete()
        ]) { error in
            if let error = error {
                print("Error deleting barcode from database: \(error)")
            } else {
                print("Successfully processed and deleted barcode: \(barcode)")
            }
        }
    }
    #endif
    
    // MARK: - Desktop Barcode Confirmation Overlay
    #if os(macOS)
    private var desktopBarcodeConfirmationOverlay: some View {
        Group {
            if showBarcodeAddedConfirmation {
                ZStack {
                    // Background overlay
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    // Confirmation card
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        
                        Text("IMEI/Serial Added")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(addedBarcode)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.background)
                            .shadow(radius: 10)
                    )
                    .frame(maxWidth: 300)
                }
            }
        }
    }
    #endif
    
    // Helper to resolve brand document ID from brand name (auto-ID docs)
    private func getBrandDocumentId(for brandName: String, completion: @escaping (String?) -> Void) {
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
                completion(doc.documentID)
            }
    }
}

