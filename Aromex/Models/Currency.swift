import Foundation
import FirebaseFirestore

struct Currency: Identifiable, Codable {
    var id: String?
    var name: String
    var symbol: String
    var exchangeRate: Double // Rate relative to CAD (1 CAD = exchangeRate of this currency)
    var createdAt: Timestamp?
    var updatedAt: Timestamp?
    
    init(name: String, symbol: String, exchangeRate: Double = 1.0) {
        self.id = UUID().uuidString
        self.name = name
        self.symbol = symbol
        self.exchangeRate = exchangeRate
        self.createdAt = Timestamp()
        self.updatedAt = Timestamp()
    }
    
    // Custom init for existing Firestore data
    init(id: String, name: String, symbol: String, exchangeRate: Double, createdAt: Timestamp? = nil, updatedAt: Timestamp? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.exchangeRate = exchangeRate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Convert to dictionary for Firestore
    func toDictionary() -> [String: Any] {
        return [
            "name": name,
            "symbol": symbol,
            "exchangeRate": exchangeRate,
            "createdAt": createdAt ?? Timestamp(),
            "updatedAt": Timestamp()
        ]
    }
}

class CurrencyManager: ObservableObject {
    static let shared = CurrencyManager()
    
    private let db = Firestore.firestore()
    
    @Published var currencies: [Currency] = []
    @Published var selectedCurrency: Currency?
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var directExchangeRates: [String: DirectExchangeRate] = [:]
    private var directRatesListener: ListenerRegistration?
    
    private var currenciesListener: ListenerRegistration?
    
    // Default CAD currency that's always available
    private let defaultCAD = Currency(id: "default_cad_id", name: "CAD", symbol: "$", exchangeRate: 1.0)
    
    private init() {
        // Start with default CAD currency
        self.selectedCurrency = defaultCAD
        fetchCurrencies()
        fetchDirectExchangeRates() // Add this line
    }
    
    // Computed property to get all currencies including CAD
    var allCurrencies: [Currency] {
        var allCurrencies = [defaultCAD] // Always include CAD first
        
        // Add other currencies from Firestore, but exclude any CAD duplicates
        let otherCurrencies = currencies.filter { $0.name.uppercased() != "CAD" }
        allCurrencies.append(contentsOf: otherCurrencies)
        
        return allCurrencies
    }
    
    func fetchCurrencies() {
        print("🔍 Fetching currencies from Firestore...")
        isLoading = true
        errorMessage = ""
        
        // Remove existing listener
        currenciesListener?.remove()
        
        // Fetch from Currencies collection
        currenciesListener = db.collection("Currencies")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] querySnapshot, error in
                self?.handleCurrenciesUpdate(querySnapshot: querySnapshot, error: error)
            }
    }
    
    private func handleCurrenciesUpdate(querySnapshot: QuerySnapshot?, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("❌ Firestore Error for Currencies: \(error.localizedDescription)")
                self.errorMessage = "Failed to load currencies: \(error.localizedDescription)"
                self.isLoading = false
                return
            }
            
            guard let querySnapshot = querySnapshot else {
                print("⚠️ QuerySnapshot is nil for Currencies")
                self.isLoading = false
                return
            }
            
            let documents = querySnapshot.documents
            print("📄 Found \(documents.count) currencies in Firestore")
            
            var fetchedCurrencies: [Currency] = []
            
            for document in documents {
                let documentID = document.documentID
                let data = document.data()
                
                print("📋 Currency Document ID: \(documentID)")
                
                if let name = data["name"] as? String,
                   let symbol = data["symbol"] as? String,
                   !name.isEmpty, !symbol.isEmpty {
                    
                    // Handle exchange rate
                    var exchangeRate: Double = 1.0
                    if let rateDouble = data["exchangeRate"] as? Double {
                        exchangeRate = rateDouble
                    } else if let rateInt = data["exchangeRate"] as? Int {
                        exchangeRate = Double(rateInt)
                    } else if let rateString = data["exchangeRate"] as? String,
                             let rateParsed = Double(rateString) {
                        exchangeRate = rateParsed
                    }
                    
                    let currency = Currency(
                        id: documentID,
                        name: name,
                        symbol: symbol,
                        exchangeRate: exchangeRate,
                        createdAt: data["createdAt"] as? Timestamp,
                        updatedAt: data["updatedAt"] as? Timestamp
                    )
                    
                    fetchedCurrencies.append(currency)
                    print("💱 Found currency: '\(name)' (\(symbol)) - Rate: \(exchangeRate)")
                } else {
                    print("⚠️ Currency Document \(documentID) missing required fields")
                }
            }
            
            // Sort by creation date
            fetchedCurrencies.sort {
                guard let date1 = $0.createdAt, let date2 = $1.createdAt else { return false }
                return date1.dateValue() < date2.dateValue()
            }
            
            self.currencies = fetchedCurrencies
            
            // Set default selected currency to CAD if not already set
            if self.selectedCurrency == nil {
                self.selectedCurrency = self.defaultCAD
            }
            
            self.isLoading = false
            self.errorMessage = ""
            
            print("✅ Successfully loaded \(fetchedCurrencies.count) currencies")
            print("📊 Total available currencies including CAD: \(self.allCurrencies.count)")
        }
    }
    
    func addCurrency(_ currency: Currency) async throws {
        print("💾 Adding new currency: \(currency.name) (\(currency.symbol))")
        
        let docRef = db.collection("Currencies").document()
        var newCurrency = currency
        newCurrency.id = docRef.documentID
        
        try await docRef.setData(newCurrency.toDictionary())
        print("✅ Currency added successfully")
    }
    
    func addCurrencyToFirestore(currencyId: String, data: [String: Any], completion: @escaping (Bool) -> Void) {
        db.collection("Currencies").document(currencyId).setData(data) { error in
            completion(error == nil)
        }
    }
    
    // Add these methods to your existing CurrencyManager class

    func fetchDirectExchangeRates() {
        print("🔍 Fetching direct exchange rates from Firestore...")
        
        directRatesListener?.remove()
        
        directRatesListener = db.collection("DirectExchangeRates")
            .addSnapshotListener { [weak self] querySnapshot, error in
                self?.handleDirectRatesUpdate(querySnapshot: querySnapshot, error: error)
            }
    }

    private func handleDirectRatesUpdate(querySnapshot: QuerySnapshot?, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("❌ Error fetching direct exchange rates: \(error.localizedDescription)")
                return
            }
            
            guard let querySnapshot = querySnapshot else {
                print("⚠️ QuerySnapshot is nil for DirectExchangeRates")
                return
            }
            
            var fetchedRates: [String: DirectExchangeRate] = [:]
            
            for document in querySnapshot.documents {
                let data = document.data()
                
                if let fromCurrency = data["fromCurrency"] as? String,
                   let toCurrency = data["toCurrency"] as? String,
                   let rate = data["rate"] as? Double {
                    
                    var directRate = DirectExchangeRate(
                        fromCurrency: fromCurrency,
                        toCurrency: toCurrency,
                        rate: rate
                    )
                    directRate.id = document.documentID
                    directRate.createdAt = data["createdAt"] as? Timestamp
                    directRate.updatedAt = data["updatedAt"] as? Timestamp
                    
                    let key = "\(fromCurrency)_to_\(toCurrency)"
                    fetchedRates[key] = directRate
                    
                    print("💱 Found direct rate: 1 \(fromCurrency) = \(rate) \(toCurrency)")
                }
            }
            
            self.directExchangeRates = fetchedRates
            print("✅ Loaded \(fetchedRates.count) direct exchange rates")
        }
    }

    func getDirectExchangeRate(from: String, to: String) -> Double? {
        let key = "\(from)_to_\(to)"
        return directExchangeRates[key]?.rate
    }

    func saveDirectExchangeRate(from: String, to: String, rate: Double) async throws {
        print("💾 Saving direct exchange rate: 1 \(from) = \(rate) \(to)")
        
        let directRate = DirectExchangeRate(fromCurrency: from, toCurrency: to, rate: rate)
        let docRef = db.collection("DirectExchangeRates").document(directRate.id!)
        
        try await docRef.setData(directRate.toDictionary())
        print("✅ Direct exchange rate saved successfully")
    }

    func requiresDirectRate(givingCurrency: Currency, receivingCurrency: Currency) -> Bool {
        // Check if both currencies are non-USD
        let bothNonUSD = givingCurrency.name != "USD" && receivingCurrency.name != "USD"
        
        if bothNonUSD {
            // Check if we already have this direct rate
            let directRate = getDirectExchangeRate(from: givingCurrency.name, to: receivingCurrency.name)
            return directRate == nil // Return true if we DON'T have the rate
        }
        
        return false // USD is involved, use existing logic
    }

    struct DirectExchangeRate: Identifiable, Codable {
        var id: String?
        var fromCurrency: String
        var toCurrency: String
        var rate: Double
        var createdAt: Timestamp?
        var updatedAt: Timestamp?
        
        init(fromCurrency: String, toCurrency: String, rate: Double) {
            self.id = "\(fromCurrency)_to_\(toCurrency)"
            self.fromCurrency = fromCurrency
            self.toCurrency = toCurrency
            self.rate = rate
            self.createdAt = Timestamp()
            self.updatedAt = Timestamp()
        }
        
        func toDictionary() -> [String: Any] {
            return [
                "fromCurrency": fromCurrency,
                "toCurrency": toCurrency,
                "rate": rate,
                "createdAt": createdAt ?? Timestamp(),
                "updatedAt": Timestamp()
            ]
        }
    }
    
    deinit {
        currenciesListener?.remove()
        directRatesListener?.remove() // Add this line
    }
}

extension Currency: Equatable {
    static func == (lhs: Currency, rhs: Currency) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name
    }
}
