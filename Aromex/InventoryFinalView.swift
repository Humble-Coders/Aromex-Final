//
//  InventoryFinalView.swift
//  Aromex
//
//  Created by Ansh Bajaj on 29/08/25.
//

import SwiftUI
import FirebaseFirestore

#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Cross-Platform Color Extension
extension Color {
    static var systemBackground: Color {
        #if os(iOS)
        return Color.systemBackground
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    static var systemGray6: Color {
        #if os(iOS)
        return Color.systemGray6
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    static var systemGray4: Color {
        #if os(iOS)
        return Color(UIColor.systemGray4)
        #else
        return Color(NSColor.separatorColor)
        #endif
    }
}

// MARK: - Data Models
struct PhoneBrand: Identifiable, Codable {
    let id: String
    let brand: String
    let models: [PhoneModel]
}

struct PhoneModel: Identifiable, Codable {
    let id: String
    let model: String
    let phones: [Phone]
}

struct Phone: Identifiable, Codable {
    let id: String
    let imei: String
    let capacity: String
    let capacityUnit: String
    let color: String
    let carrier: String
    let status: String
    let storageLocation: String
    let unitCost: Double
    let createdAt: Date
    
    init(from data: [String: Any]) {
        self.id = data["id"] as? String ?? ""
        self.imei = data["imei"] as? String ?? ""
        self.capacity = data["capacity"] as? String ?? ""
        self.capacityUnit = data["capacityUnit"] as? String ?? ""
        self.color = data["color"] as? String ?? ""
        self.carrier = data["carrier"] as? String ?? ""
        self.status = data["status"] as? String ?? ""
        self.storageLocation = data["storageLocation"] as? String ?? ""
        self.unitCost = data["unitCost"] as? Double ?? 0.0
        self.createdAt = data["createdAt"] as? Date ?? Date()
    }
    
    // Computed property for grouping phones with same specs
    var groupingKey: String {
        return "\(capacity)\(capacityUnit)-\(color)-\(carrier)-\(status)-\(storageLocation)"
    }
}

struct StorageLocation: Identifiable, Codable {
    let id: String
    let name: String
}

struct ClubbedPhone: Identifiable {
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
    let quantity: Int
    let phones: [Phone]
    
    var displayName: String {
        return "\(brand) \(model) \(capacity)\(capacityUnit) \(color) \(carrier)"
    }
}

// MARK: - View Model
class InventoryViewModel: ObservableObject {
    @Published var storageLocations: [StorageLocation] = []
    @Published var allPhones: [Phone] = []
    @Published var phoneBrands: [PhoneBrand] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedLocation: StorageLocation?
    @Published var searchText = ""
    @Published var selectedBrand: String?
    @Published var selectedStatus: String?
    @Published var selectedCapacity: String?
    @Published var selectedColor: String?
    @Published var selectedCarrier: String?
    
    private let db = Firestore.firestore()
    
    init() {
        Task {
            await fetchAllData()
        }
    }
    
    @MainActor
    func fetchAllData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch storage locations
            let locationsSnapshot = try await db.collection("StorageLocations").getDocuments()
            storageLocations = locationsSnapshot.documents.compactMap { doc in
                try? doc.data(as: StorageLocation.self)
            }
            
            // Fetch all phone brands with their models and phones
            let brandsSnapshot = try await db.collection("PhoneBrands").getDocuments()
            var fetchedBrands: [PhoneBrand] = []
            
            for brandDoc in brandsSnapshot.documents {
                guard let brandName = brandDoc.data()["brand"] as? String else { continue }
                
                // Fetch models for this brand
                let modelsSnapshot = try await db.collection("PhoneBrands").document(brandDoc.documentID).collection("Models").getDocuments()
                var fetchedModels: [PhoneModel] = []
                
                for modelDoc in modelsSnapshot.documents {
                    guard let modelName = modelDoc.data()["model"] as? String else { continue }
                    
                    // Fetch phones for this model
                    let phonesSnapshot = try await db.collection("PhoneBrands").document(brandDoc.documentID).collection("Models").document(modelDoc.documentID).collection("Phones").getDocuments()
                    var fetchedPhones: [Phone] = []
                    
                    for phoneDoc in phonesSnapshot.documents {
                        var phoneData = phoneDoc.data()
                        phoneData["id"] = phoneDoc.documentID
                        
                        // Fetch reference data
                        if let brandRef = phoneData["brand"] as? DocumentReference {
                            let brandDoc = try await brandRef.getDocument()
                            phoneData["brand"] = brandDoc.data()?["brand"] as? String ?? ""
                        }
                        
                        if let modelRef = phoneData["model"] as? DocumentReference {
                            let modelDoc = try await modelRef.getDocument()
                            phoneData["model"] = modelDoc.data()?["model"] as? String ?? ""
                        }
                        
                        if let colorRef = phoneData["color"] as? DocumentReference {
                            let colorDoc = try await colorRef.getDocument()
                            phoneData["color"] = colorDoc.data()?["name"] as? String ?? ""
                        }
                        
                        if let carrierRef = phoneData["carrier"] as? DocumentReference {
                            let carrierDoc = try await carrierRef.getDocument()
                            phoneData["carrier"] = carrierDoc.data()?["name"] as? String ?? ""
                        }
                        
                        if let locationRef = phoneData["storageLocation"] as? DocumentReference {
                            let locationDoc = try await locationRef.getDocument()
                            phoneData["storageLocation"] = locationDoc.data()?["name"] as? String ?? ""
                        }
                        
                        let phone = Phone(from: phoneData)
                        fetchedPhones.append(phone)
                    }
                    
                    if !fetchedPhones.isEmpty {
                        fetchedModels.append(PhoneModel(id: modelDoc.documentID, model: modelName, phones: fetchedPhones))
                    }
                }
                
                if !fetchedModels.isEmpty {
                    fetchedBrands.append(PhoneBrand(id: brandDoc.documentID, brand: brandName, models: fetchedModels))
                }
            }
            
            phoneBrands = fetchedBrands
            allPhones = fetchedBrands.flatMap { brand in
                brand.models.flatMap { $0.phones }
            }
            
        } catch {
            errorMessage = "Failed to fetch inventory data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func getClubbedPhones(for location: StorageLocation) -> [ClubbedPhone] {
        let locationPhones = allPhones.filter { $0.storageLocation == location.name }
        
        let grouped = Dictionary(grouping: locationPhones) { phone in
            phone.groupingKey
        }
        
        return grouped.compactMap { (key, phones) in
            guard let firstPhone = phones.first else { return nil }
            
            return ClubbedPhone(
                brand: phoneBrands.first { brand in
                    brand.models.contains { model in
                        model.phones.contains { $0.id == firstPhone.id }
                    }
                }?.brand ?? "",
                model: phoneBrands.first { brand in
                    brand.models.contains { model in
                        model.phones.contains { $0.id == firstPhone.id }
                    }
                }?.models.first { model in
                    model.phones.contains { $0.id == firstPhone.id }
                }?.model ?? "",
                capacity: firstPhone.capacity,
                capacityUnit: firstPhone.capacityUnit,
                color: firstPhone.color,
                carrier: firstPhone.carrier,
                status: firstPhone.status,
                storageLocation: firstPhone.storageLocation,
                unitCost: firstPhone.unitCost,
                quantity: phones.count,
                phones: phones
            )
        }.sorted { $0.displayName < $1.displayName }
    }
    
    var filteredClubbedPhones: [ClubbedPhone] {
        guard let selectedLocation = selectedLocation else { return [] }
        
        var clubbedPhones = getClubbedPhones(for: selectedLocation)
        
        // Apply search filter
        if !searchText.isEmpty {
            clubbedPhones = clubbedPhones.filter { phone in
                phone.displayName.localizedCaseInsensitiveContains(searchText) ||
                phone.status.localizedCaseInsensitiveContains(searchText) ||
                phone.carrier.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply brand filter
        if let selectedBrand = selectedBrand, !selectedBrand.isEmpty {
            clubbedPhones = clubbedPhones.filter { $0.brand == selectedBrand }
        }
        
        // Apply status filter
        if let selectedStatus = selectedStatus, !selectedStatus.isEmpty {
            clubbedPhones = clubbedPhones.filter { $0.status == selectedStatus }
        }
        
        // Apply capacity filter
        if let selectedCapacity = selectedCapacity, !selectedCapacity.isEmpty {
            clubbedPhones = clubbedPhones.filter { $0.capacity == selectedCapacity }
        }
        
        // Apply color filter
        if let selectedColor = selectedColor, !selectedColor.isEmpty {
            clubbedPhones = clubbedPhones.filter { $0.color == selectedColor }
        }
        
        // Apply carrier filter
        if let selectedCarrier = selectedCarrier, !selectedCarrier.isEmpty {
            clubbedPhones = clubbedPhones.filter { $0.carrier == selectedCarrier }
        }
        
        return clubbedPhones
    }
    
    var availableBrands: [String] {
        guard let selectedLocation = selectedLocation else { return [] }
        let locationPhones = getClubbedPhones(for: selectedLocation)
        return Array(Set(locationPhones.map { $0.brand })).sorted()
    }
    
    var availableStatuses: [String] {
        guard let selectedLocation = selectedLocation else { return [] }
        let locationPhones = getClubbedPhones(for: selectedLocation)
        return Array(Set(locationPhones.map { $0.status })).sorted()
    }
    
    var availableCapacities: [String] {
        guard let selectedLocation = selectedLocation else { return [] }
        let locationPhones = getClubbedPhones(for: selectedLocation)
        return Array(Set(locationPhones.map { $0.capacity })).sorted()
    }
    
    var availableColors: [String] {
        guard let selectedLocation = selectedLocation else { return [] }
        let locationPhones = getClubbedPhones(for: selectedLocation)
        return Array(Set(locationPhones.map { $0.color })).sorted()
    }
    
    var availableCarriers: [String] {
        guard let selectedLocation = selectedLocation else { return [] }
        let locationPhones = getClubbedPhones(for: selectedLocation)
        return Array(Set(locationPhones.map { $0.carrier })).sorted()
    }
}

// MARK: - Main View
struct InventoryFinalView: View {
    @StateObject private var viewModel = InventoryViewModel()
    @State private var showingFilters = false
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading Inventory...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task {
                                await viewModel.fetchAllData()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.selectedLocation == nil {
                    LocationSelectionView(viewModel: viewModel)
                } else {
                    InventoryDisplayView(viewModel: viewModel, showingFilters: $showingFilters)
                }
            }
            .navigationTitle("Inventory")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.selectedLocation != nil {
                        Button(action: {
                            viewModel.selectedLocation = nil
                        }) {
                            Image(systemName: "arrow.left")
                        }
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.selectedLocation != nil {
                        Button(action: {
                            viewModel.selectedLocation = nil
                        }) {
                            Image(systemName: "arrow.left")
                        }
                    }
                }
                #endif
            }
        }
    }
}

// MARK: - Location Selection View
struct LocationSelectionView: View {
    @ObservedObject var viewModel: InventoryViewModel
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 200), spacing: 16)
            ], spacing: 16) {
                ForEach(viewModel.storageLocations) { location in
                    LocationCard(location: location) {
                        viewModel.selectedLocation = location
                    }
                }
            }
            .padding()
        }
    }
}

struct LocationCard: View {
    let location: StorageLocation
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: "building.2")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text(location.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                Text("Tap to view inventory")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.systemBackground)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Inventory Display View
struct InventoryDisplayView: View {
    @ObservedObject var viewModel: InventoryViewModel
    @Binding var showingFilters: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.selectedLocation?.name ?? "")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("\(viewModel.filteredClubbedPhones.count) unique devices")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: { showingFilters.toggle() }) {
                        Image(systemName: showingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.title2)
                    }
                }
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search devices...", text: $viewModel.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.systemGray6)
                )
            }
            .padding()
            .background(Color.systemBackground)
            
            // Filters
            if showingFilters {
                FilterView(viewModel: viewModel)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Inventory List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredClubbedPhones) { clubbedPhone in
                        ClubbedPhoneCard(phone: clubbedPhone)
                    }
                }
                .padding()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingFilters)
    }
}

// MARK: - Filter View
struct FilterView: View {
    @ObservedObject var viewModel: InventoryViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    FilterChip(
                        title: "Brand",
                        options: viewModel.availableBrands,
                        selected: $viewModel.selectedBrand
                    )
                    
                    FilterChip(
                        title: "Status",
                        options: viewModel.availableStatuses,
                        selected: $viewModel.selectedStatus
                    )
                    
                    FilterChip(
                        title: "Capacity",
                        options: viewModel.availableCapacities,
                        selected: $viewModel.selectedCapacity
                    )
                    
                    FilterChip(
                        title: "Color",
                        options: viewModel.availableColors,
                        selected: $viewModel.selectedColor
                    )
                    
                    FilterChip(
                        title: "Carrier",
                        options: viewModel.availableCarriers,
                        selected: $viewModel.selectedCarrier
                    )
                }
                .padding(.horizontal)
            }
            
            // Clear Filters Button
            HStack {
                Spacer()
                Button("Clear All Filters") {
                    viewModel.selectedBrand = nil
                    viewModel.selectedStatus = nil
                    viewModel.selectedCapacity = nil
                    viewModel.selectedColor = nil
                    viewModel.selectedCarrier = nil
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color.systemGray6)
    }
}

struct FilterChip: View {
    let title: String
    let options: [String]
    @Binding var selected: String?
    @State private var showingDropdown = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Button(action: { showingDropdown.toggle() }) {
                HStack {
                    Text(selected ?? "All")
                        .font(.subheadline)
                        .foregroundColor(selected != nil ? .primary : .secondary)
                    
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.systemBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.systemGray4, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .popover(isPresented: $showingDropdown) {
            VStack(alignment: .leading, spacing: 8) {
                Button("All") {
                    selected = nil
                    showingDropdown = false
                }
                .foregroundColor(.primary)
                
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        selected = option
                        showingDropdown = false
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding()
            .frame(width: 150)
        }
    }
}

// MARK: - Clubbed Phone Card
struct ClubbedPhoneCard: View {
    let phone: ClubbedPhone
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(phone.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("\(phone.quantity) units")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("₹\(Int(phone.unitCost))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    Text("per unit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 16) {
                InfoBadge(icon: "checkmark.circle", text: phone.status, color: .green)
                InfoBadge(icon: "antenna.radiowaves.left.and.right", text: phone.carrier, color: .blue)
                InfoBadge(icon: "paintbrush", text: phone.color, color: .purple)
                
                Spacer()
                
                Button("Details") {
                    showingDetails = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.systemBackground)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .sheet(isPresented: $showingDetails) {
            PhoneDetailsView(phone: phone)
        }
    }
}

struct InfoBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Phone Details View
struct PhoneDetailsView: View {
    let phone: ClubbedPhone
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(phone.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("\(phone.quantity) units in stock")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Specifications
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Specifications")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 8) {
                            DetailRow(title: "Brand", value: phone.brand)
                            DetailRow(title: "Model", value: phone.model)
                            DetailRow(title: "Capacity", value: "\(phone.capacity) \(phone.capacityUnit)")
                            DetailRow(title: "Color", value: phone.color)
                            DetailRow(title: "Carrier", value: phone.carrier)
                            DetailRow(title: "Status", value: phone.status)
                            DetailRow(title: "Location", value: phone.storageLocation)
                            DetailRow(title: "Unit Cost", value: "₹\(Int(phone.unitCost))")
                        }
                    }
                    
                    // Individual Phones
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Individual Units")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        ForEach(phone.phones) { individualPhone in
                            IndividualPhoneRow(phone: individualPhone)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Device Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.vertical, 2)
    }
}

struct IndividualPhoneRow: View {
    let phone: Phone
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("IMEI: \(phone.imei)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Added: \(phone.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("₹\(Int(phone.unitCost))")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.green)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.systemGray6)
        )
    }
}

#Preview {
    InventoryFinalView()
}
