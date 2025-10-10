import Foundation
import FirebaseFirestore

struct SalesTransaction: Identifiable {
    var id: String?
    var amount: Double
    var credit: Double
    var customerName: String
    var customerId: String?
    var date: Timestamp
    var gst: Double
    var pst: Double
    var paid: Double
    var paymentSource: String
    var phones: [String]
    var supplierName: String?
    var supplierId: String?
    var orderNumber: String?
    var originalPrice: Double?
    var total: Double
    
    // Middleman-related fields
    var mCredit: Double?
    var mPaid: Double?
    var mTotal: Double?
    var middlemanId: String?
    
    init(id: String, data: [String: Any]) {
        self.id = id
        self.amount = data["amount"] as? Double ?? 0.0
        self.credit = data["credit"] as? Double ?? 0.0
        self.customerName = data["customerName"] as? String ?? ""
        self.customerId = data["customerId"] as? String
        self.date = data["date"] as? Timestamp ?? Timestamp()
        self.gst = data["gst"] as? Double ?? 0.0
        self.pst = data["pst"] as? Double ?? 0.0
        self.paid = data["paid"] as? Double ?? 0.0
        self.paymentSource = data["paymentSource"] as? String ?? ""
        self.phones = data["phones"] as? [String] ?? []
        self.supplierName = data["supplierName"] as? String
        self.supplierId = data["supplierId"] as? String
        self.orderNumber = data["orderNumber"] as? String
        self.originalPrice = data["originalPrice"] as? Double
        self.total = data["total"] as? Double ?? 0.0
        
        // Middleman fields
        self.mCredit = data["mCredit"] as? Double
        self.mPaid = data["mPaid"] as? Double
        self.mTotal = data["mTotal"] as? Double
        self.middlemanId = data["middlemanId"] as? String
    }
}

class SalesTransactionManager: ObservableObject {
    static let shared = SalesTransactionManager()
    
    private let db = Firestore.firestore()
    
    @Published var salesTransactions: [SalesTransaction] = []
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    private var salesListener: ListenerRegistration?
    
    private init() {
        fetchSalesTransactions()
    }
    
    func fetchSalesTransactions() {
        print("🔍 Fetching sales transactions from Firestore...")
        isLoading = true
        errorMessage = ""
        
        salesListener?.remove()
        
        salesListener = db.collection("Sales")
            .order(by: "date", descending: true)
            .addSnapshotListener { [weak self] querySnapshot, error in
                self?.handleSalesUpdate(querySnapshot: querySnapshot, error: error)
            }
    }
    
    private func handleSalesUpdate(querySnapshot: QuerySnapshot?, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("❌ Firestore Error for Sales: \(error.localizedDescription)")
                self.errorMessage = "Failed to load sales transactions: \(error.localizedDescription)"
                self.isLoading = false
                return
            }
            
            guard let querySnapshot = querySnapshot else {
                print("⚠️ QuerySnapshot is nil for Sales")
                self.isLoading = false
                return
            }
            
            let documents = querySnapshot.documents
            print("📄 Found \(documents.count) sales transactions in Firestore")
            
            var fetchedTransactions: [SalesTransaction] = []
            
            for document in documents {
                let documentID = document.documentID
                let data = document.data()
                
                let salesTransaction = SalesTransaction(id: documentID, data: data)
                fetchedTransactions.append(salesTransaction)
            }
            
            self.salesTransactions = fetchedTransactions
            self.isLoading = false
            self.errorMessage = ""
            
            print("✅ Successfully loaded \(fetchedTransactions.count) sales transactions")
        }
    }
    
    deinit {
        salesListener?.remove()
    }
}
