import Foundation
import FirebaseFirestore
import Combine

// Protocol for mixed transaction display
protocol MixedTransaction {
    var id: String? { get }
    var timestamp: Timestamp { get }
    var transactionType: TransactionType { get }
}

enum TransactionType {
    case currency
    case sales
    case purchase
}

// Extensions to make existing types conform to MixedTransaction
extension CurrencyTransaction: MixedTransaction {
    var transactionType: TransactionType { .currency }
}

extension SalesTransaction: MixedTransaction {
    var timestamp: Timestamp { date }
    var transactionType: TransactionType { .sales }
}

extension PurchaseTransaction: MixedTransaction {
    var timestamp: Timestamp { date }
    var transactionType: TransactionType { .purchase }
}

// Wrapper for mixed transactions - now conforms to Equatable
struct AnyMixedTransaction: Identifiable, Equatable {
    let id: String
    let timestamp: Timestamp
    let transactionType: TransactionType
    let transaction: Any
    
    init<T: MixedTransaction>(_ transaction: T) {
        self.id = transaction.id ?? UUID().uuidString
        self.timestamp = transaction.timestamp
        self.transactionType = transaction.transactionType
        self.transaction = transaction
    }
    
    var currencyTransaction: CurrencyTransaction? {
        return transaction as? CurrencyTransaction
    }
    
    var purchaseTransaction: PurchaseTransaction? {
        return transaction as? PurchaseTransaction
    }
    
    // Equatable conformance
    static func == (lhs: AnyMixedTransaction, rhs: AnyMixedTransaction) -> Bool {
        // Compare by id and timestamp as primary identifiers
        return lhs.id == rhs.id &&
               lhs.timestamp.dateValue() == rhs.timestamp.dateValue() &&
               lhs.transactionType == rhs.transactionType
    }
}

class MixedTransactionManager: ObservableObject {
    static let shared = MixedTransactionManager()
    
    @Published var mixedTransactions: [AnyMixedTransaction] = []
    
    private let currencyManager = TransactionManager.shared
    private let salesManager = SalesTransactionManager.shared
    private let purchaseManager = PurchaseTransactionManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Observe changes from all three managers
        currencyManager.$transactions
            .combineLatest(salesManager.$salesTransactions, purchaseManager.$purchaseTransactions)
            .sink { [weak self] currencyTransactions, salesTransactions, purchaseTransactions in
                self?.combinedTransactions(currency: currencyTransactions, sales: salesTransactions, purchase: purchaseTransactions)
            }
            .store(in: &cancellables)
    }
    
    private func combinedTransactions(currency: [CurrencyTransaction], sales: [SalesTransaction], purchase: [PurchaseTransaction]) {
        var combined: [AnyMixedTransaction] = []
        
        // Add currency transactions
        for transaction in currency {
            combined.append(AnyMixedTransaction(transaction))
        }
        
        // Add sales transactions
        for transaction in sales {
            combined.append(AnyMixedTransaction(transaction))
        }
        
        // Add purchase transactions
        for transaction in purchase {
            combined.append(AnyMixedTransaction(transaction))
        }
        
        // Sort by timestamp (newest first)
        combined.sort { $0.timestamp.dateValue() > $1.timestamp.dateValue() }
        
        DispatchQueue.main.async {
            self.mixedTransactions = combined
        }
    }
    
    // Get filtered transactions for specific customer/supplier
    func getCustomerTransactions(customerId: String) -> [AnyMixedTransaction] {
        var filteredTransactions: [AnyMixedTransaction] = []
        
        for mixedTransaction in mixedTransactions {
            switch mixedTransaction.transactionType {
            case .currency:
                if let currencyTx = mixedTransaction.currencyTransaction {
                    if currencyTx.giver == customerId || currencyTx.taker == customerId {
                        filteredTransactions.append(mixedTransaction)
                    }
                }
            case .sales:
                if let salesTx = mixedTransaction.transaction as? SalesTransaction {
                    if salesTx.customerId == customerId || salesTx.middlemanId == customerId {
                        filteredTransactions.append(mixedTransaction)
                    }
                }
            case .purchase:
                if let purchaseTx = mixedTransaction.purchaseTransaction {
                    if purchaseTx.supplierId == customerId {
                        filteredTransactions.append(mixedTransaction)
                    }
                }
            }
        }
        
        return filteredTransactions
    }
}
