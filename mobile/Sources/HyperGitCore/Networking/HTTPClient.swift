// HTTPClient / HTTPTransport — minimal async HTTP layer over URLSession.
// Clients depend on the Transport closure so tests can inject canned JSON and
// exercise real decoding logic without a network.
import Foundation

public enum HTTPError: Error, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: Int?)
    case badStatus(Int)
    case decoding(String)
}

/// A transport returns the raw body bytes for a GET of `path` (relative to the
/// client base URL, may include a query string) plus the response headers
/// (keys lowercased) for the given extra headers. Headers are exposed so clients
/// can follow pagination `Link` relations.
public typealias HTTPTransport = @Sendable (String, [String: String]) async throws -> (Data, [String: String])

public struct HTTPClient: Sendable {
    public let session: URLSession
    public let userAgent: String

    public init(session: URLSession = .shared, userAgent: String = "HyperGitMobile/0.1") {
        self.session = session
        self.userAgent = userAgent
    }

    /// Build a default GET transport for a base URL with a token provider and
    /// default headers. Returns the body + response headers on 2xx, maps status
    /// codes to HTTPError.
    public static func transport(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () -> String?,
        defaultHeaders: [String: String] = [:],
        session: URLSession = .shared,
        userAgent: String = "HyperGitMobile/0.1"
    ) -> HTTPTransport {
        return { path, headers in
            guard let url = URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path) else {
                throw HTTPError.invalidURL
            }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            for (k, v) in defaultHeaders { req.setValue(v, forHTTPHeaderField: k) }
            if let token = tokenProvider() {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

            let (data, resp): (Data, URLResponse)
            do {
                (data, resp) = try await session.data(for: req)
            } catch {
                throw HTTPError.invalidResponse
            }
            guard let http = resp as? HTTPURLResponse else { throw HTTPError.invalidResponse }
            switch http.statusCode {
            case 200..<300:
                var respHeaders: [String: String] = [:]
                for (key, value) in http.allHeaderFields {
                    if let k = (key as? String)?.lowercased(), let v = value as? String {
                        respHeaders[k] = v
                    }
                }
                return (data, respHeaders)
            case 401: throw HTTPError.unauthorized
            case 403:
                let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap { Int($0) }
                if retry != nil { throw HTTPError.rateLimited(retryAfter: retry) }
                throw HTTPError.forbidden
            case 404: throw HTTPError.notFound
            default: throw HTTPError.badStatus(http.statusCode)
            }
        }
    }
}
