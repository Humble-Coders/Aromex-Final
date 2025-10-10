import SwiftUI
import FirebaseFirestore

struct ExchangeRatesDialog: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @EnvironmentObject var currencyManager: CurrencyManager
    
    @State private var updatedRates: [String: String] = [:]
    @State private var isUpdating: Bool = false
    @State private var updateError: String = ""
    @State private var successMessage: String = ""
    
    // Theme colors
    let mainColor = Color(red: 0.23, green: 0.28, blue: 0.42)
    let sectionBg = Color.white
    let fieldCornerRadius: CGFloat = 10
    let fieldHeight: CGFloat = 50
    
    // Responsive properties
    private var shouldUseVerticalLayout: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }
    
    private var dialogWidth: CGFloat {
        #if os(macOS)
        return 800
        #else
        if horizontalSizeClass == .compact {
            return UIScreen.main.bounds.width - 40
        } else {
            return min(800, UIScreen.main.bounds.width - 80)
        }
        #endif
    }
    
    private var dialogHeight: CGFloat {
        #if os(macOS)
        return 700
        #else
        if shouldUseVerticalLayout {
            return min(UIScreen.main.bounds.height - 100, 800)
        } else {
            return min(700, UIScreen.main.bounds.height - 100)
        }
        #endif
    }
    
    private var horizontalPadding: CGFloat {
        #if os(macOS)
        return 32
        #else
        return shouldUseVerticalLayout ? 20 : 24
        #endif
    }
    
    // Get currency pairs ordered by bigger to smaller
    private var currencyPairs: [(bigger: Currency, smaller: Currency)] {
        var pairs: [(bigger: Currency, smaller: Currency)] = []
        let allCurrencies = currencyManager.allCurrencies
        
        for i in 0..<allCurrencies.count {
            for j in (i+1)..<allCurrencies.count {
                let currency1 = allCurrencies[i]
                let currency2 = allCurrencies[j]
                
                // Determine which is bigger (lower exchange rate = higher value)
                let biggerCurrency = currency1.exchangeRate <= currency2.exchangeRate ? currency1 : currency2
                let smallerCurrency = currency1.exchangeRate > currency2.exchangeRate ? currency1 : currency2
                
                pairs.append((bigger: biggerCurrency, smaller: smallerCurrency))
            }
        }
        
        return pairs.sorted { $0.bigger.name < $1.bigger.name }
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("Direct Exchange Rates")
                    .font(.system(size: shouldUseVerticalLayout ? 24 : 28, weight: .bold, design: .serif))
                    .foregroundColor(mainColor)
                    .padding(.top, shouldUseVerticalLayout ? 16 : 24)
                    .padding(.leading, horizontalPadding)
                    .padding(.bottom, 16)
                
                // Description
                Text("Edit direct exchange rates between currency pairs. Enter the rates and click update to save to Firebase.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 24)
                
                VStack(spacing: 24) {
                    // Currency Pairs
                    ForEach(currencyPairs.indices, id: \.self) { index in
                        let pair = currencyPairs[index]
                        currencyPairView(bigger: pair.bigger, smaller: pair.smaller)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                
                // Status Messages
                if !updateError.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(updateError)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 16)
                }
                
                if !successMessage.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text(successMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 16)
                }
                
                // Action Buttons
                actionButtons
                    .padding(.top, 32)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 24)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(sectionBg)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 8)
        )
        .frame(width: dialogWidth, height: dialogHeight)
        .onAppear {
            initializeRates()
        }
    }
    
    @ViewBuilder
    private func currencyPairView(bigger: Currency, smaller: Currency) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Pair Header
            HStack {
                Text("\(bigger.name) ↔ \(smaller.name)")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundColor(mainColor)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Text(bigger.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(6)
                    
                    Text(smaller.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .cornerRadius(6)
                }
            }
            
            // Bigger to Smaller Rate
            VStack(alignment: .leading, spacing: 8) {
                Text("\(bigger.name) to \(smaller.name)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    Text("1 \(bigger.name) =")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 100, alignment: .leading)
                    
                    TextField("Rate", text: Binding(
                        get: {
                            let rateKey = "\(bigger.name)_to_\(smaller.name)"
                            return updatedRates[rateKey] ?? ""
                        },
                        set: { newValue in
                            let rateKey = "\(bigger.name)_to_\(smaller.name)"
                            updatedRates[rateKey] = newValue
                        }
                    ))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 16)
                    .frame(height: fieldHeight)
                    .background(sectionBg)
                    .cornerRadius(fieldCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: fieldCornerRadius)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1.2)
                    )
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    
                    Text(smaller.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 60, alignment: .leading)
                }
            }
            
            // Smaller to Bigger Rate
            VStack(alignment: .leading, spacing: 8) {
                Text("\(smaller.name) to \(bigger.name)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    Text("1 \(smaller.name) =")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 100, alignment: .leading)
                    
                    TextField("Rate", text: Binding(
                        get: {
                            let rateKey = "\(smaller.name)_to_\(bigger.name)"
                            return updatedRates[rateKey] ?? ""
                        },
                        set: { newValue in
                            let rateKey = "\(smaller.name)_to_\(bigger.name)"
                            updatedRates[rateKey] = newValue
                        }
                    ))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 16)
                    .frame(height: fieldHeight)
                    .background(sectionBg)
                    .cornerRadius(fieldCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: fieldCornerRadius)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1.2)
                    )
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    
                    Text(bigger.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 60, alignment: .leading)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.systemGray6)
                .opacity(0.3)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        if shouldUseVerticalLayout {
            VStack(spacing: 12) {
                Button(action: updateRates) {
                    Text(isUpdating ? "Updating..." : "Update Rates")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(hasValidRates() && !isUpdating ? mainColor.opacity(0.97) : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(!hasValidRates() || isUpdating)
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                        .opacity(isUpdating ? 0.6 : 1)
                }
                .disabled(isUpdating)
                .buttonStyle(PlainButtonStyle())
            }
        } else {
            HStack(spacing: 16) {
                Spacer()
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .frame(width: 120, height: 44)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                        .opacity(isUpdating ? 0.6 : 1)
                }
                .disabled(isUpdating)
                .buttonStyle(PlainButtonStyle())
                
                Button(action: updateRates) {
                    Text(isUpdating ? "Updating..." : "Update Rates")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .frame(width: 140, height: 44)
                        .background(hasValidRates() && !isUpdating ? mainColor.opacity(0.97) : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(!hasValidRates() || isUpdating)
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private func initializeRates() {
        for pair in currencyPairs {
            let biggerToSmallerKey = "\(pair.bigger.name)_to_\(pair.smaller.name)"
            let smallerToBiggerKey = "\(pair.smaller.name)_to_\(pair.bigger.name)"
            
            if let rate = currencyManager.getDirectExchangeRate(from: pair.bigger.name, to: pair.smaller.name) {
                updatedRates[biggerToSmallerKey] = String(format: "%.4f", rate)
            }
            
            if let rate = currencyManager.getDirectExchangeRate(from: pair.smaller.name, to: pair.bigger.name) {
                updatedRates[smallerToBiggerKey] = String(format: "%.4f", rate)
            }
        }
    }
    
    private func hasValidRates() -> Bool {
        return !updatedRates.isEmpty && updatedRates.values.contains { value in
            if let rate = Double(value), rate > 0 {
                return true
            }
            return false
        }
    }
    
    private func updateRates() {
        updateError = ""
        successMessage = ""
        isUpdating = true
        
        Task {
            var updatesCount = 0
            
            for (rateKey, rateValue) in updatedRates {
                if let rate = Double(rateValue), rate > 0 {
                    let components = rateKey.components(separatedBy: "_to_")
                    if components.count == 2 {
                        let fromCurrency = components[0]
                        let toCurrency = components[1]
                        
                        do {
                            try await currencyManager.saveDirectExchangeRate(
                                from: fromCurrency,
                                to: toCurrency,
                                rate: rate
                            )
                            updatesCount += 1
                        } catch {
                            DispatchQueue.main.async {
                                self.updateError = "Failed to update \(fromCurrency) to \(toCurrency) rate: \(error.localizedDescription)"
                                self.isUpdating = false
                            }
                            return
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.isUpdating = false
                
                if updatesCount > 0 {
                    self.successMessage = "Successfully updated \(updatesCount) exchange rate(s)!"
                    
                    // Refresh currency manager data
                    self.currencyManager.fetchDirectExchangeRates()
                    
                    // Auto-dismiss after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                } else {
                    self.updateError = "No valid rates to update."
                }
            }
        }
    }
}
