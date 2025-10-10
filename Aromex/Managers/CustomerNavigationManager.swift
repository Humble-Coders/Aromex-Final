// Add this new class to handle customer navigation
import SwiftUI
import Combine

class CustomerNavigationManager: ObservableObject {
    static let shared = CustomerNavigationManager()
    
    @Published var shouldNavigateToDetails = false
    @Published var selectedCustomerForNavigation: Customer?
    @Published var shouldShowCustomerDetail = false
    
    private init() {}
    
    func navigateToCustomer(_ customer: Customer) {
        selectedCustomerForNavigation = customer
        shouldNavigateToDetails = true
        shouldShowCustomerDetail = true
    }
    
    func resetNavigation() {
        shouldNavigateToDetails = false
        // Don't reset selectedCustomerForNavigation here, let the detail view handle it
    }
    
    func clearSelectedCustomer() {
        selectedCustomerForNavigation = nil
        shouldShowCustomerDetail = false
    }
}
