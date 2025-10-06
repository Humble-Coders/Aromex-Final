//
//  BillScreen.swift
//  Aromex
//

import SwiftUI
import WebKit
import PDFKit
import FirebaseFirestore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct BillScreen: View {
    let purchaseId: String
    let onClose: (() -> Void)?
    @State private var isLoading = true
    @State private var htmlContent = ""
    @State private var htmlPages: [String] = []
    @State private var showPDFShare = false
    @State private var pdfData: Data?
    @State private var errorMessage: String?
    @State private var purchase: Purchase?
    @State private var currentPage: Int = 0
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var isIPad: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    var totalPages: Int {
        htmlPages.isEmpty ? 1 : htmlPages.count
    }
    
    init(purchaseId: String, onClose: (() -> Void)? = nil) {
        self.purchaseId = purchaseId
        self.onClose = onClose
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.95, blue: 0.97)
                .ignoresSafeArea(.all)
            
            if isLoading {
                loadingView
            } else if let errorMessage = errorMessage {
                errorView(message: errorMessage)
            } else {
                mainContentView
            }
        }
        .onAppear {
            loadBill()
        }
        #if os(iOS)
        .sheet(isPresented: $showPDFShare) {
            if let pdfData = pdfData {
                PDFShareView(pdfData: pdfData)
            }
        }
        #endif
        .background(
            // Hidden PDF generator that only runs once
            Group {
                if !htmlPages.isEmpty && pdfData == nil {
                    PDFGeneratorView(htmlPages: htmlPages) { generatedPDF in
                        DispatchQueue.main.async {
                            self.pdfData = generatedPDF
                        }
                    }
                }
            }
        )
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.25, green: 0.33, blue: 0.54)))
            
            Text("Generating Invoice...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("Please wait while we prepare your document")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.secondary)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 40)
    }
    
    // MARK: - Error View
    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.red)
            }
            
            Text("Unable to Load Invoice")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
            
            Text(message)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            HStack(spacing: 12) {
                Button(action: {
                    onClose?()
                }) {
                    Text("Go Back")
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
                    loadBill()
                }) {
                    Text("Try Again")
                        .font(.system(size: 16, weight: .semibold))
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
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 40)
    }
    
    // MARK: - Main Content View
    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // PDF Viewer
            pdfViewerSection
            
            // Footer with Actions
            footerView
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Back button
                Button(action: {
                    onClose?()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // Title
                VStack(spacing: 2) {
                    Text("Purchase Invoice")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if let purchase = purchase {
                        Text("Order #ORD-\(purchase.orderNumber)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Share button
                Button(action: {
                    if let pdfData = self.pdfData {
                        #if os(iOS)
                        self.showPDFShare = true
                        #else
                        self.sharePDFOnMacOS(pdfData: pdfData)
                        #endif
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Share")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.25, green: 0.33, blue: 0.54),
                                        Color(red: 0.20, green: 0.28, blue: 0.48)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .shadow(color: Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(pdfData == nil)
                .opacity(pdfData == nil ? 0.5 : 1.0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.regularMaterial)
            
            Divider()
        }
    }
    
    // MARK: - PDF Viewer Section
    private var pdfViewerSection: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Page navigation (if multiple pages)
                if totalPages > 1 {
                    pageNavigationView
                        .padding(.vertical, 12)
                        .background(.regularMaterial)
                    
                    Divider()
                }
                
                // PDF content
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    ZStack {
                        // A4 aspect ratio container
                        Rectangle()
                            .fill(Color.white)
                            .aspectRatio(210/297, contentMode: .fit)
                            .frame(maxWidth: min(geometry.size.width - 40, 800))
                            .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
                        
                        // WebView overlay - show only current page HTML
                        SinglePageWebView(
                            htmlContent: htmlPages.isEmpty ? htmlContent : htmlPages[currentPage]
                        )
                        .aspectRatio(210/297, contentMode: .fit)
                        .frame(maxWidth: min(geometry.size.width - 40, 800))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Page Navigation View
    private var pageNavigationView: some View {
        HStack(spacing: 20) {
            // Previous button
            Button(action: {
                if currentPage > 0 {
                    currentPage -= 1
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Previous")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(currentPage > 0 ? Color(red: 0.25, green: 0.33, blue: 0.54) : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(currentPage > 0 ? Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.1) : Color.secondary.opacity(0.1))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(currentPage == 0)
            
            // Page indicator
            Text("Page \(currentPage + 1) of \(totalPages)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            // Next button
            Button(action: {
                if currentPage < totalPages - 1 {
                    currentPage += 1
                }
            }) {
                HStack(spacing: 8) {
                    Text("Next")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(currentPage < totalPages - 1 ? Color(red: 0.25, green: 0.33, blue: 0.54) : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(currentPage < totalPages - 1 ? Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.1) : Color.secondary.opacity(0.1))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(currentPage >= totalPages - 1)
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Footer View
    private var footerView: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 16) {
                // Close button
                Button(action: {
                    onClose?()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Close")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Download/Share button
                Button(action: {
                    if let pdfData = self.pdfData {
                        #if os(iOS)
                        self.showPDFShare = true
                        #else
                        self.sharePDFOnMacOS(pdfData: pdfData)
                        #endif
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Download PDF")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.25, green: 0.33, blue: 0.54),
                                        Color(red: 0.20, green: 0.28, blue: 0.48)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .shadow(color: Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(pdfData == nil)
                .opacity(pdfData == nil ? 0.5 : 1.0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.regularMaterial)
        }
    }
    
    // MARK: - Load Bill Function
    private func loadBill() {
        loadBillWithRetry(maxRetries: 3)
    }
    
    private func loadBillWithRetry(maxRetries: Int, currentRetry: Int = 0) {
        isLoading = true
        errorMessage = nil
        
        guard !purchaseId.isEmpty else {
            errorMessage = "Invalid purchase ID"
            isLoading = false
            return
        }
        
        Task {
            do {
                let db = Firestore.firestore()
                let purchaseDoc = try await db.collection("Purchases").document(purchaseId).getDocument()
                
                guard purchaseDoc.exists, let data = purchaseDoc.data() else {
                    if currentRetry < maxRetries {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.loadBillWithRetry(maxRetries: maxRetries, currentRetry: currentRetry + 1)
                        }
                        return
                    }
                    
                    await MainActor.run {
                        errorMessage = "Purchase not found after \(maxRetries + 1) attempts"
                        isLoading = false
                    }
                    return
                }
                
                let purchase = try Purchase.fromFirestore(data: data, id: purchaseId)
                
                let billGenerator = BillGenerator()
                let htmlPages = try billGenerator.generateBillHTML(for: purchase)
                
                await MainActor.run {
                    self.purchase = purchase
                    self.htmlPages = htmlPages
                    self.htmlContent = htmlPages.first ?? ""
                    self.currentPage = 0
                    self.isLoading = false
                }
                
            } catch {
                if currentRetry < maxRetries && !error.localizedDescription.contains("template") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.loadBillWithRetry(maxRetries: maxRetries, currentRetry: currentRetry + 1)
                    }
                    return
                }
                
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func generateCompletePDF(htmlPages: [String]) async {
        // This function is no longer needed
    }
    
    #if os(macOS)
    private func sharePDFOnMacOS(pdfData: Data) {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "Purchase_Invoice_\(self.purchase?.orderNumber ?? 0).pdf"
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        do {
            try pdfData.write(to: tempURL)
            
            DispatchQueue.main.async {
                let sharingService = NSSharingService(named: .sendViaAirDrop)
                
                if sharingService != nil {
                    NSWorkspace.shared.selectFile(tempURL.path, inFileViewerRootedAtPath: tempDirectory.path)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([tempURL])
                }
            }
        } catch {
            print("❌ Failed to save PDF: \(error)")
        }
    }
    #endif
}

// MARK: - PDF Generator View (hidden, runs once)
struct PDFGeneratorView: View {
    let htmlPages: [String]
    let onPDFGenerated: (Data?) -> Void
    
    var body: some View {
        BillWebView(htmlPages: htmlPages, onPDFGenerated: onPDFGenerated)
            .frame(width: 0, height: 0)
            .opacity(0)
    }
}

// MARK: - SinglePageWebView (for display only)
#if os(iOS)
struct SinglePageWebView: UIViewRepresentable {
    let htmlContent: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.backgroundColor = .white
        webView.isUserInteractionEnabled = false
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
}
#else
struct SinglePageWebView: NSViewRepresentable {
    let htmlContent: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
}
#endif

// MARK: - BillWebView (for PDF generation only)
#if os(iOS)
struct BillWebView: UIViewRepresentable {
    let htmlPages: [String]
    let onPDFGenerated: (Data?) -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = .white
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if let firstPage = htmlPages.first {
            webView.loadHTMLString(firstPage, baseURL: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: BillWebView
        private var currentPageIndex = 0
        private var pdfPages: [Data] = []
        
        init(_ parent: BillWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.generatePDFForCurrentPage(from: webView)
            }
        }
        
        private func generatePDFForCurrentPage(from webView: WKWebView) {
            let config = WKPDFConfiguration()
            config.rect = .null
            
            webView.createPDF(configuration: config) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let data):
                    self.pdfPages.append(data)
                    self.currentPageIndex += 1
                    
                    if self.currentPageIndex < self.parent.htmlPages.count {
                        DispatchQueue.main.async {
                            webView.loadHTMLString(self.parent.htmlPages[self.currentPageIndex], baseURL: nil)
                        }
                    } else {
                        self.mergePDFs()
                    }
                    
                case .failure(let error):
                    print("PDF generation failed: \(error)")
                    DispatchQueue.main.async {
                        self.parent.onPDFGenerated(nil)
                    }
                }
            }
        }
        
        private func mergePDFs() {
            let mergedPDF = PDFDocument()
            
            for pdfData in pdfPages {
                if let pdfDoc = PDFDocument(data: pdfData) {
                    for pageIndex in 0..<pdfDoc.pageCount {
                        if let page = pdfDoc.page(at: pageIndex) {
                            mergedPDF.insert(page, at: mergedPDF.pageCount)
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.parent.onPDFGenerated(mergedPDF.dataRepresentation())
            }
        }
    }
}
#else
struct BillWebView: NSViewRepresentable {
    let htmlPages: [String]
    let onPDFGenerated: (Data?) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        if let firstPage = htmlPages.first {
            webView.loadHTMLString(firstPage, baseURL: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: BillWebView
        private var currentPageIndex = 0
        private var pdfPages: [Data] = []
        
        init(_ parent: BillWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.generatePDFForCurrentPage(from: webView)
            }
        }
        
        private func generatePDFForCurrentPage(from webView: WKWebView) {
            let config = WKPDFConfiguration()
            config.rect = .null
            
            webView.createPDF(configuration: config) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let data):
                    self.pdfPages.append(data)
                    self.currentPageIndex += 1
                    
                    if self.currentPageIndex < self.parent.htmlPages.count {
                        DispatchQueue.main.async {
                            webView.loadHTMLString(self.parent.htmlPages[self.currentPageIndex], baseURL: nil)
                        }
                    } else {
                        self.mergePDFs()
                    }
                    
                case .failure(let error):
                    print("PDF generation failed: \(error)")
                    DispatchQueue.main.async {
                        self.parent.onPDFGenerated(nil)
                    }
                }
            }
        }
        
        private func mergePDFs() {
            let mergedPDF = PDFDocument()
            
            for pdfData in pdfPages {
                if let pdfDoc = PDFDocument(data: pdfData) {
                    for pageIndex in 0..<pdfDoc.pageCount {
                        if let page = pdfDoc.page(at: pageIndex) {
                            mergedPDF.insert(page, at: mergedPDF.pageCount)
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.parent.onPDFGenerated(mergedPDF.dataRepresentation())
            }
        }
    }
}
#endif

// MARK: - PDF Share View
#if os(iOS)
struct PDFShareView: UIViewControllerRepresentable {
    let pdfData: Data
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityVC = UIActivityViewController(activityItems: [pdfData], applicationActivities: nil)
        return activityVC
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Purchase Model
struct Purchase {
    let id: String
    let transactionDate: Date
    let orderNumber: Int
    let subtotal: Double
    let gstPercentage: Double
    let gstAmount: Double
    let pstPercentage: Double
    let pstAmount: Double
    let adjustmentAmount: Double
    let adjustmentUnit: String
    let grandTotal: Double
    let notes: String
    let purchasedPhones: [[String: Any]]
    let paymentMethods: [String: Any]
    let supplierName: String?
    let supplierAddress: String?
    let middlemanName: String?
    let middlemanPayment: [String: Any]?
    
    static func fromFirestore(data: [String: Any], id: String) throws -> Purchase {
        guard let transactionDate = (data["transactionDate"] as? Timestamp)?.dateValue(),
              let orderNumber = data["orderNumber"] as? Int,
              let subtotal = data["subtotal"] as? Double,
              let gstPercentage = data["gstPercentage"] as? Double,
              let gstAmount = data["gstAmount"] as? Double,
              let pstPercentage = data["pstPercentage"] as? Double,
              let pstAmount = data["pstAmount"] as? Double,
              let adjustmentAmount = data["adjustmentAmount"] as? Double,
              let adjustmentUnit = data["adjustmentUnit"] as? String,
              let grandTotal = data["grandTotal"] as? Double,
              let notes = data["notes"] as? String,
              let purchasedPhones = data["purchasedPhones"] as? [[String: Any]],
              let paymentMethods = data["paymentMethods"] as? [String: Any] else {
            throw PurchaseError.invalidData
        }
        
        let supplierName = data["supplierName"] as? String
        let supplierAddress = data["supplierAddress"] as? String
        let middlemanName = data["middlemanName"] as? String
        let middlemanPayment = data["middlemanPayment"] as? [String: Any]
        
        return Purchase(
            id: id,
            transactionDate: transactionDate,
            orderNumber: orderNumber,
            subtotal: subtotal,
            gstPercentage: gstPercentage,
            gstAmount: gstAmount,
            pstPercentage: pstPercentage,
            pstAmount: pstAmount,
            adjustmentAmount: adjustmentAmount,
            adjustmentUnit: adjustmentUnit,
            grandTotal: grandTotal,
            notes: notes,
            purchasedPhones: purchasedPhones,
            paymentMethods: paymentMethods,
            supplierName: supplierName,
            supplierAddress: supplierAddress,
            middlemanName: middlemanName,
            middlemanPayment: middlemanPayment
        )
    }
}

enum PurchaseError: Error {
    case invalidData
    case firestoreError(String)
}

#Preview {
    BillScreen(purchaseId: "sample-purchase-id")
}
