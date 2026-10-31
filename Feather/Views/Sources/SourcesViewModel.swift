//
//  SourcesViewModel.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import Foundation
import AltSourceKit
import SwiftUI
import NimbleJSON
import NimbleExtensions

private struct SourceFetchRequest: Sendable {
	let objectIDURI: String
	let url: URL?
}

// FetchedResults and AltSource objects stay on the main/viewContext queue.
@MainActor
final class SourcesViewModel: ObservableObject {
	static let shared = SourcesViewModel()

	typealias RepositoryDataHandler = Result<ASRepository, Error>

	var isFinished = true
	@Published var sources: [AltSource: ASRepository] = [:]

	func fetchSources(_ sources: FetchedResults<AltSource>, refresh: Bool = false, batchSize: Int = 4) async {
		await fetchSources(Array(sources), refresh: refresh, batchSize: batchSize)
	}

	func fetchSources(_ sources: [AltSource], refresh: Bool = false, batchSize: Int = 4) async {
		guard isFinished else { return }
		if !refresh, sources.allSatisfy({ self.sources[$0] != nil }) { return }

		isFinished = false
		defer { isFinished = true }

		let sourceByID: [String: AltSource] = Dictionary(
			uniqueKeysWithValues: sources.map { ($0.objectID.uriRepresentation().absoluteString, $0) }
		)
		let requests = sources.map { source in
			SourceFetchRequest(
				objectIDURI: source.objectID.uriRepresentation().absoluteString,
				url: source.sourceURL
			)
		}
		let wantedObjectIDs = Set(sources.map(\.objectID))
		self.sources = self.sources.filter { wantedObjectIDs.contains($0.key.objectID) }

		for startIndex in stride(from: 0, to: requests.count, by: max(1, batchSize)) {
			let endIndex = min(startIndex + max(1, batchSize), requests.count)
			let batch = Array(requests[startIndex..<endIndex])
			let batchResults = await withTaskGroup(
				of: (objectIDURI: String, repository: ASRepository?, didFail: Bool).self,
				returning: (repositories: [String: ASRepository], failures: [String]).self
			) { group in
				for request in batch {
					group.addTask {
						guard let url = request.url else {
							return (request.objectIDURI, nil, true)
						}

					return await withCheckedContinuation { continuation in
						NBFetchService().fetch(from: url) { (result: RepositoryDataHandler) in
							switch result {
							case .success(let repository):
								continuation.resume(returning: (request.objectIDURI, repository, false))
							case .failure:
								continuation.resume(returning: (request.objectIDURI, nil, true))
							}
						}
					}
				}

				var repositories: [String: ASRepository] = [:]
				var failures: [String] = []
				for await (objectIDURI, repository, didFail) in group {
					if let repository {
						repositories[objectIDURI] = repository
					} else if didFail {
						failures.append(objectIDURI)
					}
				}
				return (repositories, failures)
			}

			for (objectIDURI, repository) in batchResults.repositories {
				guard let source = sourceByID[objectIDURI] else { continue }
				self.sources[source] = repository
				source.name = repository.name ?? source.name
				source.iconURL = repository.currentIconURL ?? source.iconURL
			}

			Storage.shared.saveContext()
			UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: ODPrefs.sourcesLastRefresh)
			let failedSources = batchResults.failures.compactMap { sourceByID[$0] }
			_showFetchFailureToast(for: failedSources)
		}
	}

	@MainActor
	private func _showFetchFailureToast(for failures: [AltSource]) {
		guard !failures.isEmpty else { return }

		if failures.count == 1 {
			let source = failures[0]
			let name = source.name ?? source.sourceURL?.host ?? .localized("source")
			SourceFetchErrorToastCenter.shared.show(.localized("Couldn't refresh %@", arguments: name))
		} else {
			SourceFetchErrorToastCenter.shared.show(.localized("%d sources couldn't refresh", arguments: failures.count))
		}
	}
}
