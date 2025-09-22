# Aromex Development Notes

## SwiftUI Dropdown Implementation Patterns

### Standard Searchable Dropdown Architecture

**Universal Pattern for All Platforms**: Use this exact pattern for all searchable dropdowns throughout the app.

#### 1. Separated Button Architecture
```swift
struct DropdownButton: View {
    @Binding var searchText: String
    @Binding var selectedItem: String
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect
    @FocusState.Binding var isFocused: Bool
    @Binding var internalSearchText: String
    let isLoading: Bool
    let isEnabled: Bool
    
    var body: some View {
        ZStack {
            // Main TextField with padding for the button
            TextField(isEnabled ? "Choose an option" : "Select a brand first", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 18, weight: .medium))
                .focused($isFocused)
                .padding(.horizontal, 20)
                .padding(.trailing, 50) // Extra padding for button area
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                )
                .disabled(!isEnabled)
                .onTapGesture {
                    if isEnabled {
                        withAnimation {
                            isOpen.toggle()
                        }
                        if isOpen {
                            isFocused = false
                        }
                    }
                }
                .onChange(of: searchText) { newValue in
                    // Sync internal search with display text
                    internalSearchText = newValue
                    if !newValue.isEmpty && !isOpen && newValue != selectedItem {
                        isOpen = true
                    }
                }
                .onChange(of: isOpen) { newValue in
                    // Clear internal search when opening dropdown to show full list
                    if newValue {
                        internalSearchText = ""
                    }
                }
            
            // Separate button positioned on the right
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 20)
                } else {
                    Button(action: {
                        if isEnabled {
                            withAnimation {
                                isOpen.toggle()
                            }
                            if isOpen {
                                isFocused = false
                            }
                        }
                    }) {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .frame(width: 40, height: 40) // Larger clickable area
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!isEnabled)
                    .onHover { isHovering in
                        #if os(macOS)
                        if isHovering && isEnabled {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                        #endif
                    }
                    .padding(.trailing, 10)
                }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        buttonFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { newFrame in
                        buttonFrame = newFrame
                    }
            }
        )
    }
}
```

#### 2. Dynamic Height Implementation
```swift
// iOS/iPhone/iPad Dynamic Height
private var dynamicDropdownHeight: CGFloat {
    let itemHeight: CGFloat = 50
    let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
    let itemCount = filteredItems.count
    
    if itemCount <= 4 {
        // For small lists, calculate exact height
        let itemHeight = CGFloat(itemCount) * itemHeight
        let totalHeight = addOptionHeight + itemHeight
        return min(totalHeight, 240)
    } else {
        // For larger lists, use fixed height with scroll
        return min(addOptionHeight + (4 * itemHeight), 240)
    }
}

// macOS Dynamic Height
private var dynamicMacOSDropdownHeight: CGFloat {
    let itemHeight: CGFloat = 50
    let addOptionHeight: CGFloat = shouldShowAddOption ? itemHeight : 0
    let itemCount = filteredItems.count
    
    if itemCount <= 3 {
        // For small lists, calculate exact height
        let itemHeight = CGFloat(itemCount) * itemHeight
        let totalHeight = addOptionHeight + itemHeight
        return min(totalHeight, 250)
    } else {
        // For larger lists, use fixed height with scroll
        return min(addOptionHeight + (3 * itemHeight), 250)
    }
}
```

#### 3. Platform-Specific Dropdown Display
```swift
var body: some View {
    Group {
        #if os(iOS)
        // Inline dropdown that pushes content down (iOS only)
        inlineDropdown
        #else
        // Positioned dropdown for macOS
        positionedDropdown
        #endif
    }
}

// iOS Inline Dropdown
private var inlineDropdown: some View {
    VStack(spacing: 0) {
        // Add option (if applicable)
        if shouldShowAddOption {
            VStack(spacing: 0) {
                cleanItemRow(
                    title: "Add '\(internalSearchText)'",
                    isAddOption: true,
                    action: {
                        isOpen = false
                        onAddItem(internalSearchText)
                    }
                )
                
                // Separator after add option
                if !filteredItems.isEmpty {
                    Divider()
                        .background(Color.secondary.opacity(0.4))
                        .frame(height: 0.5)
                        .padding(.horizontal, 16)
                }
            }
        }
        
        // Existing items - always use ScrollView for consistency
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredItems.enumerated()), id: \.element) { index, item in
                    VStack(spacing: 0) {
                        cleanItemRow(
                            title: item,
                            isAddOption: false,
                            action: {
                                isOpen = false
                                selectedItem = item
                                searchText = item
                            }
                        )
                        
                        // Subtle separator between items
                        if index < filteredItems.count - 1 {
                            Divider()
                                .background(Color.secondary.opacity(0.4))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: dynamicDropdownHeight)
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
    )
    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isOpen)
}

// macOS Positioned Dropdown
private var positionedDropdown: some View {
    GeometryReader { geometry in
        VStack(spacing: 0) {
            // Add option (if applicable)
            if shouldShowAddOption {
                VStack(spacing: 0) {
                    cleanItemRow(
                        title: "Add '\(internalSearchText)'",
                        isAddOption: true,
                        action: {
                            isOpen = false
                            onAddItem(internalSearchText)
                        }
                    )
                    
                    // Separator after add option
                    if !filteredItems.isEmpty {
                        Divider()
                            .background(Color.secondary.opacity(0.4))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }
                }
            }
            
            // Existing items - always use ScrollView for consistency
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredItems.enumerated()), id: \.element) { index, item in
                        VStack(spacing: 0) {
                            cleanItemRow(
                                title: item,
                                isAddOption: false,
                                action: {
                                    isOpen = false
                                    selectedItem = item
                                    searchText = item
                                }
                            )
                            
                            // Divider between items
                            if index < filteredItems.count - 1 {
                                Divider()
                                    .background(Color.secondary.opacity(0.4))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: dynamicMacOSDropdownHeight)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .frame(width: buttonFrame.width)
        .offset(
            x: buttonFrame.minX,
            y: buttonFrame.maxY + 5
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .allowsHitTesting(true)
}
```

#### 4. Key Implementation Principles

**Always Use ScrollView**: Never use conditional logic to switch between VStack and ScrollView. Always use ScrollView for consistency and reliability.

**Separate Internal Search**: Use `internalSearchText` for filtering while keeping `searchText` for display. This prevents dropdown reopening when user clicks to expand menu.

**Dynamic Height Logic**: 
- **iOS/iPhone/iPad**: ≤4 items = exact height, >4 items = fixed height with scroll
- **macOS**: ≤3 items = exact height, >3 items = fixed height with scroll

**Platform-Specific Display**:
- **iOS**: Inline dropdown that pushes content down
- **macOS**: Positioned dropdown overlay

**Consistent Styling**:
- **Item Height**: 50pt per item
- **Dividers**: `Color.secondary.opacity(0.4)` with 0.5pt height
- **Background**: `.regularMaterial` with 12pt corner radius
- **Shadow**: `Color.black.opacity(0.08)` with 12pt radius

#### 5. Benefits of This Pattern

**Reliability**: Dropdowns never break down with large item counts
**Performance**: LazyVStack only renders visible items
**Consistency**: Same behavior across all platforms
**UX**: Dynamic height prevents wasted space for small lists
**Accessibility**: Larger click targets and proper focus management
**Maintainability**: Standardized pattern reduces bugs and development time

### macOS Dropdown Double-Click Fix

**Issue**: Searchable dropdowns on macOS requiring double-clicks to select items.

**Root Cause**: 
1. User clicks dropdown item → `searchText = selectedValue`
2. `onChange(of: searchText)` triggers → Reopens dropdown
3. Requires second click to actually close dropdown

**Solution Pattern**:
```swift
// ❌ Problematic (causes double-click):
.onChange(of: searchText) { _ in
    if !searchText.isEmpty && !isOpen {
        isOpen = true  // Always reopens when text is set
    }
}

// ✅ Fixed (single-click works):
.onChange(of: searchText) { newValue in
    if !newValue.isEmpty && !isOpen && newValue != selectedItem {
        isOpen = true  // Only reopens for actual typing, not selection
    }
}
```

**Key Principle**: Distinguish between user typing (should open dropdown) vs programmatic selection (should keep dropdown closed).

**Action Order in Selection**:
```swift
action: {
    isOpen = false           // 1. Close first
    selectedItem = item      // 2. Update selection
    searchText = item        // 3. Update text (won't reopen due to logic above)
}
```

---

## Platform-Specific Dialog Implementation

### Issue: Missing Data Fetch on Different Platforms

**Problem**: When using platform-specific views (`iPhoneDialogView` vs `DesktopDialogView`), each view needs its own lifecycle management.

**Solution**: Ensure each platform-specific view has its own `onAppear` with data fetching:

```swift
var body: some View {
    if shouldShowiPhoneDialog {
        iPhoneDialogView
            .onAppear { fetchData() }  // ✅ iPhone needs this
    } else {
        DesktopDialogView
            .onAppear { fetchData() }  // ✅ Desktop needs this too
    }
}
```

**Lesson**: Platform-specific views are independent - don't assume shared lifecycle events.

---

## Date Picker Implementation Pattern

Use consistent date picker pattern across all platforms:
- **iPhone**: `fullScreenCover` with NavigationView and normal-sized calendar
- **iPad**: `popover` (450x400 frame, 1.0x scale, 30pt padding) positioned below field  
- **macOS**: `popover` (400x350 frame, 1.5x scale, 30pt padding) positioned below field

Implemented using `DatePickerModifier` with platform-specific conditional compilation.

---

## UX Consistency Patterns

### Confirmation Overlays
Use white checkmark in green circle with haptic feedback and slight delay throughout the app.

### Keyboard Toolbars  
iPad and iPhone should include Next and other relevant buttons, with proxy scroll centering screen when typing.

### Dialog Implementation
Use same dialog implementation pattern for iPhone, iPad, and MacBook throughout the app, including consistent data transfer and unified UI/UX practices.

---

## Development Debugging Strategy

When implementing complex UI interactions:

1. **Add Debug Logging**: Print statements at key interaction points
2. **Test Platform-Specific**: Each platform may behave differently
3. **Check State Flow**: Trace how state changes trigger other state changes
4. **Isolate Root Cause**: Use console output to identify exactly where logic breaks

**Example Debug Pattern**:
```swift
.onChange(of: searchText) { newValue in
    print("searchText changed to: '\(newValue)', selectedBrand: '\(selectedBrand)'")
    if !newValue.isEmpty && !isOpen && newValue != selectedBrand {
        print("Opening dropdown due to typing")
        isOpen = true
    } else {
        print("Not opening dropdown - selection or empty")
    }
}
```
