[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.]{3,40}$')]
    [string]$AdminUsername,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[^\s@]+@[^\s@]+\.[^\s@]+$')]
    [string]$AdminEmail
)

$ErrorActionPreference = 'Stop'
$envPath = Join-Path $PSScriptRoot '.env'
if (Test-Path -LiteralPath $envPath) {
    throw 'infra/.env already exists. Edit that local file; this script never overwrites secrets.'
}
if ($AdminEmail -match '[\r\n#''"$]') {
    throw 'Use a simple email address without quotes or dotenv metacharacters.'
}

function New-LocalSecret([int]$ByteCount) {
    $bytes = New-Object byte[] $ByteCount
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($bytes) } finally { $random.Dispose() }
    return ([Convert]::ToBase64String($bytes) + 'aA1!')
}

$sqlSecret = New-LocalSecret 32
$jwtSecret = New-LocalSecret 48
$adminSecret = New-LocalSecret 24
$content = @"
# Generated locally. Do not commit or share this file.
SQL_SA_PASSWORD=$sqlSecret
JWT_KEY=$jwtSecret
BOOTSTRAP_ADMIN_ENABLED=true
BOOTSTRAP_ADMIN_USERNAME=$AdminUsername
BOOTSTRAP_ADMIN_EMAIL=$AdminEmail
BOOTSTRAP_ADMIN_PASSWORD=$adminSecret
BOOTSTRAP_ADMIN_FULLNAME=Nguyen Anh Dung
EMAIL_DELIVERY_METHOD=Smtp
EMAIL_HOST=127.0.0.1
EMAIL_PORT=1025
EMAIL_USERNAME=
EMAIL_PASSWORD=
EMAIL_FROM_ADDRESS=attendance@nguyenanhdung.test
EMAIL_USE_SSL=false
"@
[System.IO.File]::WriteAllText($envPath, $content, (New-Object System.Text.UTF8Encoding $false))
Write-Host 'Created infra/.env with random SQL, JWT and admin secrets.'
Write-Host 'Open that local file to read BOOTSTRAP_ADMIN_PASSWORD for the first admin login.'
Write-Host 'Start SQL/Mailpit with Docker Compose, then run infra/Start-Api.ps1.'
