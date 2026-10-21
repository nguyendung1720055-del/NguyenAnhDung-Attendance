[CmdletBinding()]
param(
    [string]$ListenUrl = 'http://localhost:5080'
)

$ErrorActionPreference = 'Stop'
$envPath = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path -LiteralPath $envPath)) {
    throw 'Missing infra/.env. Run Initialize-Development.ps1 first.'
}
$workspaceRoot = Split-Path $PSScriptRoot -Parent
$dotnetExecutable = 'dotnet'
$toolOverrides = @{}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    $localDotnet = Join-Path $workspaceRoot '.tools/dotnet/dotnet.exe'
    if (-not (Test-Path -LiteralPath $localDotnet -PathType Leaf)) {
        throw '.NET 10 SDK was not found on PATH or at .tools/dotnet/dotnet.exe.'
    }
    $dotnetExecutable = $localDotnet
    $toolOverrides = @{
        'DOTNET_ROOT' = (Split-Path $localDotnet -Parent)
        'DOTNET_CLI_HOME' = (Join-Path $workspaceRoot '.tools/dotnet-home')
        'NUGET_PACKAGES' = (Join-Path $workspaceRoot '.tools/nuget')
    }
}

# Read plain KEY=value settings; never execute file contents as PowerShell.
$settings = @{}
foreach ($line in [System.IO.File]::ReadAllLines($envPath)) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    $separator = $trimmed.IndexOf('=')
    if ($separator -lt 1) { throw 'Invalid line in infra/.env: expected KEY=value.' }
    $key = $trimmed.Substring(0, $separator).Trim()
    $value = $trimmed.Substring($separator + 1).Trim()
    if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    $settings[$key] = $value
}
foreach ($key in @('SQL_SA_PASSWORD', 'JWT_KEY')) {
    if (-not $settings[$key]) { throw "Set $key in infra/.env first." }
}

$connection = New-Object System.Data.Common.DbConnectionStringBuilder
$connection['Server'] = 'tcp:127.0.0.1,1433'
$connection['Database'] = 'NguyenAnhDungAttendance'
$connection['User Id'] = 'sa'
$connection['Password'] = $settings['SQL_SA_PASSWORD']
$connection['Encrypt'] = $true
$connection['TrustServerCertificate'] = $true

$config = @{
    'ASPNETCORE_ENVIRONMENT' = 'Development'
    'ConnectionStrings__DefaultConnection' = $connection.ConnectionString
    'Database__Initialize' = 'true'
    'Jwt__Key' = $settings['JWT_KEY']
}
foreach ($key in $toolOverrides.Keys) { $config[$key] = $toolOverrides[$key] }
$mapping = @{
    'BootstrapAdmin__Enabled' = 'BOOTSTRAP_ADMIN_ENABLED'
    'BootstrapAdmin__Username' = 'BOOTSTRAP_ADMIN_USERNAME'
    'BootstrapAdmin__Email' = 'BOOTSTRAP_ADMIN_EMAIL'
    'BootstrapAdmin__Password' = 'BOOTSTRAP_ADMIN_PASSWORD'
    'BootstrapAdmin__FullName' = 'BOOTSTRAP_ADMIN_FULLNAME'
    'Email__DeliveryMethod' = 'EMAIL_DELIVERY_METHOD'
    'Email__Host' = 'EMAIL_HOST'
    'Email__Port' = 'EMAIL_PORT'
    'Email__Username' = 'EMAIL_USERNAME'
    'Email__Password' = 'EMAIL_PASSWORD'
    'Email__FromAddress' = 'EMAIL_FROM_ADDRESS'
    'Email__UseSsl' = 'EMAIL_USE_SSL'
}
foreach ($key in $mapping.Keys) { $config[$key] = [string]$settings[$mapping[$key]] }
$previous = @{}
try {
    foreach ($key in $config.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $config[$key], 'Process')
    }
    $project = Join-Path $workspaceRoot 'NguyenAnhDung.Attendance.Api/NguyenAnhDung.Attendance.Api.csproj'
    & $dotnetExecutable run --project $project --no-launch-profile -- --urls $ListenUrl
    if ($LASTEXITCODE -ne 0) { throw "dotnet run exited with code $LASTEXITCODE." }
}
finally {
    foreach ($key in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process')
    }
}
