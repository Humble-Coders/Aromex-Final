import SwiftUI
import FirebaseFirestore

struct AddCurrencyDialog: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    
    @State private var currencyName: String = ""
    @State private var currencySymbol: String = ""
    @State private var isAdding: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Add New Currency")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Enter the currency details")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Form fields
            VStack(spacing: 20) {
                // Currency Name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Currency Code")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    TextField("e.g., USD, INR, EUR", text: $currencyName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.08))
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        #if os(iOS)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        #endif
                }
                
                // Currency Symbol field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Currency Symbol")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    TextField("e.g., $, ₹, €", text: $currencySymbol)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.08))
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        #if os(iOS)
                        .disableAutocorrection(true)
                        #endif
                }
            }
            .padding(.horizontal, 20)
            
            // Error message
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    dismiss()
                }) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    Task {
                        await addCurrency()
                    }
                }) {
                    HStack(spacing: 8) {
                        if isAdding {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        
                        Text(isAdding ? "Adding..." : "Add Currency")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.25, green: 0.33, blue: 0.54),
                                        Color(red: 0.20, green: 0.28, blue: 0.48)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(currencyName.isEmpty || currencySymbol.isEmpty || isAdding)
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 30)
        .frame(minWidth: 400, minHeight: 350)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
    
    private func addCurrency() async {
        // Trim whitespace
        let trimmedName = currencyName.trimmingCharacters(in: .whitespaces).uppercased()
        let trimmedSymbol = currencySymbol.trimmingCharacters(in: .whitespaces)
        
        // Validate
        guard !trimmedName.isEmpty, !trimmedSymbol.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        
        isAdding = true
        errorMessage = ""
        
        do {
            let currency = Currency(
                name: trimmedName,
                symbol: trimmedSymbol,
                exchangeRate: 1.0 // Default value, not used for regular transactions
            )
            
            try await currencyManager.addCurrency(currency)
            
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to add currency: \(error.localizedDescription)"
                isAdding = false
            }
        }
    }
}

