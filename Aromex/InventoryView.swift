//
//  PurchaseView.swift
//  Aromex
//
//  Created by User on 9/17/25.
//

import SwiftUI
import FirebaseFirestore
#if os(iOS)
import UIKit
#endif

struct PurchaseView: View {
    @Binding var showingSupplierDropdown: Bool
    @Binding var selectedSupplier: EntityWithType?
    @Binding var supplierButtonFrame: CGRect
    @Binding var allEntities: [EntityWithType]
    @Binding var supplierSearchText: String
    @Binding var entityFetchError: Bool
    @Binding var retryFetchEntities: (() -> Void)
    let onPaymentConfirmed: (String) -> Void
    
    @State private var orderNumber: String = "Loading..."
    @State private var orderNumberListener: ListenerRegistration?
    @State private var isOrderNumberCustom: Bool = false
    @State private var originalOrderNumber: String = ""
    @FocusState private var isOrderNumberFieldFocused: Bool
    @State private var selectedDate = Date()
    @State private var showingDatePicker = false
    @State private var showingAddProductDialog = false
    @State private var itemToEdit: PhoneItem?
    @State private var cartItems: [PhoneItem] = []
    @State private var isLoadingEntities = true
    @FocusState private var isSupplierFieldFocused: Bool
    @State private var showingDeleteConfirmation = false
    @State private var itemToDelete: PhoneItem?
    @State private var showingDeleteSuccess = false
    @State private var deletedItemIndex: Int?
    
    // Payment details state
    @State private var gstPercentage: String = ""
    @State private var pstPercentage: String = ""
    @State private var adjustmentAmount: String = ""
    @State private var adjustmentUnit: String = "discount" // Default to discount, options: discount, receive
    @State private var notes: String = ""
    
    // Alert state
    @State private var showValidationAlert: Bool = false
    @State private var validationAlertMessage: String = ""
    @State private var showOverpaymentAlert: Bool = false
    @State private var overpaymentAlertMessage: String = ""
    
	// Middleman payment state
	@State private var useMiddlemanPayment: Bool = false
	@State private var middlemanSearchText: String = ""
	@State private var middlemanInternalSearchText: String = ""
	@State private var showingMiddlemanDropdown: Bool = false
	@State private var selectedMiddleman: EntityWithType? = nil
	@State private var middlemanAmount: String = ""
	@State private var middlemanUnit: String = "give" // Default to give, options: give, receive
	@State private var middlemanCashAmount: String = ""
	@State private var middlemanBankAmount: String = ""
	@State private var middlemanCreditCardAmount: String = ""
    
    // Payment options state
    @State private var cashAmount: String = ""
    @State private var bankAmount: String = ""
    @State private var creditCardAmount: String = ""
    @StateObject private var balanceViewModel = BalanceViewModel()
    
    // Payment confirmation state
    @State private var isConfirmingPayment = false
    @State private var showPaymentSuccess = false
    
    // Scroll proxy for iOS
    #if os(iOS)
    @State private var scrollToField: ((String) -> Void)?
    #endif
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var isCompact: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    var isIPad: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    var isIPadVertical: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular && verticalSizeClass == .compact
        #else
        return false
        #endif
    }
    
    var isMacOS: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Payment Calculations
    var subtotal: Double {
        cartItems.reduce(0) { $0 + $1.unitCost }
    }
    
    var gstAmount: Double {
        let percentage = Double(gstPercentage) ?? 0.0
        return subtotal * (percentage / 100.0)
    }
    
    var pstAmount: Double {
        let percentage = Double(pstPercentage) ?? 0.0
        return subtotal * (percentage / 100.0)
    }
    
    var adjustmentAmountValue: Double {
        return Double(adjustmentAmount) ?? 0.0
    }

    var middlemanPaymentAmountValue: Double {
        guard useMiddlemanPayment, selectedMiddleman != nil, !middlemanAmount.isEmpty else {
            return 0.0
        }
        return Double(middlemanAmount) ?? 0.0
    }
    
    var middlemanCashAmountValue: Double {
        return Double(middlemanCashAmount) ?? 0.0
    }
    
    var middlemanBankAmountValue: Double {
        return Double(middlemanBankAmount) ?? 0.0
    }
    
    var middlemanCreditCardAmountValue: Double {
        return Double(middlemanCreditCardAmount) ?? 0.0
    }
    
    var middlemanCreditAmount: Double {
        let totalPaid = middlemanCashAmountValue + middlemanBankAmountValue + middlemanCreditCardAmountValue
        return max(0, middlemanPaymentAmountValue - totalPaid)
    }
    
    // Overpayment validation
    var isMainPaymentOverpaid: Bool {
        let totalPayment = cashAmountValue + bankAmountValue + creditCardAmountValue
        return totalPayment > grandTotal
    }
    
    var isMiddlemanPaymentOverpaid: Bool {
        let totalMiddlemanPayment = middlemanCashAmountValue + middlemanBankAmountValue + middlemanCreditCardAmountValue
        return totalMiddlemanPayment > middlemanPaymentAmountValue
    }
    
    var grandTotal: Double {
        // Handle adjustment based on unit type
        let adjustmentValue: Double
        if adjustmentUnit == "discount" {
            // Discount is subtracted (negative)
            adjustmentValue = -adjustmentAmountValue
        } else {
            // Receive is added (positive)
            adjustmentValue = adjustmentAmountValue
        }
        
        return subtotal + gstAmount + pstAmount + adjustmentValue
    }
    
    // Payment calculations
    var cashAmountValue: Double {
        return Double(cashAmount) ?? 0.0
    }
    
    var bankAmountValue: Double {
        return Double(bankAmount) ?? 0.0
    }
    
    var creditCardAmountValue: Double {
        return Double(creditCardAmount) ?? 0.0
    }
    
    var creditAmount: Double {
        let totalPaid = cashAmountValue + bankAmountValue + creditCardAmountValue
        return max(0, grandTotal - totalPaid)
    }
    
    var filteredEntities: [EntityWithType] {
        if supplierSearchText.isEmpty {
            return allEntities
        } else {
            return allEntities.filter { entity in
                entity.name.localizedCaseInsensitiveContains(supplierSearchText) ||
                entity.entityType.rawValue.localizedCaseInsensitiveContains(supplierSearchText)
            }
        }
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: selectedDate)
    }
    
    var body: some View {
        #if os(iOS)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    
                    
                    // Form Section
                    if isCompact {
                        iPhoneLayout
                    } else if isIPadVertical {
                        iPhoneLayout
                    } else {
                        iPadMacLayout
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .background(.regularMaterial)
            .onAppear {
                scrollToField = { fieldId in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(fieldId, anchor: .center)
                    }
                }
                retryFetchEntities = { fetchAllEntities() }
                setupOrderNumberListener()
                fetchAllEntities()
            }
            .onDisappear {
                stopOrderNumberListener()
            }
            .onChange(of: showingSupplierDropdown) { isOpen in
                isSupplierFieldFocused = isOpen
            }
            .fullScreenCover(isPresented: $showingAddProductDialog) {
                AddProductDialog(isPresented: $showingAddProductDialog, onDismiss: nil, onSave: { items in
                    cartItems.append(contentsOf: expandedItems(from: items))
                })
            }
            .fullScreenCover(item: $itemToEdit) { item in
                EditProductDialog(isPresented: .constant(true), onDismiss: {
                    itemToEdit = nil
                }, onSave: { items in
                    updateCartItem(with: items.first!)
                }, itemToEdit: item)
            }
            .modifier(DeleteConfirmationModifier(
                isPresented: $showingDeleteConfirmation,
                showingSuccess: $showingDeleteSuccess,
                itemToDelete: itemToDelete,
                onDelete: deleteItem,
                onCancel: { itemToDelete = nil }
            ))
            .alert("Validation Required", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationAlertMessage)
            }
            .alert("Overpayment Detected", isPresented: $showOverpaymentAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(overpaymentAlertMessage)
            }
        }
#else
ScrollView {
    VStack(spacing: 0) {
        
        
        // Form Section
        if isCompact {
            iPhoneLayout
        } else if isIPadVertical {
            iPhoneLayout
        } else {
            iPadMacLayout
        }
        
        Spacer(minLength: 100)
    }
    .padding(.horizontal, 20)
}
.scrollIndicators(.hidden)
.background(.regularMaterial)
.onAppear {
    retryFetchEntities = { fetchAllEntities() }
    setupOrderNumberListener()
    fetchAllEntities()
}
.onDisappear {
    stopOrderNumberListener()
}
.onChange(of: showingSupplierDropdown) { isOpen in
    isSupplierFieldFocused = isOpen
}
.sheet(isPresented: $showingAddProductDialog) {
    AddProductDialog(isPresented: $showingAddProductDialog, onDismiss: nil, onSave: { items in
        cartItems.append(contentsOf: expandedItems(from: items))
    })
}
.sheet(item: $itemToEdit) { item in
    EditProductDialog(isPresented: .constant(true), onDismiss: {
        itemToEdit = nil
    }, onSave: { items in
        updateCartItem(with: items.first!)
    }, itemToEdit: item)
}
.modifier(DeleteConfirmationModifier(
    isPresented: $showingDeleteConfirmation,
    showingSuccess: $showingDeleteSuccess,
    itemToDelete: itemToDelete,
    onDelete: deleteItem,
    onCancel: { itemToDelete = nil }
))
.alert("Validation Required", isPresented: $showValidationAlert) {
    Button("OK", role: .cancel) { }
} message: {
    Text(validationAlertMessage)
}
.alert("Overpayment Detected", isPresented: $showOverpaymentAlert) {
    Button("OK", role: .cancel) { }
} message: {
    Text(overpaymentAlertMessage)
}
#endif
    }
    
    var iPhoneLayout: some View {
        VStack(spacing: 24) {
            // Form Fields Container
            VStack(spacing: 20) {
                orderNumberField
                dateField
                supplierDropdown
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
            
            // Action Button
            addProductButton
            
            // Cart table (iPhone stacked)
            if !cartItems.isEmpty {
                cartTableCompact
                paymentDetailsSection
                compactPaymentOptionsSection
            }
        }
    }
    
    var iPadMacLayout: some View {
        VStack(spacing: 40) {
            // Form Fields Container
            VStack(spacing: 30) {
                HStack(spacing: 24) {
                    orderNumberField
                    dateField
                    supplierDropdown
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                )
            }
            
            // Action Button
            addProductButton
            
            // Cart table (iPad/macOS grid)
            if !cartItems.isEmpty {
                if isIPadVertical {
                    cartTableCompact
                    paymentDetailsSection
                } else {
                    // For iPad horizontal and macOS, cart table full width, then split payment details
                    VStack(spacing: 20) {
                        // Cart table full width
                        if isMacOS {
                            cartTableMacOS
                        } else {
                            cartTableRegular
                        }
                        
                        // Payment options and details side by side below the table
                        HStack(alignment: .top, spacing: 20) {
                            // Left half - payment options
                            paymentOptionsSection
                                .frame(maxWidth: .infinity)
                            
                            // Right half - payment details
                            paymentDetailsSection
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Cart Tables
    private var cartTableCompact: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Added Phones")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
            
            ForEach(Array(cartItems.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 16) {
                    // Header row with title and price
                    HStack(alignment: .top, spacing: 12) {
                        // Product info
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.brand)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text(item.model)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Text("\(item.capacity) \(item.capacityUnit)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Price and status
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "$ %.2f", item.unitCost))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                            
                            statusBadge(text: item.status)
                        }
                    }
                    
                    // Horizontal divider
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Details row with badges
                    HStack(spacing: 8) {
                        uniformBadge(text: item.color)
                        if !item.carrier.isEmpty { uniformBadge(text: item.carrier) }
                        locationBadge(text: item.storageLocation)
                        Spacer()
                    }
                    
                    // IMEI row with action buttons
                    HStack(alignment: .top, spacing: 12) {
                        if !item.imeis.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("IMEI:")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                ForEach(item.imeis, id: \.self) { imei in
                                    Text(imei)
                                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.secondary.opacity(0.1))
                                        )
                                }
                            }
                        }
                        
                        Spacer()
                        
                        VStack(){
                            // Action buttons
                            HStack(spacing: 8) {
                                Button(action: {
                                    itemToEdit = item
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.blue.opacity(0.12))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button(action: {
                                    itemToDelete = item
                                    showingDeleteConfirmation = true
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.red.opacity(0.12))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                )
            }
        }
    }
    
    // Expand multi-IMEI items to one-per-IMEI for table rows
    private func expandedItems(from items: [PhoneItem]) -> [PhoneItem] {
        var result: [PhoneItem] = []
        for item in items {
            if item.imeis.isEmpty {
                result.append(item)
            } else {
                for imei in item.imeis {
                    var single = item
                    // Replace imeis with just one for display row
                    single = PhoneItem(
                        brand: item.brand,
                        model: item.model,
                        capacity: item.capacity,
                        capacityUnit: item.capacityUnit,
                        color: item.color,
                        carrier: item.carrier,
                        status: item.status,
                        storageLocation: item.storageLocation,
                        imeis: [imei],
                        unitCost: item.unitCost
                    )
                    result.append(single)
                }
            }
        }
        return result
    }
    
    private var cartTableRegular: some View {
        VStack(spacing: 0) {
            cartTableRegularHeader
            cartTableRegularContent
        }
    }
    
    private var cartTableRegularHeader: some View {
        let headerColor = Color(red: 0.25, green: 0.33, blue: 0.54)
        let columns: [GridItem] = [
            GridItem(.fixed(30), spacing: 8, alignment: .leading),              // #
            GridItem(.flexible(minimum: 45), spacing: 8, alignment: .leading), // Brand/Model
            GridItem(.fixed(80), spacing: 8, alignment: .leading),              // Capacity
            GridItem(.fixed(70), spacing: 8, alignment: .leading),              // Color
            GridItem(.fixed(90), spacing: 8, alignment: .leading),              // Carrier
            GridItem(.fixed(80), spacing: 8, alignment: .leading),              // Status
            GridItem(.fixed(100), spacing: 8, alignment: .leading),              // Storage
            GridItem(.fixed(140), spacing: 8, alignment: .leading),             // IMEI
            GridItem(.fixed(100), spacing: 8, alignment: .leading),             // Unit Cost
            GridItem(.fixed(100), spacing: 0, alignment: .leading)             // Actions
        ]
        
        return LazyVGrid(columns: columns, spacing: 8) {
            Text("#").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Brand / Model").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Capacity").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Color").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Carrier").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Status").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Storage").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("IMEI").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Unit Cost").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            HStack {
                Text("Actions").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(headerColor)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                )
        )
    }
    
    private var cartTableRegularContent: some View {
        let columns: [GridItem] = [
            GridItem(.fixed(30), spacing: 8, alignment: .leading),              // #
            GridItem(.flexible(minimum: 45), spacing: 8, alignment: .leading), // Brand/Model
            GridItem(.fixed(80), spacing: 8, alignment: .leading),              // Capacity
            GridItem(.fixed(70), spacing: 8, alignment: .leading),              // Color
            GridItem(.fixed(90), spacing: 8, alignment: .leading),              // Carrier
            GridItem(.fixed(80), spacing: 8, alignment: .leading),              // Status
            GridItem(.fixed(100), spacing: 8, alignment: .leading),              // Storage
            GridItem(.fixed(140), spacing: 8, alignment: .leading),             // IMEI
            GridItem(.fixed(100), spacing: 8, alignment: .leading),             // Unit Cost
            GridItem(.fixed(100), spacing: 0, alignment: .leading)             // Actions
        ]
        
        return VStack(spacing: 0) {
            ForEach(cartItems.indices, id: \.self) { index in
                let item = cartItems[index]
                let isLastItem = index == cartItems.count - 1
                
                LazyVGrid(columns: columns, spacing: 8) {
                    Text("\(index + 1)").font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.brand).font(.system(size: 14, weight: .semibold))
                        Text(item.model).font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    Text("\(item.capacity) \(item.capacityUnit)").font(.system(size: 14))
                    Text(item.color).font(.system(size: 14))
                    Text(item.carrier).font(.system(size: 14))
                    Text(item.status).font(.system(size: 14))
                    Text(item.storageLocation).font(.system(size: 14))
                    Text(item.imeis.first ?? "-").font(.system(size: 14))
                    Text(String(format: "$ %.2f", item.unitCost)).font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 8) {
                        Button(action: {
                            itemToEdit = item
                        }) {
                            actionIconButton(systemName: "pencil", tint: Color.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            itemToDelete = item
                            showingDeleteConfirmation = true
                        }) {
                            actionIconButton(systemName: "trash", tint: Color.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.02))
                
                if !isLastItem {
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 12,
                bottomTrailingRadius: 12,
                topTrailingRadius: 12
            )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - macOS Optimized Table
    private var cartTableMacOS: some View {
        VStack(spacing: 0) {
            cartTableMacOSHeader
            cartTableMacOSContent
        }
    }
    
    private var cartTableMacOSHeader: some View {
        let headerColor = Color(red: 0.25, green: 0.33, blue: 0.54)
        let columns: [GridItem] = [
            GridItem(.fixed(40), spacing: 20, alignment: .leading),              // #
            GridItem(.flexible(minimum: 180), spacing: 20, alignment: .leading), // Brand/Model
            GridItem(.fixed(100), spacing: 20, alignment: .leading),             // Capacity
            GridItem(.fixed(100), spacing: 20, alignment: .leading),             // Color
            GridItem(.fixed(120), spacing: 20, alignment: .leading),             // Carrier
            GridItem(.fixed(100), spacing: 20, alignment: .leading),             // Status
            GridItem(.fixed(120), spacing: 20, alignment: .leading),             // Storage
            GridItem(.fixed(180), spacing: 20, alignment: .leading),             // IMEI
            GridItem(.fixed(120), spacing: 20, alignment: .leading),             // Unit Cost
            GridItem(.fixed(140), spacing: 0, alignment: .leading)               // Actions
        ]
        
        return LazyVGrid(columns: columns, spacing: 20) {
            Text("#").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Brand / Model").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Capacity").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Color").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Carrier").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Status").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Storage").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("IMEI").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            Text("Unit Cost").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            HStack {
                Text("Actions").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Rectangle()
                .fill(headerColor)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                )
        )
    }
    
    private var cartTableMacOSContent: some View {
        let columns: [GridItem] = [
            GridItem(.fixed(40), spacing: 20, alignment: .leading),              // #
            GridItem(.flexible(minimum: 180), spacing: 20, alignment: .leading), // Brand/Model
            GridItem(.fixed(100), spacing: 20, alignment: .leading),             // Capacity
            GridItem(.fixed(100), spacing: 20, alignment: .leading),             // Color
            GridItem(.fixed(120), spacing: 20, alignment: .leading),             // Carrier
            GridItem(.fixed(100), spacing: 20, alignment: .leading),             // Status
            GridItem(.fixed(120), spacing: 20, alignment: .leading),             // Storage
            GridItem(.fixed(180), spacing: 20, alignment: .leading),             // IMEI
            GridItem(.fixed(120), spacing: 20, alignment: .leading),             // Unit Cost
            GridItem(.fixed(140), spacing: 0, alignment: .leading)               // Actions
        ]
        
        return VStack(spacing: 0) {
            ForEach(cartItems.indices, id: \.self) { index in
                let item = cartItems[index]
                let isLastItem = index == cartItems.count - 1
                
                LazyVGrid(columns: columns, spacing: 20) {
                    Text("\(index + 1)").font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.brand).font(.system(size: 14, weight: .semibold))
                        Text(item.model).font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    Text("\(item.capacity) \(item.capacityUnit)").font(.system(size: 14))
                    Text(item.color).font(.system(size: 14))
                    Text(item.carrier).font(.system(size: 14))
                    Text(item.status).font(.system(size: 14))
                    Text(item.storageLocation).font(.system(size: 14))
                    Text(item.imeis.first ?? "-").font(.system(size: 14))
                    Text(String(format: "$ %.2f", item.unitCost)).font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 8) {
                        Button(action: {
                            itemToEdit = item
                        }) {
                            actionIconButton(systemName: "pencil", tint: Color.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            itemToDelete = item
                            showingDeleteConfirmation = true
                        }) {
                            actionIconButton(systemName: "trash", tint: Color.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.primary.opacity(0.02))
                
                if !isLastItem {
                    Divider()
                        .padding(.leading, 20)
                }
            }
        }
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 12,
                bottomTrailingRadius: 12,
                topTrailingRadius: 12
            )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Payment Details Section
    private var paymentDetailsSection: some View {
        // Early return if no items - prevents any computation
        if cartItems.isEmpty {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                // Header with app's theme colors
                HStack {
                    Text("Order Summary")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    Rectangle()
                        .fill(Color(red: 0.25, green: 0.33, blue: 0.54))
                        .overlay(
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                        )
                )
                
                // Payment details content with professional styling
                VStack(spacing: 0) {
                    // Tax input section with professional styling
                    taxInputSection
                    
                    // Adjustment section
                    adjustmentSection
                    
                    // Notes section
                    notesSection
                    
                    // Subtotal section
                    professionalPaymentRow(title: "Subtotal", amount: subtotal, isHighlighted: false, showDivider: true)
                    
                    // Tax amounts - always show
                    professionalPaymentRow(title: "GST", amount: gstAmount, isHighlighted: false, showDivider: true)
                    professionalPaymentRow(title: "PST", amount: pstAmount, isHighlighted: false, showDivider: true)
                    
                    // Adjustment row with minus sign and red color
                    adjustmentRow
                    
                    // Grand total with prominent styling
                    professionalPaymentRow(title: "Grand Total", amount: grandTotal, isHighlighted: true, showDivider: false)
                }
                .background(Color.primary.opacity(0.02))
            }
            .background(
                Rectangle()
                    .fill(.regularMaterial)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 12)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            .padding(.horizontal, isIPadVertical ? 20 : 0)
            .padding(.top, 20)
        )
    }
    
    private var paymentOptionsSection: some View {
        VStack(spacing: 0) {
            // Header with professional styling
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Payment Options")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Complete your transaction")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Grand total badge
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Total Due")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        Text(String(format: "$%.2f", grandTotal))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.25, green: 0.33, blue: 0.54),
                                Color(red: 0.20, green: 0.28, blue: 0.48)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.3), radius: 8, x: 0, y: 4)
            )
            
            // Payment fields with enhanced styling
            VStack(spacing: 0) {
                // Cash field
                enhancedPaymentField(title: "Cash", amount: $cashAmount, icon: "banknote", color: .green)
                
                // Bank field
                enhancedPaymentField(title: "Bank Transfer", amount: $bankAmount, icon: "building.columns", color: .blue)
                
                // Credit Card field
                enhancedPaymentField(title: "Credit Card", amount: $creditCardAmount, icon: "creditcard", color: .purple)
                
                // Credit field (calculated)
                enhancedCreditField
                
                // Confirm Payment button
                enhancedConfirmButton
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
            
            // Account balances with professional styling
            enhancedAccountBalancesSection
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal, isIPadVertical ? 20 : 0)
        .padding(.top, 20)
    }
    
    private var compactPaymentOptionsSection: some View {
        VStack(spacing: 0) {
            // Header with professional styling
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Payment Options")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Complete your transaction")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Grand total badge
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Total Due")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        Text(String(format: "$%.2f", grandTotal))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.25, green: 0.33, blue: 0.54),
                                Color(red: 0.20, green: 0.28, blue: 0.48)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.3), radius: 8, x: 0, y: 4)
            )
            
            // Payment fields in single column for better readability
            VStack(spacing: 0) {
                // Cash field
                compactPaymentField(title: "Cash", amount: $cashAmount, icon: "banknote", color: .green)
                
                // Bank field
                compactPaymentField(title: "Bank Transfer", amount: $bankAmount, icon: "building.columns", color: .blue)
                
                // Credit Card field
                compactPaymentField(title: "Credit Card", amount: $creditCardAmount, icon: "creditcard", color: .purple)
                
                // Credit field (calculated)
                compactCreditField
                
                // Confirm Payment button
                compactConfirmButton
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
        }
        .padding(.top, 20)
    }
    
    private func compactPaymentField(title: String, amount: Binding<String>, icon: String, color: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)
                
                // Title
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Amount input
                HStack(spacing: 2) {
                    Text("$")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    TextField("0.00", text: amount)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .onChange(of: amount.wrappedValue) { newValue in
                            let filtered = newValue.filter { "0123456789.".contains($0) }
                            if filtered != newValue {
                                amount.wrappedValue = filtered
                            }
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.clear)
            
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 20)
        }
    }
    
    private var compactCreditField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 24, height: 24)
                
                // Title
                Text("Credit (Remaining)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Amount
                Text(String(format: "$%.2f", creditAmount))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.red.opacity(0.05))
        }
    }
    
    private var compactConfirmButton: some View {
        Button(action: {
            Task {
                await confirmPayment()
            }
        }) {
            HStack(spacing: 12) {
                if isConfirmingPayment {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text(isConfirmingPayment ? "Processing..." : "Confirm Payment")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color(red: 0.2, green: 0.6, blue: 0.4), Color(red: 0.15, green: 0.5, blue: 0.35)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: Color(red: 0.2, green: 0.6, blue: 0.4).opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isConfirmingPayment)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
    
    private func paymentInputField(title: String, amount: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                TextField("0.00", text: amount)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .onChange(of: amount.wrappedValue) { newValue in
                        let filtered = newValue.filter { "0123456789.".contains($0) }
                        if filtered != newValue {
                            amount.wrappedValue = filtered
                        }
                    }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.clear)
            
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 0.5)
                .padding(.horizontal, 20)
        }
    }
    
    private var creditField: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Credit")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(String(format: "$%.2f", creditAmount))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.clear)
        }
    }
    
    private var confirmPaymentButton: some View {
        Button(action: {
            // TODO: Implement payment confirmation
        }) {
            Text("Confirm Payment")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var accountBalancesSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Account Balances")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Balance rows (placeholder - would need actual balance data)
            VStack(spacing: 0) {
                balanceRow(title: "Cash Account", amount: 2500.00, color: .green)
                balanceRow(title: "Bank Account", amount: 15000.00, color: .blue)
                balanceRow(title: "Credit Card", amount: -2500.00, color: .red)
            }
        }
        .padding(.bottom, 20)
    }
    
    private func balanceRow(title: String, amount: Double, color: Color) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(String(format: "$%.2f", amount))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.clear)
            
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 0.5)
                .padding(.horizontal, 20)
        }
    }
    
    private func enhancedPaymentField(title: String, amount: Binding<String>, icon: String, color: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)
                
                // Title
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Amount input
                HStack(spacing: 2) {
                    Text("$")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    TextField("0.00", text: amount)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 65)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .onChange(of: amount.wrappedValue) { newValue in
                            let filtered = newValue.filter { "0123456789.".contains($0) }
                            if filtered != newValue {
                                amount.wrappedValue = filtered
                            }
                            // Validate overpayment for main payment fields
                            if title == "Cash" || title == "Bank Transfer" || title == "Credit Card" {
                                validateMainPayment()
                            }
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.clear)
            
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 20)
        }
    }
    
    private var enhancedCreditField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 24, height: 24)
                
                // Title
                Text("Credit (Remaining)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Amount
                Text(String(format: "$%.2f", creditAmount))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.red.opacity(0.05))
        }
    }
    
    private var enhancedConfirmButton: some View {
        Button(action: {
            Task {
                await confirmPayment()
            }
        }) {
            HStack(spacing: 12) {
                if isConfirmingPayment {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text(isConfirmingPayment ? "Processing..." : "Confirm Payment")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color(red: 0.2, green: 0.6, blue: 0.4), Color(red: 0.15, green: 0.5, blue: 0.35)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: Color(red: 0.2, green: 0.6, blue: 0.4).opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isConfirmingPayment)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
    
    private var enhancedAccountBalancesSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account Balances")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Current account status")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Balance rows with real data
            VStack(spacing: 0) {
                enhancedBalanceRow(
                    title: "Cash Account",
                    amount: balanceViewModel.cashBalance,
                    icon: "banknote.fill",
                    color: .green
                )
                enhancedBalanceRow(
                    title: "Bank Account",
                    amount: balanceViewModel.bankBalance,
                    icon: "building.columns.fill",
                    color: .blue
                )
                enhancedBalanceRow(
                    title: "Credit Card",
                    amount: balanceViewModel.creditCardBalance,
                    icon: "creditcard.fill",
                    color: balanceViewModel.creditCardBalance < 0 ? .red : .green
                )
            }
        }
        .padding(.bottom, 20)
    }
    
    private func enhancedBalanceRow(title: String, amount: Double, icon: String, color: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 20, height: 20)
                
                // Title
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Amount
                Text(String(format: "$%.2f", amount))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.clear)
            
            Rectangle()
                .fill(Color.secondary.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 20)
        }
    }
    
    private var taxInputSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // GST input
                gstInputField
                
                // PST input
                pstInputField
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .padding(.bottom, 2)
            .padding(.top, 8)
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    hideKeyboard()
                }
            }
        }
        #endif
    }
    
    private var adjustmentSection: some View {
        VStack(spacing: 16) {
            // Adjustment input - full width
            adjustmentInputField
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .padding(.bottom, 12)
        }
    }
    
    private var notesSection: some View {
        VStack(spacing: 16) {
            // Notes input - full width
            notesInputField
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            // Middleman payment toggle and inline fields
            middlemanPaymentSection
        }
    }

    private var middlemanPaymentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        useMiddlemanPayment.toggle()
                        if useMiddlemanPayment {
                            showingMiddlemanDropdown = true
                        } else {
                            showingMiddlemanDropdown = false
                            selectedMiddleman = nil
                            middlemanSearchText = ""
                            middlemanInternalSearchText = ""
                            middlemanAmount = ""
                            middlemanCashAmount = ""
                            middlemanBankAmount = ""
                            middlemanCreditCardAmount = ""
                        }
                    }
                }) {
                    Image(systemName: useMiddlemanPayment ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(useMiddlemanPayment ? .green : .secondary)
                        .font(.system(size: 20, weight: .semibold))
                }
                .buttonStyle(PlainButtonStyle())
                
                Text("Middleman Payment")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if useMiddlemanPayment && !allEntities.isEmpty {
                VStack(spacing: 12) {
                    // Middleman dropdown (inline on all platforms)
                    middlemanDropdownButton
                        .padding(.horizontal, 20)

                    if showingMiddlemanDropdown {
                        middlemanDropdownInline
                            .padding(.horizontal, 20)
                            .transition(.opacity)
                    }

                    // Amount field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Amount")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        ZStack {
                            // Main TextField with padding for the buttons
                            TextField("0.0", text: $middlemanAmount)
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .font(.system(size: 16, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.trailing, 120) // Extra padding for unit buttons area
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.08))
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                                .onChange(of: middlemanAmount) { newValue in
                                    let filtered = newValue.filter { "0123456789.".contains($0) }
                                    if filtered != newValue {
                                        middlemanAmount = filtered
                                    }
                                }
                            
                            // Unit selection buttons positioned on the right
                            HStack(spacing: 8) {
                                Spacer()
                                
                                // Unit selection buttons
                                HStack(spacing: 4) {
                                    Button(action: {
                                        middlemanUnit = "give"
                                    }) {
                                        Text("Give")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(middlemanUnit == "give" ? .white : .secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(middlemanUnit == "give" ? Color.orange : Color.secondary.opacity(0.1))
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    Button(action: {
                                        middlemanUnit = "receive"
                                    }) {
                                        Text("Receive")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(middlemanUnit == "receive" ? .white : .secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(middlemanUnit == "receive" ? Color.green : Color.secondary.opacity(0.1))
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.trailing, 10)
                            }
                        }
                        
                        // Payment split - compact one-row version
                        if middlemanPaymentAmountValue > 0 {
                            middlemanPaymentSplitRow
                        }
                    }
                    .padding(.horizontal, 20)
                    .onChange(of: middlemanUnit) { _ in
                        // Clear payment split fields when unit changes
                        middlemanCashAmount = ""
                        middlemanBankAmount = ""
                        middlemanCreditCardAmount = ""
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 24)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.08))
        )
    }

    private var middlemanPaymentSplitRow: some View {
        HStack(spacing: 6) {
            // Cash
            compactPaymentItem(title: "Cash", amount: $middlemanCashAmount, icon: "banknote", color: .green)
            
            // Bank
            compactPaymentItem(title: "Bank", amount: $middlemanBankAmount, icon: "building.columns", color: .blue)
            
            // Credit Card
            compactPaymentItem(title: "Card", amount: $middlemanCreditCardAmount, icon: "creditcard", color: .purple)
                .disabled(middlemanUnit == "receive")
                .opacity(middlemanUnit == "receive" ? 0.5 : 1.0)
            
            // Remaining Credit (read-only)
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red)
                    Text("Credit")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Text(String(format: "$%.2f", middlemanCreditAmount))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red.opacity(0.08))
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.top, 4)
    }
    
    private func compactPaymentItem(title: String, amount: Binding<String>, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            TextField("0", text: amount)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .onChange(of: amount.wrappedValue) { newValue in
                    let filtered = newValue.filter { "0123456789.".contains($0) }
                    if filtered != newValue {
                        amount.wrappedValue = filtered
                    }
                    // Validate overpayment for middleman payment fields
                    if title == "Cash" || title == "Bank" || title == "Card" {
                        validateMiddlemanPayment()
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var middlemanDropdownButton: some View {
        ZStack {
            TextField("Select middleman/customer/supplier", text: $middlemanSearchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.trailing, 50)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: middlemanSearchText) { newValue in
                    middlemanInternalSearchText = newValue
                    if !newValue.isEmpty && !showingMiddlemanDropdown && (selectedMiddleman?.name ?? "") != newValue {
                        showingMiddlemanDropdown = true
                    }
                }
                .onChange(of: showingMiddlemanDropdown) { newValue in
                    if newValue {
                        middlemanInternalSearchText = ""
                    }
                }

            HStack {
                Spacer()
                Button(action: {
                    withAnimation { showingMiddlemanDropdown.toggle() }
                }) {
                    Image(systemName: showingMiddlemanDropdown ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 6)
            }
        }
    }

    private var middlemanDropdownInline: some View {
        let source = allEntities
        let query = middlemanInternalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [EntityWithType]
        if query.isEmpty {
            filtered = source
        } else {
            filtered = source.filter { entity in
                entity.name.localizedCaseInsensitiveContains(query) ||
                entity.entityType.rawValue.localizedCaseInsensitiveContains(query)
            }
        }

        return VStack(spacing: 0) {
            // List of entities, middlemen prioritized already in allEntities sorting
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filtered.isEmpty {
                        // Show retry button if there was an error and no entities
                        if entityFetchError && allEntities.isEmpty {
                            VStack(spacing: 12) {
                                Text("Failed to load entities")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Button(action: {
                                    fetchAllEntities()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Retry")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                        } else {
                            Text("No entities found")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                        }
                    } else {
                        ForEach(filtered) { entity in
                            Button(action: {
                                withAnimation {
                                    selectedMiddleman = entity
                                    middlemanSearchText = entity.name
                                    showingMiddlemanDropdown = false
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: entity.entityType.icon)
                                        .foregroundColor(entity.entityType.color)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entity.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        let balanceText = entity.balance.map { String(format: "Balance: $%.2f", $0) } ?? "Balance: —"
                                        Text(balanceText)
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(.primary.opacity(0.7))
                                            .lineLimit(1)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Spacer()
                                    if selectedMiddleman?.id == entity.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 56)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            Divider()
                                .background(Color.secondary.opacity(0.15))
                                .padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: {
            let itemHeight: CGFloat = 56
            let maxVisible = 4
            let count = filtered.count
            if count == 0 {
                return 120 // Fixed height for empty state or error message
            } else if count <= maxVisible {
                return CGFloat(count) * itemHeight
            }
            return CGFloat(maxVisible) * itemHeight
        }())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
    
    private var adjustmentInputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adjustment")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            ZStack {
                // Main TextField with padding for the buttons
                TextField("0.0", text: $adjustmentAmount)
                    .textFieldStyle(PlainTextFieldStyle())
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .onTapGesture {
                        scrollToField?("adjustmentField")
                    }
                    #endif
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.trailing, 120) // Extra padding for unit buttons area
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.08))
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .onChange(of: adjustmentAmount) { newValue in
                        // Ensure only numbers and decimal point
                        let filtered = newValue.filter { "0123456789.".contains($0) }
                        if filtered != newValue {
                            adjustmentAmount = filtered
                            return
                        }
                        
                        // Check if adjustment exceeds grand total
                        let currentGrandTotal = subtotal + gstAmount + pstAmount
                        if let amount = Double(filtered), amount > currentGrandTotal {
                            adjustmentAmount = String(format: "%.2f", currentGrandTotal)
                        }
                    }
                    .id("adjustmentField")
                
                // Unit selection buttons positioned on the right
                HStack(spacing: 8) {
                    Spacer()
                    
                    // Unit selection buttons
                    HStack(spacing: 4) {
                        Button(action: {
                            adjustmentUnit = "discount"
                        }) {
                            Text("Discount")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(adjustmentUnit == "discount" ? .white : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(adjustmentUnit == "discount" ? Color.red : Color.secondary.opacity(0.1))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            adjustmentUnit = "receive"
                        }) {
                            Text("Receive")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(adjustmentUnit == "receive" ? .white : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(adjustmentUnit == "receive" ? Color.green : Color.secondary.opacity(0.1))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.trailing, 10)
                }
            }
        }
    }
    
    private var notesInputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            TextField("Add transaction notes...", text: $notes)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .id("notesField")
        }
    }
    
    private var adjustmentRow: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Adjustment")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if adjustmentUnit == "discount" {
                    Text(String(format: "-$%.2f", adjustmentAmountValue))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                } else {
                    Text(String(format: "+$%.2f", adjustmentAmountValue))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.clear)
            
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 0.5)
                .padding(.horizontal, 20)
        }
    }
    
    private var gstInputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GST (%)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            TextField("0.0", text: $gstPercentage)
                .textFieldStyle(PlainTextFieldStyle())
                #if os(iOS)
                .keyboardType(.decimalPad)
                .onTapGesture {
                    scrollToField?("gstField")
                }
                #endif
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: gstPercentage) { newValue in
                    // Ensure only numbers and decimal point
                    let filtered = newValue.filter { "0123456789.".contains($0) }
                    if filtered != newValue {
                        gstPercentage = filtered
                    }
                }
                .id("gstField")
        }
    }
    
    private var pstInputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PST (%)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            TextField("0.0", text: $pstPercentage)
                .textFieldStyle(PlainTextFieldStyle())
                #if os(iOS)
                .keyboardType(.decimalPad)
                .onTapGesture {
                    scrollToField?("pstField")
                }
                #endif
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: pstPercentage) { newValue in
                    // Ensure only numbers and decimal point
                    let filtered = newValue.filter { "0123456789.".contains($0) }
                    if filtered != newValue {
                        pstPercentage = filtered
                    }
                }
                .id("pstField")
        }
    }
    
    private func professionalPaymentRow(title: String, amount: Double, isHighlighted: Bool, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: isHighlighted ? 17 : 15, weight: isHighlighted ? .bold : .semibold))
                    .foregroundColor(isHighlighted ? .primary : .secondary)
                
                Spacer()
                
                Text(String(format: "$%.2f", amount))
                    .font(.system(size: isHighlighted ? 18 : 16, weight: isHighlighted ? .bold : .semibold))
                    .foregroundColor(isHighlighted ? .primary : .primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, isHighlighted ? 16 : 12)
            .background(
                Rectangle()
                    .fill(isHighlighted ? Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.06) : Color.clear)
            )
            
            if showDivider {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)
            }
        }
    }
    
    private func actionIconButton(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.12))
            )
    }
    
    private func badge(text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
            )
    }
    
    private func uniformBadge(text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
            )
    }
    
    private func locationBadge(text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "location")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 60)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
        )
    }
    
    private func statusBadge(text: String) -> some View {
        let isActive = text.lowercased() == "active"
        let tintColor = isActive ? Color.green : Color.red
        
        return Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(tintColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tintColor.opacity(0.12))
            )
    }
    
    var orderNumberField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Order number")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                
                if isOrderNumberCustom {
                    Button("Auto") {
                        orderNumber = originalOrderNumber
                        isOrderNumberCustom = false
                        print("🔄 Switched back to auto-generated order number: \(originalOrderNumber)")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.12))
                    )
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                }
            }
            
            TextField("Enter order number", text: $orderNumber)
                .font(.body)
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .focused($isOrderNumberFieldFocused)
                .onChange(of: orderNumber) { newValue in
                    // Mark as custom only if value doesn't match the auto-generated value
                    if !originalOrderNumber.isEmpty && newValue != originalOrderNumber && newValue != "Loading..." {
                        isOrderNumberCustom = true
                        print("✏️ Order number marked as custom: \(newValue)")
                    } else if !originalOrderNumber.isEmpty && newValue == originalOrderNumber {
                        isOrderNumberCustom = false
                        print("🔄 Order number back to auto-generated: \(newValue)")
                    }
                }
            
            Text(isOrderNumberCustom ? "Custom order number (will not affect auto-increment)" : "Auto-generated order number")
                .font(.system(size: 12))
                .foregroundColor(isOrderNumberCustom ? .orange : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    var dateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Date")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
            
            Button(action: {
                showingDatePicker = true
            }) {
                HStack {
                    Text(formattedDate)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .modifier(DatePickerModifier(
                isPresented: $showingDatePicker,
                selectedDate: $selectedDate,
                isCompact: isCompact
            ))
            
            Text("The date when this purchase was made")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    var supplierDropdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Supplier")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
            }
            
            SupplierDropdownButton(
                selectedSupplier: selectedSupplier,
                placeholder: "Choose an option",
                isOpen: $showingSupplierDropdown,
                buttonFrame: $supplierButtonFrame,
                searchText: $supplierSearchText,
                isFocused: $isSupplierFieldFocused
            )
            .frame(height: 44)
            
            Text("Select a supplier for this purchase")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    var addProductButton: some View {
        Button(action: {
            showingAddProductDialog = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                
                Text("Add Product")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
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
            .shadow(color: Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func setupOrderNumberListener() {
        let db = Firestore.firestore()
        
        print("🔢 Setting up OrderNumbers collection listener...")
        
        // Remove existing listener if any
        orderNumberListener?.remove()
        
        // Set up listener for OrderNumbers collection
        orderNumberListener = db.collection("OrderNumbers")
            .addSnapshotListener { [self] snapshot, error in
                if let error = error {
                    print("❌ Error listening to OrderNumbers collection: \(error)")
                    DispatchQueue.main.async {
                        self.orderNumber = "ORD-1"
                    }
                    return
                }
                
                guard let snapshot = snapshot else {
                    print("⚠️ No snapshot received from OrderNumbers collection")
                    DispatchQueue.main.async {
                        self.orderNumber = "ORD-1"
                    }
                    return
                }
                
                print("📊 Received \(snapshot.documents.count) documents from OrderNumbers collection")
                
                var highestOrderNumber = 0
                
                // Find the highest order number across all documents (excluding custom orders)
                for document in snapshot.documents {
                    let data = document.data()
                    
                    // Skip custom order numbers (marked with isCustom flag)
                    let isCustom = data["isCustom"] as? Bool ?? false
                    if isCustom {
                        print("⏭️ Skipping custom order number: \(document.documentID)")
                        continue
                    }
                    
                    // Check for different possible field names
                    let orderNo = data["orderNumber"] as? Int ?? 
                                 data["order_number"] as? Int ?? 
                                 data["number"] as? Int ?? 
                                 data["value"] as? Int ?? 0
                    
                    if orderNo > highestOrderNumber {
                        highestOrderNumber = orderNo
                        print("🔝 Found higher order number: \(orderNo)")
                    }
                }
                
                // Generate next order number (increment by 1)
                let nextOrderNumber = highestOrderNumber + 1
                
                print("🎯 Order number calculation:")
                print("   Highest found: \(highestOrderNumber)")
                print("   Next order number: \(nextOrderNumber)")
                
                DispatchQueue.main.async {
                    // Only update order number if it's not custom
                    if !self.isOrderNumberCustom {
                        let newOrderNumber = "ORD-\(nextOrderNumber)"
                        self.orderNumber = newOrderNumber
                        self.originalOrderNumber = newOrderNumber
                        print("✅ Order number updated to: \(self.orderNumber)")
                    } else {
                        print("🔒 Keeping custom order number: \(self.orderNumber)")
                    }
                }
            }
    }
    
    private func stopOrderNumberListener() {
        print("🛑 Stopping OrderNumbers collection listener...")
        orderNumberListener?.remove()
        orderNumberListener = nil
    }
    
    private func fetchAllEntities() {
        let db = Firestore.firestore()
        var entities: [EntityWithType] = []
        var hasError = false
        let group = DispatchGroup()
        
        // Fetch from all three collections
        let collections = [
            ("Customers", EntityType.customer),
            ("Suppliers", EntityType.supplier),
            ("Middlemen", EntityType.middleman)
        ]
        
        for (collectionName, entityType) in collections {
            group.enter()
            
            db.collection(collectionName).getDocuments { snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    print("Error fetching \(collectionName): \(error)")
                    hasError = true
                    return
                }
                
                if let documents = snapshot?.documents {
                    for document in documents {
                        let data = document.data()
                        print("DEBUG: Document \(document.documentID) in \(collectionName): \(data)")
                        
                        let rawBalance = (data["balance"] ?? data["Balance"] ?? data["accountBalance"] ?? data["AccountBalance"])
                        print("DEBUG: Raw balance for \(data["name"] ?? "unknown"): \(rawBalance ?? "nil")")
                        
                        let parsedBalance: Double? = {
                            if let d = rawBalance as? Double { return d }
                            if let i = rawBalance as? Int { return Double(i) }
                            if let n = rawBalance as? NSNumber { return n.doubleValue }
                            if let s = rawBalance as? String { return Double(s) }
                            return nil
                        }()
                        
                        print("DEBUG: Parsed balance for \(data["name"] ?? "unknown"): \(parsedBalance ?? 0)")
                        
                        let entity = EntityWithType(
                            id: document.documentID,
                            name: data["name"] as? String ?? "",
                            entityType: entityType,
                            balance: parsedBalance
                        )
                        entities.append(entity)
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            // Keep Middlemen at the top, then Customers and Suppliers; each group sorted by name
            self.allEntities = entities.sorted { a, b in
                func rank(_ type: EntityType) -> Int {
                    switch type {
                    case .middleman: return 0
                    case .customer: return 1
                    case .supplier: return 2
                    }
                }
                if rank(a.entityType) != rank(b.entityType) {
                    return rank(a.entityType) < rank(b.entityType)
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            self.entityFetchError = hasError
            self.isLoadingEntities = false
        }
    }
    
    private func deleteItem() {
        guard let item = itemToDelete else { return }
        
        // Find and remove the item
        if let index = cartItems.firstIndex(where: { $0.id == item.id }) {
            deletedItemIndex = index
            cartItems.remove(at: index)
            
            // Show success confirmation in the same dialog
            showingDeleteSuccess = true
            
            // Close dialog after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showingDeleteSuccess = false
                showingDeleteConfirmation = false
                deletedItemIndex = nil
                itemToDelete = nil
            }
        } else {
            itemToDelete = nil
        }
    }
    
    private func updateCartItem(with updatedItem: PhoneItem) {
        // Find and remove the original item(s) by matching the original item's ID
        cartItems.removeAll { $0.id == updatedItem.id }
        
        // Add the expanded items (one per IMEI) to the cart
        cartItems.append(contentsOf: expandedItems(from: [updatedItem]))
        
        itemToEdit = nil
    }
    
    #if os(iOS)
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif
    
    // Overpayment validation functions
    private func validateMainPayment() {
        if isMainPaymentOverpaid {
            let totalPayment = cashAmountValue + bankAmountValue + creditCardAmountValue
            overpaymentAlertMessage = "Total payment amount ($\(String(format: "%.2f", totalPayment))) exceeds the grand total ($\(String(format: "%.2f", grandTotal))). Please reduce the payment amounts."
            showOverpaymentAlert = true
        }
    }
    
    private func validateMiddlemanPayment() {
        if isMiddlemanPaymentOverpaid {
            let totalMiddlemanPayment = middlemanCashAmountValue + middlemanBankAmountValue + middlemanCreditCardAmountValue
            overpaymentAlertMessage = "Total middleman payment amount ($\(String(format: "%.2f", totalMiddlemanPayment))) exceeds the middleman amount ($\(String(format: "%.2f", middlemanPaymentAmountValue))). Please reduce the payment amounts."
            showOverpaymentAlert = true
        }
    }
}

struct DeleteConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var showingSuccess: Bool
    let itemToDelete: PhoneItem?
    let onDelete: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var isIPad: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    func body(content: Content) -> some View {
        content
        .alert("Delete Product", isPresented: $isPresented) {
            if !showingSuccess {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
            }
        } message: {
            if showingSuccess {
                Text("Product Deleted Successfully!")
            } else if let item = itemToDelete {
                Text("Are you sure you want to delete \(item.brand) \(item.model) from the cart?")
            }
        }
    }
}

struct EntityWithType: Identifiable {
    let id: String
    let name: String
    let entityType: EntityType
    let balance: Double?
}

struct DatePickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selectedDate: Date
    let isCompact: Bool
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: selectedDate)
    }
    
    func body(content: Content) -> some View {
        content
        .modifier(DatePickerPresentationModifier(
            isPresented: $isPresented,
            selectedDate: $selectedDate,
            isCompact: isCompact
        ))
    }
    
    @ViewBuilder
    var datePickerContent: some View {
        if isCompact {
            // iPhone version - normal small calendar
            #if os(iOS)
            NavigationView {
                VStack(spacing: 20) {
                    DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                    
                    Spacer()
                }
                .navigationTitle("Select Purchase Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            isPresented = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            #else
            // Fallback for macOS (though isCompact should never be true on macOS)
            VStack(spacing: 20) {
                HStack {
                    Text("Select Purchase Date")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Done") {
                        isPresented = false
                    }
                    .font(.system(size: 16, weight: .semibold))
                }
                .padding()
                
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                
                Spacer()
            }
            #endif
        } else {
            // Enhanced iPad/macOS version with large, clean, robust design
            VStack(spacing: 0) {
                // Enhanced header with clean styling
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Select Purchase Date")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("Choose the date for this purchase order")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            isPresented = false
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Confirm Selection")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
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
                            .shadow(color: Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 0.1), value: isPresented)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 30)
                    
                    // Subtle divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .padding(.horizontal, 40)
                }
                .background(.regularMaterial)
                
                // Enhanced calendar container
                VStack(spacing: 0) {
                    // Current selection indicator
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Selected Date")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            
                            Text(formattedDate)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        // Quick date options
                        HStack(spacing: 12) {
                            DateQuickButton(title: "Today", date: Date(), selectedDate: $selectedDate)
                            DateQuickButton(title: "Yesterday", date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(), selectedDate: $selectedDate)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    
                    // Large, clean calendar
                    VStack {
                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .scaleEffect(1.4)
                            .padding(.horizontal, 60)
                            .padding(.vertical, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
                            )
                            .padding(.horizontal, 40)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                 .background(
                     LinearGradient(
                         gradient: Gradient(colors: [
                             Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.3),
                             Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.1)
                         ]),
                         startPoint: .top,
                         endPoint: .bottom
                     )
                 )
            }
            .frame(width: 600, height: 500)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        }
    }
}

struct DatePickerPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selectedDate: Date
    let isCompact: Bool
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: selectedDate)
    }
    
    func body(content: Content) -> some View {
        content
        #if os(iOS)
        .modifier(iOSPresentationModifier(
            isPresented: $isPresented,
            selectedDate: $selectedDate,
            isCompact: isCompact,
            formattedDate: formattedDate
        ))
        #else
        .popover(isPresented: $isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .scaleEffect(1.5)
                .padding(30)
                .frame(width: 400, height: 350)
        }
        #endif
    }
}

struct iOSPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selectedDate: Date
    let isCompact: Bool
    let formattedDate: String
    
    func body(content: Content) -> some View {
        if isCompact {
            // iPhone - simple modal (iOS only)
            #if os(iOS)
            content
            .fullScreenCover(isPresented: $isPresented) {
                NavigationView {
                    VStack(spacing: 20) {
                        DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                        
                        Spacer()
                    }
                    .navigationTitle("Select Purchase Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                isPresented = false
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                isPresented = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
            #else
            // Fallback for macOS (though isCompact should never be true on macOS)
            content
            .popover(isPresented: $isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(20)
                    .frame(width: 300, height: 250)
            }
            #endif
        } else {
            // iPad - small popup calendar
            content
            .popover(isPresented: $isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .scaleEffect(1.0)
                    .padding(30)
                    .frame(width: 450, height: 400)
            }
        }
    }
}

struct DateQuickButton: View {
    let title: String
    let date: Date
    @Binding var selectedDate: Date
    
    private var isSelected: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: date)
    }
    
    var body: some View {
        Button(action: {
            selectedDate = date
        }) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SupplierDropdownButton: View {
    let selectedSupplier: EntityWithType?
    let placeholder: String
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    @Binding var searchText: String
    @FocusState.Binding var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if isOpen {
                    TextField("Search...", text: $searchText)
                        .font(.body)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.primary)
                        .focused($isFocused)
                        .onAppear {
                            DispatchQueue.main.async {
                                isFocused = true
                            }
                        }
                } else {
                    if let selectedSupplier = selectedSupplier {
                        HStack(spacing: 8) {
                            Text("[\(selectedSupplier.entityType.rawValue)]")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(selectedSupplier.entityType.color)
                                )
                            
                            Text(selectedSupplier.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    } else {
                        Text(placeholder)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
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
            // Remove focus from main field when opening dropdown
            if isOpen {
                isFocused = false
            }
        }
    }
}

struct SupplierDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedSupplier: EntityWithType?
    let entities: [EntityWithType]
    let buttonFrame: CGRect
    let searchText: String
    let entityFetchError: Bool
    let onRetry: () -> Void
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var localSearchText = ""
    @FocusState private var isLocalSearchFocused: Bool
    
    private var overlayWidth: CGFloat {
        #if os(macOS)
        return max(400, buttonFrame.width)
        #else
        if horizontalSizeClass == .compact {
            return UIScreen.main.bounds.width - 32
        } else {
            return max(400, buttonFrame.width)
        }
        #endif
    }
    
    // Filtered entities - use local search for iPhone, main field search for iPad/macOS
    private var filteredEntities: [EntityWithType] {
        let effectiveSearchText = horizontalSizeClass == .compact ? localSearchText : searchText
        
        let filtered: [EntityWithType]
        if effectiveSearchText.isEmpty {
            filtered = entities
        } else {
            filtered = entities.filter { entity in
                entity.name.localizedCaseInsensitiveContains(effectiveSearchText) ||
                entity.entityType.rawValue.localizedCaseInsensitiveContains(effectiveSearchText)
            }
        }
        
        // Sort to put suppliers on top
        return filtered.sorted { entity1, entity2 in
            if entity1.entityType == .supplier && entity2.entityType != .supplier {
                return true
            } else if entity1.entityType != .supplier && entity2.entityType == .supplier {
                return false
            } else {
                return entity1.name < entity2.name
            }
        }
    }
    
    var body: some View {
        centeredOverlay
    }
    
    // Platform-specific overlay implementation
    @ViewBuilder
    private var centeredOverlay: some View {
        if horizontalSizeClass == .compact {
            // iPhone: Centered modal overlay
            iphoneModalOverlay
        } else {
            // iPad/macOS: Positioned dropdown below field
            positionedDropdown
        }
    }
    
    private var iphoneModalOverlay: some View {
        ZStack {
            // Full screen background
            Color.black.opacity(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    isOpen = false
                }
                .onAppear {
                    localSearchText = ""
                    // Focus the internal search field for iPhone
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if horizontalSizeClass == .compact {
                            isLocalSearchFocused = true
                        }
                    }
                }
            
            // Centered dialog
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Select Supplier")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        isOpen = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.regularMaterial)
                
                Divider()
                
                // Search field (iPhone only)
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search entities...", text: $localSearchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.body)
                        .focused($isLocalSearchFocused)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Entity list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredEntities.isEmpty {
                            if entityFetchError && entities.isEmpty {
                                VStack(spacing: 12) {
                                    Text("Failed to load entities")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                    
                                    Button(action: {
                                        onRetry()
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Retry")
                                        }
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.vertical, 40)
                            } else {
                                Text("No entities found")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 40)
                            }
                        } else {
                            ForEach(filteredEntities, id: \.id) { entity in
                                entityRow(for: entity)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 400)
                .background(.regularMaterial)
            }
            .background(.regularMaterial)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
    }
    
    private var positionedDropdown: some View {
        ZStack {
            // Transparent background to capture taps
            Color.black.opacity(0.001)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation {
                        isOpen = false
                    }
                }
            
            // Clean dropdown directly attached to field
            VStack(alignment: .leading, spacing: 0) {
                // Entity list only - no search bar
                ScrollView {
                    VStack(spacing: 0) {
                        if filteredEntities.isEmpty {
                            if entityFetchError && entities.isEmpty {
                                VStack(spacing: 12) {
                                    Text("Failed to load entities")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                    
                                    Button(action: {
                                        onRetry()
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Retry")
                                        }
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                Text("No entities found")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                            }
                        } else {
                            ForEach(filteredEntities) { entity in
                                cleanEntityRow(for: entity)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 250)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .frame(width: buttonFrame.width)
            .position(
                x: buttonFrame.midX,
                y: buttonFrame.maxY + 5 + 125
            )
        }
    }
    
    private func cleanEntityRow(for entity: EntityWithType) -> some View {
        Button(action: {
            withAnimation {
                selectedSupplier = entity
                isOpen = false
            }
        }) {
            HStack(spacing: 16) {
                // Entity type badge - using app's standard badge style
                Text(entity.entityType.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(entity.entityType.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(entity.entityType.color.opacity(0.1))
                            .stroke(entity.entityType.color.opacity(0.3), lineWidth: 1)
                    )
                
                // Entity name
                Text(entity.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Selection indicator
                if selectedSupplier?.id == entity.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(entity.entityType.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                selectedSupplier?.id == entity.id ?
                entity.entityType.color.opacity(0.1) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func entityRow(for entity: EntityWithType) -> some View {
        Button(action: {
            withAnimation {
                selectedSupplier = entity
                isOpen = false
            }
        }) {
            HStack(spacing: 16) {
                // Entity type badge - using app's standard badge style
                Text(entity.entityType.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(entity.entityType.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(entity.entityType.color.opacity(0.1))
                            .stroke(entity.entityType.color.opacity(0.3), lineWidth: 1)
                    )
                
                // Entity name
                Text(entity.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Selection indicator
                if selectedSupplier?.id == entity.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(entity.entityType.color)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                selectedSupplier?.id == entity.id ?
                entity.entityType.color.opacity(0.1) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Payment Confirmation Extension
extension PurchaseView {
    private func confirmPayment() async {
        guard !cartItems.isEmpty else { return }
        
        // Validate required fields
        var missingFields: [String] = []
        
        if selectedSupplier == nil {
            missingFields.append("• Select a supplier from the dropdown")
        }
        
        if gstPercentage.isEmpty {
            missingFields.append("• Enter the GST percentage")
        }
        
        if pstPercentage.isEmpty {
            missingFields.append("• Enter the PST percentage")
        }
        
        if useMiddlemanPayment {
            if selectedMiddleman == nil {
                missingFields.append("• Select a middleman from the dropdown")
            }
            
            if middlemanAmount.isEmpty {
                missingFields.append("• Enter the middleman payment amount")
            }
        }
        
        if !missingFields.isEmpty {
            await MainActor.run {
                validationAlertMessage = "Please complete the following required fields:\n\n" + missingFields.joined(separator: "\n")
                showValidationAlert = true
            }
            return
        }
        
        print("🛒 Starting payment confirmation process...")
        print("📦 Cart items count: \(cartItems.count)")
        
        isConfirmingPayment = true
        
        do {
            let db = Firestore.firestore()
            print("🔥 Connected to Firestore database")
            
            // Use batch write for atomic operations
            let batch = db.batch()
            print("📝 Created Firestore batch for atomic operations")
            
            for phoneItem in cartItems {
                print("📱 Processing phone item: \(phoneItem.brand) \(phoneItem.model)")
                
                // Find or create brand document (auto-generated ID)
                print("🔍 Searching for existing brand: \(phoneItem.brand)")
                let brandQuery = db.collection("PhoneBrands").whereField("brand", isEqualTo: phoneItem.brand).limit(to: 1)
                let brandSnapshot = try await brandQuery.getDocuments()
                
                let brandDocRef: DocumentReference
                if let existingBrand = brandSnapshot.documents.first {
                    brandDocRef = existingBrand.reference
                    print("✅ Found existing brand document: \(existingBrand.documentID)")
                } else {
                    // Create new brand document with auto-generated ID
                    brandDocRef = db.collection("PhoneBrands").document()
                    print("🆕 Creating new brand document: \(brandDocRef.documentID)")
                    batch.setData([
                        "brand": phoneItem.brand,
                        "createdAt": selectedDate
                    ], forDocument: brandDocRef)
                }
                
                // Find or create model document (auto-generated ID)
                print("🔍 Searching for existing model: \(phoneItem.model)")
                let modelQuery = brandDocRef.collection("Models").whereField("model", isEqualTo: phoneItem.model).limit(to: 1)
                let modelSnapshot = try await modelQuery.getDocuments()
                
                let modelDocRef: DocumentReference
                if let existingModel = modelSnapshot.documents.first {
                    modelDocRef = existingModel.reference
                    print("✅ Found existing model document: \(existingModel.documentID)")
                } else {
                    // Create new model document with auto-generated ID
                    modelDocRef = brandDocRef.collection("Models").document()
                    print("🆕 Creating new model document: \(modelDocRef.documentID)")
                    batch.setData([
                        "model": phoneItem.model,
                        "brand": phoneItem.brand,
                        "createdAt": selectedDate
                    ], forDocument: modelDocRef)
                }
                
                // Create separate phone documents for each IMEI
                print("📱 Creating phone documents for \(phoneItem.imeis.count) IMEIs")
                for imei in phoneItem.imeis {
                    // Create phone document reference with auto-generated ID
                    let phoneDocRef = modelDocRef.collection("Phones").document()
                    print("🆕 Creating phone document for IMEI: \(imei)")
                    
                    // Prepare phone data for individual phone
                    var phoneData: [String: Any] = [
                        "brand": brandDocRef, // Brand as reference
                        "model": modelDocRef, // Model as reference
                        "capacity": phoneItem.capacity,
                        "capacityUnit": phoneItem.capacityUnit,
                        "imei": imei, // Single IMEI per document
                        "unitCost": phoneItem.unitCost,
                        "status": phoneItem.status,
                        "storageLocation": phoneItem.storageLocation,
                        "createdAt": selectedDate
                    ]
                    
                    // Add carrier as reference if it exists
                    if !phoneItem.carrier.isEmpty {
                        print("🔍 Searching for existing carrier: \(phoneItem.carrier)")
                        // Check if carrier exists in Carriers collection
                        let carrierQuery = db.collection("Carriers").whereField("name", isEqualTo: phoneItem.carrier).limit(to: 1)
                        let carrierSnapshot = try await carrierQuery.getDocuments()
                        
                        if let carrierDoc = carrierSnapshot.documents.first {
                            phoneData["carrier"] = carrierDoc.reference
                            print("✅ Found existing carrier document: \(carrierDoc.documentID)")
                        } else {
                            // Create new carrier document if it doesn't exist
                            let newCarrierRef = db.collection("Carriers").document()
                            print("🆕 Creating new carrier document: \(newCarrierRef.documentID)")
                            batch.setData([
                                "name": phoneItem.carrier,
                                "createdAt": selectedDate
                            ], forDocument: newCarrierRef)
                            phoneData["carrier"] = newCarrierRef
                        }
                    }
                    
                    // Add color as reference if it exists
                    if !phoneItem.color.isEmpty {
                        print("🔍 Searching for existing color: \(phoneItem.color)")
                        let colorQuery = db.collection("Colors").whereField("name", isEqualTo: phoneItem.color).limit(to: 1)
                        let colorSnapshot = try await colorQuery.getDocuments()
                        
                        if let colorDoc = colorSnapshot.documents.first {
                            phoneData["color"] = colorDoc.reference
                            print("✅ Found existing color document: \(colorDoc.documentID)")
                        } else {
                            // Create new color document if it doesn't exist
                            let newColorRef = db.collection("Colors").document()
                            print("🆕 Creating new color document: \(newColorRef.documentID)")
                            batch.setData([
                                "name": phoneItem.color,
                                "createdAt": selectedDate
                            ], forDocument: newColorRef)
                            phoneData["color"] = newColorRef
                        }
                    }
                    
                    // Add storage location as reference if it exists
                    if !phoneItem.storageLocation.isEmpty {
                        print("🔍 Searching for existing storage location: \(phoneItem.storageLocation)")
                        let locationQuery = db.collection("StorageLocations").whereField("name", isEqualTo: phoneItem.storageLocation).limit(to: 1)
                        let locationSnapshot = try await locationQuery.getDocuments()
                        
                        if let locationDoc = locationSnapshot.documents.first {
                            phoneData["storageLocation"] = locationDoc.reference
                            print("✅ Found existing storage location document: \(locationDoc.documentID)")
                        } else {
                            // Create new storage location document if it doesn't exist
                            let newLocationRef = db.collection("StorageLocations").document()
                            print("🆕 Creating new storage location document: \(newLocationRef.documentID)")
                            batch.setData([
                                "name": phoneItem.storageLocation,
                                "createdAt": selectedDate
                            ], forDocument: newLocationRef)
                            phoneData["storageLocation"] = newLocationRef
                        }
                    }
                    
                    // Set individual phone document
                    print("💾 Adding phone document to batch: \(phoneDocRef.documentID)")
                    batch.setData(phoneData, forDocument: phoneDocRef)
                    
                    // Also add IMEI to separate IMEI collection
                    let imeiDocRef = db.collection("IMEI").document()
                    print("🔢 Adding IMEI document to batch: \(imeiDocRef.documentID)")
                    batch.setData([
                        "imei": imei,
                        "phoneReference": phoneDocRef,
                        "createdAt": selectedDate
                    ], forDocument: imeiDocRef)
                }
            }
            
            // Create Purchase document for transaction history and billing
            let purchaseDocRef = db.collection("Purchases").document()
            print("📄 Creating purchase document: \(purchaseDocRef.documentID)")
            
            // Calculate payment totals
            let totalCashPaid = cashAmountValue
            let totalBankPaid = bankAmountValue
            let totalCreditCardPaid = creditCardAmountValue
            let totalPaid = totalCashPaid + totalBankPaid + totalCreditCardPaid
            let remainingCredit = totalPaid - grandTotal
            
            print("💰 Payment Summary:")
            print("   Cash: $\(totalCashPaid)")
            print("   Bank: $\(totalBankPaid)")
            print("   Credit Card: $\(totalCreditCardPaid)")
            print("   Total Paid: $\(totalPaid)")
            print("   Grand Total: $\(grandTotal)")
            print("   Remaining Credit: $\(remainingCredit)")
            
            // Calculate final payment amounts with middleman adjustments
            var finalCash = cashAmountValue
            var finalBank = bankAmountValue
            var finalCard = creditCardAmountValue
            
            print("💵 Initial Final Amounts:")
            print("   Final Cash: $\(finalCash)")
            print("   Final Bank: $\(finalBank)")
            print("   Final Card: $\(finalCard)")
            
            // Apply middleman payment adjustments if enabled
            if useMiddlemanPayment && (middlemanCashAmountValue > 0 || middlemanBankAmountValue > 0 || middlemanCreditCardAmountValue > 0) {
                print("🤝 Applying middleman payment adjustments:")
                print("   Middleman Unit: \(middlemanUnit)")
                print("   Middleman Cash: $\(middlemanCashAmountValue)")
                print("   Middleman Bank: $\(middlemanBankAmountValue)")
                print("   Middleman Card: $\(middlemanCreditCardAmountValue)")
                
                if middlemanUnit == "give" {
                    // Add middleman payments to final amounts
                    finalCash += middlemanCashAmountValue
                    finalBank += middlemanBankAmountValue
                    finalCard += middlemanCreditCardAmountValue
                    print("   Mode: Give - Adding middleman amounts to final totals")
                } else {
                    // Subtract middleman payments from final amounts (receive mode)
                    finalCash -= middlemanCashAmountValue
                    finalBank -= middlemanBankAmountValue
                    finalCard -= middlemanCreditCardAmountValue
                    print("   Mode: Receive - Subtracting middleman amounts from final totals")
                }
            }
            
            print("💵 Final Amounts After Middleman Adjustments:")
            print("   Final Cash: $\(finalCash)")
            print("   Final Bank: $\(finalBank)")
            print("   Final Card: $\(finalCard)")
            
            // Prepare phone details for purchase document
            var purchasedPhones: [[String: Any]] = []
            for phoneItem in cartItems {
                for imei in phoneItem.imeis {
                    var phoneDetail: [String: Any] = [
                        "brand": phoneItem.brand,
                        "model": phoneItem.model,
                        "capacity": phoneItem.capacity,
                        "capacityUnit": phoneItem.capacityUnit,
                        "imei": imei,
                        "unitCost": phoneItem.unitCost,
                        "status": phoneItem.status,
                        "storageLocation": phoneItem.storageLocation
                    ]
                    
                    if !phoneItem.carrier.isEmpty {
                        phoneDetail["carrier"] = phoneItem.carrier
                    }
                    if !phoneItem.color.isEmpty {
                        phoneDetail["color"] = phoneItem.color
                    }
                    
                    purchasedPhones.append(phoneDetail)
                }
            }
            
            // Prepare order number variables first
            let orderNumberDocRef = db.collection("OrderNumbers").document()
            print("🔢 Creating order number document: \(orderNumberDocRef.documentID)")
            
            // Extract the numeric part from the order number (remove "ORD-" prefix)
            let orderNumberValue = orderNumber.replacingOccurrences(of: "ORD-", with: "")
            let orderNumberInt = Int(orderNumberValue) ?? 1
            
            // Prepare purchase document data
            var purchaseData: [String: Any] = [
                "transactionDate": selectedDate,
                "orderNumber": orderNumberInt,
                "orderNumberReference": orderNumberDocRef,
                "isCustomOrderNumber": isOrderNumberCustom,
                "subtotal": subtotal,
                "gstPercentage": Double(gstPercentage) ?? 0.0,
                "gstAmount": gstAmount,
                "pstPercentage": Double(pstPercentage) ?? 0.0,
                "pstAmount": pstAmount,
                "adjustmentAmount": adjustmentAmountValue,
                "adjustmentUnit": adjustmentUnit,
                "grandTotal": grandTotal,
                "notes": notes,
                "purchasedPhones": purchasedPhones,
                "paymentMethods": [
                    "cash": totalCashPaid,
                    "bank": totalBankPaid,
                    "creditCard": totalCreditCardPaid,
                    "totalPaid": totalPaid,
                    "remainingCredit": remainingCredit
                ]
            ]
            
            // Add middleman payment details if applicable
            var middlemanDocRef: DocumentReference?
            var middlemanCollectionName: String?
            
            if useMiddlemanPayment, let middleman = selectedMiddleman {
                print("🤝 Adding middleman to purchase:")
                print("   Name: \(middleman.name)")
                print("   Type: \(middleman.entityType)")
                print("   Amount: \(middlemanAmount)")
                print("   Amount Value: \(middlemanPaymentAmountValue)")
                print("   Unit: \(middlemanUnit)")
                print("   Credit Amount: \(middlemanCreditAmount)")
                
                // Determine collection based on entity type
                let collectionName: String
                switch middleman.entityType {
                case .customer:
                    collectionName = "Customers"
                case .supplier:
                    collectionName = "Suppliers"
                case .middleman:
                    collectionName = "Middlemen"
                }
                
                middlemanCollectionName = collectionName
                print("🔍 Searching for middleman in \(collectionName) collection")
                
                // Get middleman reference from appropriate collection
                let middlemanQuery = db.collection(collectionName).whereField("name", isEqualTo: middleman.name).limit(to: 1)
                let middlemanSnapshot = try await middlemanQuery.getDocuments()
                
                if let middlemanDoc = middlemanSnapshot.documents.first {
                    print("✅ Found middleman document: \(middlemanDoc.documentID)")
                    middlemanDocRef = middlemanDoc.reference
                    purchaseData["middleman"] = middlemanDoc.reference
                    purchaseData["middlemanName"] = middleman.name
                    purchaseData["middlemanEntityType"] = middleman.entityType.rawValue
                    purchaseData["middlemanPayment"] = [
                        "amount": middlemanPaymentAmountValue,
                        "unit": middlemanUnit,
                        "paymentSplit": [
                            "cash": middlemanCashAmountValue,
                            "bank": middlemanBankAmountValue,
                            "creditCard": middlemanCreditCardAmountValue,
                            "credit": middlemanCreditAmount
                        ]
                    ]
                } else {
                    print("❌ Middleman document not found in \(collectionName) collection for name: \(middleman.name)")
                }
            } else {
                print("ℹ️ Middleman conditions not met - useMiddlemanPayment: \(useMiddlemanPayment), selectedMiddleman: \(selectedMiddleman?.name ?? "nil")")
            }
            
            // Add supplier details if applicable
            var supplierDocRef: DocumentReference?
            var supplierCollectionName: String?
            
            if let supplier = selectedSupplier {
                print("🏪 Adding supplier to purchase:")
                print("   Name: \(supplier.name)")
                print("   Type: \(supplier.entityType)")
                
                // Determine collection based on entity type
                let collectionName: String
                switch supplier.entityType {
                case .customer:
                    collectionName = "Customers"
                case .supplier:
                    collectionName = "Suppliers"
                case .middleman:
                    collectionName = "Middlemen"
                }
                
                supplierCollectionName = collectionName
                print("🔍 Searching for supplier in \(collectionName) collection")
                
                let supplierQuery = db.collection(collectionName).whereField("name", isEqualTo: supplier.name).limit(to: 1)
                let supplierSnapshot = try await supplierQuery.getDocuments()
                
                if let supplierDoc = supplierSnapshot.documents.first {
                    print("✅ Found supplier document: \(supplierDoc.documentID)")
                    supplierDocRef = supplierDoc.reference
                    purchaseData["supplier"] = supplierDoc.reference
                    purchaseData["supplierName"] = supplier.name
                    purchaseData["supplierEntityType"] = supplier.entityType.rawValue
                } else {
                    print("❌ Supplier document not found in \(collectionName) collection for name: \(supplier.name)")
                }
            }
            
            // Set purchase document in batch
            print("💾 Adding purchase document to batch: \(purchaseDocRef.documentID)")
            batch.setData(purchaseData, forDocument: purchaseDocRef)
            
            // Save order number to OrderNumbers collection
            let orderNumberData: [String: Any] = [
                "orderNumber": orderNumberInt,
                "isCustom": isOrderNumberCustom,
                "purchaseReference": purchaseDocRef,
                "createdAt": selectedDate,
                "transactionDate": selectedDate
            ]
            
            print("💾 Adding order number document to batch: \(orderNumberDocRef.documentID)")
            batch.setData(orderNumberData, forDocument: orderNumberDocRef)
            
            // Update supplier document with transaction history and balance
            if let supplierDocRef = supplierDocRef, let supplierCollectionName = supplierCollectionName {
                print("🏪 Updating supplier document: \(supplierDocRef.documentID)")
                
                // Get current supplier document to read existing data
                let supplierDoc = try await supplierDocRef.getDocument()
                
                if supplierDoc.exists {
                    let supplierData = supplierDoc.data() ?? [:]
                    var updatedData: [String: Any] = [:]
                    
                    // Handle transaction history
                    var transactionHistory: [[String: Any]] = supplierData["transactionHistory"] as? [[String: Any]] ?? []
                    transactionHistory.append([
                        "purchaseReference": purchaseDocRef,
                        "timestamp": selectedDate,
                        "role": "supplier"
                    ])
                    updatedData["transactionHistory"] = transactionHistory
                    print("📝 Added transaction history entry for supplier")
                    
                    // Handle balance update
                    let currentBalance = supplierData["balance"] as? Double ?? supplierData["Balance"] as? Double ?? supplierData["accountBalance"] as? Double ?? supplierData["AccountBalance"] as? Double ?? 0.0
                    let newBalance = currentBalance - abs(remainingCredit) // Always subtract the amount owed
                    updatedData["balance"] = newBalance
                    
                    print("💰 Supplier balance update:")
                    print("   Current balance: $\(currentBalance)")
                    print("   Remaining credit: $\(remainingCredit)")
                    print("   New balance: $\(newBalance)")
                    
                    // Update supplier document in batch
                    batch.updateData(updatedData, forDocument: supplierDocRef)
                } else {
                    print("❌ Supplier document does not exist: \(supplierDocRef.documentID)")
                }
            }
            
            // Update middleman document with transaction history and balance
            if let middlemanDocRef = middlemanDocRef, let middlemanCollectionName = middlemanCollectionName {
                print("🤝 Updating middleman document: \(middlemanDocRef.documentID)")
                
                // Get current middleman document to read existing data
                let middlemanDoc = try await middlemanDocRef.getDocument()
                
                if middlemanDoc.exists {
                    let middlemanData = middlemanDoc.data() ?? [:]
                    var updatedData: [String: Any] = [:]
                    
                    // Handle transaction history
                    var transactionHistory: [[String: Any]] = middlemanData["transactionHistory"] as? [[String: Any]] ?? []
                    transactionHistory.append([
                        "purchaseReference": purchaseDocRef,
                        "timestamp": selectedDate,
                        "role": "middleman"
                    ])
                    updatedData["transactionHistory"] = transactionHistory
                    print("📝 Added transaction history entry for middleman")
                    
                    // Handle balance update
                    let currentBalance = middlemanData["balance"] as? Double ?? middlemanData["Balance"] as? Double ?? middlemanData["accountBalance"] as? Double ?? middlemanData["AccountBalance"] as? Double ?? 0.0
                    let newBalance: Double
                    if middlemanUnit == "give" {
                        newBalance = currentBalance - middlemanCreditAmount // Deduct credit amount when giving
                    } else {
                        newBalance = currentBalance + middlemanCreditAmount // Add credit amount when receiving
                    }
                    updatedData["balance"] = newBalance
                    
                    print("💰 Middleman balance update:")
                    print("   Current balance: $\(currentBalance)")
                    print("   Unit: \(middlemanUnit)")
                    print("   Credit amount: $\(middlemanCreditAmount)")
                    print("   New balance: $\(newBalance)")
                    
                    // Update middleman document in batch
                    batch.updateData(updatedData, forDocument: middlemanDocRef)
                } else {
                    print("❌ Middleman document does not exist: \(middlemanDocRef.documentID)")
                }
            }
            
            // Update Balances collection with final payment amounts
            print("💳 Updating Balances collection:")
            
            // Update cash balance
            print("💰 Updating cash balance...")
            let cashDocRef = db.collection("Balances").document("cash")
            let cashDoc = try await cashDocRef.getDocument()
            
            if cashDoc.exists {
                let cashData = cashDoc.data() ?? [:]
                let currentCashBalance = cashData["amount"] as? Double ?? 0.0
                let newCashBalance = currentCashBalance - finalCash
                
                print("   Current cash balance: $\(currentCashBalance)")
                print("   Final cash amount: $\(finalCash)")
                print("   New cash balance: $\(newCashBalance)")
                
                batch.updateData([
                    "amount": newCashBalance,
                    "updatedAt": selectedDate
                ], forDocument: cashDocRef)
            } else {
                print("❌ Cash balance document does not exist")
            }
            
            // Update bank balance
            print("🏦 Updating bank balance...")
            let bankDocRef = db.collection("Balances").document("bank")
            let bankDoc = try await bankDocRef.getDocument()
            
            if bankDoc.exists {
                let bankData = bankDoc.data() ?? [:]
                let currentBankBalance = bankData["amount"] as? Double ?? 0.0
                let newBankBalance = currentBankBalance - finalBank
                
                print("   Current bank balance: $\(currentBankBalance)")
                print("   Final bank amount: $\(finalBank)")
                print("   New bank balance: $\(newBankBalance)")
                
                batch.updateData([
                    "amount": newBankBalance,
                    "updatedAt": selectedDate
                ], forDocument: bankDocRef)
            } else {
                print("❌ Bank balance document does not exist")
            }
            
            // Update credit card balance
            print("💳 Updating credit card balance...")
            let creditCardDocRef = db.collection("Balances").document("creditCard")
            let creditCardDoc = try await creditCardDocRef.getDocument()
            
            if creditCardDoc.exists {
                let creditCardData = creditCardDoc.data() ?? [:]
                let currentCreditCardBalance = creditCardData["amount"] as? Double ?? 0.0
                let newCreditCardBalance = currentCreditCardBalance - finalCard
                
                print("   Current credit card balance: $\(currentCreditCardBalance)")
                print("   Final credit card amount: $\(finalCard)")
                print("   New credit card balance: $\(newCreditCardBalance)")
                
                batch.updateData([
                    "amount": newCreditCardBalance,
                    "updatedAt": selectedDate
                ], forDocument: creditCardDocRef)
            } else {
                print("❌ Credit card balance document does not exist")
            }
            
            // Commit the batch
            print("🚀 Committing Firestore batch...")
            try await batch.commit()
            print("✅ Batch committed successfully!")
            
            // Clear cart and show success
            await MainActor.run {
                print("🧹 Clearing cart and form data...")
                cartItems.removeAll()
                cashAmount = ""
                bankAmount = ""
                creditCardAmount = ""
                gstPercentage = ""
                pstPercentage = ""
                adjustmentAmount = ""
                notes = ""
                middlemanCashAmount = ""
                middlemanBankAmount = ""
                middlemanCreditCardAmount = ""
                showPaymentSuccess = true
                print("🎉 Payment confirmation completed successfully!")
                
                // Navigate to bill screen with a small delay to ensure Firestore document is available
                print("📱 Navigating to bill screen with purchase ID: \(purchaseDocRef.documentID)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onPaymentConfirmed(purchaseDocRef.documentID)
                }
            }
            
        } catch {
            print("❌ Error confirming payment: \(error)")
            print("📊 Error details: \(error.localizedDescription)")
            // Handle error - could show alert to user
        }
        
        await MainActor.run {
            isConfirmingPayment = false
            print("🏁 Payment confirmation process finished")
        }
    }
}

#Preview {
    PurchaseView(
        showingSupplierDropdown: .constant(false),
        selectedSupplier: .constant(nil),
        supplierButtonFrame: .constant(.zero),
        allEntities: .constant([]),
        supplierSearchText: .constant(""),
        entityFetchError: .constant(false),
        retryFetchEntities: .constant({}),
        onPaymentConfirmed: { _ in }
    )
}
