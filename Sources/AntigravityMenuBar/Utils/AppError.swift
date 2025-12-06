import Foundation

enum AppError: LocalizedError {
    case databaseNotFound(path: String)
    case databaseConnectionFailed
    case failedToReadBackup(path: String)
    case failedToWriteBackup(path: String)
    case failedToRestoreDatabase
    case accountNotFound
    
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
        }
    }
}
