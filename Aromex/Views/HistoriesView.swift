//
//  HistoriesView.swift
//  Aromex
//
//  Created by CursorAI on 11/10/25.
//

import SwiftUI
import FirebaseFirestore
#if os(iOS)
import UIKit
#endif

struct HistoriesView: View {
    typealias ViewBillHandler = (String, Bool) -> Void
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var historyEntries: [HistoryEntry] = []
    @State private var hasAttemptedLoad = false
    @State private var searchText: String = ""
    @State private var selectedTab: HistoryType = .purchase // Default to first tab
    // Removed activeEntityTypes - entity filters are no longer used
    
    // Date range for filtering - default to "forever to forever" (no restriction)
    @State private var startDate: Date? = nil // nil means no start date restriction (forever past)
    @State private var endDate: Date? = nil // nil means no end date restriction (forever future)
    @State private var showStartDatePicker = false
    @State private var showEndDatePicker = false
    @State private var hasCustomDateRange = false // Track if user has set a custom date range
    
    // Incremental loading: track which dates have been loaded
    @State private var loadedDates: Set<Date> = []
    @State private var isLoadingMoreDays = false
    
    // Cache grouped entries to avoid re-sorting on every body recomputation
    @State private var groupedCache: [(date: Date, entries: [HistoryEntry])] = []
    @State private var allAvailableDates: [Date] = [] // All dates that match the filter
    
    // Navigation state for bill screen
    @State private var selectedBillTransaction: (id: String, isSale: Bool)? = nil
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    let onViewBill: ViewBillHandler?
    
    init(onViewBill: ViewBillHandler? = nil) {
        self.onViewBill = onViewBill
        #if DEBUG
        print("🔵 [HistoriesView] Initialized with onViewBill: \(onViewBill != nil ? "provided" : "nil")")
        #endif
    }
    
    // Handler that sets navigation state for bill screen
    // On iOS, use navigationDestination to preserve navigation stack
    // On other platforms or if navigation is not available, call the callback
    private func handleViewBill(transactionId: String, isSale: Bool) {
        #if os(iOS)
        // Use navigationDestination to preserve navigation stack
        selectedBillTransaction = (id: transactionId, isSale: isSale)
        #else
        // On other platforms, use the callback
        onViewBill?(transactionId, isSale)
        #endif
    }
    
    private var isCompact: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone && horizontalSizeClass == .compact
        #else
        return false
        #endif
    }
    
    // Check if a date is within the selected date range
    // If startDate/endDate are nil, it means "forever" (no restriction)
    private func dateInRange(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let dateStart = calendar.startOfDay(for: date)
        
        // If no custom date range is set, allow all dates
        if !hasCustomDateRange {
            return true
        }
        
        // Check start date restriction
        if let start = startDate {
            let rangeStart = calendar.startOfDay(for: start)
            if dateStart < rangeStart {
                return false
            }
        }
        
        // Check end date restriction
        if let end = endDate {
            let rangeEnd = calendar.startOfDay(for: end)
            if dateStart > rangeEnd {
                return false
            }
        }
        
        return true
    }
    
    // Update grouped cache - call this when filters or entries change
    private func updateGroupedCache(resetLoadedDates: Bool = false) {
        let calendar = Calendar.current
        
        // Reset loaded dates when filters or tab change
        // CRITICAL: Always clear loadedDates when reset is requested
        if resetLoadedDates {
            let countBefore = loadedDates.count
            let datesBefore = Array(loadedDates) // Store dates before clearing
            loadedDates.removeAll() // Clear all loaded dates
            #if DEBUG
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .none
            print("🟡 [HistoriesView] Reset loaded dates - cleared \(countBefore) dates")
            if countBefore > 0 {
                print("🟡 [HistoriesView] Cleared dates were: \(datesBefore.map { dateFormatter.string(from: $0) })")
            }
            print("🟡 [HistoriesView] loadedDates.count after clear: \(loadedDates.count) (should be 0)")
            #endif
        }
        
        let filtered = getFilteredEntries()
        
        #if DEBUG
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        print("🔵 [HistoriesView] updateGroupedCache - historyEntries: \(historyEntries.count), filtered: \(filtered.count)")
        if hasCustomDateRange {
            let startStr = startDate.map { dateFormatter.string(from: $0) } ?? "forever"
            let endStr = endDate.map { dateFormatter.string(from: $0) } ?? "forever"
            print("🔵 [HistoriesView] Date range: \(startStr) to \(endStr)")
        } else {
            print("🔵 [HistoriesView] Date range: forever to forever (no restriction)")
        }
        #endif
        
        // Group filtered entries by date (normalize all dates to start of day)
        let grouped = Dictionary(grouping: filtered) { entry in
            calendar.startOfDay(for: entry.transaction.date)
        }
        
        // Get all unique dates from filtered entries (already filtered by date range in getFilteredEntries)
        // These dates are already normalized to start of day
        let uniqueDates = Set(filtered.map { calendar.startOfDay(for: $0.transaction.date) })
        allAvailableDates = uniqueDates.sorted(by: >) // Sort newest first (latest date is first)
        
        #if DEBUG
        print("🔵 [HistoriesView] updateGroupedCache - allAvailableDates: \(allAvailableDates.count), loadedDates: \(loadedDates.count)")
        if !allAvailableDates.isEmpty {
            print("🔵 [HistoriesView] Available dates (newest to oldest): \(allAvailableDates.map { dateFormatter.string(from: $0) })")
        }
        #endif
        
        // CRITICAL: If resetLoadedDates is true, we MUST start fresh with only latest date
        // This is the initial load case - only show latest date
        if resetLoadedDates {
            if !allAvailableDates.isEmpty {
                // Only load the first (newest) date - the latest date
                // ABSOLUTELY DO NOT load all dates, only the latest one
                let latestDate = allAvailableDates.first!
                
                // CRITICAL: Create a new Set with ONLY the latest date
                // Do not use insert/removeAll - create fresh to avoid any issues
                loadedDates = [latestDate]
                
                #if DEBUG
                print("🟢 [HistoriesView] RESET: Setting loadedDates to ONLY latest date: \(dateFormatter.string(from: latestDate))")
                print("🟢 [HistoriesView] Total available: \(allAvailableDates.count) dates")
                print("🟢 [HistoriesView] loadedDates.count: \(loadedDates.count) (MUST be 1)")
                print("🟢 [HistoriesView] loadedDates contains: \(loadedDates.map { dateFormatter.string(from: $0) })")
                if allAvailableDates.count > 1 {
                    print("🟢 [HistoriesView] Oldest date (NOT loading): \(dateFormatter.string(from: allAvailableDates.last!))")
                }
                #endif
            } else {
                // No available dates, set to empty
                loadedDates = []
                #if DEBUG
                print("🟡 [HistoriesView] RESET: No available dates, loadedDates is empty")
                #endif
            }
        } else if loadedDates.isEmpty && !allAvailableDates.isEmpty {
            // If not resetting but loadedDates is empty, load only latest date
            let latestDate = allAvailableDates.first!
            loadedDates = [latestDate]
            #if DEBUG
            print("🟢 [HistoriesView] EMPTY: Setting loadedDates to ONLY latest date: \(dateFormatter.string(from: latestDate))")
            print("🟢 [HistoriesView] loadedDates.count: \(loadedDates.count) (MUST be 1)")
            #endif
        }
        
        // CRITICAL: ALWAYS verify loadedDates contains at most 1 date after reset
        // This is a safety check to catch any bugs
        if resetLoadedDates && loadedDates.count > 1 {
            #if DEBUG
            print("⚠️⚠️⚠️ [HistoriesView] CRITICAL ERROR: loadedDates contains \(loadedDates.count) dates after reset!")
            print("⚠️⚠️⚠️ [HistoriesView] loadedDates: \(loadedDates.map { dateFormatter.string(from: $0) })")
            print("⚠️⚠️⚠️ [HistoriesView] This should NEVER happen! Forcing to latest only.")
            #endif
            // Force to only contain latest date
            if !allAvailableDates.isEmpty {
                let latestDate = allAvailableDates.first!
                loadedDates = [latestDate]
                #if DEBUG
                print("⚠️⚠️⚠️ [HistoriesView] Fixed: loadedDates now contains only: \(dateFormatter.string(from: latestDate))")
                #endif
            } else {
                loadedDates = []
            }
        }
        
        // CRITICAL: Only show dates that are explicitly in loadedDates set
        // This ensures we only display the latest date initially, not all available dates
        // Convert Set to Array and sort (should only be 1 date initially)
        let datesToDisplay = Array(loadedDates).sorted(by: >)
        
        #if DEBUG
        print("🔵 [HistoriesView] Dates to display: \(datesToDisplay.count) - \(datesToDisplay.map { dateFormatter.string(from: $0) })")
        if datesToDisplay.count != 1 && resetLoadedDates {
            print("⚠️ [HistoriesView] ERROR: datesToDisplay.count = \(datesToDisplay.count), expected 1!")
        }
        #endif
        
        // CRITICAL: Build groupedCache ONLY from dates in loadedDates
        // Do NOT use allAvailableDates - only use loadedDates
        // This is the most important check to prevent showing multiple dates
        var newGroupedCache: [(date: Date, entries: [HistoryEntry])] = []
        
        // CRITICAL: Only iterate over dates that are in loadedDates
        // If resetLoadedDates is true, we should only have 1 date (the latest)
        for date in datesToDisplay {
            // Double-check: Only include dates that are in loadedDates
            guard loadedDates.contains(date) else {
                #if DEBUG
                print("⚠️ [HistoriesView] Skipping date not in loadedDates: \(dateFormatter.string(from: date))")
                #endif
                continue
            }
            
            // Get entries for this specific date from the grouped dictionary
            guard let entries = grouped[date],
                  !entries.isEmpty else {
                #if DEBUG
                print("🟡 [HistoriesView] No entries found for loaded date: \(dateFormatter.string(from: date))")
                #endif
                continue
            }
            
            // Sort entries within this date by time (newest first)
            let sortedEntries = entries.sorted { $0.transaction.date > $1.transaction.date }
            newGroupedCache.append((date: date, entries: sortedEntries))
        }
        
        // CRITICAL: If resetLoadedDates is true, groupedCache MUST contain at most 1 date
        // If it contains more, something went wrong - force it to only contain latest date
        if resetLoadedDates && newGroupedCache.count > 1 {
            #if DEBUG
            print("⚠️⚠️⚠️ [HistoriesView] CRITICAL ERROR: newGroupedCache contains \(newGroupedCache.count) dates after reset!")
            print("⚠️⚠️⚠️ [HistoriesView] Dates: \(newGroupedCache.map { dateFormatter.string(from: $0.date) })")
            print("⚠️⚠️⚠️ [HistoriesView] loadedDates: \(loadedDates.map { dateFormatter.string(from: $0) })")
            print("⚠️⚠️⚠️ [HistoriesView] This should NEVER happen! Forcing to latest only.")
            #endif
            
            // Force to only contain latest date
            if !newGroupedCache.isEmpty && !allAvailableDates.isEmpty {
                let latestDate = allAvailableDates.first!
                if let latestGroup = newGroupedCache.first(where: { $0.date == latestDate }) {
                    newGroupedCache = [latestGroup]
                    loadedDates = [latestDate]
                    #if DEBUG
                    print("⚠️⚠️⚠️ [HistoriesView] Fixed: groupedCache now contains only latest date")
                    #endif
                } else {
                    // Latest date not in newGroupedCache, rebuild it
                    if let entries = grouped[latestDate], !entries.isEmpty {
                        let sortedEntries = entries.sorted { $0.transaction.date > $1.transaction.date }
                        newGroupedCache = [(date: latestDate, entries: sortedEntries)]
                        loadedDates = [latestDate]
                        #if DEBUG
                        print("⚠️⚠️⚠️ [HistoriesView] Rebuilt: groupedCache now contains only latest date")
                        #endif
                    }
                }
            }
        }
        
        // Final sort by date (newest first) - should only be one date initially
        groupedCache = newGroupedCache.sorted { $0.date > $1.date }
        
        #if DEBUG
        // Verify we're only showing one date initially
        if groupedCache.count > 1 && resetLoadedDates {
            print("⚠️⚠️⚠️ [HistoriesView] FINAL ERROR: groupedCache still contains \(groupedCache.count) dates after all fixes!")
            print("⚠️⚠️⚠️ [HistoriesView] Dates in groupedCache: \(groupedCache.map { dateFormatter.string(from: $0.date) })")
            print("⚠️⚠️⚠️ [HistoriesView] loadedDates: \(loadedDates.map { dateFormatter.string(from: $0) })")
        }
        #endif
        
        #if DEBUG
        print("✅ [HistoriesView] updateGroupedCache result:")
        print("   - loadedDates.count: \(loadedDates.count)")
        print("   - loadedDates: \(loadedDates.map { dateFormatter.string(from: $0) })")
        print("   - groupedCache.count: \(groupedCache.count)")
        if !groupedCache.isEmpty {
            print("   - Dates in groupedCache: \(groupedCache.map { dateFormatter.string(from: $0.date) })")
            if groupedCache.count > 1 {
                print("   ⚠️ WARNING: Showing \(groupedCache.count) dates! Should only show 1 date on initial load.")
                print("   ⚠️ This means multiple dates are in loadedDates, which should not happen!")
            } else {
                print("   ✅ Correct: Only showing 1 date (latest)")
            }
        }
        #endif
        
        #if DEBUG
        print("✅ [HistoriesView] updateGroupedCache - groupedCache: \(groupedCache.count) groups, total entries: \(groupedCache.reduce(0) { $0 + $1.entries.count })")
        print("✅ [HistoriesView] Loaded dates: \(loadedDates.count), Available dates: \(allAvailableDates.count)")
        if !groupedCache.isEmpty {
            print("✅ [HistoriesView] First group date: \(groupedCache.first!.date), entries: \(groupedCache.first!.entries.count)")
            print("✅ [HistoriesView] Last group date: \(groupedCache.last!.date), entries: \(groupedCache.last!.entries.count)")
        }
        if !loadedDates.isEmpty {
            print("✅ [HistoriesView] Loaded dates: \(loadedDates.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none) })")
        }
        #endif
    }
    
    // Load the next day when user reaches the end
    // This will load the next OLDEST date (one day older than the currently oldest loaded date)
    // CRITICAL: We want to load dates in chronological order going backwards (newest first, then older)
    private func loadNextDay() {
        // Prevent multiple simultaneous loads
        guard !isLoadingMoreDays else {
            #if DEBUG
            print("🟡 [HistoriesView] Already loading next day, skipping...")
            #endif
            return
        }
        
        // Ensure we have available dates calculated
        guard !allAvailableDates.isEmpty else {
            #if DEBUG
            print("🟡 [HistoriesView] No available dates found")
            #endif
            return
        }
        
        // CRITICAL: We need to find the next date to load
        // Strategy: Find the oldest currently loaded date, then find the next oldest date after that
        // Since allAvailableDates is sorted newest first, we need to find the oldest loaded date
        // and then find the next date that's older than that
        
        let sortedLoadedDates = Array(loadedDates).sorted(by: >) // Sort newest first
        guard let oldestLoadedDate = sortedLoadedDates.last else {
            #if DEBUG
            print("🟡 [HistoriesView] No loaded dates found")
            #endif
            return
        }
        
        // Find all unloaded dates that are OLDER than the oldest loaded date
        // We want to load dates going backwards in time (from newest to oldest)
        // So we want the next date that's older than the oldest currently loaded date
        let unloadedOlderDates = allAvailableDates.filter { date in
            !loadedDates.contains(date) && date < oldestLoadedDate
        }
        
        guard !unloadedOlderDates.isEmpty else {
            #if DEBUG
            print("🟡 [HistoriesView] No more dates to load (all \(allAvailableDates.count) dates already loaded: \(loadedDates.count))")
            #endif
            return
        }
        
        // Sort unloaded older dates by date (newest first) and get the first one
        // This will be the next date to load (the newest unloaded date that's older than the oldest loaded date)
        let sortedUnloadedOlderDates = unloadedOlderDates.sorted(by: >)
        let nextDate = sortedUnloadedOlderDates.first!
        
        isLoadingMoreDays = true
        
        #if DEBUG
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        print("🟢 [HistoriesView] Loading next day: \(dateFormatter.string(from: nextDate))")
        print("🟢 [HistoriesView] Currently loaded: \(loadedDates.count) dates")
        print("🟢 [HistoriesView] Oldest loaded date: \(dateFormatter.string(from: oldestLoadedDate))")
        print("🟢 [HistoriesView] Available dates: \(allAvailableDates.count)")
        print("🟢 [HistoriesView] Unloaded older dates: \(unloadedOlderDates.count)")
        #endif
        
        // Add the next date to loaded dates (only one date at a time)
        loadedDates.insert(nextDate)
        
        #if DEBUG
        print("🟢 [HistoriesView] After insert - loadedDates.count: \(loadedDates.count)")
        print("🟢 [HistoriesView] Loaded dates: \(Array(loadedDates).sorted(by: >).map { dateFormatter.string(from: $0) })")
        #endif
        
        // Update cache with the new date (don't reset loaded dates)
        // Call updateGroupedCache to recalculate with the new date
        updateGroupedCache(resetLoadedDates: false)
        
        // Small delay to ensure UI updates smoothly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.isLoadingMoreDays = false
            #if DEBUG
            print("🟢 [HistoriesView] Finished loading next day, isLoadingMoreDays = false")
            #endif
        }
    }
    
    // Get filtered entries without grouping
    private func getFilteredEntries() -> [HistoryEntry] {
        let hasSearch = !searchText.isEmpty
        
        // Early return if no filters (but still apply tab and date range)
        var filtered: [HistoryEntry]
        if !hasSearch {
            filtered = historyEntries.filter { entry in
                // For expenses, purchases, and sales in Cash/Bank/CreditCard tabs, use matchesTabFilter directly (don't check selectedTab.matches)
                // For other transactions, check if transaction type matches tab first
                if entry.transaction.type == .expense {
                    // Expenses are handled by matchesTabFilter (which checks Cash/Bank/Expense tabs)
                    if !matchesTabFilter(entry) {
                        return false
                    }
                } else if entry.transaction.type == .purchase {
                    // Purchases are handled by matchesTabFilter (which checks Purchase/Cash/Bank/CreditCard tabs)
                    if !matchesTabFilter(entry) {
                        return false
                    }
                } else if entry.transaction.type == .sale {
                    // Sales are handled by matchesTabFilter (which checks Sale/Cash/Bank/CreditCard tabs)
                    if !matchesTabFilter(entry) {
                        return false
                    }
                } else if entry.transaction.type == .middleman {
                    // Middleman transactions are handled by matchesTabFilter (which checks Middleman/Cash/Bank/CreditCard tabs)
                    if !matchesTabFilter(entry) {
                        return false
                    }
                } else {
                    // For non-expense, non-purchase, non-sale, non-middleman transactions, check if transaction type matches tab
                    if !selectedTab.matches(entry.transaction.type) {
                        return false
                    }
                    
                    // Apply Cash/Bank specific filtering for currency transactions
                    if !matchesTabFilter(entry) {
                        return false
                    }
                }
                
                // Apply date range filter
                return dateInRange(entry.transaction.date)
            }
        } else {
            let searchLower = searchText.lowercased()
            
            filtered = historyEntries.filter { entry in
                // For expenses, purchases, and sales in Cash/Bank/CreditCard tabs, use matchesTabFilter directly (don't check selectedTab.matches)
                // For other transactions, check if transaction type matches tab first
                if entry.transaction.type == .expense {
                    // Expenses are handled by matchesTabFilter (which checks Cash/Bank/Expense tabs)
                    if !matchesTabFilter(entry) {
                        return false
                    }
                } else if entry.transaction.type == .purchase {
                    // Purchases are handled by matchesTabFilter (which checks Purchase/Cash/Bank/CreditCard tabs)
                    if !matchesTabFilter(entry) {
                        return false
                    }
                } else if entry.transaction.type == .sale {
                    // Sales are handled by matchesTabFilter (which checks Sale/Cash/Bank/CreditCard tabs)
                    if !matchesTabFilter(entry) {
                        return false
                    }
                } else if entry.transaction.type == .middleman {
                    // Middleman transactions are handled by matchesTabFilter (which checks Middleman/Cash/Bank/CreditCard tabs)
                    if !matchesTabFilter(entry) {
                        return false
                    }
                } else {
                    // Tab filter - always apply (only show selected tab's transactions)
                    if !selectedTab.matches(entry.transaction.type) {
                        return false
                    }
                    
                    // Apply Cash/Bank specific filtering for currency transactions
                    if !matchesTabFilter(entry) {
                        return false
                    }
                }
                
                // Date range filter - check if date is within selected range (check this early for performance)
                if !dateInRange(entry.transaction.date) {
                    return false
                }
                
                // Search filter (most expensive, do last)
                let entityNameLower = entry.entityName.lowercased()
                if entityNameLower.contains(searchLower) {
                    return true
                }
                
                if let notes = entry.transaction.notes, notes.lowercased().contains(searchLower) {
                    return true
                }
                
                if let orderNumber = entry.transaction.orderNumber,
                   String(orderNumber).contains(searchLower) {
                    return true
                }
                
                if let giverName = entry.transaction.giverName,
                   giverName.lowercased().contains(searchLower) {
                    return true
                }
                
                if let takerName = entry.transaction.takerName,
                   takerName.lowercased().contains(searchLower) {
                    return true
                }
                
                if let middlemanName = entry.transaction.middlemanName,
                   middlemanName.lowercased().contains(searchLower) {
                    return true
                }
                
                return false
            }
        }
        
        // CRITICAL: Deduplicate currency transactions in Cash and Bank tabs
        // If neither giver nor taker is myself (for Cash) or if it's a Bank transaction,
        // the same transaction appears twice (once for giver entity, once for taker entity)
        // Combine them into one entry with "giverName -> takerName" format
        if selectedTab == .currency || selectedTab == .bank {
            filtered = deduplicateCurrencyTransactions(filtered)
        }
        
        // For expenses, purchases, sales, and middleman in Cash/Bank/CreditCard tabs, adjust ONLY the paid amount based on the tab
        // Total amount and payment methods remain unchanged (show all real values)
        if selectedTab == .currency || selectedTab == .bank || selectedTab == .creditCard {
            filtered = filtered.map { entry in
                // Only adjust expenses, purchases, sales, and middleman
                guard entry.transaction.type == .expense || entry.transaction.type == .purchase || entry.transaction.type == .sale || entry.transaction.type == .middleman else {
                    return entry
                }
                
                // Only adjust paid amount based on the tab, keep everything else the same
                var adjustedPaid: Double = 0.0
                
                if selectedTab == .currency {
                    // Cash tab: Paid should show only cash amount
                    if entry.transaction.type == .expense {
                        adjustedPaid = entry.transaction.cashPaid ?? 0.0
                    } else if entry.transaction.type == .purchase {
                        adjustedPaid = entry.transaction.cashPaid ?? 0.0
                    } else if entry.transaction.type == .sale {
                        adjustedPaid = entry.transaction.cashPaid ?? 0.0
                    } else if entry.transaction.type == .middleman {
                        adjustedPaid = entry.transaction.middlemanCash ?? 0.0
                    }
                } else if selectedTab == .bank {
                    // Bank tab: Paid should show only bank amount
                    if entry.transaction.type == .expense {
                        adjustedPaid = entry.transaction.bankPaid ?? 0.0
                    } else if entry.transaction.type == .purchase {
                        adjustedPaid = entry.transaction.bankPaid ?? 0.0
                    } else if entry.transaction.type == .sale {
                        adjustedPaid = entry.transaction.bankPaid ?? 0.0
                    } else if entry.transaction.type == .middleman {
                        adjustedPaid = entry.transaction.middlemanBank ?? 0.0
                    }
                } else if selectedTab == .creditCard {
                    // Credit Card tab: Paid should show only credit card amount
                    if entry.transaction.type == .purchase {
                        adjustedPaid = entry.transaction.creditCardPaid ?? 0.0
                    } else if entry.transaction.type == .sale {
                        adjustedPaid = entry.transaction.creditCardPaid ?? 0.0
                    } else if entry.transaction.type == .middleman {
                        adjustedPaid = entry.transaction.middlemanCreditCard ?? 0.0
                    }
                } else {
                    // Expense/Purchase/Sale/Middleman tab: Paid should show total paid (cash + bank + credit card)
                    // This is already set in the transaction, so return as-is
                    return entry
                }
                
                // Create new transaction with adjusted paid amount only
                // Keep all payment methods (cashPaid, bankPaid, creditCardPaid) with original values
                // Keep amount as totalAmount (don't adjust it)
                let newTransaction = EntityTransaction(
                    id: entry.transaction.id,
                    type: entry.transaction.type,
                    date: entry.transaction.date,
                    amount: entry.transaction.amount, // Keep totalAmount (don't adjust)
                    role: entry.transaction.role,
                    orderNumber: entry.transaction.orderNumber,
                    grandTotal: entry.transaction.grandTotal,
                    paid: adjustedPaid, // Only adjust paid based on tab
                    credit: entry.transaction.credit,
                    gstAmount: entry.transaction.gstAmount,
                    pstAmount: entry.transaction.pstAmount,
                    notes: entry.transaction.notes,
                    itemCount: entry.transaction.itemCount,
                    cashPaid: entry.transaction.cashPaid, // Keep original cash amount
                    bankPaid: entry.transaction.bankPaid, // Keep original bank amount
                    creditCardPaid: entry.transaction.creditCardPaid, // Keep original credit card amount
                    middlemanCash: entry.transaction.middlemanCash,
                    middlemanBank: entry.transaction.middlemanBank,
                    middlemanCreditCard: entry.transaction.middlemanCreditCard,
                    middlemanCredit: entry.transaction.middlemanCredit,
                    middlemanUnit: entry.transaction.middlemanUnit,
                    middlemanName: entry.transaction.middlemanName,
                    sourceCollection: entry.transaction.sourceCollection,
                    currencyGiven: entry.transaction.currencyGiven,
                    currencyName: entry.transaction.currencyName,
                    giver: entry.transaction.giver,
                    giverName: entry.transaction.giverName,
                    taker: entry.transaction.taker,
                    takerName: entry.transaction.takerName,
                    isExchange: entry.transaction.isExchange,
                    receivingCurrency: entry.transaction.receivingCurrency,
                    receivedAmount: entry.transaction.receivedAmount,
                    customExchangeRate: entry.transaction.customExchangeRate,
                    balancesAfterTransaction: entry.transaction.balancesAfterTransaction
                )
                
                // Create new entry with modified transaction
                return HistoryEntry(
                    entityId: entry.entityId,
                    entityName: entry.entityName,
                    entityType: entry.entityType,
                    transaction: newTransaction
                )
            }
        }
        
        return filtered
    }
    
    // Check if entry matches the current tab's specific filter requirements
    // For Cash tab: exclude transactions where myself_bank_special_id is giver or taker, OR show expenses with cash payment, OR show purchases with cash payment
    // For Bank tab: only show transactions where myself_bank_special_id is giver or taker, OR show expenses with bank payment, OR show purchases with bank payment
    // For Credit Card tab: show purchases with credit card payment
    private func matchesTabFilter(_ entry: HistoryEntry) -> Bool {
        // Handle expense transactions separately
        if entry.transaction.type == .expense {
            #if DEBUG
            let cashPaid = entry.transaction.cashPaid ?? 0
            let bankPaid = entry.transaction.bankPaid ?? 0
            print("🔵 [matchesTabFilter] Expense: \(entry.entityName), cashPaid: \(cashPaid), bankPaid: \(bankPaid), selectedTab: \(selectedTab)")
            #endif
            
            // Cash tab: show expenses that have cash payment > 0
            if selectedTab == .currency {
                let result = (entry.transaction.cashPaid ?? 0) > 0
                #if DEBUG
                print("🔵 [matchesTabFilter] Expense in Cash tab: \(result) (cashPaid: \(entry.transaction.cashPaid ?? 0))")
                #endif
                return result
            }
            // Bank tab: show expenses that have bank payment > 0
            if selectedTab == .bank {
                let result = (entry.transaction.bankPaid ?? 0) > 0
                #if DEBUG
                print("🔵 [matchesTabFilter] Expense in Bank tab: \(result) (bankPaid: \(entry.transaction.bankPaid ?? 0))")
                #endif
                return result
            }
            // For expense tab, just check if type matches
            if selectedTab == .expense {
                return true
            }
            // Expenses don't belong in other tabs
            return false
        }
        
        // Handle purchase transactions in Cash/Bank/CreditCard tabs
        if entry.transaction.type == .purchase {
            // Cash tab: show purchases that have cash payment > 0
            if selectedTab == .currency {
                let result = (entry.transaction.cashPaid ?? 0) > 0
                #if DEBUG
                print("🔵 [matchesTabFilter] Purchase in Cash tab: \(result) (cashPaid: \(entry.transaction.cashPaid ?? 0))")
                #endif
                return result
            }
            // Bank tab: show purchases that have bank payment > 0
            if selectedTab == .bank {
                let result = (entry.transaction.bankPaid ?? 0) > 0
                #if DEBUG
                print("🔵 [matchesTabFilter] Purchase in Bank tab: \(result) (bankPaid: \(entry.transaction.bankPaid ?? 0))")
                #endif
                return result
            }
            // Credit Card tab: show purchases that have credit card payment > 0
            if selectedTab == .creditCard {
                let result = (entry.transaction.creditCardPaid ?? 0) > 0
                #if DEBUG
                print("🔵 [matchesTabFilter] Purchase in Credit Card tab: \(result) (creditCardPaid: \(entry.transaction.creditCardPaid ?? 0))")
                #endif
                return result
            }
            // For purchase tab, just check if type matches
            if selectedTab == .purchase {
                return true
            }
            // Purchases don't belong in other tabs (except Cash/Bank/CreditCard)
            return false
        }
        
        // Handle sale transactions in Cash/Bank/CreditCard tabs
        if entry.transaction.type == .sale {
            // Cash tab: show sales that have cash payment > 0
            if selectedTab == .currency {
                let result = (entry.transaction.cashPaid ?? 0) > 0
                #if DEBUG
                print("🔵 [matchesTabFilter] Sale in Cash tab: \(result) (cashPaid: \(entry.transaction.cashPaid ?? 0))")
                #endif
                return result
            }
            // Bank tab: show sales that have bank payment > 0
            if selectedTab == .bank {
                let result = (entry.transaction.bankPaid ?? 0) > 0
                #if DEBUG
                print("🔵 [matchesTabFilter] Sale in Bank tab: \(result) (bankPaid: \(entry.transaction.bankPaid ?? 0))")
                #endif
                return result
            }
            // Credit Card tab: show sales that have credit card payment > 0
            if selectedTab == .creditCard {
                let result = (entry.transaction.creditCardPaid ?? 0) > 0
                #if DEBUG
                print("🔵 [matchesTabFilter] Sale in Credit Card tab: \(result) (creditCardPaid: \(entry.transaction.creditCardPaid ?? 0))")
                #endif
                return result
            }
            // For sale tab, just check if type matches
            if selectedTab == .sale {
                return true
            }
            // Sales don't belong in other tabs (except Cash/Bank/CreditCard)
            return false
        }
        
        // Handle middleman transactions in Cash/Bank/CreditCard tabs
        if entry.transaction.type == .middleman {
            // Cash tab: show middleman transactions that have cash payment > 0
            if selectedTab == .currency {
                let result = (entry.transaction.middlemanCash ?? 0) > 0
                #if DEBUG
                print("🔵 [matchesTabFilter] Middleman in Cash tab: \(result) (middlemanCash: \(entry.transaction.middlemanCash ?? 0))")
                #endif
                return result
            }
            // Bank tab: show middleman transactions that have bank payment > 0
            if selectedTab == .bank {
                let result = (entry.transaction.middlemanBank ?? 0) > 0
                #if DEBUG
                print("🔵 [matchesTabFilter] Middleman in Bank tab: \(result) (middlemanBank: \(entry.transaction.middlemanBank ?? 0))")
                #endif
                return result
            }
            // Credit Card tab: show middleman transactions that have credit card payment > 0
            if selectedTab == .creditCard {
                let result = (entry.transaction.middlemanCreditCard ?? 0) > 0
                #if DEBUG
                print("🔵 [matchesTabFilter] Middleman in Credit Card tab: \(result) (middlemanCreditCard: \(entry.transaction.middlemanCreditCard ?? 0))")
                #endif
                return result
            }
            // For middleman tab, just check if type matches
            if selectedTab == .middleman {
                return true
            }
            // Middleman transactions don't belong in other tabs (except Cash/Bank/CreditCard)
            return false
        }
        
        // Handle currency transactions
        if entry.transaction.type == .currencyRegular || entry.transaction.type == .currencyExchange {
            let giver = entry.transaction.giver ?? ""
            let taker = entry.transaction.taker ?? ""
            let bankId = "myself_bank_special_id"
            let giverIsBank = giver == bankId
            let takerIsBank = taker == bankId
            let involvesBank = giverIsBank || takerIsBank
            
            // Cash tab: show currency transactions that do NOT involve bank
            if selectedTab == .currency {
                return !involvesBank
            }
            
            // Bank tab: show currency transactions that DO involve bank
            if selectedTab == .bank {
                return involvesBank
            }
            
            // Currency transactions don't belong in other tabs
            return false
        }
        
        // For other transaction types (sale, middleman), just check if type matches
        return selectedTab.matches(entry.transaction.type)
    }
    
    // Deduplicate currency transactions where neither giver nor taker is myself
    // Returns a deduplicated list with combined entity names
    private func deduplicateCurrencyTransactions(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        // Group entries by transaction ID
        let groupedByTransactionId = Dictionary(grouping: entries) { $0.transaction.id }
        
        var deduplicated: [HistoryEntry] = []
        var processedTransactionIds: Set<String> = []
        
        for (transactionId, entriesWithSameId) in groupedByTransactionId {
            // Skip if already processed
            if processedTransactionIds.contains(transactionId) {
                continue
            }
            
            // If only one entry, keep it as is (unless it needs special handling)
            if entriesWithSameId.count == 1 {
                let entry = entriesWithSameId.first!
                
                // Check if this is a transaction where neither giver nor taker is myself
                // If so, we might need to format the entity name differently
                if isNonMyselfCurrencyTransaction(entry.transaction) {
                    // Check if we should combine the names
                    // For non-myself transactions, show "giverName -> takerName"
                    if let giverName = entry.transaction.giverName,
                       let takerName = entry.transaction.takerName {
                        let combinedName = "\(giverName) → \(takerName)"
                        let updatedEntry = HistoryEntry(
                            entityId: entry.entityId,
                            entityName: combinedName,
                            entityType: entry.entityType,
                            transaction: entry.transaction
                        )
                        deduplicated.append(updatedEntry)
                        processedTransactionIds.insert(transactionId)
                        continue
                    }
                }
                
                // Keep as is for myself transactions or if names are missing
                deduplicated.append(entry)
                processedTransactionIds.insert(transactionId)
                continue
            }
            
            // Multiple entries with same transaction ID - this is a duplicate
            // This happens when the same transaction appears for both giver and taker entities
            if entriesWithSameId.count == 2 {
                let firstEntry = entriesWithSameId[0]
                let secondEntry = entriesWithSameId[1]
                
                // Check if neither giver nor taker is myself
                if isNonMyselfCurrencyTransaction(firstEntry.transaction) {
                    // Combine into one entry with "giverName -> takerName" format
                    if let giverName = firstEntry.transaction.giverName,
                       let takerName = firstEntry.transaction.takerName {
                        // Use the first entry's transaction (they're the same)
                        // Update the entity name to show both parties
                        let combinedName = "\(giverName) → \(takerName)"
                        let combinedEntry = HistoryEntry(
                            entityId: firstEntry.entityId, // Use giver's entity ID
                            entityName: combinedName,
                            entityType: firstEntry.entityType, // Use giver's entity type
                            transaction: firstEntry.transaction
                        )
                        deduplicated.append(combinedEntry)
                        processedTransactionIds.insert(transactionId)
                        continue
                    }
                }
                
                // If it's a myself transaction, keep only one entry (prefer the one where entity matches the role)
                // For myself transactions, we want to show it from the myself perspective
                if let giver = firstEntry.transaction.giver,
                   let taker = firstEntry.transaction.taker {
                    // Check if giver is myself
                    if giver == "myself_special_id" || giver == "myself_bank_special_id" {
                        // Keep the entry where entity is myself (giver)
                        if let myselfEntry = entriesWithSameId.first(where: { $0.entityId == giver }) {
                            deduplicated.append(myselfEntry)
                            processedTransactionIds.insert(transactionId)
                            continue
                        }
                    }
                    // Check if taker is myself
                    if taker == "myself_special_id" || taker == "myself_bank_special_id" {
                        // Keep the entry where entity is myself (taker)
                        if let myselfEntry = entriesWithSameId.first(where: { $0.entityId == taker }) {
                            deduplicated.append(myselfEntry)
                            processedTransactionIds.insert(transactionId)
                            continue
                        }
                    }
                }
                
                // Fallback: just take the first entry
                deduplicated.append(firstEntry)
                processedTransactionIds.insert(transactionId)
                continue
            }
            
            // More than 2 entries with same ID (shouldn't happen, but handle it)
            // Take the first one
            deduplicated.append(entriesWithSameId.first!)
            processedTransactionIds.insert(transactionId)
        }
        
        return deduplicated
    }
    
    // Check if a currency transaction involves neither myself CASH nor myself BANK
    private func isNonMyselfCurrencyTransaction(_ transaction: EntityTransaction) -> Bool {
        guard transaction.type == .currencyRegular || transaction.type == .currencyExchange else {
            return false
        }
        
        let giver = transaction.giver ?? ""
        let taker = transaction.taker ?? ""
        
        // Return true if neither giver nor taker is myself
        let giverIsMyself = giver == "myself_special_id" || giver == "myself_bank_special_id"
        let takerIsMyself = taker == "myself_special_id" || taker == "myself_bank_special_id"
        
        return !giverIsMyself && !takerIsMyself
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
                .padding(.horizontal, isCompact ? 16 : 24)
                .padding(.top, isCompact ? 16 : 24)
            
            // Tab Bar
            tabBar
                .padding(.horizontal, isCompact ? 16 : 24)
                .padding(.top, 16)
            
            // Filters and Content
            VStack(alignment: .leading, spacing: 16) {
                filtersSection
                contentSection
            }
            .padding(.horizontal, isCompact ? 16 : 24)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.systemGroupedBackground.ignoresSafeArea())
        #if os(iOS)
        .navigationDestination(isPresented: Binding(
            get: { selectedBillTransaction != nil },
            set: { newValue in
                if !newValue {
                    selectedBillTransaction = nil
                }
            }
        )) {
            if let billTransaction = selectedBillTransaction {
                BillScreen(
                    purchaseId: billTransaction.id,
                    onClose: {
                        selectedBillTransaction = nil
                    },
                    isSale: billTransaction.isSale
                )
            }
        }
        #endif
        .task {
            #if DEBUG
            print("🔵 [HistoriesView] View appeared, starting to load transactions...")
            #endif
            await loadTransactions()
        }
        .onAppear {
            #if DEBUG
            print("🔵 [HistoriesView] onAppear called - isLoading: \(isLoading), entries: \(historyEntries.count), error: \(errorMessage ?? "none")")
            #endif
        }
        .onChange(of: searchText) { _ in
            updateGroupedCache(resetLoadedDates: true)
        }
        .onChange(of: selectedTab) { _ in
            // Reset loaded dates when tab changes
            updateGroupedCache(resetLoadedDates: true)
        }
        // Removed onChange for activeEntityTypes - entity filters are no longer used
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task { await loadTransactions(forceRefresh: true) }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task { await loadTransactions(forceRefresh: true) }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            #endif
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: isCompact ? 22 : 28, weight: .semibold))
                    .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                Text("Transaction Histories")
                    .font(.system(size: isCompact ? 24 : 28, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Text("Unified view of purchases, sales, middleman and currency transactions across every customer, middleman and supplier.")
                .font(.system(size: isCompact ? 13 : 14))
                .foregroundColor(.secondary)
        }
    }
    
    // Tab Bar
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(HistoryType.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                        updateGroupedCache(resetLoadedDates: true)
                    }) {
                        VStack(spacing: 6) {
                            // Always show icon and text on all platforms (but use smaller font on iPhone)
                            #if os(iOS)
                            if isCompact {
                                // iPhone: Show icon and text in compact format
                                VStack(spacing: 4) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(selectedTab == tab ? tab.color : .secondary)
                                    Text(tab.displayName)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(selectedTab == tab ? tab.color : .secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(minWidth: 70)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            } else {
                                // iPad: Show icon and text horizontally
                                HStack(spacing: 6) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 14, weight: .medium))
                                    Text(tab.displayName)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(selectedTab == tab ? tab.color : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            #else
                            // macOS: Show icon and text horizontally
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 14, weight: .medium))
                                Text(tab.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(selectedTab == tab ? tab.color : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            #endif
                            
                            // Underline indicator
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(tab.color)
                                    .frame(height: 3)
                                    .cornerRadius(1.5)
                            } else {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 3)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color.systemBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
    
    private var filtersSection: some View {
        VStack(spacing: 16) {
            searchField
            dateRangePicker
            // Removed entityFilters - no longer showing customer/supplier/middleman filters
        }
    }
    
    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search by name, notes or order number", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .disableAutocorrection(true)
        #if os(iOS)
                .autocapitalization(.none)
        #endif
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.systemBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
    
    private var dateRangePicker: some View {
        HStack(spacing: 12) {
            // Start Date Picker
            dateRangeButton(
                label: "Start",
                date: startDate,
                isPresented: $showStartDatePicker,
                isCompact: isCompact
            ) { selectedDate in
                let calendar = Calendar.current
                let normalizedStart = calendar.startOfDay(for: selectedDate)
                startDate = normalizedStart
                hasCustomDateRange = true
                // Ensure start date is before or equal to end date
                if let end = endDate, normalizedStart > end {
                    endDate = normalizedStart
                }
                updateGroupedCache(resetLoadedDates: true)
            }
            
            Text("to")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            // End Date Picker
            dateRangeButton(
                label: "End",
                date: endDate,
                isPresented: $showEndDatePicker,
                isCompact: isCompact
            ) { selectedDate in
                let calendar = Calendar.current
                let normalizedEnd = calendar.startOfDay(for: selectedDate)
                endDate = normalizedEnd
                hasCustomDateRange = true
                // Ensure end date is after or equal to start date
                if let start = startDate, normalizedEnd < start {
                    startDate = normalizedEnd
                }
                updateGroupedCache(resetLoadedDates: true)
            }
            
            // Clear date range button
            if hasCustomDateRange {
                Button(action: {
                    startDate = nil
                    endDate = nil
                    hasCustomDateRange = false
                    updateGroupedCache(resetLoadedDates: true)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Spacer()
        }
    }
    
    private func dateRangeButton(
        label: String,
        date: Date?,
        isPresented: Binding<Bool>,
        isCompact: Bool,
        onDateSelected: @escaping (Date) -> Void
    ) -> some View {
        // Create a non-optional binding for the date picker (defaults to today if nil)
        let dateBinding = Binding<Date>(
            get: {
                date ?? Date()
            },
            set: { newDate in
                onDateSelected(newDate)
            }
        )
        
        return Button(action: {
            isPresented.wrappedValue = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(formatDate(date))
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
        .modifier(DatePickerModifier(
            isPresented: isPresented,
            selectedDate: dateBinding,
            isCompact: isCompact
        ))
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else {
            return "Forever"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // Removed entityFilters view - entity filters are no longer used
    // Removed filterChip function - entity filters are no longer used
    
    @ViewBuilder
    private var contentSection: some View {
        if isLoading || !hasAttemptedLoad {
            loadingView
        } else if let errorMessage {
            errorView(errorMessage)
        } else if displayableGroupedCache.isEmpty {
            emptyStateView
        } else {
            transactionsListView
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.2)
            Text("Loading transactions...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Couldn't load histories")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                    .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: {
                Task { await loadTransactions(forceRefresh: true) }
            }) {
                Text("Retry")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "archivebox")
                .font(.system(size: 36))
                        .foregroundColor(.secondary)
            
            if historyEntries.isEmpty {
                Text("No transactions yet")
                    .font(.headline)
                Text("Your transaction history will appear here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("No transactions found")
                    .font(.headline)
                Text("Try adjusting your filters or selecting a different date range.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    // CRITICAL: Get the displayable grouped cache - ensures only loaded dates are shown
    // This is a computed property that filters groupedCache to only show dates in loadedDates
    // IMPORTANT: This is the final safety check - even if groupedCache has multiple dates,
    // this will only return dates that are in loadedDates
    private var displayableGroupedCache: [(date: Date, entries: [HistoryEntry])] {
        // Filter groupedCache to only show dates that are in loadedDates
        let filtered = groupedCache.filter { group in
            loadedDates.contains(group.date)
        }
        
        // CRITICAL: If loadedDates is empty or we have no dates, return empty
        // This prevents showing any dates when they shouldn't be shown
        guard !loadedDates.isEmpty else {
            #if DEBUG
            print("🟡 [HistoriesView] displayableGroupedCache: loadedDates is empty, returning empty")
            #endif
            return []
        }
        
        // Sort by date (newest first)
        let sorted = filtered.sorted { $0.date > $1.date }
        
        #if DEBUG
        // Log if we're showing more than one date (shouldn't happen on initial load)
        if sorted.count > 1 {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .none
            print("⚠️⚠️⚠️ [HistoriesView] displayableGroupedCache contains \(sorted.count) dates!")
            print("⚠️⚠️⚠️ [HistoriesView] Dates: \(sorted.map { dateFormatter.string(from: $0.date) })")
            print("⚠️⚠️⚠️ [HistoriesView] loadedDates: \(loadedDates.map { dateFormatter.string(from: $0) })")
            print("⚠️⚠️⚠️ [HistoriesView] groupedCache: \(groupedCache.map { dateFormatter.string(from: $0.date) })")
        }
        #endif
        
        return sorted
    }
    
    private var transactionsListView: some View {
        // Use ScrollView for both platforms for now to ensure visibility
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // CRITICAL: Use displayableGroupedCache instead of groupedCache directly
                // This ensures we only show dates that are in loadedDates
                ForEach(Array(displayableGroupedCache.enumerated()), id: \.element.date) { index, group in
                    Section {
                        VStack(spacing: isCompact ? 12 : 12) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { entryIndex, entry in
                                OptimizedHistoryRowView(
                                    entry: entry,
                                    selectedTab: selectedTab,
                                    onViewBill: handleViewBill,
                                    onTransactionDeleted: { deletedId in
                                        // Remove the deleted transaction from the local list
                                        withAnimation {
                                            historyEntries.removeAll { $0.id == deletedId }
                                        }
                                        // Update the grouped cache to reflect the deletion
                                        updateGroupedCache(resetLoadedDates: false)
                                    }
                                )
                                // Removed onAppear trigger here - using footer trigger instead
                                // This prevents multiple triggers and ensures we only load when user scrolls to footer
                            }
                        }
                        .padding(.horizontal, isCompact ? 16 : 20)
                        .padding(.bottom, 24)
                        .padding(.top, isCompact ? 8 : 0)
                        
                        // Show loading indicator or trigger at the end
                        // CRITICAL: Only show footer if there are more dates to load
                        // This prevents the footer from appearing on initial load when only 1 date is loaded
                        if index == displayableGroupedCache.count - 1 && allAvailableDates.count > loadedDates.count {
                            // Show a simple "Load More" button instead of auto-triggering
                            // This gives the user control and prevents immediate loading on initial render
                            VStack(spacing: 12) {
                                if isLoadingMoreDays {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading previous day...")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                } else {
                                    // Show manual load button
                                    VStack(spacing: 8) {
                                        Text("\(allAvailableDates.count - loadedDates.count) more day\(allAvailableDates.count - loadedDates.count == 1 ? "" : "s") available")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Button(action: {
                                            loadNextDay()
                                        }) {
                                            Text("Load Previous Day")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.blue)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    .padding(.vertical, 12)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                        } else if index == displayableGroupedCache.count - 1 && !allAvailableDates.isEmpty && allAvailableDates.count == loadedDates.count {
                            // All dates loaded
                            VStack {
                                Text("All transactions loaded")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .padding(.vertical, 8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                        }
                    } header: {
                        DateHeaderView(date: group.date, count: group.entries.count)
                    }
                }
            }
        }
    }
    
    // Removed toggle function - entity filters are no longer used
    
    private func loadTransactions(forceRefresh: Bool = false) async {
        #if DEBUG
        print("🔵 [HistoriesView] loadTransactions called - forceRefresh: \(forceRefresh), isLoading: \(isLoading), hasAttemptedLoad: \(hasAttemptedLoad)")
        #endif
        
        if isLoading && !forceRefresh && hasAttemptedLoad {
            #if DEBUG
            print("🟡 [HistoriesView] Already loading, skipping...")
            #endif
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            hasAttemptedLoad = true
            #if DEBUG
            print("🟢 [HistoriesView] Set isLoading = true, hasAttemptedLoad = true")
            #endif
        }
        
        do {
            #if DEBUG
            print("🔵 [HistoriesView] Starting to fetch all histories...")
            #endif
            let entries = try await HistoryFetcher().fetchAllHistories()
            #if DEBUG
            print("✅ [HistoriesView] Successfully fetched \(entries.count) entries")
            #endif
            
            await MainActor.run {
                historyEntries = entries.sorted { $0.transaction.date > $1.transaction.date }
                isLoading = false
                
                // CRITICAL: Clear loadedDates before updating cache to ensure fresh start
                // This prevents any possibility of old dates being retained
                loadedDates.removeAll()
                groupedCache = []
                
                // Update cache after loading (reset loaded dates to start fresh)
                // This will set loadedDates to only contain the latest date
                updateGroupedCache(resetLoadedDates: true)
                
                #if DEBUG
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .short
                dateFormatter.timeStyle = .none
                print("✅ [HistoriesView] Loaded \(historyEntries.count) entries")
                print("✅ [HistoriesView] groupedCache: \(groupedCache.count) groups")
                print("✅ [HistoriesView] loadedDates: \(loadedDates.count) dates - \(loadedDates.map { dateFormatter.string(from: $0) })")
                if groupedCache.count > 1 {
                    print("⚠️⚠️⚠️ [HistoriesView] ERROR: groupedCache contains \(groupedCache.count) groups after load!")
                    print("⚠️⚠️⚠️ [HistoriesView] Dates in groupedCache: \(groupedCache.map { dateFormatter.string(from: $0.date) })")
                } else if groupedCache.count == 1 {
                    print("✅ [HistoriesView] CORRECT: Only showing 1 date (latest): \(dateFormatter.string(from: groupedCache.first!.date))")
                }
                #endif
            }
        } catch {
            #if DEBUG
            print("❌ [HistoriesView] Error loading transactions: \(error)")
            print("❌ [HistoriesView] Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("❌ [HistoriesView] Error domain: \(nsError.domain), code: \(nsError.code)")
            }
            #endif
            
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Supporting Types

private enum HistoryType: CaseIterable {
    case purchase
    case sale
    case middleman
    case currency
    case bank
    case creditCard
    case expense
    
    var displayName: String {
        switch self {
        case .purchase: return "Purchases"
        case .sale: return "Sales"
        case .middleman: return "Middlemen"
        case .currency: return "Cash"
        case .bank: return "Bank"
        case .creditCard: return "Credit Card"
        case .expense: return "Expenses"
        }
    }
    
    var icon: String {
        switch self {
        case .purchase: return "cart.fill"
        case .sale: return "dollarsign.circle.fill"
        case .middleman: return "person.2.fill"
        case .currency: return "arrow.left.arrow.right"
        case .bank: return "building.columns.fill"
        case .creditCard: return "creditcard.fill"
        case .expense: return "arrow.down.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .purchase: return Color.green
        case .sale: return Color.blue
        case .middleman: return Color(red: 0.80, green: 0.40, blue: 0.20)
        case .currency: return Color.orange
        case .bank: return Color.purple
        case .creditCard: return Color.indigo
        case .expense: return Color.red
        }
    }
    
    func matches(_ type: EntityTransactionType) -> Bool {
        switch (self, type) {
        case (.purchase, .purchase),
             (.sale, .sale),
             (.middleman, .middleman),
             (.expense, .expense):
            return true
        case (.currency, .currencyRegular),
             (.currency, .currencyExchange),
             (.bank, .currencyRegular),
             (.bank, .currencyExchange):
            return true
        default:
            return false
        }
    }
}

struct HistoryEntry: Identifiable {
    let id: String
    let entityId: String
    let entityName: String
    let entityType: EntityType
    let transaction: EntityTransaction
    
    init(entityId: String, entityName: String, entityType: EntityType, transaction: EntityTransaction) {
        self.entityId = entityId
        self.entityName = entityName
        self.entityType = entityType
        self.transaction = transaction
        let roleFragment = transaction.role.isEmpty ? "none" : transaction.role
        self.id = "\(entityId)-\(transaction.id)-\(transaction.type.rawValue)-\(roleFragment)"
    }
}

// MARK: - Date Header View

private struct DateHeaderView: View {
    let date: Date
    let count: Int
    
    private var dateText: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let entryDate = calendar.startOfDay(for: date)
        
        if entryDate == today {
            return "Today"
        } else if entryDate == yesterday {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
                    HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Text("\(count) transaction\(count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.systemGroupedBackground)
    }
}

// MARK: - Entity Transaction Row Content View (iPhone only, without card wrapper)

private struct EntityTransactionRowContentView: View {
    let transaction: EntityTransaction
    let entityType: EntityType
    let entityName: String
    let selectedTab: HistoryType
    let onTransactionDeleted: ((String) -> Void)?
    let onViewBill: ((String, Bool) -> Void)?
    
    @State private var showingTransactionDetail = false
    
    // Check if this purchase, sale, or middleman should use currency transaction layout (in Cash/Bank/CreditCard tabs)
    private var shouldUseCurrencyLayout: Bool {
        if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
            return true
        }
        // For purchases, sales, and middleman in Cash/Bank/CreditCard tabs, use currency layout
        if (transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman) && (selectedTab == .currency || selectedTab == .bank || selectedTab == .creditCard) {
            return true
        }
        return false
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // For currency transactions and purchases in Cash/Bank/CreditCard tabs: Use currency layout
            if shouldUseCurrencyLayout {
                // Main content row: Date/Amount on left, Giver/Taker on right
                HStack(alignment: .top, spacing: 12) {
                    // Left side: Date/Time and Amount stacked vertically
                    VStack(alignment: .leading, spacing: 14) {
                        // Date and Time
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dateFormatter.string(from: transaction.date))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text(timeFormatter.string(from: transaction.date))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        // Amount
                        compactAmountDisplay
                    }
                    
                    Spacer()
                    
                    // Right side: Giver/Taker for currency transactions, Entity name for purchases
                    if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
                        // Currency transaction: Show Giver/Taker
                        VStack(spacing: 4) {
                            Text(transaction.giverName ?? "")
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                                .padding(.vertical, 2)
                            
                            Spacer()
                            
                            Text(transaction.takerName ?? "")
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                        }
                        .frame(minHeight: 80) // Ensure it spans the vertical space
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    } else if transaction.type == .purchase {
                        // Purchase in Cash/Bank/CreditCard tab: Show Giver (Myself CASH/BANK/CREDIT CARD) and Taker (supplier)
                        let giverName: String = {
                            switch selectedTab {
                            case .currency: return "Myself CASH"
                            case .bank: return "Myself BANK"
                            case .creditCard: return "Myself CREDIT CARD"
                            default: return "Myself"
                            }
                        }()
                        
                        VStack(spacing: 4) {
                            Text(giverName)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                                .padding(.vertical, 2)
                            
                            Spacer()
                            
                            Text(entityName)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                        }
                        .frame(minHeight: 80) // Ensure it spans the vertical space
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    } else if transaction.type == .sale {
                        // Sale in Cash/Bank/CreditCard tab: Show Giver (customer) and Taker (Myself CASH/BANK/CREDIT CARD)
                        let takerName: String = {
                            switch selectedTab {
                            case .currency: return "Myself CASH"
                            case .bank: return "Myself BANK"
                            case .creditCard: return "Myself CREDIT CARD"
                            default: return "Myself"
                            }
                        }()
                        
                        VStack(spacing: 4) {
                            Text(entityName)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                                .padding(.vertical, 2)
                            
                            Spacer()
                            
                            Text(takerName)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                        }
                        .frame(minHeight: 80) // Ensure it spans the vertical space
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    } else if transaction.type == .middleman {
                        // Middleman in Cash/Bank/CreditCard tab: Show based on whether we're giving or receiving
                        let middlemanName = transaction.middlemanName ?? entityName
                        let myselfName: String = {
                            switch selectedTab {
                            case .currency: return "Myself CASH"
                            case .bank: return "Myself BANK"
                            case .creditCard: return "Myself CREDIT CARD"
                            default: return "Myself"
                            }
                        }()
                        
                        // If middlemanUnit == "give", we're giving money (Myself → Middleman)
                        // Otherwise, we're receiving money (Middleman → Myself)
                        let isGiving = transaction.middlemanUnit == "give"
                        let giverName = isGiving ? myselfName : middlemanName
                        let takerName = isGiving ? middlemanName : myselfName
                        
                        VStack(spacing: 4) {
                            Text(giverName)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                                .padding(.vertical, 2)
                            
                            Spacer()
                            
                            Text(takerName)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                        }
                        .frame(minHeight: 80) // Ensure it spans the vertical space
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                }
                
                // Divider below main content row
                Divider()
                    .padding(.vertical, 4)
                
                // Notes section with View Details button
                if let notes = transaction.notes, !notes.isEmpty {
                    HStack(alignment: .top, spacing: 5) {
                        Text("Notes:")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(notes)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                        
                        // View Details button - horizontally opposite to notes
                        HStack(spacing: 5) {
                            Text("View Details")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                    }
                } else {
                    // View Details button when no notes
                    HStack {
                        Spacer()
                        HStack(spacing: 5) {
                            Text("View Details")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                    }
                }
            } else {
                // For non-currency transactions: Restructured layout
                // Top row: Date/Time on left, Type Badge on right
                HStack(alignment: .center) {
                    // Date and Time
                    VStack(alignment: .leading, spacing: 3) {
                        Text(dateFormatter.string(from: transaction.date))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(timeFormatter.string(from: transaction.date))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Type Badge
                    if transaction.type != .middleman && transaction.type != .expense, let itemCount = transaction.itemCount {
                        HStack(spacing: 5) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                }
                
                // Amount row: Amount on left, Transaction Details on right
                if transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman || transaction.type == .expense {
                    HStack(alignment: .top, spacing: 12) {
                        // Amount on left
                        compactAmountDisplay
                        
                        Spacer()
                        
                        // Transaction Details on right (horizontally opposite to amount)
                        VStack(alignment: .trailing, spacing: 5) {
                            // Item count (for purchase/sale only)
                            
                            // Middleman details, Expense payment split, or Paid/Credit info
                            if transaction.type == .middleman {
                                compactMiddlemanDetails
                            } else if transaction.type == .expense {
                                compactExpensePaymentSplit
                            } else {
                                compactPaidCreditDetails
                            }
                        }
                    }
                } else {
                    // For other transaction types, just show amount
                    compactAmountDisplay
                }
                
                // Divider below amount row
                Divider()
                    .padding(.vertical, 4)
                
                // Notes section with View Details button
                if let notes = transaction.notes, !notes.isEmpty {
                    HStack(alignment: .top, spacing: 5) {
                        Text("Notes:")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(notes)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                        
                        // View Details button - horizontally opposite to notes
                        HStack(spacing: 5) {
                            Text("View Details")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                    }
                } else {
                    // View Details button when no notes
                    HStack {
                        Spacer()
                        HStack(spacing: 5) {
                            Text("View Details")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingTransactionDetail = true
        }
        .sheet(isPresented: $showingTransactionDetail) {
            // Directly show the detail sheet instead of the intermediate compact row
            TransactionDetailSheetView(
                transaction: transaction,
                entityType: entityType,
                onTransactionDeleted: onTransactionDeleted,
                onViewBill: onViewBill,
                onDismiss: {
                    showingTransactionDetail = false
                }
            )
        }
    }
    
    // MARK: - Amount Display Helpers
    
    @ViewBuilder
    private var compactAmountDisplay: some View {
        if transaction.type == .middleman {
            // For middleman in Cash/Bank/CreditCard tabs, show adjusted amount based on give/get
            // Check if we're using currency layout (which means it's in Cash/Bank/CreditCard tab)
            if shouldUseCurrencyLayout {
                compactMiddlemanAdjustedAmountDisplay
            } else {
                compactMiddlemanAmountDisplay
            }
        } else if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
            compactCurrencyAmountDisplay
        } else if transaction.type == .expense {
            compactExpenseAmountDisplay
        } else if transaction.type == .purchase {
            // For purchases in Cash/Bank/CreditCard tabs, show adjusted amount with negative sign and red color
            // Check if we're using currency layout (which means it's in Cash/Bank/CreditCard tab)
            if shouldUseCurrencyLayout {
                compactPurchaseAdjustedAmountDisplay
            } else {
                compactPurchaseSaleAmountDisplay
            }
        } else if transaction.type == .sale {
            // For sales in Cash/Bank/CreditCard tabs, show adjusted amount with positive sign and green color
            // Check if we're using currency layout (which means it's in Cash/Bank/CreditCard tab)
            if shouldUseCurrencyLayout {
                compactSaleAdjustedAmountDisplay
            } else {
                compactPurchaseSaleAmountDisplay
            }
        } else {
            compactPurchaseSaleAmountDisplay
        }
    }
    
    private var compactMiddlemanAmountDisplay: some View {
        let cash = transaction.middlemanCash ?? 0
        let bank = transaction.middlemanBank ?? 0
        let creditCard = transaction.middlemanCreditCard ?? 0
        let middlemanTotal = cash + bank + creditCard
        let sign = getMiddlemanSign()
        let formattedAmount = formatCurrency(abs(middlemanTotal))
        let text = sign + formattedAmount
        let color = getMiddlemanColor()
        return compactAmountText(text: text, color: color, hasBackground: true)
    }
    
    private var compactCurrencyAmountDisplay: some View {
        // In cash/bank tabs, use dollar format instead of showing CAD
        // Positive: $45, Negative: -$45
        let isPositive = getPaidColor() == .green
        let formattedAmount: String
        if isPositive {
            formattedAmount = formatCurrency(transaction.amount)
        } else {
            formattedAmount = "-" + formatCurrency(abs(transaction.amount))
        }
        let color = getPaidColor()
        return compactAmountText(text: formattedAmount, color: color, hasBackground: true)
    }
    
    private var compactExpenseAmountDisplay: some View {
        let sign = getPaidSign()
        let formattedAmount = formatCurrency(abs(transaction.amount))
        let text = sign + formattedAmount
        let color = getPaidColor()
        return compactAmountText(text: text, color: color, hasBackground: true)
    }
    
    private var compactPurchaseAdjustedAmountDisplay: some View {
        // For purchases in Cash/Bank/CreditCard tabs, show the adjusted paid amount
        // with negative sign (money going out) and red color
        let paid = transaction.paid ?? 0.0
        let sign = "-"
        let formattedAmount = formatCurrency(abs(paid))
        let text = sign + formattedAmount
        let color = Color.red
        return compactAmountText(text: text, color: color, hasBackground: true)
    }
    
    private var compactSaleAdjustedAmountDisplay: some View {
        // For sales in Cash/Bank/CreditCard tabs, show the adjusted paid amount
        // with positive sign (money coming in) and green color
        let paid = transaction.paid ?? 0.0
        let formattedAmount = formatCurrency(paid)
        let color = Color.green
        return compactAmountText(text: formattedAmount, color: color, hasBackground: true)
    }
    
    private var compactMiddlemanAdjustedAmountDisplay: some View {
        // For middleman in Cash/Bank/CreditCard tabs, show the adjusted paid amount
        // based on whether we're giving (red, negative) or receiving (green, positive)
        let paid = transaction.paid ?? 0.0
        let isGiving = transaction.middlemanUnit == "give"
        let formattedAmount: String
        let color: Color
        
        if isGiving {
            // Giving money: show negative sign and red color
            formattedAmount = "-" + formatCurrency(abs(paid))
            color = Color.red
        } else {
            // Receiving money: show positive and green color
            formattedAmount = formatCurrency(paid)
            color = Color.green
        }
        
        return compactAmountText(text: formattedAmount, color: color, hasBackground: true)
    }
    
    private var compactPurchaseSaleAmountDisplay: some View {
        let text = formatCurrency(transaction.amount)
        return compactAmountText(text: text, color: .primary, hasBackground: false)
    }
    
    private func compactAmountText(text: String, color: Color, hasBackground: Bool) -> some View {
        Group {
            if hasBackground {
                Text(text)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(color.opacity(0.2), lineWidth: 1)
                    )
            } else {
                Text(text)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
        }
    }
    
    @ViewBuilder
    private var compactRightBadge: some View {
        if transaction.type == .middleman, let middlemanName = transaction.middlemanName {
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11))
                    .foregroundColor(transaction.type.color)
                Text(middlemanName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(transaction.type.color.opacity(0.1))
            )
        } else if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
            // Empty - giver/taker is now shown in the top row where the badge was
            EmptyView()
        } else if transaction.type == .expense {
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 11))
                    .foregroundColor(transaction.type.color)
                Text(transaction.notes ?? "Expense")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(transaction.type.color.opacity(0.1))
            )
        } else if let orderNum = transaction.orderNumber {
            Text("Order #\(orderNum)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(transaction.type.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(transaction.type.color.opacity(0.1))
                )
        }
    }
    
    @ViewBuilder
    private var compactMiddlemanDetails: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let middlemanCash = transaction.middlemanCash, middlemanCash > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 13))
                    Text("Cash: \(getMiddlemanSign())\(formatCurrency(abs(middlemanCash)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getMiddlemanColor())
            }
            
            if let middlemanBank = transaction.middlemanBank, middlemanBank > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 13))
                    Text("Bank: \(getMiddlemanSign())\(formatCurrency(abs(middlemanBank)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getMiddlemanColor())
            }
            
            if let middlemanCreditCard = transaction.middlemanCreditCard, middlemanCreditCard > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 13))
                    Text("Card: \(getMiddlemanSign())\(formatCurrency(abs(middlemanCreditCard)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getMiddlemanColor())
            }
            
            if let middlemanCredit = transaction.middlemanCredit, middlemanCredit != 0 {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                    Text("Credit: \(formatCurrency(abs(middlemanCredit)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getMiddlemanColor())
            }
        }
    }
    
    @ViewBuilder
    private var compactExpensePaymentSplit: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let cashPaid = transaction.cashPaid, cashPaid > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 13))
                    Text("Cash: \(getPaidSign())\(formatCurrency(abs(cashPaid)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getPaidColor())
            }
            
            if let bankPaid = transaction.bankPaid, bankPaid > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 13))
                    Text("Bank: \(getPaidSign())\(formatCurrency(abs(bankPaid)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getPaidColor())
            }
            
            if let creditCardPaid = transaction.creditCardPaid, creditCardPaid > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 13))
                    Text("Card: \(getPaidSign())\(formatCurrency(abs(creditCardPaid)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getPaidColor())
            }
        }
    }
    
    @ViewBuilder
    private var compactPaidCreditDetails: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let paid = transaction.paid, paid > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 13))
                    Text("Paid: \(getPaidSign())\(formatCurrency(abs(paid)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getPaidColor())
            }
            
            if let credit = transaction.credit, credit != 0 {
                HStack(spacing: 5) {
                    Image(systemName: credit > 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 13))
                    Text("Credit: \(formatCurrency(abs(credit)))")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(getCreditColor())
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    private func getCreditColor() -> Color {
        switch transaction.type {
        case .sale: return .green
        case .purchase: return .red
        case .expense: return .red
        case .middleman:
            if let source = transaction.sourceCollection {
                if source == "Sales" {
                    return .green
                } else if source == "Purchases" {
                    return .red
                }
            }
            return .orange
        default: return .orange
        }
    }
    
    private func getPaidColor() -> Color {
        switch transaction.type {
        case .sale: return .green
        case .purchase: return .red
        case .expense: return .red
        case .middleman:
            if let source = transaction.sourceCollection {
                if source == "Sales" {
                    return .green
                } else if source == "Purchases" {
                    return .red
                }
            }
            return .orange
        case .currencyRegular, .currencyExchange:
            let taker = transaction.taker ?? ""
            let giver = transaction.giver ?? ""
            if taker == "myself_special_id" || taker == "myself_bank_special_id" {
                return .green
            } else if giver == "myself_special_id" || giver == "myself_bank_special_id" {
                return .red
            } else {
                return .orange
            }
        }
    }
    
    private func getPaidSign() -> String {
        let color = getPaidColor()
        return color == .green ? "+" : "-"
    }
    
    private func getMiddlemanColor() -> Color {
        if let unit = transaction.middlemanUnit {
            return (unit == "give") ? .red : .green
        } else {
            return .orange
        }
    }
    
    private func getMiddlemanSign() -> String {
        let color = getMiddlemanColor()
        return color == .green ? "+" : "-"
    }
}

// MARK: - Optimized History Row View

private struct OptimizedHistoryRowView: View {
    let entry: HistoryEntry
    let selectedTab: HistoryType
    let onViewBill: HistoriesView.ViewBillHandler?
    let onTransactionDeleted: ((String) -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let historyType: HistoryType
    private let badgeColor: Color
    private let badgeText: String
    private let badgeIcon: String
    private let entityIcon: String
    private let entityColor: Color
    private let showPurchaseBadge: Bool
    
    init(entry: HistoryEntry, selectedTab: HistoryType, onViewBill: HistoriesView.ViewBillHandler?, onTransactionDeleted: ((String) -> Void)? = nil) {
        self.entry = entry
        self.selectedTab = selectedTab
        self.onViewBill = onViewBill
        self.onTransactionDeleted = onTransactionDeleted
        
        switch entry.transaction.type {
        case .purchase: self.historyType = .purchase
        case .sale: self.historyType = .sale
        case .middleman: self.historyType = .middleman
        case .currencyRegular, .currencyExchange: self.historyType = .currency
        case .expense: self.historyType = .expense
        }
        
        // Show Purchase/Sale/Middleman badge if purchase, sale, or middleman appears in Cash/Bank/CreditCard tabs
        self.showPurchaseBadge = (entry.transaction.type == .purchase || entry.transaction.type == .sale || entry.transaction.type == .middleman) && (selectedTab == .currency || selectedTab == .bank || selectedTab == .creditCard)
        
        self.badgeColor = historyType.color
        self.badgeText = historyType.displayName
        self.badgeIcon = entry.transaction.type.icon
        self.entityIcon = entry.entityType.icon
        self.entityColor = entry.entityType.color
    }
    
    var body: some View {
        #if os(iOS)
        if isCompact {
            // iPhone: Match EntityDetailView card styling exactly
            // Create a unified card with entity header and transaction content
            VStack(alignment: .leading, spacing: 0) {
                // Entity header row
                headerRow
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                
                // Divider
                Divider()
                
                // Transaction content (without card wrapper)
                EntityTransactionRowContentView(
                    transaction: entry.transaction,
                    entityType: entry.entityType,
                    entityName: entry.entityName,
                    selectedTab: selectedTab,
                    onTransactionDeleted: onTransactionDeleted,
                    onViewBill: onViewBill
                )
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
                    .shadow(color: Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.08), radius: 6, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
            .padding(.vertical, 4)
        } else {
            // iPad: Keep existing style
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                EntityTransactionRowView(
                    transaction: entry.transaction,
                    entityType: entry.entityType,
                    onTransactionDeleted: onTransactionDeleted,
                    onViewBill: onViewBill
                )
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                .thinMaterial
            )
            .cornerRadius(10)
            .overlay(
                Divider().opacity(0.2),
                alignment: .bottom
            )
        }
        #else
        // macOS: Keep existing style
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            EntityTransactionRowView(
                transaction: entry.transaction,
                entityType: entry.entityType,
                onTransactionDeleted: onTransactionDeleted,
                onViewBill: onViewBill
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            .thinMaterial
        )
        .cornerRadius(10)
        .overlay(
            Divider().opacity(0.2),
            alignment: .bottom
        )
        #endif
    }
    
    private var isCompact: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
    
    private var headerRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: entityIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(entityColor)
                Text(entry.entityName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                // Show Purchase/Sale/Middleman badge if purchase, sale, or middleman appears in Cash/Bank/CreditCard tabs
                if showPurchaseBadge {
                    HStack(spacing: 4) {
                        if entry.transaction.type == .purchase {
                            Image(systemName: HistoryType.purchase.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(HistoryType.purchase.color)
                            Text("Purchase")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(HistoryType.purchase.color)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(HistoryType.purchase.color.opacity(0.12))
                                .cornerRadius(8)
                        } else if entry.transaction.type == .sale {
                            Image(systemName: HistoryType.sale.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(HistoryType.sale.color)
                            Text("Sale")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(HistoryType.sale.color)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(HistoryType.sale.color.opacity(0.12))
                                .cornerRadius(8)
                        } else if entry.transaction.type == .middleman {
                            Image(systemName: HistoryType.middleman.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(HistoryType.middleman.color)
                            Text("Middleman")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(HistoryType.middleman.color)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(HistoryType.middleman.color.opacity(0.12))
                                .cornerRadius(8)
                        }
                    }
                }
                
                // Show the main transaction type badge (Cash/Bank/CreditCard for purchases in those tabs)
                if showPurchaseBadge {
                    // For purchases in Cash/Bank/CreditCard tabs, show the tab badge
                    HStack(spacing: 4) {
                        Image(systemName: selectedTab.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(selectedTab.color)
                        Text(selectedTab.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(selectedTab.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedTab.color.opacity(0.12))
                            .cornerRadius(8)
                    }
                } else {
                    // For other transactions, show the normal badge
                    HStack(spacing: 4) {
                        Image(systemName: badgeIcon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(badgeColor)
                        Text(badgeText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(badgeColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(badgeColor.opacity(0.12))
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
}

// MARK: - Fetcher

private struct HistoryFetcher {
    private let db = Firestore.firestore()
    
    func fetchAllHistories() async throws -> [HistoryEntry] {
        #if DEBUG
        print("🔵 [HistoryFetcher] fetchAllHistories started")
        print("🔵 [HistoryFetcher] Entity types to fetch: \(EntityType.allCases.map { $0.rawValue })")
        #endif
        
        return try await withThrowingTaskGroup(of: [HistoryEntry].self) { group in
            // Fetch entity-based histories
            for entityType in EntityType.allCases {
                #if DEBUG
                print("🔵 [HistoryFetcher] Adding task for entity type: \(entityType.rawValue)")
                #endif
                group.addTask {
                    let entries = try await fetchHistories(for: entityType)
                    #if DEBUG
                    print("✅ [HistoryFetcher] Fetched \(entries.count) entries for \(entityType.rawValue)")
                    #endif
                    return entries
                }
            }
            
            // Fetch expense transactions
            #if DEBUG
            print("🔵 [HistoryFetcher] Adding task for expense transactions")
            #endif
            group.addTask {
                let entries = try await fetchExpenseTransactions()
                #if DEBUG
                print("✅ [HistoryFetcher] Fetched \(entries.count) expense entries")
                #endif
                return entries
            }
            
            var combined: [HistoryEntry] = []
            var chunkIndex = 0
            for try await chunk in group {
                chunkIndex += 1
                #if DEBUG
                print("📦 [HistoryFetcher] Received chunk \(chunkIndex) with \(chunk.count) entries")
                #endif
                combined.append(contentsOf: chunk)
            }
            #if DEBUG
            print("✅ [HistoryFetcher] fetchAllHistories completed with \(combined.count) total entries")
            #endif
            return combined
        }
    }
    
    private func fetchHistories(for entityType: EntityType) async throws -> [HistoryEntry] {
        #if DEBUG
        print("🔵 [HistoryFetcher] fetchHistories for \(entityType.rawValue) - collection: \(entityType.collectionName)")
        #endif
        
        let snapshot = try await db.collection(entityType.collectionName).getDocuments()
        #if DEBUG
        print("✅ [HistoryFetcher] Fetched \(snapshot.documents.count) documents from \(entityType.collectionName)")
        #endif
        
        return try await withThrowingTaskGroup(of: [HistoryEntry].self) { group in
            var entityIndex = 0
            for document in snapshot.documents {
                entityIndex += 1
                let entityId = document.documentID
                let data = document.data()
                let entityName = data["name"] as? String ?? "Unnamed \(entityType.rawValue)"
                let historyItems = data["transactionHistory"] as? [[String: Any]] ?? []
                
                #if DEBUG
                print("📄 [HistoryFetcher] Entity \(entityIndex)/\(snapshot.documents.count): \(entityName) (ID: \(entityId)) - \(historyItems.count) history items")
                #endif
                
                group.addTask {
                    let transactions = try await fetchTransactions(
                        entityId: entityId,
                        entityName: entityName,
                        entityType: entityType,
                        historyItems: historyItems
                    )
                    #if DEBUG
                    print("✅ [HistoryFetcher] Fetched \(transactions.count) transactions for entity: \(entityName)")
                    #endif
                    return transactions
                }
            }
            
            var results: [HistoryEntry] = []
            var transactionChunkIndex = 0
            for try await transactions in group {
                transactionChunkIndex += 1
                #if DEBUG
                print("📦 [HistoryFetcher] Received transaction chunk \(transactionChunkIndex) with \(transactions.count) entries")
                #endif
                results.append(contentsOf: transactions)
            }
            #if DEBUG
            print("✅ [HistoryFetcher] fetchHistories for \(entityType.rawValue) completed with \(results.count) total entries")
            #endif
            return results
        }
    }
    
    private func fetchTransactions(
        entityId: String,
        entityName: String,
        entityType: EntityType,
        historyItems: [[String: Any]]
    ) async throws -> [HistoryEntry] {
        #if DEBUG
        print("🔵 [HistoryFetcher] fetchTransactions for entity: \(entityName) (ID: \(entityId)) - \(historyItems.count) history items")
        #endif
        
        return try await withThrowingTaskGroup(of: [HistoryEntry].self) { group in
            #if DEBUG
            print("🔵 [HistoryFetcher] Adding task to fetch currency transactions for entity: \(entityName)")
            #endif
            group.addTask {
                let transactions = try await fetchCurrencyTransactions(entityId: entityId)
                #if DEBUG
                print("✅ [HistoryFetcher] Fetched \(transactions.count) currency transactions for entity: \(entityName)")
                #endif
                return transactions.map {
                    HistoryEntry(entityId: entityId, entityName: entityName, entityType: entityType, transaction: $0)
                }
            }
            
            var purchaseCount = 0
            var salesCount = 0
            for (index, item) in historyItems.enumerated() {
                let role = item["role"] as? String ?? ""
                let timestamp = item["timestamp"] as? Timestamp
                
                if let purchaseRef = item["purchaseReference"] as? DocumentReference {
                    purchaseCount += 1
                    #if DEBUG
                    print("🔵 [HistoryFetcher] Adding task to fetch purchase transaction \(purchaseCount) (item \(index + 1)) for entity: \(entityName), role: \(role)")
                    #endif
                    group.addTask {
                        do {
                            if let transaction = try await fetchPurchaseTransaction(ref: purchaseRef, role: role, timestamp: timestamp) {
                                #if DEBUG
                                print("✅ [HistoryFetcher] Successfully fetched purchase transaction \(purchaseRef.documentID) for entity: \(entityName)")
                                #endif
                                return [HistoryEntry(entityId: entityId, entityName: entityName, entityType: entityType, transaction: transaction)]
                            } else {
                                #if DEBUG
                                print("⚠️ [HistoryFetcher] Purchase transaction \(purchaseRef.documentID) returned nil for entity: \(entityName)")
                                #endif
                                return []
                            }
                        } catch {
                            #if DEBUG
                            print("❌ [HistoryFetcher] Error fetching purchase transaction \(purchaseRef.documentID) for entity: \(entityName): \(error)")
                            #endif
                            throw error
                        }
                    }
                }
                
                if let salesRef = item["salesReference"] as? DocumentReference {
                    salesCount += 1
                    #if DEBUG
                    print("🔵 [HistoryFetcher] Adding task to fetch sales transaction \(salesCount) (item \(index + 1)) for entity: \(entityName), role: \(role)")
                    #endif
                    group.addTask {
                        do {
                            if let transaction = try await fetchSalesTransaction(ref: salesRef, role: role, timestamp: timestamp) {
                                #if DEBUG
                                print("✅ [HistoryFetcher] Successfully fetched sales transaction \(salesRef.documentID) for entity: \(entityName)")
                                #endif
                                return [HistoryEntry(entityId: entityId, entityName: entityName, entityType: entityType, transaction: transaction)]
                } else {
                                #if DEBUG
                                print("⚠️ [HistoryFetcher] Sales transaction \(salesRef.documentID) returned nil for entity: \(entityName)")
                                #endif
                                return []
                            }
                        } catch {
                            #if DEBUG
                            print("❌ [HistoryFetcher] Error fetching sales transaction \(salesRef.documentID) for entity: \(entityName): \(error)")
                            #endif
                            throw error
                        }
                    }
                }
            }
            
            #if DEBUG
            print("🔵 [HistoryFetcher] Added \(purchaseCount) purchase tasks and \(salesCount) sales tasks for entity: \(entityName)")
            #endif
            
            var transactions: [HistoryEntry] = []
            var chunkCount = 0
            for try await chunk in group {
                chunkCount += 1
                #if DEBUG
                print("📦 [HistoryFetcher] Received chunk \(chunkCount) with \(chunk.count) entries for entity: \(entityName)")
                #endif
                transactions.append(contentsOf: chunk)
            }
            #if DEBUG
            print("✅ [HistoryFetcher] fetchTransactions completed for entity: \(entityName) with \(transactions.count) total entries")
            #endif
            return transactions
        }
    }
    
    private func fetchPurchaseTransaction(ref: DocumentReference, role: String, timestamp: Timestamp?) async throws -> EntityTransaction? {
        #if DEBUG
        print("🔵 [HistoryFetcher] fetchPurchaseTransaction - docID: \(ref.documentID), role: \(role)")
        #endif
        
        do {
            let doc = try await ref.getDocument()
            guard doc.exists, let data = doc.data() else {
                #if DEBUG
                print("⚠️ [HistoryFetcher] Purchase document \(ref.documentID) does not exist or has no data")
                #endif
                return nil
            }
            
            let purchasedPhones = data["purchasedPhones"] as? [[String: Any]] ?? []
            let services = data["services"] as? [[String: Any]] ?? []
            let paymentMethods = data["paymentMethods"] as? [String: Any] ?? [:]
            let middlemanPayment = data["middlemanPayment"] as? [String: Any] ?? [:]
            let middlemanPaymentSplit = middlemanPayment["paymentSplit"] as? [String: Any] ?? [:]
            
            let transactionType: EntityTransactionType
            if role == "middleman" {
                transactionType = .middleman
            } else {
                transactionType = .purchase
            }
            
            let grandTotal = data["grandTotal"] as? Double ?? 0.0
            #if DEBUG
            print("✅ [HistoryFetcher] Purchase transaction \(ref.documentID): type=\(transactionType.rawValue), grandTotal=\(grandTotal), phones=\(purchasedPhones.count), services=\(services.count)")
            #endif
            
            return EntityTransaction(
                id: doc.documentID,
                type: transactionType,
                date: (data["transactionDate"] as? Timestamp)?.dateValue() ?? timestamp?.dateValue() ?? Date(),
                amount: grandTotal,
                role: role,
                orderNumber: data["orderNumber"] as? Int,
                grandTotal: grandTotal,
                paid: paymentMethods["totalPaid"] as? Double,
                credit: paymentMethods["remainingCredit"] as? Double,
                gstAmount: data["gstAmount"] as? Double,
                pstAmount: data["pstAmount"] as? Double,
                notes: data["notes"] as? String,
                itemCount: purchasedPhones.count + services.count,
                cashPaid: paymentMethods["cash"] as? Double,
                bankPaid: paymentMethods["bank"] as? Double,
                creditCardPaid: paymentMethods["creditCard"] as? Double,
                middlemanCash: middlemanPaymentSplit["cash"] as? Double,
                middlemanBank: middlemanPaymentSplit["bank"] as? Double,
                middlemanCreditCard: middlemanPaymentSplit["creditCard"] as? Double,
                middlemanCredit: middlemanPaymentSplit["credit"] as? Double,
                middlemanUnit: middlemanPayment["unit"] as? String,
                middlemanName: data["middlemanName"] as? String,
                sourceCollection: "Purchases"
            )
        } catch {
            #if DEBUG
            print("❌ [HistoryFetcher] Error fetching purchase transaction \(ref.documentID): \(error)")
            #endif
            throw error
        }
    }
    
    private func fetchSalesTransaction(ref: DocumentReference, role: String, timestamp: Timestamp?) async throws -> EntityTransaction? {
        #if DEBUG
        print("🔵 [HistoryFetcher] fetchSalesTransaction - docID: \(ref.documentID), role: \(role)")
        #endif
        
        do {
            let doc = try await ref.getDocument()
            guard doc.exists, let data = doc.data() else {
                #if DEBUG
                print("⚠️ [HistoryFetcher] Sales document \(ref.documentID) does not exist or has no data")
                #endif
                return nil
            }
            
            let soldPhones = data["soldPhones"] as? [[String: Any]] ?? []
            let services = data["services"] as? [[String: Any]] ?? []
            let paymentMethods = data["paymentMethods"] as? [String: Any] ?? [:]
            let middlemanPayment = data["middlemanPayment"] as? [String: Any] ?? [:]
            let middlemanPaymentSplit = middlemanPayment["paymentSplit"] as? [String: Any] ?? [:]
            
            let transactionType: EntityTransactionType
            if role == "middleman" {
                transactionType = .middleman
            } else {
                transactionType = .sale
            }
            
            let grandTotal = data["grandTotal"] as? Double ?? 0.0
            #if DEBUG
            print("✅ [HistoryFetcher] Sales transaction \(ref.documentID): type=\(transactionType.rawValue), grandTotal=\(grandTotal), phones=\(soldPhones.count), services=\(services.count)")
            #endif
            
            return EntityTransaction(
                id: doc.documentID,
                type: transactionType,
                date: (data["transactionDate"] as? Timestamp)?.dateValue() ?? timestamp?.dateValue() ?? Date(),
                amount: grandTotal,
                role: role,
                orderNumber: data["orderNumber"] as? Int,
                grandTotal: grandTotal,
                paid: paymentMethods["totalPaid"] as? Double,
                credit: paymentMethods["remainingCredit"] as? Double,
                gstAmount: data["gstAmount"] as? Double,
                pstAmount: data["pstAmount"] as? Double,
                notes: data["notes"] as? String,
                itemCount: soldPhones.count + services.count,
                cashPaid: paymentMethods["cash"] as? Double,
                bankPaid: paymentMethods["bank"] as? Double,
                creditCardPaid: paymentMethods["creditCard"] as? Double,
                middlemanCash: middlemanPaymentSplit["cash"] as? Double,
                middlemanBank: middlemanPaymentSplit["bank"] as? Double,
                middlemanCreditCard: middlemanPaymentSplit["creditCard"] as? Double,
                middlemanCredit: middlemanPaymentSplit["credit"] as? Double,
                middlemanUnit: middlemanPayment["unit"] as? String,
                middlemanName: data["middlemanName"] as? String,
                sourceCollection: "Sales"
            )
            } catch {
            #if DEBUG
            print("❌ [HistoryFetcher] Error fetching sales transaction \(ref.documentID): \(error)")
            #endif
            throw error
        }
    }
    
    private func fetchCurrencyTransactions(entityId: String) async throws -> [EntityTransaction] {
        #if DEBUG
        print("🔵 [HistoryFetcher] fetchCurrencyTransactions for entityId: \(entityId)")
        #endif
        
        do {
            async let giverDocs = db.collection("CurrencyTransactions")
                .whereField("giver", isEqualTo: entityId)
                .whereField("isExchange", isEqualTo: false)
                .getDocuments()
            
            async let takerDocs = db.collection("CurrencyTransactions")
                .whereField("taker", isEqualTo: entityId)
                .whereField("isExchange", isEqualTo: false)
                .getDocuments()
            
            let (giverSnapshot, takerSnapshot) = try await (giverDocs, takerDocs)
            #if DEBUG
            print("✅ [HistoryFetcher] Fetched currency transactions - giver: \(giverSnapshot.documents.count), taker: \(takerSnapshot.documents.count)")
            #endif
            
            var transactions: [EntityTransaction] = []
            
            for doc in giverSnapshot.documents {
                let data = doc.data()
                let transaction = EntityTransaction(
                    id: doc.documentID,
                    type: .currencyRegular,
                    date: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                    amount: data["amount"] as? Double ?? 0.0,
                    role: "giver",
                    notes: data["notes"] as? String,
                    currencyGiven: data["currencyGiven"] as? String,
                    currencyName: data["currencyName"] as? String,
                    giver: data["giver"] as? String,
                    giverName: data["giverName"] as? String,
                    taker: data["taker"] as? String,
                    takerName: data["takerName"] as? String,
                    balancesAfterTransaction: data["balancesAfterTransaction"] as? [String: Any]
                )
                transactions.append(transaction)
            }
            
            for doc in takerSnapshot.documents {
                let data = doc.data()
                let transaction = EntityTransaction(
                    id: doc.documentID,
                    type: .currencyRegular,
                    date: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                    amount: data["amount"] as? Double ?? 0.0,
                    role: "taker",
                    notes: data["notes"] as? String,
                    currencyGiven: data["currencyGiven"] as? String,
                    currencyName: data["currencyName"] as? String,
                    giver: data["giver"] as? String,
                    giverName: data["giverName"] as? String,
                    taker: data["taker"] as? String,
                    takerName: data["takerName"] as? String,
                    balancesAfterTransaction: data["balancesAfterTransaction"] as? [String: Any]
                )
                transactions.append(transaction)
            }
            
            #if DEBUG
            print("✅ [HistoryFetcher] fetchCurrencyTransactions completed with \(transactions.count) total transactions for entityId: \(entityId)")
            #endif
            return transactions
        } catch {
            #if DEBUG
            print("❌ [HistoryFetcher] Error fetching currency transactions for entityId \(entityId): \(error)")
            #endif
            throw error
        }
    }
    
    private func fetchExpenseTransactions() async throws -> [HistoryEntry] {
        #if DEBUG
        print("🔵 [HistoryFetcher] fetchExpenseTransactions started")
        #endif
        
        do {
            let snapshot = try await db.collection("ExpenseTransactions").getDocuments()
            #if DEBUG
            print("✅ [HistoryFetcher] Fetched \(snapshot.documents.count) expense documents")
            #endif
            
            var entries: [HistoryEntry] = []
            
            for doc in snapshot.documents {
                let data = doc.data()
                
                // Parse date - use date field, fallback to createdAt, then to current date
                let date: Date
                if let dateTimestamp = data["date"] as? Timestamp {
                    date = dateTimestamp.dateValue()
                } else if let createdAtTimestamp = data["createdAt"] as? Timestamp {
                    date = createdAtTimestamp.dateValue()
                } else {
                    date = Date()
                }
                
                // Parse payment split
                let paymentSplit = data["paymentSplit"] as? [String: Any] ?? [:]
                let bankAmount = paymentSplit["bank"] as? Double ?? 0.0
                let cashAmount = paymentSplit["cash"] as? Double ?? 0.0
                let creditCardAmount = paymentSplit["creditCard"] as? Double ?? 0.0
                
                // totalAmount is stored at the document root level, not inside paymentSplit
                let totalAmount = data["totalAmount"] as? Double ?? 0.0
                
                // Calculate paid as sum of cash + bank + credit card
                let paid = cashAmount + bankAmount + creditCardAmount
                
                // Get category and notes
                let category = data["category"] as? String ?? "Expense"
                let notes = data["notes"] as? String ?? ""
                
                // Create EntityTransaction for expense
                // Use category as entityName, and expense ID as entityId
                // Since expenses don't have entities, we'll use a special entity ID
                let expenseId = doc.documentID
                let entityId = "expense_\(expenseId)"
                let entityName = category
                
                let transaction = EntityTransaction(
                    id: expenseId,
                    type: .expense,
                    date: date,
                    amount: totalAmount, // Use totalAmount from document root (not paymentSplit)
                    role: "expense",
                    paid: paid, // Set paid as sum of cash + bank + credit card
                    notes: notes.isEmpty ? nil : notes,
                    // Store payment split in cashPaid, bankPaid, creditCardPaid
                    cashPaid: cashAmount,
                    bankPaid: bankAmount,
                    creditCardPaid: creditCardAmount
                )
                
                // Create HistoryEntry - use category as entity name, special entity type
                // We'll use a special entity type or reuse an existing one
                // For now, let's use .customer as a placeholder (it won't affect filtering)
                let entry = HistoryEntry(
                    entityId: entityId,
                    entityName: entityName,
                    entityType: .customer, // Placeholder - expenses don't have entities
                    transaction: transaction
                )
                
                entries.append(entry)
            }
            
            #if DEBUG
            print("✅ [HistoryFetcher] Created \(entries.count) expense entries")
            #endif
            
            return entries
        } catch {
            #if DEBUG
            print("❌ [HistoryFetcher] Error fetching expense transactions: \(error)")
            #endif
            throw error
        }
    }
}

// MARK: - Transaction Detail Sheet View

private struct TransactionDetailSheetView: View {
    let transaction: EntityTransaction
    let entityType: EntityType
    let onTransactionDeleted: ((String) -> Void)?
    let onViewBill: ((String, Bool) -> Void)?
    let onDismiss: () -> Void
    
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError = ""
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    private func getCreditColor() -> Color {
        switch transaction.type {
        case .sale: return .green
        case .purchase: return .red
        case .expense: return .red
        case .middleman:
            if let source = transaction.sourceCollection {
                if source == "Sales" { return .green }
                else if source == "Purchases" { return .red }
            }
            return .orange
        default: return .orange
        }
    }
    
    private func getCreditTag() -> String {
        let color = getCreditColor()
        return color == .red ? "(To Pay)" : "(To Get)"
    }
    
    private func getPaidColor() -> Color {
        switch transaction.type {
        case .sale: return .green
        case .purchase: return .red
        case .expense: return .red
        case .middleman:
            if let source = transaction.sourceCollection {
                if source == "Sales" { return .green }
                else if source == "Purchases" { return .red }
            }
            return .orange
        case .currencyRegular, .currencyExchange:
            let taker = transaction.taker ?? ""
            let giver = transaction.giver ?? ""
            if taker == "myself_special_id" || taker == "myself_bank_special_id" { return .green }
            else if giver == "myself_special_id" || giver == "myself_bank_special_id" { return .red }
            else { return .orange }
        }
    }
    
    private func getPaidSign() -> String {
        let color = getPaidColor()
        return color == .green ? "+" : "-"
    }
    
    private func getMiddlemanColor() -> Color {
        if let unit = transaction.middlemanUnit {
            return (unit == "give") ? .red : .green
        } else {
            return .orange
        }
    }
    
    private func getMiddlemanSign() -> String {
        let color = getMiddlemanColor()
        return color == .green ? "+" : "-"
    }
    
    // Computed property for formatted currency amount in cash/bank tabs
    private var formattedCurrencyAmount: String {
        if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
            let isPositive = getPaidColor() == .green
            if isPositive {
                return formatCurrency(transaction.amount)
            } else {
                return "-" + formatCurrency(abs(transaction.amount))
            }
        }
        return formatCurrency(transaction.amount)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    transactionDetailContent
                }
                .padding(.bottom, 30)
            }
            .navigationTitle("Transaction Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            #endif
        }
        .alert("Delete Transaction", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                print("🚫 Delete cancelled by user")
            }
            Button("Delete", role: .destructive) {
                print("🗑️ Delete confirmed by user, calling deleteTransaction()")
                deleteTransaction()
            }
        } message: {
            Text("Are you sure you want to delete this transaction? This will reverse all balance changes and cannot be undone.")
        }
    }
    
    @ViewBuilder
    private var transactionDetailContent: some View {
        // Header Section
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dateFormatter.string(from: transaction.date))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(timeFormatter.string(from: transaction.date))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: transaction.type.icon)
                        .font(.system(size: 14, weight: .medium))
                    Text(transaction.type.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(transaction.type.color)
                        .shadow(color: transaction.type.color.opacity(0.3), radius: 2, x: 0, y: 2)
                )
            }
            
            Divider()
            
            // Main Amount
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Amount")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                if transaction.type == .currencyRegular || transaction.type == .currencyExchange {
                    // In cash/bank tabs, use dollar format instead of showing CAD
                    // Positive: $45, Negative: -$45
                    Text(formattedCurrencyAmount)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(getPaidColor())
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(getPaidColor().opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(getPaidColor().opacity(0.2), lineWidth: 1)
                        )
                } else {
                    Text(formatCurrency(transaction.amount))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        
        // Details Card
        detailsCard
        
        // Action Buttons
        actionButtons
    }
    
    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Transaction Details Section
            Group {
                if transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(title: "Transaction Details", icon: "doc.text.fill")
                        
                        if let orderNum = transaction.orderNumber {
                            detailRow(label: "Order Number", value: "#\(orderNum)", color: transaction.type.color, icon: "number")
                        }
                        
                        detailRow(label: "Role", value: transaction.role.capitalized, color: nil, icon: "person.fill")
                        
                        if let itemCount = transaction.itemCount {
                            detailRow(label: "Items", value: "\(itemCount)", color: nil, icon: "shippingbox.fill")
                        }
                    }
                } else if transaction.type == .expense {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(title: "Expense Details", icon: "arrow.down.circle.fill")
                        
                        if let notes = transaction.notes, !notes.isEmpty {
                            detailRow(label: "Notes", value: notes, color: nil, icon: "note.text")
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(title: "Transaction Details", icon: "banknote.fill")
                        
                        if let giverName = transaction.giverName {
                            detailRow(label: "From", value: giverName, color: nil, icon: "arrow.up.right")
                        }
                        
                        if let takerName = transaction.takerName {
                            detailRow(label: "To", value: takerName, color: nil, icon: "arrow.down.left")
                        }
                        
                        if transaction.type == .currencyExchange, let receivingCurrency = transaction.receivingCurrency,
                           let receivedAmount = transaction.receivedAmount {
                            detailRow(label: "Received", value: "\(String(format: "%.2f", receivedAmount)) \(receivingCurrency)", color: .green, icon: "arrow.left.arrow.right.circle.fill")
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
            
            // Payment Details Section
            if (transaction.type == .purchase || transaction.type == .sale || transaction.type == .expense) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(title: transaction.type == .expense ? "Expense Payment" : "Payment Details", icon: "dollarsign.circle.fill")
                    
                    if transaction.type == .expense {
                        let paidAmount = transaction.paid ?? 0.0
                        detailRow(
                            label: "Total Paid",
                            value: "\(getPaidSign())\(formatCurrency(abs(paidAmount)))",
                            color: getPaidColor(),
                            icon: "checkmark.circle.fill"
                        )
                    } else {
                        if let paid = transaction.paid, paid > 0 {
                            detailRow(
                                label: "Paid",
                                value: "\(getPaidSign())\(formatCurrency(abs(paid)))",
                                color: getPaidColor(),
                                icon: "checkmark.circle.fill"
                            )
                        }
                        
                        if let credit = transaction.credit, credit != 0 {
                            detailRow(
                                label: "Credit \(getCreditTag())",
                                value: formatCurrency(abs(credit)),
                                color: getCreditColor(),
                                icon: "exclamationmark.circle.fill"
                            )
                        }
                    }
                    
                    // Payment Methods Breakdown
                    if (transaction.cashPaid ?? 0) > 0 || (transaction.bankPaid ?? 0) > 0 || (transaction.creditCardPaid ?? 0) > 0 {
                        Divider().padding(.vertical, 4)
                        
                        Text("Payment Methods")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.bottom, 4)
                        
                        if let cashPaid = transaction.cashPaid, cashPaid > 0 {
                            if transaction.type == .expense {
                                paymentMethodRow(icon: "banknote.fill", label: "Cash", amount: cashPaid, color: .red, showNegative: true)
                            } else {
                                paymentMethodRow(icon: "banknote.fill", label: "Cash", amount: cashPaid, color: .green)
                            }
                        }
                        
                        if let bankPaid = transaction.bankPaid, bankPaid > 0 {
                            if transaction.type == .expense {
                                paymentMethodRow(icon: "building.columns.fill", label: "Bank", amount: bankPaid, color: .red, showNegative: true)
                            } else {
                                paymentMethodRow(icon: "building.columns.fill", label: "Bank", amount: bankPaid, color: .blue)
                            }
                        }
                        
                        if let creditCardPaid = transaction.creditCardPaid, creditCardPaid > 0 {
                            if transaction.type == .expense {
                                paymentMethodRow(icon: "creditcard.fill", label: "Credit Card", amount: creditCardPaid, color: .red, showNegative: true)
                            } else {
                                paymentMethodRow(icon: "creditcard.fill", label: "Credit Card", amount: creditCardPaid, color: .purple)
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
            }
            
            // Middleman Details Section
            if transaction.middlemanName != nil || (transaction.middlemanCash ?? 0) > 0 || (transaction.middlemanBank ?? 0) > 0 ||
               (transaction.middlemanCreditCard ?? 0) > 0 || (transaction.middlemanCredit ?? 0) != 0 {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(title: "Middleman Details", icon: "person.2.fill")
                    
                    if let middlemanName = transaction.middlemanName {
                        detailRow(label: "Middleman", value: middlemanName, color: nil, icon: "person.crop.circle.fill")
                    }
                    
                    if let middlemanCash = transaction.middlemanCash, middlemanCash > 0 {
                        detailRow(
                            label: "Cash",
                            value: "\(getMiddlemanSign())\(formatCurrency(abs(middlemanCash)))",
                            color: getMiddlemanColor(),
                            icon: "banknote.fill"
                        )
                    }
                    
                    if let middlemanBank = transaction.middlemanBank, middlemanBank > 0 {
                        detailRow(
                            label: "Bank",
                            value: "\(getMiddlemanSign())\(formatCurrency(abs(middlemanBank)))",
                            color: getMiddlemanColor(),
                            icon: "building.columns.fill"
                        )
                    }
                    
                    if let middlemanCreditCard = transaction.middlemanCreditCard, middlemanCreditCard > 0 {
                        detailRow(
                            label: "Credit Card",
                            value: "\(getMiddlemanSign())\(formatCurrency(abs(middlemanCreditCard)))",
                            color: getMiddlemanColor(),
                            icon: "creditcard.fill"
                        )
                    }
                    
                    if let middlemanCredit = transaction.middlemanCredit, middlemanCredit != 0 {
                        let middlemanColor: Color = {
                            if let unit = transaction.middlemanUnit {
                                return (unit == "give") ? .red : .green
                            } else {
                                return .orange
                            }
                        }()
                        let middlemanTag = middlemanColor == .red ? "(To Pay)" : "(To Get)"
                        detailRow(
                            label: "Credit \(middlemanTag)",
                            value: formatCurrency(abs(middlemanCredit)),
                            color: middlemanColor,
                            icon: "exclamationmark.circle.fill"
                        )
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
            }
            
            // Tax Details Section
            if (transaction.gstAmount ?? 0) > 0 || (transaction.pstAmount ?? 0) > 0 {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(title: "Tax Details", icon: "percent")
                    
                    if let gstAmount = transaction.gstAmount, gstAmount > 0 {
                        detailRow(label: "GST", value: formatCurrency(gstAmount), color: nil, icon: "tag.fill")
                    }
                    
                    if let pstAmount = transaction.pstAmount, pstAmount > 0 {
                        detailRow(label: "PST", value: formatCurrency(pstAmount), color: nil, icon: "tag.fill")
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
            }
            
            // Notes Section
            if let notes = transaction.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(title: "Notes", icon: "note.text")
                    
                    Text(notes)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.systemGray6 : Color.systemBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            // View Bill Button
            if transaction.type == .purchase || transaction.type == .sale || transaction.type == .middleman {
                Button(action: {
                    let transactionId = transaction.id
                    let isSale = (transaction.type == .sale) || (transaction.type == .middleman && transaction.sourceCollection == "Sales")
                    // Dismiss the sheet first, then navigate
                    onDismiss()
                    // Use a small delay to ensure sheet dismissal completes before navigation
                    // This prevents navigation issues when sheet is dismissing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onViewBill?(transactionId, isSale)
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 16))
                        Text("View Bill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue)
                            .shadow(color: Color.blue.opacity(0.4), radius: 4, x: 0, y: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Delete Button
            if transaction.type == .currencyRegular || transaction.type == .purchase || transaction.type == .sale ||
               (transaction.type == .expense && onTransactionDeleted != nil) {
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                        Text("Delete")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red)
                            .shadow(color: Color.red.opacity(0.4), radius: 4, x: 0, y: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                )
            
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.primary)
        }
    }
    
    private func detailRow(label: String, value: String, color: Color?, icon: String? = nil) -> some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color ?? .secondary)
                    .frame(width: 20, alignment: .center)
            }
            
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color ?? .primary)
        }
    }
    
    private func paymentMethodRow(icon: String, label: String, amount: Double, color: Color, showNegative: Bool = false) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 22, alignment: .center)
            
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            
            Spacer()
            
            if showNegative {
                Text("\(getPaidSign())\(formatCurrency(abs(amount)))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            } else {
                Text(formatCurrency(amount))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
        }
    }
    
    private func deleteTransaction() {
        // Delete transaction logic - similar to EntityTransactionRowView
        guard let onTransactionDeleted = onTransactionDeleted else { return }
        
        isDeleting = true
        deleteError = ""
        
        Task { @MainActor in
            do {
                let db = Firestore.firestore()
                let transactionType = transaction.type
                
                if transactionType == .purchase {
                    try await db.collection("Purchases").document(transaction.id).delete()
                } else if transactionType == .sale {
                    try await db.collection("Sales").document(transaction.id).delete()
                } else if transactionType == .currencyRegular || transactionType == .currencyExchange {
                    try await db.collection("CurrencyTransactions").document(transaction.id).delete()
                } else if transactionType == .expense {
                    try await db.collection("ExpenseTransactions").document(transaction.id).delete()
                }
                
                onTransactionDeleted(transaction.id)
                isDeleting = false
                onDismiss()
            } catch {
                deleteError = error.localizedDescription
                isDeleting = false
                print("❌ Error deleting transaction: \(error)")
            }
        }
    }
}
