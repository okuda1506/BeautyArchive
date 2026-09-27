import Foundation
import LinkPresentation
import UniformTypeIdentifiers

struct ProductImageCandidate: Identifiable {
    let id = UUID()
    let data: Data
    let source: String
}

enum ProductImageFetcher {
    private static let maximumImageBytes = 15_000_000
    private static let maximumPageBytes = 500_000

    @MainActor
    static func fetchCandidates(from url: URL) async -> [ProductImageCandidate] {
        async let preview = linkPreviewImage(from: url)
        async let pageImages = pageImageURLs(from: url)

        var candidates: [ProductImageCandidate] = []
        if let image = await preview {
            candidates.append(ProductImageCandidate(
                data: image, source: "リンクプレビュー · \(url.host ?? "購入先")"
            ))
        }

        let imageURLs = await pageImages
        for imageURL in imageURLs.prefix(3) where candidates.count < 3 {
            guard let image = try? await imageData(from: imageURL),
                  !candidates.contains(where: { $0.data == image }) else { continue }
            candidates.append(ProductImageCandidate(
                data: image, source: imageURL.host ?? "商品ページ"
            ))
        }
        return candidates
    }

    @MainActor
    private static func linkPreviewImage(from url: URL) async -> Data? {
        let metadataProvider = LPMetadataProvider()
        metadataProvider.timeout = 8
        guard let metadata = try? await metadataProvider.startFetchingMetadata(for: url),
              let imageProvider = metadata.imageProvider,
              let imageType = imageProvider.registeredTypeIdentifiers.first(where: {
                  UTType($0)?.conforms(to: .image) == true
              }) else { return nil }

        let original: Data? = try? await withCheckedThrowingContinuation { continuation in
            imageProvider.loadDataRepresentation(forTypeIdentifier: imageType) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? ImageFetchError.unavailable) }
            }
        }
        guard let original, original.count <= maximumImageBytes else { return nil }
        return await Task.detached(priority: .utility) {
            PhotoImageProcessor.optimizedJPEG(original)
        }.value
    }

    private static func pageImageURLs(from url: URL) async -> [URL] {
        do {
            let (data, response) = try await limitedData(
                from: url, maximumBytes: maximumPageBytes, allowTruncation: true
            )
            guard response.mimeType?.lowercased().contains("html") == true else { return [] }
            let pageURL = response.url ?? url
            return imageURLs(in: String(decoding: data, as: UTF8.self), relativeTo: pageURL)
        } catch {
            return []
        }
    }

    static func imageURLs(in html: String, relativeTo pageURL: URL) -> [URL] {
        guard let metaPattern = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive]),
              let attributePattern = try? NSRegularExpression(
                  pattern: #"([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
                  options: [.caseInsensitive]
              ) else { return [] }
        let nsHTML = html as NSString
        var urls: [URL] = []
        var seen = Set<String>()
        for tagMatch in metaPattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            let tag = nsHTML.substring(with: tagMatch.range)
            let nsTag = tag as NSString
            var attributes: [String: String] = [:]
            for match in attributePattern.matches(in: tag, range: NSRange(location: 0, length: nsTag.length)) {
                let key = nsTag.substring(with: match.range(at: 1)).lowercased()
                let valueRange = (2...4).map { match.range(at: $0) }
                    .first { $0.location != NSNotFound }
                if let valueRange { attributes[key] = nsTag.substring(with: valueRange) }
            }
            guard let name = attributes["property"] ?? attributes["name"],
                  ["og:image", "og:image:secure_url", "twitter:image"].contains(name.lowercased()),
                  let content = attributes["content"] else { continue }
            let decoded = content.replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&#38;", with: "&")
            guard let resolved = URL(string: decoded, relativeTo: pageURL)?.absoluteURL,
                  isAllowedHTTPSURL(resolved), seen.insert(resolved.absoluteString).inserted
            else { continue }
            urls.append(resolved)
            if urls.count == 3 { break }
        }
        return urls
    }

    private static func imageData(from url: URL) async throws -> Data? {
        let (data, response) = try await limitedData(from: url, maximumBytes: maximumImageBytes)
        guard response.mimeType?.lowercased().hasPrefix("image/") == true else { return nil }
        return await Task.detached(priority: .utility) {
            PhotoImageProcessor.optimizedJPEG(data)
        }.value
    }

    private static func limitedData(
        from url: URL, maximumBytes: Int, allowTruncation: Bool = false
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        request.setValue("text/html,image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let responseURL = response.url, isAllowedHTTPSURL(responseURL),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { throw ImageFetchError.unavailable }
        var data = Data()
        for try await byte in bytes {
            if data.count == maximumBytes {
                if allowTruncation { break }
                throw ImageFetchError.tooLarge
            }
            data.append(byte)
        }
        return (data, response)
    }

    private static func isAllowedHTTPSURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), host.contains("."),
              host != "localhost", !host.hasSuffix(".local"),
              !host.hasSuffix(".internal"), components.user == nil, components.password == nil
        else { return false }
        return !host.split(separator: ".").allSatisfy { UInt8($0) != nil }
    }

    private enum ImageFetchError: Error {
        case unavailable
        case tooLarge
    }
}
