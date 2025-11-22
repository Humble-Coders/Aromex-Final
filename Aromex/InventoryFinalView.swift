import SwiftUI
import FirebaseFirestore

// MARK: - Data Models
struct InventoryPhone: Identifiable, Hashable {
    let id: String
    let brandId: String
    let modelId: String
    let brand: String
    let model: String
    let capacity: String
    let capacityUnit: String
    let color: String
    let carrier: String
    let status: String
    let storageLocation: String
    let imei: String
    let unitCost: Double
    let createdAt: Date
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: InventoryPhone, rhs: InventoryPhone) -> Bool {
        lhs.id == rhs.id
    }
}

struct GroupedPhone: Identifiable {
    let id = UUID()
    let brand: String
    let model: String
    let capacity: String
    let capacityUnit: String
    let color: String
    let carrier: String
    let status: String
    let storageLocation: String
    let unitCost: Double
    let phones: [InventoryPhone]
    
    var quantity: Int { phones.count }
    var imeis: [String] { phones.map { $0.imei } }
}

struct GroupedModel: Identifiable, Equatable {
    let id = UUID()
    let brand: String
    let model: String
    let phones: [InventoryPhone]
    
    var totalQuantity: Int { phones.count }
    var activeCount: Int { phones.filter { $0.status.lowercased() == "active" }.count }
    var inactiveCount: Int { phones.filter { $0.status.lowercased() != "active" }.count }
    var averagePrice: Double { phones.isEmpty ? 0 : phones.map { $0.unitCost }.reduce(0, +) / Double(phones.count) }
    
    static func == (lhs: GroupedModel, rhs: GroupedModel) -> Bool {
        lhs.id == rhs.id
    }
}

struct CapacityColorGroup: Identifiable {
    let id = UUID()
    let capacity: String
    let capacityUnit: String
    let color: String
    let phones: [InventoryPhone]
    
    var quantity: Int { phones.count }
    var imeis: [String] { phones.map { $0.imei } }
}

struct StorageLocation: Identifiable, Hashable {
    let id: String
    let name: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: StorageLocation, rhs: StorageLocation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - View Model
@MainActor
class InventoryFinalViewModel: ObservableObject {
    @Published var allPhones: [InventoryPhone] = []
    @Published var storageLocations: [StorageLocation] = []
    @Published var selectedLocation: StorageLocation?
    @Published var selectedModel: GroupedModel?
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var selectedBrand: String?
    @Published var selectedStatus: String?
    @Published var sortOption: SortOption = .brandAZ
    
    enum SortOption: String, CaseIterable {
        case brandAZ = "Brand (A-Z)"
        case brandZA = "Brand (Z-A)"
        case modelAZ = "Model (A-Z)"
        case modelZA = "Model (Z-A)"
        case quantityHigh = "Quantity (High-Low)"
        case quantityLow = "Quantity (Low-High)"
        case priceHigh = "Price (High-Low)"
        case priceLow = "Price (Low-High)"
    }
    
    private var db = Firestore.firestore()
    private var referenceCache: [String: String] = [:]
    
    var filteredAndSortedPhones: [InventoryPhone] {
        var phones = allPhones
        
        if let location = selectedLocation {
            phones = phones.filter { $0.storageLocation == location.name }
        }
        
        if !searchText.isEmpty {
            phones = phones.filter {
                $0.brand.localizedCaseInsensitiveContains(searchText) ||
                $0.model.localizedCaseInsensitiveContains(searchText) ||
                $0.imei.localizedCaseInsensitiveContains(searchText) ||
                $0.color.localizedCaseInsensitiveContains(searchText) ||
                $0.carrier.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let brand = selectedBrand {
            phones = phones.filter { $0.brand == brand }
        }
        
        if let status = selectedStatus {
            phones = phones.filter { $0.status == status }
        }
        
        return phones
    }
    
    var groupedModels: [String: [GroupedModel]] {
        let phones = filteredAndSortedPhones
        var grouped: [String: [GroupedModel]] = [:]
        
        let brandGroups = Dictionary(grouping: phones) { $0.brand }
        
        for (brand, brandPhones) in brandGroups {
            let modelGroups = Dictionary(grouping: brandPhones) { phone in
                "\(phone.model)"
            }
            
            var brandGroupedModels: [GroupedModel] = []
            
            for (_, modelPhones) in modelGroups {
                if let firstPhone = modelPhones.first {
                    let groupedModel = GroupedModel(
                        brand: firstPhone.brand,
                        model: firstPhone.model,
                        phones: modelPhones
                    )
                    brandGroupedModels.append(groupedModel)
                }
            }
            
            brandGroupedModels = sortGroupedModels(brandGroupedModels)
            grouped[brand] = brandGroupedModels
        }
        
        return grouped
    }
    
    var capacityColorGroups: [String: [CapacityColorGroup]] {
        guard let selectedModel = selectedModel else { return [:] }
        
        let phones = selectedModel.phones
        var grouped: [String: [CapacityColorGroup]] = [:]
        
        let capacityGroups = Dictionary(grouping: phones) { phone in
            "\(phone.capacity) \(phone.capacityUnit)"
        }
        
        for (capacity, capacityPhones) in capacityGroups {
            let colorGroups = Dictionary(grouping: capacityPhones) { phone in
                phone.color
            }
            
            var capacityGroupedPhones: [CapacityColorGroup] = []
            
            for (color, colorPhones) in colorGroups {
                if let firstPhone = colorPhones.first {
                    let capacityColorGroup = CapacityColorGroup(
                        capacity: firstPhone.capacity,
                        capacityUnit: firstPhone.capacityUnit,
                        color: firstPhone.color,
                        phones: colorPhones
                    )
                    capacityGroupedPhones.append(capacityColorGroup)
                }
            }
            
            capacityGroupedPhones = capacityGroupedPhones.sorted { $0.color < $1.color }
            grouped[capacity] = capacityGroupedPhones
        }
        
        return grouped
    }
    
    var sortedBrands: [String] {
        let brands = Array(groupedModels.keys)
        switch sortOption {
        case .brandAZ:
            return brands.sorted()
        case .brandZA:
            return brands.sorted(by: >)
        default:
            return brands.sorted()
        }
    }
    
    var availableBrands: [String] {
        Array(Set(allPhones.map { $0.brand })).sorted()
    }
    
    var availableStatuses: [String] {
        Array(Set(allPhones.map { $0.status })).sorted()
    }
    
    var totalInventoryValue: Double {
        filteredAndSortedPhones.reduce(0) { $0 + $1.unitCost }
    }
    
    private func sortGroupedModels(_ models: [GroupedModel]) -> [GroupedModel] {
        switch sortOption {
        case .brandAZ, .brandZA:
            return models.sorted { $0.model < $1.model }
        case .modelAZ:
            return models.sorted { $0.model < $1.model }
        case .modelZA:
            return models.sorted { $0.model > $1.model }
        case .quantityHigh:
            return models.sorted { $0.totalQuantity > $1.totalQuantity }
        case .quantityLow:
            return models.sorted { $0.totalQuantity < $1.totalQuantity }
        case .priceHigh:
            return models.sorted { $0.averagePrice > $1.averagePrice }
        case .priceLow:
            return models.sorted { $0.averagePrice < $1.averagePrice }
        }
    }
    
    private func sortGroupedPhones(_ phones: [GroupedPhone]) -> [GroupedPhone] {
        switch sortOption {
        case .brandAZ, .brandZA:
            return phones.sorted { $0.model < $1.model }
        case .modelAZ:
            return phones.sorted { $0.model < $1.model }
        case .modelZA:
            return phones.sorted { $0.model > $1.model }
        case .quantityHigh:
            return phones.sorted { $0.quantity > $1.quantity }
        case .quantityLow:
            return phones.sorted { $0.quantity < $1.quantity }
        case .priceHigh:
            return phones.sorted { $0.unitCost > $1.unitCost }
        case .priceLow:
            return phones.sorted { $0.unitCost < $1.unitCost }
        }
    }
    
    func fetchAllData() async {
        isLoading = true
        referenceCache.removeAll()
        
        async let locationsTask = fetchStorageLocations()
        async let referencesTask = fetchAllReferences()
        async let phonesTask = fetchAllPhones()
        
        _ = await (locationsTask, referencesTask, phonesTask)
        
        isLoading = false
    }
    
    private func fetchStorageLocations() async {
        do {
            let snapshot = try await db.collection("StorageLocations").getDocuments()
            print("DEBUG: Fetched \(snapshot.documents.count) StorageLocations documents")
            for doc in snapshot.documents {
                print("DEBUG: Document \(doc.documentID) data: \(doc.data())")
            }
            storageLocations = snapshot.documents.compactMap { doc in
                guard let name = doc.data()["storageLocation"] as? String else { 
                    print("DEBUG: Document \(doc.documentID) missing storageLocation field")
                    return nil 
                }
                print("DEBUG: Found location: \(name)")
                return StorageLocation(id: doc.documentID, name: name)
            }.sorted { $0.name < $1.name }
            print("DEBUG: Final storageLocations count: \(storageLocations.count)")
        } catch {
            print("Error fetching storage locations: \(error)")
        }
    }
    
    private func fetchAllReferences() async {
        async let colorsTask = fetchReferenceCollection("Colors")
        async let carriersTask = fetchReferenceCollection("Carriers")
        async let locationsTask = fetchReferenceCollection("StorageLocations")
        
        _ = await (colorsTask, carriersTask, locationsTask)
    }
    
    private func fetchReferenceCollection(_ collection: String) async {
        do {
            let snapshot = try await db.collection(collection).getDocuments()
            for doc in snapshot.documents {
                let fieldKey = (collection == "StorageLocations") ? "storageLocation" : "name"
                if let name = doc.data()[fieldKey] as? String {
                    referenceCache[doc.documentID] = name
                }
            }
        } catch {
            print("Error fetching \(collection): \(error)")
        }
    }
    
    private func fetchAllPhones() async {
        var phones: [InventoryPhone] = []
        
        do {
            let brandsSnapshot = try await db.collection("PhoneBrands").getDocuments()
            
            await withTaskGroup(of: [InventoryPhone].self) { group in
                for brandDoc in brandsSnapshot.documents {
                    group.addTask {
                        await self.fetchPhonesForBrand(brandDoc: brandDoc)
                    }
                }
                
                for await brandPhones in group {
                    phones.append(contentsOf: brandPhones)
                }
            }
            
            allPhones = phones.sorted { $0.brand < $1.brand }
        } catch {
            print("Error fetching phones: \(error)")
        }
    }
    
    private func fetchPhonesForBrand(brandDoc: QueryDocumentSnapshot) async -> [InventoryPhone] {
        var phones: [InventoryPhone] = []
        let brandId = brandDoc.documentID
        let brandName = brandDoc.data()["brand"] as? String ?? "Unknown"
        
        do {
            let modelsSnapshot = try await brandDoc.reference.collection("Models").getDocuments()
            
            await withTaskGroup(of: [InventoryPhone].self) { group in
                for modelDoc in modelsSnapshot.documents {
                    group.addTask {
                        await self.fetchPhonesForModel(modelDoc: modelDoc, brandId: brandId, brandName: brandName)
                    }
                }
                
                for await modelPhones in group {
                    phones.append(contentsOf: modelPhones)
                }
            }
        } catch {
            print("Error fetching models for brand \(brandName): \(error)")
        }
        
        return phones
    }
    
    private func fetchPhonesForModel(modelDoc: QueryDocumentSnapshot, brandId: String, brandName: String) async -> [InventoryPhone] {
        var phones: [InventoryPhone] = []
        let modelId = modelDoc.documentID
        let modelName = modelDoc.data()["model"] as? String ?? "Unknown"
        
        do {
            let phonesSnapshot = try await modelDoc.reference.collection("Phones").getDocuments()
            
            for phoneDoc in phonesSnapshot.documents {
                if let phone = createPhone(from: phoneDoc, brandId: brandId, modelId: modelId, brand: brandName, model: modelName) {
                    phones.append(phone)
                }
            }
        } catch {
            print("Error fetching phones for model \(modelName): \(error)")
        }
        
        return phones
    }
    
    private func createPhone(from doc: QueryDocumentSnapshot, brandId: String, modelId: String, brand: String, model: String) -> InventoryPhone? {
        let data = doc.data()
        
        let color = getReferenceName(from: data["color"])
        let carrier = getReferenceName(from: data["carrier"])
        let storageLocation = getReferenceName(from: data["storageLocation"])
        
        return InventoryPhone(
            id: doc.documentID,
            brandId: brandId,
            modelId: modelId,
            brand: brand,
            model: model,
            capacity: data["capacity"] as? String ?? "",
            capacityUnit: data["capacityUnit"] as? String ?? "",
            color: color,
            carrier: carrier,
            status: data["status"] as? String ?? "",
            storageLocation: storageLocation,
            imei: data["imei"] as? String ?? "",
            unitCost: data["unitCost"] as? Double ?? 0.0,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    private func getReferenceName(from value: Any?) -> String {
        guard let ref = value as? DocumentReference else { return "" }
        return referenceCache[ref.documentID] ?? ""
    }
    
    func clearFilters() {
        searchText = ""
        selectedBrand = nil
        selectedStatus = nil
        sortOption = .brandAZ
    }
    
    func goBackToModels() {
        selectedModel = nil
    }
    
    func deletePhone(_ phone: InventoryPhone) async {
        do {
            // Construct the exact Firestore path and delete the document
            let phoneRef = db.collection("PhoneBrands")
                .document(phone.brandId)
                .collection("Models")
                .document(phone.modelId)
                .collection("Phones")
                .document(phone.id)
            
            try await phoneRef.delete()
            
            // Remove from local array - this will automatically update counts
            await MainActor.run {
                allPhones.removeAll { $0.id == phone.id }
            }
            
            print("✅ Successfully deleted phone with IMEI: \(phone.imei)")
        } catch {
            print("❌ Error deleting phone: \(error.localizedDescription)")
        }
    }
}

// MARK: - Main View
struct InventoryFinalView: View {
    @StateObject private var viewModel = InventoryFinalViewModel()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.colorScheme) var colorScheme
    @State private var modelDetailSearchText = ""
    
    var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    var body: some View {
        #if os(macOS)
        macOSLayout
            .frame(minWidth: 1000, minHeight: 700)
            .task {
                await viewModel.fetchAllData()
            }
            .onChange(of: viewModel.selectedLocation) { _ in
                // Reset to brands view when location changes
                viewModel.selectedModel = nil
                modelDetailSearchText = ""
            }
            .onChange(of: viewModel.selectedModel) { _ in
                // Clear search when model changes
                modelDetailSearchText = ""
            }
        #else
        Group {
            if isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .task {
            await viewModel.fetchAllData()
        }
        .onChange(of: viewModel.selectedLocation) { _ in
            // Reset to brands view when location changes
            viewModel.selectedModel = nil
            modelDetailSearchText = ""
        }
        .onChange(of: viewModel.selectedModel) { _ in
            // Clear search when model changes
            modelDetailSearchText = ""
        }
        #endif
    }
    
    // MARK: - macOS Layout
    #if os(macOS)
    private var macOSLayout: some View {
        HStack(spacing: 0) {
            // Fixed Sidebar
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    StatCard(
                        title: "Locations",
                        value: "\(viewModel.storageLocations.count)",
                        icon: "building.2.fill",
                        color: .blue
                    )
                    
                    StatCard(
                        title: "Total Devices",
                        value: "\(viewModel.allPhones.count)",
                        icon: "iphone.gen3",
                        color: .purple
                    )
                    
                    StatCard(
                        title: "Total Value",
                        value: "$\(Int(viewModel.totalInventoryValue))",
                        icon: "dollarsign.circle.fill",
                        color: .green
                    )
                }
                .padding(16)
                
                Divider()
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage Locations")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(viewModel.storageLocations) { location in
                                Button {
                                    viewModel.selectedLocation = location
                                } label: {
                                    LocationRow(
                                        location: location,
                                        deviceCount: viewModel.allPhones.filter { $0.storageLocation == location.name }.count,
                                        isSelected: viewModel.selectedLocation?.id == location.id
                                    )
                                    .padding(.horizontal, 12)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    viewModel.selectedLocation?.id == location.id ?
                                    Color.accentColor.opacity(0.1) : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 8)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(width: 300)
            .background(.ultraThinMaterial)
            .fixedSize(horizontal: true, vertical: false)
            
            Divider()
            
            // Main Content Area
            if viewModel.selectedLocation != nil {
                if viewModel.selectedModel != nil {
                    modelDetailContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    inventoryListContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptySelectionView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif
    
    // MARK: - Compact Layout (iPhone)
    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.selectedLocation == nil {
                    locationGridView
                } else {
                    // Main content area - handles both inventory list and model detail
                    if viewModel.selectedModel != nil {
                        modelDetailContent
                    } else {
                        inventoryListContent
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if viewModel.selectedLocation != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            if viewModel.selectedModel != nil {
                                viewModel.goBackToModels()
                            } else {
                                viewModel.selectedLocation = nil
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text(viewModel.selectedModel != nil ? "Models" : "Locations")
                            }
                            .font(.body)
                        }
                    }
                }
            }
            #endif
        }
    }
    
    // MARK: - Regular Layout (iPad)
    private var regularLayout: some View {
        HStack(spacing: 0) {
            locationSidebarView
                .frame(width: 320)
            
            Divider()
            
            if viewModel.selectedLocation != nil {
                if viewModel.selectedModel != nil {
                    modelDetailContent
                } else {
                    inventoryListContent
                }
            } else {
                emptySelectionView
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            
            Text("Loading Inventory")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Location Grid View
    private var locationGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: locationGridColumns,
                spacing: isCompact ? 12 : 16
            ) {
                ForEach(viewModel.storageLocations) { location in
                    LocationCard(
                        location: location,
                        deviceCount: viewModel.allPhones.filter { $0.storageLocation == location.name }.count,
                        isSelected: viewModel.selectedLocation?.id == location.id
                    ) {
                        viewModel.selectedLocation = location
                    }
                }
            }
            #if os(iOS)
            .padding(.horizontal, 16)
            .padding(.vertical, isCompact ? 16 : 20)
            #else
            .padding()
            #endif
        }
        .background(backgroundGray)
        .navigationTitle("Storage Locations")
        #if os(iOS)
        .safeAreaInset(edge: .top, spacing: 0) {
            if isCompact {
                statsHeaderView
            }
        }
        #else
        .safeAreaInset(edge: .top, spacing: 0) {
            statsHeaderView
        }
        #endif
    }
    
    private var locationGridColumns: [GridItem] {
        #if os(iOS)
        if isCompact {
            return [GridItem(.flexible()), GridItem(.flexible())]
        } else {
            return [GridItem(.adaptive(minimum: 280))]
        }
        #else
        return [GridItem(.adaptive(minimum: 280))]
        #endif
    }
    
    private var statsHeaderView: some View {
        HStack(spacing: isCompact ? 8 : 16) {
            StatCard(
                title: "Locations",
                value: "\(viewModel.storageLocations.count)",
                icon: "building.2.fill",
                color: .blue
            )
            #if os(iOS)
            .frame(maxWidth: isCompact ? .infinity : nil)
            #endif
            
            StatCard(
                title: "Total Devices",
                value: "\(viewModel.allPhones.count)",
                icon: "iphone.gen3",
                color: .purple
            )
            #if os(iOS)
            .frame(maxWidth: isCompact ? .infinity : nil)
            #endif
            
            StatCard(
                title: "Total Value",
                value: "$\(Int(viewModel.totalInventoryValue))",
                icon: "dollarsign.circle.fill",
                color: .green
            )
            #if os(iOS)
            .frame(maxWidth: isCompact ? .infinity : nil)
            #endif
        }
        #if os(iOS)
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.vertical, isCompact ? 12 : 16)
        #else
        .padding()
        #endif
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Location Sidebar
    private var locationSidebarView: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    StatCard(
                        title: "Locations",
                        value: "\(viewModel.storageLocations.count)",
                        icon: "building.2.fill",
                        color: .blue
                    )
                    
                    StatCard(
                        title: "Total Devices",
                        value: "\(viewModel.allPhones.count)",
                        icon: "iphone.gen3",
                        color: .purple
                    )
                    
                    StatCard(
                        title: "Total Value",
                        value: "$\(Int(viewModel.totalInventoryValue))",
                        icon: "dollarsign.circle.fill",
                        color: .green
                    )
                }
                .padding(16)
                
                Divider()
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage Locations")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    
                    ForEach(viewModel.storageLocations) { location in
                        Button {
                            viewModel.selectedLocation = location
                        } label: {
                            LocationRow(
                                location: location,
                                deviceCount: viewModel.allPhones.filter { $0.storageLocation == location.name }.count,
                                isSelected: viewModel.selectedLocation?.id == location.id
                            )
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .background(
                            viewModel.selectedLocation?.id == location.id ?
                            Color.accentColor.opacity(0.1) : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Empty Selection View
    private var emptySelectionView: some View {
        ContentUnavailableView(
            "Select a Location",
            systemImage: "location.fill.viewfinder",
            description: Text("Choose a storage location to view inventory")
        )
    }
    
    // MARK: - Inventory List Content
    private var inventoryListContent: some View {
        VStack(spacing: 0) {
            filterBar
            
            Divider()
            
            ScrollView {
                if viewModel.filteredAndSortedPhones.isEmpty {
                    emptyStateView
                        .frame(maxHeight: .infinity)
                } else {
                    inventoryGrid
                }
            }
            #if os(macOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(backgroundGray)
        }
        .navigationTitle(viewModel.selectedLocation?.name ?? "Inventory")
        #if os(iOS)
        .navigationBarTitleDisplayMode(isCompact ? .large : .inline)
        #endif
    }
    
    // MARK: - Filter Bar
    private var filterBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SearchField(text: $viewModel.searchText)
                    .frame(maxWidth: 400)
                
                #if os(macOS)
                Spacer()
                
                FilterMenu(
                    title: viewModel.selectedBrand ?? "All Brands",
                    icon: "building.2",
                    options: ["All Brands"] + viewModel.availableBrands,
                    selection: Binding(
                        get: { viewModel.selectedBrand ?? "All Brands" },
                        set: { viewModel.selectedBrand = $0 == "All Brands" ? nil : $0 }
                    )
                )
                
                FilterMenu(
                    title: viewModel.selectedStatus ?? "All Status",
                    icon: "checkmark.circle",
                    options: ["All Status"] + viewModel.availableStatuses,
                    selection: Binding(
                        get: { viewModel.selectedStatus ?? "All Status" },
                        set: { viewModel.selectedStatus = $0 == "All Status" ? nil : $0 }
                    )
                )
                
                Menu {
                    Picker("Sort", selection: $viewModel.sortOption) {
                        ForEach(InventoryFinalViewModel.SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text("Sort")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                
                if viewModel.selectedBrand != nil || viewModel.selectedStatus != nil {
                    Button(action: viewModel.clearFilters) {
                        Label("Clear", systemImage: "xmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                #else
                if !isCompact {
                    Spacer()
                    
                    FilterMenu(
                        title: viewModel.selectedBrand ?? "All Brands",
                        icon: "building.2",
                        options: ["All Brands"] + viewModel.availableBrands,
                        selection: Binding(
                            get: { viewModel.selectedBrand ?? "All Brands" },
                            set: { viewModel.selectedBrand = $0 == "All Brands" ? nil : $0 }
                        )
                    )
                    
                    FilterMenu(
                        title: viewModel.selectedStatus ?? "All Status",
                        icon: "checkmark.circle",
                        options: ["All Status"] + viewModel.availableStatuses,
                        selection: Binding(
                            get: { viewModel.selectedStatus ?? "All Status" },
                            set: { viewModel.selectedStatus = $0 == "All Status" ? nil : $0 }
                        )
                    )
                    
                    Menu {
                        Picker("Sort", selection: $viewModel.sortOption) {
                            ForEach(InventoryFinalViewModel.SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text("Sort")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    
                    if viewModel.selectedBrand != nil || viewModel.selectedStatus != nil {
                        Button(action: viewModel.clearFilters) {
                            Label("Clear", systemImage: "xmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            #if os(iOS)
            if isCompact {
                Divider()
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            title: viewModel.selectedBrand ?? "Brand",
                            icon: "building.2",
                            isActive: viewModel.selectedBrand != nil,
                            options: ["All"] + viewModel.availableBrands,
                            selection: Binding(
                                get: { viewModel.selectedBrand ?? "All" },
                                set: { viewModel.selectedBrand = $0 == "All" ? nil : $0 }
                            )
                        )
                        
                        FilterChip(
                            title: viewModel.selectedStatus ?? "Status",
                            icon: "checkmark.circle",
                            isActive: viewModel.selectedStatus != nil,
                            options: ["All"] + viewModel.availableStatuses,
                            selection: Binding(
                                get: { viewModel.selectedStatus ?? "All" },
                                set: { viewModel.selectedStatus = $0 == "All" ? nil : $0 }
                            )
                        )
                        
                        Menu {
                            Picker("Sort", selection: $viewModel.sortOption) {
                                ForEach(InventoryFinalViewModel.SortOption.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text("Sort")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(viewModel.sortOption != .brandAZ ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                viewModel.sortOption != .brandAZ ?
                                AnyShapeStyle(Color.accentColor) :
                                AnyShapeStyle(.thinMaterial),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 12)
                
                if viewModel.selectedBrand != nil || viewModel.selectedStatus != nil {
                    Divider()
                    
                    HStack {
                        Button(action: viewModel.clearFilters) {
                            Label("Clear Filters", systemImage: "xmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.red)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            #endif
        }
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Devices Found",
            systemImage: "magnifyingglass",
            description: Text("Try adjusting your filters")
        )
        .padding(.top, 100)
    }
    
    // MARK: - Inventory Grid
    private var inventoryGrid: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(viewModel.sortedBrands, id: \.self) { brand in
                Section {
                    LazyVGrid(
                        columns: {
                            #if os(macOS)
                            [GridItem(.adaptive(minimum: 340), spacing: 16)]
                            #else
                            [GridItem(.adaptive(minimum: isCompact ? 300 : 340), spacing: 16)]
                            #endif
                        }(),
                        spacing: isCompact ? 12 : 16
                    ) {
                        if let models = viewModel.groupedModels[brand] {
                            ForEach(models) { model in
                                ModelCard(model: model) {
                                    viewModel.selectedModel = model
                                }
                            }
                        }
                    }
                    #if os(iOS)
                    .padding(.horizontal, isCompact ? 16 : 20)
                    .padding(.vertical, isCompact ? 16 : 20)
                    #else
                    .padding(20)
                    #endif
                    .drawingGroup()
                } header: {
                    BrandHeader(
                        brand: brand,
                        count: viewModel.groupedModels[brand]?.reduce(0) { $0 + $1.totalQuantity } ?? 0
                    )
                }
            }
        }
    }
    
    // Filtered capacity color groups based on search
    private var filteredCapacityColorGroups: [String: [CapacityColorGroup]] {
        guard !modelDetailSearchText.isEmpty else {
            return viewModel.capacityColorGroups
        }
        
        var filtered: [String: [CapacityColorGroup]] = [:]
        for (capacity, groups) in viewModel.capacityColorGroups {
            let matchingGroups = groups.filter { group in
                capacity.localizedCaseInsensitiveContains(modelDetailSearchText) ||
                group.color.localizedCaseInsensitiveContains(modelDetailSearchText)
            }
            if !matchingGroups.isEmpty {
                filtered[capacity] = matchingGroups
            }
        }
        return filtered
    }
    
    // MARK: - Model Detail Content
    private var modelDetailContent: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // Back button and title (macOS only)
            HStack {
                Button(action: viewModel.goBackToModels) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back to Models")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Center: Brand, Model, and Device Count
                if let model = viewModel.selectedModel {
                    VStack(spacing: 4) {
                        Text("\(model.brand) \(model.model)")
                            .font(.title2.bold())
                        Text("\(model.totalQuantity) devices")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            
            Divider()
            #else
            // iPhone/iPad: Title header
            if let model = viewModel.selectedModel {
                VStack(spacing: 8) {
                    Text("\(model.brand) \(model.model)")
                        .font(.title2.bold())
                    Text("\(model.totalQuantity) devices")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                
                Divider()
            }
            #endif
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by capacity or color...", text: $modelDetailSearchText)
                    .textFieldStyle(.plain)
                if !modelDetailSearchText.isEmpty {
                    Button(action: { modelDetailSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            ScrollView {
                if filteredCapacityColorGroups.isEmpty {
                    ContentUnavailableView(
                        "No Devices Found",
                        systemImage: "magnifyingglass",
                        description: Text(modelDetailSearchText.isEmpty ? "No devices found for this model" : "No devices match your search")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    capacityColorGrid
                }
            }
            #if os(macOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(backgroundGray)
        }
        .navigationTitle(viewModel.selectedModel?.model ?? "Model Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    // MARK: - Capacity Color Grid
    private var capacityColorGrid: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(filteredCapacityColorGroups.keys.sorted(), id: \.self) { capacity in
                Section {
                    LazyVGrid(
                        columns: {
                            #if os(macOS)
                            [GridItem(.adaptive(minimum: 320), spacing: 16)]
                            #else
                            [GridItem(.adaptive(minimum: isCompact ? 300 : 320), spacing: 16)]
                            #endif
                        }(),
                        spacing: isCompact ? 12 : 16
                    ) {
                        if let colorGroups = filteredCapacityColorGroups[capacity] {
                            ForEach(colorGroups) { group in
                                CapacityColorCard(group: group, viewModel: viewModel)
                            }
                        }
                    }
                    #if os(iOS)
                    .padding(.horizontal, isCompact ? 16 : 20)
                    .padding(.vertical, isCompact ? 16 : 20)
                    #else
                    .padding(20)
                    #endif
                    .drawingGroup()
                } header: {
                    CapacityHeader(
                        capacity: capacity,
                        count: filteredCapacityColorGroups[capacity]?.reduce(0) { $0 + $1.quantity } ?? 0
                    )
                }
            }
        }
    }
    
    // MARK: - Helpers
    private var backgroundGray: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
}

// MARK: - Supporting Views

struct ModelCard: View {
    let model: GroupedModel
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.model)
                            .font(.title2.bold())
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text(model.brand)
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer(minLength: 12)
                    
                    VStack(spacing: 8) {
                        Text("\(model.totalQuantity)")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)
                        
                        Text("TOTAL")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
                
                Divider()
                
                HStack(spacing: 0) {
                    // Active Section
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("ACTIVE")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.green)
                                .textCase(.uppercase)
                                .tracking(0.5)
                        }
                        Text("\(model.activeCount)")
                            .font(.title.bold())
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Divider
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 1)
                        .padding(.vertical, 8)
                    
                    // Inactive Section
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("INACTIVE")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.red)
                                .textCase(.uppercase)
                                .tracking(0.5)
                        }
                        Text("\(model.inactiveCount)")
                            .font(.title.bold())
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
            }
            #if os(macOS)
            .padding(24)
            #else
            .padding(20)
            #endif
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct CapacityColorCard: View {
    let group: CapacityColorGroup
    @ObservedObject var viewModel: InventoryFinalViewModel
    @State private var showingIMEIDialog = false
    
    // Computed property that gets current phones from viewModel
    private var currentPhones: [InventoryPhone] {
        guard let firstPhone = group.phones.first else { return [] }
        
        return viewModel.allPhones.filter { phone in
            // Filter by group properties
            guard phone.brand == firstPhone.brand &&
                  phone.model == firstPhone.model &&
                  phone.capacity == group.capacity &&
                  phone.capacityUnit == group.capacityUnit &&
                  phone.color == group.color else {
                return false
            }
            
            // Filter by selected location if one is selected
            if let location = viewModel.selectedLocation {
                guard phone.storageLocation == location.name else {
                    return false
                }
            }
            
            // Filter by selected status if one is selected
            if let status = viewModel.selectedStatus {
                guard phone.status == status else {
                    return false
                }
            }
            
            return true
        }
    }
    
    private var activeCount: Int {
        currentPhones.filter { $0.status.lowercased() == "active" }.count
    }
    
    private var inactiveCount: Int {
        currentPhones.filter { $0.status.lowercased() != "active" }.count
    }
    
    var body: some View {
        Button(action: {
            showingIMEIDialog = true
        }) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.color)
                            .font(.title2.bold())
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("\(group.capacity) \(group.capacityUnit)")
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer(minLength: 12)
                    
                    VStack(spacing: 8) {
                        Text("\(currentPhones.count)")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)
                        
                        Text("TOTAL")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
                
                Divider()
                
                HStack(spacing: 0) {
                    // Active Section
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("ACTIVE")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.green)
                                .textCase(.uppercase)
                                .tracking(0.5)
                        }
                        Text("\(activeCount)")
                            .font(.title.bold())
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Divider
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 1)
                        .padding(.vertical, 8)
                    
                    // Inactive Section
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("INACTIVE")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.red)
                                .textCase(.uppercase)
                                .tracking(0.5)
                        }
                        Text("\(inactiveCount)")
                            .font(.title.bold())
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
            }
            #if os(macOS)
            .padding(24)
            #else
            .padding(20)
            #endif
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingIMEIDialog) {
            if let firstPhone = group.phones.first {
                IMEIDetailDialog(
                    capacity: group.capacity,
                    capacityUnit: group.capacityUnit,
                    color: group.color,
                    brand: firstPhone.brand,
                    model: firstPhone.model,
                    viewModel: viewModel
                )
            }
        }
    }
}

struct IMEIDetailDialog: View {
    let capacity: String
    let capacityUnit: String
    let color: String
    let brand: String
    let model: String
    @ObservedObject var viewModel: InventoryFinalViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDeleteAlert = false
    @State private var phoneToDelete: InventoryPhone?
    @State private var imeiSearchText = ""
    
    // Computed property that always gets fresh data from viewModel
    private var currentPhones: [InventoryPhone] {
        var phones = viewModel.allPhones.filter { phone in
            // Filter by group properties
            guard phone.brand == brand &&
                  phone.model == model &&
                  phone.capacity == capacity &&
                  phone.capacityUnit == capacityUnit &&
                  phone.color == color else {
                return false
            }
            
            // Filter by selected location if one is selected
            if let location = viewModel.selectedLocation {
                guard phone.storageLocation == location.name else {
                    return false
                }
            }
            
            // Filter by selected status if one is selected
            if let status = viewModel.selectedStatus {
                guard phone.status == status else {
                    return false
                }
            }
            
            return true
        }
        
        // Filter by IMEI search if search text is not empty
        if !imeiSearchText.isEmpty {
            phones = phones.filter { phone in
                phone.imei.localizedCaseInsensitiveContains(imeiSearchText)
            }
        }
        
        return phones
    }
    
    var body: some View {
        Group {
            if currentPhones.isEmpty {
                // Auto-dismiss when all phones are deleted
                Color.clear
                    .onAppear {
                        dismiss()
                    }
            } else if shouldShowiPhoneDialog {
                iPhoneDialogView
            } else {
                DesktopDialogView
            }
        }
        .alert("Delete Phone", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {
                phoneToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let phone = phoneToDelete {
                    phoneToDelete = nil
                    Task {
                        await viewModel.deletePhone(phone)
                    }
                }
            }
        } message: {
            if let phone = phoneToDelete {
                Text("Are you sure you want to delete the phone with IMEI: \(phone.imei)? This action cannot be undone.")
            }
        }
    }
    
    private var shouldShowiPhoneDialog: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
    
    var iPhoneDialogView: some View {
        NavigationView {
            VStack(spacing: 0) {
                iPhoneDialogHeader
                Divider()
                iPhoneDialogSearchBar
                Divider()
                iPhoneDialogDeviceList
            }
            .navigationTitle("Device Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #endif
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
    
    private var iPhoneDialogHeader: some View {
        VStack(spacing: 10) {
            // Brand and Model
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(brand)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(model)
                        .font(.title3.bold())
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            // Color, Capacity, and Count
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(color)
                        .font(.headline.bold())
                        .lineLimit(1)
                    
                    Text("\(capacity) \(capacityUnit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(currentPhones.count)")
                        .font(.title2.bold())
                    
                    Text("Devices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Active: \(activePhoneCount)")
                        .font(.caption.weight(.medium))
                }
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Inactive: \(inactivePhoneCount)")
                        .font(.caption.weight(.medium))
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }
    
    private var iPhoneDialogSearchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search IMEI...", text: $imeiSearchText)
                .textFieldStyle(.plain)
            if !imeiSearchText.isEmpty {
                Button(action: { imeiSearchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    private var iPhoneDialogDeviceList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(currentPhones, id: \.id) { phone in
                    iPhoneDeviceCard(phone: phone)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }
    
    private func iPhoneDeviceCard(phone: InventoryPhone) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // IMEI and Status Row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IMEI")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(phone.imei)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(phone.status.lowercased() == "active" ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(phone.status)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(phone.status.lowercased() == "active" ? .green : .red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    (phone.status.lowercased() == "active" ? Color.green : Color.red)
                        .opacity(0.15),
                    in: Capsule()
                )
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Device Details Grid
            VStack(alignment: .leading, spacing: 8) {
                iPhoneDeviceDetailRow(label: "Brand", value: phone.brand)
                iPhoneDeviceDetailRow(label: "Model", value: phone.model)
                iPhoneDeviceDetailRow(label: "Capacity", value: "\(phone.capacity) \(phone.capacityUnit)")
                iPhoneDeviceDetailRow(label: "Color", value: phone.color)
                iPhoneDeviceDetailRow(label: "Carrier", value: phone.carrier)
                iPhoneDeviceDetailRow(label: "Location", value: phone.storageLocation)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Actions
            HStack(spacing: 12) {
                Button(action: {
                    // TODO: Implement edit functionality
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                        Text("Edit")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                
                Button(action: {
                    phoneToDelete = phone
                    showDeleteAlert = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.subheadline)
                        Text("Delete")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var activePhoneCount: Int {
        currentPhones.filter { $0.status.lowercased() == "active" }.count
    }
    
    private var inactivePhoneCount: Int {
        currentPhones.filter { $0.status.lowercased() != "active" }.count
    }
    
    // MARK: - Device Detail Row Helper (iPhone)
    @ViewBuilder
    private func iPhoneDeviceDetailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
    
    var DesktopDialogView: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Device Details")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                Divider()
                
                // Content
                VStack(spacing: 0) {
                    // Summary Header
                    VStack(spacing: 12) {
                        // Brand and Model
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(brand)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text(model)
                                    .font(.title.bold())
                            }
                            
                            Spacer()
                        }
                        
                        // Color, Capacity, and Count
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(color)
                                    .font(.title2.bold())
                                
                                Text("\(capacity) \(capacityUnit)")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(currentPhones.count)")
                                    .font(.largeTitle.bold())
                                
                                Text("Devices")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack(spacing: 20) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 10, height: 10)
                                Text("Active: \(currentPhones.filter { $0.status.lowercased() == "active" }.count)")
                                    .font(.body.weight(.medium))
                            }
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 10, height: 10)
                                Text("Inactive: \(currentPhones.filter { $0.status.lowercased() != "active" }.count)")
                                    .font(.body.weight(.medium))
                            }
                            
                            Spacer()
                        }
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    
                    Divider()
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search IMEI...", text: $imeiSearchText)
                            .textFieldStyle(.plain)
                        if !imeiSearchText.isEmpty {
                            Button(action: { imeiSearchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    
                    Divider()
                    
                    // Table Content
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Table Header
                            HStack {
                                Text("IMEI")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Text("Brand")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                
                                Text("Model")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 110, alignment: .leading)
                                
                                Text("Capacity")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                
                                Text("Color")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                
                                Text("Status")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                
                                Text("Carrier")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                
                                Text("Location")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 110, alignment: .leading)
                                
                                Text("Actions")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .center)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.quaternary.opacity(0.5))
                            
                            // Table Rows
                            ForEach(currentPhones, id: \.id) { phone in
                                HStack {
                                    Text(phone.imei)
                                        .font(.body.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Text(phone.brand)
                                        .font(.body)
                                        .frame(width: 90, alignment: .leading)
                                    
                                    Text(phone.model)
                                        .font(.body)
                                        .frame(width: 110, alignment: .leading)
                                    
                                    Text("\(phone.capacity) \(phone.capacityUnit)")
                                        .font(.body)
                                        .frame(width: 90, alignment: .leading)
                                    
                                    Text(phone.color)
                                        .font(.body)
                                        .frame(width: 90, alignment: .leading)
                                    
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(phone.status.lowercased() == "active" ? .green : .red)
                                            .frame(width: 8, height: 8)
                                        Text(phone.status)
                                            .font(.body.weight(.medium))
                                    }
                                    .frame(width: 80, alignment: .leading)
                                    
                                    Text(phone.carrier)
                                        .font(.body)
                                        .frame(width: 90, alignment: .leading)
                                    
                                    Text(phone.storageLocation)
                                        .font(.body)
                                        .frame(width: 110, alignment: .leading)
                                    
                                    // Action buttons
                                    HStack(spacing: 8) {
                                        Button(action: {
                                            // TODO: Implement edit functionality
                                        }) {
                                            Image(systemName: "pencil")
                                                .font(.body)
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        Button(action: {
                                            phoneToDelete = phone
                                            showDeleteAlert = true
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.body)
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    .frame(width: 80, alignment: .center)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(.background)
                                .overlay(
                                    Rectangle()
                                        .fill(.separator.opacity(0.3))
                                        .frame(height: 0.5),
                                    alignment: .bottom
                                )
                            }
                        }
                    }
                    .background(.background)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 1300, height: 700) // Larger dialog size for better visibility
            .background(backgroundColor)
            .cornerRadius(12)
            .shadow(radius: 20)
        }
    }
    
    private var backgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(.systemBackground)
        #endif
    }
}

struct CapacityHeader: View {
    let capacity: String
    let count: Int
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    var body: some View {
        HStack(spacing: isCompact ? 10 : 12) {
            Circle()
                .fill(.orange.gradient)
                .frame(width: 10, height: 10)
            
            Text(capacity)
                .font(isCompact ? .title3.bold() : .title2.bold())
                .foregroundStyle(.primary)
            
            Text("\(count)")
                .font(isCompact ? .title3.weight(.bold) : .title2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, isCompact ? 10 : 12)
                .padding(.vertical, isCompact ? 5 : 6)
                .background(.orange.gradient, in: Capsule())
            
            Spacer()
        }
        #if os(iOS)
        .padding(.horizontal, isCompact ? 20 : 28)
        .padding(.vertical, isCompact ? 16 : 18)
        #else
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        #endif
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

struct LocationCard: View {
    let location: StorageLocation
    let deviceCount: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "building.2.fill")
                        .font(.title2)
                        .foregroundStyle(.blue.gradient)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(location.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Label("\(deviceCount) devices", systemImage: "iphone")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                                )
                                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    struct LocationRow: View {
                        let location: StorageLocation
                        let deviceCount: Int
                        let isSelected: Bool
                        
                        var body: some View {
                            HStack(spacing: 14) {
                                Image(systemName: "building.2.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue.gradient)
                                    .frame(width: 36)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(location.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    
                                    Label("\(deviceCount) devices", systemImage: "iphone")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                    }

                    struct StatCard: View {
                        let title: String
                        let value: String
                        let icon: String
                        let color: Color
                        @Environment(\.horizontalSizeClass) var horizontalSizeClass
                        
                        private var isCompact: Bool {
                            horizontalSizeClass == .compact
                        }
                        
                        var body: some View {
                            VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
                                HStack {
                                    Image(systemName: icon)
                                        #if os(iOS)
                                        .font(isCompact ? .caption : .title3)
                                        #else
                                        .font(.title3)
                                        #endif
                                        .foregroundStyle(color.gradient)
                                    
                                    Spacer()
                                }
                                
                                Text(value)
                                    #if os(iOS)
                                    .font(isCompact ? .title3.bold() : .title.bold())
                                    #else
                                    .font(.title.bold())
                                    #endif
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                
                                Text(title)
                                    #if os(iOS)
                                    .font(isCompact ? .caption2 : .caption)
                                    #else
                                    .font(.caption)
                                    #endif
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                    .lineLimit(1)
                            }
                            #if os(iOS)
                            .frame(
                                height: isCompact ? 75 : nil,
                                alignment: .leading
                            )
                            .padding(isCompact ? 8 : 16)
                            #else
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            #endif
                            .background(.background, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                        }
                    }

                    struct SearchField: View {
                        @Binding var text: String
                        
                        var body: some View {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                    .font(.body.weight(.medium))
                                
                                TextField("Search by brand, model, IMEI...", text: $text)
                                    .textFieldStyle(.plain)
                                
                                if !text.isEmpty {
                                    Button(action: { text = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    struct FilterMenu: View {
                        let title: String
                        let icon: String
                        let options: [String]
                        @Binding var selection: String
                        
                        var body: some View {
                            Menu {
                                Picker(title, selection: $selection) {
                                    ForEach(options, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: icon)
                                        .font(.subheadline)
                                    Text(title)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    #if os(iOS)
                    struct FilterChip: View {
                        let title: String
                        let icon: String
                        let isActive: Bool
                        let options: [String]
                        @Binding var selection: String
                        
                        var body: some View {
                            Menu {
                                Picker(title, selection: $selection) {
                                    ForEach(options, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: icon)
                                        .font(.caption)
                                    Text(title)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.bold))
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(isActive ? .white : .primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(
                                    isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.thinMaterial),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                        }
                    }
                    #endif

                    struct BrandHeader: View {
                        let brand: String
                        let count: Int
                        @Environment(\.horizontalSizeClass) var horizontalSizeClass
                        
                        private var isCompact: Bool {
                            horizontalSizeClass == .compact
                        }
                        
                        var body: some View {
                            HStack(spacing: isCompact ? 10 : 12) {
                                Circle()
                                    .fill(.blue.gradient)
                                    .frame(width: 10, height: 10)
                                
                                Text(brand)
                                    #if os(macOS)
                                    .font(.title.bold())
                                    #else
                                    .font(isCompact ? .title3.bold() : .title2.bold())
                                    #endif
                                    .foregroundStyle(.primary)
                                
                                Text("\(count)")
                                    .font(isCompact ? .title3.weight(.bold) : .title2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, isCompact ? 10 : 12)
                                    .padding(.vertical, isCompact ? 5 : 6)
                                    .background(.blue.gradient, in: Capsule())
                                
                                Spacer()
                            }
                            #if os(iOS)
                            .padding(.horizontal, isCompact ? 20 : 28)
                            .padding(.vertical, isCompact ? 16 : 18)
                            #else
                            .padding(.horizontal, 32)
                            .padding(.vertical, 20)
                            #endif
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.thickMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(.blue.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        }
                    }

                    struct PhoneCard: View {
                        let phone: GroupedPhone
                        @State private var isExpanded = false
                        
                        var body: some View {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(phone.model)
                                            .font(.headline)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                        
                                        HStack(spacing: 10) {
                                            Label {
                                                Text("\(phone.capacity) \(phone.capacityUnit)")
                                            } icon: {
                                                Image(systemName: "internaldrive")
                                            }
                                            
                                            Circle()
                                                .fill(.secondary)
                                                .frame(width: 3, height: 3)
                                            
                                            Text(phone.color)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer(minLength: 8)
                                    
                                    VStack(spacing: 6) {
                                        Text("\(phone.quantity)")
                                            .font(.title2.bold())
                                            .foregroundStyle(.primary)
                                        
                                        Text("in stock")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                }
                                
                                Divider()
                                
                                HStack(spacing: 16) {
                                    if !phone.carrier.isEmpty {
                                        Label(phone.carrier, systemImage: "antenna.radiowaves.left.and.right")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: "dollarsign.circle.fill")
                                            .font(.caption)
                                        Text(phone.unitCost, format: .currency(code: "USD"))
                                            .font(.subheadline.weight(.bold))
                                    }
                                    .foregroundStyle(.green)
                                }
                                
                                StatusBadge(status: phone.status)
                                
                                if phone.quantity > 0 {
                                    DisclosureGroup(isExpanded: $isExpanded) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(phone.imeis.prefix(5), id: \.self) { imei in
                                                HStack(spacing: 8) {
                                                    Image(systemName: "number")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .frame(width: 16)
                                                    
                                                    Text(imei)
                                                        .font(.caption.monospaced())
                                                        .foregroundStyle(.primary)
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                                            }
                                            
                                            if phone.imeis.count > 5 {
                                                Text("+\(phone.imeis.count - 5) more")
                                                    .font(.caption2.weight(.medium))
                                                    .foregroundStyle(.secondary)
                                                    .padding(.top, 2)
                                            }
                                        }
                                        .padding(.top, 8)
                                    } label: {
                                        Label("IMEI Numbers (\(phone.imeis.count))", systemImage: "barcode")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .tint(.primary)
                                }
                            }
                            #if os(macOS)
                            .padding(18)
                            #else
                            .padding(16)
                            #endif
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                        }
                    }

                    struct StatusBadge: View {
                        let status: String
                        
                        private var statusColor: Color {
                            status.lowercased() == "active" ? .green : .red
                        }
                        
                        var body: some View {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 6, height: 6)
                                
                                Text(status)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(statusColor.opacity(0.15), in: Capsule())
                        }
                    }

                    #Preview {
                        InventoryFinalView()
                    }
