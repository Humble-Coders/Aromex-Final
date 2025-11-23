import Foundation
import PDFKit

class LedgerGenerator {
    
    // Threshold for deciding which template to use (similar to bill pagination)
    private let maxItemsForSinglePage = 18  // Single page ledger with summary
    private let maxItemsForFirstPage = 20   // First page with header
    private let maxItemsPerContinuationPage = 22  // Continuation pages
    
    // Helper function to format amounts with commas (American number system: thousands, hundred thousands, millions, etc.)
    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3 // American system: groups of 3 digits (thousands, millions, etc.)
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
    
    // Generate ledger for HistoriesView (with entity names in rows)
    func generateHistoriesLedgerHTML(for tabName: String, entries: [HistoryEntry], startDate: Date?, endDate: Date?, companyAddress: String?, companyEmail: String?, companyPhone: String?) throws -> [String] {
        
        // Filter entries by date range
        var filteredEntries = entries
        if let start = startDate {
            let startOfDay = Calendar.current.startOfDay(for: start)
            filteredEntries = filteredEntries.filter { $0.transaction.date >= startOfDay }
        }
        if let end = endDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
            filteredEntries = filteredEntries.filter { $0.transaction.date < endOfDay }
        }
        
        // Filter out transactions with 0 amount - but include transactions with credit even if paid is 0
        filteredEntries = filteredEntries.filter { entry in
            let transaction = entry.transaction
            
            // Always include if there's credit (even if paid is 0)
            if let credit = transaction.credit, abs(credit) > 0.01 {
                return true
            }
            
            // Otherwise, check transaction amount
            switch transaction.type {
            case .sale, .purchase:
                let amount = transaction.grandTotal ?? transaction.amount
                return abs(amount) > 0.01
            case .expense:
                let amount = transaction.grandTotal ?? transaction.amount
                return abs(amount) > 0.01
            case .middleman:
                let total = (transaction.middlemanCash ?? 0) + (transaction.middlemanBank ?? 0) + (transaction.middlemanCreditCard ?? 0)
                return abs(total) > 0.01
            case .currencyRegular, .currencyExchange:
                return abs(transaction.amount) > 0.01
            case .balanceAdjustment:
                return abs(transaction.amount) > 0.01
            }
        }
        
        // Sort by date (oldest first for ledger)
        filteredEntries.sort { $0.transaction.date < $1.transaction.date }
        
        // Single page if 18 or fewer entries
        if filteredEntries.count <= maxItemsForSinglePage {
            return [try generateSinglePageHistoriesHTML(
                tabName: tabName,
                entries: filteredEntries,
                startDate: startDate,
                endDate: endDate,
                companyAddress: companyAddress,
                companyEmail: companyEmail,
                companyPhone: companyPhone
            )]
        }
        
        // Multi-page: split entries across pages
        return try generateMultiPageHistoriesHTMLArray(
            tabName: tabName,
            entries: filteredEntries,
            startDate: startDate,
            endDate: endDate,
            companyAddress: companyAddress,
            companyEmail: companyEmail,
            companyPhone: companyPhone
        )
    }
    
    func generateLedgerHTML(for entity: EntityProfile, entityType: EntityType, transactions: [EntityTransaction], startDate: Date?, endDate: Date?, companyAddress: String?, companyEmail: String?, companyPhone: String?) throws -> [String] {
        
        // Filter transactions by date range
        var filteredTransactions = transactions
        if let start = startDate {
            let startOfDay = Calendar.current.startOfDay(for: start)
            filteredTransactions = filteredTransactions.filter { $0.date >= startOfDay }
        }
        if let end = endDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
            filteredTransactions = filteredTransactions.filter { $0.date < endOfDay }
        }
        
        // Filter out transactions with 0 amount - but include transactions with credit even if paid is 0
        filteredTransactions = filteredTransactions.filter { transaction in
            // Always include if there's credit (even if paid is 0)
            if let credit = transaction.credit, abs(credit) > 0.01 {
                return true
            }
            
            // Otherwise, check transaction amount
            switch transaction.type {
            case .sale, .purchase:
                let amount = transaction.grandTotal ?? transaction.amount
                return abs(amount) > 0.01
            case .expense:
                let amount = transaction.grandTotal ?? transaction.amount
                return abs(amount) > 0.01
            case .middleman:
                let total = (transaction.middlemanCash ?? 0) + (transaction.middlemanBank ?? 0) + (transaction.middlemanCreditCard ?? 0)
                return abs(total) > 0.01
            case .currencyRegular, .currencyExchange:
                return abs(transaction.amount) > 0.01
            case .balanceAdjustment:
                return abs(transaction.amount) > 0.01
            }
        }
        
        // Sort by date (oldest first for ledger)
        filteredTransactions.sort { $0.date < $1.date }
        
        // Single page if 18 or fewer transactions
        if filteredTransactions.count <= maxItemsForSinglePage {
            return [try generateSinglePageHTML(
                for: entity,
                entityType: entityType,
                transactions: filteredTransactions,
                startDate: startDate,
                endDate: endDate,
                companyAddress: companyAddress,
                companyEmail: companyEmail,
                companyPhone: companyPhone
            )]
        }
        
        // Multi-page: split transactions across pages (similar to bill pagination)
        return try generateMultiPageHTMLArray(
            for: entity,
            entityType: entityType,
            transactions: filteredTransactions,
            startDate: startDate,
            endDate: endDate,
            companyAddress: companyAddress,
            companyEmail: companyEmail,
            companyPhone: companyPhone
        )
    }
    
    private func generateSinglePageHistoriesHTML(tabName: String, entries: [HistoryEntry], startDate: Date?, endDate: Date?, companyAddress: String?, companyEmail: String?, companyPhone: String?) throws -> String {
        guard let templatePath = Bundle.main.path(forResource: "ledger_template", ofType: "html"),
              let templateContent = try? String(contentsOfFile: templatePath, encoding: .utf8) else {
            throw LedgerGenerationError.templateNotFound
        }
        
        return try populateHistoriesTemplate(
            templateContent,
            tabName: tabName,
            entries: entries,
            startDate: startDate,
            endDate: endDate,
            companyAddress: companyAddress,
            companyEmail: companyEmail,
            companyPhone: companyPhone,
            isFirstPage: true,
            showSummary: true, // Single page = last page, so show summary
            showEntityInfo: true // Single page = first page, so show entity info
        )
    }
    
    private func generateMultiPageHistoriesHTMLArray(tabName: String, entries: [HistoryEntry], startDate: Date?, endDate: Date?, companyAddress: String?, companyEmail: String?, companyPhone: String?) throws -> [String] {
        var htmlPages: [String] = []
        
        // First page with up to 20 items
        let firstPageItems = Array(entries.prefix(maxItemsForFirstPage))
        var remainingEntries = Array(entries.dropFirst(maxItemsForFirstPage))
        let isOnlyPage = remainingEntries.isEmpty
        let firstPageHTML = try populateHistoriesTemplate(
            loadTemplate(isFirstPage: true),
            tabName: tabName,
            entries: firstPageItems,
            startDate: startDate,
            endDate: endDate,
            companyAddress: companyAddress,
            companyEmail: companyEmail,
            companyPhone: companyPhone,
            isFirstPage: true,
            showSummary: isOnlyPage, // Show summary only if this is the only page
            showEntityInfo: true // First page shows entity info
        )
        htmlPages.append(firstPageHTML)
        
        // Middle pages with continuation items
        while remainingEntries.count > maxItemsPerContinuationPage {
            let pageItems = Array(remainingEntries.prefix(maxItemsPerContinuationPage))
            let middlePageHTML = try populateHistoriesTemplate(
                loadTemplate(isFirstPage: false),
                tabName: tabName,
                entries: pageItems,
                startDate: startDate,
                endDate: endDate,
                companyAddress: companyAddress,
                companyEmail: companyEmail,
                companyPhone: companyPhone,
                isFirstPage: false,
                showSummary: false, // Summary only on last page
                showEntityInfo: false // Not first page
            )
            htmlPages.append(middlePageHTML)
            remainingEntries = Array(remainingEntries.dropFirst(maxItemsPerContinuationPage))
        }
        
        // Last page with remaining items + summary
        if !remainingEntries.isEmpty {
            let lastPageHTML = try populateHistoriesTemplate(
                loadTemplate(isFirstPage: false),
                tabName: tabName,
                entries: remainingEntries,
                startDate: startDate,
                endDate: endDate,
                companyAddress: companyAddress,
                companyEmail: companyEmail,
                companyPhone: companyPhone,
                isFirstPage: false,
                showSummary: true, // Last page shows summary
                showEntityInfo: false, // Not first page
                allEntriesForSummary: entries // Use all entries for summary calculation
            )
            htmlPages.append(lastPageHTML)
        } else {
            // If no remaining items, add a summary-only page
            let summaryPageHTML = try populateHistoriesTemplate(
                loadTemplate(isFirstPage: false),
                tabName: tabName,
                entries: [],
                startDate: startDate,
                endDate: endDate,
                companyAddress: companyAddress,
                companyEmail: companyEmail,
                companyPhone: companyPhone,
                isFirstPage: false,
                showSummary: true, // Last page shows summary
                showEntityInfo: false, // Not first page
                allEntriesForSummary: entries
            )
            htmlPages.append(summaryPageHTML)
        }
        
        return htmlPages
    }
    
    private func generateSinglePageHTML(for entity: EntityProfile, entityType: EntityType, transactions: [EntityTransaction], startDate: Date?, endDate: Date?, companyAddress: String?, companyEmail: String?, companyPhone: String?) throws -> String {
        guard let templatePath = Bundle.main.path(forResource: "ledger_template", ofType: "html"),
              let templateContent = try? String(contentsOfFile: templatePath, encoding: .utf8) else {
            throw LedgerGenerationError.templateNotFound
        }
        
        return try populateTemplate(
            templateContent,
            for: entity,
            entityType: entityType,
            transactions: transactions,
            startDate: startDate,
            endDate: endDate,
            companyAddress: companyAddress,
            companyEmail: companyEmail,
            companyPhone: companyPhone,
            isFirstPage: true,
            showSummary: true, // Single page = last page, so show summary
            showEntityInfo: true // Single page = first page, so show entity info
        )
    }
    
    private func generateMultiPageHTMLArray(for entity: EntityProfile, entityType: EntityType, transactions: [EntityTransaction], startDate: Date?, endDate: Date?, companyAddress: String?, companyEmail: String?, companyPhone: String?) throws -> [String] {
        var htmlPages: [String] = []
        
        // First page with up to 20 items
        let firstPageItems = Array(transactions.prefix(maxItemsForFirstPage))
        var remainingTransactions = Array(transactions.dropFirst(maxItemsForFirstPage))
        let isOnlyPage = remainingTransactions.isEmpty // Check after creating remainingTransactions
        let firstPageHTML = try populateTemplate(
            loadTemplate(isFirstPage: true),
            for: entity,
            entityType: entityType,
            transactions: firstPageItems,
            startDate: startDate,
            endDate: endDate,
            companyAddress: companyAddress,
            companyEmail: companyEmail,
            companyPhone: companyPhone,
            isFirstPage: true,
            showSummary: isOnlyPage, // Show summary only if this is the only page
            showEntityInfo: true // First page shows entity info
        )
        htmlPages.append(firstPageHTML)
        
        // Middle pages with continuation items
        while remainingTransactions.count > maxItemsPerContinuationPage {
            let pageItems = Array(remainingTransactions.prefix(maxItemsPerContinuationPage))
            let middlePageHTML = try populateTemplate(
                loadTemplate(isFirstPage: false),
                for: entity,
                entityType: entityType,
                transactions: pageItems,
                startDate: startDate,
                endDate: endDate,
                companyAddress: companyAddress,
                companyEmail: companyEmail,
                companyPhone: companyPhone,
                isFirstPage: false,
                showSummary: false, // Summary only on last page
                showEntityInfo: false // Not first page
            )
            htmlPages.append(middlePageHTML)
            remainingTransactions = Array(remainingTransactions.dropFirst(maxItemsPerContinuationPage))
        }
        
        // Last page with remaining items + summary
        if !remainingTransactions.isEmpty {
            let lastPageHTML = try populateTemplate(
                loadTemplate(isFirstPage: false),
                for: entity,
                entityType: entityType,
                transactions: remainingTransactions,
                startDate: startDate,
                endDate: endDate,
                companyAddress: companyAddress,
                companyEmail: companyEmail,
                companyPhone: companyPhone,
                isFirstPage: false,
                showSummary: true, // Last page shows summary
                showEntityInfo: false, // Not first page
                allTransactionsForSummary: transactions // Use all transactions for summary calculation
            )
            htmlPages.append(lastPageHTML)
        } else {
            // If no remaining items, add a summary-only page
            let summaryPageHTML = try populateTemplate(
                loadTemplate(isFirstPage: false),
                for: entity,
                entityType: entityType,
                transactions: [],
                startDate: startDate,
                endDate: endDate,
                companyAddress: companyAddress,
                companyEmail: companyEmail,
                companyPhone: companyPhone,
                isFirstPage: false,
                showSummary: true, // Last page shows summary
                showEntityInfo: false, // Not first page
                allTransactionsForSummary: transactions
            )
            htmlPages.append(summaryPageHTML)
        }
        
        return htmlPages
    }
    
    private func loadTemplate(isFirstPage: Bool) -> String {
        guard let templatePath = Bundle.main.path(forResource: "ledger_template", ofType: "html"),
              let templateContent = try? String(contentsOfFile: templatePath, encoding: .utf8) else {
            return ""
        }
        return templateContent
    }
    
    private func populateTemplate(_ template: String, for entity: EntityProfile, entityType: EntityType, transactions: [EntityTransaction], startDate: Date?, endDate: Date?, companyAddress: String?, companyEmail: String?, companyPhone: String?, isFirstPage: Bool = true, showSummary: Bool = true, showEntityInfo: Bool = true, allTransactionsForSummary: [EntityTransaction]? = nil) throws -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd, yyyy"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        
        let periodStart = startDate != nil ? dateFormatter.string(from: startDate!) : "Forever"
        let periodEnd = endDate != nil ? dateFormatter.string(from: endDate!) : "Forever"
        
        let generatedDate = dateFormatter.string(from: Date())
        
        var html = template
        
        // Replace header placeholders
        if let address = companyAddress, !address.isEmpty {
            html = html.replacingOccurrences(of: "{{company_address}}", with: address)
        } else {
            html = html.replacingOccurrences(of: "{{company_address}}", with: "123 Business Avenue, Suite 100, City, State 12345")
        }
        
        if let email = companyEmail, !email.isEmpty, let phone = companyPhone, !phone.isEmpty {
            html = html.replacingOccurrences(of: "Email: info@aromex.com | Phone: (123) 456-7890", with: "Email: \(email) | Phone: \(phone)")
        }
        
        // Replace entity info (only on first page)
        if showEntityInfo {
            html = html.replacingOccurrences(of: "{{entity_name}}", with: entity.name)
            html = html.replacingOccurrences(of: "{{entity_type}}", with: "") // Don't show entity type
            
            if !entity.phone.isEmpty {
                html = html.replacingOccurrences(of: "{{entity_phone}}", with: entity.phone)
                html = html.replacingOccurrences(of: "<div id=\"entity_phone_section\">{{entity_phone}}</div>", with: "<div>Phone: \(entity.phone)</div>")
            } else {
                html = html.replacingOccurrences(of: "<div id=\"entity_phone_section\">{{entity_phone}}</div>", with: "")
            }
            
            if !entity.email.isEmpty {
                html = html.replacingOccurrences(of: "{{entity_email}}", with: entity.email)
                html = html.replacingOccurrences(of: "<div id=\"entity_email_section\">{{entity_email}}</div>", with: "<div>Email: \(entity.email)</div>")
            } else {
                html = html.replacingOccurrences(of: "<div id=\"entity_email_section\">{{entity_email}}</div>", with: "")
            }
            
            // Replace period info (only on first page)
            html = html.replacingOccurrences(of: "{{period_start}}", with: periodStart)
            html = html.replacingOccurrences(of: "{{period_end}}", with: periodEnd)
            html = html.replacingOccurrences(of: "{{generated_date}}", with: generatedDate)
            
            // Remove placeholder comments to show entity section
            html = html.replacingOccurrences(of: "<!--{{ENTITY_SECTION_START}}-->", with: "")
            html = html.replacingOccurrences(of: "<!--{{ENTITY_SECTION_END}}-->", with: "")
        } else {
            // Remove entire entity section (including comments) on continuation pages
            let entitySectionStart = "<!--{{ENTITY_SECTION_START}}-->"
            let entitySectionEnd = "<!--{{ENTITY_SECTION_END}}-->"
            if let startRange = html.range(of: entitySectionStart),
               let endRange = html.range(of: entitySectionEnd) {
                html.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            }
        }
        
        // Generate transaction rows
        let transactionsHTML = generateTransactionRows(for: transactions, entityId: entity.id, entityName: entity.name)
        html = html.replacingOccurrences(of: "{{transactions}}", with: transactionsHTML)
        
        // Calculate summary (use all transactions if provided, otherwise just page transactions)
        if showSummary {
            let summaryTransactions = allTransactionsForSummary ?? transactions
            let (totalInflow, totalOutflow, _, totalCredit) = calculateSummary(transactions: summaryTransactions, entityId: entity.id)
            html = html.replacingOccurrences(of: "{{total_inflow}}", with: "$\(formatAmount(totalInflow))")
            html = html.replacingOccurrences(of: "{{total_outflow}}", with: "$\(formatAmount(totalOutflow))")
            // Temporarily disabled: html = html.replacingOccurrences(of: "{{balance_due}}", with: "$\(formatAmount(abs(totalCredit)))")
            // Remove placeholder comments to show summary and footer sections
            html = html.replacingOccurrences(of: "<!--{{SUMMARY_SECTION_START}}-->", with: "")
            html = html.replacingOccurrences(of: "<!--{{SUMMARY_SECTION_END}}-->", with: "")
            html = html.replacingOccurrences(of: "<!--{{FOOTER_SECTION_START}}-->", with: "")
            html = html.replacingOccurrences(of: "<!--{{FOOTER_SECTION_END}}-->", with: "")
        } else {
            // Remove entire summary and footer sections (including comments) for continuation pages
            let summarySectionStart = "<!--{{SUMMARY_SECTION_START}}-->"
            let summarySectionEnd = "<!--{{SUMMARY_SECTION_END}}-->"
            if let startRange = html.range(of: summarySectionStart),
               let endRange = html.range(of: summarySectionEnd) {
                html.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            }
            
            let footerSectionStart = "<!--{{FOOTER_SECTION_START}}-->"
            let footerSectionEnd = "<!--{{FOOTER_SECTION_END}}-->"
            if let startRange = html.range(of: footerSectionStart),
               let endRange = html.range(of: footerSectionEnd) {
                html.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            }
        }
        
        return html
    }
    
    // Populate template for histories ledger (with entity names in rows)
    private func populateHistoriesTemplate(_ template: String, tabName: String, entries: [HistoryEntry], startDate: Date?, endDate: Date?, companyAddress: String?, companyEmail: String?, companyPhone: String?, isFirstPage: Bool = true, showSummary: Bool = true, showEntityInfo: Bool = true, allEntriesForSummary: [HistoryEntry]? = nil) throws -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd, yyyy"
        
        let periodStart = startDate != nil ? dateFormatter.string(from: startDate!) : "Forever"
        let periodEnd = endDate != nil ? dateFormatter.string(from: endDate!) : "Forever"
        let generatedDate = dateFormatter.string(from: Date())
        
        var html = template
        
        // Replace header placeholders
        if let address = companyAddress, !address.isEmpty {
            html = html.replacingOccurrences(of: "{{company_address}}", with: address)
        } else {
            html = html.replacingOccurrences(of: "{{company_address}}", with: "123 Business Avenue, Suite 100, City, State 12345")
        }
        
        if let email = companyEmail, !email.isEmpty, let phone = companyPhone, !phone.isEmpty {
            html = html.replacingOccurrences(of: "Email: info@aromex.com | Phone: (123) 456-7890", with: "Email: \(email) | Phone: \(phone)")
        }
        
        // Replace entity info section for histories (use tab name as entity name)
        if showEntityInfo {
            html = html.replacingOccurrences(of: "{{entity_name}}", with: tabName)
            html = html.replacingOccurrences(of: "{{entity_type}}", with: "")
            html = html.replacingOccurrences(of: "<div id=\"entity_phone_section\">{{entity_phone}}</div>", with: "")
            html = html.replacingOccurrences(of: "<div id=\"entity_email_section\">{{entity_email}}</div>", with: "")
            
            // Replace period info (only on first page)
            html = html.replacingOccurrences(of: "{{period_start}}", with: periodStart)
            html = html.replacingOccurrences(of: "{{period_end}}", with: periodEnd)
            html = html.replacingOccurrences(of: "{{generated_date}}", with: generatedDate)
            
            // Remove placeholder comments to show entity section
            html = html.replacingOccurrences(of: "<!--{{ENTITY_SECTION_START}}-->", with: "")
            html = html.replacingOccurrences(of: "<!--{{ENTITY_SECTION_END}}-->", with: "")
        } else {
            // Remove entire entity section (including comments) on continuation pages
            let entitySectionStart = "<!--{{ENTITY_SECTION_START}}-->"
            let entitySectionEnd = "<!--{{ENTITY_SECTION_END}}-->"
            if let startRange = html.range(of: entitySectionStart),
               let endRange = html.range(of: entitySectionEnd) {
                html.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            }
        }
        
        // Generate transaction rows with entity names
        let transactionsHTML = generateHistoryTransactionRows(for: entries, tabName: tabName)
        html = html.replacingOccurrences(of: "{{transactions}}", with: transactionsHTML)
        
        // Calculate summary (use all entries if provided, otherwise just page entries)
        if showSummary {
            let summaryEntries = allEntriesForSummary ?? entries
            let (totalInflow, totalOutflow, _, totalCredit) = calculateHistoriesSummary(entries: summaryEntries)
            html = html.replacingOccurrences(of: "{{total_inflow}}", with: "$\(formatAmount(totalInflow))")
            html = html.replacingOccurrences(of: "{{total_outflow}}", with: "$\(formatAmount(totalOutflow))")
            // Temporarily disabled: html = html.replacingOccurrences(of: "{{balance_due}}", with: "$\(formatAmount(abs(totalCredit)))")
            // Remove placeholder comments to show summary and footer sections
            html = html.replacingOccurrences(of: "<!--{{SUMMARY_SECTION_START}}-->", with: "")
            html = html.replacingOccurrences(of: "<!--{{SUMMARY_SECTION_END}}-->", with: "")
            html = html.replacingOccurrences(of: "<!--{{FOOTER_SECTION_START}}-->", with: "")
            html = html.replacingOccurrences(of: "<!--{{FOOTER_SECTION_END}}-->", with: "")
        } else {
            // Remove entire summary and footer sections (including comments) for continuation pages
            let summarySectionStart = "<!--{{SUMMARY_SECTION_START}}-->"
            let summarySectionEnd = "<!--{{SUMMARY_SECTION_END}}-->"
            if let startRange = html.range(of: summarySectionStart),
               let endRange = html.range(of: summarySectionEnd) {
                html.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            }
            
            let footerSectionStart = "<!--{{FOOTER_SECTION_START}}-->"
            let footerSectionEnd = "<!--{{FOOTER_SECTION_END}}-->"
            if let startRange = html.range(of: footerSectionStart),
               let endRange = html.range(of: footerSectionEnd) {
                html.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            }
        }
        
        return html
    }
    
    // Calculate summary for histories ledger
    private func calculateHistoriesSummary(entries: [HistoryEntry]) -> (Double, Double, Double, Double) {
        var totalInflow: Double = 0.0
        var totalOutflow: Double = 0.0
        var totalCredit: Double = 0.0 // Balance due
        
        for entry in entries {
            let transaction = entry.transaction
            let entityId = entry.entityId
            
            switch transaction.type {
            case .sale:
                let amount = transaction.paid ?? transaction.grandTotal ?? transaction.amount
                totalInflow += amount
                // Add credit for sales (customer owes us)
                if let credit = transaction.credit, abs(credit) > 0.01 {
                    totalCredit += credit
                }
            case .purchase, .expense:
                let amount = transaction.paid ?? transaction.grandTotal ?? transaction.amount
                totalOutflow += amount
                // Subtract credit for purchases (we owe supplier)
                if let credit = transaction.credit, abs(credit) > 0.01 {
                    totalCredit -= credit
                }
            case .middleman:
                let total = (transaction.middlemanCash ?? 0) + (transaction.middlemanBank ?? 0) + (transaction.middlemanCreditCard ?? 0)
                if let unit = transaction.middlemanUnit {
                    if unit == "give" {
                        totalOutflow += total
                    } else {
                        totalInflow += total
                    }
                }
                // Add/subtract middleman credit based on unit (give = negative, receive = positive)
                if let credit = transaction.middlemanCredit, abs(credit) > 0.01 {
                    if let unit = transaction.middlemanUnit {
                        if unit == "give" {
                            totalCredit -= credit // We owe (negative)
                        } else {
                            totalCredit += credit // They owe us (positive)
                        }
                    } else {
                        totalCredit -= credit // Default to negative if unit not specified
                    }
                }
            case .currencyRegular, .currencyExchange:
                // Use the same logic as formatTransactionAmount
                let isEntityGiver = transaction.giver == entityId
                let isEntityTaker = transaction.taker == entityId
                if isEntityTaker {
                    totalOutflow += transaction.amount
                } else if isEntityGiver {
                    totalInflow += transaction.amount
                } else {
                    // Fallback: based on role
                    if transaction.role == "giver" {
                        totalInflow += transaction.amount
                    } else {
                        totalOutflow += transaction.amount
                    }
                }
            case .balanceAdjustment:
                if let balances = transaction.balancesAfterTransaction,
                   let adjustmentType = balances["adjustmentType"] as? String {
                    if adjustmentType == "To Receive" {
                        totalInflow += abs(transaction.amount)
                    } else {
                        totalOutflow += abs(transaction.amount)
                    }
                }
            }
        }
        
        let netBalance = totalInflow - totalOutflow
        return (totalInflow, totalOutflow, netBalance, totalCredit)
    }
    
    private func generateTransactionRows(for transactions: [EntityTransaction], entityId: String, entityName: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd, yyyy"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        
        var rows = ""
        
        for transaction in transactions {
            let dateStr = dateFormatter.string(from: transaction.date)
            let timeStr = timeFormatter.string(from: transaction.date)
            
            // Don't show type badge for middleman transactions
            let typeBadge = transaction.type == .middleman ? "" : getTransactionTypeBadge(transaction.type)
            let description = getTransactionDescription(transaction)
            let paymentMethod = getPaymentMethod(transaction, entityId: entityId)
            let (amountHTML, amountClass) = formatTransactionAmount(transaction, entityId: entityId)
            let creditHTML = formatCreditAmount(transaction)
            
            rows += """
            <tr>
                <td>\(dateStr)</td>
                <td>\(timeStr)</td>
                <td>\(entityName)</td>
                <td>\(typeBadge)</td>
                <td>\(description)</td>
                <td class="payment-method">\(paymentMethod.isEmpty ? "-" : paymentMethod)</td>
                <td class="text-right \(amountClass)">\(amountHTML)</td>
                <td class="text-right">\(creditHTML)</td>
            </tr>
            """
        }
        
        return rows
    }
    
    // Generate transaction rows for histories (with entity names)
    private func generateHistoryTransactionRows(for entries: [HistoryEntry], tabName: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd, yyyy"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        
        var rows = ""
        
        for entry in entries {
            let transaction = entry.transaction
            let dateStr = dateFormatter.string(from: transaction.date)
            let timeStr = timeFormatter.string(from: transaction.date)
            let entityName = entry.entityName
            
            // Don't show type badge for middleman transactions
            let typeBadge = transaction.type == .middleman ? "" : getTransactionTypeBadge(transaction.type)
            let description = getTransactionDescription(transaction)
            
            // For histories ledger, we need to determine entity ID context for payment method
            // Use the first entity ID from entries or entry's own entity ID
            let entityId = entry.entityId
            let paymentMethod = getPaymentMethod(transaction, entityId: entityId)
            let (amountHTML, amountClass) = formatTransactionAmount(transaction, entityId: entityId, tabName: tabName)
            let creditHTML = formatCreditAmount(transaction)
            
            rows += """
            <tr>
                <td>\(dateStr)</td>
                <td>\(timeStr)</td>
                <td>\(entityName)</td>
                <td>\(typeBadge)</td>
                <td>\(description)</td>
                <td class="payment-method">\(paymentMethod.isEmpty ? "-" : paymentMethod)</td>
                <td class="text-right \(amountClass)">\(amountHTML)</td>
                <td class="text-right">\(creditHTML)</td>
            </tr>
            """
        }
        
        return rows
    }
    
    private func getTransactionTypeBadge(_ type: EntityTransactionType) -> String {
        let colorMap: [EntityTransactionType: String] = [
            .purchase: "#34C759",
            .sale: "#007AFF",
            .middleman: "#CC6633",
            .currencyRegular: "#FF9500",
            .currencyExchange: "#AF52DE",
            .expense: "#FF3B30",
            .balanceAdjustment: "#5856D6"
        ]
        
        let color = colorMap[type] ?? "#86868b"
        
        return """
        <span class="transaction-type" style="background-color: \(color);">
            \(type.rawValue)
        </span>
        """
    }
    
    private func getTransactionDescription(_ transaction: EntityTransaction) -> String {
        var description = ""
        
        switch transaction.type {
        case .purchase, .sale:
            if let orderNum = transaction.orderNumber {
                description = "Order #\(orderNum)"
            } else {
                description = transaction.type.rawValue
            }
            if let notes = transaction.notes, !notes.isEmpty {
                description += " - \(notes)"
            }
        case .middleman:
            // For middleman, only show notes
            description = transaction.notes ?? ""
        case .currencyRegular, .currencyExchange:
            // For currency transactions, only show notes
            description = transaction.notes ?? ""
        case .expense:
            description = transaction.notes ?? "Expense"
        case .balanceAdjustment:
            description = transaction.notes ?? "Balance Adjustment"
        }
        
        return description.isEmpty ? transaction.type.rawValue : description
    }
    
    private func getPaymentMethod(_ transaction: EntityTransaction, entityId: String) -> String {
        var methods: [String] = []
        
        switch transaction.type {
        case .purchase, .sale, .expense:
            if let cash = transaction.cashPaid, cash > 0 {
                methods.append("Cash: $\(formatAmount(cash))")
            }
            if let bank = transaction.bankPaid, bank > 0 {
                methods.append("Bank: $\(formatAmount(bank))")
            }
            if let card = transaction.creditCardPaid, card > 0 {
                methods.append("Card: $\(formatAmount(card))")
            }
            // For all transaction types, show payment methods if available
            if methods.isEmpty {
                methods.append("-")
            }
        case .middleman:
            var middlemanMethods: [String] = []
            if let cash = transaction.middlemanCash, cash > 0 {
                middlemanMethods.append("Cash: $\(formatAmount(cash))")
            }
            if let bank = transaction.middlemanBank, bank > 0 {
                middlemanMethods.append("Bank: $\(formatAmount(bank))")
            }
            if let card = transaction.middlemanCreditCard, card > 0 {
                middlemanMethods.append("Card: $\(formatAmount(card))")
            }
            methods = middlemanMethods.isEmpty ? ["-"] : middlemanMethods
        case .currencyRegular, .currencyExchange:
            // For currency transactions, check if giver or taker is Myself CASH or Myself BANK
            var paymentMethod: String? = nil
            
            // Check giver
            if let giver = transaction.giver {
                if giver == "myself_special_id" {
                    paymentMethod = "Cash"
                } else if giver == "myself_bank_special_id" {
                    paymentMethod = "Bank"
                }
            }
            
            // Check taker if giver didn't match
            if paymentMethod == nil, let taker = transaction.taker {
                if taker == "myself_special_id" {
                    paymentMethod = "Cash"
                } else if taker == "myself_bank_special_id" {
                    paymentMethod = "Bank"
                }
            }
            
            // Default to "Cash" if neither giver nor taker matched
            methods.append(paymentMethod ?? "Cash")
        case .balanceAdjustment:
            methods.append("-")
        }
        
        return methods.joined(separator: ", ")
    }
    
    private func formatCreditAmount(_ transaction: EntityTransaction) -> String {
        var creditAmount: Double? = nil
        var creditColor: String = "amount-negative"
        
        // Get credit amount based on transaction type
        switch transaction.type {
        case .sale, .purchase:
            creditAmount = transaction.credit
            creditColor = transaction.type == .sale ? "amount-positive" : "amount-negative"
        case .middleman:
            creditAmount = transaction.middlemanCredit
            // Middleman credit color based on unit (give = negative/red, receive = positive/green)
            if let unit = transaction.middlemanUnit {
                creditColor = unit == "give" ? "amount-negative" : "amount-positive"
            } else {
                creditColor = "amount-negative"
            }
        default:
            creditAmount = nil
        }
        
        // Show credit amount if it exists and is not 0
        if let credit = creditAmount, abs(credit) > 0.01 {
            return "<span class=\"\(creditColor)\">$\(formatAmount(abs(credit)))</span>"
        }
        return "-"
    }
    
    private func formatTransactionAmount(_ transaction: EntityTransaction, entityId: String, tabName: String? = nil) -> (String, String) {
        // Returns (HTML string, CSS class name)
        switch transaction.type {
        case .sale:
            // Sale: always positive (money coming in) with green color
            let amount = transaction.paid ?? transaction.grandTotal ?? transaction.amount
            if abs(amount) < 0.01 {
                return ("$\(formatAmount(amount))", "amount-neutral")
            }
            return ("+$\(formatAmount(amount))", "amount-positive")
        case .purchase:
            // Purchase: always negative (money going out) with red color
            let amount = transaction.paid ?? transaction.grandTotal ?? transaction.amount
            if abs(amount) < 0.01 {
                return ("$\(formatAmount(amount))", "amount-neutral")
            }
            return ("-$\(formatAmount(amount))", "amount-negative")
        case .expense:
            // Expense: always negative
            if abs(transaction.amount) < 0.01 {
                return ("$\(formatAmount(transaction.amount))", "amount-neutral")
            }
            return ("-$\(formatAmount(transaction.amount))", "amount-negative")
        case .middleman:
            // Middleman: based on unit (give = -, otherwise +)
            let total = (transaction.middlemanCash ?? 0) + (transaction.middlemanBank ?? 0) + (transaction.middlemanCreditCard ?? 0)
            if abs(total) < 0.01 {
                return ("$\(formatAmount(total))", "amount-neutral")
            }
            if let unit = transaction.middlemanUnit {
                if unit == "give" {
                    return ("-$\(formatAmount(total))", "amount-negative") // Red
                } else {
                    return ("+$\(formatAmount(total))", "amount-positive") // Green
                }
            }
            let isPositive = total >= 0
            return ("$\(formatAmount(total))", isPositive ? "amount-positive" : "amount-negative")
        case .currencyRegular, .currencyExchange:
            // Currency: if entity is taker -> - (red), if entity is giver -> + (green)
            // Special case: In cash/bank tab, if neither giver nor taker is myself, show no sign and grey color
            if abs(transaction.amount) < 0.01 {
                return ("$\(formatAmount(transaction.amount))", "amount-neutral")
            }
            
            // Check if this is cash or bank tab and neither giver nor taker is myself
            if let tab = tabName, (tab == "Cash" || tab == "Bank") {
                let giver = transaction.giver ?? ""
                let taker = transaction.taker ?? ""
                let giverIsMyself = giver == "myself_special_id" || giver == "myself_bank_special_id"
                let takerIsMyself = taker == "myself_special_id" || taker == "myself_bank_special_id"
                
                // If neither is myself, show no sign and grey color
                if !giverIsMyself && !takerIsMyself {
                    return ("$\(formatAmount(transaction.amount))", "amount-neutral")
                }
            }
            
            let isEntityGiver = transaction.giver == entityId
            let isEntityTaker = transaction.taker == entityId
            if isEntityTaker {
                return ("-$\(formatAmount(transaction.amount))", "amount-negative") // Red
            } else if isEntityGiver {
                return ("+$\(formatAmount(transaction.amount))", "amount-positive") // Green
            }
            // Fallback: based on role
            let isPositive = transaction.role == "giver"
            let sign = isPositive ? "+" : "-"
            return ("\(sign)$\(formatAmount(transaction.amount))", isPositive ? "amount-positive" : "amount-negative")
        case .balanceAdjustment:
            // Balance adjustment: based on adjustment type
            if abs(transaction.amount) < 0.01 {
                return ("$\(formatAmount(transaction.amount))", "amount-neutral")
            }
            if let balances = transaction.balancesAfterTransaction,
               let adjustmentType = balances["adjustmentType"] as? String {
                let isPositive = adjustmentType == "To Receive"
                let sign = isPositive ? "+" : "-"
                let amount = abs(transaction.amount)
                return ("\(sign)$\(formatAmount(amount))", isPositive ? "amount-positive" : "amount-negative")
            }
            let isPositive = transaction.amount >= 0
            return ("$\(formatAmount(transaction.amount))", isPositive ? "amount-positive" : "amount-negative")
        }
    }
    
    private func calculateSummary(transactions: [EntityTransaction], entityId: String) -> (Double, Double, Double, Double) {
        var totalInflow: Double = 0.0
        var totalOutflow: Double = 0.0
        var totalCredit: Double = 0.0 // Balance due
        
        for transaction in transactions {
            switch transaction.type {
            case .sale:
                let amount = transaction.paid ?? transaction.grandTotal ?? transaction.amount
                totalInflow += amount
                // Add credit for sales (customer owes us)
                if let credit = transaction.credit, abs(credit) > 0.01 {
                    totalCredit += credit
                }
            case .purchase, .expense:
                let amount = transaction.paid ?? transaction.grandTotal ?? transaction.amount
                totalOutflow += amount
                // Subtract credit for purchases (we owe supplier)
                if let credit = transaction.credit, abs(credit) > 0.01 {
                    totalCredit -= credit
                }
            case .middleman:
                let total = (transaction.middlemanCash ?? 0) + (transaction.middlemanBank ?? 0) + (transaction.middlemanCreditCard ?? 0)
                if let unit = transaction.middlemanUnit {
                    if unit == "give" {
                        totalOutflow += total
                    } else {
                        totalInflow += total
                    }
                }
                // Add/subtract middleman credit based on unit (give = negative, receive = positive)
                if let credit = transaction.middlemanCredit, abs(credit) > 0.01 {
                    if let unit = transaction.middlemanUnit {
                        if unit == "give" {
                            totalCredit -= credit // We owe (negative)
                        } else {
                            totalCredit += credit // They owe us (positive)
                        }
                    } else {
                        totalCredit -= credit // Default to negative if unit not specified
                    }
                }
            case .currencyRegular, .currencyExchange:
                // Use the same logic as formatTransactionAmount
                let isEntityGiver = transaction.giver == entityId
                let isEntityTaker = transaction.taker == entityId
                if isEntityTaker {
                    totalOutflow += transaction.amount
                } else if isEntityGiver {
                    totalInflow += transaction.amount
                } else {
                    // Fallback: based on role
                    if transaction.role == "giver" {
                        totalInflow += transaction.amount
                    } else {
                        totalOutflow += transaction.amount
                    }
                }
            case .balanceAdjustment:
                if let balances = transaction.balancesAfterTransaction,
                   let adjustmentType = balances["adjustmentType"] as? String {
                    if adjustmentType == "To Receive" {
                        totalInflow += abs(transaction.amount)
                    } else {
                        totalOutflow += abs(transaction.amount)
                    }
                }
            }
        }
        
        let netBalance = totalInflow - totalOutflow
        return (totalInflow, totalOutflow, netBalance, totalCredit)
    }
    
    private func formatNetBalance(_ balance: Double) -> String {
        let formatted = String(format: "$%.2f", abs(balance))
        if balance >= 0 {
            return "<span class=\"amount-positive\">+\(formatted)</span>"
        } else {
            return "<span class=\"amount-negative\">-\(formatted)</span>"
        }
    }
}

enum LedgerGenerationError: Error {
    case templateNotFound
    case invalidData
    case generationFailed(String)
}
