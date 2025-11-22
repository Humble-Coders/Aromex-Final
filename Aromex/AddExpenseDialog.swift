//
//  AddExpenseDialog.swift
//  Aromex
//
//  Created for Quick Actions - Add Expense Feature
//

import SwiftUI
import FirebaseFirestore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct AddExpenseDialog: View {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) var colorScheme
    
    // Category dropdown state
    @State private var categorySearchText = ""
    @State private var selectedCategory = ""
    @State private var showingCategoryDropdown = false
    @State private var categoryButtonFrame: CGRect = .zero
    @State private var categories: [String] = []
    @State private var isLoadingCategories = false
    @FocusState private var isCategoryFocused: Bool
    @State private var categoryInternalSearchText = ""
    
    // Amount field
    @State private var totalAmount = ""
    @FocusState private var isAmountFocused: Bool
    
    // Payment split fields
    @State private var cashAmount = ""
    @State private var bankAmount = ""
    @State private var creditCardAmount = ""
    @FocusState private var isCashFocused: Bool
    @FocusState private var isBankFocused: Bool
    @FocusState private var isCreditCardFocused: Bool
    
    // Notes field
    @State private var notes = ""
    @FocusState private var isNotesFocused: Bool
    
    // State management
    @State private var isSaving = false
    @State private var showSaveSuccessAlert = false
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""
    @State private var showingHistory = false
    @State private var isAddingCategory = false
    
    // Transaction history
    @State private var expenseTransactions: [ExpenseTransaction] = []
    @State private var isLoadingHistory = false
    @State private var isDeletingTransaction = false
    @State private var showDeleteConfirmation = false
    @State private var transactionToDelete: ExpenseTransaction?
    @State private var showDeleteSuccessAlert = false
    @State private var showDeleteErrorAlert = false
    @State private var deleteErrorMessage = ""
    
    // Validation
    private var isFormValid: Bool {
        let hasCategory = !selectedCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let totalAmountValue = Double(totalAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let hasTotalAmount = totalAmountValue > 0
        
        let cashValue = Double(cashAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let bankValue = Double(bankAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let creditCardValue = Double(creditCardAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let splitTotal = cashValue + bankValue + creditCardValue
        
        let splitsMatchTotal = abs(splitTotal - totalAmountValue) < 0.01 // Allow for floating point precision
        
        return hasCategory && hasTotalAmount && splitsMatchTotal && splitTotal > 0
    }
    
    private var splitTotalAmount: Double {
        let cashValue = Double(cashAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let bankValue = Double(bankAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let creditCardValue = Double(creditCardAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return cashValue + bankValue + creditCardValue
    }
    
    private var totalAmountValue: Double {
        return Double(totalAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
    
    var body: some View {
        ZStack {
            #if os(iOS)
            iOSView
            #else
            macOSView
            #endif
            
            // Loading overlay
            if isSaving || isDeletingTransaction {
                loadingOverlay
            }
        }
        .alert("Success", isPresented: $showSaveSuccessAlert) {
            Button("OK") {
                clearForm()
            }
        } message: {
            Text("Expense has been recorded successfully!")
        }
        .alert("Error", isPresented: $showSaveErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .alert("Delete Transaction", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                transactionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let transaction = transactionToDelete {
                    Task {
                        await deleteExpenseTransaction(transaction)
                    }
                }
            }
        } message: {
            if let transaction = transactionToDelete {
                Text("Are you sure you want to reverse and delete this expense transaction?\n\nCategory: \(transaction.category)\nAmount: $\(String(format: "%.2f", transaction.totalAmount))\n\nThis will restore the balances and permanently delete the transaction.")
            }
        }
        .alert("Success", isPresented: $showDeleteSuccessAlert) {
            Button("OK") {
                // Reload history after successful deletion
                loadExpenseHistory()
            }
        } message: {
            Text("Transaction has been reversed and deleted successfully!")
        }
        .alert("Error", isPresented: $showDeleteErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage)
        }
        .onAppear {
            fetchCategories()
        }
        .onChange(of: selectedCategory) { newValue in
            if !newValue.isEmpty {
                categorySearchText = newValue
                categoryInternalSearchText = newValue
            }
        }
    }
    
    // MARK: - iOS View
    private var iOSView: some View {
        NavigationView {
            Group {
                if showingHistory {
                    ExpenseHistoryInlineView(
                        transactions: expenseTransactions,
                        isLoading: isLoadingHistory,
                        onBack: {
                            showingHistory = false
                        },
                        onDelete: { transaction in
                            transactionToDelete = transaction
                            showDeleteConfirmation = true
                        }
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Add Expense")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                
                                Text("Record a new expense transaction")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                            
                            // Form
                            VStack(spacing: 20) {
                                categoryField
                                amountField
                                paymentSplitSection
                                notesField
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    if showingHistory {
                        Button("Back") {
                            showingHistory = false
                        }
                    } else {
                        Button("Cancel") {
                            isPresented = false
                            onDismiss?()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !showingHistory {
                        HStack(spacing: 16) {
                            Button(action: {
                                loadExpenseHistory()
                            }) {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            
                            Button("Save") {
                                Task {
                                    await saveExpense()
                                }
                            }
                            .fontWeight(.semibold)
                            .disabled(!isFormValid)
                        }
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    if showingHistory {
                        Button("Back") {
                            showingHistory = false
                        }
                    } else {
                        Button("Cancel") {
                            isPresented = false
                            onDismiss?()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !showingHistory {
                        HStack(spacing: 16) {
                            Button(action: {
                                loadExpenseHistory()
                            }) {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            
                            Button("Save") {
                                Task {
                                    await saveExpense()
                                }
                            }
                            .fontWeight(.semibold)
                            .disabled(!isFormValid)
                        }
                    }
                }
                #endif
            }
        }
    }
    
    // MARK: - macOS View
    private var macOSView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(red: 0.90, green: 0.30, blue: 0.30))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(showingHistory ? "Expense History" : "Add Expense")
                        .font(.system(size: 24, weight: .bold))
                }
                
                Spacer()
                
                if !showingHistory {
                    Button(action: {
                        loadExpenseHistory()
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Button(action: {
                    if showingHistory {
                        showingHistory = false
                    } else {
                        isPresented = false
                        onDismiss?()
                    }
                }) {
                    Image(systemName: showingHistory ? "arrow.left" : "xmark")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .padding(.bottom, 28)
            
            Divider()
            
            // Content
            if showingHistory {
                ExpenseHistoryInlineView(
                    transactions: expenseTransactions,
                    isLoading: isLoadingHistory,
                    onBack: {
                        showingHistory = false
                    },
                    onDelete: { transaction in
                        transactionToDelete = transaction
                        showDeleteConfirmation = true
                    }
                )
            } else {
                // Form
                ScrollView {
                    VStack(spacing: 24) {
                        categoryField
                        amountField
                        paymentSplitSection
                        notesField
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 28)
                }
                
                Divider()
                
                // Footer buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        isPresented = false
                        onDismiss?()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            await saveExpense()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark")
                            Text("Save Expense")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.90, green: 0.30, blue: 0.30))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.6)
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 20)
            }
        }
        .frame(width: 600, height: 700)
    }
    
    // MARK: - Form Fields
    
    private var categoryField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Category")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("*")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            
            CategoryDropdownButton(
                searchText: $categorySearchText,
                selectedCategory: $selectedCategory,
                isOpen: $showingCategoryDropdown,
                buttonFrame: $categoryButtonFrame,
                isFocused: $isCategoryFocused,
                internalSearchText: $categoryInternalSearchText,
                isLoading: isLoadingCategories,
                colorScheme: colorScheme
            )
            
            // Inline dropdown for both iOS and macOS
            if showingCategoryDropdown {
                CategoryDropdownOverlay(
                    isOpen: $showingCategoryDropdown,
                    selectedCategory: $selectedCategory,
                    searchText: $categorySearchText,
                    internalSearchText: $categoryInternalSearchText,
                    categories: categories,
                    buttonFrame: categoryButtonFrame,
                    onAddCategory: { categoryName in
                        addNewCategory(categoryName)
                    },
                    onRenameCategory: { oldName, newName in
                        renameCategory(oldName: oldName, newName: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
    
    private var amountField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Total Amount")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("*")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            
            HStack {
                Text("$")
                    .foregroundColor(.secondary)
                TextField("0.00", text: $totalAmount)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 18, weight: .medium))
                    .focused($isAmountFocused)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            )
        }
    }
    
    private var paymentSplitSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Payment Split")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("*")
                    .foregroundColor(.red)
                    .font(.subheadline)
                
                Spacer()
                
                if splitTotalAmount > 0 {
                    let difference = totalAmountValue - splitTotalAmount
                    if abs(difference) > 0.01 {
                        Text(difference > 0 ? "Remaining: $\(String(format: "%.2f", difference))" : "Over by: $\(String(format: "%.2f", abs(difference)))")
                            .font(.caption)
                            .foregroundColor(difference > 0 ? .orange : .red)
                    } else {
                        Text("✓ Matches total")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            VStack(spacing: 12) {
                paymentField(title: "Cash", amount: $cashAmount, isFocused: $isCashFocused, color: .green)
                paymentField(title: "Bank", amount: $bankAmount, isFocused: $isBankFocused, color: .blue)
                paymentField(title: "Credit Card", amount: $creditCardAmount, isFocused: $isCreditCardFocused, color: .purple)
            }
        }
    }
    
    private func paymentField(title: String, amount: Binding<String>, isFocused: FocusState<Bool>.Binding, color: Color) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(width: 120, alignment: .leading)
            
            HStack {
                Text("$")
                    .foregroundColor(.secondary)
                TextField("0.00", text: amount)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 16))
                    .focused(isFocused)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.regularMaterial)
            )
        }
    }
    
    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes (Optional)")
                .font(.subheadline)
                .fontWeight(.medium)
            
            TextField("Add notes about this expense", text: $notes, axis: .vertical)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 16))
                .focused($isNotesFocused)
                .lineLimit(3...6)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                )
        }
    }
    
    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text(isAddingCategory ? "Adding category..." : (isDeletingTransaction ? "Reversing transaction..." : "Saving expense..."))
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
    }
    
    // MARK: - Firebase Operations
    
    private func fetchCategories() {
        isLoadingCategories = true
        let db = Firestore.firestore()
        
        db.collection("ExpenseCategories").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                self.isLoadingCategories = false
                
                if let error = error {
                    print("Error fetching expense categories: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No documents found in ExpenseCategories collection")
                    return
                }
                
                let categoryNames = documents.compactMap { document in
                    document.data()["category"] as? String
                }
                
                self.categories = categoryNames.sorted()
            }
        }
    }
    
    private func addNewCategory(_ categoryName: String) {
        isAddingCategory = true
        isSaving = true
        
        let db = Firestore.firestore()
        
        db.collection("ExpenseCategories").addDocument(data: ["category": categoryName]) { error in
            DispatchQueue.main.async {
                self.isAddingCategory = false
                self.isSaving = false
                
                if let error = error {
                    print("Error adding category: \(error)")
                    return
                }
                
                // Add to local array
                self.categories.append(categoryName)
                self.categories.sort()
                
                // Select the new category
                self.selectedCategory = categoryName
                self.categorySearchText = categoryName
            }
        }
    }
    
    private func renameCategory(oldName: String, newName: String) {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty, trimmedOld != trimmedNew else { return }
        
        let db = Firestore.firestore()
        db.collection("ExpenseCategories")
            .whereField("category", isEqualTo: trimmedOld)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error finding category to rename: \(error)")
                    return
                }
                guard let doc = snapshot?.documents.first else {
                    print("Category document not found for name: \(trimmedOld)")
                    return
                }
                doc.reference.setData(["category": trimmedNew], merge: true) { setError in
                    if let setError = setError {
                        print("Error renaming category: \(setError)")
                        return
                    }
                    DispatchQueue.main.async {
                        // Update local state
                        if let idx = self.categories.firstIndex(where: { $0.caseInsensitiveCompare(trimmedOld) == .orderedSame }) {
                            self.categories[idx] = trimmedNew
                            self.categories.sort()
                        }
                        if self.selectedCategory == trimmedOld {
                            self.selectedCategory = trimmedNew
                            self.categorySearchText = trimmedNew
                        }
                    }
                }
            }
    }
    
    private func saveExpense() async {
        isSaving = true
        
        do {
            let db = Firestore.firestore()
            let batch = db.batch()
            let expenseDate = Date()
            
            let cashValue = Double(cashAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let bankValue = Double(bankAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let creditCardValue = Double(creditCardAmount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let totalValue = totalAmountValue
            
            // Update cash balance
            if cashValue > 0 {
                let cashDocRef = db.collection("Balances").document("cash")
                let cashDoc = try await cashDocRef.getDocument()
                
                if cashDoc.exists {
                    let cashData = cashDoc.data() ?? [:]
                    let currentCashBalance = cashData["amount"] as? Double ?? 0.0
                    let newCashBalance = currentCashBalance - cashValue
                    
                    batch.updateData([
                        "amount": newCashBalance,
                        "updatedAt": expenseDate
                    ], forDocument: cashDocRef)
                }
            }
            
            // Update bank balance
            if bankValue > 0 {
                let bankDocRef = db.collection("Balances").document("bank")
                let bankDoc = try await bankDocRef.getDocument()
                
                if bankDoc.exists {
                    let bankData = bankDoc.data() ?? [:]
                    let currentBankBalance = bankData["amount"] as? Double ?? 0.0
                    let newBankBalance = currentBankBalance - bankValue
                    
                    batch.updateData([
                        "amount": newBankBalance,
                        "updatedAt": expenseDate
                    ], forDocument: bankDocRef)
                }
            }
            
            // Update credit card balance
            if creditCardValue > 0 {
                let creditCardDocRef = db.collection("Balances").document("creditCard")
                let creditCardDoc = try await creditCardDocRef.getDocument()
                
                if creditCardDoc.exists {
                    let creditCardData = creditCardDoc.data() ?? [:]
                    let currentCreditCardBalance = creditCardData["amount"] as? Double ?? 0.0
                    let newCreditCardBalance = currentCreditCardBalance - creditCardValue
                    
                    batch.updateData([
                        "amount": newCreditCardBalance,
                        "updatedAt": expenseDate
                    ], forDocument: creditCardDocRef)
                }
            }
            
            // Create expense transaction document
            let expenseDocRef = db.collection("ExpenseTransactions").document()
            let expenseData: [String: Any] = [
                "category": selectedCategory,
                "totalAmount": totalValue,
                "paymentSplit": [
                    "cash": cashValue,
                    "bank": bankValue,
                    "creditCard": creditCardValue
                ],
                "notes": notes,
                "date": expenseDate,
                "createdAt": expenseDate
            ]
            
            batch.setData(expenseData, forDocument: expenseDocRef)
            
            // Commit the batch
            try await batch.commit()
            
            await MainActor.run {
                isSaving = false
                showSaveSuccessAlert = true
            }
            
        } catch {
            await MainActor.run {
                isSaving = false
                saveErrorMessage = "Failed to save expense: \(error.localizedDescription)"
                showSaveErrorAlert = true
            }
        }
    }
    
    private func loadExpenseHistory() {
        isLoadingHistory = true
        showingHistory = true
        
        let db = Firestore.firestore()
        db.collection("ExpenseTransactions")
            .order(by: "date", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    self.isLoadingHistory = false
                    
                    if let error = error {
                        print("Error fetching expense history: \(error)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("No expense transactions found")
                        return
                    }
                    
                    self.expenseTransactions = documents.compactMap { doc -> ExpenseTransaction? in
                        let data = doc.data()
                        guard let category = data["category"] as? String,
                              let totalAmount = data["totalAmount"] as? Double,
                              let date = (data["date"] as? Timestamp)?.dateValue(),
                              let paymentSplit = data["paymentSplit"] as? [String: Double] else {
                            return nil
                        }
                        
                        let notes = data["notes"] as? String ?? ""
                        let cash = paymentSplit["cash"] ?? 0.0
                        let bank = paymentSplit["bank"] ?? 0.0
                        let creditCard = paymentSplit["creditCard"] ?? 0.0
                        
                        return ExpenseTransaction(
                            id: doc.documentID,
                            category: category,
                            totalAmount: totalAmount,
                            cashAmount: cash,
                            bankAmount: bank,
                            creditCardAmount: creditCard,
                            notes: notes,
                            date: date
                        )
                    }
                    
                    // Sort by date descending (most recent first)
                    self.expenseTransactions.sort { $0.date > $1.date }
                }
            }
    }
    
    private func clearForm() {
        selectedCategory = ""
        categorySearchText = ""
        totalAmount = ""
        cashAmount = ""
        bankAmount = ""
        creditCardAmount = ""
        notes = ""
    }
    
    private func deleteExpenseTransaction(_ transaction: ExpenseTransaction) async {
        isDeletingTransaction = true
        
        do {
            let db = Firestore.firestore()
            let batch = db.batch()
            let reverseDate = Date()
            
            // Reverse cash balance (add back the amount that was subtracted)
            if transaction.cashAmount > 0 {
                let cashDocRef = db.collection("Balances").document("cash")
                let cashDoc = try await cashDocRef.getDocument()
                
                if cashDoc.exists {
                    let cashData = cashDoc.data() ?? [:]
                    let currentCashBalance = cashData["amount"] as? Double ?? 0.0
                    let newCashBalance = currentCashBalance + transaction.cashAmount
                    
                    batch.updateData([
                        "amount": newCashBalance,
                        "updatedAt": reverseDate
                    ], forDocument: cashDocRef)
                } else {
                    // If document doesn't exist, create it with the reversed amount
                    batch.setData([
                        "amount": transaction.cashAmount,
                        "updatedAt": reverseDate
                    ], forDocument: cashDocRef)
                }
            }
            
            // Reverse bank balance (add back the amount that was subtracted)
            if transaction.bankAmount > 0 {
                let bankDocRef = db.collection("Balances").document("bank")
                let bankDoc = try await bankDocRef.getDocument()
                
                if bankDoc.exists {
                    let bankData = bankDoc.data() ?? [:]
                    let currentBankBalance = bankData["amount"] as? Double ?? 0.0
                    let newBankBalance = currentBankBalance + transaction.bankAmount
                    
                    batch.updateData([
                        "amount": newBankBalance,
                        "updatedAt": reverseDate
                    ], forDocument: bankDocRef)
                } else {
                    // If document doesn't exist, create it with the reversed amount
                    batch.setData([
                        "amount": transaction.bankAmount,
                        "updatedAt": reverseDate
                    ], forDocument: bankDocRef)
                }
            }
            
            // Reverse credit card balance (add back the amount that was subtracted)
            if transaction.creditCardAmount > 0 {
                let creditCardDocRef = db.collection("Balances").document("creditCard")
                let creditCardDoc = try await creditCardDocRef.getDocument()
                
                if creditCardDoc.exists {
                    let creditCardData = creditCardDoc.data() ?? [:]
                    let currentCreditCardBalance = creditCardData["amount"] as? Double ?? 0.0
                    let newCreditCardBalance = currentCreditCardBalance + transaction.creditCardAmount
                    
                    batch.updateData([
                        "amount": newCreditCardBalance,
                        "updatedAt": reverseDate
                    ], forDocument: creditCardDocRef)
                } else {
                    // If document doesn't exist, create it with the reversed amount
                    batch.setData([
                        "amount": transaction.creditCardAmount,
                        "updatedAt": reverseDate
                    ], forDocument: creditCardDocRef)
                }
            }
            
            // Delete the expense transaction document
            let expenseDocRef = db.collection("ExpenseTransactions").document(transaction.id)
            batch.deleteDocument(expenseDocRef)
            
            // Commit all changes atomically
            try await batch.commit()
            
            await MainActor.run {
                isDeletingTransaction = false
                transactionToDelete = nil
                showDeleteSuccessAlert = true
            }
            
        } catch {
            await MainActor.run {
                isDeletingTransaction = false
                deleteErrorMessage = "Failed to reverse transaction: \(error.localizedDescription)"
                showDeleteErrorAlert = true
            }
        }
    }
}

// MARK: - Expense Transaction Model
struct ExpenseTransaction: Identifiable {
    let id: String
    let category: String
    let totalAmount: Double
    let cashAmount: Double
    let bankAmount: Double
    let creditCardAmount: Double
    let notes: String
    let date: Date
}

// MARK: - Expense History View
struct ExpenseHistoryView: View {
    let transactions: [ExpenseTransaction]
    let isLoading: Bool
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading history...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if transactions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No expense transactions yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(transactions) { transaction in
                            ExpenseTransactionRow(
                                transaction: transaction,
                                onDelete: {
                                    // This view is only used in sheet presentation, delete not needed here
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Expense History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
}

// MARK: - Expense History Inline View
struct ExpenseHistoryInlineView: View {
    let transactions: [ExpenseTransaction]
    let isLoading: Bool
    let onBack: () -> Void
    let onDelete: (ExpenseTransaction) -> Void
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading history...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if transactions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No expense transactions yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(iOS)
                List {
                    ForEach(transactions) { transaction in
                        ExpenseTransactionRow(
                            transaction: transaction,
                            onDelete: {
                                onDelete(transaction)
                            }
                        )
                    }
                }
                #else
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(transactions) { transaction in
                            ExpenseTransactionRow(
                                transaction: transaction,
                                onDelete: {
                                    onDelete(transaction)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, 20)
                }
                #endif
            }
        }
    }
}

// MARK: - Expense Transaction Row
struct ExpenseTransactionRow: View {
    let transaction: ExpenseTransaction
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.category)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(transaction.date, style: .date)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("$\(String(format: "%.2f", transaction.totalAmount))")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: 0.90, green: 0.30, blue: 0.30))
                    
                    Text("Total Amount")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            // Payment Split Section
            if transaction.cashAmount > 0 || transaction.bankAmount > 0 || transaction.creditCardAmount > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Payment Split")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    HStack(spacing: 16) {
                        if transaction.cashAmount > 0 {
                            paymentMethodBadge(
                                label: "Cash",
                                amount: transaction.cashAmount,
                                color: .green,
                                icon: "dollarsign.circle.fill"
                            )
                        }
                        
                        if transaction.bankAmount > 0 {
                            paymentMethodBadge(
                                label: "Bank",
                                amount: transaction.bankAmount,
                                color: .blue,
                                icon: "building.columns.fill"
                            )
                        }
                        
                        if transaction.creditCardAmount > 0 {
                            paymentMethodBadge(
                                label: "Credit Card",
                                amount: transaction.creditCardAmount,
                                color: .purple,
                                icon: "creditcard.fill"
                            )
                        }
                    }
                }
            }
            
            // Notes Section
            if !transaction.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(transaction.notes)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Delete Button
            HStack {
                Spacer()
                Button(action: onDelete) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                        Text("Delete Transaction")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func paymentMethodBadge(label: String, amount: Double, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("$\(String(format: "%.2f", amount))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Category Dropdown Button (matching StorageLocationDropdownField pattern)
struct CategoryDropdownButton: View {
    @Binding var searchText: String
    @Binding var selectedCategory: String
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    var isFocused: FocusState<Bool>.Binding
    @Binding var internalSearchText: String
    let isLoading: Bool
    let colorScheme: ColorScheme
    
    var body: some View {
        ZStack {
            // Main TextField with padding for the button
            TextField("Choose a category", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 18, weight: .medium))
                .focused(isFocused)
                .padding(.horizontal, 20)
                .padding(.trailing, 50) // Extra padding for dropdown button area
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                )
                .submitLabel(.done)
                .onSubmit {
                    isFocused.wrappedValue = false
                }
                .onChange(of: searchText) { newValue in
                    if !newValue.isEmpty && !isOpen && newValue != selectedCategory {
                        isOpen = true
                    }
                    internalSearchText = newValue
                }
            
            // Separate button positioned on the right
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 20)
                } else {
                    Button(action: {
                        print("Category dropdown button clicked, isOpen before: \(isOpen)")
                        withAnimation {
                            isOpen.toggle()
                        }
                        print("Category dropdown button clicked, isOpen after: \(isOpen)")
                        if isOpen {
                            isFocused.wrappedValue = false
                        }
                    }) {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .frame(width: 40, height: 40) // Larger clickable area
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { isHovering in
                        #if os(macOS)
                        if isHovering {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                        #endif
                    }
                    .padding(.trailing, 10)
                }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame = geometry.frame(in: .global)
                        print("Category button frame captured: \(buttonFrame)")
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        buttonFrame = newFrame
                    }
            }
        )
        .onTapGesture {
            withAnimation {
                isOpen.toggle()
            }
            if isOpen {
                isFocused.wrappedValue = false
            }
        }
        .onChange(of: searchText) { newValue in
            // Sync internal search with display text
            internalSearchText = newValue
            if !newValue.isEmpty && !isOpen && newValue != selectedCategory {
                isOpen = true
            }
        }
        .onChange(of: isOpen) { newValue in
            // Clear internal search when opening dropdown to show full list
            if newValue {
                internalSearchText = ""
            }
        }
        .onChange(of: isFocused.wrappedValue) { focused in
            print("Category field focus changed: \(focused), isOpen: \(isOpen)")
            if focused && !isOpen {
                print("Setting isOpen to true due to focus")
                isOpen = true
            }
        }
    }
}

// MARK: - Category Dropdown Overlay
struct CategoryDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedCategory: String
    @Binding var searchText: String
    @Binding var internalSearchText: String
    let categories: [String]
    let buttonFrame: CGRect
    let onAddCategory: (String) -> Void
    let onRenameCategory: (String, String) -> Void
    
    @State private var showEditNameSheet = false
    @State private var editOriginalName = ""
    @State private var editNewName = ""
    
    private var filteredCategories: [String] {
        print("CategoryDropdownOverlay - Total categories: \(categories.count), categories: \(categories)")
        print("CategoryDropdownOverlay - Internal search text: '\(internalSearchText)'")
        
        if internalSearchText.isEmpty {
            let allCategories = categories.sorted()
            print("CategoryDropdownOverlay - Showing all categories: \(allCategories)")
            return allCategories // Show all categories sorted alphabetically when no search text
        } else {
            let filtered = categories.filter { category in
                category.localizedCaseInsensitiveContains(internalSearchText)
            }.sorted()
            print("CategoryDropdownOverlay - Filtered categories: \(filtered)")
            return filtered
        }
    }
    
    private var shouldShowAddOption: Bool {
        return !internalSearchText.isEmpty && !categories.contains { $0.localizedCaseInsensitiveCompare(internalSearchText) == .orderedSame }
    }
    
    var body: some View {
        inlineDropdown
            .sheet(isPresented: $showEditNameSheet) {
                ExpenseEditNameSheet(
                    title: "Edit Category",
                    text: $editNewName,
                    onCancel: { showEditNameSheet = false },
                    onSave: { commitEdit() }
                )
            }
            .onAppear {
                print("CategoryDropdownOverlay appeared with \(categories.count) categories: \(categories)")
                print("CategoryDropdownOverlay buttonFrame: \(buttonFrame)")
            }
    }
    
    // MARK: - Inline Dropdown
    private var inlineDropdown: some View {
        VStack(spacing: 0) {
            // Add category option
            if shouldShowAddOption {
                VStack(spacing: 0) {
                    cleanCategoryRow(
                        title: "Add '\(internalSearchText)'",
                        isAddOption: true,
                        action: {
                            isOpen = false
                            onAddCategory(internalSearchText)
                        }
                    )
                    
                    // Separator after add option
                    if !filteredCategories.isEmpty {
                        Divider()
                            .background(Color.secondary.opacity(0.4))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }
                }
            }
            
            // Existing categories - always use ScrollView for consistency
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredCategories.enumerated()), id: \.element) { index, category in
                        VStack(spacing: 0) {
                            cleanCategoryRow(
                                title: category,
                                isAddOption: false,
                                action: {
                                    print("Selected category: \(category)")
                                    isOpen = false
                                    selectedCategory = category
                                    searchText = category
                                }
                            )
                            .onAppear {
                                print("Rendering category row: \(category)")
                            }
                            
                            // Subtle separator between items
                            if index < filteredCategories.count - 1 {
                                Divider()
                                    .background(Color.secondary.opacity(0.4))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: dynamicDropdownHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isOpen)
    }
    
    // MARK: - Dynamic Height Calculation
    private var dynamicDropdownHeight: CGFloat {
        let itemHeight: CGFloat = 50
        let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
        let categoryCount = filteredCategories.count
        
        if categoryCount <= 4 {
            // For small lists, calculate exact height
            let categoryHeight = CGFloat(categoryCount) * itemHeight
            let totalHeight = addOptionHeight + categoryHeight
            return min(totalHeight, 240)
        } else {
            // For larger lists, use fixed height with scroll
            return min(addOptionHeight + (4 * itemHeight), 240)
        }
    }
    
    // MARK: - Clean Category Row
    private func cleanCategoryRow(title: String, isAddOption: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            // Left tap area selects item (or adds if add-option)
            Button(action: action) {
                HStack(spacing: 12) {
                    if isAddOption {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40))
                            .font(.system(size: 16, weight: .medium))
                    }
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isAddOption ? Color(red: 0.20, green: 0.60, blue: 0.40) : .primary)
                        .fontWeight(isAddOption ? .semibold : .medium)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            
            // Checkmark (before edit button)
            if !isAddOption && selectedCategory == title {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.40))
                    .font(.system(size: 16, weight: .medium))
            }
            
            // Edit button on far right (not for add option)
            if !isAddOption {
                ExpenseEditIconButton { presentEdit(for: title) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 50)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }
    
    // MARK: - Edit Presentation
    private func presentEdit(for name: String) {
        editOriginalName = name
        editNewName = name
        showEditNameSheet = true
    }
    
    private func commitEdit() {
        let oldName = editOriginalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = editNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldName.isEmpty, !newName.isEmpty, oldName != newName else { return }
        onRenameCategory(oldName, newName)
        showEditNameSheet = false
    }
}

// MARK: - Expense Edit Icon Button
struct ExpenseEditIconButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .foregroundColor(.primary)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Edit item")
        .allowsHitTesting(true)
    }
}

// MARK: - Expense Edit Name Sheet
struct ExpenseEditNameSheet: View {
    let title: String
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void
    
    var body: some View {
        #if os(iOS)
        content
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        #else
        content
            .frame(width: 360)
        #endif
    }
    
    private var content: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                TextField("New name", text: $text)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.regularMaterial)
                    )
            }
            
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: onSave) {
                    Text("Save")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(red: 0.25, green: 0.33, blue: 0.54))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(24)
    }
}

// Helper for frame detection
struct ViewFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

