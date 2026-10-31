//
//  ODImportTracking.swift
//  Odysseus
//
//  Tracks the download → import hand-off for "Get".
//
//  The pipeline used to remove the download id from `_pendingGets` as soon
//  as the 3-second post-download timer fired. If the import was slower than
//  that (a large IPA, a busy device), the import notification was discarded:
//  the app landed in the Library, the user saw "Download failed", and the
//  app was never signed.
//
//  This type keeps a short, bounded recovery window so a late import is
//  still recognised. Pure value semantics, so the transitions are testable.
//

import Foundation

struct ODImportTracking {
	enum Outcome: Equatable {
		/// No download is being tracked for this id; ignore the notification.
		case ignored
		/// This import belongs to a "Get" the user asked for; sign it.
		case signing
	}

	/// Ids whose download is running, or whose import is expected.
	private var _active: Set<String> = []
	/// Ids whose download stopped without an import. Kept in insertion order
	/// so the oldest can be dropped when the window fills up.
	private var _recoverable: [String] = []

	static let recoverableLimit = 32

	/// A "Get" started.
	mutating func begin(_ id: String) {
		_active.insert(id)
		_recoverable.removeAll { $0 == id }
	}

	/// The user cancelled, or the request failed terminally.
	mutating func forget(_ id: String) {
		_active.remove(id)
		_recoverable.removeAll { $0 == id }
	}

	/// The download stopped and no import has arrived yet. The id stays
	/// recoverable so a late import is still signed.
	/// - Returns: `true` when this id was actually being tracked.
	@discardableResult
	mutating func downloadStopped(_ id: String) -> Bool {
		guard _active.remove(id) != nil else { return false }
		_remember(id)
		return true
	}

	/// An import completed for this download id.
	mutating func imported(_ id: String) -> Outcome {
		if _active.remove(id) != nil {
			return .signing
		}
		if let index = _recoverable.firstIndex(of: id) {
			_recoverable.remove(at: index)
			return .signing
		}
		return .ignored
	}

	func isTracking(_ id: String) -> Bool {
		_active.contains(id) || _recoverable.contains(id)
	}

	var isTrackingAnything: Bool {
		!_active.isEmpty
	}

	private mutating func _remember(_ id: String) {
		_recoverable.removeAll { $0 == id }
		_recoverable.append(id)
		if _recoverable.count > Self.recoverableLimit {
			_recoverable.removeFirst(_recoverable.count - Self.recoverableLimit)
		}
	}
}
