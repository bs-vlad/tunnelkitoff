@MainActor
class AppViewModel: ObservableObject {
    // ... existing properties ...
    
    init(/* your init parameters */) {
        // ... other initialization code ...
        
        // Set up logger callback
        CustomLogger.shared.setLogCallback { [weak self] timestamp, message, isError, level in
            let formattedMessage = "[\(level)] \(message)"
            self?.addDebugLog(formattedMessage, isError: isError)
        }
    }
    
    func addDebugLog(_ message: String, isError: Bool = false) {
        Task { @MainActor in
            mainScreenState.logScreenModel.addLog(message, isError: isError)
            customLog(message)
        }
    }
} 