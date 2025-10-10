import Foundation
import FirebaseFirestore

enum CustomerType: String, CaseIterable, Codable {
    case customer = "Customer"
    case middleman = "Middleman"
    case supplier = "Supplier"
    
    var displayName: String {
        return self.rawValue
    }
    
    var shortTag: String {
        switch self {
        case .customer: return "C"
        case .middleman: return "M"
        case .supplier: return "S"
        }
    }
}

struct Customer: Identifiable, Codable, Hashable {
    var id: String?
    var name: String
    var phone: String
    var email: String
    var address: String
    var notes: String
    var balance: Double
    var type: CustomerType
    var createdAt: Timestamp?
    var updatedAt: Timestamp?
    
    init(name: String = "", phone: String = "", email: String = "", address: String = "", notes: String = "", balance: Double = 0.0, type: CustomerType = .customer) {
        self.id = UUID().uuidString
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
        self.notes = notes
        self.balance = balance
        self.type = type
        self.createdAt = Timestamp()
        self.updatedAt = Timestamp()
    }
    
    // Custom init for existing Firestore data
    init(id: String, name: String, phone: String = "", email: String = "", address: String = "", notes: String = "", balance: Double = 0.0, type: CustomerType = .customer, createdAt: Timestamp? = nil, updatedAt: Timestamp? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
        self.notes = notes
        self.balance = balance
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Legacy init for backward compatibility (keeping this for now)
    init(id: String, data: [String: Any], type: CustomerType = .customer) {
        self.id = id
        self.name = data["name"] as? String ?? ""
        self.phone = data["phone"] as? String ?? ""
        self.email = data["email"] as? String ?? ""
        self.address = data["address"] as? String ?? ""
        self.notes = data["notes"] as? String ?? ""
        self.balance = data["balance"] as? Double ?? 0.0
        self.type = type
        self.createdAt = data["createdAt"] as? Timestamp
        self.updatedAt = data["updatedAt"] as? Timestamp
    }
    
    // Convert to dictionary for Firestore
    func toDictionary() -> [String: Any] {
        return [
            "name": name,
            "phone": phone,
            "email": email,
            "address": address,
            "notes": notes,
            "balance": balance,
            "createdAt": createdAt ?? Timestamp(),
            "updatedAt": Timestamp()
        ]
    }
    
    var displayNameWithTag: String {
        return "\(name) [\(type.shortTag)]"
    }
}
