import Foundation
import FirebaseFirestore

struct CurrencyTransaction: Identifiable {
    var id: String?
    var amount: Double
    var currencyGiven: String // Currency symbol
    var currencyName: String // Currency name
    var giver: String // Customer ID or "myself"
    var giverName: String // Display name
    var taker: String // Customer ID or "myself"
    var takerName: String // Display name
    var notes: String
    var timestamp: Timestamp
    var balancesAfterTransaction: [String: Any] // Store balances after this transaction
    
    // Exchange transaction fields
    var isExchange: Bool = false
    var receivingCurrency: String? // Currency symbol being received
    var receivingCurrencyName: String? // Currency name being received
    var customExchangeRate: Double? // Custom rate (1 given currency = X receiving currency)
    var marketExchangeRate: Double? // Market rate for comparison
    var receivedAmount: Double? // Amount received in the other currency
    var profitAmount: Double? // Profit made due to rate difference
    var profitCurrency: String? // Currency in which profit is calculated
    
    init(amount: Double, currencyGiven: String, currencyName: String, giver: String, giverName: String, taker: String, takerName: String, notes: String = "", balancesAfterTransaction: [String: Any] = [:], isExchange: Bool = false, receivingCurrency: String? = nil, receivingCurrencyName: String? = nil, customExchangeRate: Double? = nil, marketExchangeRate: Double? = nil, receivedAmount: Double? = nil, profitAmount: Double? = nil, profitCurrency: String? = nil, customDate: Date? = nil) {
        self.id = UUID().uuidString
        self.amount = amount
        self.currencyGiven = currencyGiven
        self.currencyName = currencyName
        self.giver = giver
        self.giverName = giverName
        self.taker = taker
        self.takerName = takerName
        self.notes = notes
        self.timestamp = customDate != nil ? Timestamp(date: customDate!) : Timestamp()
        self.balancesAfterTransaction = balancesAfterTransaction
        self.isExchange = isExchange
        self.receivingCurrency = receivingCurrency
        self.receivingCurrencyName = receivingCurrencyName
        self.customExchangeRate = customExchangeRate
        self.marketExchangeRate = marketExchangeRate
        self.receivedAmount = receivedAmount
        self.profitAmount = profitAmount
        self.profitCurrency = profitCurrency
    }
    
    // Convert to dictionary for Firestore
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "amount": amount,
            "currencyGiven": currencyGiven,
            "currencyName": currencyName,
            "giver": giver,
            "giverName": giverName,
            "taker": taker,
            "takerName": takerName,
            "notes": notes,
            "timestamp": timestamp,
            "balancesAfterTransaction": balancesAfterTransaction,
            "isExchange": isExchange
        ]
        
        if isExchange {
            dict["receivingCurrency"] = receivingCurrency
            dict["receivingCurrencyName"] = receivingCurrencyName
            dict["customExchangeRate"] = customExchangeRate
            dict["marketExchangeRate"] = marketExchangeRate
            dict["receivedAmount"] = receivedAmount
            dict["profitAmount"] = profitAmount
            dict["profitCurrency"] = profitCurrency
        }
        
        return dict
    }
}
