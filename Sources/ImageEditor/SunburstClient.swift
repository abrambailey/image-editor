import Foundation
import Security

protocol AIImageEditing {
    func edit(image: Data, mask: Data?, prompt: String, size: String, transparentBackground: Bool, apiKey: String) async throws -> Data
}

/// Direct requests only: redirects must never forward the user's credential.
final class SunburstClient: NSObject, AIImageEditing, URLSessionTaskDelegate, @unchecked Sendable {
    static let model = "gpt-image-2.5-sunburst"

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    static func request(image: Data, mask: Data?, prompt: String, size: String, transparentBackground: Bool, apiKey: String) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw EditorError.message("Enter a valid OpenAI API key in Connection.")
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EditorError.message("Describe the change you want to make.")
        }
        guard image.count < 50 * 1024 * 1024, (mask?.count ?? 0) < 4 * 1024 * 1024 else {
            throw EditorError.message("This image or selection is too large to send. Try a smaller canvas.")
        }
        let boundary = "ImageEditor-" + UUID().uuidString
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        func file(_ name: String, _ data: Data) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(name).png\"\r\nContent-Type: image/png\r\n\r\n")
            body.append(data)
            append("\r\n")
        }
        field("model", model)
        let backgroundInstruction = transparentBackground
            ? "Preserve a transparent background using the output alpha channel. Areas exposed by removing an isolated object must be transparent. Do not replace transparency with black, white, a checkerboard, or another backdrop."
            : "Preserve the existing background except where the user's instruction asks to change it."
        field("prompt", """
        Edit the supplied image according to the user's instruction. Preserve the composition, geometry, text, colors, and fine details of everything unrelated to the requested change. If a mask is supplied, use its transparent region as the intended edit area. Keep the image dimensions and framing unchanged. Any blank padding around the image is not part of the scene.
        \(backgroundInstruction)

        User instruction:
        \(prompt)
        """)
        field("quality", "high")
        field("size", size)
        field("output_format", "png")
        field("background", transparentBackground ? "transparent" : "auto")
        field("n", "1")
        file("image", image)
        if let mask { file("mask", mask) }
        append("--\(boundary)--\r\n")
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 240
        return request
    }

    static func decodeResponse(_ data: Data, status: Int, apiKey: String = "") throws -> Data {
        guard (200...299).contains(status) else {
            let message: String
            switch status {
            case 401: message = "OpenAI rejected the API key. Update it in Connection and try again."
            case 403, 404: message = "This OpenAI project cannot access Sunburst. Check model access and organization verification."
            case 429: message = "OpenAI’s usage or rate limit was reached. Check API billing and limits, then try again."
            case 500...599: message = "OpenAI could not complete the edit. Try again in a moment."
            default:
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let detail = (json?["error"] as? [String: Any])?["message"] as? String
                let safe = apiKey.isEmpty ? detail : detail?.replacingOccurrences(of: apiKey, with: "[redacted]")
                message = "OpenAI could not complete the edit (\(status)). " + String((safe ?? "Please try again.").prefix(500))
            }
            throw EditorError.message(message)
        }
        struct Response: Decodable {
            struct Item: Decodable { let b64_json: String? }
            let data: [Item]
        }
        guard data.count <= 96 * 1024 * 1024,
              let result = try? JSONDecoder().decode(Response.self, from: data),
              let encoded = result.data.first?.b64_json,
              let bytes = Data(base64Encoded: encoded), !bytes.isEmpty else {
            throw EditorError.message("OpenAI returned no readable image. Your original is unchanged; try another instruction.")
        }
        return bytes
    }

    func edit(image: Data, mask: Data?, prompt: String, size: String, transparentBackground: Bool, apiKey: String) async throws -> Data {
        let request = try Self.request(image: image, mask: mask, prompt: prompt, size: size,
                                       transparentBackground: transparentBackground, apiKey: apiKey)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 300
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw EditorError.message("Couldn’t read OpenAI’s response. Try again.")
        }
        return try Self.decodeResponse(data, status: http.statusCode, apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum OpenAIKeyStore {
    private static let service = "local.image-editor.openai"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
    }

    static func load() -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        let data = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
                throw EditorError.message("Couldn’t save the API key in Keychain. You can still use it for this session.")
            }
        } else if status != errSecSuccess {
            throw EditorError.message("Couldn’t update the API key in Keychain. You can still use it for this session.")
        }
    }

    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EditorError.message("Couldn’t remove the saved key. Open Keychain Access to remove local.image-editor.openai.")
        }
    }
}
