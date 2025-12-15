import Foundation

enum AppError: LocalizedError {
    case databaseNotFound(path: String)
    case databaseConnectionFailed
    case failedToReadBackup(path: String)
    case failedToWriteBackup(path: String)
    case failedToRestoreDatabase
    case accountNotFound
    case languageServerNotFound
    case languageServerPortNotFound
    case quotaFetchFailed(message: String)
    case commandFailed(message: String)
    
    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let path):
            return "Database file not found at: \(path)"
        case .databaseConnectionFailed:
            return "Failed to connect to the database."
        case .failedToReadBackup(let path):
            return "Failed to read backup file at: \(path)"
        case .failedToWriteBackup(let path):
            return "Failed to save backup file to: \(path)"
        case .failedToRestoreDatabase:
            return "Failed to restore data to database."
        case .accountNotFound:
            return "Account not found."
        case .languageServerNotFound:
            return "Could not find Antigravity language server process. Make sure Antigravity is running."
        case .languageServerPortNotFound:
            return "Could not detect Antigravity language server port."
        case .quotaFetchFailed(let message):
            return "Failed to fetch quota: \(message)"
        case .commandFailed(let message):
            return "Command failed: \(message)"
        }
    }
}
