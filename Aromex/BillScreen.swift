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
    // Edit contact info state
    @State private var showingEditContact = false
    @State private var editAddress: String = ""
    @State private var editEmail: String = ""
    @State private var editPhone: String = ""
    @State private var isPermanentEdit: Bool = false
    
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
                .ignoresSafeArea(.container, edges: [])
            
            if isLoading {
                loadingView
            } else if let errorMessage = errorMessage {
                errorView(message: errorMessage)
            } else {
                contentView
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
        // Hide title on iPhone; only back and share buttons should show
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Edit button (left of Share)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    if let purchase = self.purchase {
                        editAddress = purchase.companyAddress ?? ""
                        editEmail = purchase.companyEmail ?? ""
                        editPhone = purchase.companyPhone ?? ""
                    }
                    isPermanentEdit = false
                    showingEditContact = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    onClose?()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    if let pdfData = self.pdfData {
                        self.showPDFShare = true
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                }
                .disabled(pdfData == nil)
                .opacity(pdfData == nil ? 0.5 : 1.0)
            }
        }
        .sheet(isPresented: $showingEditContact) {
            EditContactSheet(
                address: $editAddress,
                email: $editEmail,
                phone: $editPhone,
                isPermanent: $isPermanentEdit,
                onCancel: { showingEditContact = false },
                onSave: { address, email, phone, isPermanent in
                    Task {
                        await self.applyContactEdits(address: address, email: email, phone: phone, isPermanent: isPermanent)
                    }
                }
            )
        }
        #else
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    onClose?()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
            // Edit button just left of Share (both in trailing area)
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    if let purchase = self.purchase {
                        editAddress = purchase.companyAddress ?? ""
                        editEmail = purchase.companyEmail ?? ""
                        editPhone = purchase.companyPhone ?? ""
                    }
                    isPermanentEdit = false
                    showingEditContact = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    if let pdfData = self.pdfData {
                        self.sharePDFOnMacOS(pdfData: pdfData)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                }
                .disabled(pdfData == nil)
                .opacity(pdfData == nil ? 0.5 : 1.0)
            }
        }
        .sheet(isPresented: $showingEditContact) {
            EditContactSheet(
                address: $editAddress,
                email: $editEmail,
                phone: $editPhone,
                isPermanent: $isPermanentEdit,
                onCancel: { showingEditContact = false },
                onSave: { address, email, phone, isPermanent in
                    Task {
                        await self.applyContactEdits(address: address, email: email, phone: phone, isPermanent: isPermanent)
                    }
                }
            )
        }
        #endif
        .background(
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
    
    // MARK: - Main Content View (Native bars only)
    private var contentView: some View {
        Group {
            if let pdfData = pdfData, let document = PDFDocument(data: pdfData) {
                PDFViewRepresentable(document: document)
            } else {
                pagedHTMLViewer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
    
    // Removed custom header to respect native top bars
    
    // MARK: - HTML Viewer (paged, interactive)
    private var pagedHTMLViewer: some View {
        GeometryReader { geometry in
            #if os(iOS)
            TabView(selection: $currentPage) {
                ForEach(Array((htmlPages.isEmpty ? [htmlContent] : htmlPages).enumerated()), id: \.offset) { index, pageHTML in
                    InteractiveWebView(htmlContent: pageHTML)
                        .tag(index)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color.white)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            #else
            // macOS fallback - use ScrollView with manual page navigation
            VStack(spacing: 0) {
                // Page indicator
                if totalPages > 1 {
                    HStack {
                        Button(action: {
                            if currentPage > 0 {
                                currentPage -= 1
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(currentPage > 0 ? .primary : .secondary)
                        }
                        .disabled(currentPage == 0)
                        
                        Spacer()
                        
                        Text("Page \(currentPage + 1) of \(totalPages)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: {
                            if currentPage < totalPages - 1 {
                                currentPage += 1
                            }
                        }) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(currentPage < totalPages - 1 ? .primary : .secondary)
                        }
                        .disabled(currentPage >= totalPages - 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                }
                
                // Content
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    InteractiveWebView(htmlContent: htmlPages.isEmpty ? htmlContent : htmlPages[currentPage])
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color.white)
                }
            }
            #endif
        }
    }
    
    // Removed custom page navigation; paging is handled by native PageTabViewStyle
    
    // Removed custom footer to respect native bars
    
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
                
                var purchase = try Purchase.fromFirestore(data: data, id: purchaseId)
                
                // Fetch supplier name/phone from reference
                if let supplierRef = data["supplier"] as? DocumentReference {
                    let supplierSnap = try await supplierRef.getDocument()
                    if supplierSnap.exists {
                        let sData = supplierSnap.data() ?? [:]
                        let sName = sData["name"] as? String
                        let sPhone = sData["phone"] as? String
                        purchase = Purchase(
                            id: purchase.id,
                            transactionDate: purchase.transactionDate,
                            orderNumber: purchase.orderNumber,
                            subtotal: purchase.subtotal,
                            gstPercentage: purchase.gstPercentage,
                            gstAmount: purchase.gstAmount,
                            pstPercentage: purchase.pstPercentage,
                            pstAmount: purchase.pstAmount,
                            adjustmentAmount: purchase.adjustmentAmount,
                            adjustmentUnit: purchase.adjustmentUnit,
                            grandTotal: purchase.grandTotal,
                            notes: purchase.notes,
                            purchasedPhones: purchase.purchasedPhones,
                            paymentMethods: purchase.paymentMethods,
                            supplierName: sName ?? purchase.supplierName,
                            supplierAddress: purchase.supplierAddress,
                            middlemanName: purchase.middlemanName,
                            middlemanPayment: purchase.middlemanPayment,
                            supplierPhone: sPhone,
                            companyAddress: purchase.companyAddress,
                            companyEmail: purchase.companyEmail,
                            companyPhone: purchase.companyPhone
                        )
                    }
                }
                
                // Fetch company contact info from Data collection
                do {
                    async let addressDoc = db.collection("Data").document("address").getDocument()
                    async let emailDoc = db.collection("Data").document("email").getDocument()
                    async let phoneDoc = db.collection("Data").document("phone").getDocument()
                    let (addrSnap, emailSnap, phoneSnap) = try await (addressDoc, emailDoc, phoneDoc)
                    let addr = (addrSnap.data()?["address"] as? String)
                    let email = (emailSnap.data()?["email"] as? String)
                    let phone = (phoneSnap.data()?["phone"] as? String)
                    purchase = Purchase(
                        id: purchase.id,
                        transactionDate: purchase.transactionDate,
                        orderNumber: purchase.orderNumber,
                        subtotal: purchase.subtotal,
                        gstPercentage: purchase.gstPercentage,
                        gstAmount: purchase.gstAmount,
                        pstPercentage: purchase.pstPercentage,
                        pstAmount: purchase.pstAmount,
                        adjustmentAmount: purchase.adjustmentAmount,
                        adjustmentUnit: purchase.adjustmentUnit,
                        grandTotal: purchase.grandTotal,
                        notes: purchase.notes,
                        purchasedPhones: purchase.purchasedPhones,
                        paymentMethods: purchase.paymentMethods,
                        supplierName: purchase.supplierName,
                        supplierAddress: purchase.supplierAddress,
                        middlemanName: purchase.middlemanName,
                        middlemanPayment: purchase.middlemanPayment,
                        supplierPhone: purchase.supplierPhone,
                        companyAddress: addr ?? purchase.companyAddress,
                        companyEmail: email ?? purchase.companyEmail,
                        companyPhone: phone ?? purchase.companyPhone
                    )
                } catch {
                    // If Data collection docs are missing, proceed with nils
                }
                
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

// MARK: - Edit Contact Sheet
struct EditContactSheet: View {
    @Binding var address: String
    @Binding var email: String
    @Binding var phone: String
    @Binding var isPermanent: Bool
    let onCancel: () -> Void
    let onSave: (String, String, String, Bool) -> Void
    
    var body: some View {
        #if os(iOS)
        content
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        #else
        content
            .frame(width: 420)
        #endif
    }
    
    private var content: some View {
        let primary = Color(red: 0.25, green: 0.33, blue: 0.54)
        #if os(iOS)
        let fieldBG = Color(UIColor.secondarySystemBackground)
        let cardBG = Color(UIColor.systemBackground)
        #else
        let fieldBG = Color(NSColor.windowBackgroundColor)
        let cardBG = Color(NSColor.windowBackgroundColor)
        #endif
        
        return VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(primary)
                Text("Edit Bill Contact Info")
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                // Address Field (multiline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Address")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(primary)
                        TextField("Company address", text: $address, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(fieldBG))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // Email Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(primary)
                        #if os(iOS)
                        TextField("Company email", text: $email)
                            .keyboardType(.emailAddress)
                        #else
                        TextField("Company email", text: $email)
                        #endif
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(fieldBG))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // Phone Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Phone")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "phone.fill")
                            .foregroundColor(primary)
                        #if os(iOS)
                        TextField("Company phone", text: $phone)
                            .keyboardType(.phonePad)
                        #else
                        TextField("Company phone", text: $phone)
                        #endif
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(fieldBG))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                
                Toggle("Save permanently", isOn: $isPermanent)
                    .tint(primary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(cardBG)
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
            )
            
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { onSave(address, email, phone, isPermanent) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.25, green: 0.33, blue: 0.54),
                                Color(red: 0.20, green: 0.28, blue: 0.48)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    )
                    .shadow(color: Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.25), radius: 8, x: 0, y: 4)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(20)
    }
}

// MARK: - PDFViewRepresentable (for PDF display)
#if os(iOS)
struct PDFViewRepresentable: UIViewRepresentable {
    let document: PDFDocument
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .white
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        pdfView.document = document
    }
}
#else
struct PDFViewRepresentable: NSViewRepresentable {
    let document: PDFDocument
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .white
        return pdfView
    }
    
    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.document = document
    }
}
#endif

// MARK: - InteractiveWebView (zoomable/scrollable)
#if os(iOS)
struct InteractiveWebView: UIViewRepresentable {
    let htmlContent: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 4.0
        webView.scrollView.bouncesZoom = true
        webView.backgroundColor = .white
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
}

// (moved applyContactEdits below platform conditionals)
#else
struct InteractiveWebView: NSViewRepresentable {
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

// MARK: - Apply Contact Edits
extension BillScreen {
    fileprivate func applyContactEdits(address: String, email: String, phone: String, isPermanent: Bool) async {
        showingEditContact = false
        do {
            if isPermanent {
                let db = Firestore.firestore()
                try await db.collection("Data").document("address").setData(["address": address], merge: true)
                try await db.collection("Data").document("email").setData(["email": email], merge: true)
                try await db.collection("Data").document("phone").setData(["phone": phone], merge: true)
            }
            if var purchase = self.purchase {
                purchase = Purchase(
                    id: purchase.id,
                    transactionDate: purchase.transactionDate,
                    orderNumber: purchase.orderNumber,
                    subtotal: purchase.subtotal,
                    gstPercentage: purchase.gstPercentage,
                    gstAmount: purchase.gstAmount,
                    pstPercentage: purchase.pstPercentage,
                    pstAmount: purchase.pstAmount,
                    adjustmentAmount: purchase.adjustmentAmount,
                    adjustmentUnit: purchase.adjustmentUnit,
                    grandTotal: purchase.grandTotal,
                    notes: purchase.notes,
                    purchasedPhones: purchase.purchasedPhones,
                    paymentMethods: purchase.paymentMethods,
                    supplierName: purchase.supplierName,
                    supplierAddress: purchase.supplierAddress,
                    middlemanName: purchase.middlemanName,
                    middlemanPayment: purchase.middlemanPayment,
                    supplierPhone: purchase.supplierPhone,
                    companyAddress: address,
                    companyEmail: email,
                    companyPhone: phone
                )
                let billGenerator = BillGenerator()
                let pages = try billGenerator.generateBillHTML(for: purchase)
                await MainActor.run {
                    self.purchase = purchase
                    self.htmlPages = pages
                    self.htmlContent = pages.first ?? ""
                    self.currentPage = 0
                    self.pdfData = nil // regenerate PDF via hidden webview
                }
            }
        } catch {
            print("❌ Failed to apply contact edits: \(error)")
        }
    }
}

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
    // Added for bill header and supplier details
    let supplierPhone: String?
    let companyAddress: String?
    let companyEmail: String?
    let companyPhone: String?
    
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
            middlemanPayment: middlemanPayment,
            supplierPhone: nil,
            companyAddress: nil,
            companyEmail: nil,
            companyPhone: nil
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
