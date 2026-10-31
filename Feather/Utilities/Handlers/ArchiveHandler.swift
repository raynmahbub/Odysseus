//
//  ArchiveHandler.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import Foundation
import UIKit.UIApplication
import Zip
import SwiftUI
import IDeviceSwift
import NimbleExtensions

/// A value snapshot made on the viewContext queue before archive work is
/// detached. It contains no NSManagedObject references.
struct AppArchiveSnapshot: Sendable {
	let appURL: URL
	let name: String?
	let version: String?
	let identifier: String?
}

@MainActor
final class ArchiveHandler: NSObject {
	@ObservedObject var viewModel: InstallerStatusViewModel

	private let _uuid = UUID().uuidString
	private var _payloadUrl: URL?
	private let _app: AppArchiveSnapshot
	private let _uniqueWorkDir: URL

	init(snapshot: AppArchiveSnapshot, viewModel: InstallerStatusViewModel) {
		self.viewModel = viewModel
		self._app = snapshot
		self._uniqueWorkDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("FeatherInstall_\(_uuid)", isDirectory: true)
		super.init()
	}

	func move() async throws {
		let sourceURL = _app.appURL
		let workDirectory = _uniqueWorkDir
		let payloadURL = workDirectory.appendingPathComponent("Payload")
		let movedAppURL = payloadURL.appendingPathComponent(sourceURL.lastPathComponent)
		try await Task.detached(priority: .utility) {
			try FileManager.default.createDirectoryIfNeeded(at: payloadURL)
			try FileManager.default.copyItem(at: sourceURL, to: movedAppURL)
		}.value
		_payloadUrl = payloadURL
	}

	func archive() async throws -> URL {
		guard let payloadURL = _payloadUrl else {
			throw SigningFileHandlerError.appNotFound
		}

		let workDirectory = _uniqueWorkDir
		let zipURL = workDirectory.appendingPathComponent("Archive.zip")
		let ipaURL = workDirectory.appendingPathComponent("Archive.ipa")
		let compression = Self.getCompressionLevel()
		let progressChannel = AsyncStream<Double>.makeStream()
		let progressContinuation = progressChannel.continuation
		let archiveTask = Task.detached(priority: .background) {
			defer { progressContinuation.finish() }
			try Zip.zipFiles(
				paths: [payloadURL],
				zipFilePath: zipURL,
				password: nil,
				compression: ZipCompression.allCases[compression],
				progress: { progress in
					progressContinuation.yield(progress)
				}
			)
			try FileManager.default.moveItem(at: zipURL, to: ipaURL)
			return ipaURL
		}

		for await progress in progressChannel.stream {
			viewModel.packageProgress = progress
		}
		return try await archiveTask.value
	}

	func moveToArchive(_ package: URL, shouldOpen: Bool = false) async throws -> URL {
		let name = _app.name.flatMap { $0.isEmpty ? nil : $0 } ?? "App"
		let version = _app.version.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
		let destination = FileManager.default.archives.appendingPathComponent(
			"\(name)_\(version)_\(Int(Date().timeIntervalSince1970)).ipa"
		)
		try await Task.detached(priority: .utility) {
			try FileManager.default.createDirectoryIfNeeded(at: FileManager.default.archives)
			try FileManager.default.moveItem(at: package, to: destination)
		}.value

		if shouldOpen, let sharedDocumentsURL = FileManager.default.archives.toSharedDocumentsURL() {
			UIApplication.open(sharedDocumentsURL)
		}
		return destination
	}

	static func getCompressionLevel() -> Int {
		UserDefaults.standard.integer(forKey: "Feather.compressionLevel")
	}
}
