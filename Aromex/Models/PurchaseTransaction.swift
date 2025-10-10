//
//  PurchaseTransaction.swift
//  Aromex_V2
//
//  Created by Ansh Bajaj on 12/07/25.
//


import Foundation
import FirebaseFirestore

struct PurchaseTransaction: Identifiable {
    var id: String?
    var amount: Double
    var credit: Double
    var supplierName: String
    var supplierId: String?
    var date: Timestamp
    var gst: Double
    var pst: Double
    var paid: Double
    var paymentSource: String
    var phones: [String]
    var orderNumber: String?
    var originalPrice: Double?
    var total: Double
    
    init(id: String, data: [String: Any]) {
        self.id = id
        self.amount = data["amount"] as? Double ?? 0.0
        self.credit = data["credit"] as? Double ?? 0.0
        self.supplierName = data["supplierName"] as? String ?? ""
        self.supplierId = data["supplierId"] as? String
        self.date = data["date"] as? Timestamp ?? Timestamp()
        self.gst = data["gst"] as? Double ?? 0.0
        self.pst = data["pst"] as? Double ?? 0.0
        self.paid = data["paid"] as? Double ?? 0.0
        self.paymentSource = data["paymentSource"] as? String ?? ""
        self.phones = data["phones"] as? [String] ?? []
        self.orderNumber = data["orderNumber"] as? String
        self.originalPrice = data["originalPrice"] as? Double
        self.total = data["total"] as? Double ?? 0.0
    }
}

class PurchaseTransactionManager: ObservableObject {
    static let shared = PurchaseTransactionManager()
    
    private let db = Firestore.firestore()
    
    @Published var purchaseTransactions: [PurchaseTransaction] = []
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    private var purchaseListener: ListenerRegistration?
    
    private init() {
        fetchPurchaseTransactions()
    }
    
    func fetchPurchaseTransactions() {
        print("🔍 Fetching purchase transactions from Firestore...")
        isLoading = true
        errorMessage = ""
        
        purchaseListener?.remove()
        
        purchaseListener = db.collection("Purchases")
            .order(by: "date", descending: true)
            .addSnapshotListener { [weak self] querySnapshot, error in
                self?.handlePurchaseUpdate(querySnapshot: querySnapshot, error: error)
            }
    }
    
    private func handlePurchaseUpdate(querySnapshot: QuerySnapshot?, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("❌ Firestore Error for Purchases: \(error.localizedDescription)")
                self.errorMessage = "Failed to load purchase transactions: \(error.localizedDescription)"
                self.isLoading = false
                return
            }
            
            guard let querySnapshot = querySnapshot else {
                print("⚠️ QuerySnapshot is nil for Purchases")
                self.isLoading = false
                return
            }
            
            let documents = querySnapshot.documents
            print("📄 Found \(documents.count) purchase transactions in Firestore")
            
            var fetchedTransactions: [PurchaseTransaction] = []
            
            for document in documents {
                let documentID = document.documentID
                let data = document.data()
                
                let purchaseTransaction = PurchaseTransaction(id: documentID, data: data)
                fetchedTransactions.append(purchaseTransaction)
            }
            
            self.purchaseTransactions = fetchedTransactions
            self.isLoading = false
            self.errorMessage = ""
            
            print("✅ Successfully loaded \(fetchedTransactions.count) purchase transactions")
        }
    }
    
    deinit {
        purchaseListener?.remove()
    }
}