//
//  BillGenerator.swift
//  Aromex
//
//  Created by User on 9/17/25.
//

import Foundation

class BillGenerator {
    
    func generateBillHTML(for purchase: Purchase) throws -> String {
        // Load HTML template
        guard let templatePath = Bundle.main.path(forResource: "invoice_template", ofType: "html"),
              let templateContent = try? String(contentsOfFile: templatePath, encoding: .utf8) else {
            throw BillGenerationError.templateNotFound
        }
        
        // Format date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd, yyyy"
        let formattedDate = dateFormatter.string(from: purchase.transactionDate)
        
        // Generate items HTML
        let itemsHTML = generateItemsRows(for: purchase.purchasedPhones)
        
        // Replace placeholders
        var html = templateContent
        html = html.replacingOccurrences(of: "{{supplier_name}}", with: purchase.supplierName ?? "N/A")
        html = html.replacingOccurrences(of: "{{supplier_entity_type}}", with: "Supplier")
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
        
        // Payment methods
        let cashPaid = purchase.paymentMethods["cash"] as? Double ?? 0.0
        let bankPaid = purchase.paymentMethods["bank"] as? Double ?? 0.0
        let creditCardPaid = purchase.paymentMethods["creditCard"] as? Double ?? 0.0
        let totalPaid = purchase.paymentMethods["totalPaid"] as? Double ?? 0.0
        let remainingCredit = purchase.paymentMethods["remainingCredit"] as? Double ?? 0.0
        
        html = html.replacingOccurrences(of: "{{payment_cash}}", with: String(format: "%.2f", cashPaid))
        html = html.replacingOccurrences(of: "{{payment_bank}}", with: String(format: "%.2f", bankPaid))
        html = html.replacingOccurrences(of: "{{payment_credit_card}}", with: String(format: "%.2f", creditCardPaid))
        html = html.replacingOccurrences(of: "{{payment_total_paid}}", with: String(format: "%.2f", totalPaid))
        html = html.replacingOccurrences(of: "{{payment_remaining_credit}}", with: String(format: "%.2f", remainingCredit))
        
        // Generate middleman details HTML if applicable
        var middlemanDetailsHTML = ""
        if let middlemanName = purchase.middlemanName,
           let middlemanPayment = purchase.middlemanPayment,
           let middlemanAmount = middlemanPayment["amount"] as? Double,
           let middlemanUnit = middlemanPayment["unit"] as? String,
           let middlemanPaymentSplit = middlemanPayment["paymentSplit"] as? [String: Any] {
            
            let middlemanCash = middlemanPaymentSplit["cash"] as? Double ?? 0.0
            let middlemanBank = middlemanPaymentSplit["bank"] as? Double ?? 0.0
            let middlemanCreditCard = middlemanPaymentSplit["creditCard"] as? Double ?? 0.0
            let middlemanCredit = middlemanPaymentSplit["credit"] as? Double ?? 0.0
            
            middlemanDetailsHTML = """
            <div class="middleman-section">
                <div class="section-title">Middleman Details</div>
                <div class="middleman-info">
                    <div class="middleman-details">
                        <div><strong>Name:</strong> \(middlemanName)</div>
                        <div><strong>Entity Type:</strong> Middleman</div>
                        <div><strong>Amount:</strong> $\(String(format: "%.2f", middlemanAmount)) (\(middlemanUnit))</div>
                    </div>
                    <div class="middleman-payment">
                        <div class="section-title">Payment Split</div>
                        <div class="middleman-payment-grid">
                            <div class="middleman-payment-item">
                                <span>Cash:</span>
                                <span>$\(String(format: "%.2f", middlemanCash))</span>
                            </div>
                            <div class="middleman-payment-item">
                                <span>Bank:</span>
                                <span>$\(String(format: "%.2f", middlemanBank))</span>
                            </div>
                            <div class="middleman-payment-item">
                                <span>Credit Card:</span>
                                <span>$\(String(format: "%.2f", middlemanCreditCard))</span>
                            </div>
                            <div class="middleman-payment-item">
                                <span>Credit:</span>
                                <span>$\(String(format: "%.2f", middlemanCredit))</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            """
        }
        html = html.replacingOccurrences(of: "{{middleman_details}}", with: middlemanDetailsHTML)
        
        return html
    }
    
    private func generateItemsRows(for phones: [[String: Any]]) -> String {
        var rows = ""
        
        for phoneData in phones {
            let description = generatePhoneDescription(phoneData)
            let imei = phoneData["imei"] as? String ?? "N/A"
            let status = phoneData["status"] as? String ?? "N/A"
            let storageLocation = phoneData["storageLocation"] as? String ?? "N/A"
            let unitCost = phoneData["unitCost"] as? Double ?? 0.0
            let total = unitCost // Since each phone is 1 unit
            
            rows += """
            <tr>
                <td>
                    <div class="item-description">\(description)</div>
                </td>
                <td class="text-center">\(imei)</td>
                <td class="text-center">\(status)</td>
                <td class="text-center">\(storageLocation)</td>
                <td class="text-right">$\(String(format: "%.2f", unitCost))</td>
                <td class="text-right">$\(String(format: "%.2f", total))</td>
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
        
        // Add capacity if available
        if !capacity.isEmpty && capacity != "N/A" {
            description += ", \(capacity) \(capacityUnit)"
        }
        
        // Add color if available
        if let color = phoneData["color"] as? String, !color.isEmpty {
            description += ", \(color)"
        }
        
        // Add carrier if available
        if let carrier = phoneData["carrier"] as? String, !carrier.isEmpty {
            description += ", \(carrier)"
        }
        
        return description
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        return String(format: "%.2f", amount)
    }
}

enum BillGenerationError: Error {
    case templateNotFound
    case invalidData
    case generationFailed(String)
}