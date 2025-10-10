# Currency Transaction System Documentation

## Table of Contents
1. [Overview](#overview)
2. [Transaction Types](#transaction-types)
3. [Data Models](#data-models)
4. [Firebase Collections Structure](#firebase-collections-structure)
5. [Non-Currency Exchange Transaction Flow](#non-currency-exchange-transaction-flow)
6. [Firebase Operation Rules](#firebase-operation-rules)
7. [Balance Management](#balance-management)
8. [UI Flow](#ui-flow)
9. [Error Handling](#error-handling)
10. [Code Examples](#code-examples)

---

## Overview

The Aromex V2 app is a currency and transaction management system that tracks balances for multiple entities (customers, middlemen, suppliers, and "myself") across different currencies. The system supports two types of currency transactions:

1. **Regular Currency Transaction** (Non-Exchange): Simple transfer of a single currency from one party to another
2. **Currency Exchange Transaction**: Exchange of one currency for another at a specified rate

This document focuses on **Regular Currency Transactions (Non-Exchange)**.

---

## Transaction Types

### Regular Currency Transaction (isExchange = false)
A simple transfer where:
- One party (giver) gives a specific amount of currency
- Another party (taker) receives the same amount of the same currency
- Only one currency is involved
- Balances are updated for both parties
- Transaction is recorded with balance snapshots

**Example**: Customer A gives $500 CAD to Myself → Customer A's CAD balance decreases by 500, My CAD balance increases by 500

### Currency Exchange Transaction (isExchange = true)
A more complex exchange where:
- One party gives an amount in one currency
- Another party receives an equivalent amount in a different currency
- Exchange rate determines the conversion
- Profit is calculated based on rate differences
- Both currencies' balances are updated

**Example**: Myself gives 500 USD to Customer B, Customer B receives 680 CAD at rate 1.36

---

## Data Models

### CurrencyTransaction (Model)

Located in: `/Aromex_V2/Models/CurrencyTransaction.swift`

```swift
struct CurrencyTransaction: Identifiable {
    // Core fields (used in ALL transactions)
    var id: String?                           // Firestore document ID
    var amount: Double                        // Amount being given
    var currencyGiven: String                 // Currency symbol (e.g., "$", "₹", "€")
    var currencyName: String                  // Currency name (e.g., "CAD", "INR", "EUR")
    var giver: String                         // Customer ID or "myself_special_id"
    var giverName: String                     // Display name of giver
    var taker: String                         // Customer ID or "myself_special_id"
    var takerName: String                     // Display name of taker
    var notes: String                         // Optional notes
    var timestamp: Timestamp                  // When transaction occurred
    var balancesAfterTransaction: [String: Any]  // Snapshot of balances AFTER this transaction
    
    // Exchange-specific fields (only used when isExchange = true)
    var isExchange: Bool = false              // Flag to identify exchange transactions
    var receivingCurrency: String?            // Currency symbol being received
    var receivingCurrencyName: String?        // Currency name being received
    var customExchangeRate: Double?           // Rate used for exchange
    var marketExchangeRate: Double?           // Market rate for comparison
    var receivedAmount: Double?               // Amount received in other currency
    var profitAmount: Double?                 // Profit from rate difference
    var profitCurrency: String?               // Currency in which profit is calculated
}
```

### Customer (Model)

Located in: `/Aromex_V2/Models/Customer.swift`

```swift
struct Customer: Identifiable {
    var id: String?                 // Firestore document ID (or "myself_special_id")
    var name: String                // Display name
    var phone: String               // Contact phone
    var email: String               // Contact email
    var address: String             // Physical address
    var notes: String               // Additional notes
    var balance: Double             // CAD balance only
    var type: CustomerType          // .customer, .middleman, or .supplier
    var createdAt: Timestamp?
    var updatedAt: Timestamp?
}
```

### Currency (Model)

Located in: `/Aromex_V2/Models/Currency.swift`

```swift
struct Currency: Identifiable {
    var id: String?                 // Firestore document ID
    var name: String                // Currency code (e.g., "USD", "INR")
    var symbol: String              // Currency symbol (e.g., "$", "₹")
    var exchangeRate: Double        // Rate relative to CAD (1 CAD = exchangeRate of this currency)
    var createdAt: Timestamp?
    var updatedAt: Timestamp?
}
```

**Note**: CAD is the base currency with `exchangeRate = 1.0` and `symbol = "$"`

---

## Firebase Collections Structure

### Collections Overview

1. **Customers** - Regular customer entities
2. **Middlemen** - Middleman entities (intermediaries)
3. **Suppliers** - Supplier entities
4. **CurrencyTransactions** - All currency transaction records
5. **CurrencyBalances** - Non-CAD currency balances for all entities
6. **Balances** - Special collection containing the "Cash" document for "myself"
7. **Currencies** - Available currencies (excluding CAD which is hardcoded)

### Collection: CurrencyTransactions

**Purpose**: Stores all currency transaction records (both regular and exchange)

**Document Structure** (for regular non-exchange transaction):
```json
{
  "amount": 500.0,
  "currencyGiven": "$",
  "currencyName": "CAD",
  "giver": "customer_id_123",
  "giverName": "John Doe [C]",
  "taker": "myself_special_id",
  "takerName": "Myself",
  "notes": "Payment for order #123",
  "timestamp": Timestamp,
  "balancesAfterTransaction": {
    "customer_id_123": {
      "CAD": 2500.0,
      "USD": 1000.0,
      "INR": 5000.0
    },
    "myself": {
      "amount": 15000.0,    // CAD balance
      "USD": 3000.0,
      "INR": 10000.0
    }
  },
  "isExchange": false
}
```

**Key Points**:
- Each document represents one transaction
- `balancesAfterTransaction` stores a snapshot of ALL balances for involved parties AFTER the transaction
- This allows for balance reconstruction at any point in time
- Ordered by `timestamp` descending (newest first)

### Collection: Customers / Middlemen / Suppliers

**Purpose**: Store entity information and CAD balance only

**Document Structure**:
```json
{
  "name": "John Doe",
  "phone": "+1234567890",
  "email": "john@example.com",
  "address": "123 Main St",
  "notes": "VIP customer",
  "balance": 3000.0,     // CAD balance ONLY
  "createdAt": Timestamp,
  "updatedAt": Timestamp
}
```

**Key Points**:
- Document ID is the customer ID (e.g., "customer_id_123")
- `balance` field ONLY stores CAD (Canadian Dollar) balance
- All other currency balances are stored in `CurrencyBalances` collection
- Customer type is determined by which collection they're in

### Collection: CurrencyBalances

**Purpose**: Store non-CAD currency balances for all entities

**Document Structure**:
```json
{
  "USD": 1500.0,
  "INR": 25000.0,
  "EUR": 800.0,
  "updatedAt": Timestamp
}
```

**Key Points**:
- Document ID matches the customer ID from Customers/Middlemen/Suppliers collection
- Each field (except `updatedAt`) represents a currency balance
- Field key is the currency name (e.g., "USD", "INR")
- Does NOT store CAD (that's in the main customer document)

### Collection: Balances (Special "Cash" Document)

**Purpose**: Store "myself" cash balances

**Document Path**: `Balances/Cash`

**Document Structure**:
```json
{
  "amount": 15000.0,     // CAD balance for "myself"
  "USD": 3000.0,
  "INR": 50000.0,
  "EUR": 2000.0,
  "updatedAt": Timestamp
}
```

**Key Points**:
- This is a special document representing the business owner's cash
- `amount` field specifically represents CAD balance
- Other currencies are stored as separate fields
- Used when giver or taker is "myself_special_id"

### Collection: Currencies

**Purpose**: Store available currencies and their exchange rates

**Document Structure**:
```json
{
  "name": "USD",
  "symbol": "$",
  "exchangeRate": 1.35,    // 1 CAD = 1.35 USD
  "createdAt": Timestamp,
  "updatedAt": Timestamp
}
```

**Key Points**:
- CAD is NOT stored here (it's hardcoded in the app)
- Exchange rates are relative to CAD as the base currency
- Document ID is auto-generated

---

## Non-Currency Exchange Transaction Flow

### Step-by-Step Process

#### 1. User Input (UI Layer)
Located in: `/Aromex_V2/Views/AddEntryView.swift`

User provides:
- **From Customer**: Who is giving the currency (giver)
- **To Customer**: Who is receiving the currency (taker)
- **Amount**: How much currency is being transferred
- **Currency**: Which currency (e.g., CAD, USD, INR)
- **Notes**: Optional description
- **Date**: When the transaction occurred (defaults to now)

**Important**: The "Exchange" toggle must be OFF for a regular transaction.

#### 2. Transaction Validation (TransactionManager)
Located in: `/Aromex_V2/Managers/TransactionManager.swift`

**Method**: `addTransaction()`

Validation checks:
```swift
// Check both parties are selected
guard let fromCustomer = fromCustomer, 
      let toCustomer = toCustomer else {
    completion(false, "Please select both giver and receiver")
    return
}

// Check amount is positive
guard amount > 0 else {
    completion(false, "Amount must be greater than 0")
    return
}
```

#### 3. Customer Validation
**Method**: `getCustomerType(customerId:)`

Before processing, the system validates that customers exist:
- If giver is not "myself", verify they exist in Customers/Middlemen/Suppliers
- If taker is not "myself", verify they exist in Customers/Middlemen/Suppliers
- Determine which collection each customer belongs to

**Search Order**:
1. Check `Customers` collection
2. Check `Middlemen` collection  
3. Check `Suppliers` collection
4. Throw error if not found

#### 4. Transaction Processing
**Method**: `processTransaction()`

This is the core of the transaction flow. It performs the following operations **in a single Firestore batch**:

##### 4.1. Update Giver's Balance

```swift
if fromCustomer.id == "myself_special_id" {
    // Update my cash balance
    try await updateMyCashBalance(
        currency: currency, 
        amount: -amount,  // Negative because giving
        batch: batch
    )
} else {
    // Update customer balance
    try await updateCustomerBalance(
        customerId: fromCustomer.id!, 
        currency: currency, 
        amount: -amount,  // Negative because giving
        batch: batch
    )
}
```

##### 4.2. Update Taker's Balance

```swift
if toCustomer.id == "myself_special_id" {
    // Update my cash balance
    try await updateMyCashBalance(
        currency: currency, 
        amount: amount,  // Positive because receiving
        batch: batch
    )
} else {
    // Update customer balance
    try await updateCustomerBalance(
        customerId: toCustomer.id!, 
        currency: currency, 
        amount: amount,  // Positive because receiving
        batch: batch
    )
}
```

##### 4.3. Calculate Balances After Transaction

**Critical**: The system calculates what the balances WILL BE after the transaction:

```swift
var balancesAfterTransaction: [String: Any] = [:]

// For giver
if fromCustomer.id == "myself_special_id" {
    let myCurrentBalances = try await getMyCashBalances()
    var myNewBalances = myCurrentBalances
    
    if currency.symbol == "$" {
        myNewBalances["amount"] = (myNewBalances["amount"] ?? 0.0) - amount
    } else {
        myNewBalances[currency.name] = (myNewBalances[currency.name] ?? 0.0) - amount
    }
    balancesAfterTransaction["myself"] = myNewBalances
} else {
    // Similar logic for customers
    let customerCurrentBalances = try await getCustomerBalances(customerId: fromCustomer.id!)
    var customerNewBalances = customerCurrentBalances
    
    if currency.symbol == "$" {
        customerNewBalances["CAD"] = (customerNewBalances["CAD"] ?? 0.0) - amount
    } else {
        customerNewBalances[currency.name] = (customerNewBalances[currency.name] ?? 0.0) - amount
    }
    balancesAfterTransaction[fromCustomer.id!] = customerNewBalances
}

// Repeat for taker (with positive amounts)
```

##### 4.4. Create Transaction Record

```swift
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
    customDate: customDate  // Optional custom date
)

let transactionRef = db.collection("CurrencyTransactions").document()
batch.setData(transaction.toDictionary(), forDocument: transactionRef)
```

##### 4.5. Commit All Changes

```swift
try await batch.commit()
```

**Why Batch?** All operations (balance updates + transaction record) happen atomically. If any step fails, everything rolls back.

---

## Firebase Operation Rules

### Rule 1: Atomic Batch Operations

**All balance updates and transaction creation MUST happen in a single Firestore batch.**

**Why**: Ensures data consistency. If the transaction record is created but balance updates fail (or vice versa), the data would be corrupted.

```swift
let batch = db.batch()

// Update balances
try await updateMyCashBalance(currency: currency, amount: -amount, batch: batch)
try await updateCustomerBalance(customerId: toCustomer.id!, currency: currency, amount: amount, batch: batch)

// Create transaction record
batch.setData(transaction.toDictionary(), forDocument: transactionRef)

// Commit everything at once
try await batch.commit()
```

### Rule 2: CAD vs Other Currencies Storage

**CAD (Canadian Dollar)** and **Other Currencies** are stored in different locations:

#### For CAD:
- **"Myself"**: Stored in `Balances/Cash` document under field `amount`
- **Customers/Middlemen/Suppliers**: Stored in their respective collection documents under field `balance`

#### For Other Currencies (USD, INR, EUR, etc.):
- **"Myself"**: Stored in `Balances/Cash` document under field with currency name
- **Customers/Middlemen/Suppliers**: Stored in `CurrencyBalances/{customerId}` document under field with currency name

**Code Example**:
```swift
if currency.symbol == "$" {
    // This is CAD - update in main document
    if fromCustomer.id == "myself_special_id" {
        // Update Balances/Cash document, field "amount"
        currentData["amount"] = currentAmount + amount
    } else {
        // Update Customers/{id} document, field "balance"
        batch.updateData(["balance": currentBalance + amount], forDocument: customerRef)
    }
} else {
    // This is other currency - update in CurrencyBalances
    if fromCustomer.id == "myself_special_id" {
        // Update Balances/Cash document, field with currency name
        currentData[currency.name] = currentAmount + amount
    } else {
        // Update CurrencyBalances/{id} document, field with currency name
        currentData[currency.name] = currentAmount + amount
    }
}
```

### Rule 3: Customer Type Detection

**Customers can be in one of three collections**: Customers, Middlemen, or Suppliers

**Before any balance update**, the system MUST determine which collection the customer belongs to:

```swift
enum CustomerType: String {
    case customer = "Customer"
    case middleman = "Middleman"
    case supplier = "Supplier"
    
    var rawValue: String {
        // Returns the enum string value
    }
}

// Search order: Customers → Middlemen → Suppliers
private func getCustomerType(customerId: String) async throws -> CustomerType {
    // Check Customers
    let customersDoc = try await db.collection("Customers").document(customerId).getDocument()
    if customersDoc.exists { return .customer }
    
    // Check Middlemen
    let middlemenDoc = try await db.collection("Middlemen").document(customerId).getDocument()
    if middlemenDoc.exists { return .middleman }
    
    // Check Suppliers
    let suppliersDoc = try await db.collection("Suppliers").document(customerId).getDocument()
    if suppliersDoc.exists { return .supplier }
    
    throw NSError(domain: "TransactionError", code: 404,
                 userInfo: [NSLocalizedDescriptionKey: "Customer not found in any collection"])
}
```

### Rule 4: Balance Snapshots

**Every transaction MUST include a snapshot of balances AFTER the transaction.**

Format:
```json
{
  "balancesAfterTransaction": {
    "myself": {           // If "myself" is involved
      "amount": 15000.0,  // CAD balance
      "USD": 3000.0,
      "INR": 50000.0
    },
    "customer_id_123": {  // If customer is involved
      "CAD": 2500.0,      // Note: "CAD" not "amount" for customers
      "USD": 1000.0,
      "INR": 5000.0
    }
  }
}
```

**Why**: Allows historical balance reconstruction and auditing.

### Rule 5: Timestamp and Metadata

**Every update operation MUST include a timestamp:**

```swift
currentData["updatedAt"] = Timestamp()
```

For transaction creation, allow custom dates:
```swift
self.timestamp = customDate != nil ? Timestamp(date: customDate!) : Timestamp()
```

### Rule 6: Special ID for "Myself"

**The business owner/app user is represented by a special ID:**

```swift
let MYSELF_ID = "myself_special_id"
```

This is used to distinguish between:
- Updating my balances (`Balances/Cash` document)
- Updating customer balances (customer collection documents)

---

## Balance Management

### How Balance Updates Work

#### updateMyCashBalance()
```swift
private func updateMyCashBalance(
    currency: Currency, 
    amount: Double, 
    batch: WriteBatch
) async throws {
    let balancesRef = db.collection("Balances").document("Cash")
    
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
    
    // Use merge: true to preserve other fields
    batch.setData(currentData, forDocument: balancesRef, merge: true)
}
```

#### updateCustomerBalance() - for Currency object
```swift
private func updateCustomerBalance(
    customerId: String, 
    currency: Currency, 
    amount: Double, 
    batch: WriteBatch
) async throws {
    // Determine collection
    let customerType = try await getCustomerType(customerId: customerId)
    let collectionName = "\(customerType.rawValue)s"  // "Customers", "Middlemen", "Suppliers"
    
    if currency.symbol == "$" {
        // Update CAD balance in main customer document
        let customerRef = db.collection(collectionName).document(customerId)
        
        let customerDoc = try await customerRef.getDocument()
        guard customerDoc.exists else {
            throw NSError(domain: "TransactionError", code: 404, 
                         userInfo: [NSLocalizedDescriptionKey: "\(customerType.displayName) not found"])
        }
        
        let currentBalance = customerDoc.data()?["balance"] as? Double ?? 0.0
        batch.updateData([
            "balance": currentBalance + amount, 
            "updatedAt": Timestamp()
        ], forDocument: customerRef)
    } else {
        // Update non-CAD balance in CurrencyBalances collection
        let currencyBalanceRef = db.collection("CurrencyBalances").document(customerId)
        let currencyDoc = try await currencyBalanceRef.getDocument()
        var currentData = currencyDoc.data() ?? [:]
        
        let currentAmount = currentData[currency.name] as? Double ?? 0.0
        currentData[currency.name] = currentAmount + amount
        currentData["updatedAt"] = Timestamp()
        
        // Use merge: true to preserve other currency fields
        batch.setData(currentData, forDocument: currencyBalanceRef, merge: true)
    }
}
```

### Getting Current Balances

#### getMyCashBalances()
```swift
private func getMyCashBalances() async throws -> [String: Double] {
    let balancesRef = db.collection("Balances").document("Cash")
    let balancesDoc = try await balancesRef.getDocument()
    let data = balancesDoc.data() ?? [:]
    
    var balances: [String: Double] = [:]
    for (key, value) in data {
        if key != "updatedAt", let doubleValue = value as? Double {
            balances[key] = doubleValue
        }
    }
    return balances
    // Returns: ["amount": 15000.0, "USD": 3000.0, "INR": 50000.0, ...]
}
```

#### getCustomerBalances()
```swift
private func getCustomerBalances(customerId: String) async throws -> [String: Double] {
    var balances: [String: Double] = [:]
    
    // Determine collection
    let customerType = try await getCustomerType(customerId: customerId)
    let collectionName = "\(customerType.rawValue)s"
    
    // Get CAD balance
    let customerRef = db.collection(collectionName).document(customerId)
    let customerDoc = try await customerRef.getDocument()
    
    if customerDoc.exists, let cadBalance = customerDoc.data()?["balance"] as? Double {
        balances["CAD"] = cadBalance
    } else {
        balances["CAD"] = 0.0
    }
    
    // Get other currency balances
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
    // Returns: ["CAD": 2500.0, "USD": 1000.0, "INR": 5000.0, ...]
}
```

---

## UI Flow

### AddEntryView Components

Located in: `/Aromex_V2/Views/AddEntryView.swift`

#### Key State Variables
```swift
@State private var selectedFromCustomer: Customer?     // Giver
@State private var selectedToCustomer: Customer?       // Taker
@State private var amount: String = ""                 // Amount string
@State private var notes: String = ""                  // Notes
@State private var isExchangeOn: Bool = false          // Exchange toggle
@State private var selectedTransactionDate: Date = Date()
@State private var isProcessingTransaction: Bool = false
@State private var transactionError: String = ""
```

#### Transaction Submission Flow

1. User fills in the form
2. User clicks "Add Transaction" button
3. System validates inputs (both customers selected, amount > 0)
4. System calls appropriate transaction method:

```swift
if isExchangeOn {
    // Call addExchangeTransaction (not covered in this doc)
    transactionManager.addExchangeTransaction(...)
} else {
    // Call addTransaction (regular transaction)
    transactionManager.addTransaction(
        amount: transactionAmount,
        currency: currency,
        fromCustomer: fromCustomer,
        toCustomer: toCustomer,
        notes: notes.trimmingCharacters(in: .whitespaces),
        customDate: selectedTransactionDate
    ) { success, error in
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
```

5. On success: Clear form and show success message
6. On failure: Display error message

---

## Error Handling

### Common Error Scenarios

#### 1. Customer Not Found
```swift
throw NSError(
    domain: "TransactionError", 
    code: 404,
    userInfo: [NSLocalizedDescriptionKey: "Customer not found in any collection"]
)
```

**Cause**: Customer ID doesn't exist in Customers, Middlemen, or Suppliers collections

**Solution**: Verify customer still exists, refresh customer list

#### 2. Missing Required Fields
```swift
completion(false, "Please select both giver and receiver")
```

**Cause**: User didn't select both parties

**Solution**: Validate UI inputs before submission

#### 3. Invalid Amount
```swift
completion(false, "Amount must be greater than 0")
```

**Cause**: Amount is zero or negative

**Solution**: Add input validation in UI

#### 4. Batch Commit Failure

**Cause**: Network issue, permission issue, or concurrent modification

**Solution**: Transaction automatically rolls back, show error to user, allow retry

---

## Code Examples

### Example 1: Simple CAD Transaction (Customer → Myself)

**Scenario**: Customer John Doe (ID: "cust_123") pays me $500 CAD

```swift
// UI prepares data
let fromCustomer = Customer(
    id: "cust_123", 
    name: "John Doe [C]", 
    balance: 3000.0,
    type: .customer
)
let toCustomer = Customer(
    id: "myself_special_id", 
    name: "Myself", 
    balance: 0.0,
    type: .customer
)
let cadCurrency = Currency(
    id: "default_cad_id", 
    name: "CAD", 
    symbol: "$", 
    exchangeRate: 1.0
)

// Call transaction manager
transactionManager.addTransaction(
    amount: 500.0,
    currency: cadCurrency,
    fromCustomer: fromCustomer,
    toCustomer: toCustomer,
    notes: "Payment for order #456",
    customDate: Date()
) { success, error in
    if success {
        print("Transaction successful")
    } else {
        print("Transaction failed: \(error ?? "Unknown error")")
    }
}
```

**Firebase Operations**:
1. Read `Customers/cust_123` → verify exists
2. Read `Balances/Cash` → get current balances
3. Batch update:
   - Update `Customers/cust_123` field `balance`: 3000.0 - 500.0 = 2500.0
   - Update `Balances/Cash` field `amount`: (current) + 500.0
   - Create document in `CurrencyTransactions` with all data
4. Commit batch

**Result**:
- John Doe's CAD balance: 3000.0 → 2500.0
- My CAD balance: (current) → (current + 500.0)
- New transaction record created

### Example 2: USD Transaction (Myself → Supplier)

**Scenario**: I pay supplier XYZ Corp $1000 USD

```swift
let fromCustomer = Customer(
    id: "myself_special_id", 
    name: "Myself", 
    balance: 0.0,
    type: .customer
)
let toCustomer = Customer(
    id: "supp_789", 
    name: "XYZ Corp [S]", 
    balance: 0.0,
    type: .supplier
)
let usdCurrency = Currency(
    id: "curr_usd", 
    name: "USD", 
    symbol: "$", 
    exchangeRate: 1.35
)

transactionManager.addTransaction(
    amount: 1000.0,
    currency: usdCurrency,
    fromCustomer: fromCustomer,
    toCustomer: toCustomer,
    notes: "Payment for supplies",
    customDate: Date()
) { success, error in
    if success {
        print("Transaction successful")
    }
}
```

**Firebase Operations**:
1. Read `Suppliers/supp_789` → verify exists
2. Read `Balances/Cash` → get my current balances
3. Read `CurrencyBalances/supp_789` → get supplier's currency balances
4. Batch update:
   - Update `Balances/Cash` field `USD`: (current) - 1000.0
   - Update `CurrencyBalances/supp_789` field `USD`: (current) + 1000.0
   - Create document in `CurrencyTransactions`
5. Commit batch

**Result**:
- My USD balance: (current) → (current - 1000.0)
- XYZ Corp's USD balance: (current) → (current + 1000.0)
- New transaction record created

### Example 3: Complete Transaction Flow Breakdown

**Scenario**: Customer "Alice" gives me 750 INR

**Step 1: UI Input**
- From: Alice [C] (ID: alice_001)
- To: Myself (ID: myself_special_id)
- Amount: 750
- Currency: INR (₹)
- Notes: "Payment received"
- Date: 2025-10-08 14:30:00

**Step 2: Validation**
```swift
// Check both selected
✓ fromCustomer = Customer(id: "alice_001", name: "Alice [C]", ...)
✓ toCustomer = Customer(id: "myself_special_id", name: "Myself", ...)

// Check amount
✓ amount = 750.0 > 0
```

**Step 3: Customer Type Detection**
```swift
getCustomerType("alice_001")
→ Check Customers/alice_001 → EXISTS
→ Return CustomerType.customer
```

**Step 4: Process Transaction**

Create batch:
```swift
let batch = db.batch()
```

Update Alice's balance (giver):
```swift
updateCustomerBalance(customerId: "alice_001", currency: INR, amount: -750.0, batch: batch)
→ customerType = .customer → collection = "Customers"
→ currency.symbol = "₹" (not "$") → Update in CurrencyBalances
→ Read CurrencyBalances/alice_001 → { "INR": 5000.0, "USD": 200.0 }
→ Calculate new: 5000.0 + (-750.0) = 4250.0
→ Prepare batch update: CurrencyBalances/alice_001 { "INR": 4250.0, "updatedAt": Timestamp }
```

Update My balance (taker):
```swift
updateMyCashBalance(currency: INR, amount: 750.0, batch: batch)
→ currency.symbol = "₹" (not "$") → Update INR field
→ Read Balances/Cash → { "amount": 10000.0, "USD": 3000.0, "INR": 15000.0 }
→ Calculate new: 15000.0 + 750.0 = 15750.0
→ Prepare batch update: Balances/Cash { "INR": 15750.0, "updatedAt": Timestamp }
```

Get balances after transaction:
```swift
getMyCashBalances()
→ Returns: { "amount": 10000.0, "USD": 3000.0, "INR": 15000.0 }
→ Calculate after: { "amount": 10000.0, "USD": 3000.0, "INR": 15750.0 }

getCustomerBalances("alice_001")
→ Returns: { "CAD": 1500.0, "INR": 5000.0, "USD": 200.0 }
→ Calculate after: { "CAD": 1500.0, "INR": 4250.0, "USD": 200.0 }

balancesAfterTransaction = {
  "myself": { "amount": 10000.0, "USD": 3000.0, "INR": 15750.0 },
  "alice_001": { "CAD": 1500.0, "INR": 4250.0, "USD": 200.0 }
}
```

Create transaction record:
```swift
let transaction = CurrencyTransaction(
    amount: 750.0,
    currencyGiven: "₹",
    currencyName: "INR",
    giver: "alice_001",
    giverName: "Alice [C]",
    taker: "myself_special_id",
    takerName: "Myself",
    notes: "Payment received",
    balancesAfterTransaction: balancesAfterTransaction,
    customDate: Date("2025-10-08 14:30:00")
)

let transactionRef = db.collection("CurrencyTransactions").document()
batch.setData(transaction.toDictionary(), forDocument: transactionRef)
```

Commit:
```swift
try await batch.commit()
```

**Step 5: Result**

Alice's balances:
- CAD: 1500.0 (unchanged)
- INR: 5000.0 → 4250.0
- USD: 200.0 (unchanged)

My balances:
- CAD: 10000.0 (unchanged)
- INR: 15000.0 → 15750.0
- USD: 3000.0 (unchanged)

New transaction document created in `CurrencyTransactions` collection.

---

## Summary

### Key Takeaways

1. **Regular Currency Transactions** transfer a single currency from one party to another
2. **All operations use Firestore batches** to ensure atomicity
3. **CAD is special**: Stored in different fields than other currencies
4. **Customer type must be determined** before any balance update
5. **Balance snapshots** are stored with every transaction
6. **"Myself" uses a special ID** and a special Firestore document
7. **Validation happens at multiple levels**: UI, TransactionManager, Firebase

### To Recreate This Feature

1. **Set up Firebase collections**: CurrencyTransactions, Customers, Middlemen, Suppliers, CurrencyBalances, Balances, Currencies
2. **Create data models**: CurrencyTransaction, Customer, Currency
3. **Implement TransactionManager** with methods:
   - `addTransaction()` - Main entry point
   - `processTransaction()` - Core transaction logic
   - `updateMyCashBalance()` - Update "myself" balances
   - `updateCustomerBalance()` - Update customer balances
   - `getCustomerType()` - Determine customer collection
   - `getMyCashBalances()` - Get "myself" balances
   - `getCustomerBalances()` - Get customer balances
4. **Build UI** with form inputs for from/to/amount/currency/notes/date
5. **Handle async operations** with proper error handling and loading states
6. **Test thoroughly** with different scenarios and edge cases

---

## Related Documentation

- **Exchange Transactions**: See separate documentation for `isExchange = true` transactions
- **Balance Reporting**: How to calculate and display balances from transaction history
- **Customer Management**: Adding/editing/deleting customers
- **Currency Management**: Adding/editing currencies and exchange rates

---

**Document Version**: 1.0  
**Last Updated**: October 8, 2025  
**Author**: Documentation generated from Aromex V2 codebase

