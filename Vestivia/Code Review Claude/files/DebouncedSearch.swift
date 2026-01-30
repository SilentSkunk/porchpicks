// Add this to InstantSearchScreen.swift

import Combine

// STEP 1: Add debounced search state
@State private var searchDebounceTask: Task<Void, Never>? = nil

// STEP 2: Replace queryBinding with debounced version
private var queryBinding: Binding<String> {
    Binding(
        get: { coordinator.searchBoxController.query },
        set: { newValue in
            coordinator.searchBoxController.query = newValue
            
            // Cancel previous search
            searchDebounceTask?.cancel()
            
            // Only search if query is empty (instant clear) or after 300ms delay
            if newValue.isEmpty {
                coordinator.searchBoxController.submit()
            } else {
                searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                    if !Task.isCancelled {
                        await MainActor.run {
                            coordinator.searchBoxController.submit()
                        }
                    }
                }
            }
        }
    )
}
