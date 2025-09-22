//
//  EntityDetailView.swift
//  Aromex
//
//  Created by User on 9/17/25.
//

import SwiftUI
import FirebaseFirestore

struct EntityDetailView: View {
    let entity: EntityProfile
    let entityType: EntityType
    
    @State private var showingEditDialog = false
    @State private var editingEntity: EntityProfile?
    @State private var currentEntity: EntityProfile
    @State private var listener: ListenerRegistration?
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    init(entity: EntityProfile, entityType: EntityType) {
        self.entity = entity
        self.entityType = entityType
        self._currentEntity = State(initialValue: entity)
    }
    
    private var isCompact: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                professionalHeaderSection
                
                // Placeholder for future content
                VStack {
                    Text("Main Content Area")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Additional features will be added here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                )
                
                Spacer(minLength: 100)
            }
            .padding()
        }
        .sheet(item: $editingEntity) { _ in
            EditEntityDialog(
                isPresented: .constant(true),
                entityType: entityType,
                editingEntity: currentEntity,
                onSave: { updatedEntity in
                    // Handle the save operation here
                    print("Updated entity: \(updatedEntity)")
                    editingEntity = nil
                },
                onDismiss: {
                    editingEntity = nil
                }
            )
        }
        .onAppear {
            setupListener()
        }
        .onDisappear {
            removeListener()
        }
    }
    
    @ViewBuilder
    var professionalHeaderSection: some View {
        if isCompact {
            iPhoneHeaderLayout
        } else {
            iPadMacHeaderLayout
        }
    }
    
    var iPadMacHeaderLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left Column: Entity Details
            VStack(alignment: .leading, spacing: 16) {
                // Name and Type
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentEntity.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(entityType.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(entityType.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(entityType.color.opacity(0.1))
                                .stroke(entityType.color.opacity(0.3), lineWidth: 1)
                        )
                }
                
                // Contact Information
                if !currentEntity.phone.isEmpty || !currentEntity.email.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !currentEntity.phone.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.blue)
                                    .frame(width: 16, alignment: .leading)
                                Text(currentEntity.phone)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        
                        if !currentEntity.email.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.orange)
                                    .frame(width: 16, alignment: .leading)
                                Text(currentEntity.email)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    }
                }
                
                // Notes
                if !currentEntity.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "note.text")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.purple)
                                .frame(width: 16, alignment: .leading)
                            Text(currentEntity.notes)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(3)
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right Column: Balance and Edit Button
            VStack(alignment: .trailing, spacing: 16) {
                // Prominent Balance Card
                VStack(spacing: 6) {
                    Text(formatCurrency(currentEntity.balance))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(getBalanceColor(currentEntity.balance))
                        .lineLimit(1)
                    
                    Text(getBalanceDescription(currentEntity.balance))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(getBalanceColor(currentEntity.balance))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minWidth: 180)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.background)
                        .shadow(color: getBalanceColor(currentEntity.balance).opacity(0.1), radius: 6, x: 0, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(getBalanceColor(currentEntity.balance).opacity(0.2), lineWidth: 1.5)
                )
                
                // Edit Button
                Button(action: {
                    editingEntity = entity
                    showingEditDialog = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(entityType.color)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    var iPhoneHeaderLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left Column: Customer Details
            VStack(alignment: .leading, spacing: 12) {
                // Name and Type
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentEntity.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(entityType.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(entityType.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(entityType.color.opacity(0.1))
                                .stroke(entityType.color.opacity(0.3), lineWidth: 1)
                        )
                }
                
                // Contact Information
                if !currentEntity.phone.isEmpty || !currentEntity.email.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !currentEntity.phone.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                                    .frame(width: 14, alignment: .leading)
                                Text(currentEntity.phone)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        
                        if !currentEntity.email.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.orange)
                                    .frame(width: 14, alignment: .leading)
                                Text(currentEntity.email)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    }
                }
                
                // Notes
                if !currentEntity.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "note.text")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.purple)
                                .frame(width: 14, alignment: .leading)
                            Text(currentEntity.notes)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(3)
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right Column: Balance Card and Edit Button
            VStack(alignment: .trailing, spacing: 12) {
                // Bigger Balance Card
                VStack(spacing: 6) {
                    Text(formatCurrency(currentEntity.balance))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(getBalanceColor(currentEntity.balance))
                        .lineLimit(1)
                    
                    Text(getBalanceDescription(currentEntity.balance))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(getBalanceColor(currentEntity.balance))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.background)
                        .shadow(color: getBalanceColor(currentEntity.balance).opacity(0.1), radius: 5, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(getBalanceColor(currentEntity.balance).opacity(0.2), lineWidth: 1)
                )
                
                // Edit Button
                Button(action: {
                    editingEntity = entity
                    showingEditDialog = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(entityType.color)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: abs(amount))) ?? "$0.00"
    }
    
    private func getBalanceColor(_ balance: Double) -> Color {
        if balance > 0 {
            return .green
        } else if balance < 0 {
            return .red
        } else {
            return .secondary
        }
    }
    
    private func getBalanceDescription(_ balance: Double) -> String {
        if balance > 0 {
            return "Amount to Receive"
        } else if balance < 0 {
            return "Amount to Give"
        } else {
            return "No Balance"
        }
    }
    
    private func setupListener() {
        let db = Firestore.firestore()
        
        listener = db.collection(entityType.collectionName)
            .document(entity.id)
            .addSnapshotListener { documentSnapshot, error in
                
                if let error = error {
                    print("Error listening to entity changes: \(error)")
                    return
                }
                
                guard let document = documentSnapshot, document.exists else {
                    print("Entity document does not exist")
                    return
                }
                
                let data = document.data() ?? [:]
                
                // Update current entity with real-time data
                let updatedEntity = EntityProfile(
                    id: document.documentID,
                    name: data["name"] as? String ?? "",
                    phone: data["phone"] as? String ?? "",
                    email: data["email"] as? String ?? "",
                    balance: data["balance"] as? Double ?? 0.0,
                    address: data["address"] as? String ?? "",
                    notes: data["notes"] as? String ?? ""
                )
                
                currentEntity = updatedEntity
            }
    }
    
    private func removeListener() {
        listener?.remove()
        listener = nil
    }
}

#Preview {
    NavigationView {
        EntityDetailView(
            entity: EntityProfile(
                id: "preview",
                name: "John Doe",
                phone: "+1 234-567-8900",
                email: "john@example.com",
                balance: 1500.0,
                address: "123 Main St",
                notes: "Preview notes"
            ),
            entityType: .customer
        )
    }
}
