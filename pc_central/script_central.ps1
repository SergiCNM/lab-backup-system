param (
    [string]$ConfigFile = "C:\BackupCentral\config_central.json",
    [switch]$TestMode  # si está activo, no cierra la ventana
)

# -----------------------------
# Load configuration
# -----------------------------
$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$networkPath = $config.networkBackupPath   # \\FITXERS3\...\_BACKUPS
$localMirror = $config.localMirrorPath    # Disco externo F:\BACKUPS\_BACKUPS
$logPath = $config.logPath

# Prepare log folder
$logDir = Split-Path $logPath
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# Daily log file
$date = Get-Date -Format "yyyyMMdd_HHmm"
$logFile = Join-Path $logDir ("central_log_$date.txt")

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
Write-Log "===== CENTRAL BACKUP STARTED ====="

# Check network access
if (!(Test-Path $networkPath)) {
    Write-Log "ERROR: Cannot access network backup path: $networkPath"
    if (-not $TestMode) { exit 1 }
    return
}

# Create local mirror folder (external disk)
if (!(Test-Path $localMirror)) { New-Item -ItemType Directory -Path $localMirror -Force | Out-Null }

# Iterate all PC folders inside FITXERS3
$pcFolders = Get-ChildItem -Path $networkPath -Directory

foreach ($pc in $pcFolders) {
    $source = $pc.FullName
    $dest = Join-Path $localMirror $pc.Name

    Write-Log "Syncing $source -> $dest (mirror)"
    
    # Robocopy mirror
    robocopy $source $dest /MIR /Z /R:2 /W:5 /MT:16 /FFT /NP /NDL /NFL /TEE /LOG:$logFile

    Write-Log "Finished syncing $($pc.Name)"
}

Write-Log "===== CENTRAL BACKUP FINISHED ====="

if ($TestMode) {
    Write-Host ""
    Write-Host "TEST MODE: Window will remain open." -ForegroundColor Yellow
} else {
    Start-Sleep -Seconds 5
    exit
}
