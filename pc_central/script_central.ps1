param (
    [string]$ConfigFile = "C:\BackupCentral\config_central.json",
    [switch]$TestMode
)

# -----------------------------
# Load configuration
# -----------------------------
$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$networkPath    = $config.networkSource
$localMirror    = $config.localDestination
$logPath        = $config.logPath
$pcsToCopy      = $config.pcsToCopy
$deleteAfterCopy= $config.deleteAfterCopy

# Prepare log folder
if (!(Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }

# Daily log file for central script
$date = Get-Date -Format "yyyyMMdd_HHmm"
$centralLog = Join-Path $logPath ("central_log_$date.txt")

function Write-Log {
    param([string]$msg)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$time - $msg"
    Write-Host $line
    Add-Content -Path $centralLog -Value $line -Encoding UTF8
}

# -----------------------------
# Helper functions
# -----------------------------
function Get-LastLabBackupDate($pcFolder) {
    $logs = Get-ChildItem $pcFolder -Filter "backup_log_*.txt" -File | Sort-Object LastWriteTime -Descending
    if ($logs.Count -eq 0) { return $null }
    # Extract date from log name: backup_log_PC471_20260218_1430.txt
    $match = [regex]::Match($logs[0].Name, "\d{8}_\d{4}")
    if ($match.Success) { return [datetime]::ParseExact($match.Value, "yyyyMMdd_HHmm", $null) }
    return $null
}

function Get-LastCentralCopyDate($localPcFolder) {
    $file = Join-Path $localPcFolder "last_copy.txt"
    if (!(Test-Path $file)) { return $null }
    return Get-Content $file | ForEach-Object { [datetime]$_ }
}

function Save-LastCentralCopyDate($localPcFolder, $date) {
    if (!(Test-Path $localPcFolder)) { New-Item -ItemType Directory -Path $localPcFolder -Force | Out-Null }
    $file = Join-Path $localPcFolder "last_copy.txt"
    $date.ToString("yyyy-MM-dd HH:mm:ss") | Set-Content $file
}

function UltraFastDelete($folder) {
    $empty = Join-Path $env:TEMP "empty_folder"
    if (!(Test-Path $empty)) { New-Item -ItemType Directory -Path $empty | Out-Null }
    robocopy $empty $folder /MIR /R:1 /W:1 /NFL /NDL /NP | Out-Null
    Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
}

# -----------------------------
# Start backup
# -----------------------------
Write-Log "===== CENTRAL BACKUP STARTED ====="

if (!(Test-Path $networkPath)) {
    Write-Log "ERROR: Cannot access network backup path: $networkPath"
    if (-not $TestMode) { exit 1 }
}

if (!(Test-Path $localMirror)) { New-Item -ItemType Directory -Path $localMirror -Force | Out-Null }

# Iterate only selected PCs
$pcFolders = Get-ChildItem -Path $networkPath -Directory | Where-Object { $pcsToCopy -contains $_.Name }

foreach ($pc in $pcFolders) {
    $source = $pc.FullName
    $dest   = Join-Path $localMirror $pc.Name

    $lastLabDate     = Get-LastLabBackupDate $source
    $lastCentralDate = Get-LastCentralCopyDate $dest

    if ($lastLabDate -eq $null) {
        Write-Log "No lab backup logs found for $($pc.Name). Skipping."
        continue
    }

    if ($lastCentralDate -ne $null -and $lastLabDate -le $lastCentralDate) {
        Write-Log "$($pc.Name) is up-to-date. Skipping."
        continue
    }

    Write-Log "Syncing $source -> $dest (mirror)"
    robocopy $source $dest /MIR /Z /R:2 /W:5 /MT:16 /FFT /NP /NDL /NFL /LOG+:$centralLog

    Write-Log "Finished syncing $($pc.Name)"
    Save-LastCentralCopyDate $dest $lastLabDate

    if ($deleteAfterCopy) {
        Write-Log "Deleting lab backup $($pc.Name)"
        UltraFastDelete $source
        Write-Log "Lab backup deleted: $($pc.Name)"
    }
}

Write-Log "===== CENTRAL BACKUP FINISHED ====="

if ($TestMode) {
    Write-Host ""
    Write-Host "TEST MODE: Window will remain open." -ForegroundColor Yellow
} else {
    Start-Sleep -Seconds 5
    exit
}
