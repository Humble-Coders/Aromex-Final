import Foundation
import FirebaseFirestore
import SwiftUI

class FirestoreCollectionCopier: ObservableObject {
    static let shared = FirestoreCollectionCopier()
    
    private let db = Firestore.firestore()
    
    @Published var isCopying = false
    @Published var isPasting = false
    @Published var copyProgress = ""
    @Published var pasteProgress = ""
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var alertType: AlertType = .info
    
    enum AlertType {
        case success, error, info
    }
    
    private init() {}
    
    // MARK: - Copy Collections
    func copyCollections() {
        DispatchQueue.main.async {
            self.isCopying = true
            self.copyProgress = "Starting collection copy..."
        }
        
        Task {
            do {
                let collections = ["Customers", "Suppliers", "Middlemen"]
                var allData: [String: Any] = [:]
                var totalDocuments = 0
                
                for collectionName in collections {
                    await MainActor.run {
                        self.copyProgress = "Copying \(collectionName) collection..."
                    }
                    
                    let collectionData = try await copyCollection(collectionName: collectionName)
                    allData[collectionName] = collectionData
                    totalDocuments += collectionData.count
                    
                    await MainActor.run {
                        self.copyProgress = "Completed \(collectionName) collection (\(collectionData.count) documents)"
                    }
                }
                
                // Save to JSON file
                await MainActor.run {
                    self.copyProgress = "Saving to JSON file..."
                }
                try await saveToJSONFile(data: allData)
                
                await MainActor.run {
                    self.isCopying = false
                    self.copyProgress = ""
                    self.showAlert = true
                    self.alertMessage = "Collections copied successfully! Total: \(totalDocuments) documents saved to JSON file in Documents folder."
                    self.alertType = .success
                }
                
            } catch {
                await MainActor.run {
                    self.isCopying = false
                    self.copyProgress = ""
                    self.showAlert = true
                    self.alertMessage = "Error copying collections: \(error.localizedDescription)"
                    self.alertType = .error
                }
            }
        }
    }
    
    private func copyCollection(collectionName: String) async throws -> [[String: Any]] {
        let snapshot = try await db.collection(collectionName).getDocuments()
        var documents: [[String: Any]] = []
        
        for document in snapshot.documents {
            var docData = document.data()
            docData["_documentId"] = document.documentID
            
            // Clean the data to remove Firestore-specific types that can't be serialized
            let cleanedData = cleanFirestoreData(docData)
            documents.append(cleanedData)
        }
        
        print("📋 Copied \(documents.count) documents from \(collectionName)")
        return documents
    }
    
    // Clean Firestore data to make it JSON-serializable
    private func cleanFirestoreData(_ data: [String: Any]) -> [String: Any] {
        var cleanedData: [String: Any] = [:]
        
        for (key, value) in data {
            let cleanedValue = cleanFirestoreValue(value)
            cleanedData[key] = cleanedValue
        }
        
        return cleanedData
    }
    
    // Recursively clean Firestore values
    private func cleanFirestoreValue(_ value: Any) -> Any {
        switch value {
        case let timestamp as Timestamp:
            // Convert Timestamp to ISO8601 string for JSON storage
            let date = timestamp.dateValue()
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: date)
            
        case let geoPoint as GeoPoint:
            // Convert GeoPoint to dictionary
            return [
                "latitude": geoPoint.latitude,
                "longitude": geoPoint.longitude
            ]
            
        case let documentReference as DocumentReference:
            // Convert DocumentReference to path string
            return documentReference.path
            
        case let array as [Any]:
            // Recursively clean arrays
            return array.map { cleanFirestoreValue($0) }
            
        case let dictionary as [String: Any]:
            // Recursively clean dictionaries
            return cleanFirestoreData(dictionary)
            
        case is NSNull:
            // Convert NSNull to nil (will be omitted from JSON)
            return NSNull()
            
        default:
            // For other types (String, Int, Double, Bool), return as is
            return value
        }
    }
    
    private func saveToJSONFile(data: [String: Any]) async throws {
        let jsonData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
        
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "FileError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access Documents directory"])
        }
        
        let fileURL = documentsPath.appendingPathComponent("firestore_collections_backup.json")
        try jsonData.write(to: fileURL)
        
        print("💾 JSON file saved to: \(fileURL.path)")
    }
    
    // MARK: - Paste Collections
    func pasteCollections() {
        DispatchQueue.main.async {
            self.isPasting = true
            self.pasteProgress = "Starting collection paste..."
        }
        
        Task {
            do {
                // Load JSON data
                await MainActor.run {
                    self.pasteProgress = "Loading JSON data..."
                }
                let data = try await loadFromJSONFile()
                
                // Paste collections with original names
                let collections = ["Customers", "Suppliers", "Middlemen"]
                var totalPasted = 0
                
                for collectionName in collections {
                    await MainActor.run {
                        self.pasteProgress = "Pasting \(collectionName) collection..."
                    }
                    
                    if let collectionData = data[collectionName] as? [[String: Any]] {
                        try await pasteCollection(collectionName: collectionName, documents: collectionData)
                        totalPasted += collectionData.count
                        await MainActor.run {
                            self.pasteProgress = "Completed \(collectionName) collection (\(collectionData.count) documents)"
                        }
                    }
                }
                
                await MainActor.run {
                    self.isPasting = false
                    self.pasteProgress = ""
                    self.showAlert = true
                    self.alertMessage = "Collections pasted successfully! Total: \(totalPasted) documents."
                    self.alertType = .success
                }
                
            } catch {
                await MainActor.run {
                    self.isPasting = false
                    self.pasteProgress = ""
                    self.showAlert = true
                    self.alertMessage = "Error pasting collections: \(error.localizedDescription)"
                    self.alertType = .error
                }
            }
        }
    }
    
    private func loadFromJSONFile() async throws -> [String: Any] {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "FileError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access Documents directory"])
        }
        
        let fileURL = documentsPath.appendingPathComponent("firestore_collections_backup.json")
        let jsonData = try Data(contentsOf: fileURL)
        
        guard let data = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(domain: "JSONError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }
        
        print("📂 JSON file loaded from: \(fileURL.path)")
        return data
    }
    
    private func pasteCollection(collectionName: String, documents: [[String: Any]]) async throws {
        let batch = db.batch()
        
        for docData in documents {
            var newDocData = docData
            // Remove the temporary document ID field we added during copy
            newDocData.removeValue(forKey: "_documentId")
            
            // Convert ISO8601 date strings back to Firestore Timestamps
            newDocData = convertDateStringsToTimestamps(newDocData)
            
            // Create new document with new ID
            let docRef = db.collection(collectionName).document()
            
            batch.setData(newDocData, forDocument: docRef)
        }
        
        try await batch.commit()
        print("✅ Pasted \(documents.count) documents to \(collectionName)")
    }
    
    // Convert ISO8601 date strings back to Firestore Timestamps
    private func convertDateStringsToTimestamps(_ data: [String: Any]) -> [String: Any] {
        var convertedData: [String: Any] = [:]
        
        for (key, value) in data {
            let convertedValue = convertDateStringToTimestamp(value)
            convertedData[key] = convertedValue
        }
        
        return convertedData
    }
    
    // Recursively convert date strings back to Timestamps
    private func convertDateStringToTimestamp(_ value: Any) -> Any {
        switch value {
        case let dateString as String:
            // Check if this string looks like an ISO8601 date
            if dateString.contains("T") && dateString.contains("Z") {
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: dateString) {
                    return Timestamp(date: date)
                }
            }
            return value
            
        case let array as [Any]:
            // Recursively convert arrays
            return array.map { convertDateStringToTimestamp($0) }
            
        case let dictionary as [String: Any]:
            // Recursively convert dictionaries
            return convertDateStringsToTimestamps(dictionary)
            
        default:
            // For other types, return as is
            return value
        }
    }
    
    // MARK: - Check if backup exists
    func hasBackupFile() -> Bool {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        
        let fileURL = documentsPath.appendingPathComponent("firestore_collections_backup.json")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    // MARK: - Get backup file info
    func getBackupFileInfo() -> (exists: Bool, size: String, date: String) {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return (false, "", "")
        }
        
        let fileURL = documentsPath.appendingPathComponent("firestore_collections_backup.json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return (false, "", "")
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            let creationDate = attributes[.creationDate] as? Date ?? Date()
            
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            let sizeString = formatter.string(fromByteCount: fileSize)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            let dateString = dateFormatter.string(from: creationDate)
            
            return (true, sizeString, dateString)
        } catch {
            return (false, "", "")
        }
    }
    
    // MARK: - Delete backup file
    func deleteBackupFile() -> Bool {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        
        let fileURL = documentsPath.appendingPathComponent("firestore_collections_backup.json")
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("🗑️ Backup file deleted")
            return true
        } catch {
            print("❌ Error deleting backup file: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Get backup file path for sharing
    func getBackupFilePath() -> URL? {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentsPath.appendingPathComponent("firestore_collections_backup.json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        return fileURL
    }
}
