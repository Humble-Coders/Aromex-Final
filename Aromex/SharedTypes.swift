import Foundation
import SwiftUI

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
