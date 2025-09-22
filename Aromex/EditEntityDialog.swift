//
//  EditEntityDialog.swift
//  Aromex
//
//  Created by User on 9/17/25.
//

import SwiftUI
import FirebaseFirestore
#if os(iOS)
import UIKit
#endif

struct EditEntityDialog: View {
    @Binding var isPresented: Bool
    let entityType: EntityType
    let editingEntity: EntityProfile
    let onSave: (EntityProfile) -> Void
    let onDismiss: (() -> Void)?
    
    @State private var name: String = ""
    @State private var initialBalance: String = ""
    @State private var phone: String = ""
    @State private var notes: String = ""
    @State private var email: String = ""
    @State private var address: String = ""
    @State private var isUpdating = false
    @State private var showSuccessToast = false
    @State private var selectedEntityType: EntityType = .customer
    @State private var balanceType: BalanceType = .toReceive
    @FocusState private var isFieldFocused: Bool
    @FocusState private var focusedField: FieldType?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    enum BalanceType: String, CaseIterable {
        case toReceive = "To Receive"
        case toGive = "To Give"
        
        var color: Color {
            switch self {
            case .toReceive: return Color.green
            case .toGive: return Color.red
            }
        }
    }
    
    enum FieldType: CaseIterable {
        case name, initialBalance, phone, email, address, notes
    }
    
    var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact && verticalSizeClass == .regular
        #else
        return false
        #endif
    }
    
    var shouldShowiPhoneDialog: Bool {
        #if os(iOS)
        return true // Always show iPhone dialog on iOS (iPhone and iPad)
        #else
        return false // Show desktop dialog on macOS
        #endif
    }
    
    var bufferOverlay: some View {
        Group {
            if isUpdating || showSuccessToast {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            if showSuccessToast {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 40, weight: .semibold))
                                    .foregroundColor(.white)
                                    .background(
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 40, height: 40)
                                    )
                                    .shadow(color: .green.opacity(0.8), radius: 12, x: 0, y: 0)
                            } else {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            
                            Text(showSuccessToast ? "\(selectedEntityType.rawValue) Updated Successfully!" : "Updating \(selectedEntityType.rawValue)...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                        )
                    )
            }
        }
    }
    
    var entityTypeSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entity Type")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            entityTypeButtons
        }
    }
    
    var entityTypeButtons: some View {
        HStack(spacing: 8) {
            ForEach(EntityType.allCases, id: \.self) { entityType in
                entityTypeButton(for: entityType)
            }
        }
    }
    
    func entityTypeButton(for entityType: EntityType) -> some View {
        Button(action: {
            selectedEntityType = entityType
        }) {
            entityTypeButtonContent(for: entityType)
        }
        .buttonStyle(PlainButtonStyle())
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
    
    func entityTypeButtonContent(for entityType: EntityType) -> some View {
        HStack(spacing: 6) {
            Image(systemName: selectedEntityType == entityType ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(selectedEntityType == entityType ? entityType.color : .secondary)
            
            Text(entityType.rawValue)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(selectedEntityType == entityType ? entityType.color : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(entityTypeButtonBackground(for: entityType))
    }
    
    func entityTypeButtonBackground(for entityType: EntityType) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selectedEntityType == entityType ? entityType.color.opacity(0.1) : Color.gray.opacity(0.1))
            .stroke(selectedEntityType == entityType ? entityType.color : Color.clear, lineWidth: 1.5)
    }
    
    var desktopDialogHeader: some View {
        HStack(spacing: 16) {
            desktopDialogIcon
            desktopDialogTitle
            Spacer()
            desktopDialogCloseButton
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }
    
    var desktopDialogIcon: some View {
        ZStack {
            Circle()
                .fill(selectedEntityType.color.opacity(0.15))
                .frame(width: 50, height: 50)
            
            Image(systemName: "pencil")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(selectedEntityType.color)
        }
    }
    
    var desktopDialogTitle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit Entity")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            
            desktopEntityTypeSelection
        }
    }
    
    var desktopEntityTypeSelection: some View {
        HStack(spacing: 8) {
            Text("Type:")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            ForEach(EntityType.allCases, id: \.self) { entityType in
                desktopEntityTypeButton(for: entityType)
            }
        }
    }
    
    func desktopEntityTypeButton(for entityType: EntityType) -> some View {
        Button(action: {
            selectedEntityType = entityType
        }) {
            HStack(spacing: 6) {
                Image(systemName: selectedEntityType == entityType ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(selectedEntityType == entityType ? entityType.color : .secondary)
                
                Text(entityType.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(selectedEntityType == entityType ? entityType.color : .primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(desktopEntityTypeButtonBackground(for: entityType))
        }
        .buttonStyle(PlainButtonStyle())
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
    
    func desktopEntityTypeButtonBackground(for entityType: EntityType) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selectedEntityType == entityType ? entityType.color.opacity(0.1) : Color.gray.opacity(0.1))
            .stroke(selectedEntityType == entityType ? entityType.color : Color.clear, lineWidth: 1)
    }
    
    var initialBalanceField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Initial Balance")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            HStack(spacing: 0) {
                TextField("0.00", text: $initialBalance)
                    .textFieldStyle(PlainTextFieldStyle())
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .initialBalance)
                    .submitLabel(.done)
                    #endif
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: initialBalance) { newValue in
                        // Ensure the balance reflects the selected type
                        updateBalanceForType()
                    }
                
                // Balance type buttons
                HStack(spacing: 4) {
                    ForEach(BalanceType.allCases, id: \.self) { type in
                        Button(action: {
                            balanceType = type
                            updateBalanceForType()
                        }) {
                            Text(type.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(balanceType == type ? .white : type.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(balanceType == type ? type.color : type.color.opacity(0.1))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.trailing, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.regularMaterial)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    var desktopInitialBalanceField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Initial Balance")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            HStack(spacing: 0) {
                TextField("0.00", text: $initialBalance)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .onChange(of: initialBalance) { newValue in
                        updateBalanceForType()
                    }
                
                // Balance type buttons
                HStack(spacing: 6) {
                    ForEach(BalanceType.allCases, id: \.self) { type in
                        Button(action: {
                            balanceType = type
                            updateBalanceForType()
                        }) {
                            Text(type.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(balanceType == type ? .white : type.color)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(balanceType == type ? type.color : type.color.opacity(0.1))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.trailing, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private func updateBalanceForType() {
        guard !initialBalance.isEmpty else { return }
        
        let numericValue = Double(initialBalance) ?? 0
        if numericValue == 0 { return }
        
        switch balanceType {
        case .toReceive:
            // Ensure positive value
            if numericValue < 0 {
                initialBalance = String(abs(numericValue))
            }
        case .toGive:
            // Ensure negative value
            if numericValue > 0 {
                initialBalance = "-" + initialBalance
            }
        }
    }
    
    var desktopDialogCloseButton: some View {
        Button(action: {
            isPresented = false
            onDismiss?()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
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

    
    var body: some View {
        if shouldShowiPhoneDialog {
            iPhoneDialogView
        } else {
            DesktopDialogView
        }
    }
    
    var iPhoneDialogView: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        isPresented = false
                        onDismiss?()
                    }
                    .foregroundColor(selectedEntityType.color)
                    
                    Spacer()
                    
                    Text("Edit Entity")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Save") {
                        Task {
                            await saveEntity()
                        }
                    }
                    .foregroundColor(selectedEntityType.color)
                    .fontWeight(.semibold)
                    .disabled(isUpdating || name.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.background)
                
                Divider()
                
                // Content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 24) {
                        // Entity Type Selection
                        entityTypeSelection
                        
                        // Name Field (Required)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name *")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            TextField("Enter customer name", text: $name)
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .focused($focusedField, equals: .name)
                                .submitLabel(.done)
                                #endif
                                .font(.system(size: 18, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.regularMaterial)
                                        .stroke(name.isEmpty ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                                .id("name")
                                .onChange(of: focusedField) { newValue in
                                    if newValue == .name {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("name", anchor: .center)
                                        }
                                    }
                                }
                        }
                        
                        // Initial Balance Field
                        initialBalanceField
                            .id("initialBalance")
                            .onChange(of: focusedField) { newValue in
                                if newValue == .initialBalance {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        proxy.scrollTo("initialBalance", anchor: .center)
                                    }
                                }
                            }
                        
                        // Phone Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Phone")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            TextField("Enter phone number", text: $phone)
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .keyboardType(.phonePad)
                                .focused($focusedField, equals: .phone)
                                .submitLabel(.done)
                                #endif
                                .font(.system(size: 18, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.regularMaterial)
                                )
                                .id("phone")
                                .onChange(of: focusedField) { newValue in
                                    if newValue == .phone {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("phone", anchor: .center)
                                        }
                                    }
                                }
                        }
                        
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            TextField("Enter email address", text: $email)
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .focused($focusedField, equals: .email)
                                .submitLabel(.done)
                                #endif
                                .font(.system(size: 18, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.regularMaterial)
                                )
                                .id("email")
                                .onChange(of: focusedField) { newValue in
                                    if newValue == .email {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("email", anchor: .center)
                                        }
                                    }
                                }
                        }
                        
                        // Address Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Address")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            TextField("Enter address", text: $address, axis: .vertical)
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .focused($focusedField, equals: .address)
                                .submitLabel(.return)
                                .onSubmit {
                                    focusedField = nil
                                }
                                #endif
                                .font(.system(size: 18, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.regularMaterial)
                                )
                                .lineLimit(3...6)
                                .id("address")
                                .onChange(of: focusedField) { newValue in
                                    if newValue == .address {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("address", anchor: .center)
                                        }
                                    }
                                }
                        }
                        
                        // Notes Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            TextField("Enter notes", text: $notes, axis: .vertical)
                                .textFieldStyle(PlainTextFieldStyle())
                                #if os(iOS)
                                .focused($focusedField, equals: .notes)
                                .submitLabel(.return)
                                .onSubmit {
                                    focusedField = nil
                                }
                                #endif
                                .font(.system(size: 18, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.regularMaterial)
                                )
                                .lineLimit(3...6)
                                .id("notes")
                                .onChange(of: focusedField) { newValue in
                                    if newValue == .notes {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            proxy.scrollTo("notes", anchor: .center)
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 34)
                    }
                }
            }
            .background(.background)
            .overlay(bufferOverlay)
            #if os(iOS)
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(action: {
                        switch focusedField {
                        case .name:
                            focusedField = .initialBalance
                        case .initialBalance:
                            focusedField = .phone
                        case .phone:
                            focusedField = .email
                        case .email:
                            focusedField = .address
                        case .address:
                            focusedField = .notes
                        case .notes:
                            break
                        case .none:
                            break
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("Next")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .disabled(focusedField == .notes)
                }
            }
            #endif
            .onAppear {
                // Pre-fill fields with existing entity data
                selectedEntityType = entityType
                name = editingEntity.name
                phone = editingEntity.phone
                email = editingEntity.email
                address = editingEntity.address
                notes = editingEntity.notes
                
                // Set balance and balance type
                let balance = editingEntity.balance
                if balance >= 0 {
                    balanceType = .toReceive
                    initialBalance = String(balance)
                } else {
                    balanceType = .toGive
                    initialBalance = String(abs(balance))
                }
                
                #if os(iOS)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .name
                }
                #endif
            }
        }
    }
    
    var DesktopDialogView: some View {
        VStack(spacing: 0) {
            desktopDialogHeader
            
            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 32)
            
            // Content area - Layout matching image
            VStack(spacing: 20) {
                // Top row: Name, Phone, Email (horizontal)
                HStack(spacing: 20) {
                    // Name Field (Required)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Name *")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        TextField("Enter customer name", text: $name)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 18, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                                    .stroke(name.isEmpty ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                    }
                    
                    // Phone Field
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Phone")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        TextField("Enter phone", text: $phone)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 18, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                            )
                    }
                    
                    // Email Field
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Email")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        TextField("Enter email", text: $email)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 18, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                            )
                    }
                }
                
                // Address Field (full width)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Address")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    TextField("Enter address", text: $address, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 18, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                        .lineLimit(3...6)
                }
                
                // Notes Field (full width)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Notes")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    TextField("Enter notes", text: $notes, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 18, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                        .lineLimit(3...6)
                }
                
                // Initial Balance Field (full width, under notes)
                desktopInitialBalanceField
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 20)
            
            // Action buttons
            HStack(spacing: 20) {
                Button(action: {
                    isPresented = false
                    onDismiss?()
                }) {
                    Text("Cancel")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                                .background(RoundedRectangle(cornerRadius: 16).fill(.background))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isUpdating)
                .opacity(isUpdating ? 0.6 : 1.0)
                .onHover { isHovering in
                    #if os(macOS)
                    if isHovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                    #endif
                }
                
                Button(action: {
                    Task {
                        await saveEntity()
                    }
                }) {
                    HStack(spacing: 12) {
                        if isUpdating {
                            ProgressView()
                                .scaleEffect(1.0)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(isUpdating ? "Saving..." : "Save \(selectedEntityType.rawValue)")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        selectedEntityType.color,
                                        selectedEntityType.color.opacity(0.8)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .shadow(color: selectedEntityType.color.opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isUpdating || name.isEmpty)
                .opacity((isUpdating || name.isEmpty) ? 0.7 : 1.0)
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
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(width: 800, height: 750)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.background)
                .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(bufferOverlay)
        .onAppear {
            // Pre-fill fields with existing entity data
            selectedEntityType = entityType
            name = editingEntity.name
            phone = editingEntity.phone
            email = editingEntity.email
            address = editingEntity.address
            notes = editingEntity.notes
            
            // Set balance and balance type
            let balance = editingEntity.balance
            if balance >= 0 {
                balanceType = .toReceive
                initialBalance = String(balance)
            } else {
                balanceType = .toGive
                initialBalance = String(abs(balance))
            }
        }
    }
    
    private func saveEntity() async {
        guard !name.isEmpty else { return }
        
        // Close keyboard immediately when save is clicked
        focusedField = nil
        isUpdating = true
        
        // Parse the balance and ensure it reflects the selected type
        var balance = Double(initialBalance) ?? 0.0
        
        // Apply the balance type logic
        switch balanceType {
        case .toReceive:
            balance = abs(balance) // Ensure positive
        case .toGive:
            balance = -abs(balance) // Ensure negative
        }
        
        // Create updated entity data for Firestore
        let updatedData: [String: Any] = [
            "name": name,
            "balance": balance,
            "phone": phone,
            "email": email,
            "address": address,
            "notes": notes,
            "updatedAt": Timestamp()
        ]
        
        do {
            let db = Firestore.firestore()
            
            // Check if we need to move the entity to a different collection
            if selectedEntityType != entityType {
                // Moving to different entity type - need to delete from old collection and add to new
                try await db.collection(entityType.collectionName).document(editingEntity.id).delete()
                try await db.collection(selectedEntityType.collectionName).document(editingEntity.id).setData(updatedData.merging([
                    "createdAt": Timestamp(),
                    "transactionHistory": []
                ]) { _, new in new })
            } else {
                // Same entity type - just update the document
                try await db.collection(selectedEntityType.collectionName).document(editingEntity.id).updateData(updatedData)
            }
            
            // Create updated entity profile for callback
            let updatedEntity = EntityProfile(
                id: editingEntity.id,
                name: name,
                phone: phone,
                email: email,
                balance: balance,
                address: address,
                notes: notes
            )
            
            // Show success state
            showSuccessToast = true
            
            // Add double haptic feedback
            #if os(iOS)
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            // Second haptic after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                impactFeedback.impactOccurred()
            }
            #endif
            
            // Call the onSave callback with updated entity
            onSave(updatedEntity)
            
            // Dismiss dialog after checkmark has been visible for 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isPresented = false
                onDismiss?()
            }
        } catch {
            print("Error updating entity: \(error)")
            // Reset updating state on error
            isUpdating = false
            
            // Show error feedback
            #if os(iOS)
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
            #endif
            
            // TODO: Show error alert to user
            return
        }
        
        isUpdating = false
    }
}

#Preview {
    EditEntityDialog(
        isPresented: .constant(true),
        entityType: .customer,
        editingEntity: EntityProfile(
            id: "preview",
            name: "John Doe",
            phone: "+1 234-567-8900",
            email: "john@example.com",
            balance: 1500.0,
            address: "123 Main St",
            notes: "Preview notes"
        ),
        onSave: { _ in },
        onDismiss: nil
    )
}