## How does it work?

How Feather works is a bit complicated, with having multiple ways to install, app management, tweaks, etc. However, I'll point out how the important features work here.

To start off, we need a validly signed IPA. We can achieve this with Zsign, using a provided IPA with a `.p12` and `.mobileprovision` pair.

#### Install (Server)

- Use the locally hosted server for hosting the IPA files used for installation, including other assets such as icons.
  - On iOS 18, the fully-local mode needs a few entitlements: `Associated Domains`, `Custom Network Protocol`, `MDM Managed Associated Domains`, and `Network Extensions`.
- **Fully Local mode requires a TLS identity that you own.** Import a PEM certificate chain, its matching PEM private key, and a hostname covered by the certificate in Settings → Installation → Server. The private key is stored in protected app storage. Odysseus does not download or bundle a shared server key, and it does not disable system certificate validation. Make sure the hostname resolves to the device running the local server.
- If no valid TLS identity is configured, Fully Local mode fails with an error; it does not silently fall back to HTTP.
- Semi Local mode retains the existing arrangement: the local server serves over HTTP and a separate HTTPS plist server is used to initiate installation. This mode does not need a TLS private key inside Odysseus.
- The install is initiated with `itms-services://?action=download-manifest&url=<PLIST_URL>` and `UIApplication.open`.

For Semi Local mode, the externally hosted plist server is a middle man for the `PLIST_URL`, while the IPA and other files remain on the device. To initiate installation without the fully-local entitlements, Odysseus can open a local HTML page in a Safari web view, which redirects to the `itms-services://` URL. The current default plist server is `api.palera.in`; a custom endpoint can be set in Settings.

Since `itms-services` initiates the install automatically, no extra action is needed after the process. Odysseus monitors the streaming progress of the IPA being sent.

#### Install (Pairing)

- Establish a heartbeat with a TCP provider (the app will need this for later).
  - For it to be successful, the app needs a pairing file from [PlumeImpactor](https://github.com/khcrysalis/Impactor?tab=readme-ov-file#pairing-file) and a [VPN](https://apps.apple.com/us/app/localdevvpn/id6755608044).
- Once these are available and the connection succeeds, installation can proceed.
  - Before installing, Odysseus checks the socket routed to `10.7.0.1`.
- When preparing for installation, Odysseus establishes another connection for `AFC` using the TCP provider.
- Once the connection is established, Odysseus creates a staging directory under `/PublicStaging/` and uploads the IPA there.
- It then uses `AFC` to command `installd` to install that IPA and monitors installation progress with a callback.

The pairing method needs both a VPN and a lockdownd pairing file, which means a computer is needed for its initial setup. It does not require TLS certificates or an externally hosted server.
