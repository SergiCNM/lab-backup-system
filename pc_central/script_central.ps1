param (
    [string]$ConfigFile = "C:\BackupCentral\config_central.json",
    [switch]$TestMode  # If active, window will remain open
)

# -----------------------------
# Load configuration
# -----------------------------
$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$pcName = $config.pcName
$networkPath = $config.networkBackupPath   # \\FITXERS3\...\_BACKUPS
$localMirror = $config.localMirrorPath    # Local mirror (external disk)
$logPath = $config.logPath
$pcsToCopy = $config.pcsToCopy
$folders = $config.folders
$deleteAfterCopy = $config.deleteAfterCopy -eq $true

# -----------------------------
# Prepare log folder
# -----------------------------
$logDir = Split-Path $logPath
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# Daily log file including pcName
$date = Get-Date -Format "yyyyMMdd_HHmm"
$logFile = Join-Path $logDir ("central_log_${pcName}_$date.txt")

# -----------------------------
# Logging function
# -----------------------------
function Write-Log {
    param([string]$msg)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$time - $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

# -----------------------------
# Start backup
# -----------------------------
Write-Log "===== CENTRAL BACKUP STARTED ($pcName) ====="

# Create local mirror folder if not exists
if (!(Test-Path $localMirror)) { New-Item -ItemType Directory -Path $localMirror -Force | Out-Null }

# -----------------------------
# 1. Copy PCs from network
# -----------------------------
if ($pcsToCopy -and $pcsToCopy.Count -gt 0) {
    Write-Log "Starting backup of lab PCs: $($pcsToCopy -join ', ')"

    foreach ($pc in $pcsToCopy) {
        $source = Join-Path $networkPath $pc
        $dest = Join-Path $localMirror $pc

        if (!(Test-Path $source)) {
            Write-Log "WARNING: Source folder for $pc not found: $source"
            continue
        }

        Write-Log "Syncing $source -> $dest (mirror)"
        robocopy $source $dest /MIR /Z /R:2 /W:5 /MT:16 /FFT /NP /NDL /NFL /TEE /LOG:$logFile

        Write-Log "Finished syncing $pc"

        if ($deleteAfterCopy) {
            Write-Log "Deleting source backup of $pc"
            $empty = Join-Path $env:TEMP "empty_folder"
            if (!(Test-Path $empty)) { New-Item -ItemType Directory -Path $empty | Out-Null }
            robocopy $empty $source /MIR /R:1 /W:1 /NFL /NDL /NP
            Write-Log "Source backup $pc deleted"
        }
    }
} else {
    Write-Log "No PCs listed in pcsToCopy. Skipping network backup."
}

# -----------------------------
# 2. Copy local folders of central PC
# -----------------------------
if ($folders -and $folders.Count -gt 0) {
    Write-Log "Starting backup of local folders for central PC: $pcName"

    foreach ($folder in $folders) {
        $source = $folder.source
        $dest = Join-Path $localMirror $folder.name

        if (!(Test-Path $source)) {
            Write-Log "WARNING: Source folder not found: $source"
            continue
        }

        if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }

        Write-Log "Syncing $source -> $dest (mirror)"
        robocopy $source $dest /MIR /Z /R:2 /W:5 /MT:16 /FFT /NP /NDL /NFL /TEE /LOG:$logFile

        Write-Log "Finished syncing folder: $($folder.name)"
    }
} else {
    Write-Log "No local folders defined in configuration. Skipping central PC backup."
}

# -----------------------------
# Finish
# -----------------------------
Write-Log "===== CENTRAL BACKUP FINISHED ($pcName) ====="

if ($TestMode) {
    Write-Host ""
    Write-Host "TEST MODE: Window will remain open." -ForegroundColor Yellow
} else {
    Start-Sleep -Seconds 5
    exit
}
