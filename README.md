# MyLO1 Booking Automation

A Windows PowerShell script that schedules a daily MyLO1 T1 shuttle booking. Setup stores credentials encrypted for the current Windows user and creates a Windows Scheduled Task.

## Requirements

- Windows with Windows PowerShell 5.1 or later
- Windows time zone set to **India Standard Time**
- A MyLO1 account and network access to the MyLO1 service

## Setup

Keep `Book-Shuttle.ps1` and `Cleanup-Mylo.ps1` together. Open PowerShell in their folder and run:

```powershell
.\Book-Shuttle.ps1 -Setup
```

Setup prompts for:

1. A data folder name under `C:\` (press Enter for `C:\Mylo1`)
2. The daily booking time in 24-hour `HH:mm` format (IST)
3. A Scheduled Task name (press Enter for `mylo`)
4. Your mobile number and MFA code (entered as secure, hidden input)

Setup creates the selected data folder if needed, then saves the encrypted credentials in `secrets.json` and creates `booking.log`. It also creates `mylo-setup.json` beside the scripts so cleanup can identify the files and task associated with this setup.

The scheduled task runs as your current Windows user while that user is signed in. It starts at the next occurrence of the chosen time and repeats daily. The booking script uses the configured T1 trip and checks for an existing booking before attempting to book.

> **MFA note:** The script stores and reuses the MFA value supplied during setup. If MyLO1 requires a fresh, time-limited one-time code for each login, scheduled authentication may fail. Confirm that the account's MFA flow supports the value and login method this automation uses.

## Run manually

To run the booking flow without waiting for the scheduled time:

```powershell
.\Book-Shuttle.ps1
```

This sends real authentication and booking requests; it is not a dry run.

## Files and credential safety

- `Book-Shuttle.ps1` — setup and booking logic.
- `Cleanup-Mylo.ps1` — removes this setup after confirmation.
- `C:\Mylo1\secrets.json` — encrypted mobile number and MFA value by default. A different folder name can be selected during setup.
- `C:\Mylo1\booking.log` — booking activity, with timestamps in IST.
- `mylo-setup.json` — setup manifest beside the scripts, used by cleanup.

Credential encryption uses Windows DPAPI through PowerShell `ConvertFrom-SecureString`. The credentials can only be decrypted under the same Windows user on the same machine. Do not share `secrets.json`, the setup manifest, or logs publicly. Do not commit credentials or personal data to source control.

## Remove the setup

Run:

```powershell
.\Cleanup-Mylo.ps1
```

Review the listed items and type `DELETE` to confirm. Cleanup removes the recorded Scheduled Task, generated credentials and log files, setup manifest, and both scripts. It removes the data folder only if this setup created it and it is empty; it leaves other files in place. Cleanup also supports older setups without a manifest by prompting for the task and data-folder names.

## Important

Use this automation only with an account you control and in accordance with MyLO1's terms and booking policies. Review the script and confirm the trip configuration before scheduling it.
