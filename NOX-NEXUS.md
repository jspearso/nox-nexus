# NOX Nexus

NOX Cloud remote access: connecting people and devices.

Based on BetterDesk development 3.5.160 (upstream commit 8b79e6a3489c009086f5811887e780aedff72a0b), retaining its AGPL-3.0 license,
copyright notices, and access to corresponding source. The console uses NOX Nexus
identity, a violet and charcoal palette, an N connection mark, and NOX Cloud copy.
Standard RustDesk desktop clients remain compatible. BetterDesk's Tauri clients
are upstream alpha software and are not represented as production-ready clients.

Coolify runs the combined Go server and Node.js console with isolated persistent
volumes for server keys/device data and console accounts/configuration. HTTPS is
terminated at the Coolify proxy. Signal 21116 TCP/UDP, NAT test 21115 TCP, and relay
21117 TCP are published directly. WebSocket endpoints and the client HTTP API stay
inside the Docker network and are exposed only through HTTPS reverse proxy routes.
Managed enrollment requires approval of new devices.

Administrative credentials and session secrets are generated at deployment and
stored in Coolify, never in this repository. Back up both persistent volumes;
preserving the server key is essential when migrating to another host.

## Live service

Console: https://nexus.noxcloud.com.au

Client API: https://nexus.noxcloud.com.au/client-api

The client API path routes directly to the Go service, including BetterDesk
branding, telemetry and enrollment endpoints. It remains separate from the web
console API on the same hostname.

RustDesk client ID server: `nexus.noxcloud.com.au`. Relay server:
`nexus.noxcloud.com.au:21117`. Set the public key provided in the console.
The existing server identity and persistent volumes are retained.

## Generator deployment

The retired 3.5.4 Go/Tauri generator is replaced by the current Support Generator.
`AGENT_BUILD_WORKER=on` and `BETTERDESK_CLIENT_GENERATOR_MODE=legacy-custom-txt`
enable the upstream template packaging worker in the all-in-one container.
The desktop templates are built from `jspearso/nox-nexus-client` with this
instance's public signing key and pinned to `desktop/nox-nexus-1.5.0-1`.
The private signing seed stays in the persistent console volume. Generated
archives contain a signed incoming-only configuration and platform installation
helpers. This mode offers portable archives for Windows, Linux, and macOS;
retired package formats must not remain in the active queue.

Both SQLite databases and the server identity were backed up in the private
`/app/data/pre-generator-upgrade` directory before upgrading. Enrollment remains
managed; approving a connecting device is separate from generating an installer.
