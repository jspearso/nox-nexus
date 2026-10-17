#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
Installs the pinned NOX-connected BetterDesk MSI for 897FM workstations.
.DESCRIPTION
Run elevated on Windows x64 or ARM64. Installs an automatic LocalSystem service,
sets a per-device permanent password, and applies signed incoming-only settings.
No BetterDesk administrator credential or password is embedded in this script.
The native MSI retains its BetterDesk Client product/service name so installation,
IPC and settings paths agree; appearance comes from the NOX Client Branding API.

After installation an administrator must approve the device in NOX Nexus and add
it to device group 897FM. User-group visibility does not enforce a per-connection
operator ACL. Store each peer password in your controlled password vault.
.PARAMETER UnattendedPassword
A SecureString from Read-Host -AsSecureString or your deployment secret provider.
Use a different strong password for each workstation. Never hard-code it here.
.EXAMPLE
$password = Read-Host 'This PC unattended password' -AsSecureString
.\Install-NoxNexus897FM.ps1 -UnattendedPassword $password
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [Security.SecureString] $UnattendedPassword
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$ServiceName = 'BetterDesk Client'
$NativeProgramFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$InstallDirectory = Join-Path $NativeProgramFiles 'BetterDesk Client'
$ClientExe = Join-Path $InstallDirectory 'betterdesk.exe'
$ProfilePath = Join-Path $InstallDirectory 'custom.txt'
$ServerHostName = 'nexus.noxcloud.com.au'
$ClientApi = 'https://nexus.noxcloud.com.au/client-api'
$ServerKey = 'jN1jw5VFuJTX3MzvHwDu1BzovhJ7zCH3O+qRiTLqnwM='
$SignedProfile = 'UmtW+OBeSSVeKBwcbY0XCkNiSc6GQhLXkF7TVfujWxm5QcqCrB8XtMHPrt4Zx/Y/Ii1dHwbJ7I4NagZKzVbyC3siYXBwLW5hbWUiOiJCZXR0ZXJEZXNrIENsaWVudCIsImNvbm4tdHlwZSI6ImluY29taW5nIiwiZGlzYWJsZS1zZXR0aW5ncyI6IlkiLCJvdmVycmlkZS1zZXR0aW5ncyI6eyJhcGktc2VydmVyIjoiaHR0cHM6Ly9uZXh1cy5ub3hjbG91ZC5jb20uYXUvY2xpZW50LWFwaSIsImFwcHJvdmUtbW9kZSI6InBhc3N3b3JkIiwiY3VzdG9tLXJlbmRlenZvdXMtc2VydmVyIjoibmV4dXMubm94Y2xvdWQuY29tLmF1IiwiaGlkZS1oZWxwLWNhcmRzIjoiWSIsImhpZGUtc2VydmVyLXNldHRpbmdzIjoiWSIsImtleSI6ImpOMWp3NVZGdUpUWDNNenZId0R1MUJ6b3ZoSjd6Q0gzTytxUmlUTHFud009IiwicmVsYXktc2VydmVyIjoibmV4dXMubm94Y2xvdWQuY29tLmF1OjIxMTE3IiwidmVyaWZpY2F0aW9uLW1ldGhvZCI6InVzZS1wZXJtYW5lbnQtcGFzc3dvcmQifX0='
$ReleaseBase = 'https://github.com/jspearso/nox-nexus-client/releases/download/desktop/nox-nexus-1.5.0-1'
$Packages = @{
    AMD64 = @{ Name = 'betterdesk-1.5.0-x86_64.msi'; Sha256 = 'f8f772d49e6c02c930d0c2f67d952b9d41f913a703bf7aec8adf9ca136040ad9' }
    ARM64 = @{ Name = 'betterdesk-1.5.0-aarch64.msi'; Sha256 = '30026cf46cd7ba0e903057199603d7a755864c047503d1c82bb4488196380972' }
}
$NativeArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
if (-not $Packages.ContainsKey($NativeArchitecture)) { throw 'Windows x64 or ARM64 is required.' }
$Package = $Packages[$NativeArchitecture]
if ($UnattendedPassword.Length -lt 16) { throw 'Use an unattended password with at least 16 characters.' }

function Set-PrivateDirectoryAcl([string] $Path) {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sidText in @('S-1-5-18', 'S-1-5-32-544')) {
        $sid = New-Object Security.Principal.SecurityIdentifier($sidText)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}
function Quote-NativeArgument([string] $Value) {
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
function Invoke-Client([string[]] $ClientArguments) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $ClientExe
    $info.Arguments = ($ClientArguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void] $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill()
            throw 'Client provisioning command timed out.'
        }
        $output = $stdout.GetAwaiter().GetResult().Trim()
        [void] $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw 'Client provisioning command failed.' }
        return $output
    } finally { $process.Dispose() }
}
function Stop-Client {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    }
    # Reload the signed profile in existing processes as well as the service.
    Get-CimInstance Win32_Process -Filter "Name='betterdesk.exe'" |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath.Equals($ClientExe, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
function Disable-RemotePrinterAdapter {
    $adapter = Join-Path $InstallDirectory 'printer_driver_adapter.dll'
    if (Test-Path -LiteralPath $adapter) {
        $backup = $adapter + '.nox-disabled'
        if (Test-Path -LiteralPath $backup) { $backup += '-' + [guid]::NewGuid().ToString('N') }
        Move-Item -LiteralPath $adapter -Destination $backup
        Write-Output 'Remote printing disabled to avoid the native printer-adapter startup crash.'
    }
}
function Start-ClientService {
    Set-Service -Name $ServiceName -StartupType Automatic
    Start-Service -Name $ServiceName
    (Get-Service -Name $ServiceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
}
function Write-LockedProfile {
    [IO.File]::WriteAllText($ProfilePath, $SignedProfile + "`n", (New-Object Text.UTF8Encoding($false)))
}

if (Test-Path -LiteralPath $ProfilePath) {
    if ([IO.File]::ReadAllText($ProfilePath).Trim() -cne $SignedProfile) {
        throw 'An unmanaged custom.txt already exists. Review the existing installation before migration.'
    }
}
$WorkRoot = Join-Path $env:ProgramData 'NOX Nexus Deployment'
[void] (New-Item -Path $WorkRoot -ItemType Directory -Force)
Set-PrivateDirectoryAcl $WorkRoot
$WorkDirectory = Join-Path $WorkRoot ([guid]::NewGuid().ToString('N'))
[void] (New-Item -Path $WorkDirectory -ItemType Directory)
$MsiPath = Join-Path $WorkDirectory $Package.Name
$MsiLog = Join-Path $WorkRoot ('msi-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
$MustRestoreProfile = $false
$MsiExitCode = 0
try {
    Write-Output 'Downloading the pinned BetterDesk MSI...'
    Invoke-WebRequest -UseBasicParsing -Uri ($ReleaseBase + '/' + $Package.Name) -OutFile $MsiPath
    if ((Get-FileHash -LiteralPath $MsiPath -Algorithm SHA256).Hash -ine $Package.Sha256) {
        throw 'MSI SHA-256 verification failed. Installation cancelled.'
    }
    # Re-runs temporarily unlock CLI provisioning; final settings are restored even on failure.
    if (Test-Path -LiteralPath $ProfilePath) {
        Stop-Client
        $MustRestoreProfile = $true
        Remove-Item -LiteralPath $ProfilePath -Force
    }
    $MsiExec = Join-Path $env:WINDIR 'System32\msiexec.exe'
    if ($env:PROCESSOR_ARCHITEW6432) { $MsiExec = Join-Path $env:WINDIR 'Sysnative\msiexec.exe' }
    $MsiArguments = '/i "{0}" /qn /norestart ALLUSERS=1 STOP_SERVICE=N LAUNCH_TRAY_APP=N LAUNCH_MAIN_APP=N INSTALLFOLDER="{1}" /L*v "{2}"' -f $MsiPath, $InstallDirectory, $MsiLog
    $installer = Start-Process -FilePath $MsiExec -ArgumentList $MsiArguments -PassThru -Wait
    $MsiExitCode = $installer.ExitCode
    if ($MsiExitCode -notin @(0, 3010)) { throw "MSI installation failed with exit code $MsiExitCode. See $MsiLog" }
    if (-not (Test-Path -LiteralPath $ClientExe)) { throw 'MSI did not install the expected client executable.' }
    $MustRestoreProfile = $true
    Stop-Client
    Disable-RemotePrinterAdapter
    Start-ClientService
    $serviceInfo = Get-CimInstance Win32_Service -Filter "Name='BetterDesk Client'"
    if ($serviceInfo.StartName -ne 'LocalSystem') { throw 'Expected a LocalSystem service for access at the Windows sign-in screen.' }
    if ($serviceInfo.PathName -notmatch ('^\s*"?' + [regex]::Escape($ClientExe) + '"?\s+--service(?:\s|$)')) {
        throw 'Service executable differs from the expected MSI installation.'
    }
    $configuration = @{ host = $ServerHostName; relay = ($ServerHostName + ':21117'); api = $ClientApi; key = $ServerKey } | ConvertTo-Json -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($configuration)).TrimEnd('=')
    $characters = $encoded.ToCharArray()
    [Array]::Reverse($characters)
    [void] (Invoke-Client -ClientArguments @('--config', (-join $characters)))
    foreach ($setting in @(@('custom-rendezvous-server', $ServerHostName), @('relay-server', ($ServerHostName + ':21117')), @('api-server', $ClientApi), @('key', $ServerKey))) {
        if ((Invoke-Client -ClientArguments @('--option', $setting[0])) -cne $setting[1]) { throw "Client configuration verification failed for $($setting[0])." }
    }
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($UnattendedPassword)
    try {
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        $passwordResult = Invoke-Client -ClientArguments @('--password', $plainPassword)
        if ($passwordResult -notmatch '(?m)^Done!\s*$') { throw 'The client did not confirm setting its permanent password.' }
    } finally {
        $plainPassword = $null
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
    [void] (Invoke-Client -ClientArguments @('--option', 'approve-mode', 'password'))
    [void] (Invoke-Client -ClientArguments @('--option', 'verification-method', 'use-permanent-password'))
    foreach ($setting in @(@('approve-mode', 'password'), @('verification-method', 'use-permanent-password'))) {
        if ((Invoke-Client -ClientArguments @('--option', $setting[0])) -cne $setting[1]) { throw 'Unattended access settings were not applied.' }
    }
    Stop-Client
    Write-LockedProfile
    Start-ClientService
    $deviceId = Invoke-Client -ClientArguments @('--get-id')
    if ($deviceId -notmatch '^\d+$') { throw 'Unable to read the installed device ID.' }
    $receipt = [ordered]@{ ComputerName = $env:COMPUTERNAME; DeviceId = $deviceId; ExpectedDeviceGroup = '897FM'; RequiresAdministratorApprovalAndGroupAssignment = $true; RebootRequired = ($MsiExitCode -eq 3010) }
    $receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkRoot 'deployment.json') -Encoding UTF8
    [pscustomobject] $receipt
    Write-Output 'Approve this device and assign it to 897FM at https://nexus.noxcloud.com.au . Keep its peer password in your controlled vault.'
} finally {
    if ($MustRestoreProfile -and (Test-Path -LiteralPath $ClientExe)) {
        Write-LockedProfile
        Start-ClientService
    }
    if (Test-Path -LiteralPath $WorkDirectory) { Remove-Item -LiteralPath $WorkDirectory -Recurse -Force }
}
if ($MsiExitCode -eq 3010) { exit 3010 }
