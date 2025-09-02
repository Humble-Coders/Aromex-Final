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
    @FocusState private var isIPadFieldFocused: Bool
    
    var isIPad: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular && verticalSizeClass == .regular
        #else
        return false
        #endif
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
                    .background(Color.secondary.opacity(0.1))
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
            MainContentView(
                selectedMenuItem: selectedMenuItem,
                ipadEditingField: $ipadEditingField,
                ipadIsUpdating: $ipadIsUpdating,
                balanceViewModel: balanceViewModel
            )
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    var iPhonePortraitView: some View {
        #if os(iOS)
        NavigationStack {
            MainContentView(
                selectedMenuItem: selectedMenuItem,
                ipadEditingField: $ipadEditingField,
                ipadIsUpdating: $ipadIsUpdating,
                balanceViewModel: balanceViewModel
            )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
    
    let menuItems = [
        ("Home", "house"),
        ("Purchase", "cart"),
        ("Sales", "chart.line.uptrend.xyaxis"),
        ("Supplier Profile", "person.2"),
        ("Customer Profile", "person.3"),
        ("Middleman Profile", "person.badge.plus"),
        ("Inventory", "archivebox"),
        ("Statistics", "chart.bar")
    ]
    
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
    let selectedMenuItem: String
    @Binding var ipadEditingField: AccountBalanceCard.BalanceField?
    @Binding var ipadIsUpdating: Bool
    @ObservedObject var balanceViewModel: BalanceViewModel
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
                        QuickActionsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
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
        ("Supplier Profile", "person.2"),
        ("Customer Profile", "person.3"),
        ("Middleman Profile", "person.badge.plus"),
        ("Inventory", "archivebox"),
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
                                .fill(Color.white)
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
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isUpdating)
                    .opacity(isUpdating ? 0.6 : 1.0)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 34)
            }
            .background(Color.white)
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
                                    .fill(Color.white)
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
                                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
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
                .fill(Color.white)
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
                        title: "Add Customer",
                        icon: "person.badge.plus",
                        color: Color(red: 0.25, green: 0.33, blue: 0.54)
                    )
                    QuickActionButton(
                        title: "Add Supplier",
                        icon: "building.2",
                        color: Color(red: 0.20, green: 0.60, blue: 0.40)
                    )
                    QuickActionButton(
                        title: "Add Middleman",
                        icon: "person.2",
                        color: Color(red: 0.80, green: 0.40, blue: 0.20)
                    )
                    QuickActionButton(
                        title: "Add Product",
                        icon: "iphone",
                        color: Color(red: 0.60, green: 0.20, blue: 0.80)
                    )
                    QuickActionButton(
                        title: "Add Expense",
                        icon: "minus.circle",
                        color: Color(red: 0.90, green: 0.30, blue: 0.30)
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
                        title: "Add Customer",
                        icon: "person.badge.plus",
                        color: Color(red: 0.25, green: 0.33, blue: 0.54)
                    )
                    QuickActionButton(
                        title: "Add Supplier",
                        icon: "building.2",
                        color: Color(red: 0.20, green: 0.60, blue: 0.40)
                    )
                    QuickActionButton(
                        title: "Add Middleman",
                        icon: "person.2",
                        color: Color(red: 0.80, green: 0.40, blue: 0.20)
                    )
                    QuickActionButton(
                        title: "Add Product",
                        icon: "iphone",
                        color: Color(red: 0.60, green: 0.20, blue: 0.80)
                    )
                    QuickActionButton(
                        title: "Add Expense",
                        icon: "minus.circle",
                        color: Color(red: 0.90, green: 0.30, blue: 0.30)
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
    
    var body: some View {
        Button(action: {
            // TODO: Add functionality
        }) {
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
