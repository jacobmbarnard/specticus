import Foundation
import ArgumentParser

// MARK: - Resource publishing (implements #9)

/// Copies CSS, images, and SVGs into a structured output tree and rewrites HTML references.
enum ResourcePublisher {
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "ico", "bmp", "avif"
    ]
    static let svgExtensions: Set<String> = ["svg"]

    /// Subdirectories under the project root that are scanned recursively for media.
    static let recursiveAssetDirs: [String] = [
        "images", "img", "assets", "media", "figures", "static"
    ]

    struct PublishResult: Sendable {
        /// Relative stylesheet href for the HTML (e.g. `css/style.css`).
        let stylesheetHref: String
        /// Original reference path → new path relative to the HTML file.
        let pathRewrites: [String: String]
        /// Human-readable summary lines of what was copied.
        let copiedDescriptions: [String]
        /// Absolute URL of the output root directory (parent of the HTML file).
        let outputRoot: URL
    }

    /// Discover assets under `projectRoot`, copy them next to the HTML output, return rewrite map + CSS href.
    static func publish(
        projectRoot: URL,
        outputHTMLPath: String,
        sourceCSS: String,
        diagramsDir: String,
        copyAssets: Bool
    ) throws -> PublishResult {
        let fm = FileManager.default
        let htmlURL = resolve(outputHTMLPath, relativeTo: projectRoot)
        let outputRoot = htmlURL.deletingLastPathComponent().standardizedFileURL

        try fm.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        var rewrites: [String: String] = [:]
        var copied: [String] = []
        var stylesheetHref = sourceCSS

        // --- CSS
        let cssSource = resolve(sourceCSS, relativeTo: projectRoot)
        if fm.fileExists(atPath: cssSource.path) {
            if copyAssets {
                let cssName = cssSource.lastPathComponent
                let cssDestDir = outputRoot.appendingPathComponent("css", isDirectory: true)
                try fm.createDirectory(at: cssDestDir, withIntermediateDirectories: true)
                let cssDest = cssDestDir.appendingPathComponent(cssName)
                try copyFile(from: cssSource, to: cssDest, fm: fm)
                stylesheetHref = "css/\(cssName)"
                copied.append("css/\(cssName)")
                // Rewrite common ways of referencing the source CSS
                rewrites[sourceCSS] = stylesheetHref
                rewrites[cssName] = stylesheetHref
                if sourceCSS.hasPrefix("./") {
                    rewrites[String(sourceCSS.dropFirst(2))] = stylesheetHref
                }
            } else {
                stylesheetHref = sourceCSS
            }
        }

        guard copyAssets else {
            return PublishResult(
                stylesheetHref: stylesheetHref,
                pathRewrites: rewrites,
                copiedDescriptions: copied,
                outputRoot: outputRoot
            )
        }

        // --- Images & SVGs
        let outputRootPath = outputRoot.standardizedFileURL.path
        let discovered = try discoverMedia(
            projectRoot: projectRoot,
            diagramsDir: diagramsDir,
            excludingOutputRoot: outputRootPath,
            fm: fm
        )

        for asset in discovered {
            let kindDir = asset.isSVG ? "svg" : "img"
            // Preserve path relative to its discovery base when nested; else use basename.
            let destRelative = "\(kindDir)/\(asset.relativeDest)"
            let destURL = outputRoot.appendingPathComponent(destRelative)
            try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try copyFile(from: asset.sourceURL, to: destURL, fm: fm)
            copied.append(destRelative)

            // Map every known source reference form → dest relative to HTML
            for key in asset.referenceKeys {
                rewrites[key] = destRelative
            }
        }

        return PublishResult(
            stylesheetHref: stylesheetHref,
            pathRewrites: rewrites,
            copiedDescriptions: copied,
            outputRoot: outputRoot
        )
    }

    /// Apply path rewrites to HTML `src` / `href` attributes (quoted).
    static func rewriteReferences(in html: String, rewrites: [String: String]) -> String {
        guard !rewrites.isEmpty else { return html }

        // Longest keys first so more-specific paths win over basenames.
        let sorted = rewrites.keys.sorted { $0.count > $1.count }
        var result = html

        for original in sorted {
            guard let replacement = rewrites[original] else { continue }
            // Avoid no-op churn
            if original == replacement { continue }
            let escaped = NSRegularExpression.escapedPattern(for: original)
            // Match src="..." or href="..." (double or single quotes)
            let pattern = #"(?i)(\b(?:src|href)\s*=\s*)(["'])\#(escaped)\2"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1$2\(replacement)$2"
            )
        }
        return result
    }

    // MARK: - Discovery

    struct MediaAsset {
        let sourceURL: URL
        /// Path under img/ or svg/ (may include subdirs).
        let relativeDest: String
        let isSVG: Bool
        /// Keys that might appear in Markdown/HTML references.
        let referenceKeys: [String]
    }

    static func discoverMedia(
        projectRoot: URL,
        diagramsDir: String,
        excludingOutputRoot: String,
        fm: FileManager
    ) throws -> [MediaAsset] {
        var assets: [MediaAsset] = []
        var seenSources = Set<String>()

        func consider(file url: URL, pathUnderBase: String) {
            let ext = url.pathExtension.lowercased()
            let isSVG = svgExtensions.contains(ext)
            let isImage = imageExtensions.contains(ext)
            guard isSVG || isImage else { return }

            let standardized = url.standardizedFileURL.path
            // Skip anything already inside the output tree
            if standardized == excludingOutputRoot || standardized.hasPrefix(excludingOutputRoot + "/") {
                return
            }
            guard seenSources.insert(standardized).inserted else { return }

            let relativeDest = pathUnderBase.isEmpty ? url.lastPathComponent : pathUnderBase
            var keys: [String] = [
                relativeDest,
                url.lastPathComponent,
                pathUnderBase
            ].filter { !$0.isEmpty }

            // Also key by path relative to project root when different
            let rootPath = projectRoot.standardizedFileURL.path
            if standardized.hasPrefix(rootPath + "/") {
                let fromRoot = String(standardized.dropFirst(rootPath.count + 1))
                keys.append(fromRoot)
                keys.append("./\(fromRoot)")
            }

            assets.append(MediaAsset(
                sourceURL: url,
                relativeDest: relativeDest,
                isSVG: isSVG,
                referenceKeys: Array(Set(keys))
            ))
        }

        // Shallow scan of project root
        let rootContents = (try? fm.contentsOfDirectory(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in rootContents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue { continue }
            consider(file: url, pathUnderBase: url.lastPathComponent)
        }

        // Recursive asset folders
        var dirsToWalk = recursiveAssetDirs
        if !diagramsDir.isEmpty, !dirsToWalk.contains(diagramsDir) {
            dirsToWalk.append(diagramsDir)
        }

        for dirName in dirsToWalk {
            let dirURL = projectRoot.appendingPathComponent(dirName, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let enumerator = fm.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                var isFileDir: ObjCBool = false
                if fm.fileExists(atPath: fileURL.path, isDirectory: &isFileDir), isFileDir.boolValue {
                    continue
                }
                // Path relative to the asset directory (e.g. screens/a.png)
                let dirPath = dirURL.standardizedFileURL.path
                let filePath = fileURL.standardizedFileURL.path
                var rel = fileURL.lastPathComponent
                if filePath.hasPrefix(dirPath + "/") {
                    rel = String(filePath.dropFirst(dirPath.count + 1))
                }
                // Also keep keys as dirName/rel for Markdown like images/foo.png
                consider(file: fileURL, pathUnderBase: rel)
                // Extra keys for folder-qualified references are added in consider via fromRoot
            }
        }

        return assets.sorted { $0.relativeDest < $1.relativeDest }
    }

    // MARK: - Helpers

    static func resolve(_ path: String, relativeTo root: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return root.appendingPathComponent(path).standardizedFileURL
    }

    static func copyFile(from source: URL, to dest: URL, fm: FileManager) throws {
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: source, to: dest)
    }

    /// Returns the top-level generated directory to remove on clean, if any.
    /// For `output/index.html` → `output`. For bare `output.html` at root → nil (file-only clean).
    static func cleanableOutputDirectory(outputHTMLPath: String, projectRoot: URL) -> URL? {
        let htmlURL = resolve(outputHTMLPath, relativeTo: projectRoot)
        let parent = htmlURL.deletingLastPathComponent().standardizedFileURL
        let root = projectRoot.standardizedFileURL
        // Only auto-remove a dedicated output directory, never the project root.
        if parent.path == root.path || parent.path == root.path + "/" {
            return nil
        }
        // Prefer the first path component under the project as the clean root when
        // output is nested like output/index.html → clean `output/`.
        let parentPath = parent.path
        let rootPath = root.path
        guard parentPath.hasPrefix(rootPath + "/") else {
            // Absolute path outside project — clean the HTML parent only if it looks like an output dir
            return parent
        }
        let relative = String(parentPath.dropFirst(rootPath.count + 1))
        let firstComponent = relative.split(separator: "/").first.map(String.init) ?? relative
        // Convention: directories named output, dist, build, out, site, public, docs-output
        let known = Set(["output", "dist", "build", "out", "site", "public", "docs", "html"])
        if known.contains(firstComponent) {
            return root.appendingPathComponent(firstComponent, isDirectory: true)
        }
        // Otherwise remove only the immediate parent of the HTML (e.g. custom/path/doc.html → custom/path)
        return parent
    }
}
