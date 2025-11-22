//
//  ProfilesView.swift
//  Aromex
//
//  Created by Ansh Bajaj on 29/08/25.
//

import SwiftUI
import FirebaseFirestore

struct ProfilesView: View {
    @Binding var isDeletingEntity: Bool
    @Binding var showDeleteEntitySuccess: Bool
    @State private var searchText = ""
    @State private var selectedTab: EntityType = .customer
    @State private var customers: [EntityProfile] = []
    @State private var suppliers: [EntityProfile] = []
    @State private var middlemen: [EntityProfile] = []
    @State private var isLoading = false
    @State private var listeners: [ListenerRegistration] = []
    @State private var showingDeleteConfirmation = false
    @State private var entityToDelete: EntityProfile?
    @State private var selectedEntity: EntityProfile?
    @State private var showingEntityDetail = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    
    var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    var filteredEntities: [EntityProfile] {
        let entities = getEntitiesForSelectedTab()
        if searchText.isEmpty {
            return entities
        } else {
            return entities.filter { entity in
                entity.name.localizedCaseInsensitiveContains(searchText) ||
                entity.phone.localizedCaseInsensitiveContains(searchText) ||
                String(format: "%.2f", entity.balance).contains(searchText) ||
                String(format: "%.0f", entity.balance).contains(searchText)
            }
        }
    }
    
    private func getEntitiesForSelectedTab() -> [EntityProfile] {
        switch selectedTab {
        case .customer: return customers
        case .supplier: return suppliers
        case .middleman: return middlemen
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                searchBar
                
                // Tab Selection
                tabSelection
                
                // Content
                if isLoading {
                    loadingView
                } else {
                    entitiesList
                }
            }
            .background(.regularMaterial)
            .onAppear {
                setupRealtimeListeners()
            }
            .onDisappear {
                removeListeners()
            }
            .alert("Delete Entity", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    entityToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let entity = entityToDelete {
                        deleteEntity(entity)
                    }
                }
            } message: {
                if let entity = entityToDelete {
                    Text("Are you sure you want to delete \(entity.name)? This action cannot be undone.")
                }
            }
            .navigationDestination(isPresented: $showingEntityDetail) {
                if let selectedEntity = selectedEntity {
                    EntityDetailView(
                        entity: selectedEntity,
                        entityType: selectedTab
                    )
                }
            }
        }
    }
    
    
    var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: isCompact ? 14 : 16, weight: .medium))
            
            TextField("Search by name, phone, or balance...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: isCompact ? 15 : 16, weight: .medium))
        }
        .padding(.horizontal, isCompact ? 14 : 16)
        .padding(.vertical, isCompact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 10 : 12)
                .fill(.regularMaterial)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, isCompact ? 16 : 30)
        .padding(.top, isCompact ? 8 : 0)
        .padding(.bottom, isCompact ? 16 : 20)
    }
    
    var tabSelection: some View {
        HStack(spacing: isCompact ? 6 : 12) {
            ForEach(EntityType.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, isCompact ? 16 : 30)
        .padding(.bottom, isCompact ? 16 : 20)
    }
    
    func tabButton(for tab: EntityType) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTab = tab
            }
        }) {
            tabButtonContent(for: tab)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(selectedTab == tab ? 1.02 : 1.0)
        .onHover { isHovering in
            #if os(macOS)
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
            #endif
        }
    }
    
    func tabButtonContent(for tab: EntityType) -> some View {
        HStack(spacing: isCompact ? 6 : 10) {
            tabIcon(for: tab)
            if isCompact {
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(selectedTab == tab ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                tabTextContent(for: tab)
                Spacer()
            }
        }
        .padding(.horizontal, isCompact ? 10 : 20)
        .padding(.vertical, isCompact ? 8 : 16)
        .frame(maxWidth: isCompact ? .infinity : nil)
        .background(tabButtonBackground(for: tab))
    }
    
    func tabIcon(for tab: EntityType) -> some View {
        ZStack {
            Circle()
                .fill(selectedTab == tab ? tab.color : tab.color.opacity(0.1))
                .frame(width: isCompact ? 24 : 32, height: isCompact ? 24 : 32)
            
            Image(systemName: tab.icon)
                .font(.system(size: isCompact ? 12 : 16, weight: .semibold))
                .foregroundColor(selectedTab == tab ? .white : tab.color)
        }
    }
    
    func tabTextContent(for tab: EntityType) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tab.rawValue)
                .font(.system(size: isCompact ? 14 : 16, weight: .bold))
                .foregroundColor(selectedTab == tab ? .white : .primary)
            
            Text("\(getEntityCount(for: tab)) entities")
                .font(.system(size: isCompact ? 10 : 12, weight: .medium))
                .foregroundColor(selectedTab == tab ? .white.opacity(0.8) : .secondary)
        }
    }
    
    func tabButtonBackground(for tab: EntityType) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(selectedTab == tab ? tab.color : Color.gray.opacity(0.1))
            .stroke(selectedTab == tab ? Color.clear : tab.color.opacity(0.3), lineWidth: 2)
            .shadow(
                color: selectedTab == tab ? tab.color.opacity(0.3) : .clear,
                radius: selectedTab == tab ? 8 : 0,
                x: 0,
                y: selectedTab == tab ? 4 : 0
            )
    }
    
    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle(tint: .primary))
            
            Text("Loading profiles...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var entitiesList: some View {
        Group {
            if filteredEntities.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredEntities) { entity in
                            EntityProfileCard(
                                entity: entity,
                                type: selectedTab,
                                onDelete: {
                                    entityToDelete = entity
                                    showingDeleteConfirmation = true
                                },
                                onTap: {
                                    selectedEntity = entity
                                    showingEntityDetail = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, isCompact ? 16 : 30)
                    .padding(.top, isCompact ? 8 : 0)
                    .padding(.bottom, isCompact ? 16 : 20)
                }
            }
        }
    }
    
    
    var emptyStateView: some View {
        VStack(spacing: isCompact ? 16 : 20) {
            Image(systemName: selectedTab.icon)
                .font(.system(size: isCompact ? 50 : 60, weight: .light))
                .foregroundColor(selectedTab.color.opacity(0.3))
            
            VStack(spacing: isCompact ? 6 : 8) {
                Text("No \(selectedTab.rawValue.lowercased())s found")
                    .font(.system(size: isCompact ? 18 : 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                if searchText.isEmpty {
                    Text("Add your first \(selectedTab.rawValue.lowercased()) to get started")
                        .font(.system(size: isCompact ? 14 : 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Try adjusting your search terms")
                        .font(.system(size: isCompact ? 14 : 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, isCompact ? 30 : 40)
    }
    
    private func getEntityCount(for type: EntityType) -> Int {
        switch type {
        case .customer: return customers.count
        case .supplier: return suppliers.count
        case .middleman: return middlemen.count
        }
    }
    
    private func setupRealtimeListeners() {
        // Remove any existing listeners first to prevent duplicates
        removeListeners()
        
        let db = Firestore.firestore()
        
        // Set up listeners for each entity type
        setupListener(for: .customer, collection: db.collection("Customers"))
        setupListener(for: .supplier, collection: db.collection("Suppliers"))
        setupListener(for: .middleman, collection: db.collection("Middlemen"))
        
        isLoading = false
    }
    
    private func setupListener(for type: EntityType, collection: CollectionReference) {
        let listener = collection.addSnapshotListener { [self] snapshot, error in
            guard let snapshot = snapshot else {
                print("Error listening to \(type.rawValue.lowercased())s: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            let entities = snapshot.documents.compactMap { doc -> EntityProfile? in
                let data = doc.data()
                return EntityProfile(
                    id: doc.documentID,
                    name: data["name"] as? String ?? "",
                    phone: data["phone"] as? String ?? "",
                    email: data["email"] as? String ?? "",
                    balance: data["balance"] as? Double ?? 0.0,
                    address: data["address"] as? String ?? "",
                    notes: data["notes"] as? String ?? ""
                )
            }
            
            // Update the appropriate array on the main thread
            DispatchQueue.main.async {
                switch type {
                case .customer:
                    customers = entities
                case .supplier:
                    suppliers = entities
                case .middleman:
                    middlemen = entities
                }
            }
        }
        
        // Store the listener for cleanup
        listeners.append(listener)
    }
    
    private func removeListeners() {
        // Remove all listeners to prevent memory leaks and duplicate updates
        listeners.forEach { listener in
            listener.remove()
        }
        listeners.removeAll()
    }
    
    private func deleteEntity(_ entity: EntityProfile) {
        isDeletingEntity = true
        entityToDelete = nil
        
        let db = Firestore.firestore()
        let collectionName = selectedTab.collectionName
        
        db.collection(collectionName).document(entity.id).delete { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error deleting entity: \(error.localizedDescription)")
                    isDeletingEntity = false
                } else {
                    // Show success confirmation
                    showDeleteEntitySuccess = true
                    
                    // Haptic feedback
                    #if os(iOS)
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        impactFeedback.impactOccurred()
                    }
                    #endif
                    
                    // Hide success after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isDeletingEntity = false
                        showDeleteEntitySuccess = false
                    }
                }
            }
        }
    }
    
}


struct EntityProfileCard: View {
    let entity: EntityProfile
    let type: EntityType
    let onDelete: () -> Void
    let onTap: () -> Void
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    var body: some View {
        if isCompact {
            // iPhone: Optimized mobile card layout
            HStack(spacing: 12) {
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Name
                    Text(entity.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // Balance
                    Text(formatCurrency(entity.balance))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(getBalanceColor(entity.balance))
                    
                    // Phone (if available) - iPhone only
                    if !entity.phone.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(entity.phone)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Delete Button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.red)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
            )
            .onTapGesture {
                onTap()
            }
            .onHover { isHovering in
                #if os(macOS)
                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
                #endif
            }
        } else {
            // macOS/iPad: Table layout
            HStack(spacing: 0) {
                // Name Column - starts from far left
                Text(entity.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Balance Column - equally spaced
                Text(formatCurrency(entity.balance))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(getBalanceColor(entity.balance))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Phone Column - equally spaced
                Text(entity.phone.isEmpty ? "—" : entity.phone)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Actions Column - pushed to far right
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.red)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .onTapGesture {
                onTap()
            }
            .onHover { isHovering in
                #if os(macOS)
                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
                #endif
            }
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    private func getBalanceColor(_ amount: Double) -> Color {
        if amount > 0 {
            return .green
        } else if amount < 0 {
            return .red
        } else {
            return .secondary
        }
    }
}

#Preview {
    ProfilesView(
        isDeletingEntity: .constant(false),
        showDeleteEntitySuccess: .constant(false)
    )
}
