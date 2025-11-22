import SwiftUI
import FirebaseFirestore

struct CustomerDetailView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @StateObject private var currencyManager = CurrencyManager.shared
    @StateObject private var transactionManager = TransactionManager.shared
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State private var searchText = ""
    @State private var selectedCustomer: Customer?
    @State private var customerMixedTransactions: [AnyMixedTransaction] = []
    @State private var customerBalances: [String: Double] = [:]
    @State private var isLoadingTransactions = false
    @State private var isLoadingBalances = false
    
    @StateObject private var mixedTransactionManager = MixedTransactionManager.shared
    
    private let db = Firestore.firestore()
    
    // Computed properties for responsive design
    private var shouldUseVerticalLayout: Bool {
#if os(iOS)
        return horizontalSizeClass == .compact
#else
        return false
#endif
    }
    
    private var horizontalPadding: CGFloat {
#if os(macOS)
        return 32
#else
        if horizontalSizeClass == .regular {
            return 24
        } else {
            return 16
        }
#endif
    }
    
    // Get all customers including "Myself"
    private var allCustomers: [Customer] {
        var customers = [myselfCustomer]
        customers.append(contentsOf: firebaseManager.customers)
        return customers
    }
    
    // Filtered customers based on search
    private var filteredCustomers: [Customer] {
        if searchText.isEmpty {
            return allCustomers
        } else {
            return allCustomers.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
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
        VStack(spacing: 0) {
            if selectedCustomer == nil {
                // Customer List View
                customerListView
            } else {
                // Customer Detail View
                customerDetailView
            }
        }
        .background(Color.systemGroupedBackground)
        .onAppear {
            currencyManager.fetchCurrencies()
            transactionManager.fetchTransactions()
            firebaseManager.fetchAllCustomers()
        }
    }
    
    private var customerListView: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Customer List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredCustomers) { customer in
                        CustomerListCard(customer: customer) {
                            selectedCustomer = customer
                            loadCustomerDetails()
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 16)
            }
        }
    }
    
    private var customerDetailView: some View {
        VStack(spacing: 0) {
            // Back Button Header
            detailHeaderView
            
            // Customer Details
            ScrollView {
                VStack(spacing: 24) {
                    // Customer Info Card
                    customerInfoCard
                    
                    // Balances Card
                    balancesCard
                    
                    // Transactions Section
                    transactionsSection
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 16)
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 20) {
            // Title
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Customer Details")
                        .font(.system(size: shouldUseVerticalLayout ? 28 : 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Search and view customer information")
                        .font(.system(size: shouldUseVerticalLayout ? 14 : 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Refresh Button
                Button(action: {
                    firebaseManager.fetchAllCustomers()
                    transactionManager.fetchTransactions()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                        if !shouldUseVerticalLayout {
                            Text("Refresh")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, shouldUseVerticalLayout ? 12 : 16)
                    .padding(.vertical, shouldUseVerticalLayout ? 8 : 10)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Search Bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("Search customers...", text: $searchText)
                    .font(.system(size: 16, weight: .medium))
                    .textFieldStyle(PlainTextFieldStyle())
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
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.systemBackgroundColor)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 16)
    }
    
    private var detailHeaderView: some View {
        HStack {
            Button(action: {
                selectedCustomer = nil
                customerMixedTransactions = []
                customerBalances = [:]
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                    Text("Back")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            Text(selectedCustomer?.name ?? "Customer Details")
                .font(.system(size: shouldUseVerticalLayout ? 20 : 24, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Refresh Button - Updated to refresh both transactions and balances
            Button(action: {
                if let customer = selectedCustomer {
                    loadCustomerBalances(for: customer)
                    loadCustomerTransactions(for: customer)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                    if !shouldUseVerticalLayout {
                        Text("Refresh")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 16)
        .background(Color.systemBackgroundColor)
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private var customerInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Customer Information")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("[\(selectedCustomer?.type.shortTag ?? "")]")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedCustomer?.type == .customer ? Color.blue :
                                    selectedCustomer?.type == .middleman ? Color.orange : Color.green)
                    )
            }
            
            if let customer = selectedCustomer {
                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(label: "Name", value: customer.name)
                    
                    if customer.id != "myself_special_id" {
                        if !customer.phone.isEmpty {
                            DetailRow(label: "Phone", value: customer.phone)
                        }
                        if !customer.email.isEmpty {
                            DetailRow(label: "Email", value: customer.email)
                        }
                        if !customer.address.isEmpty {
                            DetailRow(label: "Address", value: customer.address)
                        }
                        if !customer.notes.isEmpty {
                            DetailRow(label: "Notes", value: customer.notes)
                        }
                    } else {
                        DetailRow(label: "Type", value: "My Account")
                        DetailRow(label: "Description", value: "Your personal cash and currency balances")
                    }
                    
                    DetailRow(label: "Customer Type", value: customer.type.displayName)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.systemBackgroundColor)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
    
    private var balancesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.green)
                
                Text("Balance Overview")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isLoadingBalances {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if customerBalances.isEmpty && !isLoadingBalances {
                VStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                    Text("No balances available")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: shouldUseVerticalLayout ? 120 : 150))
                ], spacing: 12) {
                    ForEach(Array(customerBalances.keys.sorted()), id: \.self) { currency in
                        if let balance = customerBalances[currency] {
                            BalanceCard(
                                currency: currency == "amount" ? "CAD" : currency,
                                balance: balance
                            )
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.systemBackgroundColor)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
    
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.blue)
                
                Text("Transaction History")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isLoadingTransactions {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(customerMixedTransactions.count) transactions")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        
                        if !customerMixedTransactions.isEmpty {
                            HStack(spacing: 8) {
                                let currencyCount = customerMixedTransactions.filter { $0.transactionType == .currency }.count
                                let salesCount = customerMixedTransactions.filter { $0.transactionType == .sales }.count
                                
                                if currencyCount > 0 {
                                    Text("\(currencyCount) currency")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                
                                if currencyCount > 0 && salesCount > 0 {
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if salesCount > 0 {
                                    Text("\(salesCount) sales")
                                        .font(.caption)
                                        .foregroundColor(.purple)
                                }
                            }
                        }
                    }
                }
            }
            
            if customerMixedTransactions.isEmpty && !isLoadingTransactions {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No transactions found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("This customer has no transaction history")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(customerMixedTransactions) { mixedTransaction in
                        // Only show currency transactions
                        if let currencyTx = mixedTransaction.currencyTransaction {
                            TransactionRowView(transaction: currencyTx)
                                .environmentObject(firebaseManager)
                                .environmentObject(CustomerNavigationManager.shared)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.systemBackgroundColor)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
    
    private func loadCustomerDetails() {
        guard let customer = selectedCustomer else { return }
        
        loadCustomerBalances(for: customer)
        loadCustomerTransactions(for: customer)
    }
    
    private func loadCustomerBalances(for customer: Customer) {
        isLoadingBalances = true
        customerBalances = [:]
        
        if customer.id == "myself_special_id" {
            // Load "Myself" balances from Balances/cash
            db.collection("Balances").document("cash").getDocument { snapshot, error in
                DispatchQueue.main.async {
                    self.isLoadingBalances = false
                    
                    if let error = error {
                        print("❌ Error fetching my cash balances: \(error.localizedDescription)")
                        return
                    }
                    
                    if let data = snapshot?.data() {
                        var balances: [String: Double] = [:]
                        for (key, value) in data {
                            if key != "updatedAt", let doubleValue = value as? Double {
                                balances[key] = doubleValue
                            }
                        }
                        self.customerBalances = balances
                    }
                }
            }
        } else {
            // Load customer balances
            var balances: [String: Double] = [:]
            
            // Add CAD balance
            balances["CAD"] = customer.balance
            
            // Load other currency balances
            if let customerId = customer.id {
                db.collection("CurrencyBalances").document(customerId).getDocument { snapshot, error in
                    DispatchQueue.main.async {
                        self.isLoadingBalances = false
                        
                        if let error = error {
                            print("❌ Error fetching currency balances: \(error.localizedDescription)")
                            self.customerBalances = balances // Still show CAD balance
                            return
                        }
                        
                        if let data = snapshot?.data() {
                            for (key, value) in data {
                                if key != "updatedAt", let doubleValue = value as? Double {
                                    balances[key] = doubleValue
                                }
                            }
                        }
                        
                        self.customerBalances = balances
                    }
                }
            } else {
                isLoadingBalances = false
                customerBalances = balances
            }
        }
    }
    
    private func loadCustomerTransactions(for customer: Customer) {
        isLoadingTransactions = true
        
        let customerId = customer.id == "myself_special_id" ? "myself_special_id" : (customer.id ?? "")
        
        // Get mixed transactions for this customer
        let filteredTransactions = mixedTransactionManager.getCustomerTransactions(customerId: customerId)
        
        DispatchQueue.main.async {
            self.customerMixedTransactions = filteredTransactions
            self.isLoadingTransactions = false
        }
    }
}

struct CustomerListCard: View {
    let customer: Customer
    let onTap: () -> Void
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private var shouldUseVerticalLayout: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // Customer Icon
                    if customer.id == "myself_special_id" {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.blue)
                    } else {
                        Circle()
                            .fill(customer.type == .customer ? Color.blue :
                                  customer.type == .middleman ? Color.orange : Color.green)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(customer.type.shortTag)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(customer.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        if customer.id != "myself_special_id" && !customer.phone.isEmpty {
                            Text(customer.phone)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else if customer.id == "myself_special_id" {
                            Text("My Account")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("[\(customer.type.shortTag)]")
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
                        
                        if customer.id != "myself_special_id" {
                            Text("CAD \(customer.balance, specifier: "%.2f")")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(customer.balance >= 0 ? .green : .red)
                        }
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                if customer.id != "myself_special_id" {
                    CustomerBalancesView(customer: customer)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.systemBackgroundColor)
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BalanceCard: View {
    let currency: String
    let balance: Double

    // MARK: - Computed Color Properties

    private var textColor: Color {
        if abs(balance) < 0.01 {
            return .gray
        } else {
            return balance > 0 ? .green : .red
        }
    }

    private var backgroundColor: Color {
        if abs(balance) < 0.01 {
            return Color.gray.opacity(0.1)
        } else {
            return (balance > 0 ? Color.green : Color.red).opacity(0.1)
        }
    }

    private var borderColor: Color {
        if abs(balance) < 0.01 {
            return Color.gray.opacity(0.2)
        } else {
            return (balance > 0 ? Color.green : Color.red).opacity(0.3)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(currency)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text("\(balance, specifier: "%.2f")")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(textColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }
}
