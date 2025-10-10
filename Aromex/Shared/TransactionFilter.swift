//
//  TransactionFilter.swift
//  Aromex_V2
//
//  Created by Ansh Bajaj on 17/07/25.
//


// TransactionFilters.swift
// Create this new file in your project to share the filter enums

import SwiftUI
import Foundation

// MARK: - Transaction Filter Enums
enum TransactionFilter: String, CaseIterable {
    case normalCash = "Normal Cash"
    case sales = "Sales"
    case purchases = "Purchases"
    
    var icon: String {
        switch self {
        case .normalCash: return "arrow.left.arrow.right"
        case .sales: return "cart.fill"
        case .purchases: return "shippingbox.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .normalCash: return .blue
        case .sales: return .purple
        case .purchases: return .green
        }
    }
}

enum DateFilter: String, CaseIterable {
    case all = "All Time"
    case today = "Today"
    case week = "This Week"
    case month = "This Month"
    case year = "This Year"
    case custom = "Custom Range"
    
    var icon: String {
        switch self {
        case .all: return "infinity"
        case .today: return "calendar"
        case .week: return "calendar.badge.clock"
        case .month: return "calendar.badge.plus"
        case .year: return "calendar.circle"
        case .custom: return "calendar.badge.exclamationmark"
        }
    }
}

// MARK: - Shared Transaction Filter Button Component
struct TransactionFilterButton: View {
    let filter: TransactionFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 12, weight: .medium))
                
                Text(filter.rawValue)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : filter.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? filter.color : filter.color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(filter.color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Shared Filter Logic Extensions
extension Array where Element == AnyMixedTransaction {
    func applyTransactionFilters(
        searchText: String,
        selectedFilters: Set<TransactionFilter>,
        dateFilter: DateFilter,
        customStartDate: Date,
        customEndDate: Date
    ) -> [AnyMixedTransaction] {
        var filtered = self
        
        // Apply transaction type filters
        filtered = filtered.filter { transaction in
            switch transaction.transactionType {
            case .currency:
                return selectedFilters.contains(.normalCash)
            case .sales:
                return selectedFilters.contains(.sales)
            case .purchase:
                return selectedFilters.contains(.purchases)
            }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { transaction in
                let searchLower = searchText.lowercased()
                
                switch transaction.transactionType {
                case .currency:
                    if let currencyTx = transaction.currencyTransaction {
                        return currencyTx.giverName.lowercased().contains(searchLower) ||
                               currencyTx.takerName.lowercased().contains(searchLower) ||
                               currencyTx.notes.lowercased().contains(searchLower) ||
                               "\(currencyTx.amount)".contains(searchLower) ||
                               currencyTx.currencyName.lowercased().contains(searchLower)
                    }
                case .sales:
                    if let salesTx = transaction.transaction as? SalesTransaction {
                        return salesTx.customerName.lowercased().contains(searchLower) ||
                               (salesTx.supplierName?.lowercased().contains(searchLower) ?? false) ||
                               "\(salesTx.amount)".contains(searchLower) ||
                               "\(salesTx.total)".contains(searchLower) ||
                               (salesTx.orderNumber?.lowercased().contains(searchLower) ?? false)
                    }
                case .purchase:
                    if let purchaseTx = transaction.purchaseTransaction {
                        return purchaseTx.supplierName.lowercased().contains(searchLower) ||
                               "\(purchaseTx.amount)".contains(searchLower) ||
                               "\(purchaseTx.total)".contains(searchLower) ||
                               (purchaseTx.orderNumber?.lowercased().contains(searchLower) ?? false)
                    }
                }
                return false
            }
        }
        
        // Apply date filter
        if dateFilter != .all {
            filtered = filtered.filter { transaction in
                let transactionDate = transaction.timestamp.dateValue()
                let calendar = Calendar.current
                let now = Date()
                
                switch dateFilter {
                case .today:
                    return calendar.isDate(transactionDate, inSameDayAs: now)
                case .week:
                    return calendar.dateInterval(of: .weekOfYear, for: now)?.contains(transactionDate) ?? false
                case .month:
                    return calendar.dateInterval(of: .month, for: now)?.contains(transactionDate) ?? false
                case .year:
                    return calendar.dateInterval(of: .year, for: now)?.contains(transactionDate) ?? false
                case .custom:
                    let startOfCustomStart = calendar.startOfDay(for: customStartDate)
                    let endOfCustomEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate)) ?? customEndDate
                    return transactionDate >= startOfCustomStart && transactionDate < endOfCustomEnd
                case .all:
                    return true
                }
            }
        }
        
        return filtered
    }
}