# NOX Nexus

NOX Cloud remote access: connecting people and devices.

Based on BetterDesk development 3.5.160 (upstream commit 8b79e6a3489c009086f5811887e780aedff72a0b), retaining its AGPL-3.0 license,
copyright notices, and access to corresponding source. The console uses NOX Nexus
identity, a violet and charcoal palette, an N connection mark, and NOX Cloud copy.
Standard RustDesk desktop clients remain compatible. The Support Generator uses
the current native Flutter desktop client templates. These are unsigned portable
builds, without Windows code-signing or macOS notarization.

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

The live Support download is https://nexus.noxcloud.com.au/d/nox-nexus-support.
Windows, Linux and macOS each have x64 and ARM64 portable downloads. All six
archives were downloaded and verified against their published SHA-256 hashes;
their configuration signatures, server identity, incoming-only settings and
compiled signing trust keys were checked. Linux configuration sits beside its
portable launcher, and macOS configuration is in the app's `Contents/Resources`
directory, matching the client loader.

## Windows MSI deployment for 897FM

Use `scripts/deploy/Install-NoxNexus897FM.ps1` in an elevated Windows PowerShell
session on one pilot workstation first:

```powershell
$password = Read-Host 'This PC unattended password' -AsSecureString
.\Install-NoxNexus897FM.ps1 -UnattendedPassword $password
```

The script selects the pinned x64 or ARM64 native MSI and verifies its SHA-256
before running `msiexec /qn /norestart`. It enables the automatic LocalSystem
service, configures the NOX ID/relay/API endpoints, sets the supplied permanent
password, verifies the settings through the native CLI, then installs the signed
incoming-only profile and restarts the service. MSI exit code 3010 is propagated
when Windows requests a reboot. Other installer failures stop provisioning.

The Windows MSI retains the internal product, directory and service name
`BetterDesk Client`. Its signed profile uses that same app name so its registry,
service and password configuration paths remain consistent. NOX appearance is
provided at runtime by the Client Branding API. Both MSI packages are unsigned.
An existing custom.txt from a different deployment causes the script to stop for
an explicit migration; a rerun of this deployment temporarily removes its own
profile to allow the administrator to update its password and restores it in a
finally block. The permanent password is never written into the script, MSI log,
signed profile or deployment receipt. The native password-setting CLI briefly
receives it as a process argument; run provisioning only in a trusted admin/SYSTEM
context. Supply a unique per-device secret through your password manager or
Intune/RMM secret provider. Do not embed a shared password or admin API token in a
GPO startup script.

After installation:

1. Record the reported device ID (also saved in the admin/SYSTEM-only
   `%ProgramData%\NOX Nexus Deployment\deployment.json`).
2. Approve the device in the NOX Nexus enrollment queue, matching its ID and PC.
3. Add it to **device group 897FM** under Devices. Do this centrally; the endpoint
   installer deliberately has no administrator token for group assignment.
4. Under Users, assign each authorized operator to **user group 897FM**, with the
   required connection permission. The existing user-group membership is kept.
5. Store that workstation's peer password in an access-controlled operator vault.
   Operators log into their own BetterDesk account and use the peer password for
   unattended connections. Confirm access after a PC reboot and at the Windows
   sign-in screen before expanding deployment.

The live 897FM device group is linked to user group 897FM for device visibility;
administrative roles retain their normal access. This server version does not
enforce a group-specific allowlist on each native punch/relay connection. Someone
outside the group who knows the device ID and peer password may still connect.
`LOGGED_IN_ONLY_INITIATOR=Y` can require account login globally, but does not add
per-device group enforcement. This script does not change that global setting.
See upstream `docs/setup/RUSTDESK_CLIENT_DEPLOYMENT.md` and
`docs/wiki/Fleet-and-Policies.md` for these limits. Strict group-only remote
authorization needs an additional enforced access-control mechanism.

Validation: both published MSI downloads matched their pinned hashes and MSI
container headers; the embedded Ed25519 profile signature and unattended policy
were verified; PowerShell parsing and native argument quoting passed. Windows
installation, reboot persistence and a real unattended session still require the
pilot PC test; they cannot be verified in the Linux build workspace.
