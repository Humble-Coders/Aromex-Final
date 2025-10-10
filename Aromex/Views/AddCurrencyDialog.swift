import SwiftUI

struct AddCurrencyDialog: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    
    @State private var currencyName: String = ""
    @State private var buyRate: String = ""
    @State private var sellRate: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Currency")
                .font(.title2)
                .fontWeight(.bold)
            
            TextField("Currency Name (e.g., USD)", text: $currencyName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            #if os(iOS)
            TextField("Buy Rate", text: $buyRate)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .padding(.horizontal)
            
            TextField("Sell Rate", text: $sellRate)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .padding(.horizontal)
            #else
            TextField("Buy Rate", text: $buyRate)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            TextField("Sell Rate", text: $sellRate)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            #endif
            
            HStack(spacing: 15) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Add") {
                    // TODO: Implement currency addition
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(currencyName.isEmpty)
            }
            .padding()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

