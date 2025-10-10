# Currency Transaction Quick Reference Guide

## What is a Non-Currency Exchange Transaction?

A **simple transfer** of a single currency from one party to another.
- Example: Customer A gives me $500 CAD
- Only ONE currency involved
- Both parties' balances update for that currency

**Contrast**: Exchange transaction involves TWO currencies (e.g., give USD, receive CAD)

---

## Quick Architecture Overview

```
User Input (AddEntryView)
    ↓
TransactionManager.addTransaction()
    ↓
Validate: Check customers & amount
    ↓
Determine customer types (which collection?)
    ↓
Create Firestore Batch
    ↓
Update Giver Balance (-amount)
    ↓
Update Taker Balance (+amount)
    ↓
Calculate Balance Snapshots
    ↓
Create Transaction Record
    ↓
Commit Batch (All or Nothing)
```

---

## Firebase Collections (Quick View)

| Collection | Purpose | Document ID | Key Fields |
|------------|---------|-------------|------------|
| **CurrencyTransactions** | All transaction records | Auto-generated | `amount`, `currencyGiven`, `giver`, `taker`, `balancesAfterTransaction`, `isExchange` |
| **Customers** | Customer entities | Customer ID | `name`, `balance` (CAD only), `type` |
| **Middlemen** | Middleman entities | Middleman ID | `name`, `balance` (CAD only), `type` |
| **Suppliers** | Supplier entities | Supplier ID | `name`, `balance` (CAD only), `type` |
| **CurrencyBalances** | Non-CAD balances | Customer/Middleman/Supplier ID | `USD`, `INR`, `EUR`, etc. |
| **Balances** (Cash doc) | "Myself" balances | Fixed: "Cash" | `amount` (CAD), `USD`, `INR`, etc. |
| **Currencies** | Available currencies | Auto-generated | `name`, `symbol`, `exchangeRate` |

---

## Critical Rules

### Rule 1: CAD Storage Location
- **"Myself"**: `Balances/Cash` → field `amount`
- **Customer/Middleman/Supplier**: `{Type}s/{id}` → field `balance`

### Rule 2: Other Currency Storage
- **"Myself"**: `Balances/Cash` → field `{currencyName}`
- **Customer/Middleman/Supplier**: `CurrencyBalances/{id}` → field `{currencyName}`

### Rule 3: Always Use Batches
```swift
let batch = db.batch()
// ... add all operations to batch
try await batch.commit()  // Atomic!
```

### Rule 4: Special IDs
- **"Myself"** = `"myself_special_id"`
- Customers/Middlemen/Suppliers use UUID strings

### Rule 5: Balance Snapshots Required
Every transaction MUST store `balancesAfterTransaction`:
```json
{
  "myself": { "amount": 10000, "USD": 2000 },
  "customer_id": { "CAD": 5000, "USD": 1000 }
}
```

---

## Code Snippets

### Adding a Transaction (from UI)

```swift
transactionManager.addTransaction(
    amount: 500.0,
    currency: selectedCurrency,
    fromCustomer: selectedFromCustomer,  // Who gives
    toCustomer: selectedToCustomer,      // Who receives
    notes: "Payment note",
    customDate: Date()
) { success, error in
    if success {
        print("✅ Transaction successful")
    } else {
        print("❌ Error: \(error ?? "Unknown")")
    }
}
```

### Determining Customer Type

```swift
private func getCustomerType(customerId: String) async throws -> CustomerType {
    // Check Customers
    if try await db.collection("Customers").document(customerId).getDocument().exists {
        return .customer
    }
    // Check Middlemen
    if try await db.collection("Middlemen").document(customerId).getDocument().exists {
        return .middleman
    }
    // Check Suppliers
    if try await db.collection("Suppliers").document(customerId).getDocument().exists {
        return .supplier
    }
    throw NSError(...)
}
```

### Updating Balances

```swift
// For CAD
if currency.symbol == "$" {
    if customerId == "myself_special_id" {
        // Update Balances/Cash field "amount"
    } else {
        // Update Customers/{id} field "balance"
    }
}
// For other currencies
else {
    if customerId == "myself_special_id" {
        // Update Balances/Cash field "{currencyName}"
    } else {
        // Update CurrencyBalances/{id} field "{currencyName}"
    }
}
```

### Complete Batch Example

```swift
let batch = db.batch()

// 1. Update giver balance
try await updateCustomerBalance(
    customerId: fromCustomer.id!,
    currency: currency,
    amount: -amount,  // Negative!
    batch: batch
)

// 2. Update taker balance
try await updateMyCashBalance(
    currency: currency,
    amount: amount,   // Positive!
    batch: batch
)

// 3. Create transaction record
let transaction = CurrencyTransaction(...)
let ref = db.collection("CurrencyTransactions").document()
batch.setData(transaction.toDictionary(), forDocument: ref)

// 4. Commit all at once
try await batch.commit()
```

---

## Common Scenarios

### Scenario 1: Customer pays me in CAD
```
From: Customer "John" (ID: cust_123)
To: Myself
Amount: 500 CAD
```
**Firebase Ops**:
1. Read `Customers/cust_123` (verify exists)
2. Update `Customers/cust_123` field `balance`: -500
3. Update `Balances/Cash` field `amount`: +500
4. Create `CurrencyTransactions` doc

### Scenario 2: I pay supplier in USD
```
From: Myself
To: Supplier "XYZ" (ID: supp_456)
Amount: 1000 USD
```
**Firebase Ops**:
1. Read `Suppliers/supp_456` (verify exists)
2. Update `Balances/Cash` field `USD`: -1000
3. Update `CurrencyBalances/supp_456` field `USD`: +1000
4. Create `CurrencyTransactions` doc

### Scenario 3: Customer gives customer INR
```
From: Customer "Alice" (ID: cust_001)
To: Customer "Bob" (ID: cust_002)
Amount: 2000 INR
```
**Firebase Ops**:
1. Read `Customers/cust_001` & `Customers/cust_002` (verify)
2. Update `CurrencyBalances/cust_001` field `INR`: -2000
3. Update `CurrencyBalances/cust_002` field `INR`: +2000
4. Create `CurrencyTransactions` doc

---

## Transaction Record Structure

### Regular Transaction (isExchange = false)
```json
{
  "amount": 500.0,
  "currencyGiven": "$",
  "currencyName": "CAD",
  "giver": "cust_123",
  "giverName": "John Doe [C]",
  "taker": "myself_special_id",
  "takerName": "Myself",
  "notes": "Payment for order",
  "timestamp": Timestamp,
  "balancesAfterTransaction": {
    "cust_123": { "CAD": 2500.0, "USD": 1000.0 },
    "myself": { "amount": 15000.0, "USD": 3000.0 }
  },
  "isExchange": false
}
```

---

## Validation Checklist

Before processing a transaction:
- [ ] Both `fromCustomer` and `toCustomer` are selected
- [ ] `amount > 0`
- [ ] Currency is selected
- [ ] If customer is not "myself", verify they exist in their collection
- [ ] Ensure customer type is correctly identified

During processing:
- [ ] Use Firestore batch for all operations
- [ ] Update giver balance (negative amount)
- [ ] Update taker balance (positive amount)
- [ ] Calculate and store balance snapshots
- [ ] Create transaction record with all required fields
- [ ] Commit batch

---

## Error Messages

| Error | Meaning | Fix |
|-------|---------|-----|
| "Please select both giver and receiver" | Missing party selection | Select both parties in UI |
| "Amount must be greater than 0" | Invalid amount | Enter positive number |
| "Customer not found in any collection" | Customer ID doesn't exist | Refresh customer list |
| "{Type} not found" | Document deleted/missing | Verify customer exists |

---

## Data Flow Diagram

```
┌─────────────┐
│ AddEntryView│
│  (UI Layer) │
└──────┬──────┘
       │
       │ User clicks "Add Transaction"
       │
       ▼
┌──────────────────────┐
│ TransactionManager   │
│ .addTransaction()    │
└──────┬───────────────┘
       │
       │ Validate inputs
       │
       ▼
┌──────────────────────┐
│ getCustomerType()    │◄─── Check Customers/Middlemen/Suppliers
└──────┬───────────────┘
       │
       │ Create batch
       │
       ▼
┌──────────────────────┐
│ processTransaction() │
└──────┬───────────────┘
       │
       ├─► updateCustomerBalance()  (giver, -amount)
       │
       ├─► updateMyCashBalance()     (taker, +amount)
       │
       ├─► Calculate balances after
       │
       ├─► Create CurrencyTransaction
       │
       └─► batch.commit()
              │
              ▼
      ┌──────────────┐
      │   Firestore  │
      │  (Database)  │
      └──────────────┘
```

---

## Testing Checklist

Test these scenarios:
- [ ] Customer → Myself (CAD)
- [ ] Myself → Customer (CAD)
- [ ] Customer → Customer (CAD)
- [ ] Customer → Myself (USD/INR/etc.)
- [ ] Myself → Supplier (USD/INR/etc.)
- [ ] Middleman → Customer (any currency)
- [ ] Error: Amount = 0
- [ ] Error: Negative amount
- [ ] Error: Missing customer
- [ ] Error: Deleted customer
- [ ] Custom date in past
- [ ] Custom date in future
- [ ] Large amounts (1000000+)
- [ ] Small amounts (0.01)
- [ ] Empty notes
- [ ] Long notes

---

## File Locations

- **Models**: `/Aromex_V2/Models/`
  - `CurrencyTransaction.swift`
  - `Customer.swift`
  - `Currency.swift`

- **Managers**: `/Aromex_V2/Managers/`
  - `TransactionManager.swift`

- **Views**: `/Aromex_V2/Views/`
  - `AddEntryView.swift`

- **Documentation**:
  - `CURRENCY_TRANSACTION_DOCUMENTATION.md` (detailed)
  - `TRANSACTION_QUICK_REFERENCE.md` (this file)

---

## Need More Details?

See `CURRENCY_TRANSACTION_DOCUMENTATION.md` for:
- Complete code walkthroughs
- Detailed Firebase rules
- Exchange transaction documentation
- Balance reconstruction methods
- Advanced error handling
- Complete examples with explanations

---

**Quick Reference Version**: 1.0  
**Last Updated**: October 8, 2025

