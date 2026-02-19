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
$sevenZipPath = $config.sevenZipPath

# -----------------------------
# Prepare log folder
# -----------------------------
if (!(Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }

# Daily log file including pcName
$date = Get-Date -Format "yyyyMMdd_HHmm"
$logFile = Join-Path $logPath ("central_log_${pcName}_$date.txt")

# -----------------------------
# Check 7-Zip availability (if compression is used)
# -----------------------------
function Check-SevenZip {
    param(
        [array]$foldersConfig,
        [string]$sevenZipPath
    )

    # Check if any folder has compress = true
    $compressionRequired = $false

    foreach ($f in $foldersConfig) {
        if ($null -ne $f.compress -and [bool]$f.compress -eq $true) {
            $compressionRequired = $true
            break
        }
    }

    if (-not $compressionRequired) {
        Write-Log "Compression not enabled in any folder. Skipping 7-Zip check."
        return $false
    }

    # Compression is required but path not defined
    if ([string]::IsNullOrWhiteSpace($sevenZipPath)) {
        Write-Log "WARNING: Compression enabled but sevenZipPath not defined in config. Falling back to mirror mode."
        return $false
    }

    # Path defined but executable not found
    if (-not (Test-Path $sevenZipPath)) {
        Write-Log "WARNING: 7-Zip not found at: $sevenZipPath. Compression will be disabled and mirror mode will be used."
        return $false
    }

    Write-Log "7-Zip detected at: $sevenZipPath. Compression available."
    return $true
}

# -----------------------------
# Check network path availability (central PC)
# -----------------------------
function Check-Network {
    param (
        [string]$PathToCheck
    )

    if (-not (Test-Path $PathToCheck)) {
        $msg = "WARNING: Network path is not accessible: $PathToCheck. Skipping network copy."
        Write-Host $msg -ForegroundColor Yellow
        Write-Log $msg
        return $false
    } else {
        Write-Log "Network path accessible: $PathToCheck"
        return $true
    }
}

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
# Email function
# -----------------------------
function Send-BackupEmail {
    param(
        [string]$subject,
        [string]$body
    )

    # Verificar si existe la sección email y si está habilitado
    if (-not ($config.PSObject.Properties.Name -contains "email") -or -not $config.email.enabled) {
        Write-Log "Email not configured or disabled. Skipping email."
        return
    }

    try {
        $smtpParams = @{
            SmtpServer = $config.email.smtpServer
            Port       = $config.email.smtpPort
            UseSsl     = $config.email.useSsl
            From       = $config.email.from
            To         = $config.email.to
            Subject    = $subject
            Body       = $body
            BodyAsHtml = $false
        }

        if ($config.email.PSObject.Properties.Name -contains "username" -and $config.email.username -and $config.email.password) {
            $securePwd = ConvertTo-SecureString $config.email.password -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential($config.email.username, $securePwd)
            $smtpParams.Credential = $cred
        }

        Send-MailMessage @smtpParams
        Write-Log "Email sent to $($config.email.to)"
    } catch {
        Write-Log "ERROR: Could not send email. $_"
    }
}

# -----------------------------
# Start backup
# -----------------------------
Write-Log "===== CENTRAL BACKUP STARTED ($pcName) ====="

# -----------------------------
# Validate compression tool
# -----------------------------
$sevenZipAvailable = Check-SevenZip -foldersConfig $folders -sevenZipPath $sevenZipPath

# -----------------------------
# Check local mirror drive availability (CRITICAL)
# -----------------------------
$driveRoot = [System.IO.Path]::GetPathRoot($localMirror)

if (-not (Test-Path $driveRoot)) {
    $errorMsg = "CRITICAL ERROR: Backup drive not accessible: $driveRoot (localMirrorPath = $localMirror)"
    
    Write-Host $errorMsg -ForegroundColor Red
    Write-Log $errorMsg

    # Send email if configured and enabled
    if ($null -ne $config.email -and $config.email.enabled -eq $true) {
        $subject = "CRITICAL: Central Backup FAILED on $pcName"
        $body = @"
The central backup has been aborted.

Reason:
Backup destination drive is not accessible.

Configured path:
$localMirror

Drive checked:
$driveRoot

Timestamp:
$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@
        Send-BackupEmail -subject $subject -body $body
    }

    exit 1
}

# ----------------------------------------
# Create local mirror folder if not exists
# ----------------------------------------
if (!(Test-Path $localMirror)) { New-Item -ItemType Directory -Path $localMirror -Force | Out-Null }

# -----------------------------
# 1. Copy PCs from network
# -----------------------------
if ($pcsToCopy -and $pcsToCopy.Count -gt 0) {
    $networkAvailable = Check-Network -PathToCheck $networkPath
    if ($networkAvailable) {
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
        Write-Log "Network unavailable, only local mirror backups will run."
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
            if ($sevenZipPath -and (Test-Path $sevenZipPath)) {
                Write-Log "COMPRESS mode (7-Zip) enabled for folder: $name"
            } else {
                Write-Log "COMPRESS mode enabled for folder: $name (fallback: Compress-Archive)"
            }

            $zipDest = Join-Path $localMirror ($name + ".zip")
            $tempZip = Join-Path $env:TEMP ($pcName + "_" + $name + ".zip")

            # Delete old temp zip if exists
            if (Test-Path $tempZip) {
                Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            }

            try {
                Write-Log "Creating ZIP: $tempZip"
            
                # Priority 1: sevenZipPath from config
                if ($sevenZipPath -and (Test-Path $sevenZipPath)) {
                    Write-Log "Using 7-Zip from config: $sevenZipPath"
                    & $sevenZipPath a -tzip "$tempZip" "$source\*" -mx=5 | Out-Null
                }
                else {
                    Write-Log "WARNING: 7-Zip not found or not configured. Using Compress-Archive (slower fallback)."
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

$subject = "Backup finished for $pcName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$body = Get-Content $logFile -Raw
Send-BackupEmail -subject $subject -body $body

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
