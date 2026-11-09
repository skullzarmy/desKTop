import Foundation

/// Runtime helper for EditArt parametric on-chain artwork
public enum EditArtRuntime {
    /// Formats parametric parameter values with standard EditArt 0.XXX precision
    public static func formatParameterQuery(parameters: [String: Double], seed: String? = nil) -> String {
        var queryItems: [URLQueryItem] = []

        if let s = seed {
            queryItems.append(URLQueryItem(name: "seed", value: s))
        }

        // Sort keys for deterministic URL generation
        for key in parameters.keys.sorted() {
            let val = parameters[key] ?? 0.0
            // Format to 0.XXX
            let formatted = String(format: "%.3f", val)
            queryItems.append(URLQueryItem(name: key, value: formatted))
        }

        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery ?? ""
    }
}
