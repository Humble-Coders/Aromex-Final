//
//  SalesView.swift
//  Aromex
//
//  Created by Ansh Bajaj on 07/10/25.
//


//
//  SalesView.swift
//  Aromex
//
//  Created by User on 1/7/25.
//

import SwiftUI
import FirebaseFirestore
#if os(iOS)
import UIKit
#endif

struct SalesView: View {
    @Binding var showingCustomerDropdown: Bool
    @Binding var selectedCustomer: EntityWithType?
    @Binding var customerButtonFrame: CGRect
    @Binding var allEntities: [EntityWithType]
    @Binding var customerSearchText: String
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
    @FocusState private var isCustomerFieldFocused: Bool
    @State private var showingDeleteConfirmation = false
    @State private var itemToDelete: PhoneItem?
    @State private var showingDeleteSuccess = false
    @State private var deletedItemIndex: Int?
    
    // Service state
    @State private var serviceItems: [ServiceItem] = []
    @State private var showingAddServiceDialog = false
    @State private var serviceToEdit: ServiceItem?
    @State private var serviceToDelete: ServiceItem?
    @State private var showingDeleteServiceConfirmation = false
    
    // Payment details state
    @State private var gstPercentage: String = ""
    @State private var pstPercentage: String = ""
    @State private var adjustmentAmount: String = ""
    @State private var adjustmentUnit: String = "discount"
    @State private var notes: String = ""
    
    // Alert state
    @State private var showValidationAlert: Bool = false
    @State private var validationAlertMessage: String = ""
    @State private var showOverpaymentAlert: Bool = false
    @State private var overpaymentAlertMessage: String = ""
    
    // Barcode scanner listener state
    @State private var barcodeListener: ListenerRegistration?
    @State private var showBarcodeAlert: Bool = false
    @State private var barcodeAlertMessage: String = ""
    @State private var barcodeAlertTitle: String = ""
    
    // Middleman payment state
    @State private var useMiddlemanPayment: Bool = false
    @State private var middlemanSearchText: String = ""
    @State private var middlemanInternalSearchText: String = ""
    @State private var showingMiddlemanDropdown: Bool = false
    @State private var selectedMiddleman: EntityWithType? = nil
    @State private var middlemanAmount: String = ""
    @State private var middlemanUnit: String = "give"
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
    var productSubtotal: Double {
        cartItems.reduce(0) { $0 + $1.unitCost }
    }
    
    var serviceSubtotal: Double {
        serviceItems.reduce(0) { $0 + $1.price }
    }
    
    var subtotal: Double {
        productSubtotal + serviceSubtotal
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
    
    var isMainPaymentOverpaid: Bool {
        let totalPayment = cashAmountValue + bankAmountValue + creditCardAmountValue
        return totalPayment > grandTotal
    }
    
    var isMiddlemanPaymentOverpaid: Bool {
        let totalMiddlemanPayment = middlemanCashAmountValue + middlemanBankAmountValue + middlemanCreditCardAmountValue
        return totalMiddlemanPayment > middlemanPaymentAmountValue
    }
    
    var grandTotal: Double {
        let adjustmentValue: Double
        if adjustmentUnit == "discount" {
            adjustmentValue = -adjustmentAmountValue
        } else {
            adjustmentValue = adjustmentAmountValue
        }
        
        return subtotal + gstAmount + pstAmount + adjustmentValue
    }
    
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
        if customerSearchText.isEmpty {
            return allEntities
        } else {
            return allEntities.filter { entity in
                entity.name.localizedCaseInsensitiveContains(customerSearchText) ||
                entity.entityType.rawValue.localizedCaseInsensitiveContains(customerSearchText)
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
                        proxy.scrollTo(fieldId, anchor: .top)
                    }
                }
                retryFetchEntities = { fetchAllEntities() }
                setupOrderNumberListener()
                setupBarcodeListener()
                fetchAllEntities()
            }
            .onDisappear {
                stopOrderNumberListener()
                stopBarcodeListener()
            }
            .onChange(of: showingCustomerDropdown) { isOpen in
                isCustomerFieldFocused = isOpen
                if isOpen {
                    // Clear search text to show unfiltered list
                    if selectedCustomer != nil {
                        customerSearchText = ""
                    }
                    // Scroll to field
                    #if os(iOS)
                    if isCompact {
                        // Use the scrollToField closure that's already set up
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToField?("customerDropdownField")
                        }
                    }
                    #endif
                }
            }
            .fullScreenCover(isPresented: $showingAddProductDialog) {
                SalesAddProductDialog(isPresented: $showingAddProductDialog, onDismiss: nil, onSave: { items in
                    cartItems.append(contentsOf: expandedItems(from: items))
                }, existingCartItems: cartItems)
            }
            .fullScreenCover(item: $itemToEdit) { item in
                SalesEditProductDialog(isPresented: .constant(true), onDismiss: {
                    itemToEdit = nil
                }, onSave: { items in
                    updateCartItem(with: items.first!)
                }, itemToEdit: item, existingCartItems: cartItems)
            }
            .fullScreenCover(isPresented: $showingAddServiceDialog) {
                AddServiceDialog(isPresented: $showingAddServiceDialog, onDismiss: nil, onSave: { service in
                    serviceItems.append(service)
                })
            }
            .fullScreenCover(item: $serviceToEdit) { service in
                AddServiceDialog(isPresented: .constant(true), onDismiss: {
                    serviceToEdit = nil
                }, onSave: { updatedService in
                    updateServiceItem(with: updatedService)
                }, serviceToEdit: service)
            }
            .modifier(DeleteConfirmationModifier(
                isPresented: $showingDeleteConfirmation,
                showingSuccess: $showingDeleteSuccess,
                itemToDelete: itemToDelete,
                onDelete: deleteItem,
                onCancel: { itemToDelete = nil }
            ))
            .confirmationDialog("Delete Service?", isPresented: $showingDeleteServiceConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteService()
                }
                Button("Cancel", role: .cancel) {
                    serviceToDelete = nil
                }
            } message: {
                if let service = serviceToDelete {
                    Text("Are you sure you want to delete '\(service.name)' from the cart?")
                }
            }
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
            .alert(barcodeAlertTitle, isPresented: $showBarcodeAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(barcodeAlertMessage)
            }
        }
        #else
        ScrollView {
            VStack(spacing: 0) {
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
            setupBarcodeListener()
            fetchAllEntities()
        }
        .onDisappear {
            stopOrderNumberListener()
            stopBarcodeListener()
        }
        .onChange(of: showingCustomerDropdown) { isOpen in
            isCustomerFieldFocused = isOpen
        }
        .sheet(isPresented: $showingAddProductDialog) {
            SalesAddProductDialog(isPresented: $showingAddProductDialog, onDismiss: nil, onSave: { items in
                cartItems.append(contentsOf: expandedItems(from: items))
            }, existingCartItems: cartItems)
        }
        .sheet(item: $itemToEdit) { item in
            SalesEditProductDialog(isPresented: .constant(true), onDismiss: {
                itemToEdit = nil
            }, onSave: { items in
                updateCartItem(with: items.first!)
            }, itemToEdit: item, existingCartItems: cartItems)
        }
        .sheet(isPresented: $showingAddServiceDialog) {
            AddServiceDialog(isPresented: $showingAddServiceDialog, onDismiss: nil, onSave: { service in
                serviceItems.append(service)
            })
        }
        .sheet(item: $serviceToEdit) { service in
            AddServiceDialog(isPresented: .constant(true), onDismiss: {
                serviceToEdit = nil
            }, onSave: { updatedService in
                updateServiceItem(with: updatedService)
            }, serviceToEdit: service)
        }
        .modifier(DeleteConfirmationModifier(
            isPresented: $showingDeleteConfirmation,
            showingSuccess: $showingDeleteSuccess,
            itemToDelete: itemToDelete,
            onDelete: deleteItem,
            onCancel: { itemToDelete = nil }
        ))
        .confirmationDialog("Delete Service?", isPresented: $showingDeleteServiceConfirmation) {
            Button("Delete", role: .destructive) {
                deleteService()
            }
            Button("Cancel", role: .cancel) {
                serviceToDelete = nil
            }
        } message: {
            if let service = serviceToDelete {
                Text("Are you sure you want to delete '\(service.name)' from the cart?")
            }
        }
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
        .alert(barcodeAlertTitle, isPresented: $showBarcodeAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(barcodeAlertMessage)
        }
        #endif
    }
    
    // MARK: - Layout Views
    var iPhoneLayout: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                orderNumberField
                dateField
                customerDropdown
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
            
            HStack(spacing: 16) {
                addProductButton
                addServiceButton
            }
            
            if !cartItems.isEmpty || !serviceItems.isEmpty {
                cartTableCompact
                paymentDetailsSection
                compactPaymentOptionsSection
            }
        }
    }
    
    var iPadMacLayout: some View {
        VStack(spacing: 40) {
            VStack(spacing: 30) {
                HStack(spacing: 24) {
                    orderNumberField
                    dateField
                    customerDropdown
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                )
            }
            
            HStack(spacing: 16) {
                addProductButton
                addServiceButton
            }
            
            if !cartItems.isEmpty || !serviceItems.isEmpty {
                if isIPadVertical {
                    cartTableCompact
                    paymentDetailsSection
                } else {
                    VStack(spacing: 20) {
                        if isMacOS {
                            cartTableMacOS
                        } else {
                            cartTableRegular
                        }
                        
                        HStack(alignment: .top, spacing: 20) {
                            paymentOptionsSection
                                .frame(maxWidth: .infinity)
                            
                            paymentDetailsSection
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Cart Tables (copied from PurchaseView)
    private var cartTableCompact: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !cartItems.isEmpty {
                Text("Added Phones")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                
                ForEach(Array(cartItems.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
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
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "$ %.2f", item.unitCost))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                            
                            statusBadge(text: item.status)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    HStack(spacing: 8) {
                        uniformBadge(text: item.color)
                        if !item.carrier.isEmpty { uniformBadge(text: item.carrier) }
                        locationBadge(text: item.storageLocation)
                        Spacer()
                    }
                    
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
            
            if !serviceItems.isEmpty {
                Text("Added Services")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.top, cartItems.isEmpty ? 0 : 20)
                
                ForEach(Array(serviceItems.enumerated()), id: \.element.id) { index, service in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color(red: 0.80, green: 0.40, blue: 0.20))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(service.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    Text("Service")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color(red: 0.80, green: 0.40, blue: 0.20).opacity(0.15))
                                        )
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(String(format: "$ %.2f", service.price))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Spacer()
                            
                            Button(action: {
                                serviceToEdit = service
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
                                serviceToDelete = service
                                showingDeleteServiceConfirmation = true
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
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.regularMaterial)
                            .stroke(Color(red: 0.80, green: 0.40, blue: 0.20).opacity(0.2), lineWidth: 1)
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    )
                }
            }
        }
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
            GridItem(.fixed(30), spacing: 8, alignment: .leading),
            GridItem(.flexible(minimum: 45), spacing: 8, alignment: .leading),
            GridItem(.fixed(80), spacing: 8, alignment: .leading),
            GridItem(.fixed(70), spacing: 8, alignment: .leading),
            GridItem(.fixed(90), spacing: 8, alignment: .leading),
            GridItem(.fixed(80), spacing: 8, alignment: .leading),
            GridItem(.fixed(100), spacing: 8, alignment: .leading),
            GridItem(.fixed(140), spacing: 8, alignment: .leading),
            GridItem(.fixed(100), spacing: 8, alignment: .leading),
            GridItem(.fixed(100), spacing: 0, alignment: .leading)
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
            GridItem(.fixed(30), spacing: 8, alignment: .leading),
            GridItem(.flexible(minimum: 45), spacing: 8, alignment: .leading),
            GridItem(.fixed(80), spacing: 8, alignment: .leading),
            GridItem(.fixed(70), spacing: 8, alignment: .leading),
            GridItem(.fixed(90), spacing: 8, alignment: .leading),
            GridItem(.fixed(80), spacing: 8, alignment: .leading),
            GridItem(.fixed(100), spacing: 8, alignment: .leading),
            GridItem(.fixed(140), spacing: 8, alignment: .leading),
            GridItem(.fixed(100), spacing: 8, alignment: .leading),
            GridItem(.fixed(100), spacing: 0, alignment: .leading)
        ]
        
        return VStack(spacing: 0) {
            // Products
            ForEach(cartItems.indices, id: \.self) { index in
                let item = cartItems[index]
                let rowNumber = index + 1
                let isLastProduct = index == cartItems.count - 1 && serviceItems.isEmpty
                
                LazyVGrid(columns: columns, spacing: 8) {
                    Text("\(rowNumber)").font(.system(size: 14))
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
                .drawingGroup()
                
                if !isLastProduct {
                    Divider()
                        .padding(.leading, 16)
                }
            }
            
            // Services
            ForEach(serviceItems.indices, id: \.self) { index in
                let service = serviceItems[index]
                let rowNumber = cartItems.count + index + 1
                let isLastService = index == serviceItems.count - 1
                
                LazyVGrid(columns: columns, spacing: 8) {
                    Text("\(rowNumber)").font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(service.name).font(.system(size: 14, weight: .semibold))
                            Text("(Service)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(red: 0.80, green: 0.40, blue: 0.20).opacity(0.15))
                                )
                        }
                        Text("Service Item").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    Text("-").font(.system(size: 14)).foregroundColor(.secondary)
                    Text("-").font(.system(size: 14)).foregroundColor(.secondary)
                    Text("-").font(.system(size: 14)).foregroundColor(.secondary)
                    Text("Service").font(.system(size: 14)).foregroundColor(Color(red: 0.80, green: 0.40, blue: 0.20))
                    Text("-").font(.system(size: 14)).foregroundColor(.secondary)
                    Text("-").font(.system(size: 14)).foregroundColor(.secondary)
                    Text(String(format: "$ %.2f", service.price)).font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 8) {
                        Button(action: {
                            serviceToEdit = service
                        }) {
                            actionIconButton(systemName: "pencil", tint: Color.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            serviceToDelete = service
                            showingDeleteServiceConfirmation = true
                        }) {
                            actionIconButton(systemName: "trash", tint: Color.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(red: 0.80, green: 0.40, blue: 0.20).opacity(0.03))
                .drawingGroup()
                
                if !isLastService {
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
    
    private var cartTableMacOS: some View {
        VStack(spacing: 0) {
            cartTableMacOSHeader
            cartTableMacOSContent
        }
    }
    
    private var cartTableMacOSHeader: some View {
        let headerColor = Color(red: 0.25, green: 0.33, blue: 0.54)
        let columns: [GridItem] = [
            GridItem(.fixed(40), spacing: 20, alignment: .leading),
            GridItem(.flexible(minimum: 180), spacing: 20, alignment: .leading),
            GridItem(.fixed(100), spacing: 20, alignment: .leading),
            GridItem(.fixed(100), spacing: 20, alignment: .leading),
            GridItem(.fixed(120), spacing: 20, alignment: .leading),
            GridItem(.fixed(100), spacing: 20, alignment: .leading),
            GridItem(.fixed(120), spacing: 20, alignment: .leading),
            GridItem(.fixed(180), spacing: 20, alignment: .leading),
            GridItem(.fixed(120), spacing: 20, alignment: .leading),
            GridItem(.fixed(140), spacing: 0, alignment: .leading)
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
            GridItem(.fixed(40), spacing: 20, alignment: .leading),
            GridItem(.flexible(minimum: 180), spacing: 20, alignment: .leading),
            GridItem(.fixed(100), spacing: 20, alignment: .leading),
            GridItem(.fixed(100), spacing: 20, alignment: .leading),
            GridItem(.fixed(120), spacing: 20, alignment: .leading),
            GridItem(.fixed(100), spacing: 20, alignment: .leading),
            GridItem(.fixed(120), spacing: 20, alignment: .leading),
            GridItem(.fixed(180), spacing: 20, alignment: .leading),
            GridItem(.fixed(120), spacing: 20, alignment: .leading),
            GridItem(.fixed(140), spacing: 0, alignment: .leading)
        ]
        
        return VStack(spacing: 0) {
            // Products
            ForEach(cartItems.indices, id: \.self) { index in
                let item = cartItems[index]
                let rowNumber = index + 1
                let isLastProduct = index == cartItems.count - 1 && serviceItems.isEmpty
                
                LazyVGrid(columns: columns, spacing: 20) {
                    Text("\(rowNumber)").font(.system(size: 14))
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
                .drawingGroup()
                
                if !isLastProduct {
                    Divider()
                        .padding(.leading, 20)
                }
            }
            
            // Services
            ForEach(serviceItems.indices, id: \.self) { index in
                let service = serviceItems[index]
                let rowNumber = cartItems.count + index + 1
                let isLastService = index == serviceItems.count - 1
                
                LazyVGrid(columns: columns, spacing: 20) {
                    Text("\(rowNumber)").font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(service.name).font(.system(size: 14, weight: .semibold))
                            Text("(Service)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(red: 0.80, green: 0.40, blue: 0.20).opacity(0.15))
                                )
                        }
                        Text("Service Item").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    Text("-").font(.system(size: 14)).foregroundColor(.secondary)
                    Text("-").font(.system(size: 14)).foregroundColor(.secondary)
                    Text("-").font(.system(size: 14)).foregroundColor(.secondary)
                    Text("Service").font(.system(size: 14)).foregroundColor(Color(red: 0.80, green: 0.40, blue: 0.20))
                    Text("-").font(.system(size: 14)).foregroundColor(.secondary)
                    Text("-").font(.system(size: 14)).foregroundColor(.secondary)
                    Text(String(format: "$ %.2f", service.price)).font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 8) {
                        Button(action: {
                            serviceToEdit = service
                        }) {
                            actionIconButton(systemName: "pencil", tint: Color.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            serviceToDelete = service
                            showingDeleteServiceConfirmation = true
                        }) {
                            actionIconButton(systemName: "trash", tint: Color.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(red: 0.80, green: 0.40, blue: 0.20).opacity(0.03))
                .drawingGroup()
                
                if !isLastService {
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
            
            // MARK: - Payment Details Section (copied from PurchaseView)
            private var paymentDetailsSection: some View {
                if cartItems.isEmpty && serviceItems.isEmpty {
                    return AnyView(EmptyView())
                }
                
                return AnyView(
                    VStack(alignment: .leading, spacing: 0) {
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
                        
                        VStack(spacing: 0) {
                            taxInputSection
                            adjustmentSection
                            notesSection
                            professionalPaymentRow(title: "Subtotal", amount: subtotal, isHighlighted: false, showDivider: true)
                            professionalPaymentRow(title: "GST", amount: gstAmount, isHighlighted: false, showDivider: true)
                            professionalPaymentRow(title: "PST", amount: pstAmount, isHighlighted: false, showDivider: true)
                            adjustmentRow
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
                    
                    VStack(spacing: 0) {
                        enhancedPaymentField(title: "Cash", amount: $cashAmount, icon: "banknote", color: .green)
                        enhancedPaymentField(title: "Bank Transfer", amount: $bankAmount, icon: "building.columns", color: .blue)
                        VStack(spacing: 0) {
                            HStack(spacing: 16) {
                                // Icon
                                Image(systemName: "creditcard")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.purple.opacity(0.5))
                                    .frame(width: 24, height: 24)
                                
                                // Title
                                Text("Credit Card")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary.opacity(0.5))
                                
                                Spacer()
                                
                                // N/A placeholder instead of amount input
                                HStack(spacing: 2) {
                                    Text("$")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    
                                    Text("N/A for Sales")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary.opacity(0.7))
                                        .italic()
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.05))
                            
                            Rectangle()
                                .fill(Color.secondary.opacity(0.12))
                                .frame(height: 1)
                                .padding(.horizontal, 20)
                        }
                        enhancedCreditField
                        enhancedConfirmButton
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    )
                    
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
                    
                    VStack(spacing: 0) {
                        compactPaymentField(title: "Cash", amount: $cashAmount, icon: "banknote", color: .green)
                        compactPaymentField(title: "Bank Transfer", amount: $bankAmount, icon: "building.columns", color: .blue)
                        VStack(spacing: 0) {
                            HStack(spacing: 16) {
                                // Icon
                                Image(systemName: "creditcard")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.purple.opacity(0.5))
                                    .frame(width: 24, height: 24)
                                
                                // Title
                                Text("Credit Card")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary.opacity(0.5))
                                
                                Spacer()
                                
                                // N/A placeholder
                                Text("N/A")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .italic()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.05))
                            
                            Rectangle()
                                .fill(Color.secondary.opacity(0.12))
                                .frame(height: 1)
                                .padding(.horizontal, 20)
                        }
                        compactCreditField
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
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(color)
                            .frame(width: 24, height: 24)
                        
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
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
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(width: 24, height: 24)
                        
                        Text("Credit (Remaining)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
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
            
            private func enhancedPaymentField(title: String, amount: Binding<String>, icon: String, color: Color) -> some View {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(color)
                            .frame(width: 24, height: 24)
                        
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
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
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(width: 24, height: 24)
                        
                        Text("Credit (Remaining)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
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
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(color)
                            .frame(width: 20, height: 20)
                        
                        Text(title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
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
                        gstInputField
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
                    adjustmentInputField
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .padding(.bottom, 12)
                }
            }
            
            private var notesSection: some View {
                VStack(spacing: 16) {
                    notesInputField
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

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
                            middlemanDropdownButton
                                .padding(.horizontal, 20)

                            if showingMiddlemanDropdown {
                                middlemanDropdownInline
                                    .padding(.horizontal, 20)
                                    .transition(.opacity)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Amount")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                ZStack {
                                    TextField("0.0", text: $middlemanAmount)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                        .font(.system(size: 16, weight: .medium))
                                        .padding(.horizontal, 12)
                                        .padding(.trailing, 120)
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
                                    
                                    HStack(spacing: 8) {
                                        Spacer()
                                        
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
                                
                                if middlemanPaymentAmountValue > 0 {
                                    middlemanPaymentSplitRow
                                }
                            }
                            .padding(.horizontal, 20)
                            .onChange(of: middlemanUnit) { _ in
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
                    compactPaymentItem(title: "Cash", amount: $middlemanCashAmount, icon: "banknote", color: .green)
                    compactPaymentItem(title: "Bank", amount: $middlemanBankAmount, icon: "building.columns", color: .blue)
                    compactPaymentItem(title: "Card", amount: $middlemanCreditCardAmount, icon: "creditcard", color: .purple)
                        .disabled(middlemanUnit == "receive")
                        .opacity(middlemanUnit == "receive" ? 0.5 : 1.0)
                    
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
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    if filtered.isEmpty {
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
                                return 120
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
                    
                    private var customerDropdownInline: some View {
                        let source = allEntities
                        // Use empty query if dropdown just opened with a selection to show unfiltered
                        let effectiveSearchText = customerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let query = effectiveSearchText
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
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    if filtered.isEmpty {
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
                                                    selectedCustomer = entity
                                                    customerSearchText = entity.name
                                                    showingCustomerDropdown = false
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
                                                    if selectedCustomer?.id == entity.id {
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
                                return 120
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
                        .onAppear {
                            // Scroll to field when dropdown appears
                            #if os(iOS)
                            if isCompact {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    scrollToField?("customerDropdownField")
                                }
                            }
                            #endif
                        }
                    }
                    
                    private var adjustmentInputField: some View {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Adjustment")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            ZStack {
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
                                    .padding(.trailing, 120)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.secondary.opacity(0.08))
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                                    .onChange(of: adjustmentAmount) { newValue in
                                        let filtered = newValue.filter { "0123456789.".contains($0) }
                                        if filtered != newValue {
                                            adjustmentAmount = filtered
                                            return
                                        }
                                        
                                        let currentGrandTotal = subtotal + gstAmount + pstAmount
                                        if let amount = Double(filtered), amount > currentGrandTotal {
                                            adjustmentAmount = String(format: "%.2f", currentGrandTotal)
                                        }
                                    }
                                    .id("adjustmentField")
                                
                                HStack(spacing: 8) {
                                    Spacer()
                                    
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
                    
                    // MARK: - Form Fields
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
                                    if !originalOrderNumber.isEmpty && newValue != originalOrderNumber && newValue != "Loading..." {
                                        isOrderNumberCustom = true
                                    } else if !originalOrderNumber.isEmpty && newValue == originalOrderNumber {
                                        isOrderNumberCustom = false
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
                            
                            Text("The date when this sale was made")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    var customerDropdown: some View {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Customer")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("*")
                                    .foregroundColor(.red)
                            }
                            
                            SupplierDropdownButton(
                                selectedSupplier: selectedCustomer,
                                placeholder: "Choose a customer",
                                isOpen: $showingCustomerDropdown,
                                buttonFrame: $customerButtonFrame,
                                searchText: $customerSearchText,
                                isFocused: $isCustomerFieldFocused
                            )
                            .frame(height: 44)
                            
                            // Inline dropdown for iOS (iPhone only)
                            #if os(iOS)
                            if showingCustomerDropdown && isCompact {
                                customerDropdownInline
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                            #endif
                            
                            Text("Select a customer for this sale")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .id("customerDropdownField")
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
            .frame(maxWidth: .infinity)
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
                    
    var addServiceButton: some View {
        Button(action: {
            showingAddServiceDialog = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 18, weight: .medium))
                
                Text("Add Service")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.80, green: 0.40, blue: 0.20),
                                Color(red: 0.70, green: 0.35, blue: 0.15)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .shadow(color: Color(red: 0.80, green: 0.40, blue: 0.20).opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
                    
                    // MARK: - Helper Functions
                    private func setupOrderNumberListener() {
                        let db = Firestore.firestore()
                        
                        print("🔢 [Sales] Setting up OrderNumbers collection listener...")
                        
                        // Remove existing listener if any
                        orderNumberListener?.remove()
                        
                        // Set up listener for OrderNumbers collection (same as Purchase)
                        orderNumberListener = db.collection("OrderNumbers")
                            .addSnapshotListener { [self] snapshot, error in
                                if let error = error {
                                    print("❌ [Sales] Error listening to OrderNumbers collection: \(error)")
                                    DispatchQueue.main.async {
                                        self.orderNumber = "ORD-1"
                                    }
                                    return
                                }
                                
                                guard let snapshot = snapshot else {
                                    print("⚠️ [Sales] No snapshot received from OrderNumbers collection")
                                    DispatchQueue.main.async {
                                        self.orderNumber = "ORD-1"
                                    }
                                    return
                                }
                                
                                print("📊 [Sales] Received \(snapshot.documents.count) documents from OrderNumbers collection")
                                
                                var highestOrderNumber = 0
                                
                                // Find the highest order number across all documents (excluding custom orders)
                                for document in snapshot.documents {
                                    let data = document.data()
                                    
                                    // Skip custom order numbers (marked with isCustom flag)
                                    let isCustom = data["isCustom"] as? Bool ?? false
                                    if isCustom {
                                        print("⏭️ [Sales] Skipping custom order number: \(document.documentID)")
                                        continue
                                    }
                                    
                                    // Check for different possible field names
                                    if let orderNum = data["orderNumber"] as? Int {
                                        print("📄 [Sales] Found orderNumber: \(orderNum) in document: \(document.documentID)")
                                        highestOrderNumber = max(highestOrderNumber, orderNum)
                                    }
                                }
                                
                                let nextOrderNumber = highestOrderNumber + 1
                                
                                print("🎯 [Sales] Order number calculation:")
                                print("   Highest found: \(highestOrderNumber)")
                                print("   Next order number: \(nextOrderNumber)")
                                
                                DispatchQueue.main.async {
                                    // Only update order number if it's not custom
                                    if !self.isOrderNumberCustom {
                                        let newOrderNumber = "ORD-\(nextOrderNumber)"
                                        self.orderNumber = newOrderNumber
                                        self.originalOrderNumber = newOrderNumber
                                        print("✅ [Sales] Order number updated to: \(self.orderNumber)")
                                    } else {
                                        print("🔒 [Sales] Keeping custom order number: \(self.orderNumber)")
                                    }
                                }
                            }
                    }
                    
                    private func stopOrderNumberListener() {
                        print("🛑 [Sales] Stopping OrderNumbers collection listener...")
                        orderNumberListener?.remove()
                        orderNumberListener = nil
                    }
                    
                    // MARK: - Barcode Scanner Listener
                    private func setupBarcodeListener() {
                        let db = Firestore.firestore()
                        
                        print("📱 [Sales] Setting up barcode scanner listener...")
                        
                        // Remove existing listener if any
                        barcodeListener?.remove()
                        
                        // Set up listener for Data/scanner document
                        barcodeListener = db.collection("Data")
                            .document("scanner")
                            .addSnapshotListener { [self] snapshot, error in
                                if let error = error {
                                    print("❌ [Sales] Error listening to scanner document: \(error)")
                                    return
                                }
                                
                                guard let snapshot = snapshot, snapshot.exists else {
                                    print("⚠️ [Sales] Scanner document does not exist")
                                    return
                                }
                                
                                let data = snapshot.data() ?? [:]
                                
                                // Check if barcode field exists
                                if let barcode = data["barcode"] as? String, !barcode.isEmpty {
                                    print("📷 [Sales] Barcode detected: \(barcode)")
                                    
                                    // Immediately clear the barcode field to prevent reprocessing
                                    Task {
                                        do {
                                            try await db.collection("Data").document("scanner").updateData(["barcode": ""])
                                            print("🧹 [Sales] Immediately cleared barcode field")
                                        } catch {
                                            print("❌ [Sales] Failed to clear barcode field: \(error)")
                                        }
                                    }
                                    
                                    // Process the barcode
                                    Task {
                                        await self.processBarcode(barcode, db: db)
                                    }
                                }
                            }
                    }
                    
                    private func stopBarcodeListener() {
                        print("🛑 [Sales] Stopping barcode scanner listener...")
                        barcodeListener?.remove()
                        barcodeListener = nil
                    }
                    
                    private func processBarcode(_ imei: String, db: Firestore) async {
                        print("🔍 [Sales] Processing barcode/IMEI: \(imei)")
                        
                        do {
                            // Step 1: Check if IMEI exists in IMEI collection
                            let imeiQuery = db.collection("IMEI").whereField("imei", isEqualTo: imei).limit(to: 1)
                            let imeiSnapshot = try await imeiQuery.getDocuments()
                            
                            guard let imeiDoc = imeiSnapshot.documents.first else {
                                print("❌ [Sales] IMEI not found: \(imei)")
                                await MainActor.run {
                                    self.barcodeAlertTitle = "IMEI Not Found"
                                    self.barcodeAlertMessage = "The scanned IMEI '\(imei)' was not found in the inventory."
                                    self.showBarcodeAlert = true
                                }
                                return
                            }
                            
                            print("✅ [Sales] IMEI document found: \(imeiDoc.documentID)")
                            let imeiData = imeiDoc.data()
                            
                            // Step 2: Get the phone document reference
                            guard let phoneRef = imeiData["phoneReference"] as? DocumentReference else {
                                print("❌ [Sales] No phone document reference found")
                                await MainActor.run {
                                    self.barcodeAlertTitle = "Error"
                                    self.barcodeAlertMessage = "Phone reference not found for this IMEI."
                                    self.showBarcodeAlert = true
                                }
                                return
                            }
                            
                            print("📄 [Sales] Phone reference: \(phoneRef.path)")
                            
                            // Step 3: Get the phone document
                            let phoneDoc = try await phoneRef.getDocument()
                            
                            guard phoneDoc.exists, let phoneData = phoneDoc.data() else {
                                print("❌ [Sales] Phone document not found")
                                await MainActor.run {
                                    self.barcodeAlertTitle = "Error"
                                    self.barcodeAlertMessage = "Phone details not found."
                                    self.showBarcodeAlert = true
                                }
                                return
                            }
                            
                            print("✅ [Sales] Phone document found")
                            
                            // Step 4: Extract phone details and resolve references
                            let capacity = phoneData["capacity"] as? String ?? "0"
                            let capacityUnit = phoneData["capacityUnit"] as? String ?? "GB"
                            let status = phoneData["status"] as? String ?? "Active"
                            let unitCost = phoneData["unitCost"] as? Double ?? 0.0
                            
                            // Extract IMEI - show the entire string
                            var actualIMEI = imei
                            if let imeiData = phoneData["imei"] as? [String: Any] {
                                // Convert the entire IMEI object to JSON string
                                if let jsonData = try? JSONSerialization.data(withJSONObject: imeiData),
                                   let jsonString = String(data: jsonData, encoding: .utf8) {
                                    actualIMEI = jsonString
                                    print("✅ [Sales] Using entire IMEI object as string: \(jsonString)")
                                }
                            } else if let imeiString = phoneData["imei"] as? String {
                                // Use the string directly (it's already the full JSON string)
                                actualIMEI = imeiString
                                print("✅ [Sales] IMEI stored as direct string: \(imeiString)")
                            }
                            
                            // Resolve Firebase references
                            var brand = "Unknown"
                            var model = "Unknown"
                            var color = "Unknown"
                            var carrier = "Unknown"
                            var storageLocation = "Unknown"
                            
                            // Fetch brand name
                            if let brandRef = phoneData["brand"] as? DocumentReference {
                                do {
                                    let brandDoc = try await brandRef.getDocument()
                                    if let brandData = brandDoc.data() {
                                        print("🔍 [Sales] Brand document data: \(brandData)")
                                        // Try different possible field names
                                        if let brandName = brandData["brand"] as? String {
                                            brand = brandName
                                        } else if let brandName = brandData["name"] as? String {
                                            brand = brandName
                                        } else if let brandName = brandData["title"] as? String {
                                            brand = brandName
                                        }
                                    }
                                } catch {
                                    print("❌ [Sales] Failed to fetch brand: \(error)")
                                }
                            }
                            
                            // Fetch model name
                            if let modelRef = phoneData["model"] as? DocumentReference {
                                do {
                                    let modelDoc = try await modelRef.getDocument()
                                    if let modelData = modelDoc.data() {
                                        print("🔍 [Sales] Model document data: \(modelData)")
                                        // Try different possible field names
                                        if let modelName = modelData["model"] as? String {
                                            model = modelName
                                        } else if let modelName = modelData["name"] as? String {
                                            model = modelName
                                        } else if let modelName = modelData["title"] as? String {
                                            model = modelName
                                        }
                                    }
                                } catch {
                                    print("❌ [Sales] Failed to fetch model: \(error)")
                                }
                            }
                            
                            // Fetch color name
                            if let colorRef = phoneData["color"] as? DocumentReference {
                                do {
                                    let colorDoc = try await colorRef.getDocument()
                                    if let colorData = colorDoc.data(), let colorName = colorData["name"] as? String {
                                        color = colorName
                                        print("✅ [Sales] Fetched color: \(colorName)")
                                    }
                                } catch {
                                    print("❌ [Sales] Failed to fetch color: \(error)")
                                }
                            }
                            
                            // Fetch carrier name
                            if let carrierRef = phoneData["carrier"] as? DocumentReference {
                                do {
                                    let carrierDoc = try await carrierRef.getDocument()
                                    if let carrierData = carrierDoc.data(), let carrierName = carrierData["name"] as? String {
                                        carrier = carrierName
                                        print("✅ [Sales] Fetched carrier: \(carrierName)")
                                    }
                                } catch {
                                    print("❌ [Sales] Failed to fetch carrier: \(error)")
                                }
                            }
                            
                            // Fetch storage location name
                            if let storageRef = phoneData["storageLocation"] as? DocumentReference {
                                do {
                                    let storageDoc = try await storageRef.getDocument()
                                    if let storageData = storageDoc.data(), let storageName = storageData["storageLocation"] as? String {
                                        storageLocation = storageName
                                        print("✅ [Sales] Fetched storage location: \(storageName)")
                                    }
                                } catch {
                                    print("❌ [Sales] Failed to fetch storage location: \(error)")
                                }
                            }
                            
                            print("📱 [Sales] Phone details:")
                            print("   Brand: \(brand)")
                            print("   Model: \(model)")
                            print("   Capacity: \(capacity) \(capacityUnit)")
                            print("   Color: \(color)")
                            print("   Carrier: \(carrier)")
                            print("   Storage: \(storageLocation)")
                            print("   IMEI: \(actualIMEI)")
                            print("   Status: \(status)")
                            print("   Unit Cost: $\(unitCost)")
                            
                            // Step 5: Check if IMEI already exists in cart
                            let imeiExistsInCart = await MainActor.run {
                                return self.cartItems.contains { item in
                                    item.imeis.contains(actualIMEI)
                                }
                            }
                            
                            if imeiExistsInCart {
                                print("⚠️ [Sales] IMEI already in cart")
                                await MainActor.run {
                                    self.barcodeAlertTitle = "Already in Cart"
                                    self.barcodeAlertMessage = "This phone (IMEI: \(actualIMEI)) is already in the cart."
                                    self.showBarcodeAlert = true
                                }
                                return
                            }
                            
                            // Step 6: Create PhoneItem and add to cart
                            // unitCost from phoneData is the actual purchase cost
                            // We'll use this as the initial selling price, but store actualCost separately
                            let phoneItem = PhoneItem(
                                brand: brand,
                                model: model,
                                capacity: capacity,
                                capacityUnit: capacityUnit,
                                color: color,
                                carrier: carrier,
                                status: status,
                                storageLocation: storageLocation,
                                imeis: [actualIMEI],
                                unitCost: unitCost, // Initial selling price (can be edited)
                                actualCost: unitCost // Actual purchase cost from phone document
                            )
                            
                            await MainActor.run {
                                self.cartItems.append(phoneItem)
                                print("✅ [Sales] Phone added to cart successfully")
                                self.barcodeAlertTitle = "Added to Cart"
                                self.barcodeAlertMessage = "\(brand) \(model) (\(actualIMEI)) has been added to the cart."
                                self.showBarcodeAlert = true
                            }
                            
                        } catch {
                            print("❌ [Sales] Error processing barcode: \(error)")
                            await MainActor.run {
                                self.barcodeAlertTitle = "Error"
                                self.barcodeAlertMessage = "Failed to process barcode: \(error.localizedDescription)"
                                self.showBarcodeAlert = true
                            }
                        }
                    }
                    
                    private func fetchAllEntities() {
                        let db = Firestore.firestore()
                        var entities: [EntityWithType] = []
                        var hasError = false
                        let group = DispatchGroup()
                        
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
                                        
                                        let rawBalance = (data["balance"] ?? data["Balance"] ?? data["accountBalance"] ?? data["AccountBalance"])
                                        
                                        let parsedBalance: Double? = {
                                            if let d = rawBalance as? Double { return d }
                                            if let i = rawBalance as? Int { return Double(i) }
                                            if let n = rawBalance as? NSNumber { return n.doubleValue }
                                            if let s = rawBalance as? String { return Double(s) }
                                            return nil
                                        }()
                                        
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
                    
                    private func expandedItems(from items: [PhoneItem]) -> [PhoneItem] {
                        var result: [PhoneItem] = []
                        for item in items {
                            if item.imeis.isEmpty {
                                result.append(item)
                            } else {
                                for imei in item.imeis {
                                    var single = item
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
                                        unitCost: item.unitCost,
                                        actualCost: item.actualCost
                                    )
                                    result.append(single)
                                }
                            }
                        }
                        return result
                    }
                    
                    private func updateCartItem(with updatedItem: PhoneItem) {
                        cartItems.removeAll { $0.id == updatedItem.id }
                        cartItems.append(contentsOf: expandedItems(from: [updatedItem]))
                        itemToEdit = nil
                    }
                    
                    private func deleteItem() {
                        guard let item = itemToDelete else { return }
                        
                        if let index = cartItems.firstIndex(where: { $0.id == item.id }) {
                            deletedItemIndex = index
                            cartItems.remove(at: index)
                            showingDeleteSuccess = true
                            
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
                    
                    private func updateServiceItem(with updatedService: ServiceItem) {
                        serviceItems.removeAll { $0.id == updatedService.id }
                        serviceItems.append(updatedService)
                        serviceToEdit = nil
                    }
                    
                    private func deleteService() {
                        guard let service = serviceToDelete else { return }
                        serviceItems.removeAll { $0.id == service.id }
                        serviceToDelete = nil
                    }
                    
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
                    
                    #if os(iOS)
                    private func hideKeyboard() {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    #endif
                    
                    
                }
// MARK: - Sales Payment Confirmation Extension
// Add this extension at the bottom of SalesView.swift (after the existing extension if any)

extension SalesView {
    private func confirmPayment() async {
        guard !cartItems.isEmpty || !serviceItems.isEmpty else { return }
        
        // Validate required fields
        var missingFields: [String] = []
        
        if selectedCustomer == nil {
            missingFields.append("• Select a customer from the dropdown")
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
        
        print("🛒 Starting sales payment confirmation process...")
        print("📦 Cart items count: \(cartItems.count)")
        print("🔧 Service items count: \(serviceItems.count)")
        
        await MainActor.run {
            isConfirmingPayment = true
        }
        
        do {
            let db = Firestore.firestore()
            print("🔥 Connected to Firestore database")
            
            // PHASE 1: Collect data and references before transaction
            print("🔄 PHASE 1: Collecting data and references...")
            
            // Data structures to store references to documents for transaction
            var phonesToDelete: [(phoneRef: DocumentReference, imei: String)] = []
            var imeiDocsToDelete: [DocumentReference] = []
            
            // Step 1: Find all phone and IMEI documents to delete
            for phoneItem in cartItems {
                print("📱 Processing: \(phoneItem.brand) \(phoneItem.model)")
                
                // Get brand document
                print("🔍 Searching for brand: \(phoneItem.brand)")
                let brandQuery = db.collection("PhoneBrands").whereField("brand", isEqualTo: phoneItem.brand).limit(to: 1)
                let brandSnapshot = try await brandQuery.getDocuments()
                
                guard let brandDoc = brandSnapshot.documents.first else {
                    print("⚠️ Brand not found: \(phoneItem.brand)")
                    throw NSError(domain: "SalesConfirmation", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Brand not found: \(phoneItem.brand)"
                    ])
                }
                
                let brandDocId = brandDoc.documentID
                print("✅ Found brand document: \(brandDocId)")
                
                // Get model document
                print("🔍 Searching for model: \(phoneItem.model)")
                let modelQuery = db.collection("PhoneBrands")
                    .document(brandDocId)
                    .collection("Models")
                    .whereField("model", isEqualTo: phoneItem.model)
                    .limit(to: 1)
                
                let modelSnapshot = try await modelQuery.getDocuments()
                
                guard let modelDoc = modelSnapshot.documents.first else {
                    print("⚠️ Model not found: \(phoneItem.model)")
                    throw NSError(domain: "SalesConfirmation", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Model not found: \(phoneItem.model)"
                    ])
                }
                
                let modelDocId = modelDoc.documentID
                print("✅ Found model document: \(modelDocId)")
                
                // Find phones by IMEI
                for imei in phoneItem.imeis {
                    print("🔍 Searching for phone with IMEI: \(imei)")
                    
                    let phoneQuery = db.collection("PhoneBrands")
                        .document(brandDocId)
                        .collection("Models")
                        .document(modelDocId)
                        .collection("Phones")
                        .whereField("imei", isEqualTo: imei)
                        .limit(to: 1)
                    
                    let phoneSnapshot = try await phoneQuery.getDocuments()
                    
                    if let phoneDoc = phoneSnapshot.documents.first {
                        print("✅ Found phone document: \(phoneDoc.documentID) for IMEI: \(imei)")
                        phonesToDelete.append((phoneRef: phoneDoc.reference, imei: imei))
                        
                        // Find corresponding IMEI document
                        let imeiQuery = db.collection("IMEI").whereField("imei", isEqualTo: imei).limit(to: 1)
                        let imeiSnapshot = try await imeiQuery.getDocuments()
                        
                        if let imeiDoc = imeiSnapshot.documents.first {
                            print("✅ Found IMEI document: \(imeiDoc.documentID) for IMEI: \(imei)")
                            imeiDocsToDelete.append(imeiDoc.reference)
                        } else {
                            print("⚠️ IMEI document not found for IMEI: \(imei)")
                        }
                    } else {
                        print("⚠️ Phone document not found for IMEI: \(imei)")
                        throw NSError(domain: "SalesConfirmation", code: 3, userInfo: [
                            NSLocalizedDescriptionKey: "Phone not found with IMEI: \(imei)"
                        ])
                    }
                }
            }
            
            print("✅ Found \(phonesToDelete.count) phones and \(imeiDocsToDelete.count) IMEIs to delete")
            
            // Step 2: Get customer reference
            print("👤 Getting customer reference...")
            var customerDocRef: DocumentReference?
            var customerCollectionName: String?
            
            if let customer = selectedCustomer {
                print("👤 Processing customer: \(customer.name)")
                
                // Determine collection based on entity type
                let collectionName: String
                switch customer.entityType {
                case .customer:
                    collectionName = "Customers"
                case .supplier:
                    collectionName = "Suppliers"
                case .middleman:
                    collectionName = "Middlemen"
                }
                
                customerCollectionName = collectionName
                
                let customerQuery = db.collection(collectionName).whereField("name", isEqualTo: customer.name).limit(to: 1)
                let customerSnapshot = try await customerQuery.getDocuments()
                
                if let customerDoc = customerSnapshot.documents.first {
                    print("✅ Found customer document: \(customerDoc.documentID)")
                    customerDocRef = customerDoc.reference
                } else {
                    throw NSError(domain: "SalesConfirmation", code: 4, userInfo: [
                        NSLocalizedDescriptionKey: "Customer not found: \(customer.name)"
                    ])
                }
            } else {
                throw NSError(domain: "SalesConfirmation", code: 5, userInfo: [
                    NSLocalizedDescriptionKey: "Customer is required"
                ])
            }
            
            // Step 3: Get middleman reference
            print("🤝 Getting middleman reference...")
            var middlemanDocRef: DocumentReference?
            var middlemanCollectionName: String?
            
            if useMiddlemanPayment, let middleman = selectedMiddleman {
                print("🤝 Processing middleman: \(middleman.name)")
                
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
                
                let middlemanQuery = db.collection(collectionName).whereField("name", isEqualTo: middleman.name).limit(to: 1)
                let middlemanSnapshot = try await middlemanQuery.getDocuments()
                
                if let middlemanDoc = middlemanSnapshot.documents.first {
                    print("✅ Found middleman document: \(middlemanDoc.documentID)")
                    middlemanDocRef = middlemanDoc.reference
                } else {
                    throw NSError(domain: "SalesConfirmation", code: 6, userInfo: [
                        NSLocalizedDescriptionKey: "Middleman not found: \(middleman.name)"
                    ])
                }
            }
            
            // Step 4: Create document references
            let salesDocRef = db.collection("Sales").document()
            let orderNumberDocRef = db.collection("OrderNumbers").document()
            
            // Step 5: Prepare data
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
                    finalCash -= middlemanCashAmountValue
                    finalBank -= middlemanBankAmountValue
                    finalCard -= middlemanCreditCardAmountValue
                    print("   Mode: Give - Adding middleman amounts to final totals")
                } else {
                    finalCash += middlemanCashAmountValue
                    finalBank += middlemanBankAmountValue
                    finalCard += middlemanCreditCardAmountValue
                    print("   Mode: Receive - Subtracting middleman amounts from final totals")
                }
            }
            
            print("💵 Final Amounts After Middleman Adjustments:")
            print("   Final Cash: $\(finalCash)")
            print("   Final Bank: $\(finalBank)")
            print("   Final Card: $\(finalCard)")
            
            // Prepare sold phones data
            var soldPhones: [[String: Any]] = []
            for phoneItem in cartItems {
                for imei in phoneItem.imeis {
                    var phoneDetail: [String: Any] = [
                        "brand": phoneItem.brand,
                        "model": phoneItem.model,
                        "capacity": phoneItem.capacity,
                        "capacityUnit": phoneItem.capacityUnit,
                        "imei": imei,
                        "unitCost": phoneItem.unitCost, // This is the selling price
                        "status": phoneItem.status,
                        "storageLocation": phoneItem.storageLocation
                    ]
                    
                    // Add actual cost (purchase price) if available
                    if let actualCost = phoneItem.actualCost {
                        phoneDetail["actualCost"] = actualCost
                        print("   ✅ Added actualCost: $\(actualCost) for phone \(phoneItem.brand) \(phoneItem.model)")
                    } else {
                        print("   ⚠️ actualCost is nil for phone \(phoneItem.brand) \(phoneItem.model) - unitCost: $\(phoneItem.unitCost)")
                    }
                    
                    if !phoneItem.carrier.isEmpty {
                        phoneDetail["carrier"] = phoneItem.carrier
                    }
                    if !phoneItem.color.isEmpty {
                        phoneDetail["color"] = phoneItem.color
                    }
                    
                    soldPhones.append(phoneDetail)
                }
            }
            
            // Prepare services data
            var services: [[String: Any]] = []
            for serviceItem in serviceItems {
                services.append([
                    "name": serviceItem.name,
                    "price": serviceItem.price
                ])
            }
            
            // Extract order number
            let orderNumberValue = orderNumber.replacingOccurrences(of: "ORD-", with: "")
            let orderNumberInt = Int(orderNumberValue) ?? 1
            
            // Prepare sales document data
            var salesData: [String: Any] = [
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
                "soldPhones": soldPhones,
                "services": services,
                "paymentMethods": [
                    "cash": totalCashPaid,
                    "bank": totalBankPaid,
                    "creditCard": totalCreditCardPaid,
                    "totalPaid": totalPaid,
                    "remainingCredit": remainingCredit
                ]
            ]
            
            // Add middleman payment details if applicable
            if let middlemanDocRef = middlemanDocRef, let middleman = selectedMiddleman, useMiddlemanPayment {
                print("🤝 Adding middleman details to sales document")
                salesData["middleman"] = middlemanDocRef
                salesData["middlemanName"] = middleman.name
                salesData["middlemanEntityType"] = middleman.entityType.rawValue
                salesData["middlemanPayment"] = [
                    "amount": middlemanPaymentAmountValue,
                    "unit": middlemanUnit,
                    "paymentSplit": [
                        "cash": middlemanCashAmountValue,
                        "bank": middlemanBankAmountValue,
                        "creditCard": middlemanCreditCardAmountValue,
                        "credit": middlemanCreditAmount
                    ]
                ]
            }
            
            // Add customer details
            if let customerDocRef = customerDocRef, let customer = selectedCustomer {
                print("👤 Adding customer details to sales document")
                salesData["customer"] = customerDocRef
                salesData["customerName"] = customer.name
                salesData["customerEntityType"] = customer.entityType.rawValue
            }
            
            // Prepare order number document data
            let orderNumberData: [String: Any] = [
                "orderNumber": orderNumberInt,
                "isCustom": isOrderNumberCustom,
                "salesReference": salesDocRef,
                "createdAt": selectedDate,
                "transactionDate": selectedDate
            ]
            
            // IMPORTANT: Pre-fetch the documents needed for the transaction
            print("🔍 Pre-fetching documents for transaction...")
            
            // Pre-fetch customer document
            let customerDoc = try await customerDocRef?.getDocument()
            if customerDoc == nil || !customerDoc!.exists {
                throw NSError(domain: "SalesConfirmation", code: 12, userInfo: [
                    NSLocalizedDescriptionKey: "Cannot fetch customer document before transaction"
                ])
            }
            print("✅ Successfully pre-fetched customer document")
            
            // Pre-fetch middleman document if applicable
            var middlemanData: [String: Any]?
            var middlemanCurrentBalance: Double = 0.0
            
            if let middlemanDocRef = middlemanDocRef, useMiddlemanPayment {
                let middlemanDoc = try await middlemanDocRef.getDocument()
                if !middlemanDoc.exists {
                    throw NSError(domain: "SalesConfirmation", code: 13, userInfo: [
                        NSLocalizedDescriptionKey: "Cannot fetch middleman document before transaction"
                    ])
                }
                middlemanData = middlemanDoc.data()
                middlemanCurrentBalance = middlemanData?["balance"] as? Double ??
                                        middlemanData?["Balance"] as? Double ??
                                        middlemanData?["accountBalance"] as? Double ??
                                        middlemanData?["AccountBalance"] as? Double ?? 0.0
                print("✅ Successfully pre-fetched middleman document")
            }
            
            // Pre-fetch balance documents
            let cashDocRef = db.collection("Balances").document("cash")
            let bankDocRef = db.collection("Balances").document("bank")
            let creditCardDocRef = db.collection("Balances").document("creditCard")
            
            let cashDoc = try await cashDocRef.getDocument()
            let bankDoc = try await bankDocRef.getDocument()
            let creditCardDoc = try await creditCardDocRef.getDocument()
            
            if !cashDoc.exists || !bankDoc.exists || !creditCardDoc.exists {
                throw NSError(domain: "SalesConfirmation", code: 14, userInfo: [
                    NSLocalizedDescriptionKey: "One or more balance documents don't exist"
                ])
            }
            print("✅ Successfully pre-fetched balance documents")
            
            // Store customer data to use in transaction
            let customerData = customerDoc!.data() ?? [:]
            let customerCurrentBalance = customerData["balance"] as? Double ??
                                       customerData["Balance"] as? Double ??
                                       customerData["accountBalance"] as? Double ??
                                       customerData["AccountBalance"] as? Double ?? 0.0
            
            // Store balance data
            let currentCashBalance = cashDoc.data()?["amount"] as? Double ?? 0.0
            let currentBankBalance = bankDoc.data()?["amount"] as? Double ?? 0.0
            let currentCreditCardBalance = creditCardDoc.data()?["amount"] as? Double ?? 0.0
            
            // PHASE 2: Run Firestore transaction
            print("🚀 PHASE 2: Running Firestore transaction...")
            
            try await db.runTransaction { transaction, errorPointer in
                // Step 1: Delete phone documents
                for (phoneRef, imei) in phonesToDelete {
                    print("🗑️ Deleting phone document in transaction: \(phoneRef.documentID) for IMEI: \(imei)")
                    transaction.deleteDocument(phoneRef)
                }
                
                // Step 2: Delete IMEI documents
                for imeiDocRef in imeiDocsToDelete {
                    print("🗑️ Deleting IMEI document in transaction: \(imeiDocRef.documentID)")
                    transaction.deleteDocument(imeiDocRef)
                }
                
                // Step 3: Create sales document
                print("💾 Creating sales document in transaction: \(salesDocRef.documentID)")
                transaction.setData(salesData, forDocument: salesDocRef)
                
                // Step 4: Create order number document
                print("💾 Creating order number document in transaction: \(orderNumberDocRef.documentID)")
                transaction.setData(orderNumberData, forDocument: orderNumberDocRef)
                
                // Step 5: Update customer document using pre-fetched data
                if let customerDocRef = customerDocRef {
                    print("👤 Updating customer document in transaction: \(customerDocRef.documentID)")
                    
                    // Handle transaction history using pre-fetched data
                    var transactionHistory: [[String: Any]] = customerData["transactionHistory"] as? [[String: Any]] ?? []
                    transactionHistory.append([
                        "salesReference": salesDocRef,
                        "timestamp": selectedDate,
                        "role": "customer"
                    ])
                    
                    // Handle balance update using pre-fetched data
                    let newBalance = customerCurrentBalance + abs(remainingCredit) // ADD (customer owes us)
                    
                    print("💰 Customer balance update:")
                    print("   Current balance: $\(customerCurrentBalance)")
                    print("   Remaining credit: $\(remainingCredit)")
                    print("   New balance: $\(newBalance)")
                    
                    transaction.updateData([
                        "transactionHistory": transactionHistory,
                        "balance": newBalance
                    ], forDocument: customerDocRef)
                }
                
                // Step 6: Update middleman document using pre-fetched data
                if let middlemanDocRef = middlemanDocRef, useMiddlemanPayment, let middlemanData = middlemanData {
                    print("🤝 Updating middleman document in transaction: \(middlemanDocRef.documentID)")
                    
                    // Handle transaction history using pre-fetched data
                    var transactionHistory: [[String: Any]] = middlemanData["transactionHistory"] as? [[String: Any]] ?? []
                    transactionHistory.append([
                        "salesReference": salesDocRef,
                        "timestamp": selectedDate,
                        "role": "middleman"
                    ])
                    
                    // Handle balance update using pre-fetched data
                    let newBalance: Double
                    if middlemanUnit == "give" {
                        newBalance = middlemanCurrentBalance - middlemanCreditAmount
                    } else {
                        newBalance = middlemanCurrentBalance + middlemanCreditAmount
                    }
                    
                    print("💰 Middleman balance update:")
                    print("   Current balance: $\(middlemanCurrentBalance)")
                    print("   Unit: \(middlemanUnit)")
                    print("   Credit amount: $\(middlemanCreditAmount)")
                    print("   New balance: $\(newBalance)")
                    
                    transaction.updateData([
                        "transactionHistory": transactionHistory,
                        "balance": newBalance
                    ], forDocument: middlemanDocRef)
                }
                
                // Step 7: Update Balances collection using pre-fetched data
                print("💳 Updating Balances collection in transaction:")
                
                // Calculate new balances
                let newCashBalance = currentCashBalance + finalCash
                let newBankBalance = currentBankBalance + finalBank
                let newCreditCardBalance = currentCreditCardBalance + finalCard
                
                // Update cash balance
                print("   Cash: $\(currentCashBalance) → $\(newCashBalance)")
                transaction.updateData([
                    "amount": newCashBalance,
                    "updatedAt": selectedDate
                ], forDocument: cashDocRef)
                
                // Update bank balance
                print("   Bank: $\(currentBankBalance) → $\(newBankBalance)")
                transaction.updateData([
                    "amount": newBankBalance,
                    "updatedAt": selectedDate
                ], forDocument: bankDocRef)
                
                // Update credit card balance
                print("   Credit Card: $\(currentCreditCardBalance) → $\(newCreditCardBalance)")
                transaction.updateData([
                    "amount": newCreditCardBalance,
                    "updatedAt": selectedDate
                ], forDocument: creditCardDocRef)
                
                print("✅ Transaction operations complete, ready to commit")
                return nil
            }
            
            print("✅ Transaction committed successfully!")
            
            // PHASE 3: Update UI after successful transaction
            await MainActor.run {
                print("🧹 Clearing cart and form data...")
                cartItems.removeAll()
                serviceItems.removeAll()
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
                isConfirmingPayment = false
                showPaymentSuccess = true
                print("🎉 Sales payment confirmation completed successfully!")
                
                // Navigate to bill screen
                print("📱 Navigating to bill screen with sales ID: \(salesDocRef.documentID)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onPaymentConfirmed(salesDocRef.documentID)
                }
            }
            
        } catch {
            print("❌ ERROR in sales confirmPayment: \(error)")
            print("📊 Error details: \(error.localizedDescription)")
            
            // Update UI to show error
            await MainActor.run {
                isConfirmingPayment = false
                validationAlertMessage = "Transaction failed: \(error.localizedDescription)"
                showValidationAlert = true
                print("🚫 Sales payment confirmation failed with error: \(error.localizedDescription)")
            }
        }
    }
}

                #Preview {
                    SalesView(
                        showingCustomerDropdown: .constant(false),
                        selectedCustomer: .constant(nil),
                        customerButtonFrame: .constant(.zero),
                        allEntities: .constant([]),
                        customerSearchText: .constant(""),
                        entityFetchError: .constant(false),
                        retryFetchEntities: .constant({}),
                        onPaymentConfirmed: { _ in }
                    )
                }
