//
//  EntityDetailView.swift
//  Aromex
//
//  Created by User on 9/17/25.
//

import SwiftUI
import FirebaseFirestore
#if os(iOS)
import UIKit
#endif

// Typealias to disambiguate between SwiftUI.Transaction and FirebaseFirestore.Transaction
typealias FirestoreTransaction = FirebaseFirestore.Transaction

// MARK: - Entity Transaction Model
struct EntityTransaction: Identifiable {
    let id: String
    let type: EntityTransactionType
    let date: Date
    let amount: Double
    let role: String
    
    // Purchase/Sales specific
    var orderNumber: Int?
    var grandTotal: Double?
    var paid: Double?
    var credit: Double?
    var gstAmount: Double?
    var pstAmount: Double?
    var notes: String?
    var itemCount: Int?
    
    // Payment methods breakdown
    var cashPaid: Double?
    var bankPaid: Double?
    var creditCardPaid: Double?
    
    // Middleman payment split
    var middlemanCash: Double?
    var middlemanBank: Double?
    var middlemanCreditCard: Double?
    var middlemanCredit: Double?
    var middlemanUnit: String?
    var middlemanName: String?
    var sourceCollection: String? // "Purchases" or "Sales" - to determine color coding for paid/credit
    
    // Currency transaction specific
    var currencyGiven: String?
    var currencyName: String?
    var giver: String?
    var giverName: String?
    var taker: String?
    var takerName: String?
    var isExchange: Bool?
    var receivingCurrency: String?
    var receivedAmount: Double?
    var customExchangeRate: Double?
    var balancesAfterTransaction: [String: Any]?
}

enum EntityTransactionType: String {
    case purchase = "Purchase"
    case sale = "Sale"
    case middleman = "Middleman"
    case currencyRegular = "Transaction"
    case currencyExchange = "Exchange"
    case expense = "Expense"
    case balanceAdjustment = "Balance Adjustment"
    
    var color: Color {
        switch self {
        case .purchase: return .green
        case .sale: return .blue
        case .middleman: return Color(red: 0.80, green: 0.40, blue: 0.20)
        case .currencyRegular: return .orange
        case .currencyExchange: return .purple
        case .expense: return .red
        case .balanceAdjustment: return .indigo
        }
    }
    
    var icon: String {
        switch self {
        case .purchase: return "cart.fill"
        case .sale: return "dollarsign.circle.fill"
        case .middleman: return "person.2.fill"
        case .currencyRegular: return "banknote.fill"
        case .currencyExchange: return "arrow.left.arrow.right.circle.fill"
        case .expense: return "arrow.down.circle.fill"
        case .balanceAdjustment: return "pencil.circle.fill"
        }
    }
}

struct EntityDetailView: View {
    let entity: EntityProfile
    let entityType: EntityType
    
    @State private var showingEditDialog = false
    @State private var editingEntity: EntityProfile?
    @State private var currentEntity: EntityProfile
    @State private var listener: ListenerRegistration?
    
    // Transaction history
    @State private var transactions: [EntityTransaction] = []
    @State private var isLoadingTransactions = false
    @State private var transactionError: String?
    @State private var searchText = ""
    
    // Balance adjustments
    @State private var balanceAdjustments: [EntityTransaction] = []
    
    // Currency balances
    @State private var currencyBalances: [String: Double] = [:]
    @StateObject private var currencyManager = CurrencyManager.shared
    
    // Balance editing
    @State private var showingBalanceEditSheet = false
    @State private var editingBalanceCurrency: String? = nil // nil = CAD, otherwise currency name
    @State private var balanceEditValue: String = ""
    @State private var balanceEditType: BalanceEditType = .toReceive
    @State private var isUpdatingBalance = false
    
    enum BalanceEditType: String, CaseIterable {
        case toReceive = "To Receive"
        case toGive = "To Give"
        
        var color: Color {
            switch self {
            case .toReceive: return Color.green
            case .toGive: return Color.red
            }
        }
    }
    
    // Bill screen - using optional to ensure correct transaction
    @State private var selectedBillTransaction: (id: String, isSale: Bool)? = nil
    
    // Ledger screen state
    @State private var showingLedgerDateRangeDialog = false
    @State private var ledgerStartDate: Date? = nil
    @State private var ledgerEndDate: Date? = nil
    @State private var showingLedgerScreen = false
    
    // Filters
    @State private var filterPurchase = false
    @State private var filterSale = false
    @State private var filterMiddleman = false
    @State private var filterCash = false
    
    // Date range filter
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    private var filteredTransactions: [EntityTransaction] {
        var filtered = transactions + balanceAdjustments
        // Sort by date descending (newest first) to maintain proper chronology
        filtered = filtered.sorted { $0.date > $1.date }
        
        // Apply type filters
        // If none selected OR all selected, show all
        let noneSelected = !filterPurchase && !filterSale && !filterMiddleman && !filterCash
        let allSelected = filterPurchase && filterSale && filterMiddleman && filterCash
        
        if !noneSelected && !allSelected {
            // Some filters selected - show only those
            filtered = filtered.filter { transaction in
                switch transaction.type {
                case .purchase: return filterPurchase
                case .sale: return filterSale
                case .middleman: return filterMiddleman
                case .currencyRegular, .currencyExchange: return filterCash
                case .expense: return filterCash // Expenses use the same filter as cash for now
                case .balanceAdjustment: return filterCash // Balance adjustments use the same filter as cash for now
                }
            }
        }
        
        // Apply date range filter
        if let start = startDate {
            let startOfDay = Calendar.current.startOfDay(for: start)
            filtered = filtered.filter { $0.date >= startOfDay }
        }
        
        if let end = endDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
            filtered = filtered.filter { $0.date < endOfDay }
        }
        
        // Apply search text
        if !searchText.isEmpty {
            filtered = filtered.filter { transaction in
                // Search in names
                if let giverName = transaction.giverName, giverName.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                if let takerName = transaction.takerName, takerName.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                // Search in middleman name
                if let middlemanName = transaction.middlemanName, middlemanName.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                // Search in order number
                if let orderNum = transaction.orderNumber, String(orderNum).contains(searchText) {
                    return true
                }
                
                // Search in notes
                if let notes = transaction.notes, notes.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                // Search in type
                if transaction.type.rawValue.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                // Search in role
                if transaction.role.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                // Search in currency name
                if let currencyName = transaction.currencyName, currencyName.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                // Search in amounts (total, paid, credit)
                let amountString = String(format: "%.2f", transaction.amount)
                if amountString.contains(searchText) {
                    return true
                }
                
                if let paid = transaction.paid {
                    let paidString = String(format: "%.2f", paid)
                    if paidString.contains(searchText) {
                        return true
                    }
                }
                
                if let credit = transaction.credit {
                    let creditString = String(format: "%.2f", credit)
                    if creditString.contains(searchText) {
                        return true
                    }
                }
                
                return false
            }
        }
        
        return filtered
    }
    
    init(entity: EntityProfile, entityType: EntityType) {
        self.entity = entity
        self.entityType = entityType
        self._currentEntity = State(initialValue: entity)
    }
    
    private var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: isCompact ? 16 : 20) {
                professionalHeaderSection
                
                // Transaction History Section
                transactionHistorySection
                
                Spacer(minLength: isCompact ? 60 : 100)
            }
            .padding(.horizontal, isCompact ? 8 : 20)
            .padding(.top, isCompact ? 12 : 20)
            .padding(.bottom, isCompact ? 16 : 20)
        }
        .sheet(item: $editingEntity) { _ in
            EditEntityDialog(
                isPresented: .constant(true),
                entityType: entityType,
                editingEntity: currentEntity,
                onSave: { updatedEntity in
                    // Handle the save operation here
                    print("Updated entity: \(updatedEntity)")
                    editingEntity = nil
                },
                onDismiss: {
                    editingEntity = nil
                },
                allowBalanceEditing: false
            )
        }
        .sheet(isPresented: $showingBalanceEditSheet) {
            balanceEditSheet
        }
        .sheet(isPresented: $showingLedgerDateRangeDialog) {
            LedgerDateRangeDialog(
                startDate: $ledgerStartDate,
                endDate: $ledgerEndDate,
                onCancel: {
                    showingLedgerDateRangeDialog = false
                    ledgerStartDate = nil
                    ledgerEndDate = nil
                },
                onGenerate: {
                    showingLedgerDateRangeDialog = false
                    showingLedgerScreen = true
                }
            )
        }
        #if os(iOS)
        .navigationDestination(isPresented: Binding(
            get: { selectedBillTransaction != nil },
            set: { newValue in
                if !newValue {
                    selectedBillTransaction = nil
                }
            }
        )) {
            if let billTransaction = selectedBillTransaction {
                BillScreen(
                    purchaseId: billTransaction.id,
                    onClose: {
                        selectedBillTransaction = nil
                    },
                    isSale: billTransaction.isSale
                )
                .navigationBarBackButtonHidden(true)
            }
        }
        .navigationDestination(isPresented: $showingLedgerScreen) {
            LedgerScreen(
                entity: currentEntity,
                entityType: entityType,
                transactions: getAllTransactionsForLedger(),
                startDate: ledgerStartDate,
                endDate: ledgerEndDate,
                onClose: {
                    showingLedgerScreen = false
                }
            )
            .navigationBarBackButtonHidden(true)
        }
        #else
        .background(
            NavigationLink(
                destination: Group {
                    if let billTransaction = selectedBillTransaction {
                        BillScreen(
                            purchaseId: billTransaction.id,
                            onClose: {
                                selectedBillTransaction = nil
                            },
                            isSale: billTransaction.isSale
                        )
                    }
                },
                isActive: Binding(
                    get: { selectedBillTransaction != nil },
                    set: { newValue in
                        if !newValue {
                            selectedBillTransaction = nil
                        }
                    }
                ),
                label: { EmptyView() }
            )
            .hidden()
        )
        .background(
            NavigationLink(
                destination: LedgerScreen(
                    entity: currentEntity,
                    entityType: entityType,
                    transactions: getAllTransactionsForLedger(),
                    startDate: ledgerStartDate,
                    endDate: ledgerEndDate,
                    onClose: {
                        showingLedgerScreen = false
                    }
                ),
                isActive: $showingLedgerScreen,
                label: { EmptyView() }
            )
            .hidden()
        )
        #endif
        .onAppear {
            setupListener()
            fetchTransactions()
            fetchBalanceAdjustments()
            fetchCurrencyBalances()
            currencyManager.fetchCurrencies()
        }
        .onDisappear {
            removeListener()
        }
    }
    
   
        var transactionHistorySection: some View {
            VStack(alignment: .leading, spacing: isCompact ? 14 : 16) {
                // Section Header with improved styling
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: isCompact ? 16 : 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: isCompact ? 32 : 36, height: isCompact ? 32 : 36)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [entityType.color, entityType.color.opacity(0.8)]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .shadow(color: entityType.color.opacity(0.3), radius: 3, x: 0, y: 2)
                            )
                        
                        Text("Transaction History")
                            .font(.system(size: isCompact ? 20 : 22, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    if isLoadingTransactions {
                        ProgressView()
                            .scaleEffect(isCompact ? 0.8 : 0.9)
                    }
                }
                .padding(.horizontal, isCompact ? 16 : 20)
                .padding(.top, isCompact ? 16 : 20)
                
                // Search Bar and Filters - Enhanced iPhone layout
                if isCompact {
                    // iPhone: Vertical layout with improved styling
                    VStack(spacing: 14) {
                        // Enhanced Search Bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            
                            TextField("Search transactions...", text: $searchText)
                                .font(.system(size: 15))
                                .disableAutocorrection(true)
                                #if os(iOS)
                                .autocapitalization(.none)
                                #endif
                            
                            if !searchText.isEmpty {
                                Button(action: {
                                    withAnimation {
                                        searchText = ""
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                        .padding(2)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondarySystemBackground)
                                .shadow(color: Color.primary.opacity(0.06), radius: 2, x: 0, y: 1)
                        )
                        
                        // Filters - Horizontal scrollable with enhanced chips
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Filter by Type")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 2)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    TransactionFilterChip(title: "Purchase", isActive: $filterPurchase, color: Color.green)
                                    TransactionFilterChip(title: "Sale", isActive: $filterSale, color: Color.blue)
                                    TransactionFilterChip(title: "Middleman", isActive: $filterMiddleman, color: Color(red: 0.80, green: 0.40, blue: 0.20))
                                    TransactionFilterChip(title: "Transaction", isActive: $filterCash, color: Color.orange)
                                }
                                .padding(.horizontal, 2)
                                .padding(.bottom, 4)
                            }
                        }
                        
                        // Date Range Filter with improved styling
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Date Range")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 2)
                            
                            HStack(spacing: 10) {
                                // Start Date
                                dateFilterItem(
                                    label: "From",
                                    date: startDate,
                                    dateBinding: Binding(
                                        get: { startDate ?? Date() },
                                        set: { startDate = $0 }
                                    ),
                                    clearAction: { startDate = nil }
                                )
                                
                                // End Date
                                dateFilterItem(
                                    label: "To",
                                    date: endDate,
                                    dateBinding: Binding(
                                        get: { endDate ?? Date() },
                                        set: { endDate = $0 }
                                    ),
                                    clearAction: { endDate = nil }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, isCompact ? 16 : 20)
                } else {
                    // iPad/macOS layout (unchanged)
                    HStack(spacing: 12) {
                        // Search Bar (Compact)
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            TextField("Search...", text: $searchText)
                                .font(.system(size: 13))
                                .textFieldStyle(PlainTextFieldStyle())
                            
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(width: 200)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                        )
                        
                        // Filters
                        HStack(spacing: 8) {
                            TransactionFilterChip(title: "Purchase", isActive: $filterPurchase, color: .green)
                            TransactionFilterChip(title: "Sale", isActive: $filterSale, color: .blue)
                            TransactionFilterChip(title: "Middleman", isActive: $filterMiddleman, color: Color(red: 0.80, green: 0.40, blue: 0.20))
                            TransactionFilterChip(title: "Transaction", isActive: $filterCash, color: .orange)
                        }
                        
                        // Date Range Filter
                        HStack(spacing: 8) {
                            // Start Date
                            HStack(spacing: 4) {
                                Text("From:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                DatePicker("", selection: Binding(
                                    get: { startDate ?? Date() },
                                    set: { startDate = $0 }
                                ), displayedComponents: .date)
                                .labelsHidden()
                                .frame(width: 110)
                                
                                if startDate != nil {
                                    Button(action: { startDate = nil }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(startDate != nil ? Color.purple.opacity(0.1) : Color.gray.opacity(0.08))
                            )
                            
                            // End Date
                            HStack(spacing: 4) {
                                Text("To:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                DatePicker("", selection: Binding(
                                    get: { endDate ?? Date() },
                                    set: { endDate = $0 }
                                ), displayedComponents: .date)
                                .labelsHidden()
                                .frame(width: 110)
                                
                                if endDate != nil {
                                    Button(action: { endDate = nil }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(endDate != nil ? Color.purple.opacity(0.1) : Color.gray.opacity(0.08))
                            )
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
                
                // Transaction list content with loading states and empty states
                if let error = transactionError {
                    errorView(message: error)
                } else if filteredTransactions.isEmpty && !isLoadingTransactions {
                    emptyStateView(isSearching: !searchText.isEmpty)
                } else {
                    // Transactions List
                    LazyVStack(spacing: isCompact ? 12 : 12) {
                        ForEach(filteredTransactions) { transaction in
                            EntityTransactionRowView(
                                transaction: transaction,
                                entityType: entityType,
                                onTransactionDeleted: { deletedId in
                                    removeTransactionFromList(id: deletedId)
                                },
                                onViewBill: { transactionId, isSale in
                                    print("📊 EntityDetailView received onViewBill: \(transactionId), isSale: \(isSale)")
                                    // Set the transaction as a tuple to ensure atomicity
                                    selectedBillTransaction = (id: transactionId, isSale: isSale)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, isCompact ? 16 : 20)
                    .padding(.bottom, isCompact ? 16 : 20)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 14 : 12)
                    .fill(Color.systemBackground)
                    .shadow(color: Color.primary.opacity(0.1), radius: isCompact ? 10 : 10, x: 0, y: isCompact ? 4 : 5)
            )
        }
        
        // Date filter item with improved styling
        private func dateFilterItem(label: String, date: Date?, dateBinding: Binding<Date>, clearAction: @escaping () -> Void) -> some View {
            HStack(spacing: 8) {
                // On iPhone: Show cross in place of label when date is selected
                if isCompact {
                    if date != nil {
                        Button(action: clearAction) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(width: 40, alignment: .leading)
                    } else {
                        Text(label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .leading)
                    }
                } else {
                    // iPad/macOS: Show label normally
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)
                }
                
                // Show "Forever" when no date selected, or date value
                if date == nil {
                    Button(action: {
                        // Open date picker with today's date
                        dateBinding.wrappedValue = Date()
                    }) {
                        Text("Forever")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    DatePicker("", selection: dateBinding, displayedComponents: .date)
                        .labelsHidden()
                        .scaleEffect(0.9)
                        .frame(height: 30)
                }
                
                // Cross button only for iPad/macOS (on right side)
                if !isCompact && date != nil {
                    Button(action: clearAction) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(date != nil ? Color.purple.opacity(0.1) : Color.tertiarySystemBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(date != nil ? Color.purple.opacity(0.2) : Color.gray.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        
        // Error view with improved styling
        private func errorView(message: String) -> some View {
            VStack(spacing: isCompact ? 14 : 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: isCompact ? 38 : 42))
                    .foregroundColor(.orange)
                    .shadow(color: Color.orange.opacity(0.3), radius: 2, x: 0, y: 1)
                    .padding(.bottom, 4)
                
                Text("Failed to Load Transactions")
                    .font(.system(size: isCompact ? 18 : 20, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.system(size: isCompact ? 14 : 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                // Retry button
                Button(action: {
                    fetchTransactions()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue)
                            .shadow(color: Color.blue.opacity(0.4), radius: 3, x: 0, y: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 40 : 50)
        }
        
        // Empty state view with improved styling
        private func emptyStateView(isSearching: Bool) -> some View {
            VStack(spacing: isCompact ? 14 : 16) {
                if isSearching {
                    // No search results state
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: isCompact ? 38 : 42))
                        .foregroundColor(.gray)
                        .padding(.bottom, 4)
                    
                    Text("No Matching Transactions")
                        .font(.system(size: isCompact ? 18 : 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Try adjusting your search terms or filters")
                        .font(.system(size: isCompact ? 14 : 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    
                    // Clear filters button
                    if filterPurchase || filterSale || filterMiddleman || filterCash || startDate != nil || endDate != nil {
                        Button(action: {
                            withAnimation {
                                filterPurchase = false
                                filterSale = false
                                filterMiddleman = false
                                filterCash = false
                                startDate = nil
                                endDate = nil
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Clear All Filters")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue)
                                    .shadow(color: Color.blue.opacity(0.3), radius: 2, x: 0, y: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 8)
                    }
                } else {
                    // No transactions yet state
                    Image(systemName: "tray.fill")
                        .font(.system(size: isCompact ? 38 : 42))
                        .foregroundColor(.gray)
                        .padding(.bottom, 4)
                    
                    Text("No Transactions Yet")
                        .font(.system(size: isCompact ? 18 : 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Transactions will appear here once you add them")
                        .font(.system(size: isCompact ? 14 : 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 40 : 50)
        }
    
    
    @ViewBuilder
    var professionalHeaderSection: some View {
        if isCompact {
            iPhoneHeaderLayout
        } else {
            iPadMacHeaderLayout
        }
    }
    
    var iPadMacHeaderLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left Column: Entity Details
            VStack(alignment: .leading, spacing: 16) {
                // Name and Type
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentEntity.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(entityType.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(entityType.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(entityType.color.opacity(0.1))
                                .stroke(entityType.color.opacity(0.3), lineWidth: 1)
                        )
                }
                
                // Contact Information
                if !currentEntity.phone.isEmpty || !currentEntity.email.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !currentEntity.phone.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.blue)
                                    .frame(width: 16, alignment: .leading)
                                Text(currentEntity.phone)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        
                        if !currentEntity.email.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.orange)
                                    .frame(width: 16, alignment: .leading)
                                Text(currentEntity.email)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    }
                }
                
                // Notes
                if !currentEntity.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "note.text")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.purple)
                                .frame(width: 16, alignment: .leading)
                            Text(currentEntity.notes)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(3)
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right Column: Balance Cards and Edit Button
            VStack(alignment: .trailing, spacing: 16) {
                // Balance Cards Row
                HStack(spacing: 12) {
                    // CAD Balance Card
                    VStack(spacing: 6) {
                        Text(formatCurrency(currentEntity.balance))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(getBalanceColor(currentEntity.balance))
                            .lineLimit(1)
                        
                        Text(getBalanceDescription(currentEntity.balance))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(getBalanceColor(currentEntity.balance))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minWidth: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.background)
                            .shadow(color: getBalanceColor(currentEntity.balance).opacity(0.1), radius: 6, x: 0, y: 3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(getBalanceColor(currentEntity.balance).opacity(0.2), lineWidth: 1.5)
                    )
                    .overlay(
                        Button(action: {
                            editingBalanceCurrency = nil // nil means CAD
                            balanceEditValue = String(format: "%.2f", abs(currentEntity.balance))
                            balanceEditType = currentEntity.balance >= 0 ? .toReceive : .toGive
                            showingBalanceEditSheet = true
                        }) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                                .background(Circle().fill(.background))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(8),
                        alignment: .bottomTrailing
                    )
                    
                    // Other Currency Balance Cards
                    ForEach(Array(currencyBalances.keys.sorted()), id: \.self) { currency in
                        if let balance = currencyBalances[currency], abs(balance) >= 0.01 {
                            VStack(spacing: 6) {
                                Text("\(getCurrencySymbol(for: currency)) \(String(format: "%.2f", abs(balance)))")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(getBalanceColor(balance))
                                    .lineLimit(1)
                                
                                Text(getBalanceDescription(balance))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(getBalanceColor(balance))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(minWidth: 180)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.background)
                                    .shadow(color: getBalanceColor(balance).opacity(0.1), radius: 6, x: 0, y: 3)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(getBalanceColor(balance).opacity(0.2), lineWidth: 1.5)
                            )
                            .overlay(
                                Button(action: {
                                    editingBalanceCurrency = currency
                                    balanceEditValue = String(format: "%.2f", abs(balance))
                                    balanceEditType = balance >= 0 ? .toReceive : .toGive
                                    showingBalanceEditSheet = true
                                }) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                        .background(Circle().fill(.background))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(8),
                                alignment: .bottomTrailing
                            )
                        }
                    }
                }
                
                // Action Buttons Row
                HStack(spacing: 12) {
                    // Print Ledger Button
                    Button(action: {
                        showingLedgerDateRangeDialog = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "printer.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Print Ledger")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.25, green: 0.33, blue: 0.54))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Edit Button
                    Button(action: {
                        editingEntity = entity
                        showingEditDialog = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(entityType.color)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: Color.primary.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    
    var iPhoneHeaderLayout: some View {
        // iPhone: Clean and compact vertical layout
        VStack(alignment: .leading, spacing: 10) {
            // Top Row: Name, Type, Edit Button
            HStack(alignment: .center) {
                // Name and Type in same row
                HStack(spacing: 8) {
                    Text(currentEntity.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // Type badge with subtle styling
                    HStack(spacing: 4) {
                        Image(systemName: entityType.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(entityType.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(entityType.color)
                            .shadow(color: entityType.color.opacity(0.2), radius: 1, x: 0, y: 1)
                    )
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 8) {
                    // Print Ledger Button
                    Button(action: {
                        showingLedgerDateRangeDialog = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "printer.fill")
                                .font(.system(size: 11, weight: .medium))
                            Text("Ledger")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 0.25, green: 0.33, blue: 0.54))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Edit Button - smaller and cleaner
                    Button(action: {
                        editingEntity = entity
                        showingEditDialog = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(entityType.color)
                                    .shadow(color: entityType.color.opacity(0.2), radius: 2, x: 0, y: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Balance Card - with all currencies in one card
            VStack(alignment: .leading, spacing: 10) {
                Text("Balance")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                // Main CAD Balance
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatCurrency(currentEntity.balance))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(getBalanceColor(currentEntity.balance))
                        
                        Text(getBalanceDescription(currentEntity.balance))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(getBalanceColor(currentEntity.balance).opacity(0.8))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        editingBalanceCurrency = nil
                        balanceEditValue = String(format: "%.2f", abs(currentEntity.balance))
                        balanceEditType = currentEntity.balance >= 0 ? .toReceive : .toGive
                        showingBalanceEditSheet = true
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                            .background(Circle().fill(Color.secondarySystemBackground))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Other Currencies - horizontally scrollable
                if !currencyBalances.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(Array(currencyBalances.keys.sorted()), id: \.self) { currency in
                                if let balance = currencyBalances[currency], abs(balance) >= 0.01 {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 4) {
                                                Text(currency)
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(.secondary)
                                                
                                                Text("\(String(format: "%.2f", abs(balance)))")
                                                    .font(.system(size: 15, weight: .bold))
                                                    .foregroundColor(getBalanceColor(balance))
                                            }
                                            
                                            Text(balance >= 0 ? "To Receive" : "To Give")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(getBalanceColor(balance).opacity(0.8))
                                        }
                                        
                                        Button(action: {
                                            editingBalanceCurrency = currency
                                            balanceEditValue = String(format: "%.2f", abs(balance))
                                            balanceEditType = balance >= 0 ? .toReceive : .toGive
                                            showingBalanceEditSheet = true
                                        }) {
                                            Image(systemName: "pencil.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(.blue)
                                                .background(Circle().fill(Color.secondarySystemBackground))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(getBalanceColor(balance).opacity(0.05))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(getBalanceColor(balance).opacity(0.1), lineWidth: 0.5)
                                            )
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: 36)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondarySystemBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
                    )
            )
            
            // Contact Information Card - only show if exists
            if !currentEntity.phone.isEmpty || !currentEntity.email.isEmpty {
                HStack(spacing: 12) {
                    if !currentEntity.phone.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                            Text(currentEntity.phone)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }
                    
                    if !currentEntity.email.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Text(currentEntity.email)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondarySystemBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
                        )
                )
            }
            
            // Notes - with "Notes:" prefix
            if !currentEntity.notes.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text("Notes:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text(currentEntity.notes)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondarySystemBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
                        )
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.systemBackground)
                .shadow(color: Color.primary.opacity(0.06), radius: 4, x: 0, y: 2)
        )
    }
        
        // Helper function for contact rows
        private func contactRow(icon: String, color: Color, text: String) -> some View {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(color.opacity(0.1))
                    )
                
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        
        // Compact contact row for iPhone
        private func compactContactRow(icon: String, color: Color, text: String) -> some View {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(color.opacity(0.1))
                    )
                
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        
        // Balance cards section with enhanced styling
        private var balanceCardsSection: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Balance")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                
                if currencyBalances.isEmpty {
                    // Single CAD balance card - full width with enhanced styling
                    balanceCard(
                        amount: currentEntity.balance,
                        currency: "CAD",
                        fullWidth: true,
                        onEdit: {
                            editingBalanceCurrency = nil
                            balanceEditValue = String(format: "%.2f", abs(currentEntity.balance))
                            balanceEditType = currentEntity.balance >= 0 ? .toReceive : .toGive
                            showingBalanceEditSheet = true
                        }
                    )
                } else {
                    // Multiple currencies - horizontal scrollable with enhanced cards
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            // CAD Balance Card
                            balanceCard(
                                amount: currentEntity.balance,
                                currency: "CAD",
                                fullWidth: false,
                                onEdit: {
                                    editingBalanceCurrency = nil
                                    balanceEditValue = String(format: "%.2f", abs(currentEntity.balance))
                                    balanceEditType = currentEntity.balance >= 0 ? .toReceive : .toGive
                                    showingBalanceEditSheet = true
                                }
                            )
                            
                            // Other Currency Balance Cards
                            ForEach(Array(currencyBalances.keys.sorted()), id: \.self) { currency in
                                if let balance = currencyBalances[currency], abs(balance) >= 0.01 {
                                    balanceCard(
                                        amount: balance,
                                        currency: currency,
                                        fullWidth: false,
                                        onEdit: {
                                            editingBalanceCurrency = currency
                                            balanceEditValue = String(format: "%.2f", abs(balance))
                                            balanceEditType = balance >= 0 ? .toReceive : .toGive
                                            showingBalanceEditSheet = true
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    }
                }
            }
        }
        
        // Enhanced balance card component
        private func balanceCard(amount: Double, currency: String, fullWidth: Bool, onEdit: @escaping () -> Void) -> some View {
            let balanceColor = getBalanceColor(amount)
            let symbol = currency == "CAD" ? "$" : getCurrencySymbol(for: currency)
            
            return VStack(alignment: .leading, spacing: 8) {
                // Currency label
                HStack(spacing: 5) {
                    Text(currency)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    if amount > 0 {
                        Text("To Receive")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.9))
                            )
                    } else if amount < 0 {
                        Text("To Give")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.9))
                            )
                    }
                }
                
                // Amount with larger font
                Text("\(symbol)\(String(format: "%.2f", abs(amount)))")
                    .font(.system(size: fullWidth ? 24 : 20, weight: .bold, design: .rounded))
                    .foregroundColor(balanceColor)
                
                // Description
                Text(getBalanceDescription(amount))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(balanceColor.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .padding(.top, -4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: fullWidth ? nil : 150)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.systemBackground)
                    .shadow(color: balanceColor.opacity(0.1), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(balanceColor.opacity(0.2), lineWidth: 1)
            )
            .overlay(
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                        .background(Circle().fill(Color.systemBackground))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(6),
                alignment: .bottomTrailing
            )
        }
    
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: abs(amount))) ?? "$0.00"
    }
    
    private func getBalanceColor(_ balance: Double) -> Color {
        if balance > 0 {
            return .green
        } else if balance < 0 {
            return .red
        } else {
            return .secondary
        }
    }
    
    private func getBalanceDescription(_ balance: Double) -> String {
        if balance > 0 {
            return "Amount to Receive"
        } else if balance < 0 {
            return "Amount to Give"
        } else {
            return "No Balance"
        }
    }
    
    private func setupListener() {
        let db = Firestore.firestore()
        
        listener = db.collection(entityType.collectionName)
            .document(entity.id)
            .addSnapshotListener { documentSnapshot, error in
                
                if let error = error {
                    print("Error listening to entity changes: \(error)")
                    return
                }
                
                guard let document = documentSnapshot, document.exists else {
                    print("Entity document does not exist")
                    return
                }
                
                let data = document.data() ?? [:]
                
                // Update current entity with real-time data
                let updatedEntity = EntityProfile(
                    id: document.documentID,
                    name: data["name"] as? String ?? "",
                    phone: data["phone"] as? String ?? "",
                    email: data["email"] as? String ?? "",
                    balance: data["balance"] as? Double ?? 0.0,
                    address: data["address"] as? String ?? "",
                    notes: data["notes"] as? String ?? ""
                )
                
                currentEntity = updatedEntity
            }
    }
    
    private func removeListener() {
        listener?.remove()
        listener = nil
    }
    
    private func removeTransactionFromList(id: String) {
        print("🗑️ Removing transaction from local list: \(id)")
        withAnimation {
            transactions.removeAll { $0.id == id }
            balanceAdjustments.removeAll { $0.id == id }
        }
        print("✅ Transaction removed from list. Remaining transactions: \(transactions.count), balance adjustments: \(balanceAdjustments.count)")
    }
    
    // MARK: - Fetch Transactions
    private func fetchTransactions() {
        isLoadingTransactions = true
        transactionError = nil
        
        Task {
            do {
                let db = Firestore.firestore()
                let entityDoc = try await db.collection(entityType.collectionName)
                    .document(entity.id)
                    .getDocument()
                
                guard let data = entityDoc.data() else {
                    await MainActor.run {
                        isLoadingTransactions = false
                    }
                    return
                }
                
                let transactionHistory = data["transactionHistory"] as? [[String: Any]] ?? []
                print("📜 Found \(transactionHistory.count) transaction references for \(entity.name)")
                
                // OPTIMIZATION: Fetch all transactions in parallel instead of sequentially
                let fetchedTransactions = try await withThrowingTaskGroup(of: [EntityTransaction].self) { group in
                    // Add task for currency transactions (runs in parallel)
                    group.addTask {
                        return try await self.fetchCurrencyTransactions()
                    }
                    
                    // Add tasks for purchase/sales transactions (all run in parallel)
                    for txHistoryItem in transactionHistory {
                        let role = txHistoryItem["role"] as? String ?? ""
                        let timestamp = txHistoryItem["timestamp"] as? Timestamp
                        
                        if let purchaseRef = txHistoryItem["purchaseReference"] as? DocumentReference {
                            group.addTask {
                                if let transaction = try await self.fetchPurchaseTransaction(ref: purchaseRef, role: role, timestamp: timestamp) {
                                    return [transaction]
                                }
                                return []
                            }
                        }
                        
                        if let salesRef = txHistoryItem["salesReference"] as? DocumentReference {
                            group.addTask {
                                if let transaction = try await self.fetchSalesTransaction(ref: salesRef, role: role, timestamp: timestamp) {
                                    return [transaction]
                                }
                                return []
                            }
                        }
                    }
                    
                    // Collect all results
                    var allTransactions: [EntityTransaction] = []
                    var seenIDs: Set<String> = []
                    for try await transactions in group {
                        for transaction in transactions {
                            // Deduplicate by ID to avoid duplicates
                            if !seenIDs.contains(transaction.id) {
                                allTransactions.append(transaction)
                                seenIDs.insert(transaction.id)
                            }
                        }
                    }
                    return allTransactions
                }
                
                let sortedTransactions = fetchedTransactions.sorted { $0.date > $1.date }
                
                await MainActor.run {
                    self.transactions = sortedTransactions
                    self.isLoadingTransactions = false
                    print("✅ Loaded \(sortedTransactions.count) total transactions")
                }
                
            } catch {
                await MainActor.run {
                    self.transactionError = error.localizedDescription
                    self.isLoadingTransactions = false
                    print("❌ Error loading transactions: \(error)")
                }
            }
        }
    }
    
    private func fetchPurchaseTransaction(ref: DocumentReference, role: String, timestamp: Timestamp?) async throws -> EntityTransaction? {
        let doc = try await ref.getDocument()
        guard let data = doc.data() else { return nil }
        
        let purchasedPhones = data["purchasedPhones"] as? [[String: Any]] ?? []
        let services = data["services"] as? [[String: Any]] ?? []
        let paymentMethods = data["paymentMethods"] as? [String: Any] ?? [:]
        let middlemanPayment = data["middlemanPayment"] as? [String: Any] ?? [:]
        let middlemanPaymentSplit = middlemanPayment["paymentSplit"] as? [String: Any] ?? [:]
        
        let transactionType: EntityTransactionType
        if role == "supplier" {
            transactionType = .purchase
        } else if role == "middleman" {
            transactionType = .middleman
        } else {
            transactionType = .purchase
        }
        
        return EntityTransaction(
            id: doc.documentID,
            type: transactionType,
            date: (data["transactionDate"] as? Timestamp)?.dateValue() ?? timestamp?.dateValue() ?? Date(),
            amount: data["grandTotal"] as? Double ?? 0.0,
            role: role,
            orderNumber: data["orderNumber"] as? Int,
            grandTotal: data["grandTotal"] as? Double,
            paid: paymentMethods["totalPaid"] as? Double,
            credit: paymentMethods["remainingCredit"] as? Double,
            gstAmount: data["gstAmount"] as? Double,
            pstAmount: data["pstAmount"] as? Double,
            notes: data["notes"] as? String,
            itemCount: purchasedPhones.count + services.count,
            cashPaid: paymentMethods["cash"] as? Double,
            bankPaid: paymentMethods["bank"] as? Double,
            creditCardPaid: paymentMethods["creditCard"] as? Double,
            middlemanCash: middlemanPaymentSplit["cash"] as? Double,
            middlemanBank: middlemanPaymentSplit["bank"] as? Double,
            middlemanCreditCard: middlemanPaymentSplit["creditCard"] as? Double,
            middlemanCredit: middlemanPaymentSplit["credit"] as? Double,
            middlemanUnit: middlemanPayment["unit"] as? String,
            middlemanName: data["middlemanName"] as? String,
            sourceCollection: "Purchases" // Track source for color coding
        )
    }
    
    private func fetchSalesTransaction(ref: DocumentReference, role: String, timestamp: Timestamp?) async throws -> EntityTransaction? {
        let doc = try await ref.getDocument()
        guard let data = doc.data() else { return nil }
        
        let soldPhones = data["soldPhones"] as? [[String: Any]] ?? []
        let services = data["services"] as? [[String: Any]] ?? []
        let paymentMethods = data["paymentMethods"] as? [String: Any] ?? [:]
        let middlemanPayment = data["middlemanPayment"] as? [String: Any] ?? [:]
        let middlemanPaymentSplit = middlemanPayment["paymentSplit"] as? [String: Any] ?? [:]
        
        let transactionType: EntityTransactionType
        if role == "customer" {
            transactionType = .sale
        } else if role == "middleman" {
            transactionType = .middleman
        } else {
            transactionType = .sale
        }
        
        return EntityTransaction(
            id: doc.documentID,
            type: transactionType,
            date: (data["transactionDate"] as? Timestamp)?.dateValue() ?? timestamp?.dateValue() ?? Date(),
            amount: data["grandTotal"] as? Double ?? 0.0,
            role: role,
            orderNumber: data["orderNumber"] as? Int,
            grandTotal: data["grandTotal"] as? Double,
            paid: paymentMethods["totalPaid"] as? Double,
            credit: paymentMethods["remainingCredit"] as? Double,
            gstAmount: data["gstAmount"] as? Double,
            pstAmount: data["pstAmount"] as? Double,
            notes: data["notes"] as? String,
            itemCount: soldPhones.count + services.count,
            cashPaid: paymentMethods["cash"] as? Double,
            bankPaid: paymentMethods["bank"] as? Double,
            creditCardPaid: paymentMethods["creditCard"] as? Double,
            middlemanCash: middlemanPaymentSplit["cash"] as? Double,
            middlemanBank: middlemanPaymentSplit["bank"] as? Double,
            middlemanCreditCard: middlemanPaymentSplit["creditCard"] as? Double,
            middlemanCredit: middlemanPaymentSplit["credit"] as? Double,
            middlemanUnit: middlemanPayment["unit"] as? String,
            middlemanName: data["middlemanName"] as? String,
            sourceCollection: "Sales" // Track source for color coding
        )
    }
    
    private func fetchCurrencyTransactions() async throws -> [EntityTransaction] {
        let db = Firestore.firestore()
        
        // OPTIMIZATION: Fetch both queries in parallel using async let
        async let giverDocs = db.collection("CurrencyTransactions")
            .whereField("giver", isEqualTo: entity.id)
            .whereField("isExchange", isEqualTo: false)
            .getDocuments()
        
        async let takerDocs = db.collection("CurrencyTransactions")
            .whereField("taker", isEqualTo: entity.id)
            .whereField("isExchange", isEqualTo: false)
            .getDocuments()
        
        // Wait for both queries to complete
        let (giverSnapshot, takerSnapshot) = try await (giverDocs, takerDocs)
        
        var currencyTransactions: [EntityTransaction] = []
        
        // Process giver transactions
        for doc in giverSnapshot.documents {
            let data = doc.data()
            
            let transaction = EntityTransaction(
                id: doc.documentID,
                type: .currencyRegular,
                date: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                amount: data["amount"] as? Double ?? 0.0,
                role: "giver",
                orderNumber: nil,
                grandTotal: nil,
                paid: nil,
                credit: nil,
                gstAmount: nil,
                pstAmount: nil,
                notes: data["notes"] as? String,
                itemCount: nil,
                cashPaid: nil,
                bankPaid: nil,
                creditCardPaid: nil,
                middlemanCash: nil,
                middlemanBank: nil,
                middlemanCreditCard: nil,
                middlemanCredit: nil,
                middlemanUnit: nil,
                middlemanName: nil,
                sourceCollection: nil, // Currency transactions don't have a source collection
                currencyGiven: data["currencyGiven"] as? String,
                currencyName: data["currencyName"] as? String,
                giver: data["giver"] as? String,
                giverName: data["giverName"] as? String,
                taker: data["taker"] as? String,
                takerName: data["takerName"] as? String,
                isExchange: false,
                receivingCurrency: nil,
                receivedAmount: nil,
                customExchangeRate: nil,
                balancesAfterTransaction: data["balancesAfterTransaction"] as? [String: Any]
            )
            
            currencyTransactions.append(transaction)
        }
        
        // Process taker transactions
        for doc in takerSnapshot.documents {
            let data = doc.data()
            
            let transaction = EntityTransaction(
                id: doc.documentID,
                type: .currencyRegular,
                date: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                amount: data["amount"] as? Double ?? 0.0,
                role: "taker",
                orderNumber: nil,
                grandTotal: nil,
                paid: nil,
                credit: nil,
                gstAmount: nil,
                pstAmount: nil,
                notes: data["notes"] as? String,
                itemCount: nil,
                cashPaid: nil,
                bankPaid: nil,
                creditCardPaid: nil,
                middlemanCash: nil,
                middlemanBank: nil,
                middlemanCreditCard: nil,
                middlemanCredit: nil,
                middlemanUnit: nil,
                middlemanName: nil,
                sourceCollection: nil, // Currency transactions don't have a source collection
                currencyGiven: data["currencyGiven"] as? String,
                currencyName: data["currencyName"] as? String,
                giver: data["giver"] as? String,
                giverName: data["giverName"] as? String,
                taker: data["taker"] as? String,
                takerName: data["takerName"] as? String,
                isExchange: false,
                receivingCurrency: nil,
                receivedAmount: nil,
                customExchangeRate: nil,
                balancesAfterTransaction: data["balancesAfterTransaction"] as? [String: Any]
            )
            
            currencyTransactions.append(transaction)
        }
        
        return currencyTransactions
    }
    
    private func fetchBalanceAdjustments() {
        Task {
            do {
                let db = Firestore.firestore()
                
                // Fetch balance adjustments for this entity (no orderBy to avoid index requirement)
                let snapshot = try await db.collection("BalanceAdjustments")
                    .whereField("entityId", isEqualTo: entity.id)
                    .getDocuments()
                
                var adjustments: [EntityTransaction] = []
                
                for doc in snapshot.documents {
                    let data = doc.data()
                    
                    let timestamp = data["timestamp"] as? Timestamp
                    let date = timestamp?.dateValue() ?? Date()
                    
                    let initialBalance = data["initialBalance"] as? Double ?? 0.0
                    let finalBalance = data["finalBalance"] as? Double ?? 0.0
                    let currency = data["currency"] as? String ?? "CAD"
                    let adjustmentType = data["adjustmentType"] as? String ?? "To Receive"
                    
                    // Create transaction from balance adjustment
                    let transaction = EntityTransaction(
                        id: doc.documentID,
                        type: .balanceAdjustment,
                        date: date,
                        amount: finalBalance,
                        role: "balance_adjustment",
                        orderNumber: nil,
                        grandTotal: nil,
                        paid: nil,
                        credit: nil,
                        gstAmount: nil,
                        pstAmount: nil,
                        notes: "Balance adjusted from \(String(format: "%.2f", initialBalance)) to \(String(format: "%.2f", finalBalance)) (\(adjustmentType))",
                        itemCount: nil,
                        cashPaid: nil,
                        bankPaid: nil,
                        creditCardPaid: nil,
                        middlemanCash: nil,
                        middlemanBank: nil,
                        middlemanCreditCard: nil,
                        middlemanCredit: nil,
                        middlemanUnit: nil,
                        middlemanName: nil,
                        sourceCollection: nil,
                        currencyGiven: currency,
                        currencyName: currency,
                        giver: nil,
                        giverName: nil,
                        taker: nil,
                        takerName: nil,
                        isExchange: nil,
                        receivingCurrency: nil,
                        receivedAmount: nil,
                        customExchangeRate: nil,
                        balancesAfterTransaction: [
                            "initialBalance": initialBalance,
                            "finalBalance": finalBalance,
                            "adjustmentAmount": finalBalance - initialBalance,
                            "adjustmentType": adjustmentType,
                            "currency": currency,
                            "entityId": data["entityId"] as? String ?? "",
                            "entityType": data["entityType"] as? String ?? ""
                        ]
                    )
                    
                    adjustments.append(transaction)
                }
                
                // Sort by date descending (newest first) in memory
                let sortedAdjustments = adjustments.sorted { $0.date > $1.date }
                
                await MainActor.run {
                    self.balanceAdjustments = sortedAdjustments
                    print("✅ Loaded \(sortedAdjustments.count) balance adjustments")
                }
                
            } catch {
                print("❌ Error loading balance adjustments: \(error)")
            }
        }
    }
    
    private func fetchCurrencyBalances() {
        guard !entity.id.isEmpty else { return }
        
        let db = Firestore.firestore()
        db.collection("CurrencyBalances").document(entity.id).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error fetching currency balances for \(entity.name): \(error.localizedDescription)")
                return
            }
            
            if let data = snapshot?.data() {
                var balances: [String: Double] = [:]
                
                for (key, value) in data {
                    if key != "updatedAt" && key != "createdAt", let doubleValue = value as? Double {
                        balances[key] = doubleValue
                    }
                }
                
                DispatchQueue.main.async {
                    self.currencyBalances = balances
                    print("💰 Loaded currency balances for \(entity.name): \(balances)")
                }
            }
        }
    }
    
    private func getCurrencySymbol(for currencyName: String) -> String {
        return currencyManager.allCurrencies.first { $0.name == currencyName }?.symbol ?? currencyName
    }
    
    // Get all transactions for ledger (excludes balance adjustments, sorted chronologically)
    private func getAllTransactionsForLedger() -> [EntityTransaction] {
        // Combine all transaction types: purchases, sales, currency (exclude balance adjustments)
        let allTransactions = transactions.filter { $0.type != .balanceAdjustment }
        
        // Sort chronologically (oldest first for ledger)
        let sorted = allTransactions.sorted { $0.date < $1.date }
        
        return sorted
    }
    
    var balanceEditSheet: some View {
        VStack(spacing: 24) {
            balanceEditHeader
            balanceEditCurrencySection
            balanceEditTypeSelection
            balanceEditInputSection
            Spacer()
            balanceEditSaveButton
        }
        .frame(maxWidth: 500, maxHeight: 500)
        .background(Color.systemBackground)
        .cornerRadius(20)
    }
    
    // MARK: - Balance Edit Sheet Components
    private var balanceEditHeader: some View {
        HStack {
            Text("Edit Balance")
                .font(.system(size: 24, weight: .bold))
            
            Spacer()
            
            Button(action: {
                showingBalanceEditSheet = false
            }) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var balanceEditCurrencySection: some View {
        HStack(spacing: 10) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                )
            
            Text(editingBalanceCurrency == nil ? "CAD" : editingBalanceCurrency!)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
    }
    
    private var balanceEditTypeSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Balance Type")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
            
            HStack(spacing: 12) {
                ForEach(BalanceEditType.allCases, id: \.self) { type in
                    balanceEditTypeButton(type: type)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func balanceEditTypeButton(type: BalanceEditType) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                balanceEditType = type
            }
        }) {
            VStack(spacing: 8) {
                Image(systemName: balanceEditType == type ?
                      (type == .toReceive ? "arrow.down.circle.fill" : "arrow.up.circle.fill") :
                      (type == .toReceive ? "arrow.down.circle" : "arrow.up.circle"))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(balanceEditType == type ? type.color : .secondary)
                
                Text(type.rawValue)
                    .font(.system(size: 16, weight: balanceEditType == type ? .semibold : .medium))
                    .foregroundColor(balanceEditType == type ? type.color : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(balanceEditType == type ?
                         type.color.opacity(0.1) :
                         Color.tertiarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(balanceEditType == type ?
                           type.color.opacity(0.4) :
                           Color.gray.opacity(0.1), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var balanceEditInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Amount")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            HStack(spacing: 14) {
                Text(editingBalanceCurrency == nil ? "$" : getCurrencySymbol(for: editingBalanceCurrency!))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                TextField("0.00", text: $balanceEditValue)
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
    }
    
    private var balanceEditSaveButton: some View {
        Button(action: {
            Task {
                await updateBalance()
            }
        }) {
            HStack(spacing: 12) {
                if isUpdatingBalance {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .tint(.white)
                    
                    Text("Updating...")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                    
                    Text("Save Balance")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 3)
                    .opacity(isUpdatingBalance || balanceEditValue.isEmpty ? 0.6 : 1)
            )
        }
        .disabled(isUpdatingBalance || balanceEditValue.isEmpty)
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    
    private func updateBalance() async {
        guard let balanceValue = Double(balanceEditValue) else { return }
        
        isUpdatingBalance = true
        
        var finalBalance = balanceEditType == .toReceive ? abs(balanceValue) : -abs(balanceValue)
        
        do {
            let db = Firestore.firestore()
            
            // Get initial balance before updating
            var initialBalance: Double = 0.0
            let currency = editingBalanceCurrency ?? "CAD"
            
            if editingBalanceCurrency == nil {
                // Get current CAD balance from entity
                initialBalance = currentEntity.balance
            } else {
                // Get current currency balance
                initialBalance = currencyBalances[editingBalanceCurrency!] ?? 0.0
            }
            
            if editingBalanceCurrency == nil {
                // Update CAD balance in entity collection
                try await db.collection(entityType.collectionName)
                    .document(entity.id)
                    .updateData(["balance": finalBalance, "updatedAt": Timestamp()])
                
                print("✅ Updated CAD balance to \(finalBalance)")
            } else {
                // Update currency balance in CurrencyBalances collection
                let currencyBalanceRef = db.collection("CurrencyBalances").document(entity.id)
                
                // Check if document exists
                let snapshot = try await currencyBalanceRef.getDocument()
                
                if snapshot.exists {
                    // Update existing
                    try await currencyBalanceRef.updateData([
                        editingBalanceCurrency!: finalBalance,
                        "updatedAt": Timestamp()
                    ])
                } else {
                    // Create new document
                    try await currencyBalanceRef.setData([
                        editingBalanceCurrency!: finalBalance,
                        "createdAt": Timestamp(),
                        "updatedAt": Timestamp()
                    ])
                }
                
                print("✅ Updated \(editingBalanceCurrency!) balance to \(finalBalance)")
            }
            
            // Store balance adjustment history
            let adjustmentData: [String: Any] = [
                "entityId": entity.id,
                "entityType": entityType.rawValue,
                "entityName": currentEntity.name,
                "currency": currency,
                "initialBalance": initialBalance,
                "finalBalance": finalBalance,
                "adjustmentAmount": finalBalance - initialBalance,
                "adjustmentType": balanceEditType.rawValue,
                "timestamp": Timestamp(),
                "createdAt": Timestamp()
            ]
            
            try await db.collection("BalanceAdjustments").addDocument(data: adjustmentData)
            print("✅ Stored balance adjustment history: \(currency) from \(initialBalance) to \(finalBalance)")
            
            // Refresh data
            await MainActor.run {
                isUpdatingBalance = false
                showingBalanceEditSheet = false
                fetchCurrencyBalances()
            }
            
        } catch {
            print("❌ Error updating balance: \(error.localizedDescription)")
            await MainActor.run {
                isUpdatingBalance = false
            }
        }
    }
}

struct EntityTransactionRowView: View {
    let transaction: EntityTransaction
    let entityType: EntityType
    var onTransactionDeleted: ((String) -> Void)?
    var onViewBill: ((String, Bool) -> Void)?
    
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError = ""
    @State private var showingTransactionDetail = false
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    
    private var isCompact: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    // MARK: - Credit Color Logic
    private func getCreditColor() -> Color {
        switch transaction.type {
        case .sale:
            // Sale: Credit is always green (customer owes me money)
            return .green
        case .purchase:
            // Purchase: Credit is always red (I have to pay)
            return .red
        case .expense:
            // Expense: always red (money going out)
            return .red
        case .middleman:
            // Middleman: Based on source collection (Purchases or Sales)
            // For Paid/Credit columns: use sale/purchase logic
            if let source = transaction.sourceCollection {
                if source == "Sales" {
                    return .green // Sale: customer owes me money
                } else if source == "Purchases" {
                    return .red // Purchase: I have to pay
                }
            }
            return .orange // Default fallback
        default:
            return .orange // Default for other transaction types
        }
    }
    
    // MARK: - Credit Tag Logic
    private func getCreditTag() -> String {
        let color = getCreditColor()
        return color == .red ? "(To Pay)" : "(To Get)"
    }
    
    // MARK: - Paid Color and Sign Logic
    private func getPaidColor() -> Color {
        switch transaction.type {
        case .sale:
            // Sale: always green with + sign
            return .green
        case .purchase:
            // Purchase: always red with - sign
            return .red
        case .expense:
            // Expense: always red with - sign (money going out)
            return .red
        case .middleman:
            // Middleman: based on source collection (Purchases or Sales)
            // For Paid column: use sale/purchase logic
            if let source = transaction.sourceCollection {
                if source == "Sales" {
                    return .green // + sign (sale)
                } else if source == "Purchases" {
                    return .red // - sign (purchase)
                }
            }
            return .orange // Default fallback
        case .currencyRegular, .currencyExchange:
            // Currency transactions: green if To is myself bank or myself cash, red if From is myself bank or myself cash
            let taker = transaction.taker ?? ""
            let giver = transaction.giver ?? ""
            
            if taker == "myself_special_id" || taker == "myself_bank_special_id" {
                return .green // + sign (money coming to me)
            } else if giver == "myself_special_id" || giver == "myself_bank_special_id" {
                return .red // - sign (money going from me)
            } else {
                return .orange // Other color for all other cases
            }
        case .balanceAdjustment:
            // Balance adjustments: green if To Receive, red if To Give
            if let balances = transaction.balancesAfterTransaction,
               let adjustmentType = balances["adjustmentType"] as? String {
                return adjustmentType == "To Receive" ? .green : .red
            }
            return .indigo // Default fallback
        }
    }
    
    private func getPaidSign() -> String {
        let color = getPaidColor()
        return color == .green ? "+" : "-"
    }
    
    // MARK: - Middleman Column Color and Sign Logic (based on unit field)
    private func getMiddlemanColor() -> Color {
        if let unit = transaction.middlemanUnit {
            return (unit == "give") ? .red : .green
        } else {
            return .orange // Default fallback
        }
    }
    
    private func getMiddlemanSign() -> String {
        let color = getMiddlemanColor()
        return color == .green ? "+" : "-"
    }
    
    var body: some View {
        Group {
            if isCompact {
                compactTransactionRow
            } else {
                fullTransactionRow
            }
        }
        .sheet(isPresented: $showingTransactionDetail) {
            if isCompact {
                transactionDetailSheet
            } else {
                EmptyView()
            }
        }
        .alert("Delete Transaction", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                print("🚫 Delete cancelled by user")
            }
            Button("Delete", role: .destructive) {
                print("🗑️ Delete confirmed by user, calling deleteTransaction()")
                deleteTransaction()
            }
        } message: {
            if transaction.type == .balanceAdjustment {
                let balances = transaction.balancesAfterTransaction ?? [:]
                let initialBalance = balances["initialBalance"] as? Double ?? 0.0
                let finalBalance = balances["finalBalance"] as? Double ?? transaction.amount
                let adjustmentAmount = balances["adjustmentAmount"] as? Double ?? (finalBalance - initialBalance)
                let currency = transaction.currencyName ?? "CAD"
                let currencySymbol = currency == "CAD" ? "$" : currency
                let adjustmentSign = adjustmentAmount >= 0 ? "+" : ""
                let reverseAdjustment = -adjustmentAmount
                let reverseSign = reverseAdjustment >= 0 ? "+" : ""
                
                return Text("Are you sure you want to reverse this balance adjustment?\n\nAdjustment made: \(adjustmentSign)\(currencySymbol)\(String(format: "%.2f", abs(adjustmentAmount)))\nWill reverse by: \(reverseSign)\(currencySymbol)\(String(format: "%.2f", abs(reverseAdjustment)))\n\nThis will add/subtract the adjustment amount from the current balance.\n\nThis action cannot be undone.")
            } else {
                return Text("Are you sure you want to delete this transaction? This will reverse all balance changes and cannot be undone.")
            }
        }
        .onChange(of: showingDeleteConfirmation) { newValue in
            print("🔔 showingDeleteConfirmation changed to: \(newValue)")
        }
    }
    
    // MARK: - Compact Row Helper Views
    @ViewBuilder
    private var compactAmountDisplay: some View {
        if transaction.type == .middleman {
            compactMiddlemanAmountDisplay
        } else if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
            compactCurrencyAmountDisplay
        } else if transaction.type == .expense {
            compactExpenseAmountDisplay
        } else if transaction.type == .balanceAdjustment {
            compactBalanceAdjustmentAmountDisplay
        } else {
            compactPurchaseSaleAmountDisplay
        }
    }
    
    private var compactMiddlemanAmountDisplay: some View {
        let cash = transaction.middlemanCash ?? 0
        let bank = transaction.middlemanBank ?? 0
        let creditCard = transaction.middlemanCreditCard ?? 0
        let middlemanTotal = cash + bank + creditCard
        let sign = getMiddlemanSign()
        let formattedAmount = formatCurrency(abs(middlemanTotal))
        let text = sign + formattedAmount
        let color = getMiddlemanColor()
        return compactAmountText(
            text: text,
            color: color,
            hasBackground: true
        )
    }
    
    private var compactCurrencyAmountDisplay: some View {
        let sign = getPaidSign()
        let amountString = String(format: "%.2f", transaction.amount)
        let currencyName = transaction.currencyName ?? ""
        let text = sign + " " + amountString + " " + currencyName
        let color = getPaidColor()
        return compactAmountText(
            text: text,
            color: color,
            hasBackground: true
        )
    }
    
    private var compactExpenseAmountDisplay: some View {
        let sign = getPaidSign() // Will return "-" for expenses
        let formattedAmount = formatCurrency(abs(transaction.amount))
        let text = sign + formattedAmount
        let color = getPaidColor() // Will return .red for expenses
        return compactAmountText(
            text: text,
            color: color,
            hasBackground: true
        )
    }
    
    private var compactBalanceAdjustmentAmountDisplay: some View {
        let balances = transaction.balancesAfterTransaction ?? [:]
        let initialBalance = balances["initialBalance"] as? Double ?? 0.0
        let finalBalance = balances["finalBalance"] as? Double ?? transaction.amount
        let currency = transaction.currencyName ?? "CAD"
        let currencySymbol = currency == "CAD" ? "$" : currency
        
        let initialSign = initialBalance < 0 ? "-" : ""
        let finalSign = finalBalance < 0 ? "-" : ""
        let initialText = "\(initialSign)\(currencySymbol)\(String(format: "%.2f", abs(initialBalance)))"
        let finalText = "\(finalSign)\(currencySymbol)\(String(format: "%.2f", abs(finalBalance)))"
        let text = "\(initialText) → \(finalText)"
        let color = getPaidColor()
        
        // Large format display for balance adjustments
        return Text(text)
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(color)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
    }
    
    private var compactPurchaseSaleAmountDisplay: some View {
        let text = formatCurrency(transaction.amount)
        return compactAmountText(
            text: text,
            color: .primary,
            hasBackground: false
        )
    }
    
    private func compactAmountText(text: String, color: Color, hasBackground: Bool) -> some View {
        Group {
            if hasBackground {
                Text(text)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(color.opacity(0.2), lineWidth: 1)
                    )
            } else {
                Text(text)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
        }
    }
    
    @ViewBuilder
    private var compactRightBadge: some View {
        if transaction.type == .middleman, let middlemanName = transaction.middlemanName {
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11))
                    .foregroundColor(transaction.type.color)
                Text(middlemanName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(transaction.type.color.opacity(0.1))
            )
        } else if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
            HStack(spacing: 4) {
                Text(transaction.giverName ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(Color.blue)
                Text(transaction.takerName ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            )
        } else if transaction.type == .balanceAdjustment {
            HStack(spacing: 4) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(transaction.type.color)
                Text(transaction.currencyName == "CAD" ? "$" : (transaction.currencyName ?? "$"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(transaction.type.color.opacity(0.1))
            )
        } else if transaction.type == .expense {
            // For expenses, show category or notes
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 11))
                    .foregroundColor(transaction.type.color)
                Text(transaction.notes ?? "Expense")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(transaction.type.color.opacity(0.1))
            )
        } else if let orderNum = transaction.orderNumber {
            Text("Order #\(orderNum)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(transaction.type.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(transaction.type.color.opacity(0.1))
                )
        }
    }
    
    @ViewBuilder
    private var compactMiddlemanDetails: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let middlemanCash = transaction.middlemanCash, middlemanCash > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 13))
                    Text("Cash: \(getMiddlemanSign())\(formatCurrency(abs(middlemanCash)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getMiddlemanColor())
            }
            
            if let middlemanBank = transaction.middlemanBank, middlemanBank > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 13))
                    Text("Bank: \(getMiddlemanSign())\(formatCurrency(abs(middlemanBank)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getMiddlemanColor())
            }
            
            if let middlemanCreditCard = transaction.middlemanCreditCard, middlemanCreditCard > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 13))
                    Text("Card: \(getMiddlemanSign())\(formatCurrency(abs(middlemanCreditCard)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getMiddlemanColor())
            }
            
            if let middlemanCredit = transaction.middlemanCredit, middlemanCredit != 0 {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                    Text("Credit: \(formatCurrency(abs(middlemanCredit)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getMiddlemanColor())
            }
        }
    }
    
    @ViewBuilder
    private var compactExpensePaymentSplit: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let cashPaid = transaction.cashPaid, cashPaid > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 13))
                    Text("Cash: \(getPaidSign())\(formatCurrency(abs(cashPaid)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getPaidColor()) // Will be red for expenses
            }
            
            if let bankPaid = transaction.bankPaid, bankPaid > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 13))
                    Text("Bank: \(getPaidSign())\(formatCurrency(abs(bankPaid)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getPaidColor()) // Will be red for expenses
            }
            
            if let creditCardPaid = transaction.creditCardPaid, creditCardPaid > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 13))
                    Text("Card: \(getPaidSign())\(formatCurrency(abs(creditCardPaid)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getPaidColor()) // Will be red for expenses
            }
        }
    }
    
    @ViewBuilder
    private var compactBalanceAdjustmentDetails: some View {
        VStack(alignment: .trailing, spacing: 5) {
            let balances = transaction.balancesAfterTransaction ?? [:]
            let initialBalance = balances["initialBalance"] as? Double ?? 0.0
            let finalBalance = balances["finalBalance"] as? Double ?? transaction.amount
            let currency = transaction.currencyName ?? "CAD"
            let currencySymbol = currency == "CAD" ? "$" : currency
            
            let initialSign = initialBalance < 0 ? "-" : ""
            let finalSign = finalBalance < 0 ? "-" : ""
            
            HStack(spacing: 5) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 13))
                Text("Initial: \(initialSign)\(currencySymbol)\(String(format: "%.2f", abs(initialBalance)))")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.secondary)
            
            HStack(spacing: 5) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13))
                Text("Final: \(finalSign)\(currencySymbol)\(String(format: "%.2f", abs(finalBalance)))")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(getPaidColor())
        }
    }
    
    @ViewBuilder
    private var compactPaidCreditDetails: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let paid = transaction.paid, paid > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 13))
                    Text("Paid: \(getPaidSign())\(formatCurrency(abs(paid)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getPaidColor())
            }
            
            if let credit = transaction.credit, credit != 0 {
                HStack(spacing: 5) {
                    Image(systemName: credit > 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 13))
                    Text("Credit: \(formatCurrency(abs(credit)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getCreditColor())
            }
        }
    }
    
    // MARK: - Compact Row (iPhone)
    private var compactTransactionRow: some View {
        Button(action: {
            showingTransactionDetail = true
        }) {
            Group {
                if transaction.type == .balanceAdjustment {
                // Simplified layout for balance adjustments
                VStack(alignment: .leading, spacing: 14) {
                    // Top row: Date/Time and Type badge in same row
                    HStack(alignment: .center) {
                        // Date and Time
                        HStack(spacing: 8) {
                            Text(dateFormatter.string(from: transaction.date))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text(timeFormatter.string(from: transaction.date))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Type Badge
                        HStack(spacing: 4) {
                            Image(systemName: transaction.type.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(transaction.type.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(transaction.type.color)
                                .shadow(color: transaction.type.color.opacity(0.3), radius: 2, x: 0, y: 1)
                        )
                    }
                    
                    // Main Amount Section - centered
                    HStack {
                        Spacer()
                        compactAmountDisplay
                        Spacer()
                    }
                    
                    // View Details button at bottom
                    HStack {
                        Spacer()
                        HStack(spacing: 5) {
                            Text("View Details")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                    }
                }
            } else {
                // Original layout for other transaction types
                VStack(alignment: .leading, spacing: 14) {
                    // Top row: Date, Type badge
                    HStack(alignment: .center) {
                        // Date and Time
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dateFormatter.string(from: transaction.date))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text(timeFormatter.string(from: transaction.date))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Type Badge
                        HStack(spacing: 4) {
                            Image(systemName: transaction.type.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(transaction.type.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(transaction.type.color)
                                .shadow(color: transaction.type.color.opacity(0.3), radius: 2, x: 0, y: 1)
                        )
                    }
                    
                    // Main Amount Section
                    HStack(alignment: .center) {
                        compactAmountDisplay
                        
                        Spacer()
                        
                        compactRightBadge
                    }
                    
                    // Transaction Details Section
                    if transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman || transaction.type == .expense {
                    VStack(alignment: .leading, spacing: 8) {
                        // Item count and Paid/Credit row
                        HStack(alignment: .top) {
                            // Show item count (for purchase/sale only)
                            if transaction.type != .middleman && transaction.type != .expense && transaction.type != .balanceAdjustment, let itemCount = transaction.itemCount {
                                HStack(spacing: 5) {
                                    Image(systemName: "shippingbox.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                    Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // Show category for expenses (if available in notes, or show expense type)
                            if transaction.type == .expense {
                                // Category will be shown in entityName, so we don't need to show it here
                                // But we can show notes if available
                            }
                            
                            Spacer()
                            
                            // Middleman details, Expense payment split, or Paid/Credit info
                            if transaction.type == .middleman {
                                compactMiddlemanDetails
                            } else if transaction.type == .expense {
                                compactExpensePaymentSplit
                            } else {
                                compactPaidCreditDetails
                            }
                        }
                        
                        // Divider before Notes/View Details
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Notes and View Details in same row
                        if true {
                            if let notes = transaction.notes, !notes.isEmpty {
                                HStack(alignment: .center) {
                                    HStack(spacing: 5) {
                                        Text("Notes:")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.secondary)
                                        Text(notes)
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                    .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 5) {
                                        Text("View Details")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.blue)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.blue)
                                    }
                                }
                            } else {
                                // View Details when no notes
                                HStack {
                                    Spacer()
                                    HStack(spacing: 5) {
                                        Text("View Details")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.blue)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    } else {
                        // For non-purchase/sale transactions, just show View Details
                        HStack {
                            Spacer()
                            HStack(spacing: 5) {
                                Text("View Details")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.blue)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
                    .shadow(color: Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.08), radius: 6, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.vertical, 4)
    }
    
    // MARK: - Transaction Detail Sheet (iPhone)
    private var transactionDetailSheet: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    transactionDetailContent
                }
                .padding(.bottom, 30)
            }
            .navigationTitle("Transaction Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingTransactionDetail = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            #endif
        }
    }
    
    @ViewBuilder
    private var transactionDetailContent: some View {
        // Header Section with enhanced visuals
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dateFormatter.string(from: transaction.date))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(timeFormatter.string(from: transaction.date))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Transaction type badge with enhanced styling
                HStack(spacing: 6) {
                    Image(systemName: transaction.type.icon)
                        .font(.system(size: 14, weight: .medium))
                    Text(transaction.type.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(transaction.type.color)
                        .shadow(color: transaction.type.color.opacity(0.3), radius: 2, x: 0, y: 2)
                )
            }
            
            Divider()
            
            // Main Amount with enhanced styling
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Amount")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
                    let currency = transaction.currencyName ?? ""
                    let currencySymbol = currency == "CAD" ? "$" : currency
                    Text("\(getPaidSign()) \(String(format: "%.2f", transaction.amount)) \(currencySymbol)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(getPaidColor())
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(getPaidColor().opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(getPaidColor().opacity(0.2), lineWidth: 1)
                        )
                } else if transaction.type == .balanceAdjustment {
                    let balances = transaction.balancesAfterTransaction ?? [:]
                    let initialBalance = balances["initialBalance"] as? Double ?? 0.0
                    let finalBalance = balances["finalBalance"] as? Double ?? transaction.amount
                    let currency = transaction.currencyName ?? "CAD"
                    let currencySymbol = currency == "CAD" ? "$" : currency
                    let initialSign = initialBalance < 0 ? "-" : ""
                    let finalSign = finalBalance < 0 ? "-" : ""
                    Text("\(initialSign)\(currencySymbol)\(String(format: "%.2f", abs(initialBalance))) → \(finalSign)\(currencySymbol)\(String(format: "%.2f", abs(finalBalance)))")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(getPaidColor())
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(getPaidColor().opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(getPaidColor().opacity(0.2), lineWidth: 1)
                        )
                } else {
                    Text(formatCurrency(transaction.amount))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        
        // Order/Transaction Details in card-style
        detailsCard
        
        // Action Buttons with enhanced styling
        actionButtons
    }
    
    // Extracted details card with improved styling
    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Transaction Details Section
            Group {
                if transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman {
                    // Purchase/Sale specific details
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(title: "Transaction Details", icon: "doc.text.fill")
                        
                        if let orderNum = transaction.orderNumber {
                            detailRow(label: "Order Number", value: "#\(orderNum)", color: transaction.type.color, icon: "number")
                        }
                        
                        detailRow(label: "Role", value: transaction.role.capitalized, color: nil, icon: "person.fill")
                        
                        if let itemCount = transaction.itemCount {
                            detailRow(label: "Items", value: "\(itemCount)", color: nil, icon: "shippingbox.fill")
                        }
                    }
                } else if transaction.type == .expense {
                    // Expense transaction details
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(title: "Expense Details", icon: "arrow.down.circle.fill")
                        
                        // Category is shown as entityName in the header, so we show notes here if available
                        if let notes = transaction.notes, !notes.isEmpty {
                            detailRow(label: "Notes", value: notes, color: nil, icon: "note.text")
                        }
                    }
                } else if transaction.type == .balanceAdjustment {
                    // Balance adjustment details
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(title: "Balance Adjustment Details", icon: "pencil.circle.fill")
                        
                        let balances = transaction.balancesAfterTransaction ?? [:]
                        let initialBalance = balances["initialBalance"] as? Double ?? 0.0
                        let finalBalance = balances["finalBalance"] as? Double ?? transaction.amount
                        let currency = transaction.currencyName ?? "CAD"
                        let currencySymbol = currency == "CAD" ? "$" : currency
                        
                        let initialSign = initialBalance < 0 ? "-" : ""
                        let finalSign = finalBalance < 0 ? "-" : ""
                        
                        detailRow(label: "Initial Balance", value: "\(initialSign)\(currencySymbol)\(String(format: "%.2f", abs(initialBalance)))", color: .secondary, icon: "arrow.left")
                        detailRow(label: "Final Balance", value: "\(finalSign)\(currencySymbol)\(String(format: "%.2f", abs(finalBalance)))", color: getPaidColor(), icon: "arrow.right")
                    }
                } else {
                    // Currency transaction details
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(title: "Transaction Details", icon: "banknote.fill")
                        
                        if let giverName = transaction.giverName {
                            detailRow(label: "From", value: giverName, color: nil, icon: "arrow.up.right")
                        }
                        
                        if let takerName = transaction.takerName {
                            detailRow(label: "To", value: takerName, color: nil, icon: "arrow.down.left")
                        }
                        
                        if transaction.type == .currencyExchange, let receivingCurrency = transaction.receivingCurrency,
                           let receivedAmount = transaction.receivedAmount {
                            detailRow(label: "Received", value: "\(String(format: "%.2f", receivedAmount)) \(receivingCurrency)", color: .green, icon: "arrow.left.arrow.right.circle.fill")
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
            
            // Payment Details Section for purchases/sales/expenses
            if (transaction.type == .purchase || transaction.type == .sale || transaction.type == .expense) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(title: transaction.type == .expense ? "Expense Payment" : "Payment Details", icon: "dollarsign.circle.fill")
                    
                    if transaction.type == .expense {
                        // For expenses, show paid amount (sum of cash + bank + credit card)
                        let paidAmount = transaction.paid ?? 0.0
                        detailRow(
                            label: "Total Paid",
                            value: "\(getPaidSign())\(formatCurrency(abs(paidAmount)))",
                            color: getPaidColor(), // Red for expenses
                            icon: "checkmark.circle.fill"
                        )
                    } else {
                        if let paid = transaction.paid, paid > 0 {
                            detailRow(
                                label: "Paid",
                                value: "\(getPaidSign())\(formatCurrency(abs(paid)))",
                                color: getPaidColor(),
                                icon: "checkmark.circle.fill"
                            )
                        }
                        
                        if let credit = transaction.credit, credit != 0 {
                            detailRow(
                                label: "Credit \(getCreditTag())",
                                value: formatCurrency(abs(credit)),
                                color: getCreditColor(),
                                icon: "exclamationmark.circle.fill"
                            )
                        }
                    }
                    
                    // Payment Methods Breakdown
                    if (transaction.cashPaid ?? 0) > 0 || (transaction.bankPaid ?? 0) > 0 || (transaction.creditCardPaid ?? 0) > 0 {
                        Divider().padding(.vertical, 4)
                        
                        Text("Payment Methods")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.bottom, 4)
                        
                        if let cashPaid = transaction.cashPaid, cashPaid > 0 {
                            if transaction.type == .expense {
                                paymentMethodRow(icon: "banknote.fill", label: "Cash", amount: cashPaid, color: .red, showNegative: true)
                            } else {
                                paymentMethodRow(icon: "banknote.fill", label: "Cash", amount: cashPaid, color: .green)
                            }
                        }
                        
                        if let bankPaid = transaction.bankPaid, bankPaid > 0 {
                            if transaction.type == .expense {
                                paymentMethodRow(icon: "building.columns.fill", label: "Bank", amount: bankPaid, color: .red, showNegative: true)
                            } else {
                                paymentMethodRow(icon: "building.columns.fill", label: "Bank", amount: bankPaid, color: .blue)
                            }
                        }
                        
                        if let creditCardPaid = transaction.creditCardPaid, creditCardPaid > 0 {
                            if transaction.type == .expense {
                                paymentMethodRow(icon: "creditcard.fill", label: "Credit Card", amount: creditCardPaid, color: .red, showNegative: true)
                            } else {
                                paymentMethodRow(icon: "creditcard.fill", label: "Credit Card", amount: creditCardPaid, color: .purple)
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
            }
            
            // Middleman Details Section
            if transaction.middlemanName != nil || (transaction.middlemanCash ?? 0) > 0 || (transaction.middlemanBank ?? 0) > 0 ||
               (transaction.middlemanCreditCard ?? 0) > 0 || (transaction.middlemanCredit ?? 0) != 0 {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(title: "Middleman Details", icon: "person.2.fill")
                    
                    if let middlemanName = transaction.middlemanName {
                        detailRow(label: "Middleman", value: middlemanName, color: nil, icon: "person.crop.circle.fill")
                    }
                    
                    if let middlemanCash = transaction.middlemanCash, middlemanCash > 0 {
                        detailRow(
                            label: "Cash",
                            value: "\(getMiddlemanSign())\(formatCurrency(abs(middlemanCash)))",
                            color: getMiddlemanColor(),
                            icon: "banknote.fill"
                        )
                    }
                    
                    if let middlemanBank = transaction.middlemanBank, middlemanBank > 0 {
                        detailRow(
                            label: "Bank",
                            value: "\(getMiddlemanSign())\(formatCurrency(abs(middlemanBank)))",
                            color: getMiddlemanColor(),
                            icon: "building.columns.fill"
                        )
                    }
                    
                    if let middlemanCreditCard = transaction.middlemanCreditCard, middlemanCreditCard > 0 {
                        detailRow(
                            label: "Credit Card",
                            value: "\(getMiddlemanSign())\(formatCurrency(abs(middlemanCreditCard)))",
                            color: getMiddlemanColor(),
                            icon: "creditcard.fill"
                        )
                    }
                    
                    if let middlemanCredit = transaction.middlemanCredit, middlemanCredit != 0 {
                        let middlemanColor: Color = {
                            if let unit = transaction.middlemanUnit {
                                return (unit == "give") ? .red : .green
                            } else {
                                return .orange
                            }
                        }()
                        let middlemanTag = middlemanColor == .red ? "(To Pay)" : "(To Get)"
                        detailRow(
                            label: "Credit \(middlemanTag)",
                            value: formatCurrency(abs(middlemanCredit)),
                            color: middlemanColor,
                            icon: "exclamationmark.circle.fill"
                        )
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
            }
            
            // Tax Details Section
            if (transaction.gstAmount ?? 0) > 0 || (transaction.pstAmount ?? 0) > 0 {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(title: "Tax Details", icon: "percent")
                    
                    if let gstAmount = transaction.gstAmount, gstAmount > 0 {
                        detailRow(label: "GST", value: formatCurrency(gstAmount), color: nil, icon: "tag.fill")
                    }
                    
                    if let pstAmount = transaction.pstAmount, pstAmount > 0 {
                        detailRow(label: "PST", value: formatCurrency(pstAmount), color: nil, icon: "tag.fill")
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
            }
            
            // Notes Section
            if let notes = transaction.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(title: "Notes", icon: "note.text")
                    
                    Text(notes)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 16)
    }
    
    // Action Buttons with enhanced styling
    private var actionButtons: some View {
        HStack(spacing: 16) {
            // View Bill Button
            if transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman {
                Button(action: {
                    let transactionId = transaction.id
                    let isSale = (transaction.type == .sale) || (transaction.type == .middleman && transaction.sourceCollection == "Sales")
                    // Dismiss sheet and then navigate
                    showingTransactionDetail = false
                    // Use a longer delay to ensure sheet is fully dismissed before navigation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onViewBill?(transactionId, isSale)
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 16))
                        Text("View Bill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue)
                            .shadow(color: Color.blue.opacity(0.4), radius: 4, x: 0, y: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Delete Button
            // Show delete button for currency, purchase, sale, expense (if onTransactionDeleted is provided), or balance adjustment
            if transaction.type == .currencyRegular || transaction.type == .purchase || transaction.type == .sale || 
               (transaction.type == .expense && onTransactionDeleted != nil) || transaction.type == .balanceAdjustment {
                Button(action: {
                    showingTransactionDetail = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingDeleteConfirmation = true
                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                        Text("Delete")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red)
                            .shadow(color: Color.red.opacity(0.4), radius: 4, x: 0, y: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // Helper Views
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                )
            
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.primary)
        }
    }
    
    private func detailRow(label: String, value: String, color: Color?, icon: String? = nil) -> some View {
        HStack {
            // Icon if provided
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color ?? .secondary)
                    .frame(width: 20, alignment: .center)
            }
            
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color ?? .primary)
        }
    }
    
    private func paymentMethodRow(icon: String, label: String, amount: Double, color: Color, showNegative: Bool = false) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 22, alignment: .center)
            
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            
            Spacer()
            
            if showNegative {
                Text("\(getPaidSign())\(formatCurrency(abs(amount)))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color) // Use the provided color (red for expenses)
            } else {
                Text(formatCurrency(amount))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
    
    // MARK: - Full Row (iPad/Mac)
    private var fullTransactionRow: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width, 1)
            let baseWidth: CGFloat = 1468
            let scale = min(availableWidth / baseWidth, 1.1)
            
            let columnPadding = 12 * scale
            let widePadding = 16 * scale
            
            let dateWidth = 140 * scale
            let orderWidth = 160 * scale
            let totalWidth = 110 * scale
            let paidWidth = 100 * scale
            let creditWidth = 100 * scale
            let paymentWidth = 130 * scale
            let middlemanWidthBase = 220 * scale
            let giverWidth = 130 * scale
            let notesWidth = 140 * scale
            let rawButtonWidth = 60 * scale
            let minButtonWidth: CGFloat = 44
            let buttonExtra = max(0, minButtonWidth - rawButtonWidth)
            let buttonWidth = rawButtonWidth + buttonExtra
            let adjustedMiddlemanWidth = max(middlemanWidthBase - (buttonExtra * 2), middlemanWidthBase * 0.3)
            let buttonsColumnWidth = buttonWidth * 2 + max(2, 4 * scale)
            
            HStack(spacing: 0) {
                // Date & Type Column
                VStack(alignment: .leading, spacing: 6) {
                    Text(dateFormatter.string(from: transaction.date))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .minimumScaleFactor(0.75)
                    Text(timeFormatter.string(from: transaction.date))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .minimumScaleFactor(0.75)
                    
                    HStack(spacing: 4) {
                        Image(systemName: transaction.type.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(transaction.type.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, max(6, 8 * scale))
                    .padding(.vertical, max(3, 4 * scale))
                    .background(Capsule().fill(transaction.type.color))
                }
                .frame(width: dateWidth, alignment: .leading)
                .padding(.horizontal, columnPadding)
                
                Divider().frame(height: 70)
                
                // Order/Details Column
                if transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman {
                    VStack(alignment: .leading, spacing: 6) {
                        if let orderNum = transaction.orderNumber {
                            HStack(spacing: 4) {
                                Image(systemName: "number")
                                    .font(.system(size: 10))
                                    .foregroundColor(transaction.type.color)
                                Text("\(orderNum)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(transaction.type.color)
                                    .minimumScaleFactor(0.75)
                            }
                        }
                        
                        if let itemCount = transaction.itemCount {
                            Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .minimumScaleFactor(0.75)
                        }
                        
                        Text(transaction.role.capitalized)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(width: orderWidth, alignment: .leading)
                    .padding(.horizontal, columnPadding)
                } else if transaction.type == .balanceAdjustment {
                    // Column 2: Show initial → final
                    VStack(alignment: .leading, spacing: 6) {
                        let balances = transaction.balancesAfterTransaction ?? [:]
                        let initialBalance = balances["initialBalance"] as? Double ?? 0.0
                        let finalBalance = balances["finalBalance"] as? Double ?? transaction.amount
                        let currency = transaction.currencyName ?? "CAD"
                        let currencySymbol = currency == "CAD" ? "$" : currency
                        
                        let initialSign = initialBalance < 0 ? "-" : ""
                        let finalSign = finalBalance < 0 ? "-" : ""
                        
                        Text("\(initialSign)\(currencySymbol)\(String(format: "%.2f", abs(initialBalance))) → \(finalSign)\(currencySymbol)\(String(format: "%.2f", abs(finalBalance)))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(getPaidColor())
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: orderWidth, alignment: .leading)
                    .padding(.horizontal, columnPadding)
                } else if transaction.type == .expense {
                    // Expense transactions - show category and notes
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 10))
                                .foregroundColor(transaction.type.color)
                            Text(transaction.notes ?? "Expense")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(transaction.type.color)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(width: orderWidth, alignment: .leading)
                    .padding(.horizontal, columnPadding)
                } else {
                    // Currency transactions - show giver → taker
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text(transaction.giverName ?? "")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                            Text(transaction.takerName ?? "")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(width: orderWidth, alignment: .leading)
                    .padding(.horizontal, columnPadding)
                }
                
                Divider().frame(height: 70)
                
                // Total Column
                VStack(alignment: .leading, spacing: 4) {
                    if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
                        Spacer().frame(height: 4 * scale)
                        let currency = transaction.currencyName ?? ""
                        let currencySymbol = currency == "CAD" ? "$" : currency
                        Text("\(getPaidSign())\(String(format: "%.2f", transaction.amount)) \(currencySymbol)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(getPaidColor())
                            .padding(.horizontal, max(4, 6 * scale))
                            .padding(.vertical, max(2, 3 * scale))
                            .background(getPaidColor().opacity(0.08))
                            .cornerRadius(4)
                            .minimumScaleFactor(0.7)
                    } else if transaction.type == .balanceAdjustment {
                        // Column 3: Show initial amount
                        let balances = transaction.balancesAfterTransaction ?? [:]
                        let initialBalance = balances["initialBalance"] as? Double ?? 0.0
                        let currency = transaction.currencyName ?? "CAD"
                        let currencySymbol = currency == "CAD" ? "$" : currency
                        let initialSign = initialBalance < 0 ? "-" : ""
                        
                        Text("Initial")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.75)
                        Text("\(initialSign)\(currencySymbol)\(String(format: "%.2f", abs(initialBalance)))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.7)
                    } else if transaction.type == .expense {
                        Text("Total")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.75)
                        Text("\(getPaidSign())\(formatCurrency(abs(transaction.amount)))")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(getPaidColor()) // Red for expenses
                            .minimumScaleFactor(0.75)
                    } else {
                        Text("Total")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.75)
                        Text(formatCurrency(transaction.amount))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                            .minimumScaleFactor(0.75)
                    }
                }
                .frame(width: totalWidth, alignment: .leading)
                .padding(.horizontal, columnPadding)
                
                Divider().frame(height: 70)
                
                // Paid Column
                VStack(alignment: .leading, spacing: 4) {
                    if transaction.type == .balanceAdjustment {
                        // Column 4: Show final amount
                        let balances = transaction.balancesAfterTransaction ?? [:]
                        let finalBalance = balances["finalBalance"] as? Double ?? transaction.amount
                        let currency = transaction.currencyName ?? "CAD"
                        let currencySymbol = currency == "CAD" ? "$" : currency
                        let finalSign = finalBalance < 0 ? "-" : ""
                        
                        Text("Final")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.75)
                        Text("\(finalSign)\(currencySymbol)\(String(format: "%.2f", abs(finalBalance)))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(getPaidColor())
                            .minimumScaleFactor(0.7)
                    } else if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
                        Spacer()
                    } else if transaction.type == .expense {
                        // For expenses, show paid amount (calculated from payment split)
                        Text("Paid")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.75)
                        // Use paid field which is the sum of cash + bank + credit card
                        // In Cash/Bank tabs, this will be adjusted to show only the relevant amount
                        let paidAmount = transaction.paid ?? transaction.amount
                        Text("\(getPaidSign())\(formatCurrency(abs(paidAmount)))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(getPaidColor()) // Red for expenses
                            .minimumScaleFactor(0.7)
                    } else {
                        Text("Paid")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.75)
                        if let paid = transaction.paid, paid > 0 {
                            Text("\(getPaidSign())\(formatCurrency(abs(paid)))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(getPaidColor())
                                .minimumScaleFactor(0.7)
                        } else {
                            Text(formatCurrency(0))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.secondary)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                .frame(width: paidWidth, alignment: .leading)
                .padding(.horizontal, columnPadding)
                
                Divider().frame(height: 70)
                
                // Credit Column
                VStack(alignment: .leading, spacing: 4) {
                    if transaction.type == .balanceAdjustment {
                        // Column 5: Empty for balance adjustments
                        Spacer()
                    } else if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
                        Spacer()
                    } else if transaction.type == .expense {
                        // Expenses don't have credit - they're fully paid
                        Text("Credit")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.75)
                        Text(formatCurrency(0))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.7)
                    } else {
                        HStack(spacing: 4) {
                            Text("Credit")
                                .font(.system(size: 10, weight: .bold))
                            if let credit = transaction.credit, credit != 0 {
                                Text(getCreditTag())
                                    .font(.system(size: 10, weight: .semibold))
                                    .minimumScaleFactor(0.75)
                            }
                        }
                        .foregroundColor(.secondary)
                        if let credit = transaction.credit, credit != 0 {
                            Text(formatCurrency(abs(credit)))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(getCreditColor())
                                .minimumScaleFactor(0.7)
                        } else {
                            Text(formatCurrency(0))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.secondary)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                .frame(width: creditWidth, alignment: .leading)
                .padding(.horizontal, columnPadding)
                
                Divider().frame(height: 70)
                
                // Payment Methods Column OR Giver Balances
                if transaction.type == .balanceAdjustment {
                    // Column 6: Empty for balance adjustments
                    VStack {}
                        .frame(width: paymentWidth)
                        .padding(.horizontal, columnPadding)
                } else if transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman || transaction.type == .expense {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Payment Methods")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.75)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 9))
                                .foregroundColor(transaction.type == .expense ? .red : .green)
                            Text("Cash:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            if transaction.type == .expense {
                                Text("\(getPaidSign())\(formatCurrency(abs(transaction.cashPaid ?? 0)))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(getPaidColor()) // Red for expenses
                                    .minimumScaleFactor(0.75)
                            } else {
                                Text(formatCurrency(transaction.cashPaid ?? 0))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .minimumScaleFactor(0.75)
                            }
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "building.columns.fill")
                                .font(.system(size: 9))
                                .foregroundColor(transaction.type == .expense ? .red : .blue)
                            Text("Bank:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            if transaction.type == .expense {
                                Text("\(getPaidSign())\(formatCurrency(abs(transaction.bankPaid ?? 0)))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(getPaidColor()) // Red for expenses
                                    .minimumScaleFactor(0.75)
                            } else {
                                Text(formatCurrency(transaction.bankPaid ?? 0))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .minimumScaleFactor(0.75)
                            }
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 9))
                                .foregroundColor(transaction.type == .expense ? .red : .purple)
                            Text("Card:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            if transaction.type == .expense {
                                Text("\(getPaidSign())\(formatCurrency(abs(transaction.creditCardPaid ?? 0)))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(getPaidColor()) // Red for expenses
                                    .minimumScaleFactor(0.75)
                            } else {
                                Text(formatCurrency(transaction.creditCardPaid ?? 0))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .minimumScaleFactor(0.75)
                            }
                        }
                    }
                    .frame(width: paymentWidth, alignment: .leading)
                    .padding(.horizontal, columnPadding)
                } else {
                    // Giver Balances for currency transactions
                    VStack(alignment: .leading, spacing: 6) {
                        Text(transaction.giverName ?? "Giver")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.75)
                        
                        if let balances = transaction.balancesAfterTransaction {
                            let giverBalances: [String: Double] = {
                                if transaction.giver == "myself_special_id" {
                                    return balances["myself"] as? [String: Double] ?? [:]
                                } else {
                                    return balances[transaction.giver ?? ""] as? [String: Double] ?? [:]
                                }
                            }()
                            
                            ForEach(Array(giverBalances.sorted(by: { $0.key < $1.key })), id: \.key) { item in
                                HStack(spacing: 4) {
                                    Text("\(item.key):")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.2f", item.value))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .minimumScaleFactor(0.75)
                                }
                            }
                        }
                    }
                    .frame(width: giverWidth, alignment: .leading)
                    .padding(.horizontal, columnPadding)
                }
                
                Divider().frame(height: 70)
                
                // Middleman Column OR Taker Balances
                if transaction.type == .balanceAdjustment {
                    // Column 7: Empty for balance adjustments
                    VStack {}
                        .frame(width: adjustedMiddlemanWidth)
                        .padding(.horizontal, widePadding)
                } else if transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman {
                    VStack(alignment: .leading, spacing: 6) {
                        if let middlemanName = transaction.middlemanName {
                            Text("Middleman (\(middlemanName))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        } else {
                            Text("Middleman")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .minimumScaleFactor(0.75)
                        }
                        
                        HStack(spacing: max(8, 16 * scale)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "banknote.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(getMiddlemanColor())
                                    Text("Cash:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(getMiddlemanColor())
                                        .minimumScaleFactor(0.75)
                                    if let middlemanCash = transaction.middlemanCash, middlemanCash > 0 {
                                        Text("\(getMiddlemanSign())\(formatCurrency(abs(middlemanCash)))")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(getMiddlemanColor())
                                            .minimumScaleFactor(0.75)
                                    } else {
                                        Text(formatCurrency(0))
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .minimumScaleFactor(0.75)
                                    }
                                }
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "building.columns.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(getMiddlemanColor())
                                    Text("Bank:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(getMiddlemanColor())
                                        .minimumScaleFactor(0.75)
                                    if let middlemanBank = transaction.middlemanBank, middlemanBank > 0 {
                                        Text("\(getMiddlemanSign())\(formatCurrency(abs(middlemanBank)))")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(getMiddlemanColor())
                                            .minimumScaleFactor(0.75)
                                    } else {
                                        Text(formatCurrency(0))
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .minimumScaleFactor(0.75)
                                    }
                                }
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "creditcard.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(getMiddlemanColor())
                                    Text("Card:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(getMiddlemanColor())
                                        .minimumScaleFactor(0.75)
                                    if let middlemanCreditCard = transaction.middlemanCreditCard, middlemanCreditCard > 0 {
                                        Text("\(getMiddlemanSign())\(formatCurrency(abs(middlemanCreditCard)))")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(getMiddlemanColor())
                                            .minimumScaleFactor(0.75)
                                    } else {
                                        Text(formatCurrency(0))
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .minimumScaleFactor(0.75)
                                    }
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(getMiddlemanColor())
                                    Text("Credit:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(getMiddlemanColor())
                                        .minimumScaleFactor(0.75)
                                    if let middlemanCredit = transaction.middlemanCredit, middlemanCredit != 0 {
                                        Text("\(getMiddlemanSign())\(formatCurrency(abs(middlemanCredit)))")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(getMiddlemanColor())
                                            .minimumScaleFactor(0.75)
                                    } else {
                                        Text(formatCurrency(0))
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .minimumScaleFactor(0.75)
                                    }
                                }
                            }
                            
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(width: adjustedMiddlemanWidth, alignment: .leading)
                    .padding(.horizontal, widePadding)
                } else if transaction.type == .expense {
                    // Expenses don't have taker or balances - show empty or notes
                    VStack(alignment: .leading, spacing: 6) {
                        // Empty space for expenses (no taker to show)
                        Spacer()
                    }
                    .frame(width: adjustedMiddlemanWidth, alignment: .leading)
                    .padding(.horizontal, widePadding)
                } else {
                    // Taker Balances for currency transactions
                    VStack(alignment: .leading, spacing: 6) {
                        Text(transaction.takerName ?? "Taker")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .minimumScaleFactor(0.75)
                        
                        if let balances = transaction.balancesAfterTransaction {
                            let takerBalances: [String: Double] = {
                                if transaction.taker == "myself_special_id" {
                                    return balances["myself"] as? [String: Double] ?? [:]
                                } else {
                                    return balances[transaction.taker ?? ""] as? [String: Double] ?? [:]
                                }
                            }()
                            
                            ForEach(Array(takerBalances.sorted(by: { $0.key < $1.key })), id: \.key) { item in
                                HStack(spacing: 4) {
                                    Text("\(item.key):")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.2f", item.value))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .minimumScaleFactor(0.75)
                                }
                            }
                        }
                    }
                    .frame(width: adjustedMiddlemanWidth, alignment: .leading)
                    .padding(.horizontal, widePadding)
                }
                
                Divider().frame(height: 70)
                
                // Notes Column
                VStack(alignment: .leading, spacing: 4) {
                    if let notes = transaction.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(width: notesWidth, alignment: .leading)
                .padding(.horizontal, columnPadding)
                
                Divider().frame(height: 70)
                
                // View Bill & Delete Buttons
                HStack(spacing: max(8, 16 * scale)) {
                    Button(action: {
                        let transactionId = transaction.id
                        let transactionType = transaction.type
                        print("🔵 [FULL VIEW] View Bill clicked for transaction: \(transactionId)")
                        print("📋 Transaction type: \(transactionType.rawValue)")
                        if transactionType == .purchase || transactionType == .sale || transactionType == .middleman {
                            let isSale = (transactionType == .sale) || (transactionType == .middleman && transaction.sourceCollection == "Sales")
                            print("✅ Calling onViewBill with: \(transactionId), isSale: \(isSale)")
                            onViewBill?(transactionId, isSale)
                        }
                    }) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor((transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman) ? .blue : .gray)
                            .frame(width: buttonWidth)
                            .padding(.vertical, max(10, 14 * scale))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!(transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman))
                    
                    Button(action: {
                        print("🖱️ [FULL VIEW] Delete button clicked for transaction: \(transaction.id)")
                        print("📋 Transaction type: \(transaction.type.rawValue)")
                        if transaction.type == .currencyRegular || transaction.type == .purchase || transaction.type == .sale || 
                           (transaction.type == .expense && onTransactionDeleted != nil) || transaction.type == .balanceAdjustment {
                            print("✅ Setting showingDeleteConfirmation to true")
                            showingDeleteConfirmation = true
                        } else {
                            print("❌ Transaction type cannot be deleted")
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor((transaction.type == .currencyRegular || transaction.type == .purchase || transaction.type == .sale || 
                                            (transaction.type == .expense && onTransactionDeleted != nil) || transaction.type == .balanceAdjustment) ? .red : .gray)
                            .frame(width: buttonWidth)
                            .padding(.vertical, max(10, 14 * scale))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!(transaction.type == .currencyRegular || transaction.type == .purchase || transaction.type == .sale || 
                               (transaction.type == .expense && onTransactionDeleted != nil) || transaction.type == .balanceAdjustment) || isDeleting)
                }
                .frame(width: buttonsColumnWidth, alignment: .center)
                .padding(.horizontal, columnPadding)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.systemBackground))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
        .frame(minHeight: 110, alignment: .top)
    }
    
    // MARK: - Delete Transaction Logic
    private func deleteTransaction() {
        print("🔴 deleteTransaction() called")
        print("📝 Transaction ID: \(transaction.id)")
        print("📋 Transaction Type: \(transaction.type.rawValue)")
        print("👤 Giver: \(transaction.giverName ?? "N/A") (ID: \(transaction.giver ?? "N/A"))")
        print("👤 Taker: \(transaction.takerName ?? "N/A") (ID: \(transaction.taker ?? "N/A"))")
        print("💰 Amount: \(transaction.amount)")
        print("💱 Currency: \(transaction.currencyName ?? "N/A")")
        
        isDeleting = true
        deleteError = ""
        
        Task {
            do {
                print("🚀 Starting reverseTransaction()...")
                try await reverseTransaction()
                
                await MainActor.run {
                    print("✅ Transaction deleted and reversed successfully!")
                    self.isDeleting = false
                    
                    // Notify parent to remove from list
                    print("📞 Calling onTransactionDeleted callback...")
                    onTransactionDeleted?(transaction.id)
                    print("✅ Callback executed")
                }
            } catch {
                await MainActor.run {
                    self.isDeleting = false
                    self.deleteError = "Failed to delete"
                    print("❌❌❌ Delete transaction error: \(error.localizedDescription)")
                    print("❌ Error details: \(error)")
                }
            }
        }
    }
    
    private func reverseTransaction() async throws {
        print("⚡ reverseTransaction() START")
        let db = Firestore.firestore()
        print("🔥 Firestore instance created")
        
        print("🔄 Starting transaction reversal for transaction ID: \(transaction.id)")
        print("📊 Transaction type: \(transaction.type.rawValue)")
        
        if transaction.type == .currencyRegular {
            print("💵 Handling CURRENCY transaction reversal...")
            print("📊 Transaction details: \(transaction.giverName ?? "N/A") → \(transaction.takerName ?? "N/A")")
            print("💰 Amount: \(transaction.amount) \(transaction.currencyName ?? "N/A")")
            
            try await db.runTransaction { transaction, errorPointer in
                do {
                    try self.reverseRegularTransaction(transaction: transaction)
                    print("✅ reverseRegularTransaction() completed")
                    
                    // Delete the currency transaction record
                    let transactionRef = db.collection("CurrencyTransactions").document(self.transaction.id)
                    print("📝 Marking currency transaction record for deletion: \(self.transaction.id)")
                    transaction.deleteDocument(transactionRef)
                    print("✅ Currency transaction record marked for deletion")
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                return nil
            }
            
        } else if transaction.type == .purchase {
            print("📦 Handling PURCHASE transaction reversal...")
            print("💰 Grand Total: \(transaction.amount)")
            print("🏪 Order Number: \(transaction.orderNumber ?? 0)")
            
            // Pre-fetch purchase document outside transaction
            let purchaseRef = db.collection("Purchases").document(transaction.id)
            let purchaseDoc = try await purchaseRef.getDocument()
            
            guard purchaseDoc.exists, let purchaseData = purchaseDoc.data() else {
                print("❌ Purchase document not found!")
                throw NSError(domain: "PurchaseError", code: 404,
                             userInfo: [NSLocalizedDescriptionKey: "Purchase document not found"])
            }
            
            print("✅ Purchase document fetched successfully")
            
            // Pre-fetch phone and IMEI document references
            let purchasedPhones = purchaseData["purchasedPhones"] as? [[String: Any]] ?? []
            var phoneRefsToDelete: [DocumentReference] = []
            var imeiRefsToDelete: [DocumentReference] = []
            
            for (index, phoneData) in purchasedPhones.enumerated() {
                let brand = phoneData["brand"] as? String ?? ""
                let model = phoneData["model"] as? String ?? ""
                let imei = phoneData["imei"] as? String ?? ""
                
                print("   📱 [\(index+1)/\(purchasedPhones.count)] Processing phone: \(brand) \(model), IMEI: \(imei)")
                
                // Find brand document
                let brandQuery = db.collection("PhoneBrands").whereField("brand", isEqualTo: brand).limit(to: 1)
                let brandSnapshot = try await brandQuery.getDocuments()
                
                guard let brandDoc = brandSnapshot.documents.first else {
                    print("   ⚠️ Brand not found: \(brand), skipping phone...")
                    continue
                }
                let brandDocId = brandDoc.documentID
                print("   ✅ Found brand: \(brandDocId)")
                
                // Find model document
                let modelQuery = db.collection("PhoneBrands")
                    .document(brandDocId)
                    .collection("Models")
                    .whereField("model", isEqualTo: model)
                    .limit(to: 1)
                let modelSnapshot = try await modelQuery.getDocuments()
                
                guard let modelDoc = modelSnapshot.documents.first else {
                    print("   ⚠️ Model not found: \(model), skipping phone...")
                    continue
                }
                let modelDocId = modelDoc.documentID
                print("   ✅ Found model: \(modelDocId)")
                
                // Find phone document by IMEI
                let phoneQuery = db.collection("PhoneBrands")
                    .document(brandDocId)
                    .collection("Models")
                    .document(modelDocId)
                    .collection("Phones")
                    .whereField("imei", isEqualTo: imei)
                    .limit(to: 1)
                
                let phoneSnapshot = try await phoneQuery.getDocuments()
                if let phoneDoc = phoneSnapshot.documents.first {
                    print("   ✅ Found phone document: \(phoneDoc.documentID), adding to delete list")
                    phoneRefsToDelete.append(phoneDoc.reference)
                } else {
                    print("   ⚠️ Phone document not found for IMEI: \(imei) (may have been sold already)")
                }
                
                // Find IMEI document
                let imeiQuery = db.collection("IMEI").whereField("imei", isEqualTo: imei).limit(to: 1)
                let imeiSnapshot = try await imeiQuery.getDocuments()
                if let imeiDoc = imeiSnapshot.documents.first {
                    print("   ✅ Found IMEI document: \(imeiDoc.documentID), adding to delete list")
                    imeiRefsToDelete.append(imeiDoc.reference)
                } else {
                    print("   ⚠️ IMEI document not found for IMEI: \(imei) (may have been deleted already)")
                }
            }
            
            print("✅ Pre-fetched \(phoneRefsToDelete.count) phone references and \(imeiRefsToDelete.count) IMEI references")
            if phoneRefsToDelete.isEmpty && !purchasedPhones.isEmpty {
                print("⚠️ WARNING: No phone documents found to delete! Phones may have already been sold.")
            }
            
            try await db.runTransaction { transaction, errorPointer in
                do {
                    try self.reversePurchaseTransaction(transaction: transaction, purchaseData: purchaseData, phoneRefsToDelete: phoneRefsToDelete, imeiRefsToDelete: imeiRefsToDelete)
                    print("✅ reversePurchaseTransaction() completed")
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                return nil
            }
            
        } else if transaction.type == .sale {
            print("💰 Handling SALES transaction reversal...")
            print("💰 Grand Total: \(transaction.amount)")
            print("🏪 Order Number: \(transaction.orderNumber ?? 0)")
            
            // Pre-fetch sales document outside transaction
            let salesRef = db.collection("Sales").document(transaction.id)
            let salesDoc = try await salesRef.getDocument()
            
            guard salesDoc.exists, let salesData = salesDoc.data() else {
                print("❌ Sales document not found!")
                throw NSError(domain: "SalesError", code: 404,
                             userInfo: [NSLocalizedDescriptionKey: "Sales document not found"])
            }
            
            print("✅ Sales document fetched successfully")
            
            // Pre-fetch phone creation data (brand/model/color/carrier/storage references)
            let soldPhones = salesData["soldPhones"] as? [[String: Any]] ?? []
            var phonesToCreate: [(phoneData: [String: Any], brandRef: DocumentReference, modelRef: DocumentReference, colorRef: DocumentReference?, carrierRef: DocumentReference?, storageRef: DocumentReference?)] = []
            
            for (index, phoneData) in soldPhones.enumerated() {
                print("   📱 [\(index+1)/\(soldPhones.count)] Processing phone data from sales document")
                
                // Extract brand and model as strings (sales documents store them as strings)
                let brand = phoneData["brand"] as? String ?? ""
                let model = phoneData["model"] as? String ?? ""
                
                if brand.isEmpty || model.isEmpty {
                    print("   ⚠️ Brand or model is empty (brand: '\(brand)', model: '\(model)'), skipping phone...")
                    continue
                }
                
                print("   📝 Brand: \(brand), Model: \(model)")
                
                // Find brand document
                let brandQuery = db.collection("PhoneBrands").whereField("brand", isEqualTo: brand).limit(to: 1)
                let brandSnapshot = try await brandQuery.getDocuments()
                
                guard let brandDoc = brandSnapshot.documents.first else {
                    print("   ⚠️ Brand not found: \(brand), skipping phone...")
                    continue
                }
                let brandRef = brandDoc.reference
                print("   ✅ Found brand reference: \(brandRef.documentID)")
                
                // Find model document
                let modelQuery = db.collection("PhoneBrands")
                    .document(brandDoc.documentID)
                    .collection("Models")
                    .whereField("model", isEqualTo: model)
                    .limit(to: 1)
                let modelSnapshot = try await modelQuery.getDocuments()
                
                guard let modelDoc = modelSnapshot.documents.first else {
                    print("   ⚠️ Model not found: \(model), skipping phone...")
                    continue
                }
                let modelRef = modelDoc.reference
                print("   ✅ Found model reference: \(modelRef.documentID)")
                
                // Extract color reference (stored as string in sales document, need to look up)
                var colorRef: DocumentReference? = nil
                if let color = phoneData["color"] as? String, !color.isEmpty && color != "Unknown" {
                    let colorQuery = db.collection("Colors").whereField("name", isEqualTo: color).limit(to: 1)
                    let colorSnapshot = try await colorQuery.getDocuments()
                    colorRef = colorSnapshot.documents.first?.reference
                    if let colorRef = colorRef {
                        print("   ✅ Found color reference: \(colorRef.documentID)")
                    } else {
                        print("   ℹ️ Color '\(color)' not found in Colors collection")
                    }
                } else {
                    print("   ℹ️ No color (or empty/Unknown)")
                }
                
                // Extract carrier reference (stored as string in sales document, need to look up)
                var carrierRef: DocumentReference? = nil
                if let carrier = phoneData["carrier"] as? String, !carrier.isEmpty && carrier != "Unknown" {
                    let carrierQuery = db.collection("Carriers").whereField("name", isEqualTo: carrier).limit(to: 1)
                    let carrierSnapshot = try await carrierQuery.getDocuments()
                    carrierRef = carrierSnapshot.documents.first?.reference
                    if let carrierRef = carrierRef {
                        print("   ✅ Found carrier reference: \(carrierRef.documentID)")
                    } else {
                        print("   ℹ️ Carrier '\(carrier)' not found in Carriers collection")
                    }
                } else {
                    print("   ℹ️ No carrier (or empty/Unknown)")
                }
                
                // Extract storage location reference (stored as string in sales document, need to look up)
                var storageRef: DocumentReference? = nil
                if let storageLocation = phoneData["storageLocation"] as? String, !storageLocation.isEmpty && storageLocation != "Unknown" {
                    let storageQuery = db.collection("StorageLocations").whereField("storageLocation", isEqualTo: storageLocation).limit(to: 1)
                    let storageSnapshot = try await storageQuery.getDocuments()
                    storageRef = storageSnapshot.documents.first?.reference
                    if let storageRef = storageRef {
                        print("   ✅ Found storage location reference: \(storageRef.documentID)")
                    } else {
                        print("   ℹ️ Storage location '\(storageLocation)' not found in StorageLocations collection")
                    }
                } else {
                    print("   ℹ️ No storage location (or empty/Unknown)")
                }
                
                phonesToCreate.append((phoneData: phoneData, brandRef: brandRef, modelRef: modelRef, colorRef: colorRef, carrierRef: carrierRef, storageRef: storageRef))
            }
            
            print("✅ Pre-fetched \(phonesToCreate.count) phone creation references")
            if phonesToCreate.isEmpty && !soldPhones.isEmpty {
                print("⚠️ WARNING: No phone references extracted! Cannot re-create phones.")
            }
            
            try await db.runTransaction { transaction, errorPointer in
                do {
                    try self.reverseSalesTransaction(transaction: transaction, salesData: salesData, phonesToCreate: phonesToCreate)
                    print("✅ reverseSalesTransaction() completed")
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                return nil
            }
        } else if transaction.type == .expense {
            print("💸 Handling EXPENSE transaction reversal...")
            print("💰 Total Amount: \(transaction.amount)")
            
            // Get payment split amounts
            let cashAmount = transaction.cashPaid ?? 0.0
            let bankAmount = transaction.bankPaid ?? 0.0
            let creditCardAmount = transaction.creditCardPaid ?? 0.0
            
            print("   💵 Cash: \(cashAmount), Bank: \(bankAmount), Credit Card: \(creditCardAmount)")
            
            // Use batch for expense deletion (same as AddExpenseDialog)
            let batch = db.batch()
            let reverseDate = Date()
            
            // Reverse cash balance (add back the amount that was subtracted)
            if cashAmount > 0 {
                let cashDocRef = db.collection("Balances").document("cash")
                let cashDoc = try await cashDocRef.getDocument()
                
                if cashDoc.exists {
                    let cashData = cashDoc.data() ?? [:]
                    let currentCashBalance = cashData["amount"] as? Double ?? 0.0
                    let newCashBalance = currentCashBalance + cashAmount
                    
                    batch.updateData([
                        "amount": newCashBalance,
                        "updatedAt": reverseDate
                    ], forDocument: cashDocRef)
                    print("   ✅ Reversed cash balance: \(currentCashBalance) + \(cashAmount) = \(newCashBalance)")
                } else {
                    // If document doesn't exist, create it with the reversed amount
                    batch.setData([
                        "amount": cashAmount,
                        "updatedAt": reverseDate
                    ], forDocument: cashDocRef)
                    print("   ✅ Created cash balance document with amount: \(cashAmount)")
                }
            }
            
            // Reverse bank balance (add back the amount that was subtracted)
            if bankAmount > 0 {
                let bankDocRef = db.collection("Balances").document("bank")
                let bankDoc = try await bankDocRef.getDocument()
                
                if bankDoc.exists {
                    let bankData = bankDoc.data() ?? [:]
                    let currentBankBalance = bankData["amount"] as? Double ?? 0.0
                    let newBankBalance = currentBankBalance + bankAmount
                    
                    batch.updateData([
                        "amount": newBankBalance,
                        "updatedAt": reverseDate
                    ], forDocument: bankDocRef)
                    print("   ✅ Reversed bank balance: \(currentBankBalance) + \(bankAmount) = \(newBankBalance)")
                } else {
                    // If document doesn't exist, create it with the reversed amount
                    batch.setData([
                        "amount": bankAmount,
                        "updatedAt": reverseDate
                    ], forDocument: bankDocRef)
                    print("   ✅ Created bank balance document with amount: \(bankAmount)")
                }
            }
            
            // Reverse credit card balance (add back the amount that was subtracted)
            if creditCardAmount > 0 {
                let creditCardDocRef = db.collection("Balances").document("creditCard")
                let creditCardDoc = try await creditCardDocRef.getDocument()
                
                if creditCardDoc.exists {
                    let creditCardData = creditCardDoc.data() ?? [:]
                    let currentCreditCardBalance = creditCardData["amount"] as? Double ?? 0.0
                    let newCreditCardBalance = currentCreditCardBalance + creditCardAmount
                    
                    batch.updateData([
                        "amount": newCreditCardBalance,
                        "updatedAt": reverseDate
                    ], forDocument: creditCardDocRef)
                    print("   ✅ Reversed credit card balance: \(currentCreditCardBalance) + \(creditCardAmount) = \(newCreditCardBalance)")
                } else {
                    // If document doesn't exist, create it with the reversed amount
                    batch.setData([
                        "amount": creditCardAmount,
                        "updatedAt": reverseDate
                    ], forDocument: creditCardDocRef)
                    print("   ✅ Created credit card balance document with amount: \(creditCardAmount)")
                }
            }
            
            // Delete the expense transaction document
            let expenseDocRef = db.collection("ExpenseTransactions").document(transaction.id)
            batch.deleteDocument(expenseDocRef)
            print("   📝 Marked expense transaction for deletion: \(transaction.id)")
            
            // Commit all changes atomically
            try await batch.commit()
            print("✅✅✅ Expense transaction reversal completed successfully!")
        } else if transaction.type == .balanceAdjustment {
            print("⚖️ Handling BALANCE ADJUSTMENT reversal...")
            
            guard let balances = transaction.balancesAfterTransaction else {
                throw NSError(domain: "BalanceAdjustmentError", code: 400,
                             userInfo: [NSLocalizedDescriptionKey: "Missing balance adjustment data"])
            }
            
            let initialBalance = balances["initialBalance"] as? Double ?? 0.0
            let finalBalance = balances["finalBalance"] as? Double ?? transaction.amount
            let adjustmentAmount = balances["adjustmentAmount"] as? Double ?? (finalBalance - initialBalance)
            let currency = balances["currency"] as? String ?? "CAD"
            
            // Get entityId from balances or fetch from BalanceAdjustments document
            var entityId = balances["entityId"] as? String ?? ""
            var entityTypeRaw = balances["entityType"] as? String ?? ""
            
            // If entityId is missing from balances, fetch from BalanceAdjustments document
            if entityId.isEmpty {
                print("   ⚠️ Entity ID missing from transaction data, fetching from BalanceAdjustments document...")
                let adjustmentRef = db.collection("BalanceAdjustments").document(transaction.id)
                let adjustmentDoc = try await adjustmentRef.getDocument()
                
                if adjustmentDoc.exists, let adjustmentData = adjustmentDoc.data() {
                    entityId = adjustmentData["entityId"] as? String ?? ""
                    entityTypeRaw = adjustmentData["entityType"] as? String ?? ""
                    print("   ✅ Fetched entityId: \(entityId), entityType: \(entityTypeRaw)")
                } else {
                    throw NSError(domain: "BalanceAdjustmentError", code: 404,
                                 userInfo: [NSLocalizedDescriptionKey: "Balance adjustment document not found"])
                }
            }
            
            // Validate entityId is not empty
            guard !entityId.isEmpty else {
                throw NSError(domain: "BalanceAdjustmentError", code: 400,
                             userInfo: [NSLocalizedDescriptionKey: "Entity ID is empty"])
            }
            
            // Validate transaction.id is not empty
            guard !transaction.id.isEmpty else {
                throw NSError(domain: "BalanceAdjustmentError", code: 400,
                             userInfo: [NSLocalizedDescriptionKey: "Transaction ID is empty"])
            }
            
            // Calculate reverse adjustment: if adjustment was positive (added), subtract it; if negative (subtracted), add it back
            let reverseAdjustment = -adjustmentAmount
            
            print("📊 Balance adjustment details:")
            print("   Transaction ID: \(transaction.id)")
            print("   Entity ID: \(entityId)")
            print("   Entity Type: \(entityTypeRaw)")
            print("   Currency: \(currency)")
            print("   Initial Balance: \(initialBalance)")
            print("   Final Balance: \(finalBalance)")
            print("   Adjustment Amount: \(adjustmentAmount)")
            print("   Reverse Adjustment: \(reverseAdjustment) (will add/subtract from current balance)")
            
            // Use Firestore transaction for atomicity
            try await db.runTransaction { firestoreTransaction, errorPointer in
                do {
                    // Step 1: Read current entity/balance document to get current balance
                    let entityType = EntityType(rawValue: entityTypeRaw) ?? .customer
                    let entityRef = db.collection(entityType.collectionName).document(entityId)
                    let entityDoc = try firestoreTransaction.getDocument(entityRef)
                    
                    if currency == "CAD" {
                        // Reverse CAD balance in entity collection
                        if entityDoc.exists {
                            let currentBalance = entityDoc.data()?["balance"] as? Double ?? 0.0
                            let newBalance = currentBalance + reverseAdjustment
                            
                            print("   💰 Current CAD balance: \(currentBalance)")
                            print("   🔄 Applying reverse adjustment: \(currentBalance) + \(reverseAdjustment) = \(newBalance)")
                            
                            firestoreTransaction.updateData([
                                "balance": newBalance,
                                "updatedAt": Timestamp()
                            ], forDocument: entityRef)
                            print("   ✅ Updated entity CAD balance to \(newBalance)")
                        } else {
                            print("   ⚠️ Entity document not found, cannot reverse balance")
                            throw NSError(domain: "BalanceAdjustmentError", code: 404,
                                         userInfo: [NSLocalizedDescriptionKey: "Entity document not found"])
                        }
                    } else {
                        // Reverse currency balance in CurrencyBalances collection
                        let currencyBalanceRef = db.collection("CurrencyBalances").document(entityId)
                        let currencyBalanceDoc = try firestoreTransaction.getDocument(currencyBalanceRef)
                        
                        if currencyBalanceDoc.exists {
                            let currentBalance = currencyBalanceDoc.data()?[currency] as? Double ?? 0.0
                            let newBalance = currentBalance + reverseAdjustment
                            
                            print("   💰 Current \(currency) balance: \(currentBalance)")
                            print("   🔄 Applying reverse adjustment: \(currentBalance) + \(reverseAdjustment) = \(newBalance)")
                            
                            firestoreTransaction.updateData([
                                currency: newBalance,
                                "updatedAt": Timestamp()
                            ], forDocument: currencyBalanceRef)
                            print("   ✅ Updated \(currency) balance to \(newBalance)")
                        } else {
                            // If document doesn't exist, create it with reversed amount
                            let newBalance = reverseAdjustment
                            firestoreTransaction.setData([
                                currency: newBalance,
                                "createdAt": Timestamp(),
                                "updatedAt": Timestamp()
                            ], forDocument: currencyBalanceRef)
                            print("   ✅ Created \(currency) balance document with \(newBalance)")
                        }
                    }
                    
                    // Step 2: Delete the balance adjustment record
                    let adjustmentRef = db.collection("BalanceAdjustments").document(self.transaction.id)
                    firestoreTransaction.deleteDocument(adjustmentRef)
                    print("   ✅ Marked balance adjustment record for deletion: \(self.transaction.id)")
                    
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                return nil
            }
            
            print("✅✅✅ Balance adjustment reversal completed successfully!")
        }
        
        print("✅✅✅ Transaction committed successfully! Transaction reversal completed!")
    }
    
    private func reverseRegularTransaction(transaction: FirestoreTransaction) throws {
        print("🔄🔄🔄 reverseRegularTransaction() START")
        print("🔍 Checking for required data...")
        
        guard let giver = self.transaction.giver else {
            print("❌ Missing giver ID")
            throw NSError(domain: "TransactionError", code: 400,
                         userInfo: [NSLocalizedDescriptionKey: "Missing giver ID"])
        }
        
        guard let taker = self.transaction.taker else {
            print("❌ Missing taker ID")
            throw NSError(domain: "TransactionError", code: 400,
                         userInfo: [NSLocalizedDescriptionKey: "Missing taker ID"])
        }
        
        guard let currencyName = self.transaction.currencyName else {
            print("❌ Missing currency name")
            throw NSError(domain: "TransactionError", code: 400,
                         userInfo: [NSLocalizedDescriptionKey: "Missing currency name"])
        }
        
        print("✅ All required data present:")
        print("   Giver: \(giver)")
        print("   Taker: \(taker)")
        print("   Currency: \(currencyName)")
        print("   Amount: \(self.transaction.amount)")
        
        // Step 1: Reverse giver balance (ADD back what they gave)
        print("📍 STEP 1: Reversing giver balance...")
        if giver == "myself_special_id" {
            print("   → Giver is MYSELF, updating my cash balance")
            try updateMyCashBalance(
                currency: currencyName,
                amount: self.transaction.amount, // ADD back what I gave
                transaction: transaction
            )
            print("✅ Reversed my cash balance: +\(self.transaction.amount) \(currencyName)")
        } else if giver == "myself_bank_special_id" {
            print("   → Giver is MYSELF BANK, updating my bank balance")
            try updateMyBankBalance(
                amount: self.transaction.amount, // ADD back what I gave
                transaction: transaction
            )
            print("✅ Reversed my bank balance: +\(self.transaction.amount) \(currencyName)")
        } else {
            print("   → Giver is CUSTOMER/ENTITY (ID: \(giver)), updating their balance")
            try updateCustomerBalance(
                customerId: giver,
                currency: currencyName,
                amount: self.transaction.amount, // ADD back what they gave
                transaction: transaction
            )
            print("✅ Reversed giver balance: +\(self.transaction.amount) \(currencyName)")
        }
        
        // Step 2: Reverse taker balance (SUBTRACT what they received)
        print("📍 STEP 2: Reversing taker balance...")
        if taker == "myself_special_id" {
            print("   → Taker is MYSELF, updating my cash balance")
            try updateMyCashBalance(
                currency: currencyName,
                amount: -self.transaction.amount, // SUBTRACT what I received
                transaction: transaction
            )
            print("✅ Reversed my cash balance: -\(self.transaction.amount) \(currencyName)")
        } else if taker == "myself_bank_special_id" {
            print("   → Taker is MYSELF BANK, updating my bank balance")
            try updateMyBankBalance(
                amount: -self.transaction.amount, // SUBTRACT what I received
                transaction: transaction
            )
            print("✅ Reversed my bank balance: -\(self.transaction.amount) \(currencyName)")
        } else {
            print("   → Taker is CUSTOMER/ENTITY (ID: \(taker)), updating their balance")
            try updateCustomerBalance(
                customerId: taker,
                currency: currencyName,
                amount: -self.transaction.amount, // SUBTRACT what they received
                transaction: transaction
            )
            print("✅ Reversed taker balance: -\(self.transaction.amount) \(currencyName)")
        }
        
        print("✅✅ reverseRegularTransaction() COMPLETE")
    }
    
    private func reversePurchaseTransaction(transaction: FirestoreTransaction, purchaseData: [String: Any], phoneRefsToDelete: [DocumentReference], imeiRefsToDelete: [DocumentReference]) throws {
        print("📦📦📦 reversePurchaseTransaction() START")
        
        let db = Firestore.firestore()
        
        // Extract data
        let paymentMethods = purchaseData["paymentMethods"] as? [String: Any] ?? [:]
        let supplierRef = purchaseData["supplier"] as? DocumentReference
        let middlemanRef = purchaseData["middleman"] as? DocumentReference
        let middlemanPayment = purchaseData["middlemanPayment"] as? [String: Any] ?? [:]
        let orderNumberRef = purchaseData["orderNumberReference"] as? DocumentReference
        let purchaseRef = db.collection("Purchases").document(self.transaction.id)
        
        print("📊 Purchase data extracted:")
        print("   Phones to delete: \(phoneRefsToDelete.count)")
        print("   IMEIs to delete: \(imeiRefsToDelete.count)")
        print("   Supplier: \(supplierRef?.documentID ?? "none")")
        print("   Middleman: \(middlemanRef?.documentID ?? "none")")
        print("   Order Number Ref: \(orderNumberRef?.documentID ?? "none")")
        
        // PHASE 1: ALL READS FIRST (Firestore transactions require all reads before writes)
        print("📍 PHASE 1: Reading all documents...")
        
        // Read supplier document
        var supplierDoc: DocumentSnapshot? = nil
        var supplierData: [String: Any]? = nil
        if let supplierRef = supplierRef {
            print("   📖 Reading supplier document...")
            supplierDoc = try transaction.getDocument(supplierRef)
            if supplierDoc!.exists {
                supplierData = supplierDoc!.data() ?? [:]
                print("   ✅ Supplier document read")
            }
        }
        
        // Read middleman document
        var middlemanDoc: DocumentSnapshot? = nil
        var middlemanData: [String: Any]? = nil
        if let middlemanRef = middlemanRef {
            print("   📖 Reading middleman document...")
            middlemanDoc = try transaction.getDocument(middlemanRef)
            if middlemanDoc!.exists {
                middlemanData = middlemanDoc!.data() ?? [:]
                print("   ✅ Middleman document read")
            }
        }
        
        // Read balance documents
        print("   📖 Reading balance documents...")
        let cashDocRef = db.collection("Balances").document("cash")
        let cashDoc = try transaction.getDocument(cashDocRef)
        let cashData = cashDoc.exists ? (cashDoc.data() ?? [:]) : [:]
        
        let bankDocRef = db.collection("Balances").document("bank")
        let bankDoc = try transaction.getDocument(bankDocRef)
        let bankData = bankDoc.exists ? (bankDoc.data() ?? [:]) : [:]
        
        let creditCardDocRef = db.collection("Balances").document("creditCard")
        let creditCardDoc = try transaction.getDocument(creditCardDocRef)
        let creditCardData = creditCardDoc.exists ? (creditCardDoc.data() ?? [:]) : [:]
        
        print("✅ PHASE 1 COMPLETE: All documents read")
        
        // PHASE 2: ALL WRITES (now that all reads are done)
        print("📍 PHASE 2: Performing all writes...")
        
        // STEP 1: Delete Phone and IMEI Documents
        print("📍 STEP 1: Deleting phone and IMEI documents...")
        if phoneRefsToDelete.isEmpty {
            print("   ⚠️ No phone references to delete (phones may have already been sold)")
        } else {
            for (index, phoneRef) in phoneRefsToDelete.enumerated() {
                print("   🗑️ [\(index+1)/\(phoneRefsToDelete.count)] Deleting phone document: \(phoneRef.documentID)")
                transaction.deleteDocument(phoneRef)
            }
        }
        
        if imeiRefsToDelete.isEmpty {
            print("   ⚠️ No IMEI references to delete (IMEIs may have already been deleted)")
        } else {
            for (index, imeiRef) in imeiRefsToDelete.enumerated() {
                print("   🗑️ [\(index+1)/\(imeiRefsToDelete.count)] Deleting IMEI document: \(imeiRef.documentID)")
                transaction.deleteDocument(imeiRef)
            }
        }
        print("✅ STEP 1 COMPLETE: Deleted \(phoneRefsToDelete.count) phones and \(imeiRefsToDelete.count) IMEIs")
        
        // STEP 2: Reverse Supplier Balance
        if let supplierRef = supplierRef, let supplierDoc = supplierDoc, supplierDoc.exists, var supplierData = supplierData {
            print("📍 STEP 2: Reversing supplier balance...")
            var updatedData: [String: Any] = [:]
            
            // Remove from transaction history
            var transactionHistory = supplierData["transactionHistory"] as? [[String: Any]] ?? []
            let originalCount = transactionHistory.count
            transactionHistory.removeAll { item in
                if let ref = item["purchaseReference"] as? DocumentReference {
                    return ref.documentID == self.transaction.id
                }
                return false
            }
            print("   📝 Removed from transaction history (was: \(originalCount), now: \(transactionHistory.count))")
            updatedData["transactionHistory"] = transactionHistory
            
            // Reverse balance
            let remainingCredit = paymentMethods["remainingCredit"] as? Double ?? 0.0
            let currentBalance = supplierData["balance"] as? Double ?? 0.0
            let newBalance = currentBalance + abs(remainingCredit) // ADD back (we no longer owe)
            updatedData["balance"] = newBalance
            
            print("   💰 Supplier balance: \(currentBalance) + \(abs(remainingCredit)) = \(newBalance)")
            
            transaction.updateData(updatedData, forDocument: supplierRef)
            print("   ✅ Supplier balance reversal added to transaction")
        }
        print("✅ STEP 2 COMPLETE")
        
        // STEP 3: Reverse Middleman Balance
        if let middlemanRef = middlemanRef, let middlemanDoc = middlemanDoc, middlemanDoc.exists, var middlemanData = middlemanData {
            print("📍 STEP 3: Reversing middleman balance...")
            var updatedData: [String: Any] = [:]
            
            // Remove from transaction history
            var transactionHistory = middlemanData["transactionHistory"] as? [[String: Any]] ?? []
            let originalCount = transactionHistory.count
            transactionHistory.removeAll { item in
                if let ref = item["purchaseReference"] as? DocumentReference {
                    return ref.documentID == self.transaction.id
                }
                return false
            }
            print("   📝 Removed from transaction history (was: \(originalCount), now: \(transactionHistory.count))")
            updatedData["transactionHistory"] = transactionHistory
            
            // Reverse balance based on unit
            let middlemanUnit = middlemanPayment["unit"] as? String ?? ""
            let paymentSplit = middlemanPayment["paymentSplit"] as? [String: Any] ?? [:]
            let middlemanCredit = paymentSplit["credit"] as? Double ?? 0.0
            let currentBalance = middlemanData["balance"] as? Double ?? 0.0
            
            let newBalance: Double
            if middlemanUnit == "give" {
                newBalance = currentBalance + middlemanCredit // ADD back
                print("   💰 Middleman balance (give mode): \(currentBalance) + \(middlemanCredit) = \(newBalance)")
            } else {
                newBalance = currentBalance - middlemanCredit // SUBTRACT back
                print("   💰 Middleman balance (receive mode): \(currentBalance) - \(middlemanCredit) = \(newBalance)")
            }
            updatedData["balance"] = newBalance
            
            transaction.updateData(updatedData, forDocument: middlemanRef)
            print("   ✅ Middleman balance reversal added to transaction")
        }
        print("✅ STEP 3 COMPLETE")
        
        // STEP 4: Reverse Account Balances
        print("📍 STEP 4: Reversing account balances...")
        
        let cashPaid = paymentMethods["cash"] as? Double ?? 0.0
        let bankPaid = paymentMethods["bank"] as? Double ?? 0.0
        let creditCardPaid = paymentMethods["creditCard"] as? Double ?? 0.0
        
        // Calculate final amounts with middleman adjustments
        var finalCash = cashPaid
        var finalBank = bankPaid
        var finalCard = creditCardPaid
        
        if middlemanRef != nil {
            let paymentSplit = middlemanPayment["paymentSplit"] as? [String: Any] ?? [:]
            let middlemanUnit = middlemanPayment["unit"] as? String ?? ""
            let mCash = paymentSplit["cash"] as? Double ?? 0.0
            let mBank = paymentSplit["bank"] as? Double ?? 0.0
            let mCard = paymentSplit["creditCard"] as? Double ?? 0.0
            
            print("   🤝 Applying middleman adjustments:")
            print("      Unit: \(middlemanUnit)")
            print("      M-Cash: \(mCash), M-Bank: \(mBank), M-Card: \(mCard)")
            
            if middlemanUnit == "give" {
                finalCash += mCash
                finalBank += mBank
                finalCard += mCard
                print("      Mode: give - ADDING to final amounts")
            } else {
                finalCash -= mCash
                finalBank -= mBank
                finalCard -= mCard
                print("      Mode: receive - SUBTRACTING from final amounts")
            }
        }
        
        print("   💵 Final amounts to reverse:")
        print("      Cash: \(finalCash)")
        print("      Bank: \(finalBank)")
        print("      Card: \(finalCard)")
        
        // Reverse cash balance (ADD back)
        if cashDoc.exists {
            let currentCashBalance = cashData["amount"] as? Double ?? 0.0
            let newCashBalance = currentCashBalance + finalCash // ADD back
            
            print("   💰 Cash balance: \(currentCashBalance) + \(finalCash) = \(newCashBalance)")
            transaction.updateData([
                "amount": newCashBalance,
                "updatedAt": Timestamp()
            ], forDocument: cashDocRef)
        }
        
        // Reverse bank balance (ADD back)
        if bankDoc.exists {
            let currentBankBalance = bankData["amount"] as? Double ?? 0.0
            let newBankBalance = currentBankBalance + finalBank // ADD back
            
            print("   🏦 Bank balance: \(currentBankBalance) + \(finalBank) = \(newBankBalance)")
            transaction.updateData([
                "amount": newBankBalance,
                "updatedAt": Timestamp()
            ], forDocument: bankDocRef)
        }
        
        // Reverse credit card balance (ADD back)
        if creditCardDoc.exists {
            let currentCreditCardBalance = creditCardData["amount"] as? Double ?? 0.0
            let newCreditCardBalance = currentCreditCardBalance + finalCard // ADD back
            
            print("   💳 Credit Card balance: \(currentCreditCardBalance) + \(finalCard) = \(newCreditCardBalance)")
            transaction.updateData([
                "amount": newCreditCardBalance,
                "updatedAt": Timestamp()
            ], forDocument: creditCardDocRef)
        }
        print("✅ STEP 4 COMPLETE: All account balances reversed")
        
        // STEP 5: Delete Order Number Document
        if let orderNumberRef = orderNumberRef {
            print("📍 STEP 5: Deleting order number document...")
            print("   🗑️ Marking order number for deletion: \(orderNumberRef.documentID)")
            transaction.deleteDocument(orderNumberRef)
            print("✅ STEP 5 COMPLETE")
        }
        
        // STEP 6: Delete Purchase Document
        print("📍 STEP 6: Deleting purchase document...")
        print("   🗑️ Marking purchase document for deletion: \(self.transaction.id)")
        transaction.deleteDocument(purchaseRef)
        print("✅ STEP 6 COMPLETE")
        
        print("✅✅ reversePurchaseTransaction() COMPLETE")
    }
    
    private func reverseSalesTransaction(transaction: FirestoreTransaction, salesData: [String: Any], phonesToCreate: [(phoneData: [String: Any], brandRef: DocumentReference, modelRef: DocumentReference, colorRef: DocumentReference?, carrierRef: DocumentReference?, storageRef: DocumentReference?)]) throws {
        print("💰💰💰 reverseSalesTransaction() START")
        
        let db = Firestore.firestore()
        
        // Extract data
        let paymentMethods = salesData["paymentMethods"] as? [String: Any] ?? [:]
        let customerRef = salesData["customer"] as? DocumentReference
        let middlemanRef = salesData["middleman"] as? DocumentReference
        let middlemanPayment = salesData["middlemanPayment"] as? [String: Any] ?? [:]
        let orderNumberRef = salesData["orderNumberReference"] as? DocumentReference
        let salesRef = db.collection("Sales").document(self.transaction.id)
        
        print("📊 Sales data extracted:")
        print("   Phones to create: \(phonesToCreate.count)")
        print("   Customer: \(customerRef?.documentID ?? "none")")
        print("   Middleman: \(middlemanRef?.documentID ?? "none")")
        print("   Order Number Ref: \(orderNumberRef?.documentID ?? "none")")
        
        // PHASE 1: ALL READS FIRST (Firestore transactions require all reads before writes)
        print("📍 PHASE 1: Reading all documents...")
        
        // Read customer document
        var customerDoc: DocumentSnapshot? = nil
        var customerData: [String: Any]? = nil
        if let customerRef = customerRef {
            print("   📖 Reading customer document...")
            customerDoc = try transaction.getDocument(customerRef)
            if customerDoc!.exists {
                customerData = customerDoc!.data() ?? [:]
                print("   ✅ Customer document read")
            }
        }
        
        // Read middleman document
        var middlemanDoc: DocumentSnapshot? = nil
        var middlemanData: [String: Any]? = nil
        if let middlemanRef = middlemanRef {
            print("   📖 Reading middleman document...")
            middlemanDoc = try transaction.getDocument(middlemanRef)
            if middlemanDoc!.exists {
                middlemanData = middlemanDoc!.data() ?? [:]
                print("   ✅ Middleman document read")
            }
        }
        
        // Read balance documents
        print("   📖 Reading balance documents...")
        let cashDocRef = db.collection("Balances").document("cash")
        let cashDoc = try transaction.getDocument(cashDocRef)
        let cashData = cashDoc.exists ? (cashDoc.data() ?? [:]) : [:]
        
        let bankDocRef = db.collection("Balances").document("bank")
        let bankDoc = try transaction.getDocument(bankDocRef)
        let bankData = bankDoc.exists ? (bankDoc.data() ?? [:]) : [:]
        
        let creditCardDocRef = db.collection("Balances").document("creditCard")
        let creditCardDoc = try transaction.getDocument(creditCardDocRef)
        let creditCardData = creditCardDoc.exists ? (creditCardDoc.data() ?? [:]) : [:]
        
        // Read brand/model documents for all phones (needed for IMEI document creation)
        print("   📖 Reading brand/model documents for phones...")
        var brandModelNames: [String: (brand: String, model: String)] = [:] // Key: brandRef.documentID + "|" + modelRef.documentID
        for phoneInfo in phonesToCreate {
            let key = "\(phoneInfo.brandRef.documentID)|\(phoneInfo.modelRef.documentID)"
            if brandModelNames[key] == nil {
                // Read brand document
                let brandDoc = try transaction.getDocument(phoneInfo.brandRef)
                let brandData = brandDoc.exists ? (brandDoc.data() ?? [:]) : [:]
                let brandName = brandData["brand"] as? String ?? brandData["name"] as? String ?? brandData["title"] as? String ?? ""
                
                // Read model document
                let modelDoc = try transaction.getDocument(phoneInfo.modelRef)
                let modelData = modelDoc.exists ? (modelDoc.data() ?? [:]) : [:]
                let modelName = modelData["model"] as? String ?? modelData["name"] as? String ?? modelData["title"] as? String ?? ""
                
                brandModelNames[key] = (brand: brandName, model: modelName)
                print("   ✅ Read brand/model: \(brandName) / \(modelName)")
            }
        }
        
        print("✅ PHASE 1 COMPLETE: All documents read")
        
        // PHASE 2: ALL WRITES (now that all reads are done)
        print("📍 PHASE 2: Performing all writes...")
        
        // STEP 1: Re-create Phone and IMEI Documents
        print("📍 STEP 1: Re-creating phone and IMEI documents...")
        if phonesToCreate.isEmpty {
            print("   ⚠️ No phones to create - phonesToCreate array is empty!")
        }
        for (index, phoneInfo) in phonesToCreate.enumerated() {
            let phoneData = phoneInfo.phoneData
            let imei = phoneData["imei"] as? String ?? ""
            let capacity = phoneData["capacity"] as? String ?? ""
            let capacityUnit = phoneData["capacityUnit"] as? String ?? "GB"
            // Use actualCost if available, otherwise fall back to unitCost (for backward compatibility)
            let actualCost = phoneData["actualCost"] as? Double ?? phoneData["unitCost"] as? Double ?? 0.0
            let status = phoneData["status"] as? String ?? "Active"
            
            // Get brand/model names from the pre-read documents
            let key = "\(phoneInfo.brandRef.documentID)|\(phoneInfo.modelRef.documentID)"
            let brandModel = brandModelNames[key] ?? (brand: "", model: "")
            let brand = brandModel.brand
            let model = brandModel.model
            
            print("   📱 [\(index+1)/\(phonesToCreate.count)] Processing phone: \(brand) \(model), IMEI: \(imei)")
            print("   💰 Using actual cost: $\(actualCost) (from actualCost field)")
            
            // Re-create phone document
            print("   ➕ Re-creating phone document...")
            let phoneCollectionRef = db.collection("PhoneBrands")
                .document(phoneInfo.brandRef.documentID)
                .collection("Models")
                .document(phoneInfo.modelRef.documentID)
                .collection("Phones")
            
            let newPhoneDocRef = phoneCollectionRef.document()
            
            var phoneDocData: [String: Any] = [
                "brand": phoneInfo.brandRef,
                "model": phoneInfo.modelRef,
                "imei": imei,
                "capacity": capacity,
                "capacityUnit": capacityUnit,
                "unitCost": actualCost, // Use actual cost (purchase price), not selling price
                "status": status,
                "createdAt": Timestamp()
            ]
            
            // Handle optional references
            if let colorRef = phoneInfo.colorRef {
                phoneDocData["color"] = colorRef
            }
            if let carrierRef = phoneInfo.carrierRef {
                phoneDocData["carrier"] = carrierRef
            }
            if let storageRef = phoneInfo.storageRef {
                phoneDocData["storageLocation"] = storageRef
            }
            
            transaction.setData(phoneDocData, forDocument: newPhoneDocRef)
            print("   ✅ Phone document marked for creation: \(newPhoneDocRef.documentID)")
            
            // Re-create IMEI document
            print("   ➕ Re-creating IMEI document...")
            let imeiCollectionRef = db.collection("IMEI")
            let newImeiDocRef = imeiCollectionRef.document()
            
            let imeiDocData: [String: Any] = [
                "imei": imei,
                "phone": newPhoneDocRef,
                "brand": brand,
                "model": model,
                "createdAt": Timestamp()
            ]
            
            transaction.setData(imeiDocData, forDocument: newImeiDocRef)
            print("   ✅ IMEI document marked for creation: \(newImeiDocRef.documentID)")
        }
        print("✅ STEP 1 COMPLETE: All phones and IMEIs marked for re-creation")
        
        // STEP 2: Reverse Customer Balance
        if let customerRef = customerRef, let customerDoc = customerDoc, customerDoc.exists, var customerData = customerData {
            print("📍 STEP 2: Reversing customer balance...")
            var updatedData: [String: Any] = [:]
            
            // Remove from transaction history
            var transactionHistory = customerData["transactionHistory"] as? [[String: Any]] ?? []
            let originalCount = transactionHistory.count
            transactionHistory.removeAll { item in
                if let ref = item["salesReference"] as? DocumentReference {
                    return ref.documentID == self.transaction.id
                }
                return false
            }
            print("   📝 Removed from transaction history (was: \(originalCount), now: \(transactionHistory.count))")
            updatedData["transactionHistory"] = transactionHistory
            
            // Reverse balance
            let remainingCredit = paymentMethods["remainingCredit"] as? Double ?? 0.0
            let currentBalance = customerData["balance"] as? Double ?? 0.0
            let newBalance = currentBalance - abs(remainingCredit) // SUBTRACT (customer no longer owes us)
            updatedData["balance"] = newBalance
            
            print("   💰 Customer balance: \(currentBalance) - \(abs(remainingCredit)) = \(newBalance)")
            
            transaction.updateData(updatedData, forDocument: customerRef)
            print("   ✅ Customer balance reversal added to transaction")
        }
        print("✅ STEP 2 COMPLETE")
        
        // STEP 3: Reverse Middleman Balance
        if let middlemanRef = middlemanRef, let middlemanDoc = middlemanDoc, middlemanDoc.exists, var middlemanData = middlemanData {
            print("📍 STEP 3: Reversing middleman balance...")
            var updatedData: [String: Any] = [:]
            
            // Remove from transaction history
            var transactionHistory = middlemanData["transactionHistory"] as? [[String: Any]] ?? []
            let originalCount = transactionHistory.count
            transactionHistory.removeAll { item in
                if let ref = item["salesReference"] as? DocumentReference {
                    return ref.documentID == self.transaction.id
                }
                return false
            }
            print("   📝 Removed from transaction history (was: \(originalCount), now: \(transactionHistory.count))")
            updatedData["transactionHistory"] = transactionHistory
            
            // Reverse balance based on unit
            let middlemanUnit = middlemanPayment["unit"] as? String ?? ""
            let paymentSplit = middlemanPayment["paymentSplit"] as? [String: Any] ?? [:]
            let middlemanCredit = paymentSplit["credit"] as? Double ?? 0.0
            let currentBalance = middlemanData["balance"] as? Double ?? 0.0
            
            let newBalance: Double
            if middlemanUnit == "give" {
                newBalance = currentBalance + middlemanCredit // ADD back (reverse the deduction)
                print("   💰 Middleman balance (give mode): \(currentBalance) + \(middlemanCredit) = \(newBalance)")
            } else {
                newBalance = currentBalance - middlemanCredit // SUBTRACT back (reverse the addition)
                print("   💰 Middleman balance (receive mode): \(currentBalance) - \(middlemanCredit) = \(newBalance)")
            }
            updatedData["balance"] = newBalance
            
            transaction.updateData(updatedData, forDocument: middlemanRef)
            print("   ✅ Middleman balance reversal added to transaction")
        }
        print("✅ STEP 3 COMPLETE")
        
        // STEP 4: Reverse Account Balances
        print("📍 STEP 4: Reversing account balances...")
        
        let cashPaid = paymentMethods["cash"] as? Double ?? 0.0
        let bankPaid = paymentMethods["bank"] as? Double ?? 0.0
        let creditCardPaid = paymentMethods["creditCard"] as? Double ?? 0.0
        
        // Calculate final amounts with middleman adjustments
        var finalCash = cashPaid
        var finalBank = bankPaid
        var finalCard = creditCardPaid
        
        if middlemanRef != nil {
            let paymentSplit = middlemanPayment["paymentSplit"] as? [String: Any] ?? [:]
            let middlemanUnit = middlemanPayment["unit"] as? String ?? ""
            let mCash = paymentSplit["cash"] as? Double ?? 0.0
            let mBank = paymentSplit["bank"] as? Double ?? 0.0
            let mCard = paymentSplit["creditCard"] as? Double ?? 0.0
            
            print("   🤝 Applying middleman adjustments:")
            print("      Unit: \(middlemanUnit)")
            print("      M-Cash: \(mCash), M-Bank: \(mBank), M-Card: \(mCard)")
            
            if middlemanUnit == "give" {
                finalCash -= mCash
                finalBank -= mBank
                finalCard -= mCard
                print("      Mode: give - SUBTRACTING from final amounts")
            } else {
                finalCash += mCash
                finalBank += mBank
                finalCard += mCard
                print("      Mode: receive - ADDING to final amounts")
            }
        }
        
        print("   💵 Final amounts to reverse:")
        print("      Cash: \(finalCash)")
        print("      Bank: \(finalBank)")
        print("      Card: \(finalCard)")
        
        // Reverse cash balance (SUBTRACT back - money going out)
        if cashDoc.exists {
            let currentCashBalance = cashData["amount"] as? Double ?? 0.0
            let newCashBalance = currentCashBalance - finalCash // SUBTRACT back
            
            print("   💰 Cash balance: \(currentCashBalance) - \(finalCash) = \(newCashBalance)")
            transaction.updateData([
                "amount": newCashBalance,
                "updatedAt": Timestamp()
            ], forDocument: cashDocRef)
        }
        
        // Reverse bank balance (SUBTRACT back - money going out)
        if bankDoc.exists {
            let currentBankBalance = bankData["amount"] as? Double ?? 0.0
            let newBankBalance = currentBankBalance - finalBank // SUBTRACT back
            
            print("   🏦 Bank balance: \(currentBankBalance) - \(finalBank) = \(newBankBalance)")
            transaction.updateData([
                "amount": newBankBalance,
                "updatedAt": Timestamp()
            ], forDocument: bankDocRef)
        }
        
        // Reverse credit card balance (SUBTRACT back - money going out)
        if creditCardDoc.exists {
            let currentCreditCardBalance = creditCardData["amount"] as? Double ?? 0.0
            let newCreditCardBalance = currentCreditCardBalance - finalCard // SUBTRACT back
            
            print("   💳 Credit Card balance: \(currentCreditCardBalance) - \(finalCard) = \(newCreditCardBalance)")
            transaction.updateData([
                "amount": newCreditCardBalance,
                "updatedAt": Timestamp()
            ], forDocument: creditCardDocRef)
        }
        print("✅ STEP 4 COMPLETE: All account balances reversed")
        
        // STEP 5: Delete Order Number Document
        if let orderNumberRef = orderNumberRef {
            print("📍 STEP 5: Deleting order number document...")
            print("   🗑️ Marking order number for deletion: \(orderNumberRef.documentID)")
            transaction.deleteDocument(orderNumberRef)
            print("✅ STEP 5 COMPLETE")
        }
        
        // STEP 6: Delete Sales Document
        print("📍 STEP 6: Deleting sales document...")
        print("   🗑️ Marking sales document for deletion: \(self.transaction.id)")
        transaction.deleteDocument(salesRef)
        print("✅ STEP 6 COMPLETE")
        
        print("✅✅ reverseSalesTransaction() COMPLETE")
    }
    
    private func updateMyCashBalance(currency: String, amount: Double, transaction: FirestoreTransaction) throws {
        print("💵 updateMyCashBalance() called")
        print("   Currency: \(currency)")
        print("   Amount to add: \(amount)")
        
        let db = Firestore.firestore()
        let balancesRef = db.collection("Balances").document("cash")
        print("   📍 Reference: Balances/cash")
        
        // Get current balances
        print("   🔍 Fetching current balance document...")
        let balancesDoc = try transaction.getDocument(balancesRef)
        print("   ✅ Document fetched, exists: \(balancesDoc.exists)")
        var currentData = balancesDoc.data() ?? [:]
        print("   📊 Current data keys: \(currentData.keys)")
        
        if currency == "CAD" {
            // Update CAD amount
            let currentAmount = currentData["amount"] as? Double ?? 0.0
            let newAmount = currentAmount + amount
            currentData["amount"] = newAmount
            print("   💰 My CAD balance: \(currentAmount) + \(amount) = \(newAmount)")
        } else {
            // Update specific currency field
            let currentAmount = currentData[currency] as? Double ?? 0.0
            let newAmount = currentAmount + amount
            currentData[currency] = newAmount
            print("   💰 My \(currency) balance: \(currentAmount) + \(amount) = \(newAmount)")
        }
        
        // Add timestamp
        currentData["updatedAt"] = Timestamp()
        
        print("   📝 Adding balance update to transaction...")
        transaction.setData(currentData, forDocument: balancesRef, merge: true)
        print("   ✅ Balance update added to transaction")
    }
    
    private func updateMyBankBalance(amount: Double, transaction: FirestoreTransaction) throws {
        print("🏦 updateMyBankBalance() called")
        print("   Amount to add: \(amount)")
        
        let db = Firestore.firestore()
        let balancesRef = db.collection("Balances").document("bank")
        print("   📍 Reference: Balances/bank")
        
        // Get current balance
        print("   🔍 Fetching current balance document...")
        let balancesDoc = try transaction.getDocument(balancesRef)
        print("   ✅ Document fetched, exists: \(balancesDoc.exists)")
        var currentData = balancesDoc.data() ?? [:]
        
        // Update CAD amount (bank only supports CAD)
        let currentAmount = currentData["amount"] as? Double ?? 0.0
        let newAmount = currentAmount + amount
        currentData["amount"] = newAmount
        print("   💰 My BANK balance: \(currentAmount) + \(amount) = \(newAmount)")
        
        // Add timestamp
        currentData["updatedAt"] = Timestamp()
        
        print("   📝 Adding balance update to transaction...")
        transaction.setData(currentData, forDocument: balancesRef, merge: true)
        print("   ✅ Balance update added to transaction")
    }
    
    private func updateCustomerBalance(customerId: String, currency: String, amount: Double, transaction: FirestoreTransaction) throws {
        print("👤 updateCustomerBalance() called")
        print("   Customer ID: \(customerId)")
        print("   Currency: \(currency)")
        print("   Amount to add: \(amount)")
        
        let db = Firestore.firestore()
        
        // Determine which collection this customer belongs to (check synchronously)
        print("   🔍 Determining customer type...")
        var customerType: CustomerType? = nil
        var collectionName: String = ""
        
        // Check in Customers collection first
        let customersRef = db.collection("Customers").document(customerId)
        let customersDoc = try transaction.getDocument(customersRef)
        if customersDoc.exists {
            customerType = .customer
            collectionName = "Customers"
        } else {
            // Check in Middlemen collection
            let middlemenRef = db.collection("Middlemen").document(customerId)
            let middlemenDoc = try transaction.getDocument(middlemenRef)
            if middlemenDoc.exists {
                customerType = .middleman
                collectionName = "Middlemen"
            } else {
                // Check in Suppliers collection
                let suppliersRef = db.collection("Suppliers").document(customerId)
                let suppliersDoc = try transaction.getDocument(suppliersRef)
                if suppliersDoc.exists {
                    customerType = .supplier
                    collectionName = "Suppliers"
                }
            }
        }
        
        guard let customerType = customerType else {
            print("   ❌ Customer not found in any collection!")
            throw NSError(domain: "TransactionError", code: 404,
                         userInfo: [NSLocalizedDescriptionKey: "Customer not found in any collection"])
        }
        
        print("   ✅ Customer type: \(customerType.rawValue), Collection: \(collectionName)")
        
        if currency == "CAD" {
            // Update CAD balance in the appropriate collection
            let customerRef = db.collection(collectionName).document(customerId)
            print("   📍 Reference: \(collectionName)/\(customerId)")
            
            print("   🔍 Fetching customer document...")
            let customerDoc = try transaction.getDocument(customerRef)
            print("   ✅ Document fetched, exists: \(customerDoc.exists)")
            
            guard customerDoc.exists else {
                print("   ❌ Customer document does not exist!")
                throw NSError(domain: "TransactionError", code: 404,
                             userInfo: [NSLocalizedDescriptionKey: "\(customerType.displayName) not found"])
            }
            
            let currentBalance: Double = (customerDoc.data()?["balance"] as? Double) ?? 0.0
            let newBalance = currentBalance + amount
            
            print("   💰 \(customerType.displayName) CAD balance: \(currentBalance) + \(amount) = \(newBalance)")
            print("   📝 Adding CAD balance update to transaction...")
            transaction.updateData(["balance": newBalance, "updatedAt": Timestamp()], forDocument: customerRef)
            print("   ✅ CAD balance update added to transaction")
        } else {
            // Update non-CAD balance in CurrencyBalances collection
            let currencyBalanceRef = db.collection("CurrencyBalances").document(customerId)
            print("   📍 Reference: CurrencyBalances/\(customerId)")
            
            print("   🔍 Fetching currency balance document...")
            let currencyDoc = try transaction.getDocument(currencyBalanceRef)
            print("   ✅ Document fetched, exists: \(currencyDoc.exists)")
            var currentData = currencyDoc.data() ?? [:]
            print("   📊 Current data keys: \(currentData.keys)")
            
            let currentAmount = currentData[currency] as? Double ?? 0.0
            let newAmount = currentAmount + amount
            
            print("   💰 \(customerType.displayName) \(currency) balance: \(currentAmount) + \(amount) = \(newAmount)")
            
            currentData[currency] = newAmount
            currentData["updatedAt"] = Timestamp()
            print("   📝 Adding \(currency) balance update to transaction...")
            transaction.setData(currentData, forDocument: currencyBalanceRef, merge: true)
            print("   ✅ \(currency) balance update added to transaction")
        }
    }
    
    private func getCustomerType(customerId: String) async throws -> CustomerType {
        print("🔍 getCustomerType() called for ID: \(customerId)")
        
        // Handle special customer types
        if customerId == "myself_special_id" || customerId == "myself_bank_special_id" {
            print("   ✅ Special customer type detected: \(customerId)")
            return .customer
        }
        
        let db = Firestore.firestore()
        
        // Check in Customers collection first
        print("   🔍 Checking Customers collection...")
        let customersRef = db.collection("Customers").document(customerId)
        let customersDoc = try await customersRef.getDocument()
        if customersDoc.exists {
            print("   ✅ Found in Customers collection")
            return .customer
        }
        print("   ❌ Not in Customers")
        
        // Check in Middlemen collection
        print("   🔍 Checking Middlemen collection...")
        let middlemenRef = db.collection("Middlemen").document(customerId)
        let middlemenDoc = try await middlemenRef.getDocument()
        if middlemenDoc.exists {
            print("   ✅ Found in Middlemen collection")
            return .middleman
        }
        print("   ❌ Not in Middlemen")
        
        // Check in Suppliers collection
        print("   🔍 Checking Suppliers collection...")
        let suppliersRef = db.collection("Suppliers").document(customerId)
        let suppliersDoc = try await suppliersRef.getDocument()
        if suppliersDoc.exists {
            print("   ✅ Found in Suppliers collection")
            return .supplier
        }
        print("   ❌ Not in Suppliers")
        
        print("   ❌❌❌ Customer not found in ANY collection!")
        throw NSError(domain: "TransactionError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Customer not found in any collection"])
    }
}

struct TransactionFilterChip: View {
    let title: String
    @Binding var isActive: Bool
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isActive.toggle()
            }
        }) {
            HStack(spacing: 4) {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? color : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive
                          ? color.opacity(colorScheme == .dark ? 0.2 : 0.15)
                          : Color.gray.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .shadow(color: isActive ? color.opacity(0.2) : Color.clear, radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? color.opacity(0.4) : Color.gray.opacity(0.15), lineWidth: isActive ? 1.5 : 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// Custom button style for better tap feedback
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview {
    NavigationView {
        EntityDetailView(
            entity: EntityProfile(
                id: "preview",
                name: "John Doe",
                phone: "+1 234-567-8900",
                email: "john@example.com",
                balance: 1500.0,
                address: "123 Main St",
                notes: "Preview notes"
            ),
            entityType: .customer
        )
    }
}



