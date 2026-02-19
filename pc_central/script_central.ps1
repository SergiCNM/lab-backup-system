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
if (!(Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }

# Daily log file including pcName
$date = Get-Date -Format "yyyyMMdd_HHmm"
$logFile = Join-Path $logPath ("central_log_${pcName}_$date.txt")

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
# 2. Copy local folders of central PC (with compress support)
# -----------------------------
if ($folders -and $folders.Count -gt 0) {
    Write-Log "Starting backup of local folders for central PC: $pcName"

    foreach ($folder in $folders) {
        $source = $folder.source
        $name = $folder.name
        $compress = $false

        # Backward compatibility: if compress not defined -> false
        if ($null -ne $folder.compress) {
            $compress = [bool]$folder.compress
        }

        if (!(Test-Path $source)) {
            Write-Log "WARNING: Source folder not found: $source"
            continue
        }

        if ($compress) {
            Write-Log "COMPRESS mode enabled for folder: $name"

            $zipDest = Join-Path $localMirror ($name + ".zip")
            $tempZip = Join-Path $env:TEMP ($pcName + "_" + $name + ".zip")

            # Delete old temp zip if exists
            if (Test-Path $tempZip) {
                Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            }

            try {
                Write-Log "Creating ZIP: $tempZip"

                # Use 7-Zip if available (recommended for large datasets)
                $sevenZip = "C:\Program Files\7-Zip\7z.exe"

                if (Test-Path $sevenZip) {
                    & $sevenZip a -tzip "$tempZip" "$source\*" -mx=5 | Out-Null
                } else {
                    Write-Log "7-Zip not found. Using Compress-Archive (slower)."
                    Compress-Archive -Path "$source\*" -DestinationPath $tempZip -Force
                }

                if (Test-Path $tempZip) {
                    Write-Log "Copying ZIP to mirror: $zipDest"
                    Copy-Item -Path $tempZip -Destination $zipDest -Force
                    Write-Log "Finished compressed backup: $name"
                } else {
                    Write-Log "ERROR: ZIP was not created for $name"
                }
            }
            catch {
                Write-Log "ERROR during compression of $name : $_"
            }
            finally {
                if (Test-Path $tempZip) {
                    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
                }
            }

        } else {
            # Normal mirror mode (current behavior)
            $dest = Join-Path $localMirror $name

            if (!(Test-Path $dest)) { 
                New-Item -ItemType Directory -Path $dest -Force | Out-Null 
            }

            Write-Log "MIRROR mode for folder: $name"
            Write-Log "Syncing $source -> $dest (mirror)"

            robocopy $source $dest /MIR /Z /R:2 /W:5 /MT:16 /FFT /NP /NDL /NFL /TEE /LOG:$logFile

            Write-Log "Finished syncing folder: $name"
        }
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
