//
//  LedgerDateRangeDialog.swift
//  Aromex
//

import SwiftUI

struct LedgerDateRangeDialog: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    let onCancel: () -> Void
    let onGenerate: () -> Void
    
    @State private var tempStartDate: Date = Date()
    @State private var tempEndDate: Date = Date()
    @State private var hasStartDate: Bool = false
    @State private var hasEndDate: Bool = false
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 48))
                        .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                    
                    Text("Select Date Range")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Choose the period for your transaction ledger")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Date Selection
                VStack(spacing: 20) {
                    // Start Date
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("From Date")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if hasStartDate {
                                Button(action: {
                                    withAnimation {
                                        hasStartDate = false
                                        startDate = nil
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        if hasStartDate {
                            DatePicker(
                                "",
                                selection: $tempStartDate,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .onChange(of: tempStartDate) { newValue in
                                startDate = newValue
                            }
                        } else {
                            Button(action: {
                                withAnimation {
                                    hasStartDate = true
                                    tempStartDate = startDate ?? Date()
                                    startDate = tempStartDate
                                }
                            }) {
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 14))
                                    Text("Select Start Date")
                                        .font(.system(size: 15))
                                }
                                .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // End Date
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("To Date")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if hasEndDate {
                                Button(action: {
                                    withAnimation {
                                        hasEndDate = false
                                        endDate = nil
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        if hasEndDate {
                            DatePicker(
                                "",
                                selection: $tempEndDate,
                                in: (startDate ?? Date.distantPast)...Date(),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .onChange(of: tempEndDate) { newValue in
                                endDate = newValue
                            }
                        } else {
                            Button(action: {
                                withAnimation {
                                    hasEndDate = true
                                    tempEndDate = endDate ?? Date()
                                    // Ensure end date is not before start date
                                    if let start = startDate, tempEndDate < start {
                                        tempEndDate = start
                                    }
                                    endDate = tempEndDate
                                }
                            }) {
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 14))
                                    Text("Select End Date")
                                        .font(.system(size: 15))
                                }
                                .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // Info Text
                    if hasStartDate && hasEndDate {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                            
                            Text("Both dates are optional. Leave empty to include all transactions.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        onGenerate()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Generate Ledger")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.25, green: 0.33, blue: 0.54))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color.systemBackground)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            #endif
        }
        .onAppear {
            // Initialize temp dates from bindings if they exist
            if let start = startDate {
                hasStartDate = true
                tempStartDate = start
            }
            if let end = endDate {
                hasEndDate = true
                tempEndDate = end
            }
        }
    }
}

#Preview {
    LedgerDateRangeDialog(
        startDate: .constant(nil),
        endDate: .constant(nil),
        onCancel: {},
        onGenerate: {}
    )
}

