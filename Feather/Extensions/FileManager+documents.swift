//
//  FileManager+documents.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import Foundation.NSFileManager

extension FileManager {
	/// Gives apps Signed directory
	var archives: URL {
		URL.documentsDirectory.appendingPathComponent("Archives")
	}
	
	/// Gives apps Signed directory
	var signed: URL {
		URL.documentsDirectory.appendingPathComponent("Signed")
	}
	
	/// Gives apps Signed directory with a UUID appending path
	func signed(_ uuid: String) -> URL {
		signed.appendingPathComponent(uuid)
	}
	
	/// Gives apps Unsigned directory
	var unsigned: URL {
		URL.documentsDirectory.appendingPathComponent("Unsigned")
	}
	
	/// Gives apps Unsigned directory with a UUID appending path
	func unsigned(_ uuid: String) -> URL {
		unsigned.appendingPathComponent(uuid)
	}
	
	/// Certificates live outside `Documents/` on purpose: that directory is
	/// user-visible (the app enables file sharing) and is included in backups.
	/// The `.p12` holds a signing private key, so it belongs in the app's
	/// private container; see `ODCertificateFiles`.
	var certificates: URL {
		URL.applicationSupportDirectory
			.appendingPathComponent("Odysseus", isDirectory: true)
			.appendingPathComponent(ODCertificateFiles.directoryName, isDirectory: true)
	}

	/// Pre-migration location. Only used to move material into `certificates`.
	var legacyCertificates: URL {
		URL.documentsDirectory.appendingPathComponent(ODCertificateFiles.directoryName, isDirectory: true)
	}

	/// Gives apps Certificates directory with a UUID appending path
	func certificates(_ uuid: String) -> URL {
		certificates.appendingPathComponent(uuid)
	}
}
