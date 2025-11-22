import Foundation
import FirebaseFirestore

class TransactionManager: ObservableObject {
    static let shared = TransactionManager()
    
    private let db = Firestore.firestore()
    
    @Published var transactions: [CurrencyTransaction] = []
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    private var transactionsListener: ListenerRegistration?
    
    private init() {
        fetchTransactions()
    }
    
    func fetchTransactions() {
        print("🔍 Fetching transactions from Firestore...")
        isLoading = true
        errorMessage = ""
        
        transactionsListener?.remove()
        
        transactionsListener = db.collection("CurrencyTransactions")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] querySnapshot, error in
                self?.handleTransactionsUpdate(querySnapshot: querySnapshot, error: error)
            }
    }
    
    // Add this method to your TransactionManager class

    private func calculateExchangeRate(
        givingCurrency: Currency,
        receivingCurrency: Currency
    ) async -> Double {
        // If either currency is CAD/USD, use existing calculation
        if givingCurrency.name == "CAD" || receivingCurrency.name == "CAD" {
            return (1.0 / givingCurrency.exchangeRate) * receivingCurrency.exchangeRate
        }
        
        // For non-USD pairs, get direct rate
        do {
            if let directRate = try await CurrencyManager.shared.getDirectExchangeRate(
                from: givingCurrency.name,
                to: receivingCurrency.name
            ) {
                return directRate
            }
        } catch {
            print("❌ Error getting direct exchange rate: \(error)")
        }
        
        // Fallback to USD-based calculation if direct rate not available
        return (1.0 / givingCurrency.exchangeRate) * receivingCurrency.exchangeRate
    }

    // Modify your processExchangeTransaction method to use this:
    // Replace the market rate calculation line with:
    // let marketRate = await calculateExchangeRate(givingCurrency: givingCurrency, receivingCurrency: receivingCurrency)
    
    private func handleTransactionsUpdate(querySnapshot: QuerySnapshot?, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("❌ Firestore Error for Transactions: \(error.localizedDescription)")
                self.errorMessage = "Failed to load transactions: \(error.localizedDescription)"
                self.isLoading = false
                return
            }
            
            guard let querySnapshot = querySnapshot else {
                print("⚠️ QuerySnapshot is nil for Transactions")
                self.isLoading = false
                return
            }
            
            let documents = querySnapshot.documents
            print("📄 Found \(documents.count) transactions in Firestore")
            
            var fetchedTransactions: [CurrencyTransaction] = []
            
            for document in documents {
                let documentID = document.documentID
                let data = document.data()
                
                if let amount = data["amount"] as? Double,
                   let currencyGiven = data["currencyGiven"] as? String,
                   let currencyName = data["currencyName"] as? String,
                   let giver = data["giver"] as? String,
                   let giverName = data["giverName"] as? String,
                   let taker = data["taker"] as? String,
                   let takerName = data["takerName"] as? String,
                   let timestamp = data["timestamp"] as? Timestamp {
                    
                    let notes = data["notes"] as? String ?? ""
                    let balancesAfterTransaction = data["balancesAfterTransaction"] as? [String: Any] ?? [:]
                    let isExchange = data["isExchange"] as? Bool ?? false
                    
                    var transaction = CurrencyTransaction(
                        amount: amount,
                        currencyGiven: currencyGiven,
                        currencyName: currencyName,
                        giver: giver,
                        giverName: giverName,
                        taker: taker,
                        takerName: takerName,
                        notes: notes,
                        balancesAfterTransaction: balancesAfterTransaction,
                        isExchange: isExchange
                    )
                    
                    if isExchange {
                        transaction.receivingCurrency = data["receivingCurrency"] as? String
                        transaction.receivingCurrencyName = data["receivingCurrencyName"] as? String
                        transaction.customExchangeRate = data["customExchangeRate"] as? Double
                        transaction.marketExchangeRate = data["marketExchangeRate"] as? Double
                        transaction.receivedAmount = data["receivedAmount"] as? Double
                        transaction.profitAmount = data["profitAmount"] as? Double
                        transaction.profitCurrency = data["profitCurrency"] as? String
                    }
                    
                    transaction.id = documentID
                    transaction.timestamp = timestamp
                    
                    fetchedTransactions.append(transaction)
                }
            }
            
            self.transactions = fetchedTransactions
            self.isLoading = false
            self.errorMessage = ""
            
            print("✅ Successfully loaded \(fetchedTransactions.count) transactions")
        }
    }
    
    func addTransaction(
        amount: Double,
        currency: Currency,
        fromCustomer: Customer?,
        toCustomer: Customer?,
        notes: String,
        customDate: Date? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let fromCustomer = fromCustomer,
              let toCustomer = toCustomer else {
            completion(false, "Please select both giver and receiver")
            return
        }
        
        guard amount > 0 else {
            completion(false, "Amount must be greater than 0")
            return
        }
        
        print("💾 Adding transaction: \(fromCustomer.name) -> \(toCustomer.name), \(amount) \(currency.symbol)")
        
        Task {
            do {
                // Validate customers exist in their respective collections
                if fromCustomer.id != "myself_special_id" && fromCustomer.id != "myself_bank_special_id" {
                    let fromCustomerType = try await getCustomerType(customerId: fromCustomer.id!)
                    print("✅ Found \(fromCustomer.name) in \(fromCustomerType.displayName) collection")
                }
                
                if toCustomer.id != "myself_special_id" && toCustomer.id != "myself_bank_special_id" {
                    let toCustomerType = try await getCustomerType(customerId: toCustomer.id!)
                    print("✅ Found \(toCustomer.name) in \(toCustomerType.displayName) collection")
                }
                
                // Process the transaction
                try await processTransaction(
                    amount: amount,
                    currency: currency,
                    fromCustomer: fromCustomer,
                    toCustomer: toCustomer,
                    notes: notes,
                    customDate: customDate
                )
                
                DispatchQueue.main.async {
                    completion(true, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "Transaction failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func addExchangeTransaction(
        amount: Double,
        givingCurrency: Currency,
        receivingCurrency: Currency,
        customExchangeRate: Double,
        fromCustomer: Customer?,
        toCustomer: Customer?,
        notes: String,
        customDate: Date? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let fromCustomer = fromCustomer,
              let toCustomer = toCustomer else {
            completion(false, "Please select both giver and receiver")
            return
        }
        
        guard amount > 0, customExchangeRate > 0 else {
            completion(false, "Amount and exchange rate must be greater than 0")
            return
        }
        
        print("💰 Adding exchange transaction: \(fromCustomer.name) gives \(amount) \(givingCurrency.symbol) → \(toCustomer.name) receives \(receivingCurrency.symbol) at rate \(customExchangeRate)")
        
        Task {
            do {
                // Validate customers exist in their respective collections
                if fromCustomer.id != "myself_special_id" && fromCustomer.id != "myself_bank_special_id" {
                    let fromCustomerType = try await getCustomerType(customerId: fromCustomer.id!)
                    print("✅ Found \(fromCustomer.name) in \(fromCustomerType.displayName) collection")
                }
                
                if toCustomer.id != "myself_special_id" && toCustomer.id != "myself_bank_special_id" {
                    let toCustomerType = try await getCustomerType(customerId: toCustomer.id!)
                    print("✅ Found \(toCustomer.name) in \(toCustomerType.displayName) collection")
                }
                
                // Process the exchange transaction
                try await processExchangeTransaction(
                    amount: amount,
                    givingCurrency: givingCurrency,
                    receivingCurrency: receivingCurrency,
                    customExchangeRate: customExchangeRate,
                    fromCustomer: fromCustomer,
                    toCustomer: toCustomer,
                    notes: notes,
                    customDate: customDate
                )
                
                DispatchQueue.main.async {
                    completion(true, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "Exchange transaction failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func processTransaction(
        amount: Double,
        currency: Currency,
        fromCustomer: Customer,
        toCustomer: Customer,
        notes: String,
        customDate: Date? = nil
    ) async throws {
        
        let batch = db.batch()
        
        // Handle giver balance update
        if fromCustomer.id == "myself_special_id" {
            // Update my cash balance
            try await updateMyCashBalance(currency: currency, amount: -amount, batch: batch)
        } else if fromCustomer.id == "myself_bank_special_id" {
            // Update my bank balance (only CAD supported)
            try await updateMyBankBalance(amount: -amount, batch: batch)
        } else {
            // Update customer balance
            try await updateCustomerBalance(customerId: fromCustomer.id!, currency: currency, amount: -amount, batch: batch)
        }
        
        // Handle taker balance update
        if toCustomer.id == "myself_special_id" {
            // Update my cash balance
            try await updateMyCashBalance(currency: currency, amount: amount, batch: batch)
        } else if toCustomer.id == "myself_bank_special_id" {
            // Update my bank balance (only CAD supported)
            try await updateMyBankBalance(amount: amount, batch: batch)
        } else {
            // Update customer balance
            try await updateCustomerBalance(customerId: toCustomer.id!, currency: currency, amount: amount, batch: batch)
        }
        
        // NOW get the balances AFTER the transaction updates
        var balancesAfterTransaction: [String: Any] = [:]
        
        // Store giver's balances after transaction
        if fromCustomer.id == "myself_special_id" {
            // For myself, get what the balances will be after this transaction
            let myCurrentBalances = try await getMyCashBalances()
            var myNewBalances = myCurrentBalances
            
            if currency.symbol == "$" {
                let currentAmount = myNewBalances["amount"] ?? 0.0
                myNewBalances["amount"] = currentAmount - amount
            } else {
                let currentAmount = myNewBalances[currency.name] ?? 0.0
                myNewBalances[currency.name] = currentAmount - amount
            }
            balancesAfterTransaction["myself"] = myNewBalances
        } else if fromCustomer.id == "myself_bank_special_id" {
            // For myself bank, get what the balances will be after this transaction
            let myCurrentBalances = try await getMyBankBalances()
            var myNewBalances = myCurrentBalances
            
            // Bank only supports CAD
            let currentAmount = myNewBalances["CAD"] ?? 0.0
            myNewBalances["CAD"] = currentAmount - amount
            balancesAfterTransaction["myself"] = myNewBalances
        } else {
            // For customers, get what the balances will be after this transaction
            let customerCurrentBalances = try await getCustomerBalances(customerId: fromCustomer.id!)
            var customerNewBalances = customerCurrentBalances
            
            if currency.symbol == "$" {
                let currentAmount = customerNewBalances["CAD"] ?? 0.0
                customerNewBalances["CAD"] = currentAmount - amount
            } else {
                let currentAmount = customerNewBalances[currency.name] ?? 0.0
                customerNewBalances[currency.name] = currentAmount - amount
            }
            balancesAfterTransaction[fromCustomer.id!] = customerNewBalances
        }
        
        // Store taker's balances after transaction
        if toCustomer.id == "myself_special_id" {
            // For myself, get what the balances will be after this transaction
            let myCurrentBalances = try await getMyCashBalances()
            var myNewBalances = myCurrentBalances
            
            if currency.symbol == "$" {
                let currentAmount = myNewBalances["amount"] ?? 0.0
                myNewBalances["amount"] = currentAmount + amount
            } else {
                let currentAmount = myNewBalances[currency.name] ?? 0.0
                myNewBalances[currency.name] = currentAmount + amount
            }
            balancesAfterTransaction["myself"] = myNewBalances
        } else if toCustomer.id == "myself_bank_special_id" {
            // For myself bank, get what the balances will be after this transaction
            let myCurrentBalances = try await getMyBankBalances()
            var myNewBalances = myCurrentBalances
            
            // Bank only supports CAD
            let currentAmount = myNewBalances["CAD"] ?? 0.0
            myNewBalances["CAD"] = currentAmount + amount
            balancesAfterTransaction["myself"] = myNewBalances
        } else {
            // For customers, get what the balances will be after this transaction
            let customerCurrentBalances = try await getCustomerBalances(customerId: toCustomer.id!)
            var customerNewBalances = customerCurrentBalances
            
            if currency.symbol == "$" {
                let currentAmount = customerNewBalances["CAD"] ?? 0.0
                customerNewBalances["CAD"] = currentAmount + amount
            } else {
                let currentAmount = customerNewBalances[currency.name] ?? 0.0
                customerNewBalances[currency.name] = currentAmount + amount
            }
            balancesAfterTransaction[toCustomer.id!] = customerNewBalances
        }
        
        // Create transaction record
        let transaction = CurrencyTransaction(
            amount: amount,
            currencyGiven: currency.symbol,
            currencyName: currency.name,
            giver: fromCustomer.id!,
            giverName: fromCustomer.name,
            taker: toCustomer.id!,
            takerName: toCustomer.name,
            notes: notes,
            balancesAfterTransaction: balancesAfterTransaction,
            customDate: customDate
        )
        
        let transactionRef = db.collection("CurrencyTransactions").document()
        batch.setData(transaction.toDictionary(), forDocument: transactionRef)
        
        // Commit all changes
        try await batch.commit()
        print("✅ Transaction completed successfully")
    }
    
    private func processExchangeTransaction(
        amount: Double,
        givingCurrency: Currency,
        receivingCurrency: Currency,
        customExchangeRate: Double,
        fromCustomer: Customer,
        toCustomer: Customer,
        notes: String,
        customDate: Date? = nil
    ) async throws {
        
        let batch = db.batch()
        let receivedAmount = amount * customExchangeRate
        
        // Calculate market rate and profit
        let marketRate = (1.0 / givingCurrency.exchangeRate) * receivingCurrency.exchangeRate
        let profitAmount = (customExchangeRate - marketRate) * amount
        
        // Handle giver balance update (deduct giving currency)
        if fromCustomer.id == "myself_special_id" {
            try await updateMyCashBalance(currency: givingCurrency, amount: -amount, batch: batch)
        } else if fromCustomer.id == "myself_bank_special_id" {
            // Bank only supports CAD, so we only handle if currency is CAD
            if givingCurrency.symbol == "$" {
                try await updateMyBankBalance(amount: -amount, batch: batch)
            }
        } else {
            try await updateCustomerBalance(customerId: fromCustomer.id!, currency: givingCurrency, amount: -amount, batch: batch)
        }
        
        // Handle taker balance update (add receiving currency)
        if toCustomer.id == "myself_special_id" {
            try await updateMyCashBalance(currency: receivingCurrency, amount: receivedAmount, batch: batch)
        } else if toCustomer.id == "myself_bank_special_id" {
            // Bank only supports CAD, so we only handle if currency is CAD
            if receivingCurrency.symbol == "$" {
                try await updateMyBankBalance(amount: receivedAmount, batch: batch)
            }
        } else {
            try await updateCustomerBalance(customerId: toCustomer.id!, currency: receivingCurrency, amount: receivedAmount, batch: batch)
        }
        
        // Calculate balances after transaction
        var balancesAfterTransaction: [String: Any] = [:]
        
        // Store giver's balances after transaction
        if fromCustomer.id == "myself_special_id" {
            let myCurrentBalances = try await getMyCashBalances()
            var myNewBalances = myCurrentBalances
            
            if givingCurrency.symbol == "$" {
                let currentAmount = myNewBalances["amount"] ?? 0.0
                myNewBalances["amount"] = currentAmount - amount
            } else {
                let currentAmount = myNewBalances[givingCurrency.name] ?? 0.0
                myNewBalances[givingCurrency.name] = currentAmount - amount
            }
            balancesAfterTransaction["myself"] = myNewBalances
        } else if fromCustomer.id == "myself_bank_special_id" {
            // Bank only supports CAD
            let myCurrentBalances = try await getMyBankBalances()
            var myNewBalances = myCurrentBalances
            if givingCurrency.symbol == "$" {
                let currentAmount = myNewBalances["CAD"] ?? 0.0
                myNewBalances["CAD"] = currentAmount - amount
            }
            balancesAfterTransaction["myself"] = myNewBalances
        } else {
            let customerCurrentBalances = try await getCustomerBalances(customerId: fromCustomer.id!)
            var customerNewBalances = customerCurrentBalances
            
            if givingCurrency.symbol == "$" {
                let currentAmount = customerNewBalances["CAD"] ?? 0.0
                customerNewBalances["CAD"] = currentAmount - amount
            } else {
                let currentAmount = customerNewBalances[givingCurrency.name] ?? 0.0
                customerNewBalances[givingCurrency.name] = currentAmount - amount
            }
            balancesAfterTransaction[fromCustomer.id!] = customerNewBalances
        }
        
        // Store taker's balances after transaction
        if toCustomer.id == "myself_special_id" {
            let myCurrentBalances = try await getMyCashBalances()
            var myNewBalances = myCurrentBalances
            
            if receivingCurrency.symbol == "$" {
                let currentAmount = myNewBalances["amount"] ?? 0.0
                myNewBalances["amount"] = currentAmount + receivedAmount
            } else {
                let currentAmount = myNewBalances[receivingCurrency.name] ?? 0.0
                myNewBalances[receivingCurrency.name] = currentAmount + receivedAmount
            }
            balancesAfterTransaction["myself"] = myNewBalances
        } else if toCustomer.id == "myself_bank_special_id" {
            // Bank only supports CAD
            let myCurrentBalances = try await getMyBankBalances()
            var myNewBalances = myCurrentBalances
            if receivingCurrency.symbol == "$" {
                let currentAmount = myNewBalances["CAD"] ?? 0.0
                myNewBalances["CAD"] = currentAmount + receivedAmount
            }
            balancesAfterTransaction["myself"] = myNewBalances
        } else {
            let customerCurrentBalances = try await getCustomerBalances(customerId: toCustomer.id!)
            var customerNewBalances = customerCurrentBalances
            
            if receivingCurrency.symbol == "$" {
                let currentAmount = customerNewBalances["CAD"] ?? 0.0
                customerNewBalances["CAD"] = currentAmount + receivedAmount
            } else {
                let currentAmount = customerNewBalances[receivingCurrency.name] ?? 0.0
                customerNewBalances[receivingCurrency.name] = currentAmount + receivedAmount
            }
            balancesAfterTransaction[toCustomer.id!] = customerNewBalances
        }
        
        // Create exchange transaction record
        let transaction = CurrencyTransaction(
            amount: amount,
            currencyGiven: givingCurrency.symbol,
            currencyName: givingCurrency.name,
            giver: fromCustomer.id!,
            giverName: fromCustomer.name,
            taker: toCustomer.id!,
            takerName: toCustomer.name,
            notes: notes,
            balancesAfterTransaction: balancesAfterTransaction,
            isExchange: true,
            receivingCurrency: receivingCurrency.symbol,
            receivingCurrencyName: receivingCurrency.name,
            customExchangeRate: customExchangeRate,
            marketExchangeRate: marketRate,
            receivedAmount: receivedAmount,
            profitAmount: profitAmount,
            profitCurrency: receivingCurrency.symbol,
            customDate: customDate
        )
        
        let transactionRef = db.collection("CurrencyTransactions").document()
        batch.setData(transaction.toDictionary(), forDocument: transactionRef)
        
        // Commit all changes
        try await batch.commit()
        print("✅ Exchange transaction completed successfully")
        print("💰 Profit made: \(profitAmount) \(receivingCurrency.symbol)")
    }
    
    private func updateMyCashBalance(currency: Currency, amount: Double, batch: WriteBatch) async throws {
        let balancesRef = db.collection("Balances").document("cash")
        
        // Get current balances
        let balancesDoc = try await balancesRef.getDocument()
        var currentData = balancesDoc.data() ?? [:]
        
        if currency.symbol == "$" {
            // Update CAD amount
            let currentAmount = currentData["amount"] as? Double ?? 0.0
            currentData["amount"] = currentAmount + amount
        } else {
            // Update specific currency field
            let currentAmount = currentData[currency.name] as? Double ?? 0.0
            currentData[currency.name] = currentAmount + amount
        }
        
        // Add timestamp
        currentData["updatedAt"] = Timestamp()
        
        batch.setData(currentData, forDocument: balancesRef, merge: true)
    }
    
    private func updateMyBankBalance(amount: Double, batch: WriteBatch) async throws {
        let balancesRef = db.collection("Balances").document("bank")
        
        // Get current balance
        let balancesDoc = try await balancesRef.getDocument()
        var currentData = balancesDoc.data() ?? [:]
        
        // Update CAD amount (bank only supports CAD)
        let currentAmount = currentData["amount"] as? Double ?? 0.0
        currentData["amount"] = currentAmount + amount
        print("💰 My BANK balance: \(currentAmount) + \(amount) = \(currentAmount + amount)")
        
        // Add timestamp
        currentData["updatedAt"] = Timestamp()
        
        batch.setData(currentData, forDocument: balancesRef, merge: true)
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
    
    private func updateCustomerBalance(customerId: String, currency: Currency, amount: Double, batch: WriteBatch) async throws {
        // First, determine which collection this customer belongs to
        let customerType = try await getCustomerType(customerId: customerId)
        let collectionName = "\(customerType.rawValue)s" // "Customers", "Middlemen", or "Suppliers"
        
        if currency.symbol == "$" {
            // Update CAD balance in the appropriate collection
            let customerRef = db.collection(collectionName).document(customerId)
            
            // Check if document exists first
            let customerDoc = try await customerRef.getDocument()
            guard customerDoc.exists else {
                throw NSError(domain: "TransactionError", code: 404, userInfo: [NSLocalizedDescriptionKey: "\(customerType.displayName) not found. Please refresh and try again."])
            }
            
            let currentBalance = customerDoc.data()?["balance"] as? Double ?? 0.0
            batch.updateData(["balance": currentBalance + amount, "updatedAt": Timestamp()], forDocument: customerRef)
        } else {
            // Update non-CAD balance in CurrencyBalances collection
            let currencyBalanceRef = db.collection("CurrencyBalances").document(customerId)
            let currencyDoc = try await currencyBalanceRef.getDocument()
            var currentData = currencyDoc.data() ?? [:]
            let currentAmount = currentData[currency.name] as? Double ?? 0.0
            currentData[currency.name] = currentAmount + amount
            currentData["updatedAt"] = Timestamp()
            batch.setData(currentData, forDocument: currencyBalanceRef, merge: true)
        }
    }
    
    private func getCustomerType(customerId: String) async throws -> CustomerType {
        // Handle special customer types
        if customerId == "myself_special_id" || customerId == "myself_bank_special_id" {
            return .customer
        }
        
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
        
        throw NSError(domain: "TransactionError", code: 404,
                     userInfo: [NSLocalizedDescriptionKey: "Customer not found in any collection"])
    }
    
    private func getMyCashBalances() async throws -> [String: Double] {
        let balancesRef = db.collection("Balances").document("cash")
        let balancesDoc = try await balancesRef.getDocument()
        let data = balancesDoc.data() ?? [:]
        
        var balances: [String: Double] = [:]
        for (key, value) in data {
            if key != "updatedAt", let doubleValue = value as? Double {
                balances[key] = doubleValue
            }
        }
        return balances
    }
    
    private func getMyBankBalances() async throws -> [String: Double] {
        let balancesRef = db.collection("Balances").document("bank")
        let balancesDoc = try await balancesRef.getDocument()
        let data = balancesDoc.data() ?? [:]
        
        var balances: [String: Double] = [:]
        if let amount = data["amount"] as? Double {
            balances["CAD"] = amount
        }
        return balances
    }
    
    private func getCustomerBalances(customerId: String) async throws -> [String: Double] {
        var balances: [String: Double] = [:]
        
        // First, determine which collection this customer belongs to
        let customerType = try await getCustomerType(customerId: customerId)
        let collectionName = "\(customerType.rawValue)s" // "Customers", "Middlemen", or "Suppliers"
        
        // Get CAD balance from the appropriate collection
        let customerRef = db.collection(collectionName).document(customerId)
        let customerDoc = try await customerRef.getDocument()
        
        // Only get balance if document exists
        if customerDoc.exists, let cadBalance = customerDoc.data()?["balance"] as? Double {
            balances["CAD"] = cadBalance
        } else {
            print("⚠️ \(customerType.displayName) document not found for ID: \(customerId)")
            balances["CAD"] = 0.0
        }
        
        // Get other currency balances from CurrencyBalances collection
        let currencyBalanceRef = db.collection("CurrencyBalances").document(customerId)
        let currencyDoc = try await currencyBalanceRef.getDocument()
        if let currencyData = currencyDoc.data() {
            for (key, value) in currencyData {
                if key != "updatedAt", let doubleValue = value as? Double {
                    balances[key] = doubleValue
                }
            }
        }
        
        return balances
    }
    
    deinit {
        transactionsListener?.remove()
    }
}
