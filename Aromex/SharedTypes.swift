import Foundation
import SwiftUI
#if os(iOS)
import UIKit
typealias KeyboardType = UIKeyboardType
#else
import AppKit
enum KeyboardType {
    case `default`
    case numberPad
    case decimalPad
}
#endif

enum EntityType: String, CaseIterable {
    case customer = "Customer"
    case supplier = "Supplier"
    case middleman = "Middleman"
    
    var icon: String {
        switch self {
        case .customer: return "person.badge.plus"
        case .supplier: return "building.2"
        case .middleman: return "person.2"
        }
    }
    
    var color: Color {
        switch self {
        case .customer: return Color(red: 0.25, green: 0.33, blue: 0.54)
        case .supplier: return Color(red: 0.20, green: 0.60, blue: 0.40)
        case .middleman: return Color(red: 0.80, green: 0.40, blue: 0.20)
        }
    }
    
    var collectionName: String {
        switch self {
        case .customer: return "Customers"
        case .supplier: return "Suppliers"
        case .middleman: return "Middlemen"
        }
    }
}

struct EntityProfile: Identifiable {
    let id: String
    let name: String
    let phone: String
    let email: String
    let balance: Double
    let address: String
    let notes: String
}

// Represents a phone item added in the Purchase flow
struct PhoneItem: Identifiable, Hashable {
    let id: UUID
    let brand: String
    let model: String
    let capacity: String
    let capacityUnit: String // GB or TB
    let color: String
    let carrier: String
    let status: String
    let storageLocation: String
    let imeis: [String]
    let unitCost: Double
    
    // Initializer for new items (generates new UUID)
    init(brand: String, model: String, capacity: String, capacityUnit: String, color: String, carrier: String, status: String, storageLocation: String, imeis: [String], unitCost: Double) {
        self.id = UUID()
        self.brand = brand
        self.model = model
        self.capacity = capacity
        self.capacityUnit = capacityUnit
        self.color = color
        self.carrier = carrier
        self.status = status
        self.storageLocation = storageLocation
        self.imeis = imeis
        self.unitCost = unitCost
    }
    
    // Initializer for editing existing items (preserves existing UUID)
    init(id: UUID, brand: String, model: String, capacity: String, capacityUnit: String, color: String, carrier: String, status: String, storageLocation: String, imeis: [String], unitCost: Double) {
        self.id = id
        self.brand = brand
        self.model = model
        self.capacity = capacity
        self.capacityUnit = capacityUnit
        self.color = color
        self.carrier = carrier
        self.status = status
        self.storageLocation = storageLocation
        self.imeis = imeis
        self.unitCost = unitCost
    }
}
