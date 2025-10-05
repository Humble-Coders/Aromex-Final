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

struct AddProductDialog: View {
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
    
    // IMEI validation state
    @State private var isCheckingImei = false
    @State private var showImeiDuplicateAlert = false
    @State private var duplicateImeiMessage = ""
    @State private var showImeiValidationAlert = false
    @State private var imeiValidationMessage = ""
    
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
        // Validate IMEI before saving - must be stored in dropdown (storedImeis array)
        if storedImeis.isEmpty {
            imeiValidationMessage = "Please add at least one IMEI/Serial number by clicking the checkmark button before saving the product."
            showImeiValidationAlert = true
            return
        }
        
        // Build PhoneItem from current form fields
        let unitCost = Double(price) ?? 0.0
        let phone = PhoneItem(
            brand: selectedBrand,
            model: selectedModel,
            capacity: capacity,
            capacityUnit: capacityUnit,
            color: color,
            carrier: selectedCarrier,
            status: selectedStatus,
            storageLocation: selectedStorageLocation,
            imeis: storedImeis,
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
                .navigationTitle("Add Product")
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
                        .disabled(!isAddEnabled)
                    }
                })
                .safeAreaInset(edge: .bottom) {
                    if isBrandFocused || isModelFocused || isCapacityFocused || isImeiFocused || isCarrierFocused || isColorFocused || isPriceFocused || isStatusFocused || isStorageLocationFocused {
                        HStack {
                            Spacer()
                            Button(isStorageLocationFocused ? "Add Product" : "Next") {
                                if isStorageLocationFocused {
                                    // Save and close
                                    if isAddEnabled {
                                        handleSaveAndClose()
                                    }
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
                            .disabled(isStorageLocationFocused && !isAddEnabled)
                            .opacity(isStorageLocationFocused && !isAddEnabled ? 0.7 : 1.0)
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
        .alert("IMEI Already Exists", isPresented: $showImeiDuplicateAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(duplicateImeiMessage)
        }
        .alert("IMEI Required", isPresented: $showImeiValidationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(imeiValidationMessage)
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
        .alert("IMEI Already Exists", isPresented: $showImeiDuplicateAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(duplicateImeiMessage)
        }
        .alert("IMEI Required", isPresented: $showImeiValidationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(imeiValidationMessage)
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
                            Task {
                                await validateAndAddImei()
                            }
                        }) {
                            if isCheckingImei {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .green))
                                    .frame(width: 40, height: 40)
                            } else {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                            }
                        }
                        .disabled(isCheckingImei)
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
                ColorDropdownOverlay(
                    isOpen: $showingColorDropdown,
                    selectedColor: $color,
                    searchText: $colorSearchText,
                    internalSearchText: $colorInternalSearchText,
                    colors: colors,
                    buttonFrame: colorButtonFrame,
                    onAddColor: { colorName in
                        addNewColor(colorName)
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
                CapacityDropdownOverlay(
                    isOpen: $showingCapacityDropdown,
                    selectedCapacity: $capacity,
                    searchText: $capacitySearchText,
                    internalSearchText: $capacityInternalSearchText,
                    capacities: capacities,
                    buttonFrame: capacityButtonFrame,
                    onAddCapacity: { capacityName in
                        addNewCapacity(capacityName)
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
                Text("Add Product")
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
                    Text("Add Product")
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
                CarrierDropdownOverlay(
                    isOpen: $showingCarrierDropdown,
                    selectedCarrier: $selectedCarrier,
                    searchText: $carrierSearchText,
                    internalSearchText: $carrierInternalSearchText,
                    carriers: carriers,
                    buttonFrame: carrierButtonFrame,
                    onAddCarrier: { carrierName in
                        addNewCarrier(carrierName)
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
                StorageLocationDropdownOverlay(
                    isOpen: $showingStorageLocationDropdown,
                    selectedStorageLocation: $selectedStorageLocation,
                    searchText: $storageLocationSearchText,
                    internalSearchText: $storageLocationInternalSearchText,
                    storageLocations: storageLocations,
                    buttonFrame: storageLocationButtonFrame,
                    onAddStorageLocation: { locationName in
                        addNewStorageLocation(locationName)
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
                ColorDropdownOverlay(
                    isOpen: $showingColorDropdown,
                    selectedColor: $color,
                    searchText: $colorSearchText,
                    internalSearchText: $colorInternalSearchText,
                    colors: colors,
                    buttonFrame: colorButtonFrame,
                    onAddColor: { colorName in
                        addNewColor(colorName)
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
        
        // Check if IMEI already exists in stored list
        if storedImeis.contains(barcode) {
            DispatchQueue.main.async {
                self.duplicateImeiMessage = "IMEI '\(barcode)' is already in the list"
                self.showImeiDuplicateAlert = true
            }
            
            // Delete the barcode from the database
            db.collection("Data").document("scanner").updateData([
                "barcode": FieldValue.delete()
            ]) { error in
                if let error = error {
                    print("Error deleting barcode from database: \(error)")
                }
            }
            return
        }
        
        // Check if IMEI exists in database
        let query = db.collection("IMEI").whereField("imei", isEqualTo: barcode).limit(to: 1)
        query.getDocuments { snapshot, error in
            if let error = error {
                print("Error checking IMEI: \(error)")
                return
            }
            
            DispatchQueue.main.async {
                if let snapshot = snapshot, !snapshot.documents.isEmpty {
                    // IMEI already exists in database - show rejection
                    self.duplicateImeiMessage = "IMEI '\(barcode)' already exists in the inventory"
                    self.showImeiDuplicateAlert = true
                } else {
                    // IMEI is unique - add it and show confirmation
                    self.storedImeis.append(barcode)
                    self.addedBarcode = barcode
                    self.showBarcodeAddedConfirmation = true
                    
                    // Auto-hide confirmation after 1.5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.showBarcodeAddedConfirmation = false
                    }
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
    
    // MARK: - IMEI Validation
    private func validateAndAddImei() async {
        let trimmed = imeiSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && !storedImeis.contains(trimmed) else {
            if storedImeis.contains(trimmed) {
                await MainActor.run {
                    duplicateImeiMessage = "IMEI '\(trimmed)' is already in the list"
                    showImeiDuplicateAlert = true
                }
            }
            return
        }
        
        await MainActor.run {
            isCheckingImei = true
        }
        
        do {
            let db = Firestore.firestore()
            let query = db.collection("IMEI").whereField("imei", isEqualTo: trimmed).limit(to: 1)
            let snapshot = try await query.getDocuments()
            
            await MainActor.run {
                isCheckingImei = false
                
                if snapshot.documents.isEmpty {
                    // IMEI is unique, add it
                    storedImeis.append(trimmed)
                    imeiSerial = ""
                } else {
                    // IMEI already exists in database
                    duplicateImeiMessage = "IMEI '\(trimmed)' already exists in the inventory"
                    showImeiDuplicateAlert = true
                }
            }
        } catch {
            await MainActor.run {
                isCheckingImei = false
                duplicateImeiMessage = "Error checking IMEI: \(error.localizedDescription)"
                showImeiDuplicateAlert = true
            }
        }
    }
}

    // MARK: - Brand Dropdown Button
struct BrandDropdownButton: View {
    @Binding var searchText: String
    @Binding var selectedBrand: String
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    @FocusState.Binding var isFocused: Bool
    @Binding var internalSearchText: String
    let isLoading: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
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
                        print("Brand dropdown button clicked, isOpen before: \(isOpen)")
                        withAnimation {
                            isOpen.toggle()
                        }
                        print("Brand dropdown button clicked, isOpen after: \(isOpen)")
                        if isOpen {
                            isFocused = false
                        }
                    }) {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
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
                    isOpen.toggle()
                }
                if isOpen {
                    isFocused = false
                }
            }
            .onChange(of: searchText) { newValue in
                // Sync internal search with display text
                internalSearchText = newValue
                if !newValue.isEmpty && !isOpen && newValue != selectedBrand {
                    isOpen = true
                }
            }
            .onChange(of: isOpen) { newValue in
                // Clear internal search when opening dropdown to show full list
                if newValue {
                    internalSearchText = ""
                }
            }
            .onChange(of: isFocused) { focused in
                print("Brand field focus changed: \(focused), isOpen: \(isOpen)")
                if focused && !isOpen {
                    print("Setting isOpen to true due to focus")
                    isOpen = true
                }
            }
    }
}

// MARK: - Brand Dropdown Overlay
struct BrandDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedBrand: String
    @Binding var searchText: String
    @Binding var internalSearchText: String
    let brands: [String]
    let buttonFrame: CGRect
    let onAddBrand: (String) -> Void
    
    // Removed unused variables since we're using positioned dropdown for all platforms
    
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
            #else
            // Positioned dropdown for macOS
            positionedDropdown
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
    
    private var dynamicMacOSDropdownHeight: CGFloat {
        let itemHeight: CGFloat = 50
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let brandCount = filteredBrands.count
        
        if brandCount <= 3 {
            // For small lists, calculate exact height
            let brandHeight = CGFloat(brandCount) * itemHeight
            let totalHeight = addOptionHeight + brandHeight
            return min(totalHeight, 250)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (3 * itemHeight), 250)
        }
    }
    
    // MARK: - Brand Row Views
    
    private func cleanBrandRow(title: String, isAddOption: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isAddOption {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isAddOption ? Color(red: 0.20, green: 0.60, blue: 0.40) : .primary)
                    .fontWeight(isAddOption ? .semibold : .medium)
                
                Spacer()
                
                if !isAddOption && selectedBrand == title {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(height: 50) // Increased height for better touch targets
        .background(
            // Hover effect for better interaction feedback
            Rectangle()
                .fill(Color.secondary.opacity(0.05))
                .opacity(0)
        )
        .onHover { isHovering in
            // Subtle hover effect for better UX
        }
    }
}

// MARK: - Model Dropdown Button
struct ModelDropdownButton: View {
    @Binding var searchText: String
    @Binding var selectedModel: String
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    @FocusState.Binding var isFocused: Bool
    @Binding var internalSearchText: String
    let isLoading: Bool
    let isEnabled: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Main TextField with padding for the button
            TextField(isEnabled ? "Choose an option" : "Select a brand first", text: $searchText)
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
                .disabled(!isEnabled)
                .onTapGesture {
                    if isEnabled {
                        withAnimation {
                            isOpen.toggle()
                        }
                        if isOpen {
                            isFocused = false
                        }
                    }
                }
                .onChange(of: searchText) { newValue in
                    // Sync internal search with display text
                    internalSearchText = newValue
                    if !newValue.isEmpty && !isOpen && newValue != selectedModel {
                        isOpen = true
                    }
                }
                .onChange(of: isOpen) { newValue in
                    // Clear internal search when opening dropdown to show full list
                    if newValue {
                        internalSearchText = ""
                    }
                }
                .onChange(of: isFocused) { focused in
                    print("Model field focus changed: \(focused), isOpen: \(isOpen)")
                    if focused && !isOpen && isEnabled {
                        print("Setting isOpen to true due to focus")
                        isOpen = true
                    }
                }
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
                        if isEnabled {
                            print("Model dropdown button clicked, isOpen before: \(isOpen)")
                            withAnimation {
                                isOpen.toggle()
                            }
                            print("Model dropdown button clicked, isOpen after: \(isOpen)")
                            if isOpen {
                                isFocused = false
                            }
                        }
                    }) {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
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
                    .padding(.trailing, 10)
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
    }
}

// MARK: - Model Dropdown Overlay
struct ModelDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedModel: String
    @Binding var searchText: String
    @Binding var internalSearchText: String
    let models: [String]
    let buttonFrame: CGRect
    let onAddModel: (String) -> Void
    
    private var filteredModels: [String] {
        print("ModelDropdownOverlay - Total models: \(models.count), models: \(models)")
        print("ModelDropdownOverlay - Internal search text: '\(internalSearchText)'")
        
        if internalSearchText.isEmpty {
            let allModels = models.sorted()
            print("ModelDropdownOverlay - Showing all models: \(allModels)")
            return allModels // Show all models sorted alphabetically when no search text
        } else {
            let filtered = models.filter { model in
                model.localizedCaseInsensitiveContains(internalSearchText)
            }.sorted()
            print("ModelDropdownOverlay - Filtered models: \(filtered)")
            return filtered
        }
    }
    
    private var shouldShowAddOption: Bool {
        return !internalSearchText.isEmpty && !models.contains { $0.localizedCaseInsensitiveCompare(internalSearchText) == .orderedSame }
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
            print("ModelDropdownOverlay appeared with \(models.count) models: \(models)")
            print("ModelDropdownOverlay buttonFrame: \(buttonFrame)")
        }
    }
    
    // MARK: - Inline Dropdown (iOS)
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
                                    selectedModel = model
                                    searchText = model
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
    
    // MARK: - Positioned Dropdown (macOS)
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
                                        selectedModel = model
                                        searchText = model
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
    
    private var dynamicMacOSDropdownHeight: CGFloat {
        let itemHeight: CGFloat = 50
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let modelCount = filteredModels.count
        
        if modelCount <= 3 {
            // For small lists, calculate exact height
            let modelHeight = CGFloat(modelCount) * itemHeight
            let totalHeight = addOptionHeight + modelHeight
            return min(totalHeight, 250)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (3 * itemHeight), 250)
        }
    }
    
    // MARK: - Model Row Views
    private func cleanModelRow(title: String, isAddOption: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isAddOption {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isAddOption ? Color(red: 0.20, green: 0.60, blue: 0.40) : .primary)
                    .fontWeight(isAddOption ? .semibold : .medium)
                
                Spacer()
                
                if !isAddOption && selectedModel == title {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(height: 50) // Increased height for better touch targets
        .background(
            // Hover effect for better interaction feedback
            Rectangle()
                .fill(Color.secondary.opacity(0.05))
                .opacity(0)
        )
        .onHover { isHovering in
            // Subtle hover effect for better UX
        }
    }
}

// MARK: - Carrier Dropdown Button
struct CarrierDropdownButton: View {
    @Binding var searchText: String
    @Binding var selectedCarrier: String
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    @FocusState.Binding var isFocused: Bool
    @Binding var internalSearchText: String
    let isLoading: Bool
    let isEnabled: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Main TextField with padding for the button
            TextField(isEnabled ? "Choose an option" : "Select a brand first", text: $searchText)
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
                .disabled(!isEnabled)
                .onTapGesture {
                    if isEnabled {
                        withAnimation {
                            isOpen.toggle()
                        }
                        if isOpen {
                            isFocused = false
                        }
                    }
                }
                .onChange(of: searchText) { newValue in
                    // Sync internal search with display text
                    internalSearchText = newValue
                    if !newValue.isEmpty && !isOpen && newValue != selectedCarrier {
                        isOpen = true
                    }
                }
                .onChange(of: isOpen) { newValue in
                    // Clear internal search when opening dropdown to show full list
                    if newValue {
                        internalSearchText = ""
                    }
                }
                .onChange(of: isFocused) { focused in
                    print("Carrier field focus changed: \(focused), isOpen: \(isOpen)")
                    if focused && !isOpen && isEnabled {
                        print("Setting isOpen to true due to focus")
                        isOpen = true
                    }
                }
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
                        if isEnabled {
                            print("Carrier dropdown button clicked, isOpen before: \(isOpen)")
                            withAnimation {
                                isOpen.toggle()
                            }
                            print("Carrier dropdown button clicked, isOpen after: \(isOpen)")
                            if isOpen {
                                isFocused = false
                            }
                        }
                    }) {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
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
                    .padding(.trailing, 10)
                }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame = geometry.frame(in: .global)
                        print("Carrier button frame captured: \(buttonFrame)")
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        buttonFrame = newFrame
                    }
            }
        )
    }
}

// MARK: - Carrier Dropdown Overlay
struct CarrierDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedCarrier: String
    @Binding var searchText: String
    @Binding var internalSearchText: String
    let carriers: [String]
    let buttonFrame: CGRect
    let onAddCarrier: (String) -> Void
    
    private var filteredCarriers: [String] {
        print("CarrierDropdownOverlay - Total carriers: \(carriers.count), carriers: \(carriers)")
        print("CarrierDropdownOverlay - Internal search text: '\(internalSearchText)'")
        
        if internalSearchText.isEmpty {
            let allCarriers = carriers.sorted()
            print("CarrierDropdownOverlay - Showing all carriers: \(allCarriers)")
            return allCarriers // Show all carriers sorted alphabetically when no search text
        } else {
            let filtered = carriers.filter { carrier in
                carrier.localizedCaseInsensitiveContains(internalSearchText)
            }.sorted()
            print("CarrierDropdownOverlay - Filtered carriers: \(filtered)")
            return filtered
        }
    }
    
    private var shouldShowAddOption: Bool {
        return !internalSearchText.isEmpty && !carriers.contains { $0.localizedCaseInsensitiveCompare(internalSearchText) == .orderedSame }
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
            print("CarrierDropdownOverlay appeared with \(carriers.count) carriers: \(carriers)")
            print("CarrierDropdownOverlay buttonFrame: \(buttonFrame)")
        }
    }
    
    // MARK: - Inline Dropdown (iOS)
    private var inlineDropdown: some View {
        VStack(spacing: 0) {
            // Add carrier option (if applicable)
            if shouldShowAddOption {
                VStack(spacing: 0) {
                    cleanCarrierRow(
                        title: "Add '\(internalSearchText)'",
                        isAddOption: true,
                        action: {
                            isOpen = false
                            onAddCarrier(internalSearchText)
                        }
                    )
                    
                    // Separator after add option
                    if !filteredCarriers.isEmpty {
                        Divider()
                            .background(Color.secondary.opacity(0.4))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }
                }
            }
            
            // Existing carriers - always use ScrollView for consistency
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredCarriers.enumerated()), id: \.element) { index, carrier in
                        VStack(spacing: 0) {
                            cleanCarrierRow(
                                title: carrier,
                                isAddOption: false,
                                action: {
                                    print("Selected carrier: \(carrier)")
                                    isOpen = false
                                    selectedCarrier = carrier
                                    searchText = carrier
                                }
                            )
                            .onAppear {
                                print("Rendering carrier row: \(carrier)")
                            }
                            
                            // Subtle separator between items
                            if index < filteredCarriers.count - 1 {
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
        let itemHeight: CGFloat = 50 // Height per item
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let carrierCount = filteredCarriers.count
        
        if carrierCount <= 4 {
            // For small lists, calculate exact height
            let carrierHeight = CGFloat(carrierCount) * itemHeight
            let totalHeight = addOptionHeight + carrierHeight
            return min(totalHeight, 240)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (4 * itemHeight), 240)
        }
    }
    
    // MARK: - Positioned Dropdown (macOS)
    private var positionedDropdown: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Add carrier option (if applicable)
                if shouldShowAddOption {
                    VStack(spacing: 0) {
                        cleanCarrierRow(
                            title: "Add '\(internalSearchText)'",
                            isAddOption: true,
                            action: {
                                isOpen = false
                                onAddCarrier(internalSearchText)
                            }
                        )
                        
                        // Separator after add option
                        if !filteredCarriers.isEmpty {
                            Divider()
                                .background(Color.secondary.opacity(0.4))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                
                // Existing carriers - always use ScrollView for consistency
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredCarriers.enumerated()), id: \.element) { index, carrier in
                            VStack(spacing: 0) {
                                cleanCarrierRow(
                                    title: carrier,
                                    isAddOption: false,
                                    action: {
                                        print("Selected carrier: \(carrier)")
                                        isOpen = false
                                        selectedCarrier = carrier
                                        searchText = carrier
                                    }
                                )
                                .onAppear {
                                    print("Rendering carrier row: \(carrier)")
                                }
                                
                                // Divider between items
                                if index < filteredCarriers.count - 1 {
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
    
    private var dynamicMacOSDropdownHeight: CGFloat {
        let itemHeight: CGFloat = 50 // Height per item
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let carrierCount = filteredCarriers.count
        
        if carrierCount <= 3 {
            // For small lists, calculate exact height
            let carrierHeight = CGFloat(carrierCount) * itemHeight
            let totalHeight = addOptionHeight + carrierHeight
            return min(totalHeight, 250)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (3 * itemHeight), 250)
        }
    }
    
    // MARK: - Carrier Row Views
    private func cleanCarrierRow(title: String, isAddOption: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isAddOption {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isAddOption ? Color(red: 0.20, green: 0.60, blue: 0.40) : .primary)
                    .fontWeight(isAddOption ? .semibold : .medium)
                
                Spacer()
                
                if !isAddOption && selectedCarrier == title {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(height: 50) // Increased height for better touch targets
        .background(
            // Hover effect for better interaction feedback
            Rectangle()
                .fill(Color.secondary.opacity(0.05))
                .opacity(0)
        )
        .onHover { isHovering in
            // Subtle hover effect for better UX
        }
    }
}

// MARK: - Status Dropdown Button
struct StatusDropdownButton: View {
    @Binding var selectedStatus: String
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    @FocusState.Binding var isFocused: Bool
    let statusOptions: [String]
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Main TextField with padding for the button
            TextField("Choose an option", text: .constant(selectedStatus))
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
                .disabled(true) // Read-only field
                .onTapGesture {
                    withAnimation {
                        isOpen.toggle()
                    }
                    if isOpen {
                        isFocused = false
                    }
                }
            
            // Separate button positioned on the right
            HStack {
                Spacer()
                Button(action: {
                    withAnimation {
                        isOpen.toggle()
                    }
                    if isOpen {
                        isFocused = false
                    }
                }) {
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
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
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        buttonFrame = newFrame
                    }
            }
        )
    }
}

// MARK: - Status Dropdown Overlay
struct StatusDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedStatus: String
    let statusOptions: [String]
    let buttonFrame: CGRect
    
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
            print("StatusDropdownOverlay appeared with \(statusOptions.count) options: \(statusOptions)")
            print("StatusDropdownOverlay buttonFrame: \(buttonFrame)")
        }
    }
    
    // MARK: - Inline Dropdown (iOS)
    private var inlineDropdown: some View {
        VStack(spacing: 0) {
            // Status options
            VStack(spacing: 0) {
                ForEach(Array(statusOptions.enumerated()), id: \.element) { index, status in
                    VStack(spacing: 0) {
                        cleanStatusRow(
                            title: status,
                            action: {
                                isOpen = false
                                selectedStatus = status
                            }
                        )
                        
                        // Subtle separator between items
                        if index < statusOptions.count - 1 {
                            Divider()
                                .background(Color.secondary.opacity(0.4))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CGFloat(statusOptions.count * 50)) // Fixed height based on item count
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
    
    // MARK: - Positioned Dropdown (macOS)
    private var positionedDropdown: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Status options
                VStack(spacing: 0) {
                    ForEach(Array(statusOptions.enumerated()), id: \.element) { index, status in
                        VStack(spacing: 0) {
                            cleanStatusRow(
                                title: status,
                                action: {
                                    isOpen = false
                                    selectedStatus = status
                                }
                            )
                            
                            // Divider between items
                            if index < statusOptions.count - 1 {
                                Divider()
                                    .background(Color.secondary.opacity(0.4))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: CGFloat(statusOptions.count * 50)) // Fixed height based on item count
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
    
    // MARK: - Status Row Views
    private func cleanStatusRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .fontWeight(.medium)
                
                Spacer()
                
                if selectedStatus == title {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(height: 50) // Fixed height for better touch targets
        .background(
            // Hover effect for better interaction feedback
            Rectangle()
                .fill(Color.secondary.opacity(0.05))
                .opacity(0)
        )
        .onHover { isHovering in
            // Subtle hover effect for better UX
        }
    }
}

// MARK: - Storage Location Dropdown Button
struct StorageLocationDropdownButton: View {
    @Binding var searchText: String
    @Binding var selectedStorageLocation: String
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    @FocusState.Binding var isFocused: Bool
    @Binding var internalSearchText: String
    let isLoading: Bool
    let isEnabled: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Main TextField with padding for the button
            TextField(isEnabled ? "Choose an option" : "Select a brand first", text: $searchText)
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
                .disabled(!isEnabled)
                .onTapGesture {
                    if isEnabled {
                        withAnimation {
                            isOpen.toggle()
                        }
                        if isOpen {
                            isFocused = false
                        }
                    }
                }
                .onChange(of: searchText) { newValue in
                    // Sync internal search with display text
                    internalSearchText = newValue
                    if !newValue.isEmpty && !isOpen && newValue != selectedStorageLocation {
                        isOpen = true
                    }
                }
                .onChange(of: isOpen) { newValue in
                    // Clear internal search when opening dropdown to show full list
                    if newValue {
                        internalSearchText = ""
                    }
                }
                .onChange(of: isFocused) { focused in
                    print("Storage Location field focus changed: \(focused), isOpen: \(isOpen)")
                    if focused && !isOpen && isEnabled {
                        print("Setting isOpen to true due to focus")
                        isOpen = true
                    }
                }
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
                        if isEnabled {
                            print("Storage Location dropdown button clicked, isOpen before: \(isOpen)")
                            withAnimation {
                                isOpen.toggle()
                            }
                            print("Storage Location dropdown button clicked, isOpen after: \(isOpen)")
                            if isOpen {
                                isFocused = false
                            }
                        }
                    }) {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
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
                    .padding(.trailing, 10)
                }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame = geometry.frame(in: .global)
                        print("Storage Location button frame captured: \(buttonFrame)")
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        buttonFrame = newFrame
                    }
            }
        )
    }
}

// MARK: - Storage Location Dropdown Overlay
struct StorageLocationDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedStorageLocation: String
    @Binding var searchText: String
    @Binding var internalSearchText: String
    let storageLocations: [String]
    let buttonFrame: CGRect
    let onAddStorageLocation: (String) -> Void
    
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
            #else
            // Positioned dropdown for macOS
            positionedDropdown
            #endif
        }
        .onAppear {
            print("StorageLocationDropdownOverlay appeared with \(storageLocations.count) locations: \(storageLocations)")
            print("StorageLocationDropdownOverlay buttonFrame: \(buttonFrame)")
        }
    }
    
    // MARK: - Inline Dropdown (iOS)
    private var inlineDropdown: some View {
        VStack(spacing: 0) {
            // Add location option (if applicable)
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
            
            // Existing locations - always use ScrollView for consistency
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
    
    // MARK: - Positioned Dropdown (macOS)
    private var positionedDropdown: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Add location option (if applicable)
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
                
                // Existing locations - always use ScrollView for consistency
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
    
    private var dynamicMacOSDropdownHeight: CGFloat {
        let itemHeight: CGFloat = 50
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let locationCount = filteredStorageLocations.count
        
        if locationCount <= 3 {
            // For small lists, calculate exact height
            let locationHeight = CGFloat(locationCount) * itemHeight
            let totalHeight = addOptionHeight + locationHeight
            return min(totalHeight, 250)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (3 * itemHeight), 250)
        }
    }
    
    // MARK: - Storage Location Row Views
    private func cleanStorageLocationRow(title: String, isAddOption: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isAddOption {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isAddOption ? Color(red: 0.20, green: 0.60, blue: 0.40) : .primary)
                    .fontWeight(isAddOption ? .semibold : .medium)
                
                Spacer()
                
                if !isAddOption && selectedStorageLocation == title {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(height: 50) // Fixed height for better touch targets
        .background(
            // Hover effect for better interaction feedback
            Rectangle()
                .fill(Color.secondary.opacity(0.05))
                .opacity(0)
        )
        .onHover { isHovering in
            // Subtle hover effect for better UX
        }
    }
}

// MARK: - IMEI Dropdown Button
struct ImeiDropdownButton: View {
    @Binding var searchText: String
    @Binding var storedImeis: [String]
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    @FocusState.Binding var isFocused: Bool
    @Binding var internalSearchText: String
    
    @Environment(\.colorScheme) var colorScheme
    @State private var showingCameraView = false
    @State private var showingiPhoneBarcodeScanner = false
    @State private var showAddedConfirmation = false
    
    // IMEI validation state
    @State private var isCheckingImei = false
    @State private var showImeiDuplicateAlert = false
    @State private var duplicateImeiMessage = ""
    @State private var showImeiValidationAlert = false
    @State private var imeiValidationMessage = ""
    
    var body: some View {
        ZStack {
            // Main TextField with padding for the button
            TextField(storedImeis.isEmpty ? "Enter IMEI or Serial Number" : "\(storedImeis.count) IMEI\(storedImeis.count == 1 ? "" : "s") added", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 18, weight: .medium))
                .focused($isFocused)
                .padding(.horizontal, 20)
                .padding(.trailing, 100) // Extra padding for both buttons area
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                )
                .foregroundColor(storedImeis.isEmpty ? .secondary : .primary)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
                .submitLabel(.done)
                .onSubmit {
                    isFocused = false
                }
            
            // Separate buttons positioned side by side on the right
            HStack(spacing: 8) {
                Spacer()
                
                // Inline confirmation icon (brief)
                if showAddedConfirmation {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                        .transition(.opacity)
                }
                
                // Add typed IMEI button (appears when there is text)
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: {
                        Task {
                            await validateAndAddImeiFromField()
                        }
                    }) {
                        if isCheckingImei {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .green))
                                .frame(width: 40, height: 40)
                        } else {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isCheckingImei)
                }
                
                // Dropdown toggle button
                Button(action: {
                    withAnimation {
                        isOpen.toggle()
                    }
                    if isOpen {
                        isFocused = false
                    }
                }) {
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
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
                
                // Camera button
                Button(action: {
                    #if os(iOS)
                    // Use iPhone scanner sheet for both iPhone and iPad
                    showingiPhoneBarcodeScanner = true
                    #else
                    showingCameraView = true
                    #endif
                }) {
                    Image(systemName: "camera")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 10)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        buttonFrame = newFrame
                    }
            }
        )
        .onTapGesture {
            withAnimation {
                isOpen.toggle()
            }
            if isOpen {
                isFocused = false
            }
        }
        // Stop using typed text to filter the dropdown
        // Removed syncing of internalSearchText from searchText
        .onChange(of: isOpen) { newValue in
            if newValue {
                internalSearchText = ""
            }
        }
        .onChange(of: isFocused) { focused in
            if focused && !isOpen {
                isOpen = true
            }
        }
        .sheet(isPresented: $showingCameraView) {
            CameraView(imeiText: $searchText)
        }
        #if os(iOS)
        .sheet(isPresented: $showingiPhoneBarcodeScanner) {
            iPhoneBarcodeScannerSheet(imeiText: $searchText, storedImeis: $storedImeis)
        }
        #endif
        .alert("IMEI Already Exists", isPresented: $showImeiDuplicateAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(duplicateImeiMessage)
        }
        .alert("IMEI Required", isPresented: $showImeiValidationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(imeiValidationMessage)
        }
    }
    
    // MARK: - IMEI Validation
    private func validateAndAddImeiFromField() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && !storedImeis.contains(trimmed) else {
            if storedImeis.contains(trimmed) {
                await MainActor.run {
                    duplicateImeiMessage = "IMEI '\(trimmed)' is already in the list"
                    showImeiDuplicateAlert = true
                }
            }
            return
        }
        
        await MainActor.run {
            isCheckingImei = true
        }
        
        do {
            let db = Firestore.firestore()
            let query = db.collection("IMEI").whereField("imei", isEqualTo: trimmed).limit(to: 1)
            let snapshot = try await query.getDocuments()
            
            await MainActor.run {
                isCheckingImei = false
                
                if snapshot.documents.isEmpty {
                    // IMEI is unique, add it
                    storedImeis.append(trimmed)
                    searchText = ""
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAddedConfirmation = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showAddedConfirmation = false
                        }
                    }
                } else {
                    // IMEI already exists in database
                    duplicateImeiMessage = "IMEI '\(trimmed)' already exists in the inventory"
                    showImeiDuplicateAlert = true
                }
            }
        } catch {
            await MainActor.run {
                isCheckingImei = false
                duplicateImeiMessage = "Error checking IMEI: \(error.localizedDescription)"
                showImeiDuplicateAlert = true
            }
        }
    }
}

// MARK: - IMEI Dropdown Overlay
struct ImeiDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var storedImeis: [String]
    @Binding var searchText: String
    @Binding var internalSearchText: String
    let buttonFrame: CGRect
    let onDelete: (String) -> Void
    
    private var filteredImeis: [String] {
        if internalSearchText.isEmpty {
            return storedImeis
        } else {
            return storedImeis.filter { imei in
                imei.localizedCaseInsensitiveContains(internalSearchText)
            }
        }
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
            print("ImeiDropdownOverlay appeared with \(storedImeis.count) IMEIs: \(storedImeis)")
            print("ImeiDropdownOverlay buttonFrame: \(buttonFrame)")
        }
    }
    
    // MARK: - Inline Dropdown (iOS)
    private var inlineDropdown: some View {
        VStack(spacing: 0) {
            if storedImeis.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "barcode")
                        .foregroundColor(.secondary)
                    Text("No IMEIs added. Use the camera to add.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredImeis.enumerated()), id: \.offset) { index, imei in
                            VStack(spacing: 0) {
                                cleanImeiRow(
                                    title: imei,
                                    index: index,
                                    action: {
                                        isOpen = false
                                        searchText = imei
                                    },
                                    onDelete: {
                                        onDelete(imei)
                                    }
                                )
                                
                                // Subtle separator between items
                                if index < filteredImeis.count - 1 {
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
        let imeiCount = filteredImeis.count
        
        if storedImeis.isEmpty {
            return 60 // Height for empty state
        } else if imeiCount <= 4 {
            // For small lists, calculate exact height
            let imeiHeight = CGFloat(imeiCount) * itemHeight
            return min(imeiHeight, 240)
        } else {
            // For larger lists, use fixed height with scroll
            return min(4 * itemHeight, 240)
        }
    }
    
    // MARK: - Positioned Dropdown (macOS)
    private var positionedDropdown: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if storedImeis.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "barcode")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        
                        Text("No IMEIs added yet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("Use the camera button to scan and add IMEIs")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredImeis.enumerated()), id: \.offset) { index, imei in
                                cleanImeiRow(
                                    title: imei,
                                    index: index,
                                    action: {
                                        isOpen = false
                                        searchText = imei
                                    },
                                    onDelete: {
                                        onDelete(imei)
                                    }
                                )
                                
                                if index < filteredImeis.count - 1 {
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
            .frame(width: 300, height: min(CGFloat(max(filteredImeis.count, 1)) * 50, 300))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
            .position(
                x: buttonFrame.midX,
                y: buttonFrame.maxY + 150 + (min(CGFloat(max(filteredImeis.count, 1)) * 50, 300) / 2)
            )
        }
    }
    
    // MARK: - Helper Views
    private func cleanImeiRow(title: String, index: Int, action: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .center, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.red.opacity(0.1)))
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            Rectangle()
                .fill(Color.secondary.opacity(0.05))
                .opacity(0)
        )
        .onHover { isHovering in
            // Subtle hover effect for better UX
        }
    }
}

// MARK: - Camera View for Barcode Scanning

struct CameraView: View {
    @Binding var imeiText: String
    @Environment(\.dismiss) private var dismiss
    @State private var captureSession: AVCaptureSession?
    @State private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    @State private var isScanning = false
    @State private var cameraDelegate = CameraDelegate()
    
    // Multiple barcode detection
    @State private var detectedBarcodes: [String] = []
    @State private var showingBarcodeSelection = false
    
    // Photo capture
    @State private var photoOutput: AVCapturePhotoOutput?
    @State private var isCapturingPhoto = false
    #if os(iOS)
    @State private var capturedImage: UIImage?
    #else
    @State private var capturedImage: NSImage?
    #endif
    @State private var showingCapturedImage = false
    @State private var currentVideoFrame: CMSampleBuffer?
    @State private var capturedImageBarcodes: [String] = []
    @State private var showingDoneButton = false
    
    // Serial queue for safe array modifications
    private let arrayQueue = DispatchQueue(label: "com.aromex.arrayQueue", qos: .userInitiated)
    
    // Stable copies for ForEach rendering to prevent mutation crashes
    private var stableDetectedBarcodes: [(Int, String)] {
        let snapshot = detectedBarcodes
        return Array(snapshot.enumerated())
    }
    
    private var stableCapturedImageBarcodes: [(Int, String)] {
        let snapshot = capturedImageBarcodes
        return Array(snapshot.enumerated())
    }
    
    // Helper function to safely modify arrays
    private func safeUpdateCapturedBarcodes(_ newBarcodes: [String]) {
        arrayQueue.async {
            DispatchQueue.main.async {
                self.capturedImageBarcodes.removeAll()
                self.capturedImageBarcodes.append(contentsOf: newBarcodes)
                self.showingDoneButton = true
            }
        }
    }
    
    private func safeUpdateDetectedBarcodes(_ newBarcodes: [String]) {
        arrayQueue.async {
            DispatchQueue.main.async {
                self.detectedBarcodes.removeAll()
                self.detectedBarcodes.append(contentsOf: newBarcodes)
            }
        }
    }
    
    private func safeClearDetectedBarcodes() {
        arrayQueue.async {
            DispatchQueue.main.async {
                self.detectedBarcodes.removeAll()
            }
        }
    }
    
    private func safeClearCapturedImageBarcodes() {
        arrayQueue.async {
            DispatchQueue.main.async {
                self.capturedImageBarcodes.removeAll()
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Professional dark background with subtle gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.15)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header section with title and instructions
                    VStack(spacing: 16) {
                        // Professional title
                        Text("Scan Barcode")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Position the barcode within the frame below")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 30)
                    
                    // Camera preview section
                    ZStack {
                        // Professional camera frame with border
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .frame(width: 720, height: 520)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.black.opacity(0.3))
                            )
                        
                        // Camera preview
                        CameraPreviewView(captureSession: $captureSession)
                            .frame(width: 700, height: 500)
                            .cornerRadius(16)
                            .clipped()
                            .onAppear {
                                print("Camera preview appeared - setting up camera")
                                setupCamera()
                            }
                            .onDisappear {
                                print("Camera preview disappeared - stopping camera")
                                stopCamera()
                            }
                        
                        // Scanning overlay with corner indicators
                        VStack {
                            HStack {
                                // Top-left corner
                                VStack {
                                    HStack {
                                        Rectangle()
                                            .frame(width: 30, height: 3)
                                        Spacer()
                                    }
                                    HStack {
                                        Rectangle()
                                            .frame(width: 3, height: 30)
                                        Spacer()
                                    }
                                }
                                Spacer()
                                // Top-right corner
                                VStack {
                                    HStack {
                                        Spacer()
                                        Rectangle()
                                            .frame(width: 30, height: 3)
                                    }
                                    HStack {
                                        Spacer()
                                        Rectangle()
                                            .frame(width: 3, height: 30)
                                    }
                                }
                            }
                            Spacer()
                            HStack {
                                // Bottom-left corner
                                VStack {
                                    HStack {
                                        Spacer()
                                        Rectangle()
                                            .frame(width: 3, height: 30)
                                    }
                                    HStack {
                                        Rectangle()
                                            .frame(width: 30, height: 3)
                                        Spacer()
                                    }
                                }
                                Spacer()
                                // Bottom-right corner
                                VStack {
                                    HStack {
                                        Spacer()
                                        Rectangle()
                                            .frame(width: 3, height: 30)
                                    }
                                    HStack {
                                        Spacer()
                                        Rectangle()
                                            .frame(width: 30, height: 3)
                                    }
                                }
                            }
                        }
                        .frame(width: 700, height: 500)
                        .foregroundColor(.green)
                    }
                    .padding(.bottom, 30)
                    
                    // Bottom section with action buttons
                    VStack(spacing: 20) {
                        Text("Align the barcode in the frame and tap 'Capture Photo'")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        
                        // Action buttons
                        HStack(spacing: 16) {
                            // Cancel button
                            Button(action: {
                                dismiss()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("Cancel")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 25)
                                        .fill(Color.red.opacity(0.8))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Photo capture button
                            Button(action: {
                                #if os(iOS)
                                print("Capture button tapped on iOS")
                                #else
                                print("Capture button tapped on macOS")
                                #endif
                                capturePhoto()
                            }) {
                                HStack(spacing: 8) {
                                    if isCapturingPhoto {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "camera.circle.fill")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    Text(isCapturingPhoto ? "Processing..." : "Capture Photo")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 25)
                                        .fill(Color.blue.opacity(0.8))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isCapturingPhoto)
                        }
                    }
                    .padding(.bottom, 40)
                }
                
                // Captured image overlay
                #if os(iOS)
                if showingCapturedImage, let image = capturedImage {
                    capturedImageOverlay(image)
                }
                #else
                if showingCapturedImage, let image = capturedImage {
                    capturedImageOverlay(image)
                }
                #endif
                
                // Multiple barcode selection overlay
                if showingBarcodeSelection {
                    barcodeSelectionOverlay
                }
            }
            #if os(iOS)
            .navigationBarHidden(true) // Hide default navigation bar
            #endif
        }
        .frame(width: 900, height: 750) // ✅ Larger dialog to prevent cutoff
        #if os(macOS)
        .frame(width: 900, height: 750) // ✅ Additional frame for macOS
        #endif
    }
    
    // MARK: - Captured Image Overlay
    
    private func capturedImageHeader() -> some View {
        Text("Captured Image")
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.white)
    }
    
    #if os(iOS)
    private func capturedImagePreview(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 350, maxHeight: 250)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
    }
    #else
    private func capturedImagePreview(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 350, maxHeight: 250)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
    }
    #endif
    
    private func capturedImageBarcodeList() -> some View {
        VStack(spacing: 12) {
            Text("Detected Barcodes (\(capturedImageBarcodes.count))")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            VStack(spacing: 8) {
                ForEach(Array(stableCapturedImageBarcodes.enumerated()), id: \.offset) { index, barcode in
                    capturedImageBarcodeItem(index: index, barcode: barcode.1)
                }
            }
        }
    }
    
    private func capturedImageBarcodeItem(index: Int, barcode: String) -> some View {
        HStack {
            Text("\(index + 1).")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 20, alignment: .leading)
            
            Text(barcode)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    private func capturedImageNoBarcodesMessage() -> some View {
        Text("No barcodes detected")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
    }
    
    private func capturedImageCancelButton() -> some View {
        Button(action: {
            cancelPhotoCapture()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.red.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func capturedImageDoneButton() -> some View {
        Button(action: {
            processCapturedBarcodes()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.green.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(Color.green.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func capturedImageActionButtons() -> some View {
        HStack(spacing: 16) {
            capturedImageCancelButton()
            
            if showingDoneButton {
                capturedImageDoneButton()
            }
        }
    }
    
    #if os(iOS)
    private func capturedImageContent(_ image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                capturedImageHeader()
                capturedImagePreview(image)
                
                if !capturedImageBarcodes.isEmpty {
                    capturedImageBarcodeList()
                } else {
                    capturedImageNoBarcodesMessage()
                }
                
                capturedImageActionButtons()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }
    #else
    private func capturedImageContent(_ image: NSImage) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                capturedImageHeader()
                capturedImagePreview(image)
                
                if !capturedImageBarcodes.isEmpty {
                    capturedImageBarcodeList()
                } else {
                    capturedImageNoBarcodesMessage()
                }
                
                capturedImageActionButtons()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }
    #endif
    
    #if os(iOS)
    private func capturedImageOverlay(_ image: UIImage) -> some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            capturedImageContent(image)
        }
    }
    #else
    private func capturedImageOverlay(_ image: NSImage) -> some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            capturedImageContent(image)
        }
    }
    #endif
    
    // MARK: - Barcode Selection Overlay
    
    private var barcodeSelectionOverlay: some View {
        ZStack {
            // Full opaque background
            Color.black
                .ignoresSafeArea()
            
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                // iPhone-specific ultra-compact layout
                iPhoneBarcodeSelection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .onAppear {
                        print("iPhone barcode selection overlay appeared")
                    }
            } else {
                // iPad layout
                iPadBarcodeSelection
                    .onAppear {
                        print("iPad barcode selection overlay appeared")
                    }
            }
            #else
            // macOS layout
            macOSBarcodeSelection
                .onAppear {
                    print("macOS barcode selection overlay appeared")
                }
            #endif
        }
        #if os(iOS)
        .ignoresSafeArea(.all) // Ensure full screen on iPhone
        #endif
    }
    
    // MARK: - Platform-Specific Barcode Selection Views
    
    private var iPhoneBarcodeHeader: some View {
        VStack(spacing: 2) {
            Text("Choose Barcode")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            
            Text("Tap to select:")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.top, 6)
        .padding(.bottom, 3)
    }
    
    private var iPhoneBarcodeList: some View {
        ScrollView {
            VStack(spacing: 3) {
                ForEach(Array(stableDetectedBarcodes.enumerated()), id: \.offset) { index, barcode in
                    iPhoneBarcodeItemCompact(index: index, barcode: barcode.1)
                }
            }
            .padding(.horizontal, 10)
        }
    }
    
    private func iPhoneBarcodeItemCompact(index: Int, barcode: String) -> some View {
        Button(action: {
            selectBarcode(barcode)
        }) {
            HStack(spacing: 12) {
                // Number badge - simplified
                Text("\(index + 1)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.blue)
                    .clipShape(Circle())
                
                // Barcode text - simplified
                VStack(alignment: .leading, spacing: 4) {
                    Text(barcode)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    
                    Text("Tap to select")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Selection indicator - simplified
                Text("→")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.3))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            print("iPhoneBarcodeItemCompact appeared for index \(index) with barcode: \(barcode)")
        }
    }
    
    private var iPhoneBarcodeCancelButton: some View {
        Button(action: {
            cancelBarcodeSelection()
        }) {
            Text("Cancel")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.red.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 3)
        .padding(.bottom, 6)
    }
    
    private var iPhoneBarcodeSelection: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top safe area
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: geometry.safeAreaInsets.top)
                
                // Header - compact for iPhone
                VStack(spacing: 4) {
                    Text("Select Barcode")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Tap to choose")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.vertical, 16)
                
                // Barcode list - simplified layout
                VStack(spacing: 12) {
                    ForEach(Array(stableDetectedBarcodes.enumerated()), id: \.offset) { index, barcode in
                        iPhoneBarcodeItemCompact(index: index, barcode: barcode.1)
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: geometry.size.height * 0.7)
                .onAppear {
                    print("iPhone barcode list appeared with \(stableDetectedBarcodes.count) barcodes")
                    for (index, barcode) in stableDetectedBarcodes.enumerated() {
                        print("Barcode \(index): \(barcode.1)")
                    }
                }
                
                Spacer()
                
                // Cancel button - always visible at bottom
                Button(action: {
                    cancelBarcodeSelection()
                }) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.8))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .ignoresSafeArea(.all)
    }
    
    private var iPadBarcodeHeader: some View {
        VStack(spacing: 6) {
            Text("Choose Barcode")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Text("Select which barcode to use:")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.top, 20)
        .padding(.bottom, 15)
    }
    
    private var iPadBarcodeList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(stableDetectedBarcodes.enumerated()), id: \.offset) { index, barcode in
                    iPadBarcodeItem(index: index, barcode: barcode.1)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxHeight: 400)
    }
    
    private func iPadBarcodeItem(index: Int, barcode: String) -> some View {
        Button(action: {
            selectBarcode(barcode)
        }) {
            HStack {
                Text("\(index + 1)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color.blue)
                    )
                
                Text(barcode)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var iPadBarcodeCancelButton: some View {
        Button(action: {
            cancelBarcodeSelection()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                Text("Cancel")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.red.opacity(0.8))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.bottom, 20)
    }
    
    private var iPadBarcodeSelection: some View {
        VStack(spacing: 0) {
            iPadBarcodeHeader
            iPadBarcodeList
            Spacer(minLength: 20)
            iPadBarcodeCancelButton
        }
    }
    
    private var macOSBarcodeHeader: some View {
        VStack(spacing: 8) {
            Text("Choose Barcode")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text("Select which barcode to use:")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.top, 30)
        .padding(.bottom, 20)
    }
    
    private var macOSBarcodeList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(stableDetectedBarcodes.enumerated()), id: \.offset) { index, barcode in
                    macOSBarcodeItem(index: index, barcode: barcode.1)
                }
            }
            .padding(.horizontal, 30)
        }
        .frame(maxHeight: 450)
    }
    
    private func macOSBarcodeItem(index: Int, barcode: String) -> some View {
        Button(action: {
            selectBarcode(barcode)
        }) {
            HStack {
                Text("\(index + 1)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.blue)
                    )
                
                Text(barcode)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var macOSBarcodeCancelButton: some View {
        Button(action: {
            cancelBarcodeSelection()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.red.opacity(0.8))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.bottom, 30)
    }
    
    private var macOSBarcodeSelection: some View {
        VStack(spacing: 0) {
            macOSBarcodeHeader
            macOSBarcodeList
            Spacer(minLength: 30)
            macOSBarcodeCancelButton
        }
    }
    
    // MARK: - Barcode Selection Functions
    
    private func selectBarcode(_ barcode: String) {
        imeiText = barcode
        
        DispatchQueue.main.async {
            self.showingBarcodeSelection = false
            self.safeClearDetectedBarcodes()
            self.dismiss()
        }
    }
    
    private func cancelBarcodeSelection() {
        DispatchQueue.main.async {
            self.showingBarcodeSelection = false
            self.safeClearDetectedBarcodes()
            // Resume scanning
        }
    }
    
    private func cancelPhotoCapture() {
        showingCapturedImage = false
        #if os(iOS)
        capturedImage = nil
        #endif
        safeClearCapturedImageBarcodes()
        showingDoneButton = false
        isCapturingPhoto = false
        // Return to camera view
    }
    
    private func processCapturedBarcodes() {
        // Create a copy to avoid mutation during processing
        let barcodes = Array(capturedImageBarcodes)
        print("processCapturedBarcodes called with \(barcodes.count) barcodes: \(barcodes)")
        
        if barcodes.count == 1 {
            // Single barcode - use it directly
            print("Single barcode detected, auto-filling IMEI field")
            imeiText = barcodes[0]
            dismiss()
        } else if barcodes.count > 1 {
            // Multiple barcodes - show selection
            print("Multiple barcodes detected, showing selection overlay")
            safeUpdateDetectedBarcodes(barcodes)
            DispatchQueue.main.async {
                // Update UI state
                self.showingCapturedImage = false
                self.showingBarcodeSelection = true
            }
        } else {
            // No barcodes - just close
            dismiss()
        }
    }
    
    // MARK: - Photo Capture Functions
    
    private func capturePhoto() {
        print("capturePhoto() called")
        // Immediately show processing state
        isCapturingPhoto = true
        print("Set isCapturingPhoto = true")
        
        // Capture the current video frame instantly
        if let videoFrame = currentVideoFrame {
            print("Found video frame, processing...")
            #if os(iOS)
            // Convert video frame to UIImage instantly
            if let image = imageFromSampleBuffer(videoFrame) {
                // Immediately show the captured image
                capturedImage = image
                showingCapturedImage = true
                isCapturingPhoto = false
                
                // Analyze for barcodes in background
                DispatchQueue.global(qos: .userInitiated).async {
                    analyzeImageForBarcodes(image)
                }
            } else {
                isCapturingPhoto = false
            }
            #else
            // For macOS, convert to image and show it
            print("Processing on macOS...")
            if let image = imageFromSampleBuffer(videoFrame) {
                print("Successfully converted sample buffer to NSImage")
                // Show the captured image
                capturedImage = image
                showingCapturedImage = true
                isCapturingPhoto = false
                print("Set showingCapturedImage = true, isCapturingPhoto = false")
                
                // Analyze for barcodes in background
                DispatchQueue.global(qos: .userInitiated).async {
                    print("Starting barcode analysis on background thread...")
                    analyzeSampleBufferForBarcodes(videoFrame)
                }
            } else {
                print("Failed to convert sample buffer to image on macOS")
                isCapturingPhoto = false
            }
            #endif
        } else {
            print("No video frame available")
            isCapturingPhoto = false
        }
    }
    
    #if os(iOS)
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
    #else
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> NSImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    #endif
    
    #if os(iOS)
    private func analyzeImageForBarcodes(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        
        let request = VNDetectBarcodesRequest { [self] request, error in
            guard let results = request.results as? [VNBarcodeObservation] else { return }
            
            // Extract all barcode payloads
            let barcodes = results.compactMap { $0.payloadStringValue }
            
            // Use safe array update to prevent mutation crashes
            safeUpdateCapturedBarcodes(barcodes)
        }
        
        // Configure request for maximum barcode detection quality
        request.revision = VNDetectBarcodesRequestRevision3 // Use latest revision
        request.symbologies = [.QR, .Aztec, .DataMatrix, .PDF417, .Code128, .Code93, .Code39, .EAN13, .EAN8, .UPCE] // Support all common barcode types (UPCA is handled by EAN13)
        
        // Use high priority for faster detection
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
    #endif
    
    #if os(macOS)
    private func analyzeSampleBufferForBarcodes(_ sampleBuffer: CMSampleBuffer) {
        print("analyzeSampleBufferForBarcodes called")
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { 
            print("Failed to get pixel buffer from sample buffer")
            return 
        }
        print("Got pixel buffer, creating barcode detection request...")
        
        let request = VNDetectBarcodesRequest { [self] request, error in
            print("Barcode detection callback triggered")
            if let error = error {
                print("Barcode detection error: \(error)")
                return
            }
            guard let results = request.results as? [VNBarcodeObservation] else { 
                print("No barcode results found")
                return 
            }
            
            // Extract all barcode payloads
            let barcodes = results.compactMap { $0.payloadStringValue }
            print("Found \(barcodes.count) barcodes in captured image: \(barcodes)")
            
            // Use safe array update to prevent mutation crashes
            safeUpdateCapturedBarcodes(barcodes)
        }
        
        // Configure request for maximum barcode detection quality
        request.revision = VNDetectBarcodesRequestRevision3 // Use latest revision
        request.symbologies = [.QR, .Aztec, .DataMatrix, .PDF417, .Code128, .Code93, .Code39, .EAN13, .EAN8, .UPCE] // Support all common barcode types (UPCA is handled by EAN13)
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
    #endif
    
    private func setupCamera() {
        print("Setting up camera...")
        
        // Use front camera for macOS, back camera for iOS
        #if os(macOS)
        // Try different camera discovery methods for macOS
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        
        guard let captureDevice = discoverySession.devices.first else {
            print("Failed to get front camera on macOS - trying default device")
            // Fallback to default camera
            guard let defaultDevice = AVCaptureDevice.default(for: .video) else {
                print("No camera devices found on macOS")
                return
            }
            print("Using default camera on macOS: \(defaultDevice.localizedName)")
            setupCameraWithDevice(defaultDevice)
            return
        }
        print("Found front camera on macOS: \(captureDevice.localizedName)")
        setupCameraWithDevice(captureDevice)
        #else
        // Use back camera for both iPad and iPhone
        let devicePosition: AVCaptureDevice.Position = .back
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: devicePosition) else { 
            print("Failed to get camera on iOS")
            return 
        }
        let deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        print("Found back camera on \(deviceType): \(captureDevice.localizedName)")
        setupCameraWithDevice(captureDevice)
        #endif
    }
    
    private func setupCameraWithDevice(_ captureDevice: AVCaptureDevice) {
        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            
            // Create new session and ensure it's properly initialized
            let captureSession = AVCaptureSession()
            
            // Begin configuration before adding inputs/outputs
            captureSession.beginConfiguration()
            
            // Configure session for highest quality
            captureSession.sessionPreset = .high
            
            // Try to use the highest available quality for iPhone and iPad
            if captureSession.canSetSessionPreset(.hd4K3840x2160) {
                captureSession.sessionPreset = .hd4K3840x2160
                print("Using 4K quality for barcode scanning")
            } else if captureSession.canSetSessionPreset(.hd1920x1080) {
                captureSession.sessionPreset = .hd1920x1080
                print("Using 1080p quality for barcode scanning")
            } else if captureSession.canSetSessionPreset(.hd1280x720) {
                captureSession.sessionPreset = .hd1280x720
                print("Using 720p quality for barcode scanning")
            } else {
                captureSession.sessionPreset = .high
                print("Using high quality preset for barcode scanning")
            }
            
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                print("Added camera input to session")
            } else {
                print("Failed to add camera input to session")
                return
            }
            
            let videoOutput = AVCaptureVideoDataOutput()
            
            // Configure video output for maximum quality barcode detection
            let outputWidth: Int
            let outputHeight: Int
            
            // Match output resolution to session preset for maximum quality
            if captureSession.sessionPreset == .hd4K3840x2160 {
                outputWidth = 3840
                outputHeight = 2160
                print("Using 4K video output (3840x2160) for maximum barcode detection quality")
            } else if captureSession.sessionPreset == .hd1920x1080 {
                outputWidth = 1920
                outputHeight = 1080
                print("Using 1080p video output (1920x1080) for maximum barcode detection quality")
            } else if captureSession.sessionPreset == .hd1280x720 {
                outputWidth = 1280
                outputHeight = 720
                print("Using 720p video output (1280x720) for maximum barcode detection quality")
            } else {
                // For .high preset, use 1080p as it's typically the best available
                outputWidth = 1920
                outputHeight = 1080
                print("Using 1080p video output (1920x1080) for high quality barcode detection")
            }
            
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: outputWidth,
                kCVPixelBufferHeightKey as String: outputHeight
            ]
            
            // Ensure we don't drop frames for better barcode detection
            videoOutput.alwaysDiscardsLateVideoFrames = false
            
            cameraDelegate.onBarcodeDetected = { [self] barcodes in
                print("Barcodes detected in live stream: \(barcodes)")
                // Auto-scanning disabled - user must capture photo manually
                // This callback is kept for potential future use or debugging
            }
            
            cameraDelegate.onFrameReceived = { [self] sampleBuffer in
                // Store the current video frame for instant capture (thread-safe)
                DispatchQueue.main.async {
                    self.currentVideoFrame = sampleBuffer
                }
            }
            // Use a serial queue for video processing to prevent race conditions
            let videoQueue = DispatchQueue(label: "com.aromex.videoQueue", qos: .userInitiated)
            videoOutput.setSampleBufferDelegate(cameraDelegate, queue: videoQueue)
            
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                print("Added video output to session")
            } else {
                print("Failed to add video output to session")
                return
            }
            
            // Add photo output for photo capture
            let photoOutput = AVCapturePhotoOutput()
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
                self.photoOutput = photoOutput
                print("Added photo output to session")
            } else {
                print("Could not add photo output to session")
            }
            
            // Commit session configuration before starting
            captureSession.commitConfiguration()
            
            // Optimize camera settings for barcode scanning
            do {
                try captureDevice.lockForConfiguration()
                
                // Set focus mode for better barcode detection
                if captureDevice.isFocusModeSupported(.continuousAutoFocus) {
                    captureDevice.focusMode = .continuousAutoFocus
                    print("Set continuous autofocus for barcode scanning")
                }
                
                // Set exposure mode for better contrast
                if captureDevice.isExposureModeSupported(.continuousAutoExposure) {
                    captureDevice.exposureMode = .continuousAutoExposure
                    print("Set continuous auto exposure for barcode scanning")
                }
                
                // Enable torch if available (for better scanning in low light)
                if captureDevice.hasTorch && captureDevice.isTorchModeSupported(.auto) {
                    captureDevice.torchMode = .auto
                    print("Enabled auto torch for barcode scanning")
                }
                
                captureDevice.unlockForConfiguration()
            } catch {
                print("Failed to configure camera settings: \(error)")
            }
            
            // Store session reference
            self.captureSession = captureSession
            
            // Start session on main thread to avoid internal collection mutation issues
            DispatchQueue.main.async {
                self.startNewSession(captureSession)
            }
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    private func startNewSession(_ captureSession: AVCaptureSession) {
        // Ensure session is not already running
        guard !captureSession.isRunning else {
            print("Camera session already running")
            self.isScanning = true
            return
        }
        
        // Start the session
        captureSession.startRunning()
        print("Camera session started successfully")
        self.isScanning = true
    }
    
    private func stopCamera() {
        DispatchQueue.main.async {
            if let session = self.captureSession, session.isRunning {
                print("Stopping camera session")
                session.stopRunning()
            }
            self.isScanning = false
        }
    }
}

// MARK: - Camera Preview View

#if os(iOS)
struct CameraPreviewView: UIViewRepresentable {
    @Binding var captureSession: AVCaptureSession?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.frame = CGRect(x: 0, y: 0, width: 700, height: 500)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession ?? AVCaptureSession())
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        
        // Fix orientation for iPad - force landscape orientation
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            previewLayer.connection?.videoOrientation = .landscapeRight
        }
        #endif
        
        view.layer.addSublayer(previewLayer)
        
        // Store the preview layer for later updates
        view.tag = 999 // Use tag to identify the preview layer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.session = captureSession
            // Update frame when view size changes
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
                
                // Maintain landscape orientation for iPad
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    previewLayer.connection?.videoOrientation = .landscapeRight
                }
                #endif
            }
        }
    }
}
#else
struct CameraPreviewView: NSViewRepresentable {
    @Binding var captureSession: AVCaptureSession?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.frame = CGRect(x: 0, y: 0, width: 700, height: 500)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession ?? AVCaptureSession())
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer?.addSublayer(previewLayer)
        
        // Store the preview layer for later updates
        // Note: NSView.tag is read-only, so we'll identify by layer type
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let previewLayer = nsView.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.session = captureSession
            // Update frame when view size changes
            DispatchQueue.main.async {
                previewLayer.frame = nsView.bounds
            }
        }
    }
}
#endif

// MARK: - Camera Delegate for Barcode Detection

class CameraDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onBarcodeDetected: (([String]) -> Void)?
    var onFrameReceived: ((CMSampleBuffer) -> Void)?
    
    // Thread-safe queue for frame updates
    private let frameQueue = DispatchQueue(label: "com.aromex.frameQueue", qos: .userInitiated)
    private var lastFrameTime: CFTimeInterval = 0
    private let frameRateLimit: CFTimeInterval = 1.0 / 30.0 // Limit to 30 FPS
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let currentTime = CACurrentMediaTime()
        
        // Rate limit frame updates to prevent overwhelming the UI
        guard currentTime - lastFrameTime >= frameRateLimit else { return }
        lastFrameTime = currentTime
        
        // Store the current frame for instant capture (rate limited)
        frameQueue.async { [weak self] in
            DispatchQueue.main.async {
                self?.onFrameReceived?(sampleBuffer)
            }
        }
        
        // Barcode detection on background queue
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let results = request.results as? [VNBarcodeObservation] else { return }
            
            // Extract all barcode payloads
            let barcodes = results.compactMap { $0.payloadStringValue }
            
            if !barcodes.isEmpty {
                DispatchQueue.main.async {
                    self?.onBarcodeDetected?(barcodes)
                }
            }
        }
        
        // Configure request for maximum barcode detection quality
        request.revision = VNDetectBarcodesRequestRevision3 // Use latest revision
        request.symbologies = [.QR, .Aztec, .DataMatrix, .PDF417, .Code128, .Code93, .Code39, .EAN13, .EAN8, .UPCE] // Support all common barcode types (UPCA is handled by EAN13)
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}

// MARK: - Photo Capture Delegate

#if os(iOS)
class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void
    
    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            completion(nil)
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("Could not create image from photo data")
            completion(nil)
            return
        }
        
        completion(image)
    }
}
#endif

// MARK: - iPhone Barcode Scanner Sheet

#if os(iOS)
    struct iPhoneBarcodeScannerSheet: View {
        @Binding var imeiText: String
        @Binding var storedImeis: [String]
        @Environment(\.dismiss) private var dismiss
        @State private var captureSession: AVCaptureSession?
        @State private var cameraDelegate = CameraDelegate()
        @State private var detectedBarcodes: [String] = []
        @State private var showingBarcodeSelection = false
        @State private var currentVideoFrame: CMSampleBuffer?
        @State private var isCapturingPhoto = false
        #if os(iOS)
        @State private var capturedImage: UIImage?
        #endif
        @State private var showingCapturedImage = false
        @State private var capturedImageBarcodes: [String] = []
        @State private var isFlashlightOn = true
        @State private var captureDevice: AVCaptureDevice?
        
        // IMEI validation state
        @State private var isCheckingImei = false
        @State private var showImeiDuplicateAlert = false
        @State private var duplicateImeiMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Full screen background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                        // Header with device-specific layout
                        Group {
                            if UIDevice.current.userInterfaceIdiom == .phone {
                                // iPhone: Symmetric layout with flashlight button
                                HStack {
                                    Spacer()
                                        .frame(width: 44)
                                    
                                    VStack(spacing: 8) {
                                        Text("Scan Barcode")
                                            .font(.system(size: 26, weight: .bold))
                                            .foregroundColor(.white)
                                        
                                        Text("Position the barcode within the frame")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        toggleFlashlight()
                                    }) {
                                        Image(systemName: isFlashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                            .font(.system(size: 22, weight: .medium))
                                            .foregroundColor(.white)
                                            .frame(width: 44, height: 44)
                                            .background(
                                                Circle()
                                                    .fill(Color.black.opacity(0.4))
                                                    .overlay(
                                                        Circle()
                                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                    )
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            } else {
                                // iPad: Centered layout without flashlight button
                                VStack(spacing: 8) {
                                    Text("Scan Barcode")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Text("Position the barcode within the frame")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.top, 25)
                        .padding(.bottom, 25)
                        .padding(.horizontal, 20)
                    
                    // Camera preview area - responsive sizing
                    ZStack {
                        // Camera frame - larger on iPad
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.6), lineWidth: 3)
                            .frame(
                                width: UIDevice.current.userInterfaceIdiom == .pad ? 500 : 350,
                                height: UIDevice.current.userInterfaceIdiom == .pad ? 350 : 250
                            )
                        
                        // Camera preview - larger on iPad
                        if let session = captureSession {
                            CameraPreviewView(captureSession: .constant(session))
                                .frame(
                                    width: UIDevice.current.userInterfaceIdiom == .pad ? 480 : 330,
                                    height: UIDevice.current.userInterfaceIdiom == .pad ? 330 : 230
                                )
                                .cornerRadius(16)
                                .clipped()
                        }
                        
                        // Scanning overlay with corner indicators - responsive sizing
                        VStack {
                            HStack {
                                // Top-left corner
                                VStack(alignment: .leading, spacing: 0) {
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4
                                        )
                                        .foregroundColor(.green)
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30
                                        )
                                        .foregroundColor(.green)
                                }
                                Spacer()
                                // Top-right corner
                                VStack(alignment: .trailing, spacing: 0) {
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4
                                        )
                                        .foregroundColor(.green)
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30
                                        )
                                        .foregroundColor(.green)
                                }
                            }
                            Spacer()
                            HStack {
                                // Bottom-left corner
                                VStack(alignment: .leading, spacing: 0) {
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30
                                        )
                                        .foregroundColor(.green)
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4
                                        )
                                        .foregroundColor(.green)
                                }
                                Spacer()
                                // Bottom-right corner
                                VStack(alignment: .trailing, spacing: 0) {
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30
                                        )
                                        .foregroundColor(.green)
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4
                                        )
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .frame(
                            width: UIDevice.current.userInterfaceIdiom == .pad ? 500 : 350,
                            height: UIDevice.current.userInterfaceIdiom == .pad ? 350 : 250
                        )
                    }
                    .padding(.bottom, 35)
                    
                    // Action buttons - responsive sizing
                    VStack(spacing: UIDevice.current.userInterfaceIdiom == .pad ? 20 : 16) {
                        // Capture button
                        Button(action: {
                            capturePhoto()
                        }) {
                            HStack(spacing: 8) {
                                if isCapturingPhoto {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .font(.system(
                                            size: UIDevice.current.userInterfaceIdiom == .pad ? 18 : 16,
                                            weight: .medium
                                        ))
                                }
                                     Text("Take Photo")
                                         .font(.system(
                                            size: UIDevice.current.userInterfaceIdiom == .pad ? 18 : 16,
                                            weight: .semibold
                                         ))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 400 : .infinity)
                        .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 18 : 14)
                        .background(
                            RoundedRectangle(cornerRadius: UIDevice.current.userInterfaceIdiom == .pad ? 16 : 12)
                                .fill(Color.blue)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isCapturingPhoto)
                    
                    // Cancel button
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(
                                size: UIDevice.current.userInterfaceIdiom == .pad ? 18 : 16,
                                weight: .semibold
                            ))
                            .foregroundColor(.white)
                            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 400 : .infinity)
                            .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 18 : 14)
                            .background(
                                RoundedRectangle(cornerRadius: UIDevice.current.userInterfaceIdiom == .pad ? 16 : 12)
                                    .fill(Color.red.opacity(0.8))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 20)
                    
                    Spacer()
                }
                
                     // Captured image overlay
                     #if os(iOS)
                     if showingCapturedImage {
                         iPhoneCapturedImageOverlay(
                             image: capturedImage,
                             barcodes: capturedImageBarcodes,
                             onSelect: { barcode in
                                 // Automatically validate and store, like before
                                 Task {
                                     await validateAndAddImeiFromScanner(barcode)
                                 }
                             },
                             onCancel: {
                                 showingCapturedImage = false
                                 capturedImage = nil
                                 capturedImageBarcodes.removeAll()
                             },
                             onRetake: {
                                 showingCapturedImage = false
                                 capturedImage = nil
                                 capturedImageBarcodes.removeAll()
                                 isCapturingPhoto = false
                                 // Turn flashlight back on for iPhone when retaking
                                #if os(iOS)
                                if UIDevice.current.userInterfaceIdiom == .phone {
                                    ensureFlashlightOn()
                                }
                                #endif
                             }
                         )
                     }
                     #endif
                     
                     // Barcode selection overlay
                    if showingBarcodeSelection {
                         iPhoneBarcodeSelectionOverlay(
                             barcodes: detectedBarcodes,
                             onSelect: { barcode in
                                // Automatically validate and store, like before
                                Task {
                                    await validateAndAddImeiFromScanner(barcode)
                                }
                             },
                             onCancel: {
                                 showingBarcodeSelection = false
                                 detectedBarcodes.removeAll()
                             }
                         )
                     }
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
        }
        .onAppear {
            setupCamera()
        }
        .onDisappear {
            stopCamera()
        }
        .alert("IMEI Already Exists", isPresented: $showImeiDuplicateAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(duplicateImeiMessage)
        }
    }
    
        private func setupCamera() {
            let captureSession = AVCaptureSession()
            captureSession.beginConfiguration()
            
            // Get back camera device first
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                print("Failed to get camera device")
                return
            }
            
            self.captureDevice = device
            
            // Check device-specific preset support and set highest quality
            let deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
            
            if device.supportsSessionPreset(.hd4K3840x2160) && captureSession.canSetSessionPreset(.hd4K3840x2160) {
                captureSession.sessionPreset = .hd4K3840x2160
                print("Using 4K quality for \(deviceType) barcode scanning")
            } else if device.supportsSessionPreset(.hd1920x1080) && captureSession.canSetSessionPreset(.hd1920x1080) {
                captureSession.sessionPreset = .hd1920x1080
                print("Using 1080p quality for \(deviceType) barcode scanning")
            } else if device.supportsSessionPreset(.hd1280x720) && captureSession.canSetSessionPreset(.hd1280x720) {
                captureSession.sessionPreset = .hd1280x720
                print("Using 720p quality for \(deviceType) barcode scanning")
            } else {
                captureSession.sessionPreset = .high
                print("Using high quality preset for \(deviceType) barcode scanning")
            }
            
            captureSession.addInput(input)
            
            // Configure camera settings for highest quality
            do {
                try device.lockForConfiguration()
                
                // Set focus and exposure for barcode scanning
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                
                // Enable flashlight by default for iPhone only
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .phone && device.hasTorch && device.isTorchAvailable {
                    device.torchMode = .on
                    try device.setTorchModeOn(level: 1.0)
                    print("Flashlight enabled for iPhone barcode scanning")
                }
                #endif
                
                device.unlockForConfiguration()
            } catch {
                print("Failed to configure camera: \(error)")
            }
            
            let videoOutput = AVCaptureVideoDataOutput()
            
            // Set video output to match session preset for highest quality
            let preset = captureSession.sessionPreset
            var width: Int = 1920
            var height: Int = 1080
            
            switch preset {
            case .hd4K3840x2160:
                width = 3840
                height = 2160
            case .hd1920x1080:
                width = 1920
                height = 1080
            case .hd1280x720:
                width = 1280
                height = 720
            default:
                width = 1920
                height = 1080
            }
            
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = false
            
            cameraDelegate.onBarcodeDetected = { barcodes in
                // Auto-scanning disabled - user must capture manually
            }
            
            cameraDelegate.onFrameReceived = { sampleBuffer in
                DispatchQueue.main.async {
                    self.currentVideoFrame = sampleBuffer
                }
            }
            
            let videoQueue = DispatchQueue(label: "com.aromex.iphone.videoQueue", qos: .userInitiated)
            videoOutput.setSampleBufferDelegate(cameraDelegate, queue: videoQueue)
            
            captureSession.addOutput(videoOutput)
            captureSession.commitConfiguration()
            
            DispatchQueue.main.async {
                self.captureSession = captureSession
                captureSession.startRunning()
                
                // Ensure flashlight is on after session starts
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.ensureFlashlightOn()
                }
            }
        }
    
         private func capturePhoto() {
             guard let videoFrame = currentVideoFrame else { return }
             
             isCapturingPhoto = true
             
             // Convert frame to image and freeze the display
             #if os(iOS)
             if let image = imageFromSampleBuffer(videoFrame) {
                 DispatchQueue.main.async {
                     self.capturedImage = image
                     self.showingCapturedImage = true
                     self.isCapturingPhoto = false
                     // Turn off flashlight after capture (iPhone only)
                    if UIDevice.current.userInterfaceIdiom == .phone,
                       let device = self.captureDevice, device.hasTorch {
                        do {
                            try device.lockForConfiguration()
                            device.torchMode = .off
                            device.unlockForConfiguration()
                            self.isFlashlightOn = false
                        } catch {
                            print("Failed to turn off flashlight after capture: \(error)")
                        }
                    }
                 }
                 
                 // Analyze the frame for barcodes in background
                 analyzeFrameForBarcodes(videoFrame)
             } else {
                 isCapturingPhoto = false
             }
             #endif
         }
    
    private func analyzeFrameForBarcodes(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectBarcodesRequest { request, error in
            guard let results = request.results as? [VNBarcodeObservation] else { return }
            
            let barcodes = results.compactMap { $0.payloadStringValue }
            
            DispatchQueue.main.async {
                self.capturedImageBarcodes = barcodes
                
                // Always show captured image so user can verify and retake if needed
                // The captured image overlay will handle single/multiple/no barcode scenarios
            }
        }
        
        request.revision = VNDetectBarcodesRequestRevision3
        request.symbologies = [.QR, .Aztec, .DataMatrix, .PDF417, .Code128, .Code93, .Code39, .EAN13, .EAN8, .UPCE]
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
    
    private func stopCamera() {
        #if os(iOS)
        // Turn off flashlight before stopping camera (iPhone only)
        if UIDevice.current.userInterfaceIdiom == .phone,
           let device = captureDevice, device.hasTorch {
            do {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
                print("Flashlight turned off when stopping camera")
            } catch {
                print("Failed to turn off flashlight: \(error)")
            }
        }
        #endif
        
        captureSession?.stopRunning()
        captureSession = nil
    }
    
    private func toggleFlashlight() {
        #if os(iOS)
        // Only allow flashlight toggle on iPhone
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let device = captureDevice, 
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            
            if isFlashlightOn {
                device.torchMode = .off
                isFlashlightOn = false
                print("Flashlight turned off")
            } else {
                if device.isTorchAvailable {
                    device.torchMode = .on
                    try device.setTorchModeOn(level: 1.0)
                    isFlashlightOn = true
                    print("Flashlight turned on")
                }
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to toggle flashlight: \(error)")
        }
        #endif
    }
    
    private func ensureFlashlightOn() {
        #if os(iOS)
        // Only ensure flashlight is on for iPhone
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let device = captureDevice, 
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Force flashlight to stay on
            if device.isTorchAvailable {
                device.torchMode = .on
                try device.setTorchModeOn(level: 1.0)
                isFlashlightOn = true
                print("Flashlight ensured to be on for iPhone")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to ensure flashlight on: \(error)")
        }
        #endif
    }
    
    #if os(iOS)
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        // Create UIImage with correct orientation for iPhone
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        
        return image
    }
    #endif
    
    // MARK: - Scanner IMEI Validation
    private func validateAndAddImeiFromScanner(_ barcode: String) async {
        // Check if IMEI already exists in stored list
        if storedImeis.contains(barcode) {
            await MainActor.run {
                duplicateImeiMessage = "IMEI '\(barcode)' is already in the list"
                showImeiDuplicateAlert = true
            }
            return
        }
        
        do {
            let db = Firestore.firestore()
            let query = db.collection("IMEI").whereField("imei", isEqualTo: barcode).limit(to: 1)
            let snapshot = try await query.getDocuments()
            
            await MainActor.run {
                if snapshot.documents.isEmpty {
                    // IMEI is unique - automatically store it and close scanner
                    storedImeis.append(barcode)
                    dismiss()
                } else {
                    // IMEI already exists in database - show alert but keep scanner open
                    duplicateImeiMessage = "IMEI '\(barcode)' already exists in the inventory"
                    showImeiDuplicateAlert = true
                }
            }
        } catch {
            await MainActor.run {
                // Error occurred - show alert but keep scanner open
                duplicateImeiMessage = "Error checking IMEI: \(error.localizedDescription)"
                showImeiDuplicateAlert = true
            }
        }
    }
}
#endif

// MARK: - iPhone Barcode Selection Overlay

#if os(iOS)
struct iPhoneBarcodeSelectionOverlay: View {
    let barcodes: [String]
    let onSelect: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.9).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Select Barcode")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Choose which barcode to use")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.top, 40)
                .padding(.bottom, 20)
                
                // Barcode list
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(barcodes.enumerated()), id: \.offset) { index, barcode in
                            Button(action: {
                                onSelect(barcode)
                            }) {
                                HStack(spacing: 12) {
                                    // Number badge
                                    Text("\(index + 1)")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Color.blue)
                                        .clipShape(Circle())
                                    
                                    // Barcode text
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(barcode)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                            .truncationMode(.tail)
                                        
                                        Text("Tap to select")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    
                                    Spacer()
                                    
                                    // Arrow
                                    Text("→")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Cancel button
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.8))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}
#endif

// MARK: - iPhone Captured Image Overlay

#if os(iOS)
struct iPhoneCapturedImageOverlay: View {
    let image: UIImage?
    let barcodes: [String]
    let onSelect: (String) -> Void
    let onCancel: () -> Void
    let onRetake: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.95).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header - more compact on iPad
                VStack(spacing: UIDevice.current.userInterfaceIdiom == .pad ? 8 : 12) {
                    Text("Captured Image")
                        .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 20 : 22, weight: .bold))
                        .foregroundColor(.white)
                    
                    if barcodes.isEmpty {
                        Text("No barcodes detected")
                            .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 14 : 16, weight: .medium))
                            .foregroundColor(.orange)
                    } else {
                        Text("\(barcodes.count) barcode\(barcodes.count == 1 ? "" : "s") detected")
                            .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 14 : 16, weight: .medium))
                            .foregroundColor(.green)
                    }
                    
                    Text("Review the image and codes below")
                        .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 12 : 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 25 : 40)
                .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 15 : 24)
                
                // Captured image with border - smaller on iPad for more space
                if let capturedImage = image {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .frame(
                                width: UIDevice.current.userInterfaceIdiom == .pad ? 280 : 320,
                                height: UIDevice.current.userInterfaceIdiom == .pad ? 200 : 240
                            )
                        
                        Image(uiImage: capturedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 260 : 300,
                                maxHeight: UIDevice.current.userInterfaceIdiom == .pad ? 180 : 220
                            )
                            .cornerRadius(12)
                            .clipped()
                    }
                    .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 10 : 24)
                }
                
                // Barcode list with refined UI
                if barcodes.count > 1 {
                    VStack(spacing: UIDevice.current.userInterfaceIdiom == .pad ? 8 : 16) {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(barcodes.enumerated()), id: \.offset) { index, barcode in
                                    Button(action: {
                                        onSelect(barcode)
                                    }) {
                                        HStack(spacing: 16) {
                                            // Number badge with gradient
                                            ZStack {
                                                Circle()
                                                    .fill(LinearGradient(
                                                        colors: [.blue, .blue.opacity(0.8)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ))
                                                    .frame(width: 36, height: 36)
                                                
                                                Text("\(index + 1)")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                            
                                            // Barcode content
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(barcode)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(2)
                                                    .truncationMode(.tail)
                                                
                                                Text("Tap to use this barcode")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.white.opacity(0.8))
                                            }
                                            
                                            Spacer()
                                            
                                            // Selection arrow
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                        }
                        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 20)
                    }
                    .frame(maxHeight: UIDevice.current.userInterfaceIdiom == .pad ? 500 : 240)
                    }
                } else if barcodes.count == 1 {
                    // Single barcode display
                    VStack(spacing: 16) {
                        Text("Detected barcode:")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.green)
                            
                            Text(barcodes[0])
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .truncationMode(.tail)
                            
                            Spacer()
                        }
                        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 30 : 20)
                        .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 20 : 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.green.opacity(0.4), lineWidth: 1)
                                )
                        )
                    }
                } else {
                    // No barcodes detected
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)
                        
                        Text("No barcodes detected in this image")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Try repositioning the camera or ensure the barcode is clearly visible")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 60 : 40)
                }
                
                Spacer()
                
                // Action buttons - more compact on iPad
                VStack(spacing: UIDevice.current.userInterfaceIdiom == .pad ? 10 : 16) {
                    // Primary action button (only show for single barcode)
                    if barcodes.count == 1 {
                        Button(action: {
                            onSelect(barcodes[0])
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 14 : 16, weight: .medium))
                                Text("Use This Barcode")
                                    .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 14 : 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 12 : 16)
                            .background(
                                RoundedRectangle(cornerRadius: UIDevice.current.userInterfaceIdiom == .pad ? 10 : 12)
                                    .fill(LinearGradient(
                                        colors: [.green, .green.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Secondary buttons - smaller on iPad
                    HStack(spacing: UIDevice.current.userInterfaceIdiom == .pad ? 8 : 12) {
                        // Retake photo button
                        Button(action: onRetake) {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.rotate")
                                    .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 12 : 14, weight: .medium))
                                Text("Retake")
                                    .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 13 : 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 10 : 14)
                            .background(
                                RoundedRectangle(cornerRadius: UIDevice.current.userInterfaceIdiom == .pad ? 10 : 12)
                                    .fill(Color.blue.opacity(0.8))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Cancel button
                        Button(action: onCancel) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 12 : 14, weight: .medium))
                                Text("Cancel")
                                    .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 13 : 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 10 : 14)
                            .background(
                                RoundedRectangle(cornerRadius: UIDevice.current.userInterfaceIdiom == .pad ? 10 : 12)
                                    .fill(Color.red.opacity(0.8))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 20)
                .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 30 : 40)
            }
        }
    }
}
#endif


// MARK: - Color Dropdown Button
struct ColorDropdownButton: View {
    @Binding var searchText: String
    @Binding var selectedColor: String
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    @FocusState.Binding var isFocused: Bool
    @Binding var internalSearchText: String
    let isLoading: Bool
    
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
                .onChange(of: searchText) { newValue in
                    // Sync internal search with display text
                    internalSearchText = newValue
                    if !newValue.isEmpty && !isOpen && newValue != selectedColor {
                        isOpen = true
                    }
                }
                .onChange(of: isOpen) { newValue in
                    // Clear internal search when opening dropdown to show full list
                    if newValue {
                        internalSearchText = ""
                    }
                }
                .onChange(of: isFocused) { focused in
                    if focused && !isOpen {
                        isOpen = true
                    }
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
                        print("Color dropdown button clicked, isOpen before: \(isOpen)")
                        withAnimation {
                            isOpen.toggle()
                        }
                        print("Color dropdown button clicked, isOpen after: \(isOpen)")
                        if isOpen {
                            isFocused = false
                        }
                    }) {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
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
                            print("Color button frame captured: \(buttonFrame)")
                        }
                        .onChange(of: geometry.frame(in: .global)) { newFrame in
                            buttonFrame = newFrame
                        }
                }
            )
    }
}

// MARK: - Color Dropdown Overlay
struct ColorDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedColor: String
    @Binding var searchText: String
    @Binding var internalSearchText: String
    let colors: [String]
    let buttonFrame: CGRect
    let onAddColor: (String) -> Void
    
    private var filteredColors: [String] {
        print("ColorDropdownOverlay - Total colors: \(colors.count), colors: \(colors)")
        print("ColorDropdownOverlay - Internal search text: '\(internalSearchText)'")
        
        if internalSearchText.isEmpty {
            let allColors = colors.sorted()
            print("ColorDropdownOverlay - Showing all colors: \(allColors)")
            return allColors // Show all colors sorted alphabetically when no search text
        } else {
            let filtered = colors.filter { color in
                color.localizedCaseInsensitiveContains(internalSearchText)
            }.sorted()
            print("ColorDropdownOverlay - Filtered colors: \(filtered)")
            return filtered
        }
    }
    
    private var shouldShowAddOption: Bool {
        return !internalSearchText.isEmpty && !colors.contains { $0.localizedCaseInsensitiveCompare(internalSearchText) == .orderedSame }
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
            print("ColorDropdownOverlay appeared with \(colors.count) colors: \(colors)")
            print("ColorDropdownOverlay buttonFrame: \(buttonFrame)")
        }
    }
    
    // MARK: - Inline Dropdown
    private var inlineDropdown: some View {
        VStack(spacing: 0) {
            // Add color option (if applicable)
            if shouldShowAddOption {
                VStack(spacing: 0) {
                    cleanColorRow(
                        title: "Add '\(internalSearchText)'",
                        isAddOption: true,
                        action: {
                            isOpen = false
                            onAddColor(internalSearchText)
                        }
                    )
                    
                    // Separator after add option
                    if !filteredColors.isEmpty {
                        Divider()
                            .background(Color.secondary.opacity(0.4))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }
                }
            }
            
            // Existing colors - always use ScrollView for consistency
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredColors.enumerated()), id: \.element) { index, color in
                        VStack(spacing: 0) {
                            cleanColorRow(
                                title: color,
                                isAddOption: false,
                                action: {
                                    print("Selected color: \(color)")
                                    isOpen = false
                                    selectedColor = color
                                    searchText = color
                                }
                            )
                            
                            // Divider between items (except for the last one)
                            if index < filteredColors.count - 1 {
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .frame(maxHeight: dynamicHeight)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    // MARK: - Positioned Dropdown
    private var positionedDropdown: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Add color option (if applicable)
                if shouldShowAddOption {
                    VStack(spacing: 0) {
                        cleanColorRow(
                            title: "Add '\(internalSearchText)'",
                            isAddOption: true,
                            action: {
                                isOpen = false
                                onAddColor(internalSearchText)
                            }
                        )
                        
                        // Separator after add option
                        if !filteredColors.isEmpty {
                            Divider()
                                .background(Color.secondary.opacity(0.4))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                
                // Existing colors in ScrollView (macOS only)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredColors.enumerated()), id: \.element) { index, color in
                            VStack(spacing: 0) {
                                cleanColorRow(
                                    title: color,
                                    isAddOption: false,
                                    action: {
                                        print("Selected color: \(color)")
                                        isOpen = false
                                        selectedColor = color
                                        searchText = color
                                    }
                                )
                                .onAppear {
                                    print("Rendering color row: \(color)")
                                }
                                
                                // Divider between items
                                if index < filteredColors.count - 1 {
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
        let colorCount = filteredColors.count
        
        if colorCount <= 4 {
            // For small lists, calculate exact height
            let colorHeight = CGFloat(colorCount) * itemHeight
            let totalHeight = addOptionHeight + colorHeight
            return min(totalHeight, 240)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (4 * itemHeight), 240)
        }
    }
    
    // MARK: - Dynamic Height Calculation
    private var dynamicHeight: CGFloat {
        let itemHeight: CGFloat = 50
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        
        if filteredColors.count <= 3 {
            // For smaller lists, calculate exact height
            let colorHeight = CGFloat(filteredColors.count) * itemHeight
            let totalHeight = addOptionHeight + colorHeight
            return min(totalHeight, 250)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (3 * itemHeight), 250)
        }
    }
    
    // MARK: - Color Row Views
    
    private func cleanColorRow(title: String, isAddOption: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isAddOption {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isAddOption ? Color(red: 0.20, green: 0.60, blue: 0.40) : .primary)
                    .fontWeight(isAddOption ? .semibold : .medium)
                
                Spacer()
                
                if !isAddOption && selectedColor == title {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovering in
            // Subtle hover effect for better UX
        }
    }
}

// MARK: - Capacity Dropdown Button
struct CapacityDropdownButton: View {
    @Binding var searchText: String
    @Binding var selectedCapacity: String
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    @FocusState.Binding var isFocused: Bool
    @Binding var internalSearchText: String
    @Binding var capacityUnit: String
    let isLoading: Bool
    
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
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onSubmit {
                    isFocused = false
                }
                .onChange(of: searchText) { newValue in
                    // Sync internal search with display text
                    internalSearchText = newValue
                    if !newValue.isEmpty && !isOpen && newValue != selectedCapacity {
                        isOpen = true
                    }
                }
                .onChange(of: isOpen) { newValue in
                    // Clear internal search when opening dropdown to show full list
                    if newValue {
                        internalSearchText = ""
                    }
                }
                .onChange(of: isFocused) { focused in
                    if focused && !isOpen {
                        isOpen = true
                    }
                }
            
            // Unit selection buttons and dropdown button positioned on the right
            HStack(spacing: 8) {
                Spacer()
                
                // Unit selection buttons
                HStack(spacing: 4) {
                    Button(action: {
                        capacityUnit = "GB"
                    }) {
                        Text("GB")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(capacityUnit == "GB" ? .white : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(capacityUnit == "GB" ? Color.blue : Color.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        capacityUnit = "TB"
                    }) {
                        Text("TB")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(capacityUnit == "TB" ? .white : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(capacityUnit == "TB" ? Color.blue : Color.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 20)
                } else {
                    Button(action: {
                        print("Capacity dropdown button clicked, isOpen before: \(isOpen)")
                        withAnimation {
                            isOpen.toggle()
                        }
                        print("Capacity dropdown button clicked, isOpen after: \(isOpen)")
                        if isOpen {
                            isFocused = false
                        }
                    }) {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
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
                            print("Capacity button frame captured: \(buttonFrame)")
                        }
                        .onChange(of: geometry.frame(in: .global)) { newFrame in
                            buttonFrame = newFrame
                        }
                }
            )
    }
}

// MARK: - Capacity Dropdown Overlay
struct CapacityDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedCapacity: String
    @Binding var searchText: String
    @Binding var internalSearchText: String
    let capacities: [String]
    let buttonFrame: CGRect
    let onAddCapacity: (String) -> Void
    
    private var filteredCapacities: [String] {
        print("CapacityDropdownOverlay - Total capacities: \(capacities.count), capacities: \(capacities)")
        print("CapacityDropdownOverlay - Internal search text: '\(internalSearchText)'")
        
        if internalSearchText.isEmpty {
            let allCapacities = capacities.sorted()
            print("CapacityDropdownOverlay - Showing all capacities: \(allCapacities)")
            return allCapacities // Show all capacities sorted alphabetically when no search text
        } else {
            let filtered = capacities.filter { capacity in
                capacity.localizedCaseInsensitiveContains(internalSearchText)
            }.sorted()
            print("CapacityDropdownOverlay - Filtered capacities: \(filtered)")
            return filtered
        }
    }
    
    private var shouldShowAddOption: Bool {
        return !internalSearchText.isEmpty && !capacities.contains { $0.localizedCaseInsensitiveCompare(internalSearchText) == .orderedSame }
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
            print("CapacityDropdownOverlay appeared with \(capacities.count) capacities: \(capacities)")
            print("CapacityDropdownOverlay buttonFrame: \(buttonFrame)")
        }
    }
    
    // MARK: - Inline Dropdown
    private var inlineDropdown: some View {
        VStack(spacing: 0) {
            // Add capacity option (if applicable)
            if shouldShowAddOption {
                VStack(spacing: 0) {
                    cleanCapacityRow(
                        title: "Add '\(internalSearchText)'",
                        isAddOption: true,
                        action: {
                            isOpen = false
                            onAddCapacity(internalSearchText)
                        }
                    )
                    
                    // Separator after add option
                    if !filteredCapacities.isEmpty {
                        Divider()
                            .background(Color.secondary.opacity(0.4))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }
                }
            }
            
            // Existing capacities - always use ScrollView for consistency
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredCapacities.enumerated()), id: \.element) { index, capacity in
                        VStack(spacing: 0) {
                            cleanCapacityRow(
                                title: capacity,
                                isAddOption: false,
                                action: {
                                    print("Selected capacity: \(capacity)")
                                    isOpen = false
                                    selectedCapacity = capacity
                                    searchText = capacity
                                }
                            )
                            
                            // Divider between items (except for the last one)
                            if index < filteredCapacities.count - 1 {
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .frame(maxHeight: dynamicHeight)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    // MARK: - Positioned Dropdown (macOS)
    private var positionedDropdown: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Add capacity option (if applicable)
                if shouldShowAddOption {
                    VStack(spacing: 0) {
                        cleanCapacityRow(
                            title: "Add '\(internalSearchText)'",
                            isAddOption: true,
                            action: {
                                isOpen = false
                                onAddCapacity(internalSearchText)
                            }
                        )
                        
                        // Separator after add option
                        if !filteredCapacities.isEmpty {
                            Divider()
                                .background(Color.secondary.opacity(0.4))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                
                // Existing capacities in ScrollView (macOS only)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredCapacities.enumerated()), id: \.element) { index, capacity in
                            VStack(spacing: 0) {
                                cleanCapacityRow(
                                    title: capacity,
                                    isAddOption: false,
                                    action: {
                                        print("Selected capacity: \(capacity)")
                                        isOpen = false
                                        selectedCapacity = capacity
                                        searchText = capacity
                                    }
                                )
                                .onAppear {
                                    print("Rendering capacity row: \(capacity)")
                                }
                                
                                // Divider between items
                                if index < filteredCapacities.count - 1 {
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
        let capacityCount = filteredCapacities.count
        
        if capacityCount <= 4 {
            // For small lists, calculate exact height
            let capacityHeight = CGFloat(capacityCount) * itemHeight
            let totalHeight = addOptionHeight + capacityHeight
            return min(totalHeight, 240)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (4 * itemHeight), 240)
        }
    }
    
    // MARK: - Dynamic Height Calculation
    private var dynamicHeight: CGFloat {
        let itemHeight: CGFloat = 50
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        
        if filteredCapacities.count <= 3 {
            // For smaller lists, calculate exact height
            let capacityHeight = CGFloat(filteredCapacities.count) * itemHeight
            let totalHeight = addOptionHeight + capacityHeight
            return min(totalHeight, 250)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (3 * itemHeight), 250)
        }
    }
    
    // MARK: - Capacity Row Views
    
    private func cleanCapacityRow(title: String, isAddOption: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isAddOption {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isAddOption ? Color(red: 0.20, green: 0.60, blue: 0.40) : .primary)
                    .fontWeight(isAddOption ? .semibold : .medium)
                
                Spacer()
                
                if !isAddOption && selectedCapacity == title {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40)) // App's green theme
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovering in
            // Subtle hover effect for better UX
        }
    }
}


#Preview {
    AddProductDialog(isPresented: .constant(true), onDismiss: nil, onSave: { _ in })
}
