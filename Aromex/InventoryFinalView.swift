import SwiftUI
import FirebaseFirestore

// MARK: - Data Models
struct InventoryPhone: Identifiable, Hashable {
    let id: String
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

struct StorageLocation: Identifiable {
    let id: String
    let name: String
}

// MARK: - View Model
@MainActor
class InventoryFinalViewModel: ObservableObject {
    @Published var allPhones: [InventoryPhone] = []
    @Published var storageLocations: [StorageLocation] = []
    @Published var selectedLocation: StorageLocation?
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
    
    var groupedPhones: [String: [GroupedPhone]] {
        let phones = filteredAndSortedPhones
        var grouped: [String: [GroupedPhone]] = [:]
        
        let brandGroups = Dictionary(grouping: phones) { $0.brand }
        
        for (brand, brandPhones) in brandGroups {
            let phoneGroups = Dictionary(grouping: brandPhones) { phone in
                "\(phone.model)|\(phone.capacity)|\(phone.capacityUnit)|\(phone.color)|\(phone.carrier)|\(phone.status)|\(phone.storageLocation)"
            }
            
            var brandGroupedPhones: [GroupedPhone] = []
            
            for (_, groupPhones) in phoneGroups {
                if let firstPhone = groupPhones.first {
                    let groupedPhone = GroupedPhone(
                        brand: firstPhone.brand,
                        model: firstPhone.model,
                        capacity: firstPhone.capacity,
                        capacityUnit: firstPhone.capacityUnit,
                        color: firstPhone.color,
                        carrier: firstPhone.carrier,
                        status: firstPhone.status,
                        storageLocation: firstPhone.storageLocation,
                        unitCost: firstPhone.unitCost,
                        phones: groupPhones
                    )
                    brandGroupedPhones.append(groupedPhone)
                }
            }
            
            brandGroupedPhones = sortGroupedPhones(brandGroupedPhones)
            grouped[brand] = brandGroupedPhones
        }
        
        return grouped
    }
    
    var sortedBrands: [String] {
        let brands = Array(groupedPhones.keys)
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
            storageLocations = snapshot.documents.compactMap { doc in
                guard let name = doc.data()["name"] as? String else { return nil }
                return StorageLocation(id: doc.documentID, name: name)
            }.sorted { $0.name < $1.name }
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
                if let name = doc.data()["name"] as? String {
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
        let brandName = brandDoc.data()["brand"] as? String ?? "Unknown"
        
        do {
            let modelsSnapshot = try await brandDoc.reference.collection("Models").getDocuments()
            
            await withTaskGroup(of: [InventoryPhone].self) { group in
                for modelDoc in modelsSnapshot.documents {
                    group.addTask {
                        await self.fetchPhonesForModel(modelDoc: modelDoc, brandName: brandName)
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
    
    private func fetchPhonesForModel(modelDoc: QueryDocumentSnapshot, brandName: String) async -> [InventoryPhone] {
        var phones: [InventoryPhone] = []
        let modelName = modelDoc.data()["model"] as? String ?? "Unknown"
        
        do {
            let phonesSnapshot = try await modelDoc.reference.collection("Phones").getDocuments()
            
            for phoneDoc in phonesSnapshot.documents {
                if let phone = createPhone(from: phoneDoc, brand: brandName, model: modelName) {
                    phones.append(phone)
                }
            }
        } catch {
            print("Error fetching phones for model \(modelName): \(error)")
        }
        
        return phones
    }
    
    private func createPhone(from doc: QueryDocumentSnapshot, brand: String, model: String) -> InventoryPhone? {
        let data = doc.data()
        
        let color = getReferenceName(from: data["color"])
        let carrier = getReferenceName(from: data["carrier"])
        let storageLocation = getReferenceName(from: data["storageLocation"])
        
        return InventoryPhone(
            id: doc.documentID,
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
}

// MARK: - Main View
struct InventoryFinalView: View {
    @StateObject private var viewModel = InventoryFinalViewModel()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    var isCompact: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    var isIPad: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    var isMacOS: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
    
    var body: some View {
        Group {
            if isCompact {
                iPhoneView
            } else if isIPad {
                iPadView
            } else {
                macOSView
            }
        }
        .task {
            await viewModel.fetchAllData()
        }
    }
    
    // MARK: - iPhone View
    private var iPhoneView: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.selectedLocation == nil {
                locationSelectionView
            } else {
                inventoryContentView
            }
        }
        .background(.regularMaterial)
    }
    
    // MARK: - iPad View
    private var iPadView: some View {
        HStack(spacing: 0) {
            if viewModel.selectedLocation == nil {
                locationSelectionView
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: {
                            viewModel.selectedLocation = nil
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Locations")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        
                        Spacer()
                    }
                    .background(.regularMaterial)
                    
                    Divider()
                    
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(viewModel.storageLocations) { location in
                                locationCard(location: location, isCompact: false)
                            }
                        }
                        .padding(16)
                    }
                }
                .frame(width: 300)
                .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                
                Divider()
                
                inventoryContentView
            }
        }
        .overlay(loadingOverlay)
    }
    
    // MARK: - macOS View
    private var macOSView: some View {
        HStack(spacing: 0) {
            if viewModel.selectedLocation == nil {
                locationSelectionView
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: {
                            viewModel.selectedLocation = nil
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Locations")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        
                        Spacer()
                    }
                    .background(.regularMaterial)
                    
                    Divider()
                    
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(viewModel.storageLocations) { location in
                                locationCard(location: location, isCompact: false)
                            }
                        }
                        .padding(20)
                    }
                }
                .frame(width: 320)
                .background(.regularMaterial)
                
                Divider()
                
                inventoryContentView
            }
        }
        .overlay(loadingOverlay)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.25, green: 0.33, blue: 0.54)))
            
            Text("Loading Inventory...")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var loadingOverlay: some View {
        Group {
            if viewModel.isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 24) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            
                            Text("Loading Inventory...")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                        }
                    )
            }
        }
    }
    
    // MARK: - Location Selection View
    private var locationSelectionView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Storage Locations")
                        .font(.system(size: isCompact ? 24 : 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("\(viewModel.storageLocations.count) locations • \(viewModel.allPhones.count) total devices")
                        .font(.system(size: isCompact ? 14 : 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, isCompact ? 20 : 32)
            .padding(.top, isCompact ? 20 : 32)
            .padding(.bottom, isCompact ? 16 : 24)
            
            Divider()
            
            ScrollView {
                LazyVGrid(
                    columns: gridColumns,
                    spacing: isCompact ? 12 : 16
                ) {
                    ForEach(viewModel.storageLocations) { location in
                        locationCard(location: location, isCompact: isCompact)
                    }
                }
                .padding(isCompact ? 16 : 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var gridColumns: [GridItem] {
        if isCompact {
            return [GridItem(.flexible())]
        } else if isIPad {
            return [GridItem(.flexible()), GridItem(.flexible())]
        } else {
            return [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        }
    }
    
    private func locationCard(location: StorageLocation, isCompact: Bool) -> some View {
        let phonesInLocation = viewModel.allPhones.filter { $0.storageLocation == location.name }
        let isSelected = viewModel.selectedLocation?.id == location.id
        
        return Button(action: {
            withAnimation {
                viewModel.selectedLocation = location
            }
        }) {
            VStack(alignment: .leading, spacing: isCompact ? 12 : 16) {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: isCompact ? 24 : 28, weight: .semibold))
                        .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(location.name)
                        .font(.system(size: isCompact ? 18 : 20, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("\(phonesInLocation.count) devices")
                            .font(.system(size: isCompact ? 14 : 15, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(isCompact ? 16 : 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.1) : Color(red: 1, green: 1, blue: 1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color(red: 0.25, green: 0.33, blue: 0.54) : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Inventory Content View
    private var inventoryContentView: some View {
        VStack(spacing: 0) {
            inventoryHeader
            Divider()
            
            if viewModel.filteredAndSortedPhones.isEmpty {
                emptyStateView
            } else {
                inventoryListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var inventoryHeader: some View {
        VStack(spacing: isCompact ? 12 : 16) {
            HStack {
                if isCompact {
                    Button(action: {
                        viewModel.selectedLocation = nil
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Locations")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedLocation?.name ?? "")
                        .font(.system(size: isCompact ? 22 : 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("\(viewModel.filteredAndSortedPhones.count) devices")
                        .font(.system(size: isCompact ? 14 : 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if isCompact {
                iPhoneFilters
            } else {
                desktopFilters
            }
        }
        .padding(.horizontal, isCompact ? 16 : 24)
        .padding(.vertical, isCompact ? 16 : 20)
        .background(.regularMaterial)
    }
    
    private var iPhoneFilters: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search devices...", text: $viewModel.searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.body)
                
                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.1))
            )
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Button("All Brands") {
                            viewModel.selectedBrand = nil
                        }
                        Divider()
                        ForEach(viewModel.availableBrands, id: \.self) { brand in
                            Button(brand) {
                                viewModel.selectedBrand = brand
                            }
                        }
                    } label: {
                        filterChip(
                            title: viewModel.selectedBrand ?? "Brand",
                            icon: "iphone",
                            isActive: viewModel.selectedBrand != nil
                        )
                    }
                    
                    Menu {
                        Button("All Statuses") {
                            viewModel.selectedStatus = nil
                        }
                        Divider()
                        ForEach(viewModel.availableStatuses, id: \.self) { status in
                            Button(status) {
                                viewModel.selectedStatus = status
                            }
                        }
                    } label: {
                        filterChip(
                            title: viewModel.selectedStatus ?? "Status",
                            icon: "checkmark.circle",
                            isActive: viewModel.selectedStatus != nil
                        )
                    }
                    
                    Menu {
                        ForEach(InventoryFinalViewModel.SortOption.allCases, id: \.self) { option in
                            Button(option.rawValue) {
                                viewModel.sortOption = option
                            }
                        }
                    } label: {
                        filterChip(
                            title: "Sort",
                            icon: "arrow.up.arrow.down",
                            isActive: viewModel.sortOption != .brandAZ
                        )
                    }
                    
                    if viewModel.selectedBrand != nil || viewModel.selectedStatus != nil {
                        Button(action: {
                            viewModel.clearFilters()
                        }) {
                            filterChip(
                                title: "Clear",
                                icon: "xmark",
                                isActive: false
                            )
                            .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
    
    private var desktopFilters: some View {
        HStack(spacing: 16) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search devices...", text: $viewModel.searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.body)
                
                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.1))
            )
            
            Menu {
                Button("All Brands") {
                    viewModel.selectedBrand = nil
                }
                Divider()
                ForEach(viewModel.availableBrands, id: \.self) { brand in
                    Button(brand) {
                        viewModel.selectedBrand = brand
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                    Text(viewModel.selectedBrand ?? "All Brands")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(viewModel.selectedBrand != nil ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            
            Spacer()
            
            if viewModel.selectedBrand != nil || viewModel.selectedStatus != nil || viewModel.sortOption != .brandAZ {
                Button(action: {
                    viewModel.clearFilters()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                        Text("Clear Filters")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private func filterChip(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
        }
        .foregroundColor(isActive ? .white : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color(red: 0.25, green: 0.33, blue: 0.54) : Color.secondary.opacity(0.1))
        )
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Devices Found")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Try adjusting your filters or search terms")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            if viewModel.selectedBrand != nil || viewModel.selectedStatus != nil || !viewModel.searchText.isEmpty {
                Button(action: {
                    viewModel.clearFilters()
                }) {
                    Text("Clear All Filters")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(red: 0.25, green: 0.33, blue: 0.54))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Inventory List
    private var inventoryListView: some View {
        ScrollView {
            LazyVStack(spacing: isCompact ? 16 : 20) {
                ForEach(viewModel.sortedBrands, id: \.self) { brand in
                    brandSection(brand: brand)
                }
            }
            .padding(isCompact ? 16 : 24)
        }
    }
    
    private func brandSection(brand: String) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 12 : 16) {
            HStack {
                Text(brand)
                    .font(.system(size: isCompact ? 20 : 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                let brandPhones = viewModel.groupedPhones[brand] ?? []
                let totalQuantity = brandPhones.reduce(0) { $0 + $1.quantity }
                
                Text("\(totalQuantity) devices")
                    .font(.system(size: isCompact ? 14 : 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, isCompact ? 16 : 20)
            .padding(.vertical, isCompact ? 12 : 16)
            .background(
                Rectangle()
                    .fill(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.1))
            )
            
            if let phones = viewModel.groupedPhones[brand] {
                ForEach(phones) { groupedPhone in
                    if isCompact {
                        compactPhoneCard(groupedPhone: groupedPhone)
                    } else {
                        desktopPhoneCard(groupedPhone: groupedPhone)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Compact Phone Card (iPhone)
    private func compactPhoneCard(groupedPhone: GroupedPhone) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(groupedPhone.model)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 6) {
                        Text("\(groupedPhone.capacity) \(groupedPhone.capacityUnit)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(groupedPhone.color)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "cube.box.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("×\(groupedPhone.quantity)")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.25, green: 0.33, blue: 0.54))
                    )
                    
                    statusBadge(text: groupedPhone.status)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                if !groupedPhone.carrier.isEmpty {
                    detailRow(icon: "antenna.radiowaves.left.and.right", text: groupedPhone.carrier)
                }
                
                detailRow(icon: "dollarsign.circle", text: String(format: "$%.2f", groupedPhone.unitCost))
            }
            
            if groupedPhone.quantity > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("IMEI Numbers")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(groupedPhone.imeis.prefix(3), id: \.self) { imei in
                            Text(imei)
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.08))
                                )
                        }
                        
                        if groupedPhone.imeis.count > 3 {
                            Text("+ \(groupedPhone.imeis.count - 3) more")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }
    
    // MARK: - Desktop Phone Card (iPad/macOS)
    private func desktopPhoneCard(groupedPhone: GroupedPhone) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(groupedPhone.model)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        specBadge(icon: "internaldrive", text: "\(groupedPhone.capacity) \(groupedPhone.capacityUnit)")
                        specBadge(icon: "paintpalette", text: groupedPhone.color)
                        if !groupedPhone.carrier.isEmpty {
                            specBadge(icon: "antenna.radiowaves.left.and.right", text: groupedPhone.carrier)
                        }
                    }
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                    
                    Text(String(format: "$%.2f", groupedPhone.unitCost))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                }
            }
            
            Spacer()
            
            if groupedPhone.quantity > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("IMEI Numbers")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(groupedPhone.imeis.prefix(5), id: \.self) { imei in
                                Text(imei)
                                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.secondary.opacity(0.08))
                                    )
                            }
                            
                            if groupedPhone.imeis.count > 5 {
                                Text("+ \(groupedPhone.imeis.count - 5) more")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                .frame(width: 200)
            }
            
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    Image(systemName: "cube.box.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.54))
                    
                    Text("\(groupedPhone.quantity)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("in stock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.25, green: 0.33, blue: 0.54).opacity(0.1))
                )
                
                statusBadge(text: groupedPhone.status)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Helper Views
    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
        }
    }
    
    private func specBadge(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
        )
    }
    
    private func statusBadge(text: String) -> some View {
        let isActive = text.lowercased() == "active"
        let tintColor = isActive ? Color.green : Color.red
        
        return Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(tintColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tintColor.opacity(0.12))
            )
    }
}

#Preview {
    InventoryFinalView()
}
