//
//  AddServiceDialog.swift
//  Aromex
//
//  Created for Adding Services to Sales
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct AddServiceDialog: View {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let onSave: ((ServiceItem) -> Void)?
    var serviceToEdit: ServiceItem? = nil
    
    @State private var serviceName: String = ""
    @State private var servicePrice: String = ""
    @FocusState private var isNameFocused: Bool
    @FocusState private var isPriceFocused: Bool
    @State private var showingCloseConfirmation = false
    
    @Environment(\.colorScheme) var colorScheme
    
    private var hasFormData: Bool {
        !serviceName.isEmpty || !servicePrice.isEmpty
    }
    
    private var isSaveEnabled: Bool {
        !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !servicePrice.isEmpty &&
        (Double(servicePrice) ?? 0.0) > 0
    }
    
    var body: some View {
        #if os(iOS)
        NavigationView {
            contentView
                .navigationTitle(serviceToEdit == nil ? "Add Service" : "Edit Service")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            handleCloseAction()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            handleSave()
                        }
                        .disabled(!isSaveEnabled)
                        .fontWeight(.semibold)
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(serviceToEdit == nil ? "Add Service" : "Edit Service")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    handleCloseAction()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            Divider()
            
            contentView
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") {
                    handleCloseAction()
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button("Save") {
                    handleSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isSaveEnabled)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 400)
        #endif
    }
    
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Service Name Field
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Service Name")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("*")
                            .foregroundColor(.red)
                    }
                    
                    TextField("Enter service name", text: $serviceName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.08))
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .focused($isNameFocused)
                }
                
                // Service Price Field
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Price")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("*")
                            .foregroundColor(.red)
                    }
                    
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        TextField("0.00", text: $servicePrice)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 16, weight: .medium))
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .onChange(of: servicePrice) { newValue in
                                let filtered = newValue.filter { "0123456789.".contains($0) }
                                if filtered != newValue {
                                    servicePrice = filtered
                                }
                            }
                            .focused($isPriceFocused)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.08))
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    hideKeyboard()
                }
            }
        }
        #endif
        .onAppear {
            if let service = serviceToEdit {
                serviceName = service.name
                servicePrice = String(format: "%.2f", service.price)
            } else {
                // Focus on name field when dialog opens (for new service)
                #if os(iOS)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isNameFocused = true
                }
                #endif
            }
        }
        .confirmationDialog("Close without saving?", isPresented: $showingCloseConfirmation) {
            Button("Discard Changes", role: .destructive) {
                closeDialog()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Are you sure you want to close?")
        }
    }
    
    private func handleCloseAction() {
        if hasFormData {
            showingCloseConfirmation = true
        } else {
            closeDialog()
        }
    }
    
    private func closeDialog() {
        isPresented = false
        onDismiss?()
    }
    
    private func handleSave() {
        guard isSaveEnabled else { return }
        
        let trimmedName = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        guard let price = Double(servicePrice), price > 0 else { return }
        
        let serviceItem: ServiceItem
        if let existingService = serviceToEdit {
            serviceItem = ServiceItem(id: existingService.id, name: trimmedName, price: price)
        } else {
            serviceItem = ServiceItem(name: trimmedName, price: price)
        }
        
        onSave?(serviceItem)
        closeDialog()
    }
    
    #if os(iOS)
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif
}






