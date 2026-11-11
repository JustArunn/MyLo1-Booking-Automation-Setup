$ErrorActionPreference = "Stop"

$ManifestPath = Join-Path $PSScriptRoot "mylo-setup.json"
$HasManifest = Test-Path -LiteralPath $ManifestPath -PathType Leaf

if ($HasManifest) {
    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw |
        ConvertFrom-Json
}
else {
    Write-Host "No setup manifest found. Enter the existing setup details."
    $TaskName = (Read-Host "Scheduled task name to remove (blank to skip)").Trim()
    $FolderName = (Read-Host "Data folder name under C:\ [Mylo1]").Trim()
    if ([string]::IsNullOrWhiteSpace($FolderName)) {
        $FolderName = "Mylo1"
    }

    if ($FolderName -eq "." -or
        $FolderName -eq ".." -or
        $FolderName -match '[\\/:*?"<>|]' -or
        $FolderName.EndsWith(".") -or
        $FolderName.EndsWith(" ")) {
        throw "Invalid folder name. No files were removed."
    }

    $DataFolder = Join-Path "C:\" $FolderName
    $SecretsFile = Join-Path $DataFolder "secrets.json"
    $LogFile = Join-Path $DataFolder "booking.log"
    $Manifest = [pscustomobject]@{
        Version = 1
        TaskName = $TaskName
        TaskPath = "\"
        DataFolder = $DataFolder
        SecretsFile = $SecretsFile
        LogFile = $LogFile
        DataFolderCreated = $false
        SecretsFileCreated = Test-Path -LiteralPath $SecretsFile -PathType Leaf
        LogFileCreated = Test-Path -LiteralPath $LogFile -PathType Leaf
        AutomationScript = Join-Path $PSScriptRoot "Book-Shuttle.ps1"
        CleanupScript = $PSCommandPath
    }
}

if ($Manifest.Version -ne 1 -or
    ($HasManifest -and [string]::IsNullOrWhiteSpace([string]$Manifest.TaskName)) -or
    [string]::IsNullOrWhiteSpace([string]$Manifest.DataFolder) -or
    $Manifest.DataFolderCreated -isnot [bool] -or
    $Manifest.SecretsFileCreated -isnot [bool] -or
    $Manifest.LogFileCreated -isnot [bool]) {
    throw "Setup manifest is invalid or unsupported. No files were removed."
}

if (![string]::IsNullOrWhiteSpace([string]$Manifest.TaskName) -and
    [string]$Manifest.TaskName -match '[\\/:*?"<>|]') {
    throw "Manifest contains an unsafe task name. No files were removed."
}

$DataFolder = [IO.Path]::GetFullPath([string]$Manifest.DataFolder)
$DataFolderName = Split-Path -Leaf $DataFolder
$DataFolderParent = Split-Path -Parent $DataFolder

if ($DataFolderParent.TrimEnd("\") -ine "C:" -or
    $DataFolderName -match '[\\/:*?"<>|]' -or
    $DataFolderName -eq "." -or
    $DataFolderName -eq "..") {
    throw "Manifest contains an unsafe data folder path. No files were removed."
}

$ExpectedSecretsFile = Join-Path $DataFolder "secrets.json"
$ExpectedLogFile = Join-Path $DataFolder "booking.log"

if ([IO.Path]::GetFullPath([string]$Manifest.SecretsFile) -ine $ExpectedSecretsFile -or
    [IO.Path]::GetFullPath([string]$Manifest.LogFile) -ine $ExpectedLogFile -or
    [string]$Manifest.TaskPath -ine "\") {
    throw "Manifest contains unexpected file or task paths. No files were removed."
}

$AutomationScript = Join-Path $PSScriptRoot "Book-Shuttle.ps1"
$CleanupScript = $PSCommandPath
if ([IO.Path]::GetFullPath([string]$Manifest.AutomationScript) -ine
        [IO.Path]::GetFullPath($AutomationScript) -or
    [IO.Path]::GetFullPath([string]$Manifest.CleanupScript) -ine
        [IO.Path]::GetFullPath($CleanupScript)) {
    throw "Manifest script paths do not match this installation. No files were removed."
}

Write-Host "This will remove:"
if (![string]::IsNullOrWhiteSpace([string]$Manifest.TaskName)) {
    Write-Host "  Scheduled Task: $($Manifest.TaskName)"
}
if ($Manifest.SecretsFileCreated) {
    Write-Host "  Credentials: $ExpectedSecretsFile"
}
if ($Manifest.LogFileCreated) {
    Write-Host "  Log: $ExpectedLogFile"
}
if ($HasManifest) {
    Write-Host "  Setup manifest: $ManifestPath"
}
if ($Manifest.DataFolderCreated) {
    Write-Host "  Data folder (only if empty): $DataFolder"
}
Write-Host "  Automation script: $AutomationScript"
Write-Host "  Cleanup script: $CleanupScript"

$Confirmation = Read-Host "Type DELETE to confirm"
if ($Confirmation -cne "DELETE") {
    Write-Host "Cleanup cancelled. No files were removed."
    return
}

$Task = $null
if (![string]::IsNullOrWhiteSpace([string]$Manifest.TaskName)) {
    $Task = Get-ScheduledTask `
        -TaskName ([string]$Manifest.TaskName) `
        -TaskPath "\" `
        -ErrorAction SilentlyContinue
}

if ($Task) {
    if ($Task.State -eq "Running") {
        Stop-ScheduledTask `
            -TaskName ([string]$Manifest.TaskName) `
            -TaskPath "\"
    }

    Unregister-ScheduledTask `
        -TaskName ([string]$Manifest.TaskName) `
        -TaskPath "\" `
        -Confirm:$false
    Write-Host "Scheduled task removed."
}
else {
    if (![string]::IsNullOrWhiteSpace([string]$Manifest.TaskName)) {
        Write-Host "Scheduled task was not present."
    }
}

if ($Manifest.SecretsFileCreated -and
    (Test-Path -LiteralPath $ExpectedSecretsFile -PathType Leaf)) {
    Remove-Item -LiteralPath $ExpectedSecretsFile
    Write-Host "Generated credentials file removed."
}

if ($Manifest.LogFileCreated -and
    (Test-Path -LiteralPath $ExpectedLogFile -PathType Leaf)) {
    Remove-Item -LiteralPath $ExpectedLogFile
    Write-Host "Generated log file removed."
}

if ($Manifest.DataFolderCreated -and
    (Test-Path -LiteralPath $DataFolder -PathType Container)) {
    $RemainingItems = @(Get-ChildItem -LiteralPath $DataFolder -Force)
    if ($RemainingItems.Count -eq 0) {
        Remove-Item -LiteralPath $DataFolder
        Write-Host "Empty data folder removed."
    }
    else {
        Write-Host "Data folder retained because it contains other files."
    }
}

if (Test-Path -LiteralPath $AutomationScript -PathType Leaf) {
    Remove-Item -LiteralPath $AutomationScript
}
if ($HasManifest) {
    Remove-Item -LiteralPath $ManifestPath
}
Remove-Item -LiteralPath $CleanupScript
Write-Host "Automation and cleanup scripts removed. Cleanup complete."
