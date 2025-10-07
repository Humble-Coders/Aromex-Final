import Foundation
import PDFKit

class BillGenerator {
    
    // Threshold for deciding which template to use
    private let maxItemsForSinglePage = 8
    private let maxItemsForShortFirstPage = 13  // 9-13 items
    private let maxItemsForLongFirstPage = 16  // 14-16 items: first page without totals
    private let maxItemsPerContinuationPage = 18
    
    func generateBillHTML(for purchase: Purchase) throws -> [String] {
        let itemCount = purchase.purchasedPhones.count
        
        // Single page: 8 or fewer items
        if itemCount <= maxItemsForSinglePage {
            return [try generateSinglePageHTML(for: purchase)]
        }
        
        // 9-13 items: put full table on first page, totals/payment/notes on second (footer) page
        if itemCount <= maxItemsForShortFirstPage {
            let firstPageHTML = try generateFirstPage(for: purchase, items: purchase.purchasedPhones)
            let footerPageHTML = try generateFooterPage(for: purchase)
            return [firstPageHTML, footerPageHTML]
        }
        
        // Multi-page: 14+ items
        return try generateMultiPageHTMLArray(for: purchase)
    }
    
    private func generateSinglePageHTML(for purchase: Purchase) throws -> String {
        guard let templatePath = Bundle.main.path(forResource: "invoice_single_page", ofType: "html"),
              let templateContent = try? String(contentsOfFile: templatePath, encoding: .utf8) else {
            throw BillGenerationError.templateNotFound
        }
        
        return try populateTemplate(templateContent, with: purchase, items: purchase.purchasedPhones)
    }
    
    // Removed short-first-page generator; 9-13 case uses existing first + footer templates
    
    private func generateMultiPageHTMLArray(for purchase: Purchase) throws -> [String] {
        var htmlPages: [String] = []
        let allItems = purchase.purchasedPhones
        
        // First page with up to 16 items
        let firstPageItems = Array(allItems.prefix(maxItemsForLongFirstPage))
        let firstPageHTML = try generateFirstPage(for: purchase, items: firstPageItems)
        htmlPages.append(firstPageHTML)
        
        var remainingItems = Array(allItems.dropFirst(maxItemsForLongFirstPage))
        
        // Middle pages with continuation items
        while remainingItems.count > maxItemsPerContinuationPage {
            let pageItems = Array(remainingItems.prefix(maxItemsPerContinuationPage))
            let middlePageHTML = try generateMiddlePage(for: purchase, items: pageItems)
            htmlPages.append(middlePageHTML)
            remainingItems = Array(remainingItems.dropFirst(maxItemsPerContinuationPage))
        }
        
        // Last page with remaining items + totals + payment
        if !remainingItems.isEmpty {
            let lastPageHTML = try generateLastPage(for: purchase, items: remainingItems)
            htmlPages.append(lastPageHTML)
        } else {
            let footerPageHTML = try generateFooterPage(for: purchase)
            htmlPages.append(footerPageHTML)
        }
        
        return htmlPages
    }
    
    private func generateFirstPage(for purchase: Purchase, items: [[String: Any]]) throws -> String {
        guard let templatePath = Bundle.main.path(forResource: "invoice_first_page", ofType: "html"),
              let templateContent = try? String(contentsOfFile: templatePath, encoding: .utf8) else {
            throw BillGenerationError.templateNotFound
        }
        
        return try populateTemplate(templateContent, with: purchase, items: items)
    }
    
    private func generateMiddlePage(for purchase: Purchase, items: [[String: Any]]) throws -> String {
        guard let templatePath = Bundle.main.path(forResource: "invoice_middle_page", ofType: "html"),
              let templateContent = try? String(contentsOfFile: templatePath, encoding: .utf8) else {
            throw BillGenerationError.templateNotFound
        }
        
        return try populateTemplate(templateContent, with: purchase, items: items)
    }
    
    private func generateLastPage(for purchase: Purchase, items: [[String: Any]]) throws -> String {
        guard let templatePath = Bundle.main.path(forResource: "invoice_last_page", ofType: "html"),
              let templateContent = try? String(contentsOfFile: templatePath, encoding: .utf8) else {
            throw BillGenerationError.templateNotFound
        }
        
        return try populateTemplate(templateContent, with: purchase, items: items)
    }
    
    private func generateFooterPage(for purchase: Purchase) throws -> String {
        guard let templatePath = Bundle.main.path(forResource: "invoice_footer_page", ofType: "html"),
              let templateContent = try? String(contentsOfFile: templatePath, encoding: .utf8) else {
            throw BillGenerationError.templateNotFound
        }
        
        return try populateTemplate(templateContent, with: purchase, items: [])
    }
    
    private func populateTemplate(_ template: String, with purchase: Purchase, items: [[String: Any]]) throws -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd, yyyy"
        let formattedDate = dateFormatter.string(from: purchase.transactionDate)
        
        let itemsHTML = generateItemsRows(for: items)
        
        var html = template
        html = html.replacingOccurrences(of: "{{supplier_name}}", with: purchase.supplierName ?? "N/A")
        html = html.replacingOccurrences(of: "{{order_number}}", with: "ORD-\(purchase.orderNumber)")
        html = html.replacingOccurrences(of: "{{transaction_date}}", with: formattedDate)
        html = html.replacingOccurrences(of: "{{subtotal}}", with: String(format: "%.2f", purchase.subtotal))
        html = html.replacingOccurrences(of: "{{gst_percentage}}", with: String(format: "%.1f", purchase.gstPercentage))
        html = html.replacingOccurrences(of: "{{gst_amount}}", with: String(format: "%.2f", purchase.gstAmount))
        html = html.replacingOccurrences(of: "{{pst_percentage}}", with: String(format: "%.1f", purchase.pstPercentage))
        html = html.replacingOccurrences(of: "{{pst_amount}}", with: String(format: "%.2f", purchase.pstAmount))
        html = html.replacingOccurrences(of: "{{adjustment_amount}}", with: String(format: "%.2f", purchase.adjustmentAmount))
        html = html.replacingOccurrences(of: "{{adjustment_unit}}", with: purchase.adjustmentUnit)
        html = html.replacingOccurrences(of: "{{grand_total}}", with: String(format: "%.2f", purchase.grandTotal))
        html = html.replacingOccurrences(of: "{{notes}}", with: purchase.notes.isEmpty ? "No additional notes" : purchase.notes)
        html = html.replacingOccurrences(of: "{{items}}", with: itemsHTML)

        // Company header info
        if let companyAddress = purchase.companyAddress, !companyAddress.isEmpty {
            html = html.replacingOccurrences(of: "123 Business Avenue, Suite 100, City, State 12345", with: companyAddress)
        }
        if let companyEmail = purchase.companyEmail, !companyEmail.isEmpty,
           let companyPhone = purchase.companyPhone, !companyPhone.isEmpty {
            html = html.replacingOccurrences(of: "Email: info@aromex.com | Phone: (123) 456-7890", with: "Email: \(companyEmail) | Phone: \(companyPhone)")
        }
        
        // Supplier phone in place of entity type
        if let supplierPhone = purchase.supplierPhone, !supplierPhone.isEmpty {
            html = html.replacingOccurrences(of: "{{supplier_entity_type}}", with: supplierPhone)
        }
        
        let cashPaid = purchase.paymentMethods["cash"] as? Double ?? 0.0
        let bankPaid = purchase.paymentMethods["bank"] as? Double ?? 0.0
        let creditCardPaid = purchase.paymentMethods["creditCard"] as? Double ?? 0.0
        let totalPaid = purchase.paymentMethods["totalPaid"] as? Double ?? 0.0
        let remainingCredit = purchase.paymentMethods["remainingCredit"] as? Double ?? 0.0
        
        // Format payment amounts with color for negatives
        html = html.replacingOccurrences(of: "{{payment_cash}}", with: formatAmount(cashPaid))
        html = html.replacingOccurrences(of: "{{payment_bank}}", with: formatAmount(bankPaid))
        html = html.replacingOccurrences(of: "{{payment_credit_card}}", with: formatAmount(creditCardPaid))
        html = html.replacingOccurrences(of: "{{payment_total_paid}}", with: formatAmount(totalPaid))
        html = html.replacingOccurrences(of: "{{payment_remaining_credit}}", with: formatAmount(remainingCredit))
        
        return html
    }
    
    private func formatAmount(_ amount: Double) -> String {
        let absAmount = abs(amount)
        let formattedValue = String(format: "$%.2f", absAmount)
        
        if amount < 0 {
            return "<span class=\"amount-negative\">\(formattedValue)</span>"
        }
        return formattedValue
    }
    
    private func generateItemsRows(for phones: [[String: Any]]) -> String {
        var rows = ""
        
        for phoneData in phones {
            let description = generatePhoneDescription(phoneData)
            let imei = phoneData["imei"] as? String ?? "N/A"
            let unitCost = phoneData["unitCost"] as? Double ?? 0.0
            let total = unitCost
            
            rows += """
            <tr>
                <td><div class="item-description">\(description)</div></td>
                <td>\(imei)</td>
                <td>$\(String(format: "%.2f", unitCost))</td>
                <td>$\(String(format: "%.2f", total))</td>
            </tr>
            """
        }
        
        return rows
    }
    
    private func generatePhoneDescription(_ phoneData: [String: Any]) -> String {
        let brand = phoneData["brand"] as? String ?? "N/A"
        let model = phoneData["model"] as? String ?? "N/A"
        let capacity = phoneData["capacity"] as? String ?? "N/A"
        let capacityUnit = phoneData["capacityUnit"] as? String ?? ""
        
        var description = "\(brand) \(model)"
        
        if !capacity.isEmpty && capacity != "N/A" {
            description += ", \(capacity) \(capacityUnit)"
        }
        
        if let color = phoneData["color"] as? String, !color.isEmpty {
            description += ", \(color)"
        }
        
        if let carrier = phoneData["carrier"] as? String, !carrier.isEmpty {
            description += ", \(carrier)"
        }
        
        return description
    }
}

enum BillGenerationError: Error {
    case templateNotFound
    case invalidData
    case generationFailed(String)
}
