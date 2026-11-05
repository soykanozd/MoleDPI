// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine

struct ReleaseVersion: Comparable, Equatable {
    let numbers: [Int]
    let beta: Bool
    init?(_ tag: String) {
        let value = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard value.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+(-beta)?$", options:.regularExpression) != nil else { return nil }
        beta = value.hasSuffix("-beta")
        numbers = value.replacingOccurrences(of:"-beta",with:"").split(separator:".").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
    }
    static func < (a:Self,b:Self) -> Bool {
        if a.numbers != b.numbers { return a.numbers.lexicographicallyPrecedes(b.numbers) }
        return a.beta && !b.beta
    }
}
@MainActor final class UpdateChecker: ObservableObject {
    @Published private(set) var message = ""
    @Published private(set) var checking = false
    @Published private(set) var releaseURL: URL?
    private var task: Task<Void,Never>?
    static func safeURL(_ value: String) -> URL? {
        guard let url = URL(string:value), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.path.hasPrefix("/soykanozd/MoleDPI/releases/tag/"),
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }
    func check() {
        guard !checking else { return }
        checking = true; message = "Checking GitHub…"; releaseURL = nil
        task = Task {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 10
            configuration.httpCookieStorage = nil
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel(); checking = false }
            do {
                var request = URLRequest(url:URL(string:"https://api.github.com/repos/soykanozd/MoleDPI/releases?per_page=30")!)
                request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
                let (data,response) = try await session.data(for:request)
                guard !Task.isCancelled else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000,
                      let releases = try JSONSerialization.jsonObject(with:data) as? [[String:Any]] else {
                    throw URLError(.badServerResponse)
                }
                let tag = Bundle.main.object(forInfoDictionaryKey:"MoleReleaseTag") as? String ??
                    ((Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.9.3")+"-beta")
                guard let current = ReleaseVersion(tag) else { throw URLError(.cannotParseResponse) }
                let candidates = releases.compactMap { entry -> (ReleaseVersion,URL)? in
                    guard entry["draft"] as? Bool == false, let tag = entry["tag_name"] as? String,
                          let version = ReleaseVersion(tag), let raw = entry["html_url"] as? String,
                          let url = Self.safeURL(raw) else { return nil }
                    return (version,url)
                }
                if let newest = candidates.max(by: { $0.0 < $1.0 }), newest.0 > current {
                    releaseURL = newest.1; message = "An update is available."
                } else { message = "You're up to date." }
            } catch {
                if !Task.isCancelled { message = "Could not check for updates. Try again later." }
            }
        }
    }
    func cancel() { task?.cancel() }
}
