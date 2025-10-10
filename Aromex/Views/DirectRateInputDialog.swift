import SwiftUI
import FirebaseFirestore

struct DirectRateInputDialog: View {
    let givingCurrency: Currency
    let receivingCurrency: Currency
    let onRateProvided: (Double) -> Void
    let onCancel: () -> Void
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @EnvironmentObject var currencyManager: CurrencyManager
    
    @State private var exchangeRate: String = ""
    @State private var rateError: String = ""
    @State private var isSaving: Bool = false
    
    // Theme colors
    let mainColor = Color(red: 0.23, green: 0.28, blue: 0.42)
    let sectionBg = Color.white
    
    private var shouldUseVerticalLayout: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }
    
    private var dialogWidth: CGFloat {
        #if os(macOS)
        return 500
        #else
        if horizontalSizeClass == .compact {
            return UIScreen.main.bounds.width - 40
        } else {
            return min(500, UIScreen.main.bounds.width - 80)
        }
        #endif
    }
    
    private var isRateValid: Bool {
        guard let rate = Double(exchangeRate.trimmingCharacters(in: .whitespaces)) else { return false }
        return rate > 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Title Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                    
                    Text("Direct Exchange Rate Required")
                        .font(.system(size: shouldUseVerticalLayout ? 20 : 24, weight: .bold, design: .serif))
                        .foregroundColor(mainColor)
                }
                
                Text("Please provide the direct exchange rate between these currencies")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Currency Info
            VStack(alignment: .leading, spacing: 16) {
                Text("Currency Exchange")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(mainColor)
                
                HStack(spacing: 16) {
                    // From Currency
                    VStack(spacing: 8) {
                        Text("From")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 6) {
                            Text(givingCurrency.symbol)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text(givingCurrency.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                    
                    // To Currency
                    VStack(spacing: 8) {
                        Text("To")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 6) {
                            Text(receivingCurrency.symbol)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text(receivingCurrency.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            // Rate Input Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Direct Exchange Rate")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(mainColor)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        // Left side - constant
                        HStack(spacing: 4) {
                            Text("1")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                            Text(givingCurrency.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                        
                        // Equals sign
                        Text("=")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        // Right side - editable
                        HStack(spacing: 8) {
                            TextField("0.00", text: $exchangeRate)
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            
                            Text(receivingCurrency.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(sectionBg)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(rateError.isEmpty ? Color.gray.opacity(0.15) : Color.red, lineWidth: 1.2)
                        )
                    }
                    
                    if !rateError.isEmpty {
                        Text(rateError)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.red)
                    }
                    
                    Text("Enter the current direct rate from \(givingCurrency.name) to \(receivingCurrency.name)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
            
            // Note Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    
                    Text("This rate will be saved for future use")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.blue)
                }
                
                Text("We'll store this direct exchange rate and use it for all future transactions between \(givingCurrency.name) and \(receivingCurrency.name). You can update it later if needed.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
            
            // Action Buttons
            if shouldUseVerticalLayout {
                VStack(spacing: 12) {
                    Button(action: saveAndProceed) {
                        Text(isSaving ? "Saving..." : "Save & Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(isRateValid && !isSaving ? mainColor : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(!isRateValid || isSaving)
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: onCancel) {
                        Text("Cancel Transaction")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                            .opacity(isSaving ? 0.6 : 1)
                    }
                    .disabled(isSaving)
                    .buttonStyle(PlainButtonStyle())
                }
            } else {
                HStack(spacing: 16) {
                    Spacer()
                    
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 100, height: 44)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                            .opacity(isSaving ? 0.6 : 1)
                    }
                    .disabled(isSaving)
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: saveAndProceed) {
                        Text(isSaving ? "Saving..." : "Save & Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 140, height: 44)
                            .background(isRateValid && !isSaving ? mainColor : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(!isRateValid || isSaving)
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(sectionBg)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 8)
        )
        .frame(width: dialogWidth)
    }
    
    private func saveAndProceed() {
        rateError = ""
        
        guard let rate = Double(exchangeRate.trimmingCharacters(in: .whitespaces)) else {
            rateError = "Please enter a valid number"
            return
        }
        
        guard rate > 0 else {
            rateError = "Exchange rate must be greater than 0"
            return
        }
        
        isSaving = true
        
        Task {
            do {
                try await currencyManager.saveDirectExchangeRate(
                    from: givingCurrency.name,
                    to: receivingCurrency.name,
                    rate: rate
                )
                
                DispatchQueue.main.async {
                    self.onRateProvided(rate)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.rateError = "Failed to save rate. Please try again."
                }
            }
        }
    }
}
