# iOS Dropdown Implementation Pattern for Sheets/Dialogs

## Overview
This document outlines the pattern for implementing searchable dropdowns in iOS sheets and dialogs that work reliably across iPhone and iPad.

## Key Principles

### 1. Inline Dropdown Approach
- **Use inline dropdowns** that push content down instead of overlays
- **Avoid positioning issues** that occur with absolute positioning across different screen sizes
- **Natural layout flow** - dropdown expands the form naturally

### 2. Separated Search Logic
- **Display Text**: `searchText` - what user sees in the field
- **Internal Filtering**: `internalSearchText` - controls dropdown content filtering
- **Sync Logic**: When user types, both get updated
- **Clear Logic**: When dropdown opens, only `internalSearchText` gets cleared

## Implementation Components

### 1. State Variables
```swift
@State private var brandSearchText = ""        // Display text in field
@State private var selectedBrand = ""          // Currently selected brand
@State private var showingBrandDropdown = false // Dropdown open state
@State private var brandButtonFrame: CGRect = .zero // Button frame
@State private var phoneBrands: [String] = []   // Available options
@State private var isLoadingBrands = false     // Loading state
@FocusState private var isBrandFocused: Bool   // Field focus state
@State private var internalSearchText = ""     // Internal search for filtering
```

### 2. BrandDropdownButton Structure
```swift
struct BrandDropdownButton: View {
    @Binding var searchText: String           // Display text
    @Binding var selectedBrand: String        // Selected value
    @Binding var isOpen: Bool                 // Open state
    @Binding var buttonFrame: CGRect          // Frame for positioning
    @FocusState.Binding var isFocused: Bool   // Focus state
    @Binding var internalSearchText: String   // Internal filtering
    let isLoading: Bool                       // Loading state
}
```

### 3. Dropdown Logic
```swift
.onChange(of: searchText) { newValue in
    // Sync internal search with display text
    internalSearchText = newValue
    if !newValue.isEmpty && !isOpen && newValue != selectedBrand {
        isOpen = true
    }
}
.onChange(of: isOpen) { newValue in
    // Clear internal search when opening dropdown to show full list
    if newValue {
        internalSearchText = ""
    }
}
```

### 4. Inline Dropdown Implementation
```swift
// In brand field VStack
#if os(iOS)
if showingBrandDropdown {
    BrandDropdownOverlay(
        isOpen: $showingBrandDropdown,
        selectedBrand: $selectedBrand,
        searchText: $brandSearchText,
        internalSearchText: $internalSearchText,
        brands: phoneBrands,
        buttonFrame: brandButtonFrame,
        onAddBrand: { brandName in
            addNewBrand(brandName)
        }
    )
    .frame(maxWidth: .infinity, alignment: .leading)
    .transition(.opacity.combined(with: .scale(scale: 0.95)))
}
#endif
```

### 5. Dropdown Content Structure
```swift
private var inlineDropdown: some View {
    VStack(spacing: 0) {
        // Add option (if applicable)
        if shouldShowAddOption {
            cleanBrandRow(
                title: "Add '\(internalSearchText)'",
                isAddOption: true,
                action: { /* add logic */ }
            )
        }
        
        // Options in ScrollView for overflow
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredBrands.prefix(8)), id: \.self) { brand in
                    cleanBrandRow(
                        title: brand,
                        isAddOption: false,
                        action: { /* selection logic */ }
                    )
                }
            }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading) // Full width, left aligned
    .frame(height: 200) // Fixed height
    .background(.regularMaterial)
    .cornerRadius(8)
    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    .animation(.easeInOut(duration: 0.2), value: isOpen)
}
```

### 6. Filtering Logic
```swift
private var filteredBrands: [String] {
    if internalSearchText.isEmpty {
        return brands.sorted() // Show all brands when no search
    } else {
        return brands.filter { brand in
            brand.localizedCaseInsensitiveContains(internalSearchText)
        }.sorted()
    }
}

private var shouldShowAddOption: Bool {
    return !internalSearchText.isEmpty && !brands.contains { 
        $0.localizedCaseInsensitiveCompare(internalSearchText) == .orderedSame 
    }
}
```

## Key Benefits

1. **Reliable Positioning**: No complex coordinate calculations needed
2. **Cross-Device Compatibility**: Works consistently on iPhone, iPad, and different screen sizes
3. **Natural UX**: Content flows naturally as dropdown expands
4. **Proper Search Logic**: Field text preserved, dropdown shows full list when clicked
5. **Smooth Animations**: Scale + opacity transitions for professional feel
6. **Performance**: LazyVStack for efficient rendering of large lists

## Usage Pattern

1. **User clicks dropdown** → Shows full unfiltered list
2. **User types** → Filters results in real-time
3. **User selects** → Dropdown closes, field shows selection
4. **User clicks again** → Shows full list (not filtered), field text preserved

## Platform Notes

- **iOS Only**: Use `#if os(iOS)` for inline dropdowns in sheets/dialogs
- **macOS**: Can use overlay approach with positioning for desktop apps
- **Conditional Compilation**: Ensure proper platform-specific behavior

This pattern provides reliable, user-friendly dropdowns that work consistently across all iOS devices and screen sizes.
