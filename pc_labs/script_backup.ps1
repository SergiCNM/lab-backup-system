# Example clean PC without confirmation: .\backup_lab.ps1 -Mode clean-pc -Force
# Examble backup: .\backup_lab.ps1 -Mode backup

param (
    [string]$ConfigFile = ".\config_lab.json",
    [string]$Mode = "",   # backup | clean-pc | clean-all
    [switch]$Force               # Skip confirmations
)

$TestMode = $true  # si es $true → no cierra ventana al acabar

# Force UTF-8 output to avoid encoding issues
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Load configuration
$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$pcName = $config.pcName
$networkBase = $config.networkBackupPath
$sevenZipPath = $config.sevenZipPath
$folders = $config.folders

# Backup path for this PC
$pcBackupPath = Join-Path $networkBase $pcName

# Prepare log file
$logDir = $config.logPath
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

# Log con fecha, hora y nombre del PC
$logFile = Join-Path $logDir ("${pcName}_backup_log_{0:yyyyMMdd_HHmm}.txt" -f (Get-Date))

function Show-Menu {
    Write-Host ""
    Write-Host "===== LAB BACKUP SYSTEM ====="
    Write-Host "1 - Run BACKUP"
    Write-Host "2 - Clean backup of THIS PC ($pcName)"
    Write-Host "3 - Clean ALL backups (DANGEROUS)"
    Write-Host "4 - Exit"
    Write-Host ""
    $choice = Read-Host "Select an option"
    return $choice
}

function Test-Network {
    if (!(Test-Path $networkBase)) {
        Write-Host "ERROR: Cannot access network path:" -ForegroundColor Red
        Write-Host $networkBase -ForegroundColor Red
        exit 1
    }
}

function Run-Backup {
    Write-Host ""
    Write-Host "===== BACKUP STARTED ($pcName) ====="
    Test-Network

    # Crear carpeta del PC si no existe
    if (!(Test-Path $pcBackupPath)) {
        New-Item -ItemType Directory -Path $pcBackupPath -Force | Out-Null
    }

    foreach ($folder in $folders) {
        $source = $folder.source
        $name = $folder.name
        $compress = $false

        # Comprobar si existe el campo compress en JSON
        if ($folder.PSObject.Properties.Name -contains "compress") {
            $compress = [bool]$folder.compress
        }

        if (!(Test-Path $source)) {
            Write-Host "Source not found: $source" -ForegroundColor Yellow
            continue
        }

        # -------------------------------------------------
        # MODO 1: NORMAL MIRROR (NO COMPRESSION)
        # -------------------------------------------------
        if (-not $compress) {
            $dest = Join-Path $pcBackupPath $name
            if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }

            Write-Host "Sync (mirror): $source -> $dest"
            robocopy $source $dest /MIR /Z /R:2 /W:5 /FFT /XA:H /MT:16 /TEE /LOG:$logFile
        }
        # -------------------------------------------------
        # MODO 2: COMPRESSED BACKUP (ZIP)
        # -------------------------------------------------
        else {
            Write-Host "Compressed backup enabled for: $name" -ForegroundColor Cyan

            # Carpeta temporal para copiar los archivos antes de zip
            $tempFolder = Join-Path $env:TEMP ("backup_" + $pcName + "_" + $name)
            if (Test-Path $tempFolder) { Remove-Item $tempFolder -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null
            Write-Host "Copying to temp folder: $tempFolder"

            # Calcular tamaño de la carpeta de origen
            $folderSize = (Get-ChildItem -Path $source -Recurse | Measure-Object -Property Length -Sum).Sum
            if (-not $folderSize) { $folderSize = 0 }

            # Comprobar espacio libre en unidad temporal
            $psDrive = (Get-Item $tempFolder).PSDrive
            $freeSpace = $psDrive.Free

            if ($freeSpace -lt 2 * $folderSize) {
                Write-Host "WARNING: Not enough free space on $($psDrive.Name): to compress folder '$name'." -ForegroundColor Yellow
                Write-Host "Fallback to normal mirror copy."

                $dest = Join-Path $pcBackupPath $name
                if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                robocopy $source $dest /MIR /Z /R:2 /W:5 /FFT /XA:H /MT:16 /TEE /LOG:$logFile
                continue
            }

            # Copiar contenido a carpeta temporal
            robocopy $source $tempFolder /MIR /Z /R:2 /W:5 /FFT /XA:H /MT:16 /LOG:$logFile /NFL /NDL /NP

            # Crear ZIP con 7-Zip
            $zipFileName = "${name}.zip"
            $zipDest = Join-Path $pcBackupPath $zipFileName
            $localZip = Join-Path $env:TEMP ("${pcName}_${name}.zip")
            if (Test-Path $localZip) { Remove-Item $localZip -Force }

            Write-Host "Creating ZIP: $localZip"
            $sevenZipExe = $sevenZipPath
            $sevenZipArgs = "a -tzip `"$localZip`" `"$tempFolder\*`" -mx=9"

            try {
                $proc = Start-Process -FilePath $sevenZipExe -ArgumentList $sevenZipArgs -Wait -NoNewWindow -PassThru
                if ($proc.ExitCode -ne 0) { throw "7-Zip failed with exit code $($proc.ExitCode)" }

                Write-Host "Copying ZIP to network: $zipDest"
                Copy-Item -Path $localZip -Destination $zipDest -Force
            } catch {
                Write-Host "ERROR: Could not create ZIP for '$name'. Falling back to normal mirror." -ForegroundColor Red
                Write-Host $_
                $dest = Join-Path $pcBackupPath $name
                if (!(Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                robocopy $source $dest /MIR /Z /R:2 /W:5 /FFT /XA:H /MT:16 /TEE /LOG:$logFile
            } finally {
                # Cleanup temporal
                Remove-Item $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $localZip -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Host "===== BACKUP FINISHED ====="

    # Copiar log final a la red
    try {
       $networkLog = Join-Path $pcBackupPath (Split-Path $logFile -Leaf)
       Copy-Item -Path $logFile -Destination $networkLog -Force
       Write-Host "Backup log copied to network folder: $networkLog" -ForegroundColor Cyan
    } catch {
       Write-Host "WARNING: Could not copy log to network path!" -ForegroundColor Yellow
       Write-Host $_
    }
}

function Clean-PC {
    Test-Network

    Write-Host ""
    Write-Host "Cleaning backup for this PC: $pcName"
    Write-Host "Target path: $pcBackupPath"
    
    if (!(Test-Path $pcBackupPath)) {
        Write-Host "No backup folder found for this PC."
        return
    }

    if (-not $Force) {
    	$confirm = Read-Host "Type YES to confirm deletion"
	if ($confirm -ne "YES") {
        	Write-Host "Operation cancelled."
        	return
	}
    }

    # Safety check
    if ($pcBackupPath -notlike "*$pcName*") {
        Write-Host "SECURITY ERROR: Path does not contain PC name. Aborting." -ForegroundColor Red
        exit 1
    }

    # Ultra fast delete using empty mirror
    $empty = Join-Path $env:TEMP "empty_backup_folder"
    if (!(Test-Path $empty)) {
        New-Item -ItemType Directory -Path $empty | Out-Null
    }

    Write-Host "Performing fast cleanup on network storage..."
    robocopy $empty $pcBackupPath /MIR /R:1 /W:1

    # Remove-Item $pcBackupPath -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Backup for $pcName successfully deleted from network storage."
}

function Clean-All {
    Test-Network

    Write-Host ""
    Write-Host "WARNING: This will delete ALL backups in network path!" -ForegroundColor Red
    Write-Host $networkBase -ForegroundColor Red

    if (-not $Force) {
    	$confirm = Read-Host "Type DELETE_ALL to confirm"
    	if ($confirm -ne "DELETE_ALL") {
           Write-Host "Operation cancelled."
	   return
    	}
    }

    $empty = Join-Path $env:TEMP "empty_backup_folder"
    if (!(Test-Path $empty)) {
        New-Item -ItemType Directory -Path $empty | Out-Null
    }

    Write-Host "Deleting all backups (fast mirror cleanup)..."
    robocopy $empty $networkBase /MIR /R:1 /W:1 /NFL /NDL /NP

    Write-Host "All backups removed from network storage."
}

# Automatic mode (for Task Scheduler)
switch ($Mode.ToLower()) {
    "backup"   { Run-Backup; exit }
    "clean-pc" { Clean-PC; exit }
    "clean-all"{ Clean-All; exit }
}

# Interactive menu (no parameters)
while ($true) {
    $option = Show-Menu
    switch ($option) {
        "1" {
		Run-Backup
		Write-Host "Backup finished!" -ForegroundColor Green
		if (-not $TestMode) {
		   Start-Sleep -Seconds 2
  		   exit
                } else {
		   Write-Host "TEST MODE: script will stay open for inspection."
		}
	}
        "2" { 
		Clean-PC 
		Write-Host "Clean backup for this PC finished!" -ForegroundColor Green
		Start-Sleep -Seconds 2
		exit
	}
        "3" { 
		Clean-All 
		Write-Host "Clean backup for all PCs finished!" -ForegroundColor Green
		Start-Sleep -Seconds 2
		exit
	}
	"4" { 
    		Write-Host "Exiting backup system..." -ForegroundColor Cyan
		Start-Sleep -Seconds 2   # Wait 2 seconds so user can read message
		exit
	}
        default { Write-Host "Invalid option." }
    }
}
