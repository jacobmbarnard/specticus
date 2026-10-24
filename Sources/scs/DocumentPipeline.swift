import Foundation

// MARK: - Shared assemble → number → publish (internals #21)

/// Shared front half of `scs build` and `scs export markdown`.
/// Caller passes a loaded project and flags; this type does not load config itself.
/// Each command renders and writes its own artifact from the prepared markdown + publish result.
enum DocumentPipeline {
    struct Options: Sendable {
        /// Single-file mode; `nil` discovers multi-file sources like build/export today.
        var input: String? = nil
        var skipHeadingNumbers: Bool = false
        var skipAssets: Bool = false
        /// Anchor for the asset tree (parent of the HTML path). Defaults to `project.defaultOutputPath`.
        /// Export keeps sharing the HTML output tree even when writing `export.md`.
        var outputHTMLPath: String? = nil
    }

    struct Assembled: Sendable {
        /// Assembled Markdown, optionally heading-numbered.
        let markdown: String
        /// Effective heading-number max level (0 when skipped / disabled).
        let headingMaxLevel: Int
    }

    struct Result: Sendable {
        let markdown: String
        let publish: ResourcePublisher.PublishResult
        /// Whether asset copy was requested after config + flags.
        let copyAssets: Bool
        let headingMaxLevel: Int
    }

    /// Assemble sources and optionally number headings (no asset I/O).
    static func assembleAndNumber(
        project: SpecticusProject,
        options: Options = Options()
    ) throws -> Assembled {
        var markdown = try DocumentGenerator.assembleSources(
            input: options.input,
            baseDirectory: project.root.path,
            fallbackInput: project.config.build.defaultInput,
            layout: project.assemblyLayout
        )

        let headingMax = options.skipHeadingNumbers ? 0 : project.config.build.headingNumberMaxLevel
        if headingMax > 0 {
            markdown = HeadingNumberer.numberHeadings(in: markdown, maxLevel: headingMax)
        }

        return Assembled(markdown: markdown, headingMaxLevel: headingMax)
    }

    /// Publish CSS/images/SVGs for the HTML output tree.
    static func publishAssets(
        project: SpecticusProject,
        options: Options = Options()
    ) throws -> (publish: ResourcePublisher.PublishResult, copyAssets: Bool) {
        let copyAssets = project.config.build.copyAssets && !options.skipAssets
        let htmlPath = options.outputHTMLPath ?? project.defaultOutputPath
        let publish = try ResourcePublisher.publish(
            projectRoot: project.root,
            outputHTMLPath: htmlPath,
            sourceCSS: project.styleSheetPath,
            diagramsDir: project.config.build.diagramsDir,
            copyAssets: copyAssets
        )
        return (publish, copyAssets)
    }

    /// Assemble, optionally number headings, then publish assets.
    static func prepare(project: SpecticusProject, options: Options = Options()) throws -> Result {
        let assembled = try assembleAndNumber(project: project, options: options)
        let published = try publishAssets(project: project, options: options)
        return Result(
            markdown: assembled.markdown,
            publish: published.publish,
            copyAssets: published.copyAssets,
            headingMaxLevel: assembled.headingMaxLevel
        )
    }
}
