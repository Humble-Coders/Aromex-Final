import SwiftUI
import FirebaseFirestore

struct BalanceReportView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @EnvironmentObject var navigationManager: CustomerNavigationManager
    @StateObject private var currencyManager = CurrencyManager.shared
    @StateObject private var balanceViewModel = BalanceViewModel()
    @State private var balanceData: [CustomerBalanceData] = []
    @State private var filteredData: [CustomerBalanceData] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedCurrencyFilter = "All"
    @State private var minAmount = ""
    @State private var maxAmount = ""
    @State private var showingFilters = false
    @State private var sortBy: SortOption = .name
    @State private var sortAscending = true
    @State private var totalOwe: [String: Double] = [:]
    @State private var totalDue: [String: Double] = [:]
    @State private var myCash: [String: Double] = [:]
    @State private var totalInventoryValue: Double = 0.0
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private let db = Firestore.firestore()
    
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case totalBalance = "Total Balance"
        case cadBalance = "CAD Balance"
        case lastUpdated = "Last Updated"
    }
    
    private var shouldUseVerticalLayout: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }
    
    private var currencies: [String] {
        // Always show all available currencies from the currency manager
        let allAvailableCurrencies = currencyManager.allCurrencies.map { $0.name }
        return ["All"] + allAvailableCurrencies.sorted()
    }
    
    private var displayCurrencies: [String] {
        // Currencies to display in the table (excluding "All")
        return currencies.filter { $0 != "All" }
    }
    
    private var totalCashAmount: Double {
        // Use the "amount" key for CAD if it exists, otherwise sum all cash values
        if let cadAmount = myCash["amount"] {
            return cadAmount
        } else {
            return myCash.values.reduce(0, +)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header with search and filters
                    headerSection
                    
                    // Balance table
                    if isLoading {
                        loadingView
                    } else if filteredData.isEmpty {
                        emptyStateView
                    } else {
                        if shouldUseVerticalLayout {
                            mobileListView
                        } else {
                            balanceTableView
                        }
                    }
                    
                    // Add some bottom spacing
                    Spacer(minLength: 20)
                }
            }
            .background(Color.systemGroupedBackground)
            .navigationDestination(isPresented: $navigationManager.shouldShowCustomerDetail) {
                if let selectedCustomer = navigationManager.selectedCustomerForNavigation {
                    let entityProfile = EntityProfile(
                        id: selectedCustomer.id ?? "",
                        name: selectedCustomer.name,
                        phone: selectedCustomer.phone,
                        email: selectedCustomer.email,
                        balance: selectedCustomer.balance,
                        address: selectedCustomer.address,
                        notes: selectedCustomer.notes
                    )
                    
                    let entityType: EntityType = {
                        switch selectedCustomer.type {
                        case .customer: return .customer
                        case .middleman: return .middleman
                        case .supplier: return .supplier
                        }
                    }()
                    
                    EntityDetailView(entity: entityProfile, entityType: entityType)
                }
            }
            .onAppear {
                currencyManager.fetchCurrencies()
                fetchAllBalances()
                fetchTotalOweDue()
                fetchMyCash()
                fetchInventoryValue()
            }
            .onChange(of: searchText) { _ in
                applyFilters()
            }
            .onChange(of: selectedCurrencyFilter) { _ in
                applyFilters()
            }
            .onChange(of: minAmount) { _ in
                applyFilters()
            }
            .onChange(of: maxAmount) { _ in
                applyFilters()
            }
            .onChange(of: sortBy) { _ in
                applySorting()
            }
            .onChange(of: sortAscending) { _ in
                applySorting()
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
    }
    
        private var headerSection: some View {
        VStack(spacing: shouldUseVerticalLayout ? 16 : 20) {
            // Title and refresh
            HStack(alignment: .center) {
                
                Button(action: {
                    fetchAllBalances()
                    fetchTotalOweDue()
                    fetchMyCash()
                    fetchInventoryValue()
                }) {
                    HStack(spacing: shouldUseVerticalLayout ? 6 : 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .medium))
                        if !shouldUseVerticalLayout {
                            Text("Refresh")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, shouldUseVerticalLayout ? 10 : 16)
                    .padding(.vertical, shouldUseVerticalLayout ? 6 : 10)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(shouldUseVerticalLayout ? 6 : 8)
                    .shadow(color: .blue.opacity(0.3), radius: shouldUseVerticalLayout ? 2 : 4, x: 0, y: shouldUseVerticalLayout ? 1 : 2)
                }
                .disabled(isLoading)
                .buttonStyle(PlainButtonStyle())
            }
            
            // Total Owe/Due Summary
            totalOweDueSummary
            
            // Search and Filter Controls
            VStack(spacing: shouldUseVerticalLayout ? 12 : 16) {
                // Search results counter
                if !searchText.isEmpty {
                    HStack {
                        Text("\(filteredData.count) result\(filteredData.count == 1 ? "" : "s") found")
                            .font(.system(size: shouldUseVerticalLayout ? 12 : 14, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Clear Search") {
                            searchText = ""
                            applyFilters()
                        }
                        .font(.system(size: shouldUseVerticalLayout ? 12 : 14, weight: .medium))
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, shouldUseVerticalLayout ? 12 : 16)
                    .padding(.vertical, shouldUseVerticalLayout ? 8 : 10)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(shouldUseVerticalLayout ? 8 : 10)
                }
                
                // Search bar with improved styling
                HStack(spacing: shouldUseVerticalLayout ? 12 : 16) {
                    HStack(spacing: shouldUseVerticalLayout ? 10 : 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        TextField("Search by name or balance...", text: $searchText)
                            .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .medium))
                            .textFieldStyle(PlainTextFieldStyle())
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
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                applyFilters()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: shouldUseVerticalLayout ? 12 : 14))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, shouldUseVerticalLayout ? 12 : 16)
                    .padding(.vertical, shouldUseVerticalLayout ? 10 : 12)
                    .background(
                        RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 10 : 12)
                            .fill(Color.systemGray6)
                            .overlay(
                                RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 10 : 12)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    )
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingFilters.toggle()
                        }
                    }) {
                        HStack(spacing: shouldUseVerticalLayout ? 6 : 8) {
                            Image(systemName: showingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .medium))
                            if !shouldUseVerticalLayout {
                                Text("Filters")
                                .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(showingFilters ? .white : .blue)
                        .padding(.horizontal, shouldUseVerticalLayout ? 10 : 16)
                        .padding(.vertical, shouldUseVerticalLayout ? 10 : 12)
                        .background(
                            RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 10 : 12)
                                .fill(showingFilters ? Color.blue : Color.blue.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 10 : 12)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .shadow(color: showingFilters ? .blue.opacity(0.3) : .clear, radius: shouldUseVerticalLayout ? 2 : 4, x: 0, y: shouldUseVerticalLayout ? 1 : 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Filters (if showing)
                if showingFilters {
                    filtersSection
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                }
            }
        }
        .padding(.horizontal, shouldUseVerticalLayout ? 12 : 24)
        .padding(.vertical, shouldUseVerticalLayout ? 16 : 20)
        .background(
            RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 12 : 16)
                .fill(Color.systemBackgroundColor)
                .shadow(color: .black.opacity(0.08), radius: shouldUseVerticalLayout ? 8 : 12, x: 0, y: shouldUseVerticalLayout ? 2 : 4)
        )
        .padding(.horizontal, shouldUseVerticalLayout ? 12 : 24)
        .padding(.top, shouldUseVerticalLayout ? 12 : 16)
    }
    
    private var totalOweDueSummary: some View {
        VStack(spacing: shouldUseVerticalLayout ? 10 : 12) {
            // Total Owe Section
            VStack(alignment: .leading, spacing: shouldUseVerticalLayout ? 10 : 12) {
                HStack(spacing: shouldUseVerticalLayout ? 6 : 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .medium))
                        .foregroundColor(.red)
                    Text("Total I Owe")
                        .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .bold))
                        .foregroundColor(.red)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: shouldUseVerticalLayout ? 6 : 8) {
                        ForEach(Array(totalOwe.keys.sorted()), id: \.self) { currency in
                            if let amount = totalOwe[currency], abs(amount) >= 0.01 {
                                VStack(spacing: shouldUseVerticalLayout ? 1 : 2) {
                                    Text(currency)
                                        .font(.system(size: shouldUseVerticalLayout ? 9 : 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text("\(abs(amount), specifier: "%.2f")")
                                        .font(.system(size: shouldUseVerticalLayout ? 12 : 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, shouldUseVerticalLayout ? 6 : 8)
                                .padding(.vertical, shouldUseVerticalLayout ? 3 : 4)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(shouldUseVerticalLayout ? 5 : 6)
                            }
                        }
                        
                        if totalOwe.isEmpty || totalOwe.values.allSatisfy({ abs($0) < 0.01 }) {
                            Text("All settled")
                                .font(.system(size: shouldUseVerticalLayout ? 11 : 12, weight: .medium))
                                .foregroundColor(.gray)
                                .padding(.horizontal, shouldUseVerticalLayout ? 6 : 8)
                                .padding(.vertical, shouldUseVerticalLayout ? 3 : 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(shouldUseVerticalLayout ? 5 : 6)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, shouldUseVerticalLayout ? 12 : 16)
            .padding(.vertical, shouldUseVerticalLayout ? 10 : 12)
            .background(
                RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 10 : 12)
                    .fill(Color.red.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 10 : 12)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
            )
            
            // Total Due Section
            VStack(alignment: .leading, spacing: shouldUseVerticalLayout ? 10 : 12) {
                HStack(spacing: shouldUseVerticalLayout ? 6 : 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .medium))
                        .foregroundColor(.green)
                    Text("Total Due to Me")
                        .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .bold))
                        .foregroundColor(.green)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(totalDue.keys.sorted()), id: \.self) { currency in
                            if let amount = totalDue[currency], abs(amount) >= 0.01 {
                                VStack(spacing: 2) {
                                    Text(currency)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text("\(amount, specifier: "%.2f")")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                        
                        if totalDue.isEmpty || totalDue.values.allSatisfy({ abs($0) < 0.01 }) {
                            Text("Nothing due")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                    )
            )
            
            // Account Balances Row (My Cash, Bank Balance, Credit Card)
            if shouldUseVerticalLayout {
                VStack(spacing: 10) {
                    // My Cash
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                            Text("My Cash")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        
                        Text(balanceViewModel.formatAmount(totalCashAmount))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(balanceViewModel.getBalanceColor(totalCashAmount))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                    
                    // Bank Balance
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "building.columns")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.purple)
                            Text("Bank Balance")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.purple)
                        }
                        
                        Text(balanceViewModel.formatAmount(balanceViewModel.bankBalance))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(balanceViewModel.getBalanceColor(balanceViewModel.bankBalance))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                            )
                    )
                    
                    // Credit Card Balance
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.orange)
                            Text("Credit Card")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        
                        Text(balanceViewModel.formatAmount(balanceViewModel.creditCardBalance))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(balanceViewModel.getBalanceColor(balanceViewModel.creditCardBalance))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            } else {
                HStack(spacing: 12) {
                    // My Cash
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.blue)
                            Text("My Cash")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        
                        Text(balanceViewModel.formatAmount(totalCashAmount))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(balanceViewModel.getBalanceColor(totalCashAmount))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                    
                    // Bank Balance
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "building.columns")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.purple)
                            Text("Bank Balance")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.purple)
                        }
                        
                        Text(balanceViewModel.formatAmount(balanceViewModel.bankBalance))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(balanceViewModel.getBalanceColor(balanceViewModel.bankBalance))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                            )
                    )
                    
                    // Credit Card Balance
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.orange)
                            Text("Credit Card")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        
                        Text(balanceViewModel.formatAmount(balanceViewModel.creditCardBalance))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(balanceViewModel.getBalanceColor(balanceViewModel.creditCardBalance))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
            
            // Inventory Value Section
            VStack(alignment: .leading, spacing: shouldUseVerticalLayout ? 10 : 12) {
                HStack(spacing: shouldUseVerticalLayout ? 6 : 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .medium))
                        .foregroundColor(.green)
                    Text("Inventory Value")
                        .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .bold))
                        .foregroundColor(.green)
                }
                
                Text("$\(Int(totalInventoryValue))")
                    .font(.system(size: shouldUseVerticalLayout ? 18 : 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, shouldUseVerticalLayout ? 12 : 16)
            .padding(.vertical, shouldUseVerticalLayout ? 10 : 12)
            .background(
                RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 10 : 12)
                    .fill(Color.green.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 10 : 12)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    private var filtersSection: some View {
        VStack(spacing: 20) {
            // First row: Currency filter and Sort controls
            HStack(spacing: shouldUseVerticalLayout ? 12 : 20) {
                // Currency Filter
                VStack(alignment: .leading, spacing: 8) {
                    Text("Filter by Currency")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Picker("Currency", selection: $selectedCurrencyFilter) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency).tag(currency)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.systemGray6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                
                // Sort By
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sort by")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Picker("Sort", selection: $sortBy) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.systemGray6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                        
                        Button(action: { sortAscending.toggle() }) {
                            Image(systemName: sortAscending ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Second row: Amount range filters
            HStack(spacing: shouldUseVerticalLayout ? 12 : 20) {
                // Min Amount
                VStack(alignment: .leading, spacing: 8) {
                    Text("Minimum Amount")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    TextField("0.00", text: $minAmount)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.systemGray6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                
                // Max Amount
                VStack(alignment: .leading, spacing: 8) {
                    Text("Maximum Amount")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    TextField("999999.99", text: $maxAmount)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.systemGray6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                
                // Clear Filters Button
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Button(action: clearFilters) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Clear All")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(8)
                        .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.systemGray6.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var balanceTableView: some View {
        HStack {
            Spacer(minLength: 0)
            
            VStack(spacing: 0) {
                // Table header
                tableHeaderView
                
                // Table rows
                ForEach(filteredData.indices, id: \.self) { index in
                    let customer = filteredData[index]
                    CustomerBalanceRow(
                        customer: customer,
                        currencies: displayCurrencies,
                        isEven: index % 2 == 0,
                        showGridLines: true
                    )
                }
            }
            .background(Color.systemBackgroundColor)
            .cornerRadius(shouldUseVerticalLayout ? 10 : 12)
            .shadow(color: .black.opacity(0.08), radius: shouldUseVerticalLayout ? 6 : 8, x: 0, y: shouldUseVerticalLayout ? 2 : 4)
            
            Spacer(minLength: 0)
        }
        .padding(.top, shouldUseVerticalLayout ? 16 : 24)
        .padding(.horizontal, shouldUseVerticalLayout ? 12 : 24)
        .padding(.bottom, shouldUseVerticalLayout ? 16 : 20)
    }

    // iPhone-optimized list (compact width)
    private var mobileListView: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredData.indices, id: \.self) { index in
                let customer = filteredData[index]
                Button(action: {
                    // Navigate to detail on tap
                    if let actualCustomer = firebaseManager.customers.first(where: { $0.id == customer.id }) {
                        navigationManager.navigateToCustomer(actualCustomer)
                    }
                }) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(customer.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            // Show primary net (CAD) prominently
                            let cad = round(customer.cadBalance * 100) / 100
                            HStack(spacing: 6) {
                                Text(String(format: "%.2f CAD", abs(cad)))
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                Text(cad >= 0 ? "To Receive" : "To Give")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(cad >= 0 ? .green : .red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((cad >= 0 ? Color.green : Color.red).opacity(0.12))
                            .cornerRadius(6)
                        }
                        
                        HStack(spacing: 8) {
                            // Type chip
                            Text(customer.type.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.12))
                                .cornerRadius(6)
                            
                            if !customer.phone.isEmpty {
                                Text(customer.phone)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.08))
                                    .cornerRadius(6)
                            }
                            Spacer()
                        }
                        
                        // Horizontal chips for non-zero other currencies
                        if !customer.currencyBalances.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(customer.currencyBalances.keys.sorted()), id: \
.self) { currency in
                                        let value = round((customer.currencyBalances[currency] ?? 0) * 100) / 100
                                        if abs(value) >= 0.01 {
                                            HStack(spacing: 6) {
                                                Text("\(currency): \(String(format: "%.2f", abs(value)))")
                                                    .font(.system(size: 11, weight: .semibold))
                                                Text(value >= 0 ? "To Receive" : "To Give")
                                                    .font(.system(size: 10, weight: .semibold))
                                            }
                                            .foregroundColor(value >= 0 ? .green : .red)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background((value >= 0 ? Color.green : Color.red).opacity(0.12))
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.systemBackgroundColor)
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }
    
    private var tableHeaderView: some View {
        HStack(spacing: 0) {
            // Person column
            VStack(spacing: shouldUseVerticalLayout ? 3 : 4) {
                Text("Contact")
                    .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Name & Type")
                    .font(.system(size: shouldUseVerticalLayout ? 11 : 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(width: shouldUseVerticalLayout ? 120 : 200)
            .padding(.horizontal, shouldUseVerticalLayout ? 16 : 20)
            .padding(.vertical, shouldUseVerticalLayout ? 14 : 16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.blue.opacity(0.05)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Rectangle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 1),
                alignment: .trailing
            )
            
            // Phone column
            VStack(spacing: 4) {
                Text("Phone")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Contact Number")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(width: 160)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.08), Color.gray.opacity(0.04)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1),
                alignment: .trailing
            )
            
            // Email column
            VStack(spacing: 4) {
                Text("Email")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Email Address")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(width: 200)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.08), Color.gray.opacity(0.04)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1),
                alignment: .trailing
            )
            
            // Address column (hidden on iPad only)
            #if os(iOS)
            if horizontalSizeClass != .regular {
                VStack(spacing: 4) {
                    Text("Address")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Location")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(width: 220)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.gray.opacity(0.08), Color.gray.opacity(0.04)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1),
                    alignment: .trailing
                )
            }
            #else
            VStack(spacing: 4) {
                Text("Address")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Location")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(width: 220)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.08), Color.gray.opacity(0.04)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1),
                alignment: .trailing
            )
            #endif
            
            // Currency columns
            ForEach(displayCurrencies, id: \.self) { currency in
                VStack(spacing: shouldUseVerticalLayout ? 3 : 4) {
                    Text(currency)
                        .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Balance")
                        .font(.system(size: shouldUseVerticalLayout ? 11 : 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(width: shouldUseVerticalLayout ? 100 : 140)
                .padding(.vertical, shouldUseVerticalLayout ? 14 : 16)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.gray.opacity(0.08), Color.gray.opacity(0.04)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1),
                    alignment: .trailing
                )
            }
        }
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading balance data...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.systemGroupedBackground)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Balance Data")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("No customers have outstanding balances matching your filters")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Clear Filters") {
                clearFilters()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.systemGroupedBackground)
    }
    
    private func fetchAllBalances() {
        isLoading = true
        balanceData.removeAll()
        filteredData.removeAll() // Clear filtered data immediately
        
        let group = DispatchGroup()
        var tempBalanceData: [CustomerBalanceData] = []
        
        // Safety check for empty customers
        guard !firebaseManager.customers.isEmpty else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.applyFilters()
            }
            return
        }
        
        // Fetch all customers
        for customer in firebaseManager.customers {
            group.enter()
            
            var customerBalance = CustomerBalanceData(
                id: customer.id ?? UUID().uuidString,
                name: customer.name,
                type: customer.type,
                phone: customer.phone,
                email: customer.email,
                address: customer.address,
                cadBalance: customer.balance,
                currencyBalances: [:],
                totalBalance: customer.balance,
                lastUpdated: Date()
            )
            
            // Fetch other currency balances from CurrencyBalances collection
            if let customerId = customer.id, !customerId.isEmpty {
                db.collection("CurrencyBalances").document(customerId).getDocument { snapshot, error in
                    defer { group.leave() }
                    
                    if let error = error {
                        print("❌ Error fetching currency balances for \(customer.name): \(error.localizedDescription)")
                        // Still add customer even if currency fetch fails
                        if abs(customerBalance.cadBalance) >= 0.01 {
                            tempBalanceData.append(customerBalance)
                        }
                        return
                    }
                    
                    if let data = snapshot?.data() {
                        var currencyBalances: [String: Double] = [:]
                        var total = customer.balance // Start with CAD balance
                        
                        for (key, value) in data {
                            if key != "updatedAt" && key != "createdAt", let doubleValue = value as? Double {
                                currencyBalances[key] = doubleValue
                                // Add to total (simplified conversion - could use actual exchange rates)
                                total += doubleValue
                            }
                        }
                        
                        customerBalance.currencyBalances = currencyBalances
                        customerBalance.totalBalance = total
                        
                        if let updatedAt = data["updatedAt"] as? Timestamp {
                            customerBalance.lastUpdated = updatedAt.dateValue()
                        }
                        
                        print("💰 Loaded balances for \(customer.name): CAD=\(customer.balance), Others=\(currencyBalances)")
                    }
                    
                    // Add customers with any non-zero balances (CAD or other currencies)
                    if abs(customerBalance.cadBalance) >= 0.01 ||
                       customerBalance.currencyBalances.values.contains(where: { abs($0) >= 0.01 }) {
                        tempBalanceData.append(customerBalance)
                    }
                }
            } else {
                // If no valid customer ID, just check CAD balance
                if abs(customerBalance.cadBalance) >= 0.01 {
                    tempBalanceData.append(customerBalance)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.balanceData = tempBalanceData
            self.applyFilters()
            self.isLoading = false
            print("✅ Balance report loaded with \(tempBalanceData.count) customers")
        }
    }
    
    private func fetchTotalOweDue() {
        let group = DispatchGroup()
        var tempTotalOwe: [String: Double] = [:]
        var tempTotalDue: [String: Double] = [:]
        
        // Fetch CAD balances from all customer types
        for customer in firebaseManager.customers {
            let cadBalance = customer.balance
            
            if cadBalance < 0 {
                // I owe this amount
                tempTotalOwe["CAD"] = (tempTotalOwe["CAD"] ?? 0) + cadBalance
            } else if cadBalance > 0 {
                // This amount is due to me
                tempTotalDue["CAD"] = (tempTotalDue["CAD"] ?? 0) + cadBalance
            }
            
            // Fetch other currency balances
            if let customerId = customer.id, !customerId.isEmpty {
                group.enter()
                db.collection("CurrencyBalances").document(customerId).getDocument { snapshot, error in
                    defer { group.leave() }
                    
                    if let data = snapshot?.data() {
                        for (currency, value) in data {
                            if currency != "updatedAt" && currency != "createdAt",
                               let balance = value as? Double,
                               abs(balance) >= 0.01 {
                                
                                if balance < 0 {
                                    // I owe this amount
                                    tempTotalOwe[currency] = (tempTotalOwe[currency] ?? 0) + balance
                                } else if balance > 0 {
                                    // This amount is due to me
                                    tempTotalDue[currency] = (tempTotalDue[currency] ?? 0) + balance
                                }
                            }
                        }
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            self.totalOwe = tempTotalOwe
            self.totalDue = tempTotalDue
            print("💰 Total Owe: \(tempTotalOwe)")
            print("💰 Total Due: \(tempTotalDue)")
        }
    }
    
    private func fetchMyCash() {
        db.collection("Balances").document("cash").getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error fetching my cash: \(error.localizedDescription)")
                    return
                }
                
                if let data = snapshot?.data() {
                    var cashBalances: [String: Double] = [:]
                    
                    for (key, value) in data {
                        if key != "updatedAt" && key != "createdAt",
                           let balance = value as? Double,
                           abs(balance) >= 0.01 {
                            cashBalances[key] = balance
                        }
                    }
                    
                    self.myCash = cashBalances
                    print("💰 My Cash: \(cashBalances)")
                }
            }
        }
    }
    
    private func fetchInventoryValue() {
        Task {
            var totalValue: Double = 0.0
            var referenceCache: [String: String] = [:]
            
            // First, fetch all reference collections for resolving document references
            async let colorsTask = fetchReferenceCollectionForInventory("Colors")
            async let carriersTask = fetchReferenceCollectionForInventory("Carriers")
            async let locationsTask = fetchReferenceCollectionForInventory("StorageLocations")
            
            let (colors, carriers, locations) = await (colorsTask, carriersTask, locationsTask)
            
            // Merge all reference caches
            referenceCache.merge(colors) { (_, new) in new }
            referenceCache.merge(carriers) { (_, new) in new }
            referenceCache.merge(locations) { (_, new) in new }
            
            do {
                let brandsSnapshot = try await db.collection("PhoneBrands").getDocuments()
                
                await withTaskGroup(of: [Double].self) { group in
                    for brandDoc in brandsSnapshot.documents {
                        group.addTask {
                            await self.fetchBrandInventoryValue(brandDoc: brandDoc, referenceCache: referenceCache)
                        }
                    }
                    
                    for await brandValues in group {
                        for value in brandValues {
                            totalValue += value
                        }
                    }
                }
                
                await MainActor.run {
                    self.totalInventoryValue = totalValue
                    print("📦 Total Inventory Value: $\(Int(totalValue))")
                }
            } catch {
                print("❌ Error fetching inventory value: \(error.localizedDescription)")
            }
        }
    }
    
    private func fetchReferenceCollectionForInventory(_ collection: String) async -> [String: String] {
        var cache: [String: String] = [:]
        do {
            let snapshot = try await db.collection(collection).getDocuments()
            for doc in snapshot.documents {
                let fieldKey = (collection == "StorageLocations") ? "storageLocation" : "name"
                if let name = doc.data()[fieldKey] as? String {
                    cache[doc.documentID] = name
                }
            }
        } catch {
            print("Error fetching \(collection): \(error)")
        }
        return cache
    }
    
    private func fetchBrandInventoryValue(brandDoc: QueryDocumentSnapshot, referenceCache: [String: String]) async -> [Double] {
        var values: [Double] = []
        
        do {
            let modelsSnapshot = try await brandDoc.reference.collection("Models").getDocuments()
            
            await withTaskGroup(of: [Double].self) { group in
                for modelDoc in modelsSnapshot.documents {
                    group.addTask {
                        await self.fetchModelInventoryValue(modelDoc: modelDoc, referenceCache: referenceCache)
                    }
                }
                
                for await modelValues in group {
                    values.append(contentsOf: modelValues)
                }
            }
        } catch {
            print("Error fetching models for brand: \(error)")
        }
        
        return values
    }
    
    private func fetchModelInventoryValue(modelDoc: QueryDocumentSnapshot, referenceCache: [String: String]) async -> [Double] {
        var values: [Double] = []
        
        do {
            let phonesSnapshot = try await modelDoc.reference.collection("Phones").getDocuments()
            
            for phoneDoc in phonesSnapshot.documents {
                let data = phoneDoc.data()
                if let unitCost = data["unitCost"] as? Double {
                    values.append(unitCost)
                }
            }
        } catch {
            print("Error fetching phones for model: \(error)")
        }
        
        return values
    }
    
    private func applyFilters() {
        var filtered = balanceData
        
        // Search filter
        if !searchText.isEmpty {
            print("🔍 Searching for: '\(searchText)' in \(balanceData.count) customers")
            filtered = filtered.filter { customer in
                let nameMatch = customer.name.localizedCaseInsensitiveContains(searchText)
                let balanceMatch = customer.currencyBalances.contains { currency, balance in
                    "\(balance)".contains(searchText)
                }
                let cadBalanceMatch = "\(customer.cadBalance)".contains(searchText)
                
                let isMatch = nameMatch || balanceMatch || cadBalanceMatch
                if isMatch {
                    print("✅ Match found: \(customer.name) - Name: \(nameMatch), Balance: \(balanceMatch), CAD: \(cadBalanceMatch)")
                }
                
                return isMatch
            }
            print("🔍 Search results: \(filtered.count) customers found")
        }
        
        // Currency filter
        if selectedCurrencyFilter != "All" {
            filtered = filtered.filter { customer in
                if selectedCurrencyFilter == "CAD" {
                    return abs(customer.cadBalance) >= 0.01
                } else {
                    return customer.currencyBalances[selectedCurrencyFilter] != nil &&
                           abs(customer.currencyBalances[selectedCurrencyFilter] ?? 0) >= 0.01
                }
            }
        }
        
        // Amount range filter
        if let minVal = Double(minAmount) {
            filtered = filtered.filter { abs($0.totalBalance) >= minVal }
        }
        
        if let maxVal = Double(maxAmount) {
            filtered = filtered.filter { abs($0.totalBalance) <= maxVal }
        }
        
        filteredData = filtered
        applySorting()
    }
    
    private func applySorting() {
        filteredData.sort { first, second in
            let result: Bool
            
            switch sortBy {
            case .name:
                result = first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            case .totalBalance:
                result = abs(first.totalBalance) < abs(second.totalBalance)
            case .cadBalance:
                result = abs(first.cadBalance) < abs(second.cadBalance)
            case .lastUpdated:
                result = first.lastUpdated < second.lastUpdated
            }
            
            return sortAscending ? result : !result
        }
    }
    
    private func clearFilters() {
        searchText = ""
        selectedCurrencyFilter = "All"
        minAmount = ""
        maxAmount = ""
    }
}

struct CustomerBalanceData: Identifiable {
    let id: String
    let name: String
    let type: CustomerType
    let phone: String
    let email: String
    let address: String
    var cadBalance: Double
    var currencyBalances: [String: Double]
    var totalBalance: Double
    var lastUpdated: Date
}

struct CustomerBalanceRow: View {
    let customer: CustomerBalanceData
    let currencies: [String]
    let isEven: Bool
    let showGridLines: Bool
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @EnvironmentObject var firebaseManager: FirebaseManager
    @EnvironmentObject var navigationManager: CustomerNavigationManager
    
    private var shouldUseVerticalLayout: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }
    
    private func navigateToCustomerDetail() {
        // Find the actual customer object from firebaseManager
        if let actualCustomer = firebaseManager.customers.first(where: { $0.id == customer.id }) {
            navigationManager.navigateToCustomer(actualCustomer)
        }
    }
    
    private var customerInfoColumn: some View {
        VStack(alignment: .leading, spacing: shouldUseVerticalLayout ? 6 : 8) {
            HStack(spacing: shouldUseVerticalLayout ? 10 : 12) {
                // Customer type indicator with better styling
                RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 5 : 6)
                    .fill(customer.type == .customer ? Color.blue :
                          customer.type == .middleman ? Color.orange : Color.green)
                    .frame(width: shouldUseVerticalLayout ? 10 : 12, height: shouldUseVerticalLayout ? 10 : 12)
                    .overlay(
                        Text(customer.type.shortTag)
                            .font(.system(size: shouldUseVerticalLayout ? 7 : 8, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: shouldUseVerticalLayout ? 1 : 2) {
                    Text(customer.name)
                        .font(.system(size: shouldUseVerticalLayout ? 13 : 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .underline()
                    
                    Text(customer.type.displayName)
                        .font(.system(size: shouldUseVerticalLayout ? 10 : 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: shouldUseVerticalLayout ? 10 : 12))
                    .foregroundColor(.blue.opacity(0.6))
            }
        }
        .frame(width: shouldUseVerticalLayout ? 120 : 200, alignment: .leading)
        .padding(.horizontal, shouldUseVerticalLayout ? 16 : 20)
        .padding(.vertical, shouldUseVerticalLayout ? 14 : 16)
        .background(isEven ? Color.systemBackgroundColor : Color.gray.opacity(0.02))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1),
            alignment: .trailing
        )
    }
    
    private var phoneColumn: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(customer.phone.isEmpty ? "—" : customer.phone)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(customer.phone.isEmpty ? .secondary : .primary)
                .lineLimit(1)
        }
        .frame(width: 160)
        .padding(.vertical, 16)
        .background(isEven ? Color.systemBackgroundColor : Color.gray.opacity(0.02))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1),
            alignment: .trailing
        )
    }
    
    private var emailColumn: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(customer.email.isEmpty ? "—" : customer.email)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(customer.email.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 200)
        .padding(.vertical, 16)
        .background(isEven ? Color.systemBackgroundColor : Color.gray.opacity(0.02))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1),
            alignment: .trailing
        )
    }
    
    private var addressColumn: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(customer.address.isEmpty ? "—" : customer.address)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(customer.address.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 220)
        .padding(.vertical, 16)
        .background(isEven ? Color.systemBackgroundColor : Color.gray.opacity(0.02))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1),
            alignment: .trailing
        )
    }
    
    private func balanceColumn(for currency: String) -> some View {
        let balance = currency == "CAD" ? customer.cadBalance : (customer.currencyBalances[currency] ?? 0)
        let roundedBalance = round(balance * 100) / 100
        
        return VStack(spacing: shouldUseVerticalLayout ? 4 : 6) {
            if abs(roundedBalance) >= 0.01 {
                Text("\(roundedBalance, specifier: "%.2f")")
                    .font(.system(size: shouldUseVerticalLayout ? 13 : 15, weight: .bold, design: .monospaced))
                    .foregroundColor(roundedBalance > 0 ? .green : .red)
                
                Text(roundedBalance > 0 ? "To Receive" : "To Pay")
                    .font(.system(size: shouldUseVerticalLayout ? 9 : 10, weight: .semibold))
                    .padding(.horizontal, shouldUseVerticalLayout ? 6 : 8)
                    .padding(.vertical, shouldUseVerticalLayout ? 2 : 3)
                    .background(
                        RoundedRectangle(cornerRadius: shouldUseVerticalLayout ? 6 : 8)
                            .fill(roundedBalance > 0 ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                    )
                    .foregroundColor(roundedBalance > 0 ? .green : .red)
            } else {
                Text("0.00")
                    .font(.system(size: shouldUseVerticalLayout ? 13 : 15, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)
                
                Text("Settled")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.12))
                    )
                    .foregroundColor(.gray)
            }
        }
        .frame(width: shouldUseVerticalLayout ? 100 : 140)
        .padding(.vertical, shouldUseVerticalLayout ? 14 : 16)
        .background(isEven ? Color.systemBackgroundColor : Color.gray.opacity(0.02))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1),
            alignment: .trailing
        )
    }
    
    var body: some View {
        Button(action: {
            navigateToCustomerDetail()
        }) {
            HStack(spacing: 0) {
                customerInfoColumn
                
                phoneColumn
                emailColumn
                // Address column hidden on iPad (iOS regular width)
                #if os(iOS)
                if horizontalSizeClass != .regular {
                    addressColumn
                }
                #else
                addressColumn
                #endif
                
                ForEach(currencies, id: \.self) { currency in
                    balanceColumn(for: currency)
                }
            }
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
