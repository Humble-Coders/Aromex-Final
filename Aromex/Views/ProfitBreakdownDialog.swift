import SwiftUI
import FirebaseFirestore

struct ProfitBreakdownDialog: View {
    let totalExchangeProfit: [String: Double]
    let totalProfitInCAD: Double // Changed from totalProfitInUSD
    let timeframe: ProfitTimeframe
    let currencyManager: CurrencyManager
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Theme colors
    let mainColor = Color(red: 0.23, green: 0.28, blue: 0.42)
    let sectionBg = Color.white
    
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
        return 600
        #else
        if horizontalSizeClass == .compact {
            return UIScreen.main.bounds.width - 40
        } else {
            return min(600, UIScreen.main.bounds.width - 80)
        }
        #endif
    }
    
    private var dialogHeight: CGFloat {
        #if os(macOS)
        return 500
        #else
        if shouldUseVerticalLayout {
            return min(UIScreen.main.bounds.height - 100, 600)
        } else {
            return min(500, UIScreen.main.bounds.height - 100)
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
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profit Breakdown")
                            .font(.system(size: shouldUseVerticalLayout ? 24 : 28, weight: .bold, design: .serif))
                            .foregroundColor(mainColor)
                        
                        Text("Exchange profits for \(timeframe.rawValue.lowercased())")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, shouldUseVerticalLayout ? 16 : 24)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 24)
                
                VStack(spacing: 24) {
                    // Total CAD Profit Summary
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                            
                            Text("Total Profit (CAD)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        
                        HStack {
                            Text("$\(totalProfitInCAD, specifier: "%.2f")")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundColor(totalProfitInCAD >= 0 ? .green : .red)
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Converted using")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("DirectExchangeRates")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(totalProfitInCAD >= 0 ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(totalProfitInCAD >= 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2), lineWidth: 1)
                            )
                    )
                    
                    // Individual Currency Breakdown
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                            
                            Text("Currency Breakdown")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        
                        if totalExchangeProfit.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "chart.line.flattrend.xyaxis")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                
                                Text("No exchange profits")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text("No profitable exchange transactions found for \(timeframe.rawValue.lowercased())")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(totalExchangeProfit.keys.sorted()), id: \.self) { currency in
                                    if let profit = totalExchangeProfit[currency], abs(profit) >= 0.01 {
                                        CurrencyProfitRow(
                                            currency: currency,
                                            profit: profit,
                                            currencyManager: currencyManager
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.systemGray6.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                    
                    // Calculation Note
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                            
                            Text("How it's calculated:")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Individual currency profits calculated using (Custom Rate - Market Rate) × Amount")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.secondary)
                            
                            Text("• Market rates sourced exclusively from DirectExchangeRates collection")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.secondary)
                            
                            Text("• CAD conversion uses direct exchange rates only, no approximations")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.secondary)
                            
                            Text("• Total CAD profit = Sum of all currency profits converted to CAD")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 32)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(sectionBg)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 8)
        )
        .frame(width: dialogWidth, height: dialogHeight)
    }
}

struct CurrencyProfitRow: View {
    let currency: String
    let profit: Double
    let currencyManager: CurrencyManager
    
    private var profitInCAD: Double? {
        // Convert profit to CAD using DirectExchangeRates only
        if currency == "CAD" {
            return profit
        }
        
        // Try direct rate from currency to CAD
        if let directRate = currencyManager.getDirectExchangeRate(from: currency, to: "CAD") {
            return profit * directRate
        }
        
        // Try reverse rate (CAD to currency) and invert
        if let reverseRate = currencyManager.getDirectExchangeRate(from: "CAD", to: currency) {
            return profit / reverseRate
        }
        
        // No direct rate available
        return nil
    }
    
    private var currencySymbol: String {
        return currencyManager.allCurrencies.first(where: { $0.name == currency })?.symbol ?? currency
    }
    
    private var hasDirectRate: Bool {
        return currency == "CAD" ||
               currencyManager.getDirectExchangeRate(from: currency, to: "CAD") != nil ||
               currencyManager.getDirectExchangeRate(from: "CAD", to: currency) != nil
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Currency Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(currencySymbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(currency)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                // Show rate source info
                if currency != "CAD" {
                    if hasDirectRate {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            
                            Text("Direct rate available")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                            
                            Text("No direct rate to CAD")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Profit Display
            VStack(alignment: .trailing, spacing: 6) {
                // Original currency profit
                Text("\(profit > 0 ? "+" : "")\(profit, specifier: "%.2f") \(currencySymbol)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(profit >= 0 ? .green : .red)
                
                // CAD equivalent
                if let cadValue = profitInCAD {
                    HStack(spacing: 4) {
                        Text("≈")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("\(cadValue > 0 ? "+" : "")$\(abs(cadValue), specifier: "%.2f")")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(cadValue >= 0 ? .green : .red)
                        
                        Text("CAD")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(cadValue >= 0 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.systemBackgroundColor)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}
