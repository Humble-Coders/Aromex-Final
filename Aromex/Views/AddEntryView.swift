import SwiftUI
#if os(macOS)
import AppKit
#endif
import FirebaseFirestore

// Add these enums at the top of the file

enum ProfitTimeframe: String, CaseIterable {
    case all = "All Time"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisYear = "This Year"
    case lastYear = "Last Year"
    
    var icon: String {
        switch self {
        case .all: return "clock"
        case .thisMonth: return "calendar"
        case .lastMonth: return "calendar.badge.clock"
        case .thisYear: return "calendar.badge.plus"
        case .lastYear: return "calendar.badge.minus"
        }
    }
}

// Color extensions are now in Shared/ColorExtensions.swift

struct CustomerBalancesView: View {
    let customer: Customer
    @State private var currencyBalances: [String: Double] = [:]
    @State private var isLoading = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        HStack(spacing: 8) {
            // Always show CAD balance first
            let roundedCADBalance = round(customer.balance * 100) / 100
            HStack(spacing: 2) {
                Text("CAD")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(roundedCADBalance, specifier: "%.2f")")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(abs(roundedCADBalance) < 0.01 ? .gray : (roundedCADBalance > 0 ? .green : .red))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.1))
            )
            
            // Show other currencies only if they have non-zero balances
            ForEach(Array(currencyBalances.keys.sorted()), id: \.self) { currencyName in
                if let balance = currencyBalances[currencyName] {
                    let roundedBalance = round(balance * 100) / 100
                    if abs(roundedBalance) >= 0.01 { // Only show if not effectively zero
                        HStack {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 2) {
                                Text(currencyName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(roundedBalance, specifier: "%.2f")")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(roundedBalance > 0 ? .green : .red)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.1))
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            fetchCurrencyBalances()
        }
    }
    
    private func fetchCurrencyBalances() {
        guard let customerId = customer.id, customerId != "myself_special_id" else {
            return
        }
        
        isLoading = true
        
        db.collection("CurrencyBalances").document(customerId).getDocument { snapshot, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("❌ Error fetching currency balances for \(customer.name): \(error.localizedDescription)")
                    return
                }
                
                guard let data = snapshot?.data() else {
                    print("📄 No currency balances found for \(customer.name)")
                    return
                }
                
                var balances: [String: Double] = [:]
                for (key, value) in data {
                    if key != "updatedAt", let doubleValue = value as? Double {
                        balances[key] = doubleValue
                    }
                }
                
                self.currencyBalances = balances
                print("💰 Loaded currency balances for \(customer.name): \(balances)")
            }
        }
    }
}

struct AddEntryView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @StateObject private var currencyManager = CurrencyManager.shared
    @StateObject private var transactionManager = TransactionManager.shared
    @State private var selectedFromCustomer: Customer?
    @State private var selectedToCustomer: Customer?
    @State private var amount: String = ""
    @State private var notes: String = ""
    @State private var isExchangeOn: Bool = false
    @State private var showingAddCustomerDialog: Bool = false
    @State private var showingAddCurrencyDialog: Bool = false
    @State private var isProcessingTransaction: Bool = false
    @State private var transactionError: String = ""
    @State private var showTransactionsTab: Bool = false
    @State private var selectedTransactionDate: Date = Date()
    @State private var showingExchangeRatesDialog: Bool = false
    @State private var totalExchangeProfit: [String: Double] = [:]
    
    // Exchange-specific fields
    @State private var selectedReceivingCurrency: Currency?
    @State private var customExchangeRate: String = ""
    @State private var showReceivingCurrencyDropdown: Bool = false
    @State private var receivingCurrencyButtonFrame: CGRect = .zero
    
    // Dropdown states
    @State private var selectedFromDropdownOpen: Bool = false
    @State private var selectedToDropdownOpen: Bool = false
    @State private var currencyDropdownOpen: Bool = false
    @State private var fromButtonFrame: CGRect = .zero
    @State private var toButtonFrame: CGRect = .zero
    @State private var currencyButtonFrame: CGRect = .zero
    
    // Separate search text for each dropdown
    @State private var fromSearchText: String = ""
    @State private var toSearchText: String = ""
    
    // Focus states for dropdown search fields
    @FocusState private var isFromFieldFocused: Bool
    @FocusState private var isToFieldFocused: Bool
    @FocusState private var isAmountFieldFocused: Bool
    
    // Environment to detect size class
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    
    @State private var selectedProfitTimeframe: ProfitTimeframe = .all
    @State private var showingTimeframeMenu: Bool = false
    
    @EnvironmentObject var navigationManager: CustomerNavigationManager
    
    @StateObject private var salesTransactionManager = SalesTransactionManager.shared
    @StateObject private var mixedTransactionManager = MixedTransactionManager.shared
    
    @State private var transactionSearchText = ""
    @State private var selectedTransactionFilters: Set<TransactionFilter> = [.normalCash] // Default: only normal cash
    @State private var selectedDateFilter: DateFilter = .all
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var filteredMixedTransactions: [AnyMixedTransaction] = []
    
    @State private var showingProfitBreakdown: Bool = false
    @State private var totalProfitInUSD: Double = 0.0
    
    @State private var showingDirectRateDialog = false
    @State private var pendingDirectRateCallback: ((Double) -> Void)?


    // Computed properties
    private var shouldUseVerticalLayout: Bool {
        #if os(iOS)
        // iPhone always uses vertical layout, iPad uses horizontal layout
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
    
    private var horizontalPadding: CGFloat {
        #if os(iOS)
        return shouldUseVerticalLayout ? 16 : 40 // Reduced padding for iPhone
        #else
        return 40
        #endif
    }

    private var hasActiveFilters: Bool {
        return !transactionSearchText.isEmpty ||
               selectedTransactionFilters.count != 1 || // Not default (only normalCash)
               !selectedTransactionFilters.contains(.normalCash) ||
               selectedDateFilter != .all
    }

    private var customDateRangeView: some View {
        VStack(spacing: 12) {
            Text("Custom Date Range")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            if shouldUseVerticalLayout {
                VStack(spacing: 8) {
                    DatePicker("From", selection: $customStartDate, displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())
                        .onChange(of: customStartDate) { _ in applyTransactionFilters() }
                    
                    DatePicker("To", selection: $customEndDate, displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())
                        .onChange(of: customEndDate) { _ in applyTransactionFilters() }
                }
            } else {
                HStack(spacing: 16) {
                    DatePicker("From", selection: $customStartDate, displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())
                        .onChange(of: customStartDate) { _ in applyTransactionFilters() }
                    
                    DatePicker("To", selection: $customEndDate, displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())
                        .onChange(of: customEndDate) { _ in applyTransactionFilters() }
                }
            }
        }
        .padding(.top, 8)
    }

    // Add these methods to AddEntryView
    private func toggleTransactionFilter(_ filter: TransactionFilter) {
        if selectedTransactionFilters.contains(filter) {
            selectedTransactionFilters.remove(filter)
        } else {
            selectedTransactionFilters.insert(filter)
        }
        applyTransactionFilters()
    }

    private func clearAllFilters() {
        transactionSearchText = ""
        selectedTransactionFilters = [.normalCash] // Reset to default (only normal cash)
        selectedDateFilter = .all
        applyTransactionFilters()
    }

    private func applyTransactionFilters() {
        // Use the shared extension for filtering
        filteredMixedTransactions = mixedTransactionManager.mixedTransactions.applyTransactionFilters(
            searchText: transactionSearchText,
            selectedFilters: selectedTransactionFilters,
            dateFilter: selectedDateFilter,
            customStartDate: customStartDate,
            customEndDate: customEndDate
        )
    }

    // Add the TransactionFilterButton component
    
    // Computed properties for validation
    private var isTransactionValid: Bool {
        let basicValidation = selectedFromCustomer != nil &&
               selectedToCustomer != nil &&
               !amount.trimmingCharacters(in: .whitespaces).isEmpty &&
               Double(amount.trimmingCharacters(in: .whitespaces)) != nil &&
               Double(amount.trimmingCharacters(in: .whitespaces))! > 0 &&
               currencyManager.selectedCurrency != nil &&
               selectedFromCustomer?.id != selectedToCustomer?.id
        
        if isExchangeOn {
            return basicValidation &&
                   selectedReceivingCurrency != nil &&
                   !customExchangeRate.trimmingCharacters(in: .whitespaces).isEmpty &&
                   Double(customExchangeRate.trimmingCharacters(in: .whitespaces)) != nil &&
                   Double(customExchangeRate.trimmingCharacters(in: .whitespaces))! > 0 &&
                   selectedReceivingCurrency?.id != currencyManager.selectedCurrency?.id
        }
        
        return basicValidation
    }
    
    // Filtered customers with "Myself" option
    private var filteredFromCustomers: [Customer] {
        var customers = [myselfCustomer]
        if fromSearchText.isEmpty {
            customers.append(contentsOf: firebaseManager.customers)
        } else {
            if "Myself".localizedCaseInsensitiveContains(fromSearchText) {
                // Keep "Myself" if search matches
            } else {
                customers.removeFirst() // Remove "Myself" if search doesn't match
            }
            customers.append(contentsOf: firebaseManager.customers.filter {
                $0.name.localizedCaseInsensitiveContains(fromSearchText)
            })
        }
        return customers
    }
    
    private var filteredToCustomers: [Customer] {
        var customers = [myselfCustomer]
        if toSearchText.isEmpty {
            customers.append(contentsOf: firebaseManager.customers)
        } else {
            if "Myself".localizedCaseInsensitiveContains(toSearchText) {
                // Keep "Myself" if search matches
            } else {
                customers.removeFirst() // Remove "Myself" if search doesn't match
            }
            customers.append(contentsOf: firebaseManager.customers.filter {
                $0.name.localizedCaseInsensitiveContains(toSearchText)
            })
        }
        return customers
    }
    
    private func validateDirectRateExists(from: Currency, to: Currency) -> Bool {
        return getMarketRateFromDirectRates(from: from, to: to) != nil
    }
    
    // Create "Myself" customer instance
    private var myselfCustomer: Customer {
        Customer(
            id: "myself_special_id",
            name: "Myself",
            phone: "",
            email: "",
            address: "",
            notes: "",
            balance: 0.0,
            type: .customer,
            createdAt: nil,
            updatedAt: nil
        )
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header - Only show on iOS
                #if os(iOS)
                
                #endif
                
                // Main Content
                ScrollView {
                    VStack(spacing: 32) {
                        // Transaction Section
                        transactionSection
                        
                        // All Transactions Section
                        allTransactionsSection
                        
                        
                        // Status indicators
                        statusIndicators
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 5)
                }
                .background(Color.systemBackground)
            }
            
            // Dropdown overlays
            if selectedFromDropdownOpen {
                CustomerDropdownOverlay(
                    isOpen: $selectedFromDropdownOpen,
                    selectedCustomer: $selectedFromCustomer,
                    customers: filteredFromCustomers,
                    buttonFrame: fromButtonFrame
                )
            }
            
            if selectedToDropdownOpen {
                CustomerDropdownOverlay(
                    isOpen: $selectedToDropdownOpen,
                    selectedCustomer: $selectedToCustomer,
                    customers: filteredToCustomers,
                    buttonFrame: toButtonFrame
                )
            }
            
            if currencyDropdownOpen {
                CurrencyDropdownOverlay(
                    isOpen: $currencyDropdownOpen,
                    selectedCurrency: Binding(
                        get: { currencyManager.selectedCurrency },
                        set: { newCurrency in
                            currencyManager.selectedCurrency = newCurrency
                            if newCurrency != nil && isExchangeOn {
                                handleGivingCurrencySelection()
                            }
                        }
                    ),
                    currencies: currencyManager.allCurrencies,
                    buttonFrame: currencyButtonFrame,
                    onAddCurrency: {
                        currencyDropdownOpen = false
                        showingAddCurrencyDialog = true
                    }
                )
            }

            // For receiving currency dropdown:
            if showReceivingCurrencyDropdown {
                CurrencyDropdownOverlay(
                    isOpen: $showReceivingCurrencyDropdown,
                    selectedCurrency: Binding(
                        get: { selectedReceivingCurrency },
                        set: { newCurrency in
                            selectedReceivingCurrency = newCurrency
                            if newCurrency != nil && isExchangeOn {
                                handleReceivingCurrencySelection()
                            }
                        }
                    ),
                    currencies: currencyManager.allCurrencies,
                    buttonFrame: receivingCurrencyButtonFrame,
                    onAddCurrency: {
                        showReceivingCurrencyDropdown = false
                        showingAddCurrencyDialog = true
                    }
                )
            }
        }
        .onAppear {
            isAmountFieldFocused = false
            currencyManager.fetchCurrencies()
            transactionManager.fetchTransactions()
            salesTransactionManager.fetchSalesTransactions()
            refreshEntireScreen()
            applyTransactionFilters()
        }
        .onChange(of: selectedFromDropdownOpen) { isOpen in
            isFromFieldFocused = isOpen
            if isOpen {
                isAmountFieldFocused = false
                currencyDropdownOpen = false
            }
        }
        .onChange(of: selectedToDropdownOpen) { isOpen in
            isToFieldFocused = isOpen
            if isOpen {
                isAmountFieldFocused = false
                currencyDropdownOpen = false
            }
        }
        .onChange(of: currencyManager.selectedCurrency) { newValue in
            if newValue != nil && isExchangeOn {
                handleGivingCurrencySelection()
            }
        }
        .onChange(of: selectedReceivingCurrency) { newValue in
            if newValue != nil && isExchangeOn {
                handleReceivingCurrencySelection()
            }
        }
        .onChange(of: isExchangeOn) { newValue in
            if !newValue {
                selectedReceivingCurrency = nil
                customExchangeRate = ""
            } else {
                // When exchange is turned on, try to auto-populate if both currencies are selected
                if currencyManager.selectedCurrency != nil && selectedReceivingCurrency != nil {
                    handleCurrencySelection()
                }
            }
        }
        .onChange(of: currencyDropdownOpen) { isOpen in
            if isOpen {
                isAmountFieldFocused = false
                selectedFromDropdownOpen = false
                selectedToDropdownOpen = false
                showReceivingCurrencyDropdown = false
            }
        }
        .onChange(of: showReceivingCurrencyDropdown) { isOpen in
            if isOpen {
                isAmountFieldFocused = false
                selectedFromDropdownOpen = false
                selectedToDropdownOpen = false
                currencyDropdownOpen = false
            }
        }
        .onChange(of: isExchangeOn) { isOn in
            if !isOn {
                selectedReceivingCurrency = nil
                customExchangeRate = ""
            }
        }
        .sheet(isPresented: $showingAddCustomerDialog) {
            AddCustomerDialog(isPresented: $showingAddCustomerDialog)
        }
        .sheet(isPresented: $showingAddCurrencyDialog) {
            AddCurrencyDialog()
                .environmentObject(currencyManager)
        }
        .sheet(isPresented: $showingExchangeRatesDialog) {
            ExchangeRatesDialog()
                .environmentObject(currencyManager)
        }
        .onChange(of: mixedTransactionManager.mixedTransactions) { _ in
            applyTransactionFilters()
        }
        // Add this to monitor transaction changes
        .onReceive(mixedTransactionManager.$mixedTransactions) { _ in
            applyTransactionFilters()
        }

        .sheet(isPresented: $showingDirectRateDialog) {
            if let givingCurrency = currencyManager.selectedCurrency,
               let receivingCurrency = selectedReceivingCurrency {
                DirectRateInputDialog(
                    givingCurrency: givingCurrency,
                    receivingCurrency: receivingCurrency,
                    onRateProvided: { providedRate in
                        print("✅ Rate provided from dialog: \(providedRate)")
                        showingDirectRateDialog = false
                        pendingDirectRateCallback?(providedRate)
                        
                        // Force refresh the currency manager to pick up the new rate
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            currencyManager.fetchDirectExchangeRates()
                        }
                    },
                    onCancel: {
                        print("❌ Dialog cancelled")
                        showingDirectRateDialog = false
                        // Clear the rate field since user cancelled
                        customExchangeRate = ""
                    }
                )
                .environmentObject(currencyManager)
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .foregroundColor(.blue)
            }
        }
        #endif
    }
    
    private var headerView: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.2, green: 0.3, blue: 0.5),
                    Color(red: 0.3, green: 0.4, blue: 0.6)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            
            if shouldUseVerticalLayout {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Image(systemName: "building.2.crop.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                        
                        Text("AROMEX")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Refresh Button
                        Button(action: refreshEntireScreen) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Text("Transaction Entry")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    // Exchange Rates Bar (Vertical)
                    exchangeRatesBarVertical
                    
                    // Total Exchange Profit Bar (Vertical)
                    totalExchangeProfitBarVertical
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 16) {
                    HStack {
                        HStack(spacing: 16) {
                            Image(systemName: "building.2.crop.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.white)
                            
                            Text("AROMEX")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        Text("Transaction Entry")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                        
                        HStack(spacing: 16) {
                            // Refresh Button
                            Button(action: refreshEntireScreen) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.body)
                                    Text("Refresh")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {}) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // Exchange Rates Bar (Horizontal)
                    exchangeRatesBarHorizontal
                    
                    // Total Exchange Profit Bar (Horizontal)
                    totalExchangeProfitBarHorizontal
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 24)
            }
        }
        .frame(height: shouldUseVerticalLayout ? 240 : 180)
    }
    
    // ADDED: Missing transactionSection
    private var transactionSection: some View {
        VStack(spacing: shouldUseVerticalLayout ? 24 : 40) { // Reduced spacing for iPhone
            // Section Header
            
            
            
            // Transaction Form
            VStack(spacing: shouldUseVerticalLayout ? 20 : 32) { // Reduced spacing for iPhone
                if shouldUseVerticalLayout {
                    verticalTransactionForm
                } else {
                    horizontalTransactionForm
                }
            }
            .padding(.vertical, shouldUseVerticalLayout ? 20 : 32) // Reduced padding for iPhone
            .background(Color.white)
            .cornerRadius(shouldUseVerticalLayout ? 12 : 16) // Smaller corner radius for iPhone
            .shadow(color: .black.opacity(0.08), radius: shouldUseVerticalLayout ? 8 : 12, x: 0, y: shouldUseVerticalLayout ? 2 : 4) // Smaller shadow for iPhone
            .padding(.horizontal, horizontalPadding)
        }
    }
    
    private var allTransactionsSection: some View {
        VStack(spacing: 24) {
            // Section Header with Search and Filters
            VStack(spacing: 16) {
                // Title Row
                HStack {
                    HStack(spacing: 16) {
                        Image(systemName: "doc.text.fill")
                            .font(shouldUseVerticalLayout ? .title2 : .title)
                            .foregroundColor(.blue)
                        
                        Text("All Transactions")
                            .font(shouldUseVerticalLayout ? .title2 : .title)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    if !filteredMixedTransactions.isEmpty {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(filteredMixedTransactions.count) transactions")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Search Bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Search by name, amount, or notes...", text: $transactionSearchText)
                        .font(.system(size: 16, weight: .medium))
                        .textFieldStyle(PlainTextFieldStyle())
                        .onChange(of: transactionSearchText) { _ in
                            applyTransactionFilters()
                        }
                    
                    if !transactionSearchText.isEmpty {
                        Button(action: {
                            transactionSearchText = ""
                            applyTransactionFilters()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.systemGray6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                )
                
                // Filter Controls
                VStack(spacing: shouldUseVerticalLayout ? 12 : 16) {
                    // Transaction Type Filters
                    VStack(alignment: .leading, spacing: shouldUseVerticalLayout ? 6 : 8) {
                        Text("Transaction Types")
                            .font(.system(size: shouldUseVerticalLayout ? 13 : 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        // All filters in one row for both layouts
                        HStack(spacing: shouldUseVerticalLayout ? 6 : 8) {
                            ForEach(TransactionFilter.allCases, id: \.self) { filter in
                                TransactionFilterButton(
                                    filter: filter,
                                    isSelected: selectedTransactionFilters.contains(filter),
                                    action: { toggleTransactionFilter(filter) }
                                )
                            }
                        }
                    }
                    
                    // Date Filter
                    HStack(spacing: shouldUseVerticalLayout ? 12 : 16) {
                        VStack(alignment: .leading, spacing: shouldUseVerticalLayout ? 6 : 8) {
                            Text("Date Range")
                                .font(.system(size: shouldUseVerticalLayout ? 13 : 14, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Picker("Date Filter", selection: $selectedDateFilter) {
                                ForEach(DateFilter.allCases, id: \.self) { filter in
                                    HStack {
                                        Image(systemName: filter.icon)
                                        Text(filter.rawValue)
                                    }
                                    .tag(filter)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: shouldUseVerticalLayout ? .infinity : 200)
                            .padding(.horizontal, shouldUseVerticalLayout ? 10 : 12)
                            .padding(.vertical, shouldUseVerticalLayout ? 6 : 8)
                            .background(
                                RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 6 : 8)
                                    .fill(Color.systemGray6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 6 : 8)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            )
                            .onChange(of: selectedDateFilter) { _ in
                                applyTransactionFilters()
                            }
                        }
                        
                        if !shouldUseVerticalLayout {
                            Spacer()
                            
                            // Clear All Filters Button
                            Button(action: clearAllFilters) {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                    Text("Clear All")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.red)
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // Clear All button for vertical layout
                    if shouldUseVerticalLayout {
                        Button(action: clearAllFilters) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                Text("Clear All Filters")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, shouldUseVerticalLayout ? 8 : 10)
                            .background(Color.red)
                            .cornerRadius(shouldUseVerticalLayout ? 6 : 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Custom Date Range (if selected)
                    if selectedDateFilter == .custom {
                        customDateRangeView
                    }
                }
                .padding(.horizontal, shouldUseVerticalLayout ? 12 : 16)
                .padding(.vertical, shouldUseVerticalLayout ? 12 : 16)
                .background(
                    RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 10 : 12)
                        .fill(Color.systemGray6.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 10 : 12)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, horizontalPadding)
            
            // Transactions List
            VStack(spacing: 16) {
                if transactionManager.isLoading || salesTransactionManager.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading transactions...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 40)
                } else if filteredMixedTransactions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: hasActiveFilters ? "doc.text.magnifyingglass" : "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text(hasActiveFilters ? "No transactions match your filters" : "No transactions yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text(hasActiveFilters ? "Try adjusting your search or filter criteria" : "Start by adding your first transaction above")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        if hasActiveFilters {
                            Button(action: clearAllFilters) {
                                Text("Clear All Filters")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredMixedTransactions) { mixedTransaction in
                            // Only show currency transactions
                            if let currencyTx = mixedTransaction.currencyTransaction {
                                TransactionRowView(transaction: currencyTx)
                                    .environmentObject(FirebaseManager.shared)
                                    .environmentObject(CustomerNavigationManager.shared)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }
    private var horizontalTransactionForm: some View {
        VStack(spacing: horizontalSizeClass == .compact ? 24 : 32) {
            // Main Transaction Row - Everything in One Line - CENTERED
            HStack(alignment: .top, spacing: horizontalSizeClass == .compact ? 12 : 16) {
                Spacer() // Left spacer to center content
                
                // FROM Section
                VStack(alignment: .leading, spacing: horizontalSizeClass == .compact ? 6 : 8) {
                    Text("From")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    SimpleDropdownButton(
                        selectedCustomer: selectedFromCustomer,
                        placeholder: "Select customer",
                        isOpen: $selectedFromDropdownOpen,
                        buttonFrame: $fromButtonFrame,
                        searchText: $fromSearchText,
                        isFocused: $isFromFieldFocused
                    )
                    .frame(width: horizontalSizeClass == .compact ? 140 : 160, height: 44)
                }
                
                // Arrow Connector
                VStack(spacing: 4) {
                    Spacer().frame(height: 18) // Align with dropdowns
                    HStack(spacing: 4) {
                        Text("gives to")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blue)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .frame(height: 44)
                    .padding(.horizontal, horizontalSizeClass == .compact ? 6 : 8)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                }
                .frame(width: horizontalSizeClass == .compact ? 70 : 90)
                
                // TO Section
                VStack(alignment: .leading, spacing: horizontalSizeClass == .compact ? 6 : 8) {
                    Text("To")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    SimpleDropdownButton(
                        selectedCustomer: selectedToCustomer,
                        placeholder: "Select customer",
                        isOpen: $selectedToDropdownOpen,
                        buttonFrame: $toButtonFrame,
                        searchText: $toSearchText,
                        isFocused: $isToFieldFocused
                    )
                    .frame(width: horizontalSizeClass == .compact ? 140 : 160, height: 44)
                }
                
                // AMOUNT Section (Combined Currency + Amount)
                VStack(alignment: .leading, spacing: horizontalSizeClass == .compact ? 6 : 8) {
                    Text("Amount")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    combinedAmountCurrencyField
                        .frame(width: horizontalSizeClass == .compact ? 160 : 180, height: 44)
                }
                
                // DATE Section
                VStack(alignment: .leading, spacing: horizontalSizeClass == .compact ? 6 : 8) {
                    Text("Date")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    DatePicker("", selection: $selectedTransactionDate, displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())
                        .labelsHidden()
                        .frame(width: horizontalSizeClass == .compact ? 110 : 130, height: 44)
                        .background(Color.white)
                        
                }
                
                // EXCHANGE RATE Section (only if exchange is on) - Only show on iOS
                #if os(iOS)
                if isExchangeOn {
                    VStack(alignment: .leading, spacing: horizontalSizeClass == .compact ? 6 : 8) {
                        Text("Exchange Rate")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        exchangeRateCompactField
                            .frame(width: horizontalSizeClass == .compact ? 180 : 200, height: 44)
                    }
                }
                #endif
                

                
                // ACTION BUTTONS
                HStack(spacing: horizontalSizeClass == .compact ? 8 : 12) {
                    // Add Customer Button
                    VStack(spacing: horizontalSizeClass == .compact ? 2 : 4) {
                        Spacer().frame(height: horizontalSizeClass == .compact ? 16 : 18) // Align with other elements
                        Button(action: { showingAddCustomerDialog = true }) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: horizontalSizeClass == .compact ? 40 : 44, height: 44)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Add Transaction Button
                    VStack(spacing: horizontalSizeClass == .compact ? 2 : 4) {
                        Spacer().frame(height: horizontalSizeClass == .compact ? 16 : 18) // Align with other elements
                        Button(action: { addTransaction() }) {
                            Text(isProcessingTransaction ? "⏳" : "Add")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: horizontalSizeClass == .compact ? 50 : 60, height: 44)
                                .background(
                                    isTransactionValid && !isProcessingTransaction ?
                                    Color(red: 0.3, green: 0.4, blue: 0.6) : Color.gray.opacity(0.5)
                                )
                                .cornerRadius(8)
                        }
                        .disabled(!isTransactionValid || isProcessingTransaction)
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                Spacer() // Right spacer to center content
            }
            
            // Customer Balances Row (shown below main row when customers are selected) - CENTERED
            if selectedFromCustomer != nil || selectedToCustomer != nil {
                HStack {
                    Spacer()
                    customerBalancesRow
                    Spacer()
                }
            }
            
            // Exchange Details Row (shown below when exchange is on and values are entered) - CENTERED - Only show on iOS
            #if os(iOS)
            if isExchangeOn && shouldShowExchangeDetails {
                HStack {
                    Spacer()
                    exchangeDetailsRow
                    Spacer()
                }
            }
            #endif
            
            // Notes Row - CENTERED
            HStack {
                Spacer()
                notesRow
                Spacer()
            }
        }
    }

    private var verticalTransactionForm: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Card
                
                
                // Transaction Flow Card
                VStack(spacing: 16) {
                    // FROM Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                            Text("From")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        SimpleDropdownButton(
                            selectedCustomer: selectedFromCustomer,
                            placeholder: "Select customer",
                            isOpen: $selectedFromDropdownOpen,
                            buttonFrame: $fromButtonFrame,
                            searchText: $fromSearchText,
                            isFocused: $isFromFieldFocused
                        )
                        .frame(height: 44)
                        
                        // Show balance immediately below
                        if let customer = selectedFromCustomer {
                            HStack {
                                compactCustomerBalance(for: customer)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    // Flow Arrow
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("gives to")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.blue)
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.blue)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        .padding(.vertical, 8)
                        Spacer()
                    }
                    
                    // TO Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.green)
                            Text("To")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        SimpleDropdownButton(
                            selectedCustomer: selectedToCustomer,
                            placeholder: "Select customer",
                            isOpen: $selectedToDropdownOpen,
                            buttonFrame: $toButtonFrame,
                            searchText: $toSearchText,
                            isFocused: $isToFieldFocused
                        )
                        .frame(height: 44)
                        
                        // Show balance immediately below
                        if let customer = selectedToCustomer {
                            HStack {
                                compactCustomerBalance(for: customer)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.top, 5).padding(.bottom, 16).padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.systemBackground)
                        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
                        )
                )
                
                // Transaction Details Card
                VStack(spacing: 16) {
                    // AMOUNT Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.orange)
                            Text("Amount")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        combinedAmountCurrencyField
                            .frame(height: 44)
                    }
                    
                    // DATE Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "calendar.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.purple)
                            Text("Date")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        #if os(iOS)
                        DatePicker("", selection: $selectedTransactionDate, displayedComponents: .date)
                            .datePickerStyle(CompactDatePickerStyle())
                            .labelsHidden()
                            .frame(height: 44)
                            .background(Color.systemBackground)
                            .cornerRadius(10)
                            
                        #else
                        DatePicker("", selection: $selectedTransactionDate, displayedComponents: .date)
                            .datePickerStyle(CompactDatePickerStyle())
                            .labelsHidden()
                            .frame(height: 44)
                            .background(Color.systemBackground)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        #endif
                    }
                    
                    // EXCHANGE RATE Section - Only show on iOS
                    #if os(iOS)
                    if isExchangeOn {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.2.squarepath")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.red)
                                Text("Exchange Rate")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            
                            exchangeRateCompactField
                                .frame(height: 44)
                            
                            // Show profit/loss immediately below
                            if shouldShowExchangeDetails {
                                VStack(alignment: .leading, spacing: 8) {
                                    Divider()
                                        .background(Color.gray.opacity(0.3))
                                    exchangeProfitLossDisplay
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                    #endif
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.systemBackground)
                        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.1), lineWidth: 1)
                        )
                )
                
                // Notes Card
                VStack(alignment: .leading, spacing: 8) {
                    
                    notesRow
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.systemBackground)
                        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.indigo.opacity(0.1), lineWidth: 1)
                        )
                )
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: { addTransaction() }) {
                        HStack(spacing: 8) {
                            if isProcessingTransaction {
                                ProgressView()
                                    .scaleEffect(0.9)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Processing...")
                                    .font(.system(size: 16, weight: .semibold))
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Add Transaction")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            isTransactionValid && !isProcessingTransaction ?
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                gradient: Gradient(colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.5)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(
                            color: isTransactionValid && !isProcessingTransaction ?
                            Color.blue.opacity(0.3) : Color.clear,
                            radius: 8, x: 0, y: 4
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!isTransactionValid || isProcessingTransaction)
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(isTransactionValid && !isProcessingTransaction ? 1.0 : 0.98)
                    .animation(.easeInOut(duration: 0.15), value: isTransactionValid)
                    
                    Button(action: { showingAddCustomerDialog = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 14, weight: .medium))
                            Text("Add New Customer")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // Combined Amount and Currency Field (Compact)
    private var combinedAmountCurrencyField: some View {
        HStack(spacing: 0) {
            // Currency Button (Left)
            Button(action: { currencyDropdownOpen.toggle() }) {
                HStack(spacing: 3) {
                    Text(currencyManager.selectedCurrency?.symbol ?? "$")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    Text(currencyManager.selectedCurrency?.name ?? "CAD")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                    Image(systemName: currencyDropdownOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .frame(height: 40)
                .background(Color.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .background(
                GeometryReader { geometry in
                    Color.clear.onAppear {
                        currencyButtonFrame = geometry.frame(in: .global)
                    }
                }
            )
            
            // Amount Input (Right)
            TextField("0.00", text: $amount)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .focused($isAmountFieldFocused)
                #if os(iOS)
                .keyboardType(.decimalPad)
                .onSubmit {
                    isAmountFieldFocused = false
                }
                #endif
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    // Compact Exchange Rate Field
    // Replace your exchangeRateCompactField with this debugging version:
    private var exchangeRateCompactField: some View {
        HStack(spacing: 8) {
            if let displayCurrencies = getDisplayCurrencies() {
                // Left side - bigger currency
                HStack(spacing: 4) {
                    Text("1")
                        .font(.system(size: 14, weight: .semibold))
                    Text(displayCurrencies.left.name)
                        .font(.system(size: 12, weight: .medium))
                    Text("=")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .frame(height: 44)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
                
                // Rate Input
                TextField("Rate", text: Binding(
                    get: { customExchangeRate },
                    set: { newValue in
                        handleExchangeRateInputChange(newValue)
                    }
                ))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .padding(.horizontal, 8)
                .frame(width: 80, height: 44)
                .background(Color.white)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                
                // Right side - smaller currency
                Text(displayCurrencies.right.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
            } else {
                // Fallback to original design if currencies not selected
                HStack(spacing: 4) {
                    Text("1")
                        .font(.system(size: 14, weight: .semibold))
                    Text(currencyManager.selectedCurrency?.name ?? "USD")
                        .font(.system(size: 12, weight: .medium))
                    Text("=")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .frame(height: 44)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                
                TextField("Rate", text: $customExchangeRate)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .padding(.horizontal, 8)
                    .frame(width: 60, height: 44)
                    .background(Color.white)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                Button(action: {
                    showReceivingCurrencyDropdown.toggle()
                }) {
                    Text(selectedReceivingCurrency?.name ?? "Select")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 44)
                        .background(Color.orange)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .background(
                    GeometryReader { geometry in
                        Color.clear.onAppear {
                            receivingCurrencyButtonFrame = geometry.frame(in: .global)
                        }
                    }
                )
            }
        }
    }

    // Customer Balances Row
    private var customerBalancesRow: some View {
        HStack(spacing: 40) {
            // From Customer Balance
            if let customer = selectedFromCustomer {
                HStack(spacing: 12) {
                    Text("\(customer.name) balances:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    CustomerBalancesView(customer: customer)
                }
            }
            
            Spacer()
            
            // To Customer Balance
            if let customer = selectedToCustomer {
                HStack(spacing: 12) {
                    Text("\(customer.name) balances:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    CustomerBalancesView(customer: customer)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
        .padding(.horizontal, 20)
    }

    // Exchange Details Row
    private var exchangeDetailsRow: some View {
        exchangeProfitLossDisplay
            .padding(.horizontal, 20)
    }

    // Compact Customer Balance (for vertical layout)
    private func compactCustomerBalance(for customer: Customer) -> some View {
        HStack(spacing: 6) {
            Text("Balances:")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            
            CustomerBalancesView(customer: customer)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(5)
    }

    private func calculateMarketRate(from: Currency, to: Currency) -> Double? {
        // Check if we need direct rate
        if currencyManager.requiresDirectRate(givingCurrency: from, receivingCurrency: to) {
            return currencyManager.getDirectExchangeRate(from: from.name, to: to.name)
        }
        
        // Use existing USD-based calculation
        return (1.0 / from.exchangeRate) * to.exchangeRate
    }

    // Add these methods to your AddEntryView:

    private func handleExchangeRateInputChange(_ newValue: String) {
        customExchangeRate = newValue
        
        // Only proceed if user actually typed something
        guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        // Check if both currencies are selected
        guard let givingCurrency = currencyManager.selectedCurrency,
              let receivingCurrency = selectedReceivingCurrency else {
            print("⚠️ Missing currencies")
            return
        }
        
        print("🔍 Checking currencies: \(givingCurrency.name) → \(receivingCurrency.name)")
        
        // Always check if we have a direct rate available
        let hasDirectRate = getMarketRateFromDirectRates(from: givingCurrency, to: receivingCurrency) != nil
        
        if !hasDirectRate {
            print("🚨 No direct rate found! Showing dialog...")
            showingDirectRateDialog = true
            pendingDirectRateCallback = { providedRate in
                print("✅ Direct rate provided: \(providedRate)")
            }
        }
    }
    
    // MARK: - Exchange Rate Helper Methods
//    private func getBiggerCurrency(from currency1: Currency, to currency2: Currency) -> Currency {
//        // Currency with LOWER exchange rate has HIGHER value (is "bigger")
//        // Because lower exchangeRate means fewer units needed to equal 1 CAD
//        return currency1.exchangeRate <= currency2.exchangeRate ? currency1 : currency2
//    }
//
//    private func getSmallerCurrency(from currency1: Currency, to currency2: Currency) -> Currency {
//        // Currency with HIGHER exchange rate has LOWER value (is "smaller")
//        // Because higher exchangeRate means more units needed to equal 1 CAD
//        return currency1.exchangeRate > currency2.exchangeRate ? currency1 : currency2
//    }

    private func getBiggerCurrencyFallback(from currency1: Currency, to currency2: Currency) -> (left: Currency, right: Currency) {
        // Use the original logic as fallback
        let biggerCurrency = currency1.exchangeRate <= currency2.exchangeRate ? currency1 : currency2
        let smallerCurrency = currency1.exchangeRate > currency2.exchangeRate ? currency1 : currency2
        return (left: biggerCurrency, right: smallerCurrency)
    }
    
    private func getDisplayCurrencies() -> (left: Currency, right: Currency)? {
        guard let givingCurrency = currencyManager.selectedCurrency,
              let receivingCurrency = selectedReceivingCurrency else {
            return nil
        }
        
        // Get both possible rates from DirectExchangeRates
        let rate1 = currencyManager.getDirectExchangeRate(from: givingCurrency.name, to: receivingCurrency.name)
        let rate2 = currencyManager.getDirectExchangeRate(from: receivingCurrency.name, to: givingCurrency.name)
        
        // Determine which direction gives us a rate >= 1.0
        if let directRate = rate1, directRate >= 1.0 {
            // 1 givingCurrency = directRate receivingCurrency (rate >= 1)
            return (left: givingCurrency, right: receivingCurrency)
        } else if let reverseRate = rate2, reverseRate >= 1.0 {
            // 1 receivingCurrency = reverseRate givingCurrency (rate >= 1)
            return (left: receivingCurrency, right: givingCurrency)
        } else if let directRate = rate1 {
            // Use direct rate even if < 1 (fallback)
            return (left: givingCurrency, right: receivingCurrency)
        } else if let reverseRate = rate2 {
            // Use reverse rate even if < 1 (fallback)
            return (left: receivingCurrency, right: givingCurrency)
        } else {
            // No direct rates available, fallback to original logic
            return getBiggerCurrencyFallback(from: givingCurrency, to: receivingCurrency)
        }
    }

    private func convertRateForCalculation(displayRate: Double) -> Double {
        guard let displayCurrencies = getDisplayCurrencies(),
              let givingCurrency = currencyManager.selectedCurrency,
              let receivingCurrency = selectedReceivingCurrency else {
            return displayRate
        }
        
        // If the display order matches the actual transaction order, use rate as is
        if displayCurrencies.left.name == givingCurrency.name {
            return displayRate
        } else {
            // Display shows bigger=smaller, but we need smaller=bigger for calculation
            // So we need to convert: if display shows 1 CAD = 60 INR,
            // we need 1 INR = 1/60 CAD = 0.0167 CAD
            return 1.0 / displayRate
        }
    }
    
    
    // MARK: - Currency Selection Handler
    private func handleCurrencySelection() {
        guard let givingCurrency = currencyManager.selectedCurrency,
              let receivingCurrency = selectedReceivingCurrency else {
            customExchangeRate = ""
            return
        }
        
        print("🔄 Handling currency selection: \(givingCurrency.name) → \(receivingCurrency.name)")
        
        // Don't auto-populate if user is already typing
        if !customExchangeRate.trimmingCharacters(in: .whitespaces).isEmpty {
            print("⚠️ Rate field not empty, skipping auto-population")
            return
        }
        
        guard let displayCurrencies = getDisplayCurrencies() else {
            print("❌ Could not determine display currencies")
            return
        }
        
        print("📊 Display format: 1 \(displayCurrencies.left.name) = X \(displayCurrencies.right.name)")
        
        // Always try to get rate from DirectExchangeRates collection
        if let directRate = getMarketRateFromDirectRates(from: displayCurrencies.left, to: displayCurrencies.right) {
            customExchangeRate = String(format: "%.4f", directRate)
            print("📱 Auto-populated from DirectExchangeRates: \(customExchangeRate)")
        } else {
            print("❌ No direct rate found in DirectExchangeRates collection")
            // Don't auto-populate, let user enter the rate
            // The direct rate dialog will be shown when they start typing
        }
    }


    // MARK: - Helper function specifically for receiving currency selection
    private func handleReceivingCurrencySelection() {
        print("🎯 Receiving currency selected: \(selectedReceivingCurrency?.name ?? "nil")")
        
        // Add a small delay to ensure UI is updated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.handleCurrencySelection()
        }
    }

    // MARK: - Helper function for giving currency selection
    private func handleGivingCurrencySelection() {
        print("🎯 Giving currency selected: \(currencyManager.selectedCurrency?.name ?? "nil")")
        
        // Clear the receiving currency selection when giving currency changes
        // This forces user to reselect and ensures proper rate calculation
        if selectedReceivingCurrency != nil {
            selectedReceivingCurrency = nil
            customExchangeRate = ""
            print("🔄 Cleared receiving currency due to giving currency change")
        }
    }
    
    private func getMarketRateFromDirectRates(from: Currency, to: Currency) -> Double? {
        // Always try to get direct rate first
        if let directRate = currencyManager.getDirectExchangeRate(from: from.name, to: to.name) {
            return directRate
        }
        
        // If no direct rate found, try reverse direction and invert
        if let reverseRate = currencyManager.getDirectExchangeRate(from: to.name, to: from.name) {
            return 1.0 / reverseRate
        }
        
        // If still no direct rate, return nil to indicate missing rate
        return nil
    }
    
    private func getDisplayMarketRate() -> Double? {
        guard let displayCurrencies = getDisplayCurrencies() else { return nil }
        
        // Simply fetch the rate in the display direction
        return currencyManager.getDirectExchangeRate(
            from: displayCurrencies.left.name,
            to: displayCurrencies.right.name
        )
    }

    private func getMarketRateForDisplay() -> Double? {
        guard let displayCurrencies = getDisplayCurrencies() else { return nil }
        
        let marketRate = getMarketRate2(from: displayCurrencies.left, to: displayCurrencies.right)
        return marketRate
    }
    
    private func getActualTransactionMarketRate(from givingCurrency: Currency, to receivingCurrency: Currency) -> Double? {
        // Always get the rate in the actual transaction direction
        if let directRate = currencyManager.getDirectExchangeRate(from: givingCurrency.name, to: receivingCurrency.name) {
            return directRate
        } else if let reverseRate = currencyManager.getDirectExchangeRate(from: receivingCurrency.name, to: givingCurrency.name) {
            return 1.0 / reverseRate
        } else {
            return nil
        }
    }

    // Replace the exchange profit calculation logic in AddEntryView.swift

    private var exchangeProfitLossDisplay: some View {
        VStack {
            if let givingCurrency = currencyManager.selectedCurrency,
               let receivingCurrency = selectedReceivingCurrency,
               let displayRate = Double(customExchangeRate.trimmingCharacters(in: .whitespaces)),
               let transactionAmount = Double(amount.trimmingCharacters(in: .whitespaces)),
               displayRate > 0 && transactionAmount > 0,
               let displayCurrencies = getDisplayCurrencies() {
                
                // Get display market rate (for showing to user)
                let displayMarketRate = currencyManager.getDirectExchangeRate(
                    from: displayCurrencies.left.name,
                    to: displayCurrencies.right.name
                )
                
                // Get actual transaction market rate (giving -> receiving direction)
                let transactionMarketRate = currencyManager.getDirectExchangeRate(
                    from: givingCurrency.name,
                    to: receivingCurrency.name
                ) ?? {
                    // If direct rate doesn't exist, try reverse and invert
                    if let reverseRate = currencyManager.getDirectExchangeRate(
                        from: receivingCurrency.name,
                        to: givingCurrency.name
                    ) {
                        return 1.0 / reverseRate
                    }
                    return nil
                }()
                
                // Get actual transaction custom rate (what user entered in transaction direction)
                let transactionCustomRate: Double = {
                    // Check if display direction matches transaction direction
                    if displayCurrencies.left.name == givingCurrency.name &&
                       displayCurrencies.right.name == receivingCurrency.name {
                        // Display and transaction are same direction
                        return displayRate
                    } else {
                        // Display is opposite to transaction direction, so invert
                        return 1.0 / displayRate
                    }
                }()
                
                if let actualDisplayMarketRate = displayMarketRate,
                   let actualTransactionMarketRate = transactionMarketRate {
                    
                    // Calculate profit using actual transaction rates
                    let actualProfitRate = transactionCustomRate - actualTransactionMarketRate
                    let totalProfitLoss = actualProfitRate * transactionAmount
                    
                    HStack(spacing: shouldUseVerticalLayout ? 12 : 20) {
                        // Market Rate (shown in display format for UX)
                        VStack(alignment: .leading, spacing: shouldUseVerticalLayout ? 1 : 2) {
                            Text("Market Rate")
                                .font(.system(size: shouldUseVerticalLayout ? 9 : 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text("1 \(displayCurrencies.left.name) = \(actualDisplayMarketRate, specifier: "%.4f") \(displayCurrencies.right.name)")
                                .font(.system(size: shouldUseVerticalLayout ? 10 : 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Profit/Loss (shown in receiving currency of actual transaction)
                        if abs(totalProfitLoss) >= 0.01 {
                            VStack(alignment: .trailing, spacing: shouldUseVerticalLayout ? 1 : 2) {
                                Text(totalProfitLoss > 0 ? "Your Profit" : "Your Loss")
                                    .font(.system(size: shouldUseVerticalLayout ? 9 : 10, weight: .bold))
                                    .foregroundColor(totalProfitLoss > 0 ? .green : .red)
                                Text("\(totalProfitLoss > 0 ? "+" : "")\(totalProfitLoss, specifier: "%.2f") \(receivingCurrency.name)")
                                    .font(.system(size: shouldUseVerticalLayout ? 11 : 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(totalProfitLoss > 0 ? .green : .red)
                            }
                            .padding(.horizontal, shouldUseVerticalLayout ? 8 : 12)
                            .padding(.vertical, shouldUseVerticalLayout ? 4 : 6)
                            .background(
                                RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 5 : 6)
                                    .fill(totalProfitLoss > 0 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            )
                        } else {
                            VStack(alignment: .trailing, spacing: shouldUseVerticalLayout ? 1 : 2) {
                                Text("Break Even")
                                    .font(.system(size: shouldUseVerticalLayout ? 9 : 10, weight: .bold))
                                    .foregroundColor(.gray)
                                Text("No profit/loss")
                                    .font(.system(size: shouldUseVerticalLayout ? 10 : 11, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, shouldUseVerticalLayout ? 8 : 12)
                            .padding(.vertical, shouldUseVerticalLayout ? 4 : 6)
                            .background(
                                RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 5 : 6)
                                    .fill(Color.gray.opacity(0.1))
                            )
                        }
                    }
                    .padding(.horizontal, shouldUseVerticalLayout ? 12 : 16)
                    .padding(.vertical, shouldUseVerticalLayout ? 8 : 12)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(shouldUseVerticalLayout ? 8 : 10)
                    
                    // Debug info (remove in production)
                    VStack(alignment: .leading, spacing: shouldUseVerticalLayout ? 2 : 4) {
                        Text("Debug Info:")
                            .font(.system(size: shouldUseVerticalLayout ? 7 : 8, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Transaction: \(givingCurrency.name) → \(receivingCurrency.name)")
                            .font(.system(size: shouldUseVerticalLayout ? 7 : 8))
                            .foregroundColor(.secondary)
                        Text("Display: \(displayCurrencies.left.name) → \(displayCurrencies.right.name)")
                            .font(.system(size: shouldUseVerticalLayout ? 7 : 8))
                            .foregroundColor(.secondary)
                        Text("User Rate (display): \(displayRate, specifier: "%.4f")")
                            .font(.system(size: shouldUseVerticalLayout ? 7 : 8))
                            .foregroundColor(.secondary)
                        Text("User Rate (transaction): \(transactionCustomRate, specifier: "%.4f")")
                            .font(.system(size: shouldUseVerticalLayout ? 7 : 8))
                            .foregroundColor(.secondary)
                        Text("Market Rate (transaction): \(actualTransactionMarketRate, specifier: "%.4f")")
                            .font(.system(size: shouldUseVerticalLayout ? 7 : 8))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, shouldUseVerticalLayout ? 6 : 8)
                    .padding(.horizontal, shouldUseVerticalLayout ? 12 : 16)
                    
                } else {
                    // No market rate available
                    VStack(spacing: shouldUseVerticalLayout ? 6 : 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: shouldUseVerticalLayout ? 12 : 14))
                                .foregroundColor(.orange)
                            Text("Market Rate Required")
                                .font(.system(size: shouldUseVerticalLayout ? 11 : 12, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        
                        Text("Please provide a direct exchange rate to calculate profit/loss")
                            .font(.system(size: shouldUseVerticalLayout ? 10 : 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, shouldUseVerticalLayout ? 12 : 16)
                    .padding(.vertical, shouldUseVerticalLayout ? 8 : 12)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(shouldUseVerticalLayout ? 8 : 10)
                }
            }
        }
    }
    
    private var rateInfoDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let displayCurrencies = getDisplayCurrencies() {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    
                    Text("Enter rate as: 1 \(displayCurrencies.left.name) = X \(displayCurrencies.right.name)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
                
                // Show market rate availability status
                if let marketRate = getDisplayMarketRate() {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        
                        Text("Market rate available: \(marketRate, specifier: "%.4f")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        
                        Text("No market rate found - profit calculation unavailable")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
    }
    
    private var exchangeRateFieldWithInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            exchangeRateCompactField
            
            if selectedReceivingCurrency != nil {
                rateInfoDisplay
            }
        }
    }

    private func getMarketRate2(from givingCurrency: Currency, to receivingCurrency: Currency) -> Double? {
        // Always use DirectExchangeRates collection only
        return getMarketRateFromDirectRates(from: givingCurrency, to: receivingCurrency)
    }
    
    // Notes Row
    private var notesRow: some View {
        HStack(spacing: shouldUseVerticalLayout ? 8 : 12) { // Much more compact spacing for iPhone
            Image(systemName: "note.text")
                .font(.system(size: shouldUseVerticalLayout ? 12 : 16, weight: .medium)) // Much smaller for iPhone
                .foregroundColor(.blue)
            
            TextField("Add notes (optional)", text: $notes)
                .font(.system(size: shouldUseVerticalLayout ? 12 : 14, weight: .medium)) // Much smaller for iPhone
                .padding(.horizontal, shouldUseVerticalLayout ? 8 : 12) // Much more compact padding for iPhone
                .frame(height: shouldUseVerticalLayout ? 32 : 40) // Much smaller height for iPhone
                .background(Color.gray.opacity(0.05))
                .cornerRadius(shouldUseVerticalLayout ? 5 : 8) // Much smaller corner radius for iPhone
                .overlay(
                    RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 5 : 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .padding(.horizontal, shouldUseVerticalLayout ? 12 : 20) // Much more compact padding for iPhone
    }

    // Replace your shouldShowExchangeDetails computed property:
    private var shouldShowExchangeDetails: Bool {
        guard !customExchangeRate.trimmingCharacters(in: .whitespaces).isEmpty,
              !amount.trimmingCharacters(in: .whitespaces).isEmpty,
              let receivingCurrency = selectedReceivingCurrency,
              let givingCurrency = currencyManager.selectedCurrency else {
            return false
        }
        
        // Always show the exchange details section, but the content inside will handle
        // whether to show profit calculation or "rate required" message
        return true
    }
    
    private var statusIndicators: some View {
        Group {
            if !transactionError.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.body)
                        .foregroundColor(.red)
                    Text(transactionError)
                        .font(.body)
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal, horizontalPadding)
            }
            
            if firebaseManager.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading customers...")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            if !firebaseManager.isConnected {
                HStack {
                    Image(systemName: "wifi.slash")
                        .font(.body)
                        .foregroundColor(.red)
                    Text("No internet connection")
                        .font(.body)
                        .foregroundColor(.red)
                    
                    Button("Retry") {
                        firebaseManager.retryConnection()
                    }
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal, horizontalPadding)
            }
            
            if !firebaseManager.errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.body)
                        .foregroundColor(.orange)
                    Text(firebaseManager.errorMessage)
                        .font(.body)
                        .foregroundColor(.orange)
                    
                    Button("Retry") {
                        firebaseManager.retryConnection()
                    }
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal, horizontalPadding)
            }
            
            HStack {
                Image(systemName: firebaseManager.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.body)
                    .foregroundColor(firebaseManager.isConnected ? .green : .red)
                Text("Found \(firebaseManager.customers.count) customers")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                if firebaseManager.isConnected {
                    Text("• Connected")
                        .font(.body)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }
    
    private func addTransaction() {
        guard let fromCustomer = selectedFromCustomer,
              let toCustomer = selectedToCustomer,
              let currency = currencyManager.selectedCurrency,
              let transactionAmount = Double(amount.trimmingCharacters(in: .whitespaces)) else {
            transactionError = "Please fill in all required fields"
            return
        }
        
        guard transactionAmount > 0 else {
            transactionError = "Amount must be greater than 0"
            return
        }
        
        guard fromCustomer.id != toCustomer.id else {
            transactionError = "Giver and receiver cannot be the same"
            return
        }
        
        // Additional validation for exchange transactions
        if isExchangeOn {
            guard let receivingCurrency = selectedReceivingCurrency,
                  let displayRate = Double(customExchangeRate.trimmingCharacters(in: .whitespaces)) else {
                transactionError = "Please fill in exchange rate and receiving currency"
                return
            }
            
            guard displayRate > 0 else {
                transactionError = "Exchange rate must be greater than 0"
                return
            }
            
            guard receivingCurrency.id != currency.id else {
                transactionError = "Giving and receiving currencies must be different"
                return
            }
            
            // Verify that we have a market rate available in DirectExchangeRates
            guard getMarketRateFromDirectRates(from: currency, to: receivingCurrency) != nil else {
                transactionError = "Market rate not available. Please add direct exchange rate first."
                return
            }
        }
        
        isProcessingTransaction = true
        transactionError = ""
        
        if isExchangeOn {
            // Convert display rate to actual transaction rate
            let displayRate = Double(customExchangeRate.trimmingCharacters(in: .whitespaces))!
            let actualCustomRate = convertRateForCalculation(displayRate: displayRate)
            
            // Handle exchange transaction with converted rate
            transactionManager.addExchangeTransaction(
                amount: transactionAmount,
                givingCurrency: currency,
                receivingCurrency: selectedReceivingCurrency!,
                customExchangeRate: actualCustomRate,
                fromCustomer: fromCustomer,
                toCustomer: toCustomer,
                notes: notes.trimmingCharacters(in: .whitespaces),
                customDate: selectedTransactionDate
            ) { [self] success, error in
                DispatchQueue.main.async {
                    self.isProcessingTransaction = false
                    
                    if success {
                        self.clearForm()
                        print("✅ Exchange transaction completed successfully")
                    } else {
                        self.transactionError = error ?? "Failed to process exchange transaction"
                    }
                }
            }
        } else {
            // Handle regular transaction (unchanged)
            transactionManager.addTransaction(
                amount: transactionAmount,
                currency: currency,
                fromCustomer: fromCustomer,
                toCustomer: toCustomer,
                notes: notes.trimmingCharacters(in: .whitespaces),
                customDate: selectedTransactionDate
            ) { [self] success, error in
                DispatchQueue.main.async {
                    self.isProcessingTransaction = false
                    
                    if success {
                        self.clearForm()
                        print("✅ Transaction completed successfully")
                    } else {
                        self.transactionError = error ?? "Failed to process transaction"
                    }
                }
            }
        }
    }
    
    // Process transaction function (alias for addTransaction)
    private func processTransaction() {
        addTransaction()
    }
    
    // Exchange Rates Display Components
    private var exchangeRatesBarHorizontal: some View {
       Button(action: { showingExchangeRatesDialog = true }) {
           HStack(spacing: 8) {
               Image(systemName: "dollarsign.circle.fill")
                   .font(.body)
                   .foregroundColor(.white)
               
               Text("Rates:")
                   .font(.system(size: 14, weight: .semibold))
                   .foregroundColor(.white.opacity(0.9))
               
               ScrollView(.horizontal, showsIndicators: false) {
                   HStack(spacing: 8) {
                       ForEach(currencyManager.allCurrencies) { currency in
                           if currency.name != "CAD" {
                               let directRate = currencyManager.getDirectExchangeRate(from: "CAD", to: currency.name)
                               let reverseRate = currencyManager.getDirectExchangeRate(from: currency.name, to: "CAD")
                               
                               HStack(spacing: 3) {
                                   Text("1$ =")
                                       .font(.system(size: 11, weight: .medium))
                                       .foregroundColor(.white.opacity(0.8))
                                   
                                   Group {
                                       if let directRate = directRate {
                                           Text("\(directRate, specifier: "%.4f")")
                                               .font(.system(size: 11, weight: .bold, design: .monospaced))
                                               .foregroundColor(.white)
                                               .onAppear {
                                                   print("📊 ExchangeRatesBarH: Using direct rate for CAD to \(currency.name): \(directRate)")
                                               }
                                       } else if let reverseRate = reverseRate {
                                           let calculatedRate = 1.0/reverseRate
                                           Text("\(calculatedRate, specifier: "%.4f")")
                                               .font(.system(size: 11, weight: .bold, design: .monospaced))
                                               .foregroundColor(.white.opacity(0.7))
                                               .onAppear {
                                                   print("📊 ExchangeRatesBarH: Using reverse rate for CAD to \(currency.name): \(currency.name) to CAD = \(reverseRate), calculated CAD to \(currency.name) = \(calculatedRate)")
                                               }
                                       } else {
                                           Text("N/A")
                                               .font(.system(size: 11, weight: .bold, design: .monospaced))
                                               .foregroundColor(.white.opacity(0.5))
                                               .onAppear {
                                                   print("⚠️ ExchangeRatesBarH: No rate found for CAD to \(currency.name) (neither direct nor reverse)")
                                               }
                                       }
                                   }
                                   .onAppear {
                                       print("🔍 ExchangeRatesBarH: Processing currency \(currency.name)")
                                       print("   - Direct rate (CAD to \(currency.name)): \(directRate?.description ?? "nil")")
                                       print("   - Reverse rate (\(currency.name) to CAD): \(reverseRate?.description ?? "nil")")
                                   }
                                   
                                   Text(currency.name)
                                       .font(.system(size: 11, weight: .medium))
                                       .foregroundColor(.white.opacity(0.8))
                               }
                               .padding(.horizontal, 6)
                               .padding(.vertical, 3)
                               .background(Color.white.opacity(0.15))
                               .cornerRadius(4)
                           }
                       }
                       
                       if currencyManager.allCurrencies.filter({ $0.name != "CAD" }).isEmpty {
                           Text("No custom currencies")
                               .font(.system(size: 11, weight: .medium))
                               .foregroundColor(.white.opacity(0.7))
                               .padding(.horizontal, 8)
                               .padding(.vertical, 3)
                               .background(Color.white.opacity(0.1))
                               .cornerRadius(4)
                               .onAppear {
                                   print("⚠️ ExchangeRatesBarH: No non-CAD currencies found")
                               }
                       }
                   }
                   .onAppear {
                       print("📊 ExchangeRatesBarH: Loading horizontal exchange rates display")
                       print("   - Total currencies: \(currencyManager.allCurrencies.count)")
                       print("   - Non-CAD currencies: \(currencyManager.allCurrencies.filter({ $0.name != "CAD" }).count)")
                   }
               }
               .frame(maxWidth: 400)
               
               Image(systemName: "pencil.circle.fill")
                   .font(.callout)
                   .foregroundColor(.white.opacity(0.8))
           }
           .padding(.horizontal, 12)
           .padding(.vertical, 6)
           .background(Color.white.opacity(0.1))
           .cornerRadius(8)
       }
       .buttonStyle(PlainButtonStyle())
    }

    private var exchangeRatesBarVertical: some View {
       Button(action: { showingExchangeRatesDialog = true }) {
           VStack(spacing: 6) {
               HStack(spacing: 6) {
                   Image(systemName: "dollarsign.circle.fill")
                       .font(.callout)
                       .foregroundColor(.white)
                   
                   Text("Exchange Rates")
                       .font(.system(size: 13, weight: .semibold))
                       .foregroundColor(.white.opacity(0.9))
                   
                   Image(systemName: "pencil.circle.fill")
                       .font(.caption)
                       .foregroundColor(.white.opacity(0.8))
               }
               
               ScrollView(.horizontal, showsIndicators: false) {
                   HStack(spacing: 6) {
                       ForEach(currencyManager.allCurrencies) { currency in
                           if currency.name != "CAD" {
                               VStack(spacing: 1) {
                                   Text(currency.symbol)
                                       .font(.system(size: 9, weight: .medium))
                                       .foregroundColor(.white.opacity(0.8))
                                   
                                   let directRate = currencyManager.getDirectExchangeRate(from: currency.name, to: "CAD")
                                   let reverseRate = currencyManager.getDirectExchangeRate(from: "CAD", to: currency.name)
                                   
                                   Group {
                                       if let directRate = directRate {
                                           Text("\(directRate, specifier: "%.4f")")
                                               .font(.system(size: 10, weight: .bold, design: .monospaced))
                                               .foregroundColor(.white)
                                               .onAppear {
                                                   print("📊 ExchangeRatesBar: Using direct rate for \(currency.name) to CAD: \(directRate)")
                                               }
                                       } else if let reverseRate = reverseRate {
                                           let calculatedRate = 1.0/reverseRate
                                           Text("\(calculatedRate, specifier: "%.4f")")
                                               .font(.system(size: 10, weight: .bold, design: .monospaced))
                                               .foregroundColor(.white.opacity(0.7))
                                               .onAppear {
                                                   print("📊 ExchangeRatesBar: Using reverse rate for \(currency.name) to CAD: CAD to \(currency.name) = \(reverseRate), calculated \(currency.name) to CAD = \(calculatedRate)")
                                               }
                                       } else {
                                           Text("No rate")
                                               .font(.system(size: 9, weight: .medium))
                                               .foregroundColor(.white.opacity(0.5))
                                               .onAppear {
                                                   print("⚠️ ExchangeRatesBar: No rate found for \(currency.name) to CAD (neither direct nor reverse)")
                                               }
                                       }
                                   }
                                   .onAppear {
                                       print("🔍 ExchangeRatesBar: Processing currency \(currency.name) (\(currency.symbol))")
                                       print("   - Direct rate (\(currency.name) to CAD): \(directRate?.description ?? "nil")")
                                       print("   - Reverse rate (CAD to \(currency.name)): \(reverseRate?.description ?? "nil")")
                                   }
                               }
                               .padding(.horizontal, 5)
                               .padding(.vertical, 2)
                               .background(Color.white.opacity(0.15))
                               .cornerRadius(3)
                           }
                       }
                       
                       if currencyManager.allCurrencies.filter({ $0.name != "CAD" }).isEmpty {
                           Text("No rates")
                               .font(.system(size: 10, weight: .medium))
                               .foregroundColor(.white.opacity(0.7))
                               .padding(.horizontal, 6)
                               .padding(.vertical, 2)
                               .background(Color.white.opacity(0.1))
                               .cornerRadius(3)
                               .onAppear {
                                   print("⚠️ ExchangeRatesBar: No non-CAD currencies found")
                               }
                       }
                   }
                   .onAppear {
                       print("📊 ExchangeRatesBar: Loading exchange rates display")
                       print("   - Total currencies: \(currencyManager.allCurrencies.count)")
                       print("   - Non-CAD currencies: \(currencyManager.allCurrencies.filter({ $0.name != "CAD" }).count)")
                   }
               }
           }
           .padding(.horizontal, 10)
           .padding(.vertical, 5)
           .background(Color.white.opacity(0.1))
           .cornerRadius(6)
       }
       .buttonStyle(PlainButtonStyle())
    }
    
    private func refreshEntireScreen() {
        currencyManager.fetchCurrencies()
        transactionManager.fetchTransactions()
        firebaseManager.fetchAllCustomers()
        
        // Calculate profit after a small delay to ensure data is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.calculateTotalExchangeProfit()
        }
    }
    
    private var totalExchangeProfitBarHorizontal: some View {
        Button(action: { showingProfitBreakdown.toggle() }) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.body)
                    .foregroundColor(.white)
                
                Text("Profit:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                // Timeframe Filter Button
                Menu {
                    ForEach(ProfitTimeframe.allCases, id: \.self) { timeframe in
                        Button(action: {
                            selectedProfitTimeframe = timeframe
                            calculateTotalExchangeProfit()
                        }) {
                            HStack {
                                Image(systemName: timeframe.icon)
                                Text(timeframe.rawValue)
                                if selectedProfitTimeframe == timeframe {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedProfitTimeframe.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(selectedProfitTimeframe.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(4)
                }
                
                // Single USD converted profit display
                HStack(spacing: 3) {
                    if totalProfitInUSD != 0 {
                        Text(totalProfitInUSD > 0 ? "+" : "")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(totalProfitInUSD > 0 ? .green : .red)
                        Text("$\(abs(totalProfitInUSD), specifier: "%.2f")")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(totalProfitInUSD > 0 ? .green : .red)
                        Text("CAD")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    } else {
                        Text("No profit (\(selectedProfitTimeframe.rawValue.lowercased()))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((totalProfitInUSD > 0 ? Color.green : (totalProfitInUSD < 0 ? Color.red : Color.white)).opacity(0.15))
                .cornerRadius(4)
                
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingProfitBreakdown) {
            ProfitBreakdownDialog(
                totalExchangeProfit: totalExchangeProfit,
                totalProfitInCAD: totalProfitInUSD,
                timeframe: selectedProfitTimeframe,
                currencyManager: currencyManager
            )
        }
    }

    private var totalExchangeProfitBarVertical: some View {
        Button(action: { showingProfitBreakdown.toggle() }) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.callout)
                        .foregroundColor(.white)
                    
                    Text("Profit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    
                    // Compact Timeframe Button
                    Menu {
                        ForEach(ProfitTimeframe.allCases, id: \.self) { timeframe in
                            Button(action: {
                                selectedProfitTimeframe = timeframe
                                calculateTotalExchangeProfit()
                            }) {
                                HStack {
                                    Image(systemName: timeframe.icon)
                                    Text(timeframe.rawValue)
                                    if selectedProfitTimeframe == timeframe {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: selectedProfitTimeframe.icon)
                                .font(.system(size: 8, weight: .medium))
                            Text(selectedProfitTimeframe == .all ? "All" : selectedProfitTimeframe.rawValue.first?.uppercased() ?? "")
                                .font(.system(size: 9, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(3)
                    }
                    
                    Image(systemName: "info.circle")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // Single USD converted profit display
                VStack(spacing: 2) {
                    if totalProfitInUSD != 0 {
                        Text("CAD")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Text("\(totalProfitInUSD > 0 ? "+" : "")\(totalProfitInUSD, specifier: "%.1f")")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(totalProfitInUSD > 0 ? .green : .red)
                    } else {
                        Text("No profit")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background((totalProfitInUSD > 0 ? Color.green : (totalProfitInUSD < 0 ? Color.red : Color.white)).opacity(0.15))
                .cornerRadius(3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingProfitBreakdown) {
            ProfitBreakdownDialog(
                totalExchangeProfit: totalExchangeProfit,
                totalProfitInCAD: totalProfitInUSD,
                timeframe: selectedProfitTimeframe,
                currencyManager: currencyManager
            )
        }
    }
    
    private func getDisplayRateFromDirectRate(directRate: Double, givingCurrency: Currency, receivingCurrency: Currency) -> Double {
        guard let displayCurrencies = getDisplayCurrencies() else { return directRate }
        
        // If display order matches transaction order, use direct rate as is
        if displayCurrencies.left.name == givingCurrency.name {
            return directRate
        } else {
            // Display shows bigger=smaller, but direct rate is smaller=bigger
            return 1.0 / directRate
        }
    }
    
    private func getDisplayRateFromMarketRate(marketRate: Double, givingCurrency: Currency, receivingCurrency: Currency) -> Double {
        guard let displayCurrencies = getDisplayCurrencies() else { return marketRate }
        
        // If display order matches transaction order, use market rate as is
        if displayCurrencies.left.name == givingCurrency.name {
            return marketRate
        } else {
            // Display shows bigger=smaller, but market rate is smaller=bigger
            return 1.0 / marketRate
        }
    }

    // Replace the calculateTotalExchangeProfit function in AddEntryView:
    private func calculateTotalExchangeProfit() {
        var profitByCurrency: [String: Double] = [:]
        var totalCADProfit: Double = 0.0
        
        // Filter transactions by timeframe
        let filteredTransactions = transactionManager.transactions.filter { transaction in
            guard transaction.isExchange else { return false }
            
            let transactionDate = transaction.timestamp.dateValue()
            let now = Date()
            
            switch selectedProfitTimeframe {
            case .thisMonth:
                let calendar = Calendar.current
                let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
                let endOfMonth = calendar.dateInterval(of: .month, for: now)?.end ?? now
                return transactionDate >= startOfMonth && transactionDate < endOfMonth
            case .lastMonth:
                let calendar = Calendar.current
                let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
                let startOfLastMonth = calendar.dateInterval(of: .month, for: lastMonth)?.start ?? lastMonth
                let endOfLastMonth = calendar.dateInterval(of: .month, for: lastMonth)?.end ?? lastMonth
                return transactionDate >= startOfLastMonth && transactionDate < endOfLastMonth
            case .thisYear:
                let calendar = Calendar.current
                let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
                let endOfYear = calendar.dateInterval(of: .year, for: now)?.end ?? now
                return transactionDate >= startOfYear && transactionDate < endOfYear
            case .lastYear:
                let calendar = Calendar.current
                let lastYear = calendar.date(byAdding: .year, value: -1, to: now) ?? now
                let startOfLastYear = calendar.dateInterval(of: .month, for: lastYear)?.start ?? lastYear
                let endOfLastYear = calendar.dateInterval(of: .month, for: lastYear)?.end ?? lastYear
                return transactionDate >= startOfLastYear && transactionDate < endOfLastYear
            case .all:
                return true
            }
        }
        
        print("🔍 Calculating profit for \(selectedProfitTimeframe.rawValue): \(filteredTransactions.count) transactions")
        
        // Go through filtered exchange transactions
        for transaction in filteredTransactions {
            guard let customRate = transaction.customExchangeRate,
                  let receivingCurrencyName = transaction.receivingCurrencyName else {
                continue
            }
            
            let givingCurrencyName = transaction.currencyName
            
            // Always get market rate from DirectExchangeRates collection only
            let currentMarketRate: Double?
            
            if let directRate = currencyManager.getDirectExchangeRate(from: givingCurrencyName, to: receivingCurrencyName) {
                currentMarketRate = directRate
            } else if let reverseRate = currencyManager.getDirectExchangeRate(from: receivingCurrencyName, to: givingCurrencyName) {
                currentMarketRate = 1.0 / reverseRate
            } else {
                print("⚠️ No market rate found in DirectExchangeRates for \(givingCurrencyName) → \(receivingCurrencyName)")
                continue // Skip if no direct rate available
            }
            
            guard let actualMarketRate = currentMarketRate else { continue }
            
            // Calculate current profit for this transaction
            let profitRate = customRate - actualMarketRate
            let transactionProfit = profitRate * transaction.amount
            
            // Add to total for this currency
            profitByCurrency[receivingCurrencyName] = (profitByCurrency[receivingCurrencyName] ?? 0) + transactionProfit
            
            // Convert profit to CAD using DirectExchangeRates only
            if receivingCurrencyName == "CAD" {
                totalCADProfit += transactionProfit
            } else {
                // Try to get CAD conversion from DirectExchangeRates
                if let cadRate = currencyManager.getDirectExchangeRate(from: receivingCurrencyName, to: "CAD") {
                    let profitInCAD = transactionProfit * cadRate
                    totalCADProfit += profitInCAD
                } else if let reverseCadRate = currencyManager.getDirectExchangeRate(from: "CAD", to: receivingCurrencyName) {
                    let profitInCAD = transactionProfit / reverseCadRate
                    totalCADProfit += profitInCAD
                } else {
                    print("⚠️ Could not convert \(receivingCurrencyName) profit to CAD - no direct rate available")
                    // Don't add to total CAD profit if no conversion rate available
                }
            }
        }
        
        totalExchangeProfit = profitByCurrency
        totalProfitInUSD = totalCADProfit // Now this represents CAD profit
        print("💰 Total Exchange Profit (\(selectedProfitTimeframe.rawValue)): \(profitByCurrency)")
        print("💵 Total Profit in CAD: $\(totalCADProfit)")
    }
    private func clearForm() {
        selectedFromCustomer = nil
        selectedToCustomer = nil
        amount = ""
        notes = ""
        transactionError = ""
        selectedReceivingCurrency = nil
        customExchangeRate = ""
        selectedTransactionDate = Date()
    }
}

struct SimpleDropdownButton: View {
    let selectedCustomer: Customer?
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
                    if let selectedCustomer = selectedCustomer {
                        Text(selectedCustomer.displayNameWithTag)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    } else {
                        Text(placeholder)
                            .font(.body)
                            .foregroundColor(.primary.opacity(0.6))
                    }
                }
            }
            Spacer()
            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isOpen ? Color.blue.opacity(0.6) : Color.gray.opacity(0.3), lineWidth: isOpen ? 2 : 1)
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOpen.toggle()
                isFocused = isOpen
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

struct CustomerDropdownButton: View {
    let title: String
    let selectedCustomer: Customer?
    let isOpen: Bool
    let buttonFrame: Binding<CGRect>
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                if let customer = selectedCustomer {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(customer.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text("[\(customer.type.displayName)]")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame.wrappedValue = geometry.frame(in: .global)
                    }
            }
        )
    }
}

struct CustomerDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedCustomer: Customer?
    let customers: [Customer]
    let buttonFrame: CGRect
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @StateObject private var currencyManager = CurrencyManager.shared
    @State private var searchText = ""
    
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
    
    // Filtered customers based on search text
    private var filteredCustomers: [Customer] {
        if searchText.isEmpty {
            return customers
        } else {
            return customers.filter { customer in
                customer.name.localizedCaseInsensitiveContains(searchText) ||
                customer.type.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        #if os(macOS)
        macosOverlay
        #else
        iosDialog
        #endif
    }
    
    // macOS overlay implementation
    private var macosOverlay: some View {
        Color.black.opacity(0.001)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {
                withAnimation {
                    isOpen = false
                }
            }
            .overlay(
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(customers) { customer in
                                customerRow(for: customer)
                                
                                // Add separator after "Myself" option
                                if customer.id == "myself_special_id" && customers.count > 1 {
                                    Divider()
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: min(CGFloat(customers.count) * 80 + (customers.count > 1 ? 10 : 0), 320))
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 6)
                )
                .frame(width: overlayWidth)
                .position(
                    x: buttonFrame.midX,
                    y: buttonFrame.maxY + 15 + (min(CGFloat(customers.count) * 80 + (customers.count > 1 ? 10 : 0), 320) / 2)
                )
            )
    }
    
    // iOS dialog implementation
    private var iosDialog: some View {
        ZStack {
            // Blurred background
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isOpen = false
                    }
                }
                .onAppear {
                    // Clear search text when dialog opens
                    searchText = ""
                }
            
            // Dialog content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Select Customer")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isOpen = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.white)
                
                Divider()
                
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search customers...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.body)
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
                
                // Customer list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredCustomers.isEmpty {
                            // No results message
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                
                                Text("No customers found")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                
                                Text("Try adjusting your search terms")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(filteredCustomers) { customer in
                                customerRow(for: customer)
                                
                                // Add separator after "Myself" option
                                if customer.id == "myself_special_id" && filteredCustomers.count > 1 {
                                    Divider()
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                }
                .background(Color.white)
            }
            .background(Color.white)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 20)
            .padding(.vertical, 40)
        }
        .transition(.opacity.combined(with: .scale))
    }
    
    // Shared customer row implementation
    private func customerRow(for customer: Customer) -> some View {
        Button(action: {
            withAnimation {
                selectedCustomer = customer
                isOpen = false
            }
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    // Customer name with icon
                    HStack(spacing: 6) {
                        if customer.id == "myself_special_id" {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.callout)
                                .foregroundColor(.blue)
                        }
                        Text(customer.name)
                            .font(.body)
                            .fontWeight(customer.id == "myself_special_id" ? .semibold : .medium)
                            .foregroundColor(customer.id == "myself_special_id" ? .blue : .primary)
                    }
                    
                    // Currency balances
                    if customer.id != "myself_special_id" {
                        CustomerBalancesView(customer: customer)
                    } else {
                        // For "Myself", show placeholder balances
                        HStack(spacing: 8) {
                            HStack(spacing: 2) {
                                Text("CAD")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("0.00")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue.opacity(0.1))
                            )
                        }
                    }
                }
                
                Spacer()
                
                // Customer type badge
                if customer.id != "myself_special_id" {
                    Text("[\(customer.type.displayName)]")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(customer.type == .customer ? Color.blue :
                                    customer.type == .middleman ? Color.orange : Color.green)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                selectedCustomer?.id == customer.id ?
                Color.blue.opacity(0.1) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CurrencyDropdownButton: View {
    let selectedCurrency: Currency?
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    
    var body: some View {
        HStack(spacing: 2) {
            // Show currency name with better truncation
            Text(selectedCurrency?.name ?? "CAD")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7) // Allow text to scale down if needed
            
            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 4)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isOpen ? Color.blue.opacity(0.6) : Color.gray.opacity(0.3), lineWidth: isOpen ? 2 : 1)
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOpen.toggle()
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

struct CurrencyDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedCurrency: Currency?
    let currencies: [Currency]
    let buttonFrame: CGRect
    let onAddCurrency: () -> Void
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var searchText = ""
    
    private var overlayWidth: CGFloat {
        #if os(macOS)
        return 180
        #else
        if horizontalSizeClass == .compact {
            return min(200, UIScreen.main.bounds.width - 40)
        } else {
            return 180
        }
        #endif
    }
    
    // Filtered currencies based on search text
    private var filteredCurrencies: [Currency] {
        if searchText.isEmpty {
            return currencies
        } else {
            return currencies.filter { currency in
                currency.name.localizedCaseInsensitiveContains(searchText) ||
                currency.symbol.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        #if os(macOS)
        macosOverlay
        #else
        iosDialog
        #endif
    }
    
    // macOS overlay implementation
    private var macosOverlay: some View {
        Color.black.opacity(0.001)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {
                withAnimation {
                    isOpen = false
                }
            }
            .overlay(
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Currency options (now includes CAD always)
                            ForEach(currencies) { currency in
                                currencyRow(for: currency)
                            }
                            
                            // Add Currency Button
                            Divider()
                                .padding(.horizontal, 16)
                            
                            Button(action: onAddCurrency) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.body)
                                        .foregroundColor(.blue)
                                        .frame(width: 20)
                                    
                                    Text("Add Currency")
                                        .font(.callout)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: min(CGFloat(currencies.count) * 36 + 50, 200))
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 6)
                )
                .frame(width: overlayWidth)
                .position(
                    x: buttonFrame.midX,
                    y: buttonFrame.maxY + 8 + (min(CGFloat(currencies.count) * 36 + 50, 200) / 2)
                )
            )
    }
    
    // iOS dialog implementation
    private var iosDialog: some View {
        ZStack {
            // Blurred background
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isOpen = false
                    }
                }
                .onAppear {
                    // Clear search text when dialog opens
                    searchText = ""
                }
            
            // Dialog content
            VStack(spacing: 0) {
                // Header with improved styling
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        Text("Select Currency")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isOpen = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                            .background(Color.white, in: Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(Color.white)
                
                Divider()
                    .opacity(0.3)
                
                // Enhanced search field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Search currencies...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16, weight: .medium))
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        #endif
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                
                // Currency list with improved spacing
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredCurrencies.isEmpty {
                            // Enhanced no results message
                            VStack(spacing: 16) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                
                                Text("No currencies found")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                Text("Try adjusting your search terms")
                                    .font(.body)
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            .padding(.vertical, 60)
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(filteredCurrencies) { currency in
                                currencyRow(for: currency)
                                
                                if currency.id != filteredCurrencies.last?.id {
                                    Divider()
                                        .padding(.horizontal, 24)
                                        .opacity(0.3)
                                }
                            }
                            
                            // Enhanced Add Currency Button
                            Divider()
                                .padding(.horizontal, 24)
                                .opacity(0.3)
                            
                            Button(action: onAddCurrency) {
                                HStack(spacing: 14) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                    
                                    Text("Add New Currency")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 18)
                                .background(Color.blue.opacity(0.05))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                        }
                    }
                }
                .background(Color.white)
            }
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.15), radius: 25, x: 0, y: 15)
            .padding(.horizontal, 24)
            .padding(.vertical, 60)
        }
        .transition(.opacity.combined(with: .scale))
    }
    
    // Shared currency row implementation
    private func currencyRow(for currency: Currency) -> some View {
        Button(action: {
            withAnimation {
                selectedCurrency = currency
                isOpen = false
            }
        }) {
            HStack(spacing: 12) {
                // Currency symbol with background
                Text(currency.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.blue)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
//                    Text("Exchange Rate: \(String(format: "%.4f", currency.exchangeRate))")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                        .lineLimit(1)
                }
                
                Spacer()
                
                if selectedCurrency?.id == currency.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedCurrency?.id == currency.id ? Color.blue.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedCurrency?.id == currency.id ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TransactionRowView: View {
    let transaction: CurrencyTransaction
    @StateObject private var currencyManager = CurrencyManager.shared
    @EnvironmentObject var firebaseManager: FirebaseManager
    @EnvironmentObject var navigationManager: CustomerNavigationManager
    
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError = ""
    
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
    
    private var giverBalances: [String: Double] {
        if transaction.giver == "myself_special_id" {
            return transaction.balancesAfterTransaction["myself"] as? [String: Double] ?? [:]
        } else {
            return transaction.balancesAfterTransaction[transaction.giver] as? [String: Double] ?? [:]
        }
    }
    
    private var takerBalances: [String: Double] {
        if transaction.taker == "myself_special_id" {
            return transaction.balancesAfterTransaction["myself"] as? [String: Double] ?? [:]
        } else {
            return transaction.balancesAfterTransaction[transaction.taker] as? [String: Double] ?? [:]
        }
    }
    
    private func navigateToCustomer(id: String, name: String) {
        if let customer = firebaseManager.customers.first(where: { $0.id == id }) {
            navigationManager.navigateToCustomer(customer)
        }
    }
    
    private func calculateProfitPercentage(customRate: Double, givingCurrency: String, receivingCurrency: String) -> Double? {
        let marketRate: Double?
        
        if let directRate = currencyManager.getDirectExchangeRate(from: givingCurrency, to: receivingCurrency) {
            marketRate = directRate
        } else if let reverseRate = currencyManager.getDirectExchangeRate(from: receivingCurrency, to: givingCurrency) {
            marketRate = 1.0 / reverseRate
        } else {
            return nil
        }
        
        guard let actualMarketRate = marketRate, actualMarketRate > 0 else {
            return nil
        }
        
        let profitPercentage = ((customRate - actualMarketRate) / actualMarketRate) * 100
        return profitPercentage
    }
    
    private func getCADConversionFromDirectRates(amount: Double, fromCurrency: String) -> Double? {
        if fromCurrency == "CAD" {
            return amount
        }
        
        if let directRate = currencyManager.getDirectExchangeRate(from: fromCurrency, to: "CAD") {
            return amount * directRate
        }
        
        if let reverseRate = currencyManager.getDirectExchangeRate(from: "CAD", to: fromCurrency) {
            return amount / reverseRate
        }
        
        return nil
    }
    
    private var dynamicProfitData: (profit: Double, currency: String)? {
        guard transaction.isExchange,
              let customRate = transaction.customExchangeRate,
              let receivingCurrencyName = transaction.receivingCurrencyName else {
            return nil
        }
        
        let givingCurrencyName = transaction.currencyName
        
        let givingCurrency = currencyManager.allCurrencies.first { $0.name == givingCurrencyName }
        let receivingCurrency = currencyManager.allCurrencies.first { $0.name == receivingCurrencyName }
        
        guard let givingCurr = givingCurrency,
              let receivingCurr = receivingCurrency else {
            return nil
        }
        
        let currentMarketRate: Double?
        
        if let directRate = currencyManager.getDirectExchangeRate(from: givingCurrencyName, to: receivingCurrencyName) {
            currentMarketRate = directRate
        } else if let reverseRate = currencyManager.getDirectExchangeRate(from: receivingCurrencyName, to: givingCurrencyName) {
            currentMarketRate = 1.0 / reverseRate
        } else {
            return nil
        }
        
        guard let actualMarketRate = currentMarketRate else {
            return nil
        }
        
        let profitRate = customRate - actualMarketRate
        let totalProfit = profitRate * transaction.amount
        
        return (profit: totalProfit, currency: receivingCurrencyName)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Check if we should use compact layout (iPhone)
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                // iPhone - Compact layout
                compactTransactionView
            } else {
                // iPad - Full layout
                fullTransactionView
            }
            #else
            // macOS - Full layout
            fullTransactionView
            #endif
        }
    }
    
    // Compact transaction view for iPhone
    private var compactTransactionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date and Time
            HStack {
                Text(dateFormatter.string(from: transaction.timestamp.dateValue()))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(timeFormatter.string(from: transaction.timestamp.dateValue()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Transaction Details
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(transaction.giverName) → \(transaction.takerName)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(transaction.amount, specifier: "%.2f") \(transaction.currencyName)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                // Delete button
                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Exchange info if applicable
            if transaction.isExchange {
                HStack {
                    Text("Rate: \(transaction.customExchangeRate ?? 0, specifier: "%.4f")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let receivingCurrency = transaction.receivingCurrencyName,
                       let receivedAmount = transaction.receivedAmount {
                        Text("→ \(receivedAmount, specifier: "%.2f") \(receivingCurrency)")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(6)
            }
            
            // Notes if any
            if !transaction.notes.isEmpty {
                Text(transaction.notes)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .alert("Delete Transaction", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTransaction()
            }
        } message: {
            Text("Are you sure you want to delete this transaction? This action cannot be undone.")
        }
    }
    
    // Full transaction view for iPad and macOS
    private var fullTransactionView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header Row with Delete Button
            HStack(spacing: 0) {
                Text("Date & Time")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 120, alignment: .leading)
                    .padding(.horizontal, 12)
                
                Divider().frame(height: 20)
                
                Text("Transaction Details")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 240, alignment: .leading)
                    .padding(.horizontal, 12)
                
                Divider().frame(height: 20)
                
                Text("Exchange Info")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 160, alignment: .leading)
                    .padding(.horizontal, 12)
                
                Divider().frame(height: 20)
                
                Text("Giver Balances")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 140, alignment: .leading)
                    .padding(.horizontal, 12)
                
                Divider().frame(height: 20)
                
                Text("Taker Balances")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 140, alignment: .leading)
                    .padding(.horizontal, 12)
                
                Divider().frame(height: 20)
                
                // Delete Button Column Header
                Text("Actions")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .center)
                    .padding(.horizontal, 12)
            }
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)

            // Actual Transaction Row
            HStack(spacing: 0) {
                // COLUMN 1: Date & Time with Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text(dateFormatter.string(from: transaction.timestamp.dateValue()))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(timeFormatter.string(from: transaction.timestamp.dateValue()))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(4)
                    
                    if !transaction.notes.isEmpty {
                        Text(transaction.notes)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.05))
                            .cornerRadius(6)
                            .lineLimit(3)
                    }
                }
                .frame(width: 120, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                
                Divider()
                
                // COLUMN 2: Transaction Details - Reduced width to accommodate delete button
                VStack(alignment: .leading, spacing: 16) {
                    // Amount Section
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Given")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Text("\(transaction.amount, specifier: "%.2f") \(transaction.currencyName)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.red.opacity(0.8))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(4)
                        }
                        
                        if transaction.isExchange {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.blue.opacity(0.7))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("To be received")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Text("\(transaction.receivedAmount ?? 0, specifier: "%.2f") \(transaction.receivingCurrencyName ?? "")")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green.opacity(0.8))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.08))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    
                    // Participants Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transaction Flow")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            // Clickable Giver
                            Button(action: {
                                navigateToCustomer(id: transaction.giver, name: transaction.giverName)
                            }) {
                                HStack(spacing: 4) {
                                    if transaction.giver == "myself_special_id" {
                                        Image(systemName: "person.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.blue)
                                    } else {
                                        Circle()
                                            .fill(Color.orange.opacity(0.7))
                                            .frame(width: 8, height: 8)
                                    }
                                    
                                    Text(transaction.giverName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(transaction.giver == "myself_special_id" ? .blue : .primary)
                                        .underline(transaction.giver != "myself_special_id")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.orange.opacity(0.1), Color.orange.opacity(0.05)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(transaction.giver == "myself_special_id")
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.blue.opacity(0.7))
                            
                            // Clickable Taker
                            Button(action: {
                                navigateToCustomer(id: transaction.taker, name: transaction.takerName)
                            }) {
                                HStack(spacing: 4) {
                                    if transaction.taker == "myself_special_id" {
                                        Image(systemName: "person.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.blue)
                                    } else {
                                        Circle()
                                            .fill(Color.green.opacity(0.7))
                                            .frame(width: 8, height: 8)
                                    }
                                    
                                    Text(transaction.takerName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(transaction.taker == "myself_special_id" ? .blue : .primary)
                                        .underline(transaction.taker != "myself_special_id")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.green.opacity(0.1), Color.green.opacity(0.05)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(transaction.taker == "myself_special_id")
                            
                            Spacer()
                        }
                    }
                }
                .frame(width: 240, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                
                Divider()
                
                // COLUMN 3: Exchange Info
                VStack(alignment: .leading, spacing: 8) {
                    if transaction.isExchange {
                        // Exchange Rate
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Exchange Rate")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            
                            if let customRate = transaction.customExchangeRate {
                                HStack(spacing: 4) {
                                    Text("1 \(transaction.currencyName) = \(customRate, specifier: "%.4f") \(transaction.receivingCurrencyName ?? "")")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.blue.opacity(0.8))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                        
                        // Current Profit Display
                        if let profit = dynamicProfitData?.profit,
                           let profitCurrency = dynamicProfitData?.currency {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(profit > 0 ? "Current Profit:" : (profit < 0 ? "Current Loss:" : "Break Even:"))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(profit > 0 ? .green.opacity(0.8) : (profit < 0 ? .red.opacity(0.8) : .gray))
                                    
                                    Text("\(profit > 0 ? "+" : "")\(profit, specifier: "%.2f") \(profitCurrency)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(profit > 0 ? .green.opacity(0.8) : (profit < 0 ? .red.opacity(0.8) : .gray))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background((profit > 0 ? Color.green : (profit < 0 ? Color.red : Color.gray)).opacity(0.08))
                                .cornerRadius(6)
                                
                                // CAD Conversion
                                if profitCurrency != "CAD" {
                                    let profitInCAD = getCADConversionFromDirectRates(amount: profit, fromCurrency: profitCurrency)
                                    
                                    if let cadAmount = profitInCAD {
                                        HStack(spacing: 4) {
                                            Text("≈")
                                                .font(.system(size: 8, weight: .medium))
                                                .foregroundColor(.secondary)
                                            Text("\(cadAmount > 0 ? "+" : "")$\(abs(cadAmount), specifier: "%.2f")")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .foregroundColor(cadAmount > 0 ? .green.opacity(0.8) : (cadAmount < 0 ? .red.opacity(0.8) : .gray))
                                            Text("CAD")
                                                .font(.system(size: 8, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.gray.opacity(0.05))
                                        .cornerRadius(4)
                                    }
                                }
                                
                                // Profit percentage
                                if let customRate = transaction.customExchangeRate {
                                    let profitPercentage = calculateProfitPercentage(
                                        customRate: customRate,
                                        givingCurrency: transaction.currencyName,
                                        receivingCurrency: transaction.receivingCurrencyName ?? ""
                                    )
                                    
                                    if let percentage = profitPercentage {
                                        HStack(spacing: 4) {
                                            Text("\(percentage > 0 ? "+" : "")\(percentage, specifier: "%.2f")%")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundColor(percentage > 0 ? .green.opacity(0.8) : (percentage < 0 ? .red.opacity(0.8) : .gray))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.gray.opacity(0.05))
                                        .cornerRadius(4)
                                    }
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 16))
                                .foregroundColor(.blue.opacity(0.6))
                            
                            Text("Regular Transfer")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Text("\(transaction.amount, specifier: "%.2f") \(transaction.currencyName)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
                .frame(width: 160, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                
                Divider()
                
                // COLUMN 4: Giver Balances
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 4) {
                        if transaction.giver == "myself_special_id" {
                            Image(systemName: "person.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else {
                            Circle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                        
                        Text(transaction.giverName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(giverBalances.keys.sorted()), id: \.self) { currencyKey in
                            if let balance = giverBalances[currencyKey] {
                                let roundedBalance = round(balance * 100) / 100
                                if abs(roundedBalance) >= 0.01 || currencyKey == "amount" || currencyKey == "CAD" {
                                    HStack(spacing: 4) {
                                        Text(currencyKey == "amount" ? "CAD" : currencyKey)
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(2)
                                        
                                        Text("\(roundedBalance, specifier: "%.2f")")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(abs(roundedBalance) < 0.01 ? .secondary : (roundedBalance > 0 ? Color.green.opacity(0.8) : Color.red.opacity(0.8)))
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: 140, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                
                Divider()
                
                // COLUMN 5: Taker Balances
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 4) {
                        if transaction.taker == "myself_special_id" {
                            Image(systemName: "person.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else {
                            Circle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                        
                        Text(transaction.takerName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(takerBalances.keys.sorted()), id: \.self) { currencyKey in
                            if let balance = takerBalances[currencyKey] {
                                let roundedBalance = round(balance * 100) / 100
                                if abs(roundedBalance) >= 0.01 || currencyKey == "amount" || currencyKey == "CAD" {
                                    HStack(spacing: 4) {
                                        Text(currencyKey == "amount" ? "CAD" : currencyKey)
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(2)
                                        
                                        Text("\(roundedBalance, specifier: "%.2f")")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(abs(roundedBalance) < 0.01 ? .secondary : (roundedBalance > 0 ? Color.green.opacity(0.8) : Color.red.opacity(0.8)))
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: 140, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                
                Divider()
                
                // COLUMN 6: Delete Button
                VStack(alignment: .center, spacing: 8) {
                    if isDeleting {
                        VStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Deleting...")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Text("Delete")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(8)
                            .shadow(color: .red.opacity(0.3), radius: 3, x: 0, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if !deleteError.isEmpty {
                        Text(deleteError)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .frame(width: 80, alignment: .center)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.systemBackground)
                    .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
        }
        .onAppear {
            currencyManager.fetchCurrencies()
        }
        .alert("Delete Transaction", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTransaction()
            }
        } message: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Are you sure you want to delete this transaction?")
                Text("This will:")
                Text("• Delete the transaction record")
                Text("• Reverse all balance changes")
                Text("• Update affected customer balances")
                Text("This action cannot be undone.")
            }
        }
    }
    
    private func deleteTransaction() {
        isDeleting = true
        deleteError = ""
        
        Task {
            do {
                try await reverseTransaction()
                
                DispatchQueue.main.async {
                    self.isDeleting = false
                    // The transaction will automatically disappear from the list
                    // as the TransactionManager's listener will detect the deletion
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDeleting = false
                    self.deleteError = "Failed to delete"
                    print("❌ Delete transaction error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func reverseTransaction() async throws {
        let db = Firestore.firestore()
        let batch = db.batch()
        
        print("🔄 Starting transaction reversal for transaction ID: \(transaction.id ?? "unknown")")
        print("📊 Transaction details: \(transaction.giverName) → \(transaction.takerName)")
        print("💰 Amount: \(transaction.amount) \(transaction.currencyName)")
        print("🔄 Is Exchange: \(transaction.isExchange)")
        
        if transaction.isExchange {
            // Handle exchange transaction reversal
            try await reverseExchangeTransaction(batch: batch)
        } else {
            // Handle regular transaction reversal
            try await reverseRegularTransaction(batch: batch)
        }
        
        // Delete the transaction record
        if let transactionId = transaction.id {
            let transactionRef = db.collection("CurrencyTransactions").document(transactionId)
            batch.deleteDocument(transactionRef)
            print("📝 Marked transaction record for deletion")
        }
        
        // Commit all changes
        try await batch.commit()
        print("✅ Transaction reversal completed successfully")
    }
    
    private func reverseExchangeTransaction(batch: WriteBatch) async throws {
        print("🔄 Processing exchange transaction reversal...")
        
        guard let receivingCurrencyName = transaction.receivingCurrencyName,
              let receivedAmount = transaction.receivedAmount else {
            throw NSError(domain: "TransactionError", code: 400,
                         userInfo: [NSLocalizedDescriptionKey: "Missing exchange transaction data"])
        }
        
        let givingCurrencyName = transaction.currencyName
        let givenAmount = transaction.amount
        
        print("📊 Exchange details:")
        print("   - Giver gave: \(givenAmount) \(givingCurrencyName)")
        print("   - Taker received: \(receivedAmount) \(receivingCurrencyName)")
        
        // Step 1: Reverse giver balance (ADD back the giving currency)
        if transaction.giver == "myself_special_id" {
            try await updateMyCashBalance(
                currency: givingCurrencyName,
                amount: givenAmount, // ADD back what I gave
                batch: batch
            )
            print("✅ Reversed my cash balance: +\(givenAmount) \(givingCurrencyName)")
        } else {
            try await updateCustomerBalance(
                customerId: transaction.giver,
                currency: givingCurrencyName,
                amount: givenAmount, // ADD back what they gave
                batch: batch
            )
            print("✅ Reversed giver balance: +\(givenAmount) \(givingCurrencyName)")
        }
        
        // Step 2: Reverse taker balance (SUBTRACT the receiving currency)
        if transaction.taker == "myself_special_id" {
            try await updateMyCashBalance(
                currency: receivingCurrencyName,
                amount: -receivedAmount, // SUBTRACT what I received
                batch: batch
            )
            print("✅ Reversed my cash balance: -\(receivedAmount) \(receivingCurrencyName)")
        } else {
            try await updateCustomerBalance(
                customerId: transaction.taker,
                currency: receivingCurrencyName,
                amount: -receivedAmount, // SUBTRACT what they received
                batch: batch
            )
            print("✅ Reversed taker balance: -\(receivedAmount) \(receivingCurrencyName)")
        }
    }
    
    private func updateCustomerBalance(customerId: String, currency: String, amount: Double, batch: WriteBatch) async throws {
        let db = Firestore.firestore()
        
        // First, determine which collection this customer belongs to
        let customerType = try await getCustomerType(customerId: customerId)
        let collectionName = "\(customerType.rawValue)s"
        
        if currency == "CAD" {
            // Update CAD balance in the appropriate collection
            let customerRef = db.collection(collectionName).document(customerId)
            
            let customerDoc = try await customerRef.getDocument()
            guard customerDoc.exists else {
                throw NSError(domain: "TransactionError", code: 404,
                             userInfo: [NSLocalizedDescriptionKey: "\(customerType.displayName) not found"])
            }
            
            let currentBalance = customerDoc.data()?["balance"] as? Double ?? 0.0
            let newBalance = currentBalance + amount
            
            print("💰 \(customerType.displayName) CAD balance: \(currentBalance) + \(amount) = \(newBalance)")
            batch.updateData(["balance": newBalance, "updatedAt": Timestamp()], forDocument: customerRef)
        } else {
            // Update non-CAD balance in CurrencyBalances collection
            let currencyBalanceRef = db.collection("CurrencyBalances").document(customerId)
            let currencyDoc = try await currencyBalanceRef.getDocument()
            var currentData = currencyDoc.data() ?? [:]
            
            let currentAmount = currentData[currency] as? Double ?? 0.0
            let newAmount = currentAmount + amount
            
            print("💰 \(customerType.displayName) \(currency) balance: \(currentAmount) + \(amount) = \(newAmount)")
            
            currentData[currency] = newAmount
            currentData["updatedAt"] = Timestamp()
            batch.setData(currentData, forDocument: currencyBalanceRef, merge: true)
        }
    }
    
    private func reverseRegularTransaction(batch: WriteBatch) async throws {
        print("🔄 Processing regular transaction reversal...")
        
        // Step 1: Reverse giver balance (ADD back what they gave)
        if transaction.giver == "myself_special_id" {
            try await updateMyCashBalance(
                currency: transaction.currencyName,
                amount: transaction.amount, // ADD back what I gave
                batch: batch
            )
            print("✅ Reversed my cash balance: +\(transaction.amount) \(transaction.currencyName)")
        } else {
            try await updateCustomerBalance(
                customerId: transaction.giver,
                currency: transaction.currencyName,
                amount: transaction.amount, // ADD back what they gave
                batch: batch
            )
            print("✅ Reversed giver balance: +\(transaction.amount) \(transaction.currencyName)")
        }
        
        // Step 2: Reverse taker balance (SUBTRACT what they received)
        if transaction.taker == "myself_special_id" {
            try await updateMyCashBalance(
                currency: transaction.currencyName,
                amount: -transaction.amount, // SUBTRACT what I received
                batch: batch
            )
            print("✅ Reversed my cash balance: -\(transaction.amount) \(transaction.currencyName)")
        } else {
            try await updateCustomerBalance(
                customerId: transaction.taker,
                currency: transaction.currencyName,
                amount: -transaction.amount, // SUBTRACT what they received
                batch: batch
            )
            print("✅ Reversed taker balance: -\(transaction.amount) \(transaction.currencyName)")
        }
    }
    
    private func updateMyCashBalance(currency: String, amount: Double, batch: WriteBatch) async throws {
        let db = Firestore.firestore()
        let balancesRef = db.collection("Balances").document("Cash")
        
        // Get current balances
        let balancesDoc = try await balancesRef.getDocument()
        var currentData = balancesDoc.data() ?? [:]
        
        if currency == "CAD" {
            // Update CAD amount
            let currentAmount = currentData["amount"] as? Double ?? 0.0
            let newAmount = currentAmount + amount
            currentData["amount"] = newAmount
            print("💰 My CAD balance: \(currentAmount) + \(amount) = \(newAmount)")
        } else {
            // Update specific currency field
            let currentAmount = currentData[currency] as? Double ?? 0.0
            let newAmount = currentAmount + amount
            currentData[currency] = newAmount
            print("💰 My \(currency) balance: \(currentAmount) + \(amount) = \(newAmount)")
        }
        
        // Add timestamp
        currentData["updatedAt"] = Timestamp()
        
        batch.setData(currentData, forDocument: balancesRef, merge: true)
    }
    
    private func reverseMyCashBalance(amount: Double, currency: String, batch: WriteBatch, isAddition: Bool = true) async throws {
        let db = Firestore.firestore()
        let balancesRef = db.collection("Balances").document("Cash")
        
        // Get current balances
        let balancesDoc = try await balancesRef.getDocument()
        var currentData = balancesDoc.data() ?? [:]
        
        if currency == "CAD" {
            // Reverse CAD amount
            let currentAmount = currentData["amount"] as? Double ?? 0.0
            let reverseAmount = isAddition ? amount : -amount
            currentData["amount"] = currentAmount + reverseAmount
            print("🔄 Reversing my cash CAD: \(currentAmount) + \(reverseAmount) = \(currentAmount + reverseAmount)")
        } else {
            // Reverse specific currency field
            let currentAmount = currentData[currency] as? Double ?? 0.0
            let reverseAmount = isAddition ? amount : -amount
            currentData[currency] = currentAmount + reverseAmount
            print("🔄 Reversing my cash \(currency): \(currentAmount) + \(reverseAmount) = \(currentAmount + reverseAmount)")
        }
        
        // Add timestamp
        currentData["updatedAt"] = Timestamp()
        
        batch.setData(currentData, forDocument: balancesRef, merge: true)
    }
    
    private func reverseCustomerBalance(customerId: String, amount: Double, currency: String, batch: WriteBatch, isAddition: Bool = true) async throws {
        let db = Firestore.firestore()
        
        // Determine which collection this customer belongs to
        let customerType = try await getCustomerType(customerId: customerId)
        let collectionName = "\(customerType.rawValue)s"
        
        if currency == "CAD" {
            // Reverse CAD balance in the appropriate collection
            let customerRef = db.collection(collectionName).document(customerId)
            
            let customerDoc = try await customerRef.getDocument()
            guard customerDoc.exists else {
                throw NSError(domain: "TransactionError", code: 404, userInfo: [NSLocalizedDescriptionKey: "\(customerType.displayName) not found"])
            }
            
            let currentBalance = customerDoc.data()?["balance"] as? Double ?? 0.0
            let reverseAmount = isAddition ? amount : -amount
            let newBalance = currentBalance + reverseAmount
            
            print("🔄 Reversing \(customerType.displayName) CAD: \(currentBalance) + \(reverseAmount) = \(newBalance)")
            batch.updateData(["balance": newBalance, "updatedAt": Timestamp()], forDocument: customerRef)
        } else {
            // Reverse non-CAD balance in CurrencyBalances collection
            let currencyBalanceRef = db.collection("CurrencyBalances").document(customerId)
            let currencyDoc = try await currencyBalanceRef.getDocument()
            var currentData = currencyDoc.data() ?? [:]
            
            let currentAmount = currentData[currency] as? Double ?? 0.0
            let reverseAmount = isAddition ? amount : -amount
            let newAmount = currentAmount + reverseAmount
            
            print("🔄 Reversing \(customerType.displayName) \(currency): \(currentAmount) + \(reverseAmount) = \(newAmount)")
            
            currentData[currency] = newAmount
            currentData["updatedAt"] = Timestamp()
            batch.setData(currentData, forDocument: currencyBalanceRef, merge: true)
        }
    }
    
    private func getCustomerType(customerId: String) async throws -> CustomerType {
        let db = Firestore.firestore()
        
        // Check in Customers collection first
        let customersRef = db.collection("Customers").document(customerId)
        let customersDoc = try await customersRef.getDocument()
        if customersDoc.exists {
            return .customer
        }
        
        // Check in Middlemen collection
        let middlemenRef = db.collection("Middlemen").document(customerId)
        let middlemenDoc = try await middlemenRef.getDocument()
        if middlemenDoc.exists {
            return .middleman
        }
        
        // Check in Suppliers collection
        let suppliersRef = db.collection("Suppliers").document(customerId)
        let suppliersDoc = try await suppliersRef.getDocument()
        if suppliersDoc.exists {
            return .supplier
        }
        
        throw NSError(domain: "TransactionError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Customer not found in any collection"])
    }
}
