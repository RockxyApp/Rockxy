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
        panel.message = String(localized: "Choose a .rockxysession file to open")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        if case let .failure(sizeError) = ImportSizePolicy.validateFileSize(
            at: url,
            maxSize: ImportSizePolicy.maxSessionFileSize
        ) {
            Self.logger.error("Session import rejected: \(sizeError.localizedDescription)")
            showImportError(
                title: String(localized: "Session Too Large"),
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
        } catch let error as SessionSerializerError {
            Self.logger.error("Failed to open session: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "Invalid Session File"),
                message: String(
                    localized: "\"\(url.lastPathComponent)\" could not be read.\n\n\(error.localizedDescription)"
                )
            )
        } catch {
            Self.logger.error("Failed to open session: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "Session Import Failed"),
                message: String(
                    localized: "Could not read \"\(url.lastPathComponent)\".\n\n\(error.localizedDescription)"
                )
            )
        }
    }

    // MARK: - Import HAR

    func importHAR() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.har, .json]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a HAR file to import")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        if case let .failure(sizeError) = ImportSizePolicy.validateFileSize(
            at: url,
            maxSize: ImportSizePolicy.maxHARFileSize
        ) {
            Self.logger.error("HAR import rejected: \(sizeError.localizedDescription)")
            showImportError(
                title: String(localized: "HAR File Too Large"),
                message: sizeError.localizedDescription
            )
            return
        }

        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0

            let data = try Data(contentsOf: url)
            let importer = HARImporter()
            let importedTransactions = try importer.importData(data)

            let preview = ImportPreview(
                fileName: url.lastPathComponent,
                fileType: .har,
                transactionCount: importedTransactions.count,
                logEntryCount: 0,
                fileSize: fileSize,
                captureStartDate: nil,
                captureEndDate: nil,
                rockxyVersion: nil,
                sourceURL: url
            )

            importPreview = preview
        } catch {
            Self.logger.error("Failed to pre-parse HAR: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "HAR Import Failed"),
                message: String(
                    localized: "Could not import \"\(url.lastPathComponent)\".\n\nThe file may not be a valid HAR archive. \(error.localizedDescription)"
                )
            )
        }
    }

    // MARK: - Execute Import

    func executeImport(_ preview: ImportPreview) {
        importPreview = nil

        switch preview.fileType {
        case .har:
            executeHARImport(from: preview.sourceURL, fileName: preview.fileName)
        case .rockxysession:
            executeSessionImport(from: preview.sourceURL, fileName: preview.fileName)
        }
    }

    func cancelImport() {
        importPreview = nil
    }

    // MARK: - Private

    private func executeHARImport(from url: URL, fileName: String) {
        do {
            let data = try Data(contentsOf: url)
            let importer = HARImporter()
            let importedTransactions = try importer.importData(data)

            clearSession()

            for transaction in importedTransactions {
                transaction.sequenceNumber = nextSequenceNumber
                nextSequenceNumber += 1
                transactions.append(transaction)
                updateDomainTree(for: transaction)
                updateAppNodes(for: transaction)
            }
            recomputeFilteredTransactions()
            headerColumnStore.updateDiscoveredHeaders(from: transactions)

            sessionProvenance = SessionProvenance(
                fileName: fileName,
                transactionCount: importedTransactions.count,
                logEntryCount: 0,
                importedAt: Date()
            )

            activeToast = ToastMessage(
                style: .success,
                text: String(localized: "Imported \(importedTransactions.count) transactions from \(fileName)")
            )

            Self.logger.info("Imported HAR from \(fileName): \(importedTransactions.count) transactions")
        } catch {
            Self.logger.error("Failed to import HAR: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "HAR Import Failed"),
                message: String(localized: "Could not import \"\(fileName)\".\n\n\(error.localizedDescription)")
            )
        }
    }

    private func executeSessionImport(from url: URL, fileName: String) {
        do {
            let data = try Data(contentsOf: url)
            let session = try SessionSerializer.deserialize(from: data)

            clearSession()

            for codableTransaction in session.transactions {
                let transaction = codableTransaction.toLiveModel()
                transaction.sequenceNumber = nextSequenceNumber
                nextSequenceNumber += 1
                transactions.append(transaction)
                updateDomainTree(for: transaction)
                updateAppNodes(for: transaction)
            }

            if let codableLogEntries = session.logEntries {
                logEntries = codableLogEntries.map { $0.toLiveModel() }
            }

            recomputeFilteredTransactions()
            headerColumnStore.updateDiscoveredHeaders(from: transactions)

            sessionProvenance = SessionProvenance(
                fileName: fileName,
                transactionCount: session.transactions.count,
                logEntryCount: session.logEntries?.count ?? 0,
                importedAt: Date()
            )

            activeToast = ToastMessage(
                style: .success,
                text: String(localized: "Opened session with \(session.transactions.count) transactions")
            )

            Self.logger.info("Opened session from \(fileName): \(session.transactions.count) transactions")
        } catch {
            Self.logger.error("Failed to open session: \(error.localizedDescription)")
            showImportError(
                title: String(localized: "Session Import Failed"),
                message: String(localized: "Could not read \"\(fileName)\".\n\n\(error.localizedDescription)")
            )
        }
    }

    private func showImportError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}
