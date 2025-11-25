<h1> Dell BIOS Search </h1>
PowerShell script to look up the latest Dell BIOS packages for a list of models and remotely install them on target machines.

<h2> Table of Contents</h2>

- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Script Defintion](#script-defintion)
- [Usage](#usage)
  - [1) Refresh BIOS catalog](#1-refresh-bios-catalog)
  - [2) Push BIOS updates to hosts](#2-push-bios-updates-to-hosts)
- [Tips](#tips)


## Prerequisites
- PowerShell 7+ with internet access.
- Selenium PowerShell module: `Install-Module Selenium -Scope CurrentUser`.
- Google Chrome installed on the machine running the scripts.
- PsExec available on `PATH` (used by `execute.ps1` for remote execution).
- Admin rights to each target (`C$` share reachable) and the correct BIOS password (update the `/p="biospassword"` argument in `execute.ps1` before running).

## Setup
1) From the repo root, fetch the latest ChromeDriver (creates a `chromeDriver-<version>` folder next to `src`):
   ```pwsh
   pwsh ./src/Fetch-ChromeDriver.ps1
   ```
2) Populate `res/WSID.txt` with one hostname or IP per line for the machines you want to update.
3) Ensure `res/newModels.csv` lists the models you care about. Columns are `Model,Version,Product,URL` where `Product` is the Dell support slug (e.g., `Latitude-13-5320-2-in-1-Laptop`). You can start from the existing file or copy from `res/archivedModels.csv`.

## Script Defintion
- `src/seleniumSearch.ps1` updates `res/newModels.csv` with the latest BIOS download links/versions from Dell Support (headless Selenium).
- `src/Fetch-ChromeDriver.ps1` fetches the current stable ChromeDriver required by Selenium.
- `src/execute.ps1` copies and runs the matching BIOS executable on each host in `res/WSID.txt` and aggregates the logs.
- `res/newModels.csv` / `oldModels.csv` store the model catalog; `res/WSID.txt` is the hostname/IP list.

## Usage
### 1) Refresh BIOS catalog
Headless Selenium will look up each `Product` entry and rewrite `res/newModels.csv` with the latest `URL` and `Version`, keeping a backup in `res/oldModels.csv`:
```pwsh
pwsh ./src/seleniumSearch.ps1
```
Pass `-newModels` / `-oldModels` if you want to use different CSV paths. To quiet console output, redirect logs: `pwsh ./src/seleniumSearch.ps1 > output.log`.

### 2) Push BIOS updates to hosts
```pwsh
pwsh ./src/execute.ps1 -WSID ./res/WSID.txt -Throttle 10
```
- Resolves each hostname/IP, detects its model via `systeminfo`, matches it to `res/newModels.csv`, downloads the BIOS exe, and runs it remotely with PsExec (or locally if the host is the current machine).
- Creates/updates `Updates.log` in `src/` and also reads `update.log` from each target (`C:\temp\biosUpdates\update.log`). Increase `-Throttle` to parallelize more hosts.

## Tips
- Run on AC power and schedule maintenance windows; BIOS flashes will reboot machines.
- If Selenium cannot find a BIOS link for a model, verify the `Product` category in the CSV matches the Dell Support URL.
- Keep ChromeDriver versions in sync with your installed Chrome by re-running `Fetch-ChromeDriver.ps1` when Chrome updates.
