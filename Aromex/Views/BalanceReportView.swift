import SwiftUI
import FirebaseFirestore

// Color extension for cross-platform compatibility
extension Color {
    
    static var systemGray6Color: Color {
        #if os(macOS)
        return Color(NSColor.controlColor)
        #else
        return Color(.systemGray6)
        #endif
    }
    
    static var systemGray5Color: Color {
        #if os(macOS)
        return Color(NSColor.unemphasizedSelectedContentBackgroundColor)
        #else
        return Color(.systemGray5)
        #endif
    }
}

struct BalanceReportView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @StateObject private var currencyManager = CurrencyManager.shared
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
    
    var body: some View {
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
                    balanceTableView
                }
                
                // Add some bottom spacing
                Spacer(minLength: 20)
            }
        }
        .background(Color.systemGroupedBackground)
        .onAppear {
            currencyManager.fetchCurrencies()
            fetchAllBalances()
            fetchTotalOweDue()
            fetchMyCash()
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
    
        private var headerSection: some View {
        VStack(spacing: shouldUseVerticalLayout ? 16 : 20) {
            // Title and refresh
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: shouldUseVerticalLayout ? 3 : 4) {
                    Text("Balance Report")
                        .font(.system(size: shouldUseVerticalLayout ? 24 : 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Net balance with contacts • Tap to view details")
                        .font(.system(size: shouldUseVerticalLayout ? 13 : 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    fetchAllBalances()
                    fetchTotalOweDue()
                    fetchMyCash()
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
                            .fill(Color.systemGray6Color)
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
            
            // My Cash Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                    Text("My Cash")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.blue)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(myCash.keys.sorted()), id: \.self) { currency in
                            if let amount = myCash[currency], abs(amount) >= 0.01 {
                                VStack(spacing: 2) {
                                    Text(currency == "amount" ? "CAD" : currency)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text("\(amount, specifier: "%.2f")")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                        
                        if myCash.isEmpty || myCash.values.allSatisfy({ abs($0) < 0.01 }) {
                            Text("No cash")
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
                    .fill(Color.blue.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
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
                            .fill(Color.systemGray6Color)
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
                                .fill(Color.systemGray6Color)
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
                                .fill(Color.systemGray6Color)
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
                                .fill(Color.systemGray6Color)
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
                .fill(Color.systemGray6Color.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var balanceTableView: some View {
        HStack {
            if !shouldUseVerticalLayout {
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    if !shouldUseVerticalLayout {
                        Spacer(minLength: 0)
                    }
                    
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
                    
                    if !shouldUseVerticalLayout {
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, shouldUseVerticalLayout ? 12 : 24)
            .padding(.bottom, shouldUseVerticalLayout ? 16 : 20)
            
            if !shouldUseVerticalLayout {
                Spacer()
            }
        }
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
            .frame(minWidth: shouldUseVerticalLayout ? 120 : 200, maxWidth: .infinity, alignment: .center)
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
        db.collection("Balances").document("Cash").getDocument { snapshot, error in
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
        .frame(minWidth: shouldUseVerticalLayout ? 120 : 200, maxWidth: .infinity, alignment: .leading)
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
