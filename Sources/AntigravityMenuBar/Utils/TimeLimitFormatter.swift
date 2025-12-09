import Foundation

/// Utility for parsing and formatting time limits
struct TimeLimitFormatter {
    
    /// Parse time string "HH:mm" and date string "dd.MM.yyyy" into a Date
    /// - Parameters:
    ///   - time: Time string in format "HH:mm" (e.g., "14:30")
    ///   - date: Date string in format "dd.MM.yyyy" (e.g., "31.12.2026")
    /// - Returns: Combined Date or nil if parsing fails
    static func parse(time: String, date: String) -> Date? {
        let combined = "\(time) \(date)"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm dd.MM.yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: combined)
    }
    
    /// Format a Date to countdown string showing remaining time
    /// - Parameter date: Target date to count down to
    /// - Returns: Formatted string like "2d 5:30:45" or nil if expired
    static func formatCountdown(to date: Date) -> String? {
        let now = Date()
        
        if date <= now {
            return nil  // Don't show anything when expired
        }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute, .second], from: now, to: date)
        
        let days = components.day ?? 0
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0
        
        // Format as HH:mm:ss with optional days prefix
        if days > 0 {
            return String(format: "  ⏳ %dd %d:%02d:%02d", days, hours, minutes, seconds)
        } else {
            return String(format: "  ⏳ %d:%02d:%02d", hours, minutes, seconds)
        }
    }
    
    /// Format current date as default date string
    /// - Returns: Today's date in "dd.MM.yyyy" format
    static func defaultDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: Date())
    }
    
    /// Format current time as default time string
    /// - Returns: Current time in "HH:mm" format
    static func defaultTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
    
    /// Format compact countdown for menu bar display
    /// - Parameter date: Target date to count down to
    /// - Returns: Compact formatted string like "8:40" or "2d 5:30"
    static func formatMenuBarCountdown(to date: Date) -> String {
        let now = Date()
        
        if date <= now {
            return ""
        }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute, .second], from: now, to: date)
        
        let days = components.day ?? 0
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0
        
        // Compact format for menu bar
        if days > 0 {
            return String(format: "%dd %d:%02d:%02d", days, hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
    }
}
