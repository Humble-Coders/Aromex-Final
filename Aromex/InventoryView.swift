//
//  PurchaseView.swift
//  Aromex
//
//  Created by User on 9/17/25.
//

import SwiftUI
import FirebaseFirestore
#if os(iOS)
import UIKit
#endif

struct PurchaseView: View {
    @Binding var showingSupplierDropdown: Bool
    @Binding var selectedSupplier: EntityWithType?
    @Binding var supplierButtonFrame: CGRect
    @Binding var allEntities: [EntityWithType]
    @Binding var supplierSearchText: String
    
    @State private var orderNumber: String = "Loading..."
    @State private var selectedDate = Date()
    @State private var showingDatePicker = false
    @State private var showingAddProductDialog = false
    @State private var isLoadingEntities = true
    @FocusState private var isSupplierFieldFocused: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var isCompact: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    var filteredEntities: [EntityWithType] {
        if supplierSearchText.isEmpty {
            return allEntities
        } else {
            return allEntities.filter { entity in
                entity.name.localizedCaseInsensitiveContains(supplierSearchText) ||
                entity.entityType.rawValue.localizedCaseInsensitiveContains(supplierSearchText)
            }
        }
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: selectedDate)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                
                
                // Form Section
                if isCompact {
                    iPhoneLayout
                } else {
                    iPadMacLayout
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
        .background(.regularMaterial)
        .onAppear {
            fetchOrderNumber()
            if allEntities.isEmpty {
                fetchAllEntities()
            }
        }
        .onChange(of: showingSupplierDropdown) { isOpen in
            isSupplierFieldFocused = isOpen
        }
        .sheet(isPresented: $showingAddProductDialog) {
            AddProductDialog(isPresented: $showingAddProductDialog, onDismiss: nil)
        }
    }
    
    var iPhoneLayout: some View {
        VStack(spacing: 24) {
            // Form Fields Container
            VStack(spacing: 20) {
                orderNumberField
                dateField
                supplierDropdown
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
            
            // Action Button
            addProductButton
        }
    }
    
    var iPadMacLayout: some View {
        VStack(spacing: 40) {
            // Form Fields Container
            VStack(spacing: 30) {
                HStack(spacing: 24) {
                    orderNumberField
                    dateField
                    supplierDropdown
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                )
            }
            
            // Action Button
            addProductButton
        }
    }
    
    var orderNumberField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Order number")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
            
            Text(orderNumber)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            
            Text("Unique order number for this purchase")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    var dateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Date")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
            
            Button(action: {
                showingDatePicker = true
            }) {
                HStack {
                    Text(formattedDate)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.regularMaterial)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .modifier(DatePickerModifier(
                isPresented: $showingDatePicker,
                selectedDate: $selectedDate,
                isCompact: isCompact
            ))
            
            Text("The date when this purchase was made")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    var supplierDropdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Supplier")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("*")
                    .foregroundColor(.red)
            }
            
            SupplierDropdownButton(
                selectedSupplier: selectedSupplier,
                placeholder: "Choose an option",
                isOpen: $showingSupplierDropdown,
                buttonFrame: $supplierButtonFrame,
                searchText: $supplierSearchText,
                isFocused: $isSupplierFieldFocused
            )
            .frame(height: 44)
            
            Text("Select a supplier for this purchase")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    var addProductButton: some View {
        Button(action: {
            showingAddProductDialog = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                
                Text("Add Product")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
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
    }
    
    private func fetchOrderNumber() {
        let db = Firestore.firestore()
        
        db.collection("Data").document("purchaseOrderNo").getDocument { document, error in
            if let error = error {
                print("Error fetching order number: \(error)")
                DispatchQueue.main.async {
                    self.orderNumber = "ORD-1"
                }
                return
            }
            
            if let document = document, document.exists {
                let data = document.data()
                let currentOrderNo = data?["purchaseOrderNo"] as? Int ?? 0
                let nextOrderNo = currentOrderNo + 1
                
                DispatchQueue.main.async {
                    self.orderNumber = "ORD-\(nextOrderNo)"
                }
            } else {
                // Document doesn't exist, start from 1
                DispatchQueue.main.async {
                    self.orderNumber = "ORD-1"
                }
            }
        }
    }
    
    private func fetchAllEntities() {
        let db = Firestore.firestore()
        var entities: [EntityWithType] = []
        let group = DispatchGroup()
        
        // Fetch from all three collections
        let collections = [
            ("Customers", EntityType.customer),
            ("Suppliers", EntityType.supplier),
            ("Middlemen", EntityType.middleman)
        ]
        
        for (collectionName, entityType) in collections {
            group.enter()
            
            db.collection(collectionName).getDocuments { snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    print("Error fetching \(collectionName): \(error)")
                    return
                }
                
                if let documents = snapshot?.documents {
                    for document in documents {
                        let data = document.data()
                        let entity = EntityWithType(
                            id: document.documentID,
                            name: data["name"] as? String ?? "",
                            entityType: entityType
                        )
                        entities.append(entity)
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            self.allEntities = entities.sorted { $0.name < $1.name }
            self.isLoadingEntities = false
        }
    }
}

struct EntityWithType: Identifiable {
    let id: String
    let name: String
    let entityType: EntityType
}

struct DatePickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selectedDate: Date
    let isCompact: Bool
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: selectedDate)
    }
    
    func body(content: Content) -> some View {
        content
        .modifier(DatePickerPresentationModifier(
            isPresented: $isPresented,
            selectedDate: $selectedDate,
            isCompact: isCompact
        ))
    }
    
    @ViewBuilder
    var datePickerContent: some View {
        if isCompact {
            // iPhone version - normal small calendar
            #if os(iOS)
            NavigationView {
                VStack(spacing: 20) {
                    DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                    
                    Spacer()
                }
                .navigationTitle("Select Purchase Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            isPresented = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            #else
            // Fallback for macOS (though isCompact should never be true on macOS)
            VStack(spacing: 20) {
                HStack {
                    Text("Select Purchase Date")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Done") {
                        isPresented = false
                    }
                    .font(.system(size: 16, weight: .semibold))
                }
                .padding()
                
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                
                Spacer()
            }
            #endif
        } else {
            // Enhanced iPad/macOS version with large, clean, robust design
            VStack(spacing: 0) {
                // Enhanced header with clean styling
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Select Purchase Date")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("Choose the date for this purchase order")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            isPresented = false
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Confirm Selection")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
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
                            .shadow(color: Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 0.1), value: isPresented)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 30)
                    
                    // Subtle divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .padding(.horizontal, 40)
                }
                .background(.regularMaterial)
                
                // Enhanced calendar container
                VStack(spacing: 0) {
                    // Current selection indicator
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Selected Date")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            
                            Text(formattedDate)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        // Quick date options
                        HStack(spacing: 12) {
                            DateQuickButton(title: "Today", date: Date(), selectedDate: $selectedDate)
                            DateQuickButton(title: "Yesterday", date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(), selectedDate: $selectedDate)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    
                    // Large, clean calendar
                    VStack {
                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .scaleEffect(1.4)
                            .padding(.horizontal, 60)
                            .padding(.vertical, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
                            )
                            .padding(.horizontal, 40)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                 .background(
                     LinearGradient(
                         gradient: Gradient(colors: [
                             Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.3),
                             Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.1)
                         ]),
                         startPoint: .top,
                         endPoint: .bottom
                     )
                 )
            }
            .frame(width: 600, height: 500)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        }
    }
}

struct DatePickerPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selectedDate: Date
    let isCompact: Bool
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: selectedDate)
    }
    
    func body(content: Content) -> some View {
        content
        #if os(iOS)
        .modifier(iOSPresentationModifier(
            isPresented: $isPresented,
            selectedDate: $selectedDate,
            isCompact: isCompact,
            formattedDate: formattedDate
        ))
        #else
        .popover(isPresented: $isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .scaleEffect(1.5)
                .padding(30)
                .frame(width: 400, height: 350)
        }
        #endif
    }
}

struct iOSPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selectedDate: Date
    let isCompact: Bool
    let formattedDate: String
    
    func body(content: Content) -> some View {
        if isCompact {
            // iPhone - simple modal (iOS only)
            #if os(iOS)
            content
            .fullScreenCover(isPresented: $isPresented) {
                NavigationView {
                    VStack(spacing: 20) {
                        DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                        
                        Spacer()
                    }
                    .navigationTitle("Select Purchase Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                isPresented = false
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                isPresented = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
            #else
            // Fallback for macOS (though isCompact should never be true on macOS)
            content
            .popover(isPresented: $isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(20)
                    .frame(width: 300, height: 250)
            }
            #endif
        } else {
            // iPad - small popup calendar
            content
            .popover(isPresented: $isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .scaleEffect(1.0)
                    .padding(30)
                    .frame(width: 450, height: 400)
            }
        }
    }
}

struct DateQuickButton: View {
    let title: String
    let date: Date
    @Binding var selectedDate: Date
    
    private var isSelected: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: date)
    }
    
    var body: some View {
        Button(action: {
            selectedDate = date
        }) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SupplierDropdownButton: View {
    let selectedSupplier: EntityWithType?
    let placeholder: String
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    @Binding var searchText: String
    @FocusState.Binding var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if isOpen {
                    TextField("Search...", text: $searchText)
                        .font(.body)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.primary)
                        .focused($isFocused)
                        .onAppear {
                            DispatchQueue.main.async {
                                isFocused = true
                            }
                        }
                } else {
                    if let selectedSupplier = selectedSupplier {
                        HStack(spacing: 8) {
                            Text("[\(selectedSupplier.entityType.rawValue)]")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(selectedSupplier.entityType.color)
                                )
                            
                            Text(selectedSupplier.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    } else {
                        Text(placeholder)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        buttonFrame = newFrame
                    }
            }
        )
        .onTapGesture {
            withAnimation {
                isOpen.toggle()
            }
            // Remove focus from main field when opening dropdown
            if isOpen {
                isFocused = false
            }
        }
    }
}

struct SupplierDropdownOverlay: View {
    @Binding var isOpen: Bool
    @Binding var selectedSupplier: EntityWithType?
    let entities: [EntityWithType]
    let buttonFrame: CGRect
    let searchText: String
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var localSearchText = ""
    @FocusState private var isLocalSearchFocused: Bool
    
    private var overlayWidth: CGFloat {
        #if os(macOS)
        return max(400, buttonFrame.width)
        #else
        if horizontalSizeClass == .compact {
            return UIScreen.main.bounds.width - 32
        } else {
            return max(400, buttonFrame.width)
        }
        #endif
    }
    
    // Filtered entities - use local search for iPhone, main field search for iPad/macOS
    private var filteredEntities: [EntityWithType] {
        let effectiveSearchText = horizontalSizeClass == .compact ? localSearchText : searchText
        
        let filtered: [EntityWithType]
        if effectiveSearchText.isEmpty {
            filtered = entities
        } else {
            filtered = entities.filter { entity in
                entity.name.localizedCaseInsensitiveContains(effectiveSearchText) ||
                entity.entityType.rawValue.localizedCaseInsensitiveContains(effectiveSearchText)
            }
        }
        
        // Sort to put suppliers on top
        return filtered.sorted { entity1, entity2 in
            if entity1.entityType == .supplier && entity2.entityType != .supplier {
                return true
            } else if entity1.entityType != .supplier && entity2.entityType == .supplier {
                return false
            } else {
                return entity1.name < entity2.name
            }
        }
    }
    
    var body: some View {
        centeredOverlay
    }
    
    // Platform-specific overlay implementation
    @ViewBuilder
    private var centeredOverlay: some View {
        if horizontalSizeClass == .compact {
            // iPhone: Centered modal overlay
            iphoneModalOverlay
        } else {
            // iPad/macOS: Positioned dropdown below field
            positionedDropdown
        }
    }
    
    private var iphoneModalOverlay: some View {
        ZStack {
            // Full screen background
            Color.black.opacity(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    isOpen = false
                }
                .onAppear {
                    localSearchText = ""
                    // Focus the internal search field for iPhone
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if horizontalSizeClass == .compact {
                            isLocalSearchFocused = true
                        }
                    }
                }
            
            // Centered dialog
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Select Supplier")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        isOpen = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.regularMaterial)
                
                Divider()
                
                // Search field (iPhone only)
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search entities...", text: $localSearchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.body)
                        .focused($isLocalSearchFocused)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        #endif
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Entity list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredEntities.isEmpty {
                            Text("No entities found")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 40)
                        } else {
                            ForEach(filteredEntities, id: \.id) { entity in
                                entityRow(for: entity)
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
                .background(.regularMaterial)
            }
            .background(.regularMaterial)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
    }
    
    private var positionedDropdown: some View {
        ZStack {
            // Transparent background to capture taps
            Color.black.opacity(0.001)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation {
                        isOpen = false
                    }
                }
            
            // Clean dropdown directly attached to field
            VStack(alignment: .leading, spacing: 0) {
                // Entity list only - no search bar
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredEntities) { entity in
                            cleanEntityRow(for: entity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: 250)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .frame(width: buttonFrame.width)
            .position(
                x: buttonFrame.midX,
                y: buttonFrame.maxY + 5 + 125
            )
        }
    }
    
    private func cleanEntityRow(for entity: EntityWithType) -> some View {
        Button(action: {
            withAnimation {
                selectedSupplier = entity
                isOpen = false
            }
        }) {
            HStack(spacing: 16) {
                // Entity type badge - using app's standard badge style
                Text(entity.entityType.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(entity.entityType.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(entity.entityType.color.opacity(0.1))
                            .stroke(entity.entityType.color.opacity(0.3), lineWidth: 1)
                    )
                
                // Entity name
                Text(entity.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Selection indicator
                if selectedSupplier?.id == entity.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(entity.entityType.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                selectedSupplier?.id == entity.id ?
                entity.entityType.color.opacity(0.1) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func entityRow(for entity: EntityWithType) -> some View {
        Button(action: {
            withAnimation {
                selectedSupplier = entity
                isOpen = false
            }
        }) {
            HStack(spacing: 16) {
                // Entity type badge - using app's standard badge style
                Text(entity.entityType.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(entity.entityType.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(entity.entityType.color.opacity(0.1))
                            .stroke(entity.entityType.color.opacity(0.3), lineWidth: 1)
                    )
                
                // Entity name
                Text(entity.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Selection indicator
                if selectedSupplier?.id == entity.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(entity.entityType.color)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                selectedSupplier?.id == entity.id ?
                entity.entityType.color.opacity(0.1) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    PurchaseView(
        showingSupplierDropdown: .constant(false),
        selectedSupplier: .constant(nil),
        supplierButtonFrame: .constant(.zero),
        allEntities: .constant([]),
        supplierSearchText: .constant("")
    )
}
