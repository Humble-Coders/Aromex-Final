//
//  LedgerScreen.swift
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

struct LedgerScreen: View {
    let entity: EntityProfile
    let entityType: EntityType
    let transactions: [EntityTransaction]
    let startDate: Date?
    let endDate: Date?
    let onClose: (() -> Void)?
    
    @State private var isLoading = true
    @State private var htmlContent = ""
    @State private var htmlPages: [String] = []
    @State private var showPDFShare = false
    @State private var pdfData: Data?
    @State private var errorMessage: String?
    @State private var currentPage: Int = 0
    
    // Company contact info state
    @State private var companyAddress: String?
    @State private var companyEmail: String?
    @State private var companyPhone: String?
    
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
    
    init(entity: EntityProfile, entityType: EntityType, transactions: [EntityTransaction], startDate: Date?, endDate: Date?, onClose: (() -> Void)? = nil) {
        self.entity = entity
        self.entityType = entityType
        self.transactions = transactions
        self.startDate = startDate
        self.endDate = endDate
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
            loadLedger()
        }
        #if os(iOS)
        .sheet(isPresented: $showPDFShare) {
            if let pdfData = pdfData {
                let entityName = entity.name.replacingOccurrences(of: " ", with: "_")
                let startStr = startDate != nil ? dateFormatter.string(from: startDate!) : "All"
                let endStr = endDate != nil ? dateFormatter.string(from: endDate!) : "All"
                let fileName = "Ledger_\(entityName)_\(startStr)_to_\(endStr).pdf"
                PDFShareView(pdfData: pdfData, fileName: fileName)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        #endif
        .background(
            Group {
                if !htmlPages.isEmpty && pdfData == nil {
                    LedgerPDFGeneratorView(htmlPages: htmlPages) { generatedPDF in
                        DispatchQueue.main.async {
                            self.pdfData = generatedPDF
                        }
                    }
                }
            }
        )
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM_dd_yyyy"
        return formatter
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.25, green: 0.33, blue: 0.54)))
            
            Text("Generating Ledger...")
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
            
            Text("Unable to Load Ledger")
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
                    loadLedger()
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
    
    // MARK: - Load Ledger Function
    private func loadLedger() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Fetch company contact info from Firestore
                let db = Firestore.firestore()
                
                async let addressDoc = db.collection("Data").document("address").getDocument()
                async let emailDoc = db.collection("Data").document("email").getDocument()
                async let phoneDoc = db.collection("Data").document("phone").getDocument()
                
                let (addrSnap, emailSnap, phoneSnap) = try await (addressDoc, emailDoc, phoneDoc)
                
                let addr = addrSnap.data()?["address"] as? String
                let email = emailSnap.data()?["email"] as? String
                let phone = phoneSnap.data()?["phone"] as? String
                
                // Generate ledger HTML
                let generator = LedgerGenerator()
                let htmlPages = try generator.generateLedgerHTML(
                    for: entity,
                    entityType: entityType,
                    transactions: transactions,
                    startDate: startDate,
                    endDate: endDate,
                    companyAddress: addr,
                    companyEmail: email,
                    companyPhone: phone
                )
                
                await MainActor.run {
                    self.companyAddress = addr
                    self.companyEmail = email
                    self.companyPhone = phone
                    self.htmlPages = htmlPages
                    self.htmlContent = htmlPages.first ?? ""
                    self.isLoading = false
                    self.currentPage = 0
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    #if os(macOS)
    private func sharePDFOnMacOS(pdfData: Data) {
        let tempDirectory = FileManager.default.temporaryDirectory
        let entityName = entity.name.replacingOccurrences(of: " ", with: "_")
        let startStr = startDate != nil ? dateFormatter.string(from: startDate!) : "All"
        let endStr = endDate != nil ? dateFormatter.string(from: endDate!) : "All"
        let fileName = "Ledger_\(entityName)_\(startStr)_to_\(endStr).pdf"
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
struct LedgerPDFGeneratorView: View {
    let htmlPages: [String]
    let onPDFGenerated: (Data?) -> Void
    
    var body: some View {
        LedgerWebView(htmlPages: htmlPages, onPDFGenerated: onPDFGenerated)
            .frame(width: 0, height: 0)
            .opacity(0)
    }
}

// MARK: - LedgerWebView (for PDF generation only)
#if os(iOS)
struct LedgerWebView: UIViewRepresentable {
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
        let parent: LedgerWebView
        private var currentPageIndex = 0
        private var pdfPages: [Data] = []
        
        init(_ parent: LedgerWebView) {
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
struct LedgerWebView: NSViewRepresentable {
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
        let parent: LedgerWebView
        private var currentPageIndex = 0
        private var pdfPages: [Data] = []
        
        init(_ parent: LedgerWebView) {
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

// MARK: - Histories Ledger Screen

struct HistoriesLedgerScreen: View {
    let tabName: String
    let entries: [HistoryEntry]
    let startDate: Date?
    let endDate: Date?
    let onClose: (() -> Void)?
    
    @State private var isLoading = true
    @State private var htmlContent = ""
    @State private var htmlPages: [String] = []
    @State private var showPDFShare = false
    @State private var pdfData: Data?
    @State private var errorMessage: String?
    @State private var currentPage: Int = 0
    
    // Company contact info state
    @State private var companyAddress: String?
    @State private var companyEmail: String?
    @State private var companyPhone: String?
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    
    var totalPages: Int {
        htmlPages.isEmpty ? 1 : htmlPages.count
    }
    
    init(tabName: String, entries: [HistoryEntry], startDate: Date?, endDate: Date?, onClose: (() -> Void)? = nil) {
        self.tabName = tabName
        self.entries = entries
        self.startDate = startDate
        self.endDate = endDate
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
            loadLedger()
        }
        #if os(iOS)
        .sheet(isPresented: $showPDFShare) {
            if let pdfData = pdfData {
                let tabNameSanitized = tabName.replacingOccurrences(of: " ", with: "_")
                let startStr = startDate != nil ? dateFormatter.string(from: startDate!) : "All"
                let endStr = endDate != nil ? dateFormatter.string(from: endDate!) : "All"
                let fileName = "Ledger_\(tabNameSanitized)_\(startStr)_to_\(endStr).pdf"
                PDFShareView(pdfData: pdfData, fileName: fileName)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    onClose?()
                    dismiss()
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
        #else
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    onClose?()
                    dismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
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
        #endif
        .background(
            Group {
                if !htmlPages.isEmpty && pdfData == nil {
                    LedgerPDFGeneratorView(htmlPages: htmlPages) { generatedPDF in
                        DispatchQueue.main.async {
                            self.pdfData = generatedPDF
                        }
                    }
                }
            }
        )
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM_dd_yyyy"
        return formatter
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.25, green: 0.33, blue: 0.54)))
            
            Text("Generating Ledger...")
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
            
            Text("Unable to Load Ledger")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
            
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            HStack(spacing: 12) {
                Button(action: {
                    onClose?()
                    dismiss()
                }) {
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
                    loadLedger()
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
    
    // MARK: - Load Ledger
    private func loadLedger() {
        isLoading = true
        errorMessage = nil
        
        Task {
            await fetchCompanyContactInfo()
            
            do {
                let generator = LedgerGenerator()
                let pages = try generator.generateHistoriesLedgerHTML(
                    for: tabName,
                    entries: entries,
                    startDate: startDate,
                    endDate: endDate,
                    companyAddress: companyAddress,
                    companyEmail: companyEmail,
                    companyPhone: companyPhone
                )
                
                await MainActor.run {
                    self.htmlPages = pages
                    if !pages.isEmpty {
                        self.htmlContent = pages[0]
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Fetch Company Contact Info
    private func fetchCompanyContactInfo() async {
        let db = Firestore.firestore()
        
        do {
            // Fetch company contact info from Firestore (same as regular LedgerScreen)
            async let addressDoc = db.collection("Data").document("address").getDocument()
            async let emailDoc = db.collection("Data").document("email").getDocument()
            async let phoneDoc = db.collection("Data").document("phone").getDocument()
            
            let (addrSnap, emailSnap, phoneSnap) = try await (addressDoc, emailDoc, phoneDoc)
            
            await MainActor.run {
                self.companyAddress = addrSnap.data()?["address"] as? String
                self.companyEmail = emailSnap.data()?["email"] as? String
                self.companyPhone = phoneSnap.data()?["phone"] as? String
            }
        } catch {
            print("⚠️ Could not fetch company contact info: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Share PDF on macOS
    #if os(macOS)
    private func sharePDFOnMacOS(pdfData: Data) {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tabNameSanitized = tabName.replacingOccurrences(of: " ", with: "_")
        let startStr = startDate != nil ? dateFormatter.string(from: startDate!) : "All"
        let endStr = endDate != nil ? dateFormatter.string(from: endDate!) : "All"
        let fileName = "Ledger_\(tabNameSanitized)_\(startStr)_to_\(endStr).pdf"
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        do {
            try pdfData.write(to: tempURL)
            
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([tempURL])
            }
        } catch {
            print("❌ Failed to save PDF: \(error)")
        }
    }
    #endif
}

#Preview {
    LedgerScreen(
        entity: EntityProfile(
            id: "test",
            name: "John Doe",
            phone: "123-456-7890",
            email: "john@example.com",
            balance: 1000.0,
            address: "123 Main St",
            notes: "Test entity"
        ),
        entityType: .customer,
        transactions: [],
        startDate: nil,
        endDate: nil
    )
}
