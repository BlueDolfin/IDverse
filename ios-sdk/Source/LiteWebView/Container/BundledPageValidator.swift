import Foundation

/// Spec §5a: the bundled bridge page must resolve INSIDE the app bundle. Canonicalizes
/// both URLs — `..` traversal is normalized AND symlinks are resolved (a link placed
/// inside the bundle must not alias content outside it; standardization alone cannot
/// catch that) — then requires a true path-component prefix (so "/x/Demo.appEvil"
/// cannot pass as inside "/x/Demo.app").
enum BundledPageValidator {
    static func validate(_ page: URL?, bundleURL: URL) -> URL? {
        guard let page, page.isFileURL, bundleURL.isFileURL else { return nil }
        let resolvedPage = page.canonicalFileURL
        let pageComponents = resolvedPage.pathComponents
        let bundleComponents = bundleURL.canonicalFileURL.pathComponents
        guard pageComponents.count > bundleComponents.count,
              Array(pageComponents.prefix(bundleComponents.count)) == bundleComponents
        else { return nil }
        return resolvedPage
    }
}
