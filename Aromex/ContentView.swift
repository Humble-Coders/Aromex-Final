//
//  ContentView.swift
//  Aromex
//
//  Created by Ansh Bajaj on 29/08/25.
// check check 2

import SwiftUI
import FirebaseFirestore

struct ContentView: View {
    @State private var selectedMenuItem = "Home"
    @State private var showingSidebar = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // iPad dialog state
    @State private var ipadEditingField: AccountBalanceCard.BalanceField? = nil
    @State private var ipadIsUpdating = false
    @State private var ipadEditValue: String = ""
    @StateObject private var balanceViewModel = BalanceViewModel()
    
    // Customer dialog state
    @State private var showingAddCustomerDialog = false
    @FocusState private var isIPadFieldFocused: Bool
    
    // Delete entity state
    @State private var isDeletingEntity = false
    @State private var showDeleteEntitySuccess = false
    
    // Purchase screen supplier dropdown state
    @State private var showingSupplierDropdown = false
    @State private var selectedSupplier: EntityWithType? = nil
    @State private var supplierButtonFrame: CGRect = .zero
    @State private var allEntities: [EntityWithType] = []
    @State private var supplierSearchText: String = ""
    @State private var entityFetchError = false
    @State private var retryFetchEntities: (() -> Void) = {}
    
    // Scanner state
    @State private var showingScanner = false
    
    // Bill screen state
    @State private var showingBillScreen = false
    @State private var billPurchaseId: String = ""
    
    var isIPad: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    var deleteEntityOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea(.all)
            
            if showDeleteEntitySuccess {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Text("Entity Deleted Successfully!")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Deleting Entity...")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    var body: some View {
        ZStack {
            Group {
                if horizontalSizeClass == .compact && verticalSizeClass == .regular {
                    // iPhone Portrait Mode
                    iPhonePortraitView
                } else {
                    // macOS, iPad, iPhone Landscape
                    desktopView
                }
            }
            
            // iPad compact dialog overlay at highest level
            if isIPad && ipadEditingField != nil {
                iPadCompactDialog
            }
            
            // Delete entity overlay at highest level
            if isDeletingEntity {
                deleteEntityOverlay
            }
            
            // Supplier dropdown overlay at highest level
            if showingSupplierDropdown {
                SupplierDropdownOverlay(
                    isOpen: $showingSupplierDropdown,
                    selectedSupplier: $selectedSupplier,
                    entities: allEntities,
                    buttonFrame: supplierButtonFrame,
                    searchText: supplierSearchText,
                    entityFetchError: entityFetchError,
                    onRetry: retryFetchEntities
                )
            }
        }
        .sheet(isPresented: $showingAddCustomerDialog) {
            AddCustomerDialog(
                isPresented: $showingAddCustomerDialog
            )
        }
        .onChange(of: showingBillScreen) { isShowing in
            if isShowing {
                selectedMenuItem = "Bill"
            }
        }
    }
    
    var iPadCompactDialog: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    ipadEditingField = nil
                }
            
            // Compact dialog
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Edit \(ipadEditingField?.fieldTitle ?? "")")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        ipadEditingField = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Current value
                Text("Current: \(formatCurrency(getCurrentBalance()))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Input field
                TextField("Enter amount", text: $ipadEditValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 16, weight: .medium))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .focused($isIPadFieldFocused)
                    #endif
                    .onChange(of: ipadEditValue) { newValue in
                        if ipadEditingField == .creditCard {
                            // For credit card, add negative sign only if value is not 0 or empty
                            if !newValue.isEmpty {
                                let numericValue = Double(newValue) ?? 0
                                if numericValue != 0 && !newValue.hasPrefix("-") {
                                    ipadEditValue = "-" + newValue
                                } else if numericValue == 0 && newValue.hasPrefix("-") {
                                    // Remove negative sign if value is 0
                                    ipadEditValue = String(newValue.dropFirst())
                                }
                            }
                        }
                    }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        ipadEditingField = nil
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                    
                    Button(action: {
                        Task {
                            await saveIPadBalance()
                        }
                    }) {
                        HStack {
                            if ipadIsUpdating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(ipadIsUpdating ? "Saving..." : "Save")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .disabled(ipadIsUpdating || ipadEditValue.isEmpty)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        (ipadIsUpdating || ipadEditValue.isEmpty) ? 
                        Color.gray : 
                        Color(red: 0.25, green: 0.33, blue: 0.54)
                    )
                    .cornerRadius(8)
                }
            }
            .padding(20)
            .background(.background)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            .frame(maxWidth: 400)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .overlay(
            // Full-screen buffer overlay during save
            Group {
                if ipadIsUpdating {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Updating...")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .medium))
                            }
                        )
                }
            }
        )
        .onAppear {
            ipadEditValue = getCurrentBalanceString()
            #if os(iOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isIPadFieldFocused = true
            }
            #endif
        }
    }
    
    private func saveIPadBalance() async {
        guard let field = ipadEditingField,
              let doubleValue = Double(ipadEditValue) else { return }
        
        ipadIsUpdating = true
        
        let documentName: String
        switch field {
        case .bank: documentName = "bank"
        case .cash: documentName = "cash"
        case .creditCard: documentName = "creditCard"
        }
        
        do {
            try await balanceViewModel.updateBalance(documentName: documentName, amount: doubleValue)
            ipadEditingField = nil
        } catch {
            print("Error updating balance: \(error)")
        }
        
        ipadIsUpdating = false
    }
    
    private func getCurrentBalance() -> Double {
        guard let field = ipadEditingField else { return 0 }
        switch field {
        case .bank: return balanceViewModel.bankBalance
        case .cash: return balanceViewModel.cashBalance
        case .creditCard: return balanceViewModel.creditCardBalance
        }
    }
    
    private func getCurrentBalanceString() -> String {
        return String(getCurrentBalance())
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    var desktopView: some View {
        NavigationSplitView {
            SidebarView(selectedMenuItem: $selectedMenuItem)
        } detail: {
            if selectedMenuItem == "Bill" {
                BillScreen(purchaseId: billPurchaseId, onClose: { 
                    // Return to Purchase and ensure bill screen is dismissed
                    selectedMenuItem = "Purchase"
                    showingBillScreen = false
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MainContentView(
                    selectedMenuItem: $selectedMenuItem,
                    ipadEditingField: $ipadEditingField,
                    ipadIsUpdating: $ipadIsUpdating,
                    balanceViewModel: balanceViewModel,
                    showingAddCustomerDialog: $showingAddCustomerDialog,
                    isDeletingEntity: $isDeletingEntity,
                    showDeleteEntitySuccess: $showDeleteEntitySuccess,
                    showingSupplierDropdown: $showingSupplierDropdown,
                    selectedSupplier: $selectedSupplier,
                    supplierButtonFrame: $supplierButtonFrame,
                    allEntities: $allEntities,
                    supplierSearchText: $supplierSearchText,
                    entityFetchError: $entityFetchError,
                    retryFetchEntities: $retryFetchEntities,
                    showingScanner: $showingScanner,
                    showingBillScreen: $showingBillScreen,
                    billPurchaseId: $billPurchaseId
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    var iPhonePortraitView: some View {
        #if os(iOS)
        NavigationStack {
            MainContentView(
                selectedMenuItem: $selectedMenuItem,
                ipadEditingField: $ipadEditingField,
                ipadIsUpdating: $ipadIsUpdating,
                balanceViewModel: balanceViewModel,
                showingAddCustomerDialog: $showingAddCustomerDialog,
                isDeletingEntity: $isDeletingEntity,
                showDeleteEntitySuccess: $showDeleteEntitySuccess,
                showingSupplierDropdown: $showingSupplierDropdown,
                selectedSupplier: $selectedSupplier,
                supplierButtonFrame: $supplierButtonFrame,
                allEntities: $allEntities,
                supplierSearchText: $supplierSearchText,
                entityFetchError: $entityFetchError,
                retryFetchEntities: $retryFetchEntities,
                showingScanner: $showingScanner,
                showingBillScreen: $showingBillScreen,
                billPurchaseId: $billPurchaseId
            )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if selectedMenuItem != "Bill" && !showingBillScreen {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                showingSidebar = true
                            }) {
                                Image(systemName: "line.horizontal.3")
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {}) {
                                Image(systemName: "person.circle")
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingSidebar) {
                    MobileSidebarView(selectedMenuItem: $selectedMenuItem, isPresented: $showingSidebar)
                }
        }
        #else
        // This should never be reached on macOS due to size class check, but fallback to desktop view
        desktopView
        #endif
    }
}

struct SidebarView: View {
    @Binding var selectedMenuItem: String
    
    var menuItems: [(String, String)] {
        var items: [(String, String)] = [
            ("Home", "house"),
            ("Purchase", "cart"),
            ("Sales", "chart.line.uptrend.xyaxis"),
            ("Profiles", "person.3"),
            ("Inventory", "archivebox")
        ]
        
        #if os(iOS)
        items.append(("Scanner", "camera"))
        #endif
        
        items.append(("Statistics", "chart.bar"))
        return items
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("AROMEX")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 30)
            
            // Menu Items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(menuItems, id: \.0) { item in
                    MenuItemView(
                        title: item.0,
                        icon: item.1,
                        isSelected: selectedMenuItem == item.0
                    ) {
                        selectedMenuItem = item.0
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .frame(minWidth: 250)
        .background(Color(red: 0.25, green: 0.33, blue: 0.54)) // Dark blue color
    }
}

struct MenuItemView: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                
                Spacer()
                
                if title == "Statistics" {
                    Image(systemName: "lock")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MainContentView: View {
    @Binding var selectedMenuItem: String
    @Binding var ipadEditingField: AccountBalanceCard.BalanceField?
    @Binding var ipadIsUpdating: Bool
    @ObservedObject var balanceViewModel: BalanceViewModel
    @Binding var showingAddCustomerDialog: Bool
    @Binding var isDeletingEntity: Bool
    @Binding var showDeleteEntitySuccess: Bool
    @Binding var showingSupplierDropdown: Bool
    @Binding var selectedSupplier: EntityWithType?
    @Binding var supplierButtonFrame: CGRect
    @Binding var allEntities: [EntityWithType]
    @Binding var supplierSearchText: String
    @Binding var entityFetchError: Bool
    @Binding var retryFetchEntities: (() -> Void)
    @Binding var showingScanner: Bool
    @Binding var showingBillScreen: Bool
    @Binding var billPurchaseId: String
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar (only show for desktop/horizontal view)
//            if !(horizontalSizeClass == .compact && verticalSizeClass == .regular) {
//                HStack {
//                    Spacer()
//                    
//                    Text(selectedMenuItem)
//                        .font(.system(size: 16))
//                        .foregroundColor(.primary)
//                    
//                    Spacer()
//                    
//                    Button(action: {}) {
//                        Image(systemName: "person.circle")
//                            .font(.title2)
//                            .foregroundColor(.gray)
//                    }
//                }
//                .padding(.horizontal, 20)
//                .padding(.vertical, 15)
//                .background(.background)
//                .overlay(
//                    Rectangle()
//                        .frame(height: 0.5)
//                        .foregroundColor(Color.gray.opacity(0.3)),
//                    alignment: .bottom
//                )
//            }
            
            // Main Content Area
            Group {
                if selectedMenuItem == "Scanner" {
                    #if os(iOS)
                    ScannerView(onClose: { selectedMenuItem = "Home" })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                    #else
                    Text("Scanner is only available on iOS devices")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #endif
                } else if selectedMenuItem == "Bill" {
                    BillScreen(purchaseId: billPurchaseId, onClose: { 
                        // Return to Purchase and ensure bill screen is dismissed
                        selectedMenuItem = "Purchase"
                        showingBillScreen = false
                    })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea(.all)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 25) {
                            Spacer()
                            // Financial Overview Cards
                            if selectedMenuItem == "Home" {
                                FinancialOverviewView(
                                    ipadEditingField: $ipadEditingField,
                                    ipadIsUpdating: $ipadIsUpdating,
                                    balanceViewModel: balanceViewModel
                                )
                                
                                // Quick Actions Section
                                QuickActionsView(showingAddCustomerDialog: $showingAddCustomerDialog)
                            } else if selectedMenuItem == "Profiles" {
                                ProfilesView(
                                    isDeletingEntity: $isDeletingEntity,
                                    showDeleteEntitySuccess: $showDeleteEntitySuccess
                                )
                            } else if selectedMenuItem == "Purchase" {
                                PurchaseView(
                                    showingSupplierDropdown: $showingSupplierDropdown,
                                    selectedSupplier: $selectedSupplier,
                                    supplierButtonFrame: $supplierButtonFrame,
                                    allEntities: $allEntities,
                                    supplierSearchText: $supplierSearchText,
                                    entityFetchError: $entityFetchError,
                                    retryFetchEntities: $retryFetchEntities,
                                    onPaymentConfirmed: { purchaseId in
                                        print("📱 Received purchase ID in callback: \(purchaseId)")
                                        billPurchaseId = purchaseId
                                        showingBillScreen = true
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
                }
            }
        }
        .navigationTitle(selectedMenuItem)
    }
}

struct FinancialOverviewView: View {
    @Binding var ipadEditingField: AccountBalanceCard.BalanceField?
    @Binding var ipadIsUpdating: Bool
    @ObservedObject var balanceViewModel: BalanceViewModel
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section Title
            HStack {
                Text("Financial Overview")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 30)
            
            // Cards Layout
            if horizontalSizeClass == .compact && verticalSizeClass == .regular {
                // iPhone Portrait - Vertical stack
                VStack(spacing: 15) {
                    AccountBalanceCard(
                        balanceViewModel: balanceViewModel,
                        ipadEditingField: $ipadEditingField,
                        ipadIsUpdating: $ipadIsUpdating
                    )
                    DebtOverviewCard()
                }
                .padding(.horizontal, 20)
            } else {
                // macOS/iPad - Grid layout with equal heights
                HStack(alignment: .top, spacing: 20) {
                    AccountBalanceCard(
                        balanceViewModel: balanceViewModel,
                        ipadEditingField: $ipadEditingField,
                        ipadIsUpdating: $ipadIsUpdating
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    DebtOverviewCard()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 280) // Set a fixed height for the container
                .padding(.horizontal, 30)
            }
        }
    }
}

// Updated AccountBalanceCard with proper alignment
struct AccountBalanceCard: View {
    @ObservedObject var balanceViewModel: BalanceViewModel
    @Binding var ipadEditingField: BalanceField?
    @Binding var ipadIsUpdating: Bool
    @State private var editingField: BalanceField? = nil
    @State private var editValue: String = ""
    @State private var isUpdating = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    enum BalanceField: Identifiable {
        case bank, cash, creditCard
        
        var id: String {
            switch self {
            case .bank: return "bank"
            case .cash: return "cash"
            case .creditCard: return "creditCard"
            }
        }
        
        var fieldTitle: String {
            switch self {
            case .bank: return "Bank Balance"
            case .cash: return "Cash"
            case .creditCard: return "Credit Card"
            }
        }
    }
    
    var isIPad: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    

    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header - Fixed at top
            HStack {
                Text("Account Balances")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "creditcard")
                    .font(.title2)
                    .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
            }
            .padding(.bottom, 20)
            
                            // Balance Items - Expandable middle section
                VStack(spacing: 15) {
                    EditableBalanceItemView(
                        title: "Bank Balance",
                        amount: balanceViewModel.formatAmount(balanceViewModel.bankBalance),
                        icon: "building.columns",
                        color: balanceViewModel.getBalanceColor(balanceViewModel.bankBalance),
                        onEdit: {
                            if isIPad {
                                ipadEditingField = .bank
                            } else {
                                editingField = .bank
                            }
                        }
                    )
                    
                    EditableBalanceItemView(
                        title: "Cash",
                        amount: balanceViewModel.formatAmount(balanceViewModel.cashBalance),
                        icon: "banknote",
                        color: balanceViewModel.getBalanceColor(balanceViewModel.cashBalance),
                        onEdit: {
                            if isIPad {
                                ipadEditingField = .cash
                            } else {
                                editingField = .cash
                            }
                        }
                    )
                    
                    EditableBalanceItemView(
                        title: "Credit Card",
                        amount: balanceViewModel.formatAmount(balanceViewModel.creditCardBalance),
                        icon: "creditcard",
                        color: balanceViewModel.getBalanceColor(balanceViewModel.creditCardBalance),
                        onEdit: {
                            if isIPad {
                                ipadEditingField = .creditCard
                            } else {
                                editingField = .creditCard
                            }
                        }
                    )
                }
            
            // This Spacer pushes content to top and fills remaining space
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top) // Key: alignment to top
        .background(.background)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .overlay(
            // Loading overlay when updating
            Group {
                if isUpdating {
                    Color.black.opacity(0.3)
                        .overlay(
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Updating...")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .medium))
                            }
                        )
                        .cornerRadius(12)
                }
            }
        )
        .sheet(item: $editingField) { field in
            EditBalanceDialog(
                field: field,
                currentValue: {
                    switch field {
                    case .bank:
                        return String(balanceViewModel.bankBalance)
                    case .cash:
                        return String(balanceViewModel.cashBalance)
                    case .creditCard:
                        return String(balanceViewModel.creditCardBalance)
                    }
                }(),
                isUpdating: $isUpdating,
                onSave: { newValue in
                    Task {
                        await updateBalance(field: field, value: newValue)
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }
    
    private func updateBalance(field: BalanceField, value: String) async {
        guard let doubleValue = Double(value) else { return }
        
        isUpdating = true
        
        let documentName: String
        switch field {
        case .bank:
            documentName = "bank"
        case .cash:
            documentName = "cash"
        case .creditCard:
            documentName = "creditCard"
        }
        
        do {
            try await balanceViewModel.updateBalance(documentName: documentName, amount: doubleValue)
            editingField = nil
        } catch {
            print("Error updating balance: \(error)")
        }
        
        isUpdating = false
    }
}

// Updated DebtOverviewCard with proper alignment
struct DebtOverviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header - Fixed at top
            HStack {
                Text("Debt Overview")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
            }
            .padding(.bottom, 20)
            
            // Debt Items - Expandable middle section
            VStack(spacing: 15) {
                DebtItemView(
                    title: "Total Owed",
                    amount: "$45,300.00",
                    icon: "arrow.up.circle",
                    color: .red
                )
                
                DebtItemView(
                    title: "Total Due to Me",
                    amount: "$67,850.00",
                    icon: "arrow.down.circle",
                    color: .green
                )
            }
            
            // This Spacer pushes content to top and fills remaining space
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top) // Key: alignment to top
        .background(.background)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

struct BalanceItemView: View {
    let title: String
    let amount: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text(amount)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DebtItemView: View {
    let title: String
    let amount: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 25)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                Text(amount)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(maxHeight: .infinity, alignment: .center) // Key: alignment to top
            
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 15)
        .background(color.opacity(0.1))
        .cornerRadius(10)
        .frame(maxHeight: .infinity, alignment: .center) // Key: alignment to top
        
    }
}

#if os(iOS)
struct MobileSidebarView: View {
    @Binding var selectedMenuItem: String
    @Binding var isPresented: Bool
    
    let menuItems = [
        ("Home", "house"),
        ("Purchase", "cart"),
        ("Sales", "chart.line.uptrend.xyaxis"),
        ("Profiles", "person.3"),
        ("Inventory", "archivebox"),
        ("Scanner", "camera"),
        ("Statistics", "chart.bar")
    ]
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    Text("AROMEX")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.25, green: 0.33, blue: 0.54))
                
                // Menu Items
                VStack(spacing: 0) {
                    ForEach(menuItems, id: \.0) { item in
                        MobileMenuItemView(
                            title: item.0,
                            icon: item.1,
                            isSelected: selectedMenuItem == item.0
                        ) {
                            selectedMenuItem = item.0
                            isPresented = false
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
#endif

#if os(iOS)
struct MobileMenuItemView: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? Color(red: 0.25, green: 0.33, blue: 0.54) : .primary)
                    .frame(width: 25)
                
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? Color(red: 0.25, green: 0.33, blue: 0.54) : .primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                }
                
                if title == "Statistics" {
                    Image(systemName: "lock")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(isSelected ? Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
#endif

#Preview {
    ContentView()
}

// MARK: - Balance ViewModel
class BalanceViewModel: ObservableObject {
    @Published var bankBalance: Double = 0.0
    @Published var cashBalance: Double = 0.0
    @Published var creditCardBalance: Double = 0.0
    
    private var db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    
    init() {
        setupListeners()
    }
    
    deinit {
        removeListeners()
    }
    
    private func setupListeners() {

        
        // Bank Balance Listener
        let bankListener = db.collection("Balances").document("bank")
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error listening to bank balance: \(error)")
                    return
                }
                
                if let document = documentSnapshot, document.exists {
                    let data = document.data()
                    if let amount = data?["amount"] {
                        if let doubleAmount = amount as? Double {
                            self.bankBalance = doubleAmount
                        } else if let intAmount = amount as? Int {
                            self.bankBalance = Double(intAmount)
                        } else {
                            self.bankBalance = 0.0
                        }
                    } else {
                        self.bankBalance = 0.0
                    }
                } else {
                    self.bankBalance = 0.0
                }
            }
        listeners.append(bankListener)
        
        // Cash Balance Listener
        let cashListener = db.collection("Balances").document("cash")
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error listening to cash balance: \(error)")
                    return
                }
                
                if let document = documentSnapshot, document.exists {
                    let data = document.data()
                    if let amount = data?["amount"] {
                        if let doubleAmount = amount as? Double {
                            self.cashBalance = doubleAmount
                        } else if let intAmount = amount as? Int {
                            self.cashBalance = Double(intAmount)
                        } else {
                            self.cashBalance = 0.0
                        }
                    } else {
                        self.cashBalance = 0.0
                    }
                } else {
                    self.cashBalance = 0.0
                }
            }
        listeners.append(cashListener)
        
        // Credit Card Balance Listener
        let creditCardListener = db.collection("Balances").document("creditCard")
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error listening to credit card balance: \(error)")
                    return
                }
                
                if let document = documentSnapshot, document.exists {
                    let data = document.data()
                    if let amount = data?["amount"] {
                        if let doubleAmount = amount as? Double {
                            self.creditCardBalance = doubleAmount
                        } else if let intAmount = amount as? Int {
                            self.creditCardBalance = Double(intAmount)
                        } else {
                            self.creditCardBalance = 0.0
                        }
                    } else {
                        self.creditCardBalance = 0.0
                    }
                } else {
                    self.creditCardBalance = 0.0
                }
            }
        listeners.append(creditCardListener)
        

    }
    
    private func removeListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    func getBalanceColor(_ amount: Double) -> Color {
        return amount >= 0 ? Color.green : Color.red
    }
    
    func updateBalance(documentName: String, amount: Double) async throws {
        let db = Firestore.firestore()
        try await db.collection("Balances").document(documentName).setData([
            "amount": amount
        ], merge: true)
    }
}

// MARK: - Editable Balance Item View
struct EditableBalanceItemView: View {
    let title: String
    let amount: String
    let icon: String
    let color: Color
    let onEdit: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text(amount)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Edit Balance Dialog
struct EditBalanceDialog: View {
    let field: AccountBalanceCard.BalanceField
    let currentValue: String
    @Binding var isUpdating: Bool
    let onSave: (String) -> Void
    
    @State private var editValue: String = ""
    @FocusState private var isFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var fieldTitle: String {
        switch field {
        case .bank:
            return "Bank Balance"
        case .cash:
            return "Cash"
        case .creditCard:
            return "Credit Card"
        }
    }
    
    var isCompact: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    var body: some View {
        Group {
            if isCompact {
                // iPhone Portrait - Full screen sheet
                iPhoneDialogView
            } else {
                // macOS/iPad - Centered dialog
                DesktopDialogView
            }
        }
        .onAppear {
            editValue = currentValue
            #if os(iOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFieldFocused = true
            }
            #endif
        }
    }
    
    var iPhoneDialogView: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header Section
                VStack(spacing: 20) {
                    // Icon and title
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.15))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "pencil")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit \(fieldTitle)")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text("Update your financial information")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Current value display
                    VStack(spacing: 12) {
                        Text("Current Amount")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Text(formatCurrency(Double(currentValue) ?? 0))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.08))
                                    .stroke(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.2), lineWidth: 2)
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
                
                // Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                
                // Input Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("New Amount")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                    
                    TextField("0.00", text: $editValue)
                        .textFieldStyle(PlainTextFieldStyle())
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        .focused($isFieldFocused)
                        #endif
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .onChange(of: editValue) { newValue in
                            if field == .creditCard {
                                // For credit card, add negative sign only if value is not 0 or empty
                                if !newValue.isEmpty {
                                    let numericValue = Double(newValue) ?? 0
                                    if numericValue != 0 && !newValue.hasPrefix("-") {
                                        editValue = "-" + newValue
                                    } else if numericValue == 0 && newValue.hasPrefix("-") {
                                        // Remove negative sign if value is 0
                                        editValue = String(newValue.dropFirst())
                                    }
                                }
                            }
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                    
                    Text("Enter the new amount for this account")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                Spacer()
                
                // Action Buttons Section
                VStack(spacing: 16) {
                    // Save Button
                    Button(action: {
                        onSave(editValue)
                    }) {
                        HStack(spacing: 10) {
                            if isUpdating {
                                ProgressView()
                                    .scaleEffect(0.9)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            
                            Text(isUpdating ? "Saving..." : "Save Changes")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
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
                    .disabled(isUpdating || editValue.isEmpty)
                    .opacity((isUpdating || editValue.isEmpty) ? 0.6 : 1.0)
                    
                    // Cancel Button
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(.background))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isUpdating)
                    .opacity(isUpdating ? 0.6 : 1.0)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 34)
            }
            .background(.background)
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
        }
    }
    
    var DesktopDialogView: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack(spacing: 16) {
                // Icon with subtle background
                ZStack {
                    Circle()
                        .fill(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit \(fieldTitle)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Update your financial information")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    dismiss()
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
            
            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 36)
            
            // Content area
            VStack(spacing: 36) {
                // Current value display
                VStack(spacing: 20) {
                    HStack {
                        Text("Current Amount")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    HStack {
                        Text(formatCurrency(Double(currentValue) ?? 0))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .minimumScaleFactor(0.8)
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.08))
                            .stroke(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.2), lineWidth: 2)
                    )
                }
                .padding(.top, 28)
                
                // Input section
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("New Amount")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    VStack(spacing: 16) {
                        TextField("0.00", text: $editValue)
                            .textFieldStyle(PlainTextFieldStyle())
                            #if os(iOS)
                            .focused($isFieldFocused)
                            #endif
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .onChange(of: editValue) { newValue in
                                if field == .creditCard {
                                    // For credit card, add negative sign only if value is not 0 or empty
                                    if !newValue.isEmpty {
                                        let numericValue = Double(newValue) ?? 0
                                        if numericValue != 0 && !newValue.hasPrefix("-") {
                                            editValue = "-" + newValue
                                        } else if numericValue == 0 && newValue.hasPrefix("-") {
                                            // Remove negative sign if value is 0
                                            editValue = String(newValue.dropFirst())
                                        }
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.regularMaterial)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
                        
                        HStack {
                            Text("Enter the new amount for this account")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                
                // Action buttons
                HStack(spacing: 20) {
                    Button(action: {
                        dismiss()
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
                    .disabled(isUpdating)
                    .opacity(isUpdating ? 0.6 : 1.0)
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
                        onSave(editValue)
                    }) {
                        HStack(spacing: 12) {
                            if isUpdating {
                                ProgressView()
                                    .scaleEffect(1.0)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Text(isUpdating ? "Saving..." : "Save Changes")
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
                    .disabled(isUpdating || editValue.isEmpty)
                    .opacity((isUpdating || editValue.isEmpty) ? 0.7 : 1.0)
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
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
        }
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.background)
                .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}

// Quick Actions Section
struct QuickActionsView: View {
    @Binding var showingAddCustomerDialog: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section Title
            HStack {
                Text("Quick Actions")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 30)
            
            // Action Buttons
            if horizontalSizeClass == .compact && verticalSizeClass == .regular {
                // iPhone Portrait - Vertical stack
                VStack(spacing: 12) {
                    QuickActionButton(
                        title: "Add Entity",
                        icon: "person.badge.plus",
                        color: Color(red: 0.25, green: 0.33, blue: 0.54),
                        action: {
                            showingAddCustomerDialog = true
                        }
                    )
                    QuickActionButton(
                        title: "Add Product",
                        icon: "iphone",
                        color: Color(red: 0.60, green: 0.20, blue: 0.80),
                        action: {}
                    )
                    QuickActionButton(
                        title: "Add Expense",
                        icon: "minus.circle",
                        color: Color(red: 0.90, green: 0.30, blue: 0.30),
                        action: {}
                    )
                }
                .padding(.horizontal, 20)
            } else {
                // macOS/iPad - Grid layout
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 15),
                    GridItem(.flexible(), spacing: 15),
                    GridItem(.flexible(), spacing: 15)
                ], spacing: 15) {
                    QuickActionButton(
                        title: "Add Entity",
                        icon: "person.badge.plus",
                        color: Color(red: 0.25, green: 0.33, blue: 0.54),
                        action: {
                            showingAddCustomerDialog = true
                        }
                    )
                    QuickActionButton(
                        title: "Add Product",
                        icon: "iphone",
                        color: Color(red: 0.60, green: 0.20, blue: 0.80),
                        action: {}
                    )
                    QuickActionButton(
                        title: "Add Expense",
                        icon: "minus.circle",
                        color: Color(red: 0.90, green: 0.30, blue: 0.30),
                        action: {}
                    )
                }
                .padding(.horizontal, 30)
            }
        }
    }
}

// Individual Quick Action Button
struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon with background
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(color)
                }
                
                // Title
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                // Arrow indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
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
    }
}

// Add Entity Dialog
struct AddCustomerDialog: View {
    @Binding var isPresented: Bool
    @State private var name: String = ""
    @State private var initialBalance: String = ""
    @State private var phone: String = ""
    @State private var notes: String = ""
    @State private var email: String = ""
    @State private var address: String = ""
    @State private var isUpdating = false
    @State private var showSuccessToast = false
    @State private var selectedEntityType: EntityType = .customer
    @State private var balanceType: BalanceType = .toReceive
    @FocusState private var isFieldFocused: Bool
    @FocusState private var focusedField: FieldType?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    enum BalanceType: String, CaseIterable {
        case toReceive = "To Receive"
        case toGive = "To Give"
        
        var color: Color {
            switch self {
            case .toReceive: return Color.green
            case .toGive: return Color.red
            }
        }
    }
    
    enum EntityType: String, CaseIterable {
        case customer = "Customer"
        case supplier = "Supplier"
        case middleman = "Middleman"
        
        var icon: String {
            switch self {
            case .customer: return "person.badge.plus"
            case .supplier: return "building.2"
            case .middleman: return "person.2"
            }
        }
        
        var color: Color {
            switch self {
            case .customer: return Color(red: 0.25, green: 0.33, blue: 0.54)
            case .supplier: return Color(red: 0.20, green: 0.60, blue: 0.40)
            case .middleman: return Color(red: 0.80, green: 0.40, blue: 0.20)
            }
        }
        
        var collectionName: String {
            switch self {
            case .customer: return "Customers"
            case .supplier: return "Suppliers"
            case .middleman: return "Middlemen"
            }
        }
    }
    
    enum FieldType: CaseIterable {
        case name, initialBalance, phone, email, address, notes
    }
    
    var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    var shouldShowiPhoneDialog: Bool {
        #if os(iOS)
        return true // Always show iPhone dialog on iOS (iPhone and iPad)
        #else
        return false // Show desktop dialog on macOS
        #endif
    }
    
    var bufferOverlay: some View {
        Group {
            if isUpdating || showSuccessToast {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            if showSuccessToast {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 40, weight: .semibold))
                                    .foregroundColor(.white)
                                    .background(
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 40, height: 40)
                                    )
                                    .shadow(color: .green.opacity(0.8), radius: 12, x: 0, y: 0)
                            } else {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            
                            Text(showSuccessToast ? "\(selectedEntityType.rawValue) Added Successfully!" : "Saving \(selectedEntityType.rawValue)...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                        )
                    )
            }
        }
    }
    
    var entityTypeSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entity Type")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            entityTypeButtons
        }
    }
    
    var entityTypeButtons: some View {
        HStack(spacing: 8) {
            ForEach(EntityType.allCases, id: \.self) { entityType in
                entityTypeButton(for: entityType)
            }
        }
    }
    
    func entityTypeButton(for entityType: EntityType) -> some View {
        Button(action: {
            selectedEntityType = entityType
        }) {
            entityTypeButtonContent(for: entityType)
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
    
    func entityTypeButtonContent(for entityType: EntityType) -> some View {
        HStack(spacing: 6) {
            Image(systemName: selectedEntityType == entityType ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(selectedEntityType == entityType ? entityType.color : .secondary)
            
            Text(entityType.rawValue)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(selectedEntityType == entityType ? entityType.color : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(entityTypeButtonBackground(for: entityType))
    }
    
    func entityTypeButtonBackground(for entityType: EntityType) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selectedEntityType == entityType ? entityType.color.opacity(0.1) : Color.gray.opacity(0.1))
            .stroke(selectedEntityType == entityType ? entityType.color : Color.clear, lineWidth: 1.5)
    }
    
    var desktopDialogHeader: some View {
        HStack(spacing: 16) {
            desktopDialogIcon
            desktopDialogTitle
            Spacer()
            desktopDialogCloseButton
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }
    
    var desktopDialogIcon: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.15))
                .frame(width: 50, height: 50)
            
            Image(systemName: "person.badge.plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
        }
    }
    
    var desktopDialogTitle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add New Entity")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            
            desktopEntityTypeSelection
        }
    }
    
    var desktopEntityTypeSelection: some View {
        HStack(spacing: 8) {
            Text("Type:")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            ForEach(EntityType.allCases, id: \.self) { entityType in
                desktopEntityTypeButton(for: entityType)
            }
        }
    }
    
    func desktopEntityTypeButton(for entityType: EntityType) -> some View {
        Button(action: {
            selectedEntityType = entityType
        }) {
            HStack(spacing: 6) {
                Image(systemName: selectedEntityType == entityType ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(selectedEntityType == entityType ? entityType.color : .secondary)
                
                Text(entityType.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(selectedEntityType == entityType ? entityType.color : .primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(desktopEntityTypeButtonBackground(for: entityType))
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
    
    func desktopEntityTypeButtonBackground(for entityType: EntityType) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selectedEntityType == entityType ? entityType.color.opacity(0.1) : Color.gray.opacity(0.1))
            .stroke(selectedEntityType == entityType ? entityType.color : Color.clear, lineWidth: 1)
    }
    
    var initialBalanceField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Initial Balance")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            HStack(spacing: 0) {
                TextField("0.00", text: $initialBalance)
                    .textFieldStyle(PlainTextFieldStyle())
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .initialBalance)
                    .submitLabel(.done)
                    #endif
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: initialBalance) { newValue in
                        // Ensure the balance reflects the selected type
                        updateBalanceForType()
                    }
                
                // Balance type buttons
                HStack(spacing: 4) {
                    ForEach(BalanceType.allCases, id: \.self) { type in
                        Button(action: {
                            balanceType = type
                            updateBalanceForType()
                        }) {
                            Text(type.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(balanceType == type ? .white : type.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(balanceType == type ? type.color : type.color.opacity(0.1))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.trailing, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.regularMaterial)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    var desktopInitialBalanceField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Initial Balance")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            HStack(spacing: 0) {
                TextField("0.00", text: $initialBalance)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .onChange(of: initialBalance) { newValue in
                        updateBalanceForType()
                    }
                
                // Balance type buttons
                HStack(spacing: 6) {
                    ForEach(BalanceType.allCases, id: \.self) { type in
                        Button(action: {
                            balanceType = type
                            updateBalanceForType()
                        }) {
                            Text(type.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(balanceType == type ? .white : type.color)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(balanceType == type ? type.color : type.color.opacity(0.1))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.trailing, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private func updateBalanceForType() {
        guard !initialBalance.isEmpty else { return }
        
        let numericValue = Double(initialBalance) ?? 0
        if numericValue == 0 { return }
        
        switch balanceType {
        case .toReceive:
            // Ensure positive value
            if numericValue < 0 {
                initialBalance = String(abs(numericValue))
            }
        case .toGive:
            // Ensure negative value
            if numericValue > 0 {
                initialBalance = "-" + initialBalance
            }
        }
    }
    
    var desktopDialogCloseButton: some View {
        Button(action: {
            isPresented = false
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

    
    var body: some View {
        if shouldShowiPhoneDialog {
            iPhoneDialogView
        } else {
            DesktopDialogView
        }
    }
    
    var iPhoneDialogView: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                    
                    Spacer()
                    
                    Text("Add Entity")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Save") {
                        Task {
                            await saveCustomer()
                        }
                    }
                    .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                    .fontWeight(.semibold)
                    .disabled(isUpdating || name.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.background)
                
                Divider()
                
                // Content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 24) {
                        // Entity Type Selection
                        entityTypeSelection
                        
                        // Name Field (Required)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name *")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            TextField("Enter customer name", text: $name)
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .focused($focusedField, equals: .name)
                                .submitLabel(.done)
                                #endif
                                .font(.system(size: 18, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.regularMaterial)
                                        .stroke(name.isEmpty ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                                .id("name")
                                .onChange(of: focusedField) { newValue in
                                    if newValue == .name {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("name", anchor: .center)
                                        }
                                    }
                                }
                        }
                        
                        // Initial Balance Field
                        initialBalanceField
                            .id("initialBalance")
                            .onChange(of: focusedField) { newValue in
                                if newValue == .initialBalance {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        proxy.scrollTo("initialBalance", anchor: .center)
                                    }
                                }
                            }
                        
                        // Phone Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Phone")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            TextField("Enter phone number", text: $phone)
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .keyboardType(.phonePad)
                                .focused($focusedField, equals: .phone)
                                .submitLabel(.done)
                                #endif
                                .font(.system(size: 18, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.regularMaterial)
                                )
                                .id("phone")
                                .onChange(of: focusedField) { newValue in
                                    if newValue == .phone {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("phone", anchor: .center)
                                        }
                                    }
                                }
                        }
                        
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            TextField("Enter email address", text: $email)
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .focused($focusedField, equals: .email)
                                .submitLabel(.done)
                                #endif
                                .font(.system(size: 18, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.regularMaterial)
                                )
                                .id("email")
                                .onChange(of: focusedField) { newValue in
                                    if newValue == .email {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("email", anchor: .center)
                                        }
                                    }
                                }
                        }
                        
                        // Address Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Address")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            TextField("Enter address", text: $address, axis: .vertical)
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .focused($focusedField, equals: .address)
                                .submitLabel(.return)
                                .onSubmit {
                                    focusedField = nil
                                }
                                #endif
                                .font(.system(size: 18, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.regularMaterial)
                                )
                                .lineLimit(3...6)
                                .id("address")
                                .onChange(of: focusedField) { newValue in
                                    if newValue == .address {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("address", anchor: .center)
                                        }
                                    }
                                }
                        }
                        
                        // Notes Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            TextField("Enter notes", text: $notes, axis: .vertical)
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .focused($focusedField, equals: .notes)
                                .submitLabel(.return)
                                .onSubmit {
                                    focusedField = nil
                                }
                                #endif
                                .font(.system(size: 18, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.regularMaterial)
                                )
                                .lineLimit(3...6)
                                .id("notes")
                                .onChange(of: focusedField) { newValue in
                                    if newValue == .notes {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("notes", anchor: .center)
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 34)
                    }
                }
            }
            .background(.background)
            .overlay(bufferOverlay)
            #if os(iOS)
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(action: {
                        switch focusedField {
                        case .name:
                            focusedField = .initialBalance
                        case .initialBalance:
                            focusedField = .phone
                        case .phone:
                            focusedField = .email
                        case .email:
                            focusedField = .address
                        case .address:
                            focusedField = .notes
                        case .notes:
                            break
                        case .none:
                            break
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("Next")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .disabled(focusedField == .notes)
                }
            }
            #endif
            .onAppear {
                #if os(iOS)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .name
                }
                #endif
            }
        }
    }
    
    var DesktopDialogView: some View {
        VStack(spacing: 0) {
            desktopDialogHeader
            
            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 32)
            
            // Content area - Layout matching image
            VStack(spacing: 20) {
                // Top row: Name, Phone, Email (horizontal)
                HStack(spacing: 20) {
                    // Name Field (Required)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Name *")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        TextField("Enter customer name", text: $name)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 18, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                                    .stroke(name.isEmpty ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                    }
                    
                    // Phone Field
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Phone")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        TextField("Enter phone", text: $phone)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 18, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                            )
                    }
                    
                    // Email Field
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Email")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        TextField("Enter email", text: $email)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 18, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                            )
                    }
                }
                
                // Address Field (full width)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Address")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    TextField("Enter address", text: $address, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 18, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                        .lineLimit(3...6)
                }
                
                // Notes Field (full width)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Notes")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    TextField("Enter notes", text: $notes, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 18, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                        .lineLimit(3...6)
                }
                
                // Initial Balance Field (full width, under notes)
                desktopInitialBalanceField
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 20)
            
            // Action buttons
            HStack(spacing: 20) {
                Button(action: {
                    isPresented = false
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
                .disabled(isUpdating)
                .opacity(isUpdating ? 0.6 : 1.0)
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
                    Task {
                        await saveCustomer()
                    }
                }) {
                    HStack(spacing: 12) {
                        if isUpdating {
                            ProgressView()
                                .scaleEffect(1.0)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(isUpdating ? "Saving..." : "Save \(selectedEntityType.rawValue)")
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
                .disabled(isUpdating || name.isEmpty)
                .opacity((isUpdating || name.isEmpty) ? 0.7 : 1.0)
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
            .padding(.bottom, 28)
        }
        .frame(width: 800, height: 750)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.background)
                .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(bufferOverlay)
    }
    
    private func saveCustomer() async {
        guard !name.isEmpty else { return }
        
        // Close keyboard immediately when save is clicked
        focusedField = nil
        isUpdating = true
        
        // Parse the balance and ensure it reflects the selected type
        var balance = Double(initialBalance) ?? 0.0
        
        // Apply the balance type logic
        switch balanceType {
        case .toReceive:
            balance = abs(balance) // Ensure positive
        case .toGive:
            balance = -abs(balance) // Ensure negative
        }
        
        let customerData: [String: Any] = [
            "name": name,
            "balance": balance,
            "phone": phone,
            "email": email,
            "address": address,
            "notes": notes,
            "transactionHistory": [],
            "createdAt": Timestamp(),
            "updatedAt": Timestamp()
        ]
        
        do {
            let db = Firestore.firestore()
            try await db.collection(selectedEntityType.collectionName).addDocument(data: customerData)
            
            // Show success state
            showSuccessToast = true
            
            // Add double haptic feedback
            #if os(iOS)
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            // Second haptic after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                impactFeedback.impactOccurred()
            }
            #endif
            
            // Dismiss dialog after checkmark has been visible for 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isPresented = false
            }
        } catch {
            print("Error saving customer: \(error)")
        }
        
        isUpdating = false
    }
}
