import Foundation
import CoreText
import SwiftUI

final class FontRegistrar {
    static let shared = FontRegistrar()
    private var registeredURLs: Set<URL> = []

    func registerFont(at url: URL) -> String? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        registeredURLs.insert(url)

        guard let provider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(provider),
              let postScriptName = cgFont.postScriptName as String? else {
            return nil
        }
        return postScriptName
    }

    func unregisterAll() {
        for url in registeredURLs {
            var error: Unmanaged<CFError>?
            CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &error)
        }
        registeredURLs.removeAll()
    }
}
