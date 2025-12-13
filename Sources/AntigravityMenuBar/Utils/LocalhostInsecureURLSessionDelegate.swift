import Foundation

final class LocalhostInsecureURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Antigravity language_server uses a local HTTPS endpoint with a self-signed cert.
        // We only accept it for localhost.
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let host = challenge.protectionSpace.host.lowercased() as String? else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if host == "127.0.0.1" || host == "localhost" {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }
}
