# NOX Nexus

NOX Cloud remote access: connecting people and devices.

Based on BetterDesk stable 3.5.4 (upstream main), retaining its AGPL-3.0 license,
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

Console and RustDesk client API: https://nexus.noxcloud.com.au

RustDesk client ID server: `nexus.noxcloud.com.au`. Relay server:
`nexus.noxcloud.com.au:21117`. Set the public key provided in the console.
The existing server identity and persistent volumes are retained.
