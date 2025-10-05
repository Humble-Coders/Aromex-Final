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
    @State private var scrollOffset: CGPoint = .zero
    @State private var zoomScale: CGFloat = 1.0
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var isIPadHorizontal: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    init(purchaseId: String, onClose: (() -> Void)? = nil) {
        self.purchaseId = purchaseId
        self.onClose = onClose
    }
    
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea(.all)
            
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Generating Bill...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text("Error Loading Bill")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Try Again") {
                        loadBill()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Purchase Invoice")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Button("Done") {
                            onClose?()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(.regularMaterial)
                    
                    ZoomableScrollView(zoomScale: $zoomScale, scrollOffset: $scrollOffset) {
                        BillWebView(htmlPages: htmlPages.isEmpty ? [htmlContent] : htmlPages) { pdfData in
                            DispatchQueue.main.async {
                                self.pdfData = pdfData
                            }
                        }
                        .frame(width: 595, height: 842)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    HStack(spacing: 16) {
                        Button(action: {
                            onClose?()
                        }) {
                            HStack {
                                Image(systemName: "arrow.left")
                                Text("Back")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                        }
                        .foregroundColor(.primary)
                        
                        Button(action: {
                            if let pdfData = self.pdfData {
                                #if os(iOS)
                                self.showPDFShare = true
                                #else
                                self.sharePDFOnMacOS(pdfData: pdfData)
                                #endif
                            }
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share PDF")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(pdfData != nil ? Color.blue : Color.gray)
                            .cornerRadius(8)
                        }
                        .foregroundColor(.white)
                        .disabled(pdfData == nil)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: -1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }
    
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

// MARK: - Zoomable ScrollView
struct ZoomableScrollView<Content: View>: View {
    @Binding var zoomScale: CGFloat
    @Binding var scrollOffset: CGPoint
    let content: Content
    
    init(zoomScale: Binding<CGFloat>, scrollOffset: Binding<CGPoint>, @ViewBuilder content: () -> Content) {
        self._zoomScale = zoomScale
        self._scrollOffset = scrollOffset
        self.content = content()
    }
    
    var body: some View {
        #if os(iOS)
        ZoomableScrollViewRepresentable(zoomScale: $zoomScale, scrollOffset: $scrollOffset, content: content)
        #else
        ZoomableScrollViewRepresentable(zoomScale: $zoomScale, scrollOffset: $scrollOffset, content: content)
        #endif
    }
}

#if os(iOS)
struct ZoomableScrollViewRepresentable<Content: View>: UIViewRepresentable {
    @Binding var zoomScale: CGFloat
    @Binding var scrollOffset: CGPoint
    let content: Content
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 3.0
        scrollView.minimumZoomScale = 0.5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalToConstant: 595),
            hostingController.view.heightAnchor.constraint(equalToConstant: 842)
        ])
        
        context.coordinator.hostingController = hostingController
        context.coordinator.scrollView = scrollView
        
        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        scrollView.zoomScale = zoomScale
        scrollView.contentOffset = scrollOffset
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        let parent: ZoomableScrollViewRepresentable
        var hostingController: UIHostingController<Content>?
        var scrollView: UIScrollView?
        
        init(_ parent: ZoomableScrollViewRepresentable) {
            self.parent = parent
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController?.view
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            parent.zoomScale = scrollView.zoomScale
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.scrollOffset = scrollView.contentOffset
        }
    }
}
#else
struct ZoomableScrollViewRepresentable<Content: View>: NSViewRepresentable {
    @Binding var zoomScale: CGFloat
    @Binding var scrollOffset: CGPoint
    let content: Content
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.allowsMagnification = true
        scrollView.maxMagnification = 3.0
        scrollView.minMagnification = 0.5
        
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(x: 0, y: 0, width: 595, height: 842)
        
        scrollView.documentView = hostingView
        context.coordinator.scrollView = scrollView
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.magnificationChanged),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.magnification = zoomScale
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: ZoomableScrollViewRepresentable
        var scrollView: NSScrollView?
        
        init(_ parent: ZoomableScrollViewRepresentable) {
            self.parent = parent
        }
        
        @objc func magnificationChanged() {
            if let scrollView = scrollView {
                parent.zoomScale = scrollView.magnification
            }
        }
    }
}
#endif

#if os(iOS)
struct BillWebView: UIViewRepresentable {
    let htmlPages: [String]
    let onPDFGenerated: (Data?) -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
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
