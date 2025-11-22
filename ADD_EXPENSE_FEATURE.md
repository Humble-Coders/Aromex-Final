# Add Expense Feature Documentation

## Overview
The Add Expense feature allows users to record business expenses with payment splitting across Cash, Bank, and Credit Card accounts. It automatically updates account balances and maintains transaction history.

## Location
- **Button**: Home Screen → Quick Actions → "Add Expense"
- **File**: `/Users/ansh/Desktop/iOSDev/Aromex/Aromex/AddExpenseDialog.swift`

## Features

### 1. Category Dropdown (✓ Searchable)
- **Collection**: `ExpenseCategories`
- **Field**: `category`
- **Functionality**:
  - Search/filter categories
  - Add new categories on-the-fly
  - Rename existing categories
  - Auto-completion

### 2. Amount Field
- Enter total expense amount in dollars
- Validates that amount is greater than 0

### 3. Payment Split
- **Cash** - Green indicator
- **Bank** - Blue indicator  
- **Credit Card** - Purple indicator

**Features**:
- Visual validation: Shows if split matches total
- Real-time feedback:
  - "Remaining: $X.XX" (if under total)
  - "Over by: $X.XX" (if exceeds total)
  - "✓ Matches total" (when correct)
- All amounts must sum to total amount

### 4. Notes Field (Optional)
- Multi-line text input
- For additional context about the expense

### 5. Save Operation
When user clicks "Save":

#### Firebase Operations:
1. **Update Cash Balance** (if cash amount > 0)
   - Collection: `Balances`
   - Document: `cash`
   - Operation: Deduct cash amount from `amount` field

2. **Update Bank Balance** (if bank amount > 0)
   - Collection: `Balances`
   - Document: `bank`
   - Operation: Deduct bank amount from `amount` field

3. **Update Credit Card Balance** (if credit card amount > 0)
   - Collection: `Balances`
   - Document: `creditCard`
   - Operation: Deduct credit card amount from `amount` field

4. **Create Expense Transaction**
   - Collection: `ExpenseTransactions`
   - Fields:
     ```
     {
       category: String,
       totalAmount: Double,
       paymentSplit: {
         cash: Double,
         bank: Double,
         creditCard: Double
       },
       notes: String,
       date: Timestamp,
       createdAt: Timestamp
     }
     ```

#### All operations use Firebase Batch for atomicity (all succeed or all fail)

### 6. Transaction History
- **Access**: Click history icon (⟲) in toolbar
- **Display**: Last 50 transactions, sorted by date (newest first)
- **Shows**:
  - Category name
  - Total amount (highlighted in red)
  - Payment split breakdown with icons
  - Notes (if any)
  - Transaction date

### 7. User Experience

#### Loading States:
- Shows spinner and "Adding category..." when creating category
- Shows spinner and "Saving expense..." during save operation
- Shows "Loading history..." when fetching transaction history

#### Success:
- Alert: "Expense has been recorded successfully!"
- Form clears automatically after user clicks OK

#### Error Handling:
- Alert shows detailed error message
- Dialog remains open so user can retry
- Form data is preserved

#### Validation:
- Save button disabled until:
  - Category is selected
  - Total amount > 0
  - Payment split matches total amount
  - At least one payment method has value > 0

## UI/UX

### iOS (iPhone/iPad):
- Full-screen presentation
- Navigation bar with Cancel and Save buttons
- History icon in toolbar
- Scrollable form
- Bottom safe area insets

### macOS:
- Sheet presentation (600x700 window)
- Custom header with title and close button
- History icon in header
- Fixed-size, centered window
- Professional spacing and typography

### Form Layout:
1. Category field (required) *
2. Total Amount field (required) *
3. Payment Split section (required) *
   - Cash input
   - Bank input
   - Credit Card input
   - Real-time validation feedback
4. Notes field (optional)

### Color Scheme:
- Primary: Red/Orange (rgb: 0.90, 0.30, 0.30)
- Cash: Green
- Bank: Blue
- Credit Card: Purple

## Data Models

### ExpenseTransaction
```swift
struct ExpenseTransaction: Identifiable {
    let id: String               // Document ID
    let category: String         // Expense category
    let totalAmount: Double      // Total expense amount
    let cashAmount: Double       // Amount paid via cash
    let bankAmount: Double       // Amount paid via bank
    let creditCardAmount: Double // Amount paid via credit card
    let notes: String            // Optional notes
    let date: Date               // Transaction date
}
```

## Firebase Collections

### ExpenseCategories
```
ExpenseCategories/
  {documentId}/
    - category: String (e.g., "Office Supplies", "Travel", "Marketing")
```

### ExpenseTransactions
```
ExpenseTransactions/
  {documentId}/
    - category: String
    - totalAmount: Double
    - paymentSplit: Map
      - cash: Double
      - bank: Double
      - creditCard: Double
    - notes: String
    - date: Timestamp
    - createdAt: Timestamp
```

### Balances
```
Balances/
  cash/
    - amount: Double
    - updatedAt: Timestamp
  
  bank/
    - amount: Double
    - updatedAt: Timestamp
  
  creditCard/
    - amount: Double
    - updatedAt: Timestamp
```

## Integration

### Quick Actions Button:
```swift
QuickActionButton(
    title: "Add Expense",
    icon: "minus.circle",
    color: Color(red: 0.90, green: 0.30, blue: 0.30),
    action: {
        showingAddExpenseDialog = true
    }
)
```

### Dialog Presentation:
```swift
#if os(iOS)
.fullScreenCover(isPresented: $showingAddExpenseDialog) {
    AddExpenseDialog(isPresented: $showingAddExpenseDialog, onDismiss: nil)
}
#else
.sheet(isPresented: $showingAddExpenseDialog) {
    AddExpenseDialog(isPresented: $showingAddExpenseDialog, onDismiss: nil)
}
#endif
```

## Testing Checklist
- [ ] Open dialog from Quick Actions
- [ ] Search and select category
- [ ] Add new category from dropdown
- [ ] Enter total amount
- [ ] Split payment across multiple methods
- [ ] Verify validation (split must match total)
- [ ] Add optional notes
- [ ] Save expense
- [ ] Verify loading overlay appears
- [ ] Verify success alert
- [ ] Verify form clears after success
- [ ] Check Balances collection updated correctly
- [ ] Check ExpenseTransactions document created
- [ ] View transaction history
- [ ] Test error handling (disconnect internet)
- [ ] Test on both iOS and macOS

## Files Modified
1. **Created**: `Aromex/AddExpenseDialog.swift` (new file, ~1100 lines)
2. **Modified**: `Aromex/ContentView.swift` (added state and presentation modifiers)

## Date Implemented
October 12, 2025

