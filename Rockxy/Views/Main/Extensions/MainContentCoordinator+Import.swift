import AppKit
import Foundation
import os
import UniformTypeIdentifiers

// Extends `MainContentCoordinator` with import behavior for the main workspace.

// MARK: - MainContentCoordinator + Import

/// Coordinator extension for importing sessions from native `.rockxysession` files
/// and HAR archives. Both flows show an `ImportReviewSheet` for user confirmation
/// before performing any destructive session replacement.
extension MainContentCoordinator {
    // MARK: - Open Session

    func openSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.rockxySession]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a .rockxysession file to open", bundle: RockxyLocalization.bundle)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        prepareSessionImport(from: url)
    }

    /// Validates and pre-parses a `.rockxysession` file, then presents the
    /// import review sheet. Shared by File > Open, Finder opens, and drops.
    func prepareSessionImport(from url: URL) {
        if case let .failure(sizeError) = ImportSizePolicy.validateFileSize(
            at: url,
            maxSize: ImportSizePolicy.maxSessionFileSize
        ) {
            Self.logger.error("Session import rejected: \(sizeError.localizedDescription)")
            showImportError(
                title: String(localized: "Session Too Large", bundle: RockxyLocalization.bundle),
                message: sizeError.localizedDescription
            )
            return
        }

        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0

            let data = try Data(contentsOf: url)
            let session = try SessionSerializer.deserialize(from: data)

            let preview = ImportPreview(
                fileName: url.lastPathComponent,
                fileType: .rockxysession,
                transactionCount: session.transactions.count,
                logEntryCount: session.logEntries?.count ?? 0,
                fileSize: fileSize,
                captureStartDate: session.metadata.captureStartDate,
                captureEndDate: session.metadata.captureEndDate,
                rockxyVersion: session.metadata.rockxyVersion,
                sourceURL: url
            )

            importPreview = preview
            RecentCaptureDocuments.shared.note(url)
        } catch let error as SessionSerializerError {
            Self.logger.error("Failed to open session: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "Invalid Session File", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "\"\(url.lastPathComponent)\" could not be read.\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            )
        } catch {
            Self.logger.error("Failed to open session: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "Session Import Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not read \"\(url.lastPathComponent)\".\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    // MARK: - Import HAR

    func importHAR() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.har, .json]
            + [UTType(filenameExtension: "chlsj"), UTType(filenameExtension: "chls")].compactMap(\.self)
        panel.allowsMultipleSelection = false
        panel.message = String(
            localized: "Choose a HAR file or a Charles session (.chlsj or .chls) to import",
            bundle: RockxyLocalization.bundle
        )

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        if ExternalCaptureDocumentKind(url: url) == .charlesBinarySession {
            prepareCharlesSessionImport(from: url)
        } else {
            prepareHARImport(from: url)
        }
    }

    // MARK: - Import Charles Session

    nonisolated static let charlesConversionConsentKey = RockxyIdentity.current
        .defaultsKey("charlesConversionConsented")

    /// Converts a binary Charles session with the installed Charles, after a one-time
    /// consent, then shows the usual import review for the converted HAR.
    func prepareCharlesSessionImport(
        from url: URL,
        converter: CharlesSessionConverter = CharlesSessionConverter(),
        defaults: UserDefaults = .standard,
        askConsent: @MainActor () -> Bool = MainContentCoordinator.confirmCharlesConversion
    ) {
        guard converter.isCharlesInstalled else {
            showImportError(
                title: String(localized: "Charles Is Not Installed", bundle: RockxyLocalization.bundle),
                message: CharlesSessionConverterError.charlesNotInstalled.localizedDescription
            )
            return
        }
        if !defaults.bool(forKey: Self.charlesConversionConsentKey) {
            guard askConsent() else {
                return
            }
            defaults.set(true, forKey: Self.charlesConversionConsentKey)
        }
        if case let .failure(sizeError) = ImportSizePolicy.validateFileSize(
            at: url,
            maxSize: ImportSizePolicy.maxHARFileSize
        ) {
            showImportError(
                title: String(localized: "Session Too Large", bundle: RockxyLocalization.bundle),
                message: sizeError.localizedDescription
            )
            return
        }
        activeToast = ToastMessage(
            style: .success,
            text: String(
                localized: "Converting \(url.lastPathComponent) with Charles…",
                bundle: RockxyLocalization.bundle
            )
        )
        Task { @MainActor in
            do {
                let har = try await converter.convertToHAR(url)
                let directory = har.deletingLastPathComponent()
                do {
                    let converted = try await Task.detached(priority: .userInitiated) {
                        try Self.makeHARPreview(from: har)
                    }.value
                    var preview = ImportPreview(
                        fileName: url.lastPathComponent,
                        fileType: .charlesSession,
                        transactionCount: converted.transactionCount,
                        logEntryCount: 0,
                        fileSize: (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0,
                        captureStartDate: nil,
                        captureEndDate: nil,
                        rockxyVersion: nil,
                        sourceURL: har,
                        skippedEntryCount: converted.skippedEntryCount
                    )
                    preview.temporaryDirectory = directory
                    importPreview = preview
                    RecentCaptureDocuments.shared.note(url)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    showHARPreviewFailure(error, url: url)
                }
            } catch {
                Self.logger.error("Charles conversion failed: \(error.localizedDescription)")
                showImportError(
                    title: String(localized: "Charles Session Import Failed", bundle: RockxyLocalization.bundle),
                    message: error.localizedDescription
                )
            }
        }
    }

    /// One-time notice before Rockxy runs another app's converter.
    static func confirmCharlesConversion() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Convert with Charles?", bundle: RockxyLocalization.bundle)
        alert.informativeText = String(
            localized: """
            .chls is Charles's own format, so Rockxy asks the installed Charles to convert the file to \
            HAR, then imports that. Charles runs in the background without opening a window or changing \
            proxy settings. Rockxy won't ask again.
            """,
            bundle: RockxyLocalization.bundle
        )
        alert.addButton(withTitle: String(localized: "Convert", bundle: RockxyLocalization.bundle))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: RockxyLocalization.bundle))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Validates and pre-parses a HAR archive, then presents the import review
    /// sheet. Shared by File > Import, Finder opens, and drops.
    func prepareHARImport(from url: URL) {
        if case let .failure(sizeError) = ImportSizePolicy.validateFileSize(
            at: url,
            maxSize: ImportSizePolicy.maxHARFileSize
        ) {
            Self.logger.error("HAR import rejected: \(sizeError.localizedDescription)")
            showImportError(
                title: String(localized: "HAR File Too Large", bundle: RockxyLocalization.bundle),
                message: sizeError.localizedDescription
            )
            return
        }

        // A small archive is parsed in place so the review sheet appears immediately; a large
        // one is read and parsed off the main actor so the UI never freezes.
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        if fileSize <= Self.inlineHARParseLimit {
            do {
                presentHARPreview(try Self.makeHARPreview(from: url), url: url)
            } catch {
                showHARPreviewFailure(error, url: url)
            }
            return
        }
        Task { @MainActor in
            do {
                let preview = try await Task.detached(priority: .userInitiated) {
                    try Self.makeHARPreview(from: url)
                }.value
                presentHARPreview(preview, url: url)
            } catch {
                showHARPreviewFailure(error, url: url)
            }
        }
    }

    nonisolated static let inlineHARParseLimit: Int64 = 1_048_576

    nonisolated static func makeHARPreview(from url: URL) throws -> ImportPreview {
        let fileSize = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let data = try Data(contentsOf: url)
        let result = try HARImporter().importReportingSkips(data)
        return ImportPreview(
            fileName: url.lastPathComponent,
            fileType: isCharlesJSONSession(data) ? .charlesJSON : .har,
            transactionCount: result.transactions.count,
            logEntryCount: 0,
            fileSize: fileSize,
            captureStartDate: nil,
            captureEndDate: nil,
            rockxyVersion: nil,
            sourceURL: url,
            skippedEntryCount: result.skipped
        )
    }

    private func presentHARPreview(_ preview: ImportPreview, url: URL) {
        importPreview = preview
        RecentCaptureDocuments.shared.note(url)
    }

    private func showHARPreviewFailure(_ error: Error, url: URL) {
        Self.logger.error("Failed to pre-parse HAR: \(error.localizedDescription)")
        showImportError(
            title: String(localized: "HAR Import Failed", bundle: RockxyLocalization.bundle),
            message: String(
                localized: "Could not import \"\(url.lastPathComponent)\".\n\nThe file may not be a valid HAR archive. \(error.localizedDescription)",
                bundle: RockxyLocalization.bundle
            )
        )
    }

    // MARK: - External Documents

    nonisolated static func isCharlesJSONSession(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)).map(CharlesJSONSessionImporter.looksLikeSession) ?? false
    }

    /// Opens a capture document handed to Rockxy from Finder, the Dock, or a
    /// drop onto the main window. Only the first supported file is reviewed,
    /// because an import replaces the current session after confirmation.
    /// Returns `false` when none of the URLs is a supported capture document.
    @discardableResult
    func openExternalDocuments(_ urls: [URL]) -> Bool {
        guard let (url, kind) = urls.lazy
            .compactMap({ url in ExternalCaptureDocumentKind(url: url).map { (url, $0) } })
            .first else
        {
            return false
        }
        switch kind {
        case .session:
            prepareSessionImport(from: url)
        case .har:
            prepareHARImport(from: url)
        case .charlesBinarySession:
            prepareCharlesSessionImport(from: url)
        }
        return true
    }

    // MARK: - Execute Import

    func executeImport(_ preview: ImportPreview) {
        importPreview = nil

        Task { @MainActor in
            guard await ensureProjectCatalogReadyForDataIntake() else {
                showImportError(
                    title: String(localized: "Import Unavailable", bundle: RockxyLocalization.bundle),
                    message: String(
                        localized: "Projects could not be loaded. Repair Projects before importing captured traffic.",
                        bundle: RockxyLocalization.bundle
                    )
                )
                return
            }
            defer { removeTemporaryImportFiles(of: preview) }
            switch preview.fileType {
            case .har,
                 .charlesJSON,
                 .charlesSession:
                await executeHARImport(from: preview.sourceURL, fileName: preview.fileName)
            case .rockxysession:
                await executeSessionImport(from: preview.sourceURL, fileName: preview.fileName)
            }
        }
    }

    func cancelImport() {
        if let importPreview {
            removeTemporaryImportFiles(of: importPreview)
        }
        importPreview = nil
    }

    private func removeTemporaryImportFiles(of preview: ImportPreview) {
        if let directory = preview.temporaryDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - Private

    private func executeHARImport(from url: URL, fileName: String) async {
        do {
            let importedTransactions = try await Task.detached(priority: .userInitiated) {
                try HARImporter().importData(try Data(contentsOf: url))
            }.value

            await clearSession()
            let captureContext = activeCaptureContext

            for transaction in importedTransactions {
                transaction.assignCaptureContextIfMissing(captureContext)
                transaction.sequenceNumber = nextSequenceNumber
                nextSequenceNumber += 1
                transactions.append(transaction)
                updateDomainTree(for: transaction)
                updateAppNodes(for: transaction)
            }
            transactionsByProjectID[projectStore.activeProjectID] = transactions
            nextSequenceNumberByProjectID[projectStore.activeProjectID] = nextSequenceNumber
            let overflow = max(0, transactions.count - liveHistoryLimit)
            if overflow > 0 {
                evictOldestTransactions(count: overflow)
            }
            rebuildObservedDomainsByApp()
            recomputeFilteredTransactions()
            headerColumnStore.updateDiscoveredHeaders(from: transactions)
            TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)

            sessionProvenance = SessionProvenance(
                fileName: fileName,
                transactionCount: importedTransactions.count,
                logEntryCount: 0,
                importedAt: Date()
            )
            sessionProvenanceByProjectID[projectStore.activeProjectID] = sessionProvenance

            activeToast = ToastMessage(
                style: .success,
                text: String(AttributedString(
                    localized: "Imported ^[\(importedTransactions.count) transaction](inflect: true) from \(fileName)",
                    bundle: RockxyLocalization.bundle,
                    locale: RockxyLocalization.locale
                ).characters)
            )

            Self.logger.info("Imported HAR from \(fileName): \(importedTransactions.count) transactions")
        } catch {
            Self.logger.error("Failed to import HAR: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "HAR Import Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not import \"\(fileName)\".\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    private func executeSessionImport(from url: URL, fileName: String) async {
        do {
            let data = try Data(contentsOf: url)
            let session = try SessionSerializer.deserialize(from: data)

            await clearSession()
            let captureContext = activeCaptureContext

            for codableTransaction in session.transactions {
                let transaction = codableTransaction.toLiveModel()
                transaction.assignCaptureContextIfMissing(captureContext)
                transaction.sequenceNumber = nextSequenceNumber
                nextSequenceNumber += 1
                transactions.append(transaction)
                updateDomainTree(for: transaction)
                updateAppNodes(for: transaction)
            }
            transactionsByProjectID[projectStore.activeProjectID] = transactions
            nextSequenceNumberByProjectID[projectStore.activeProjectID] = nextSequenceNumber
            let overflow = max(0, transactions.count - liveHistoryLimit)
            if overflow > 0 {
                evictOldestTransactions(count: overflow)
            }
            rebuildObservedDomainsByApp()

            if let codableLogEntries = session.logEntries {
                logEntries = codableLogEntries.map { $0.toLiveModel() }
            }
            let maxLogs = AppSettingsStorage.load().maxLogBufferSize
            if logEntries.count > maxLogs {
                logEntries.removeFirst(logEntries.count - maxLogs)
            }
            logEntriesByProjectID[projectStore.activeProjectID] = logEntries

            recomputeFilteredTransactions()
            headerColumnStore.updateDiscoveredHeaders(from: transactions)
            TrafficDomainSnapshot.shared.update(appNodes: appNodes, domainTree: domainTree)

            sessionProvenance = SessionProvenance(
                fileName: fileName,
                transactionCount: session.transactions.count,
                logEntryCount: session.logEntries?.count ?? 0,
                importedAt: Date()
            )
            sessionProvenanceByProjectID[projectStore.activeProjectID] = sessionProvenance

            activeToast = ToastMessage(
                style: .success,
                text: String(AttributedString(
                    localized: "Opened session with ^[\(session.transactions.count) transaction](inflect: true)",
                    bundle: RockxyLocalization.bundle,
                    locale: RockxyLocalization.locale
                ).characters)
            )

            Self.logger.info("Opened session from \(fileName): \(session.transactions.count) transactions")
        } catch {
            Self.logger.error("Failed to open session: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "Session Import Failed", bundle: RockxyLocalization.bundle),
                message: String(
                    localized: "Could not read \"\(fileName)\".\n\n\(error.localizedDescription)",
                    bundle: RockxyLocalization.bundle
                )
            )
        }
    }

    private func showImportError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK", bundle: RockxyLocalization.bundle))
        alert.runModal()
    }
}
