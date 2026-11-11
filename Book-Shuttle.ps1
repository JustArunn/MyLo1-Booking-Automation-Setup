
param(
    [switch]$Setup
)

# ============================================================
# MYLO1 DAILY SHUTTLE BOOKING
# Windows PowerShell 5.1+
# ============================================================

Add-Type -AssemblyName System.Net.Http

$ErrorActionPreference = "Stop"

# ---------------- CONFIGURATION ----------------

$BaseUrl = "https://shuttle.mylo1.com"

$TripId = "1"
$TripName = "T1"

$TimeZone = "India Standard Time"

# TRUE  = Testing only, no booking request.
# FALSE = Actual ticket booking.
$DryRun = $false

$Folder = "C:\Mylo1"
$SecretFile = Join-Path $Folder "secrets.json"
$LogFile = Join-Path $Folder "booking.log"
$SetupManifest = Join-Path $PSScriptRoot "mylo-setup.json"

# ---------------- LOGGING ----------------

function Write-Log {

    param([string]$Message)

    $IndiaTime = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(
        [DateTimeOffset]::UtcNow,
        $TimeZone
    )

    $Timestamp = $IndiaTime.ToString("yyyy-MM-dd HH:mm:ss")

    $Line = "$Timestamp | $Message"

    Write-Host $Line

    Add-Content -Path $LogFile -Value $Line
}

# ---------------- SETUP ----------------

function Assert-IndiaTimeZone {

    $LocalTimeZone = [TimeZoneInfo]::Local.Id

    if ($LocalTimeZone -ne $TimeZone) {
        throw "Windows time zone must be 'India Standard Time'. Current time zone: '$LocalTimeZone'."
    }
}

function Set-MyLO1Automation {

    Assert-IndiaTimeZone

    $TripName = (Read-Host "Shuttle name (for example, T1)").Trim()
    if ([string]::IsNullOrWhiteSpace($TripName)) {
        throw "Shuttle name cannot be empty."
    }

    $TripId = (Read-Host "Shuttle trip ID from MyLO1").Trim()
    if ([string]::IsNullOrWhiteSpace($TripId)) {
        throw "Shuttle trip ID cannot be empty."
    }

    $FolderName = (Read-Host "Data folder name under C:\ [Mylo1]").Trim()
    if ([string]::IsNullOrWhiteSpace($FolderName)) {
        $FolderName = "Mylo1"
    }

    if ($FolderName -eq "." -or
        $FolderName -eq ".." -or
        $FolderName -match '[\\/:*?"<>|]' -or
        $FolderName.EndsWith(".") -or
        $FolderName.EndsWith(" ")) {
        throw "Invalid folder name. Enter a single folder name under C:\ without path separators or invalid filename characters."
    }

    $script:Folder = Join-Path "C:\" $FolderName
    $script:SecretFile = Join-Path $script:Folder "secrets.json"
    $script:LogFile = Join-Path $script:Folder "booking.log"

    $TimeText = Read-Host "Daily booking time in IST (24-hour HH:mm)"
    try {
        $BookingTime = [datetime]::ParseExact(
            $TimeText,
            "HH:mm",
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }
    catch {
        throw "Invalid booking time. Enter it in 24-hour HH:mm format, for example 08:30."
    }

    $TaskName = (Read-Host "Scheduled task name [mylo]").Trim()
    if ([string]::IsNullOrWhiteSpace($TaskName)) {
        $TaskName = "mylo"
    }

    if ($TaskName -match '[\\/:*?"<>|]') {
        throw 'Invalid task name. Do not use any of these characters: \ / : * ? " < > |'
    }

    $CleanupScript = Join-Path $PSScriptRoot "Cleanup-Mylo.ps1"
    if (!(Test-Path -LiteralPath $CleanupScript -PathType Leaf)) {
        throw "Cleanup script not found: $CleanupScript"
    }

    if (Test-Path -LiteralPath $SetupManifest) {
        throw "Setup manifest already exists at $SetupManifest. Run Cleanup-Mylo.ps1 before setting up again."
    }

    $ExistingTask = Get-ScheduledTask `
        -TaskName $TaskName `
        -TaskPath "\" `
        -ErrorAction SilentlyContinue

    if ($ExistingTask) {
        throw "A scheduled task named '$TaskName' already exists. Choose another name or clean up the existing setup first."
    }

    if (Test-Path -LiteralPath $SecretFile) {
        throw "A secrets file already exists at $SecretFile. Choose another data folder to avoid overwriting it."
    }

    if (Test-Path -LiteralPath $LogFile -PathType Container) {
        throw "The log path is a folder, not a file: $LogFile"
    }

    $MobileSecure = Read-Host "MobileNo" -AsSecureString
    if ($MobileSecure.Length -eq 0) {
        throw "MobileNo cannot be empty."
    }

    $MfaSecure = Read-Host "MfaCode" -AsSecureString
    if ($MfaSecure.Length -eq 0) {
        throw "MfaCode cannot be empty."
    }

    $Secrets = @{
        MobileNo = ConvertFrom-SecureString $MobileSecure
        MfaCode = ConvertFrom-SecureString $MfaSecure
    }

    $DataFolderCreated = !(Test-Path -LiteralPath $Folder)
    $LogFileCreated = !(Test-Path -LiteralPath $LogFile)
    $PowerShellPath = Join-Path $PSHOME "powershell.exe"
    $ScriptPath = $PSCommandPath
    $Manifest = @{
        Version = 1
        TaskName = $TaskName
        TaskPath = "\"
        TripId = $TripId
        TripName = $TripName
        DataFolder = $Folder
        SecretsFile = $SecretFile
        LogFile = $LogFile
        DataFolderCreated = $DataFolderCreated
        SecretsFileCreated = $true
        LogFileCreated = $LogFileCreated
        AutomationScript = $ScriptPath
        CleanupScript = $CleanupScript
    }

    $Manifest |
        ConvertTo-Json |
        Set-Content -Path $SetupManifest -Encoding UTF8

    if ($DataFolderCreated) {
        New-Item -ItemType Directory -Path $Folder -Force |
            Out-Null
    }

    if ($LogFileCreated) {
        New-Item -ItemType File -Path $LogFile |
            Out-Null
    }

    $Secrets |
        ConvertTo-Json |
        Set-Content -Path $SecretFile -Encoding UTF8

    $Action = New-ScheduledTaskAction `
        -Execute $PowerShellPath `
        -Argument "-NoProfile -File `"$ScriptPath`""

    $FirstRun = [datetime]::Today.Add($BookingTime.TimeOfDay)
    if ($FirstRun -le [datetime]::Now) {
        $FirstRun = $FirstRun.AddDays(1)
    }

    $Trigger = New-ScheduledTaskTrigger `
        -Daily `
        -At $FirstRun

    $Principal = New-ScheduledTaskPrincipal `
        -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
        -LogonType Interactive `
        -RunLevel Limited

    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Description "Daily MyLO1 $TripName shuttle booking at $TimeText IST." |
        Out-Null

    Write-Host "Encrypted credentials saved to $SecretFile"
    Write-Host "Daily task '$TaskName' configured for $TimeText IST."
    Write-Host "The task runs as the current Windows user while that user is signed in."
}

# ---------------- DECRYPT CREDENTIALS ----------------

function Convert-SecureStringToPlainText {

    param(
        [System.Security.SecureString]$SecureString
    )

    $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $SecureString
    )

    try {

        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            $Pointer
        )

    }
    finally {

        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer)
    }
}

function Get-Credentials {

    if (!(Test-Path $SecretFile)) {
        throw "secrets.json not found. Configure credentials first."
    }

    $Secrets = Get-Content $SecretFile -Raw | ConvertFrom-Json

    $MobileSecure = ConvertTo-SecureString $Secrets.MobileNo
    $MfaSecure = ConvertTo-SecureString $Secrets.MfaCode

    $Mobile = Convert-SecureStringToPlainText $MobileSecure
    $Mfa = Convert-SecureStringToPlainText $MfaSecure

    return @{
        MobileNo = $Mobile
        MfaCode = $Mfa
    }
}

# ---------------- MULTIPART POST REQUEST ----------------

function Invoke-MyLO1Post {

    param(
        [string]$Url,
        [hashtable]$Fields,
        [string]$Token = ""
    )

    $Client = [System.Net.Http.HttpClient]::new()

    $Content = [System.Net.Http.MultipartFormDataContent]::new()

    $Request = $null
    $Response = $null

    try {

        foreach ($Key in $Fields.Keys) {

            $Value = [string]$Fields[$Key]

            $FieldContent = [System.Net.Http.StringContent]::new(
                $Value,
                [System.Text.Encoding]::UTF8
            )

            $Content.Add($FieldContent, $Key)
        }

        $Request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Post,
            $Url
        )

        $Request.Content = $Content

        [void]$Request.Headers.TryAddWithoutValidation(
            "Origin",
            "https://quickbook.mylo1.com"
        )

        [void]$Request.Headers.TryAddWithoutValidation(
            "Referer",
            "https://quickbook.mylo1.com/"
        )

        if ($Token) {

            [void]$Request.Headers.TryAddWithoutValidation(
                "Authorization",
                "token $Token"
            )
        }

        $Response = $Client.SendAsync($Request).
            GetAwaiter().GetResult()

        $ResponseText = $Response.Content.ReadAsStringAsync().
            GetAwaiter().GetResult()

        if (!$Response.IsSuccessStatusCode) {
            throw "HTTP error: $($Response.StatusCode)"
        }

        $Result = $ResponseText | ConvertFrom-Json

        if ($Result.status -ne 200) {
            throw "API error: $($Result.message)"
        }

        return $Result
    }
    finally {

        if ($Response) {
            $Response.Dispose()
        }

        if ($Request) {
            $Request.Dispose()
        }

        $Content.Dispose()
        $Client.Dispose()
    }
}

# ---------------- GET REQUEST ----------------

function Invoke-MyLO1Get {

    param(
        [string]$Url,
        [string]$Token
    )

    $Client = [System.Net.Http.HttpClient]::new()

    $Request = $null
    $Response = $null

    try {

        $Request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Get,
            $Url
        )

        [void]$Request.Headers.TryAddWithoutValidation(
            "Authorization",
            "token $Token"
        )

        [void]$Request.Headers.TryAddWithoutValidation(
            "Accept",
            "application/json"
        )

        [void]$Request.Headers.TryAddWithoutValidation(
            "Origin",
            "https://quickbook.mylo1.com"
        )

        [void]$Request.Headers.TryAddWithoutValidation(
            "Referer",
            "https://quickbook.mylo1.com/"
        )

        $Response = $Client.SendAsync($Request).
            GetAwaiter().GetResult()

        $ResponseText = $Response.Content.ReadAsStringAsync().
            GetAwaiter().GetResult()

        if (!$Response.IsSuccessStatusCode) {
            throw "HTTP error: $($Response.StatusCode)"
        }

        $Result = $ResponseText | ConvertFrom-Json

        if ($Result.status -ne 200) {
            throw "API error: $($Result.message)"
        }

        return $Result
    }
    finally {

        if ($Response) {
            $Response.Dispose()
        }

        if ($Request) {
            $Request.Dispose()
        }

        $Client.Dispose()
    }
}

# ---------------- LOGIN ----------------

function Get-AuthToken {

    param($Credentials)

    Write-Log "Performing MFA login..."

    $LoginResult = Invoke-MyLO1Post `
        -Url "$BaseUrl/accounts/v2/mfa_login" `
        -Fields @{
            username = $Credentials.MobileNo
            mfa_code = $Credentials.MfaCode
        }

    $Token = $LoginResult.data.token

    if ([string]::IsNullOrWhiteSpace($Token)) {
        throw "Authentication token not received."
    }

    Write-Log "Login successful. Token received."

    return $Token
}

# ---------------- TODAY'S DATE ----------------

function Get-BookingDate {

    $IndiaTime = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(
        [DateTimeOffset]::UtcNow,
        $TimeZone
    )

    return $IndiaTime.ToString("yyyy-MM-dd")
}

# ---------------- SHUTTLE CONFIGURATION ----------------

function Set-ShuttleConfiguration {

    if (!(Test-Path -LiteralPath $SetupManifest -PathType Leaf)) {
        return
    }

    $Manifest = Get-Content -LiteralPath $SetupManifest -Raw | ConvertFrom-Json
    $ConfiguredTripId = [string]$Manifest.TripId
    $ConfiguredTripName = [string]$Manifest.TripName

    if ([string]::IsNullOrWhiteSpace($ConfiguredTripId) -and
        [string]::IsNullOrWhiteSpace($ConfiguredTripName)) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($ConfiguredTripId) -or
        [string]::IsNullOrWhiteSpace($ConfiguredTripName)) {
        throw "Setup manifest has incomplete shuttle configuration. Run setup again."
    }

    $script:TripId = $ConfiguredTripId
    $script:TripName = $ConfiguredTripName
}

# ---------------- CHECK SERVER BOOKING STATUS ----------------

function Test-ExistingShuttleBooking {

    param(
        [string]$Token,
        [string]$BookingDate
    )

    Write-Log "Fetching actual booking status from MyLO1..."

    $Result = Invoke-MyLO1Get `
        -Url "$BaseUrl/pass_manager/v1/todays_pass" `
        -Token $Token

    $Data = $Result.data

    if ($null -eq $Data) {
        throw "Invalid todays_pass response. Booking stopped."
    }

    $Message = [string]$Data.message

    # No active rides.
    if ($Message -eq "NO ACTIVE RIDES") {

        Write-Log "MyLO1 confirms NO ACTIVE RIDES."

        return $false
    }

    # Active rides exist.
    if ($Message -eq "ACTIVE RIDES") {

        $Passes = @($Data.all_passes)

        if ($Passes.Count -eq 0) {
            throw "ACTIVE RIDES returned but all_passes is empty. Booking stopped."
        }

        foreach ($Pass in $Passes) {

            if ($null -eq $Pass) {
                throw "Invalid pass information received. Booking stopped."
            }

            # Get trip code.
            $ServerTripId = [string]$Pass.trip_code

            # Get travel date.
            $ServerDate = $null

            try {

                $ParsedDate = [datetime]::Parse(
                    [string]$Pass.pass_date,
                    [System.Globalization.CultureInfo]::InvariantCulture
                )

                $ServerDate = $ParsedDate.ToString("yyyy-MM-dd")

            }
            catch {

                throw "Unable to parse pass_date. Booking stopped."
            }

            if ([string]::IsNullOrWhiteSpace($ServerTripId) -or
                [string]::IsNullOrWhiteSpace($ServerDate)) {

                throw "Trip code or booking date missing. Booking stopped."
            }

            Write-Log "Active ride found. Trip code: $ServerTripId"
            Write-Log "Active ride date: $ServerDate"

            # Check exact trip and date.
            if ($ServerTripId -eq $TripId -and
                $ServerDate -eq $BookingDate) {

                if ($Pass.ticket_visible -eq $true) {

                    Write-Log "Active $TripName booking already exists."
                    Write-Log "Skipping duplicate booking."

                    return $true
                }

                # Do not risk another booking if the server
                # reports a matching ride but ticket is hidden.
                throw "Matching $TripName ride exists but ticket_visible is not true. Verify booking status manually."
            }
        }

        Write-Log "No active $TripName booking found for $BookingDate."

        return $false
    }

    throw "Unexpected todays_pass response: $Message"
}

# ---------------- BOOK TICKET ----------------

function Invoke-ShuttleBooking {

    param(
        [string]$Token,
        [string]$BookingDate
    )

    Write-Log "Sending $TripName booking request..."

    $Result = Invoke-MyLO1Post `
        -Url "$BaseUrl/pass_manager/v1/book_pass" `
        -Token $Token `
        -Fields @{
            trip_id = $TripId
            date = $BookingDate
        }

    $BookingMessage = [string]$Result.data

    if ($BookingMessage -notmatch "SUCCESS") {
        throw "Booking not confirmed: $BookingMessage"
    }

    Write-Log "========================================"
    Write-Log "TICKET BOOKED SUCCESSFULLY!"
    Write-Log "Trip: $TripName"
    Write-Log "Date: $BookingDate"
    Write-Log "Response: $BookingMessage"
    Write-Log "========================================"
}

# ---------------- SETUP ENTRY POINT ----------------

if ($Setup) {
    Set-MyLO1Automation
    return
}

# ---------------- MAIN ----------------

try {

    Assert-IndiaTimeZone
    Set-ShuttleConfiguration

    if (!(Test-Path $Folder)) {

        New-Item -ItemType Directory -Path $Folder -Force |
            Out-Null
    }

    Write-Log "========================================"
    Write-Log "MYLO1 AUTOMATION STARTED"
    Write-Log "========================================"

    Write-Log "Trip: $TripName"

    $BookingDate = Get-BookingDate

    Write-Log "Booking date: $BookingDate"

    # Step 1: Load credentials.
    $Credentials = Get-Credentials

    # Step 2: Authenticate.
    $Token = Get-AuthToken -Credentials $Credentials

    # Step 3: Avoid creating a duplicate active booking.
    $AlreadyBooked = Test-ExistingShuttleBooking `
        -Token $Token `
        -BookingDate $BookingDate

    if ($AlreadyBooked) {

        Write-Log "Active booking confirmed by MyLO1."
        return
    }

    # Step 4: Dry run protection.
    if ($DryRun) {

        Write-Log "DRY RUN: No booking request was sent."

        return
    }

    # Step 5: Book ticket.
    Invoke-ShuttleBooking `
        -Token $Token `
        -BookingDate $BookingDate

}
catch {

    Write-Log "ERROR: $($_.Exception.Message)"

    exit 1
}
finally {

    $Credentials = $null
    $Token = $null

    Write-Log "Automation finished."
}
