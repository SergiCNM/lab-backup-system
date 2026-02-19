# Lab Backup System - Installation and Usage Guide

<img width="1536" height="1024" alt="Diagrama sistema de còpies de seguretat" src="https://github.com/user-attachments/assets/51044b55-5a5d-49d2-8d71-64370f7e288d" />

## Overview

This repository contains two backup scripts designed for a laboratory environment:

* `pc_labs` → Script for each laboratory PC (sends backups to network storage)
* `pc_central` → Script for the central computer (copies backups to external disk / future cloud)

The system is designed to:

* Automatically backup selected folders
* Store backups in a network path (for example: `\\FITXERS3\fitxers\__Caracteritzacio Electrica_ICTS\_BACKUPS`)
* Generate log files with date, time and PC name
* Allow cleaning backups safely
* Work manually or via Windows Task Scheduler
* Central PC can also backup its own folders and optionally copy selected lab PCs

---

# Repository Structure

```
backup-system/
│
├── pc_labs/
│   ├── backup_lab.ps1
│   └── config_lab.json
│
├── pc_central/
│   ├── backup_central.ps1
│   └── config_central.json
│
└── README.md
```

Each laboratory PC must only use the files inside `pc_labs`.
The central backup computer must only use the files inside `pc_central`.

---

# PART 1 - Installation on Laboratory PCs (pc_labs)

## Step 1 - Create Required Network Folder

On the server or NAS (example):

```
\\FITXERS3\fitxers\__Caracteritzacio Electrica_ICTS\_BACKUPS\
```

Inside this folder, each PC will automatically create:

```
\\FITXERS3\fitxers\__Caracteritzacio Electrica_ICTS\_BACKUPS\PC_NAME\
```

Example:

```
\\FITXERS3\fitxers\__Caracteritzacio Electrica_ICTS\_BACKUPS\PC471\
\\FITXERS3\fitxers\__Caracteritzacio Electrica_ICTS\_BACKUPS\PC312\
```

Make sure:

* All lab PCs have read/write permissions
* Network path is accessible from all PCs

---

## Step 2 - Create Local Script Folder on Each Lab PC

Recommended path:

```
C:\BackupLab\
```

Copy into this folder:

* `backup_lab.ps1`
* `config_lab.json`

Final structure:

```
C:\BackupLab\backup_lab.ps1
C:\BackupLab\config_lab.json
```

---

## Step 3 - Configure config_lab.json

Example configuration:

```json
{
  "pcName": "PC471",
  "networkBackupPath": "\\\\FITXERS3\\fitxers\\__Caracteritzacio Electrica_ICTS\\_BACKUPS",
  "logPath": "C:\\BackupLab\\logs",
  "sevenZipPath": "C:\\Program Files\\7-Zip\\7z.exe",
  "folders": [
    {
      "name": "Documents",
      "source": "C:\\Users\\Lab\\Documents",
      "compress": false
    },
    {
      "name": "Projects",
      "source": "D:\\Projects",
      "compress": true
    }
  ]
}
```

Important fields:

* `pcName` → Unique name of the PC
* `networkBackupPath` → Shared backup folder
* `logPath` → Local folder for logs
* `sevenZipPath` → Full path to 7-Zip executable (required for compression)
* `folders` → List of folders to backup
* `compress` (optional) →
    * `true`  = ZIP compression using 7-Zip
    * `false` = Fast mirror backup (robocopy)
    * Not declared → defaults to `false` (mirror)
 
### Folder Naming Recommendation (Important)

Folder `name` is used as the destination folder and ZIP filename.

It is recommended to:
- Avoid special characters
- Avoid very long names
- Prefer simple names (e.g. `GitHub`, `Measurements`, `Projects`)

Example:
* Good:
`"name": "GitHub"`

* Avoid:
`"name": "Desarrollo GITHUB Backup Version Final"`

**This improves compatibility with ZIP creation and long path handling on both lab PCs and central PC.**

---

## Step 4 - Enable PowerShell Script Execution (Required)

Open PowerShell as Administrator and run:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
```

Press:

```
Y
```

This allows execution of local PowerShell scripts.

---

# PART 2 - How the Backup Script Works (Lab PCs)

## Interactive Mode (Manual Execution)

Open PowerShell in:

```
C:\BackupLab\
```

Run:

```powershell
.\backup_lab.ps1
```

You will see a menu:

```
1 - Run BACKUP
2 - Clean backup of THIS PC
3 - Clean ALL backups (DANGEROUS)
4 - Exit
```

---

## Automatic Mode (Command Line)

### Run Backup

```powershell
.\backup_lab.ps1 -Mode backup
```

### Clean Backup of Current PC (with confirmation)

```powershell
.\backup_lab.ps1 -Mode clean-pc
```

### Clean Backup Without Confirmation (for automation)

```powershell
.\backup_lab.ps1 -Mode clean-pc -Force
```

### Clean ALL Backups (DANGEROUS)

```powershell
.\backup_lab.ps1 -Mode clean-all
```

---

## Compressed Backup Mode (ZIP per Folder)

The system supports per-folder compression using 7-Zip.
You can download 7-zip application at <a href="https://www.7-zip.org/" target="_blank">https://www.7-zip.org/</a>

If `"compress": true` is enabled in a folder configuration, the script will:

1. Create a temporary mirror copy in `%TEMP%`
2. Compress the folder using 7-Zip
3. Copy the ZIP file to the network backup folder
4. Delete temporary files automatically

Example:
```json
{
  "name": "Desarrollo GITHUB",
  "source": "D:\\GitHub",
  "compress": true
}
```
This mode is ideal for:
* Large folders with many small files
* Historical or rarely accessed data
* Repositories and archives

---

# PART 3 - Log System

The script automatically generates log files with:

* PC name
* Date
* Time

Example:

```
backup_log_PC471_20260218_1430.txt
```

Logs are stored in:

```
C:\BackupLab\logs\
```

After the backup finishes, the log file is also copied to:

```
\\FITXERS3\fitxers\__Caracteritzacio Electrica_ICTS\_BACKUPS\PC_NAME\
```

This allows the central computer to:

* Verify last successful backup
* Detect failed backups
* Monitor backup history per PC

---

# PART 4 - Requirements (Important)

## Disk Space Safety for Compression

When compression mode is enabled, the script uses the local TEMP directory
(usually located in the C: drive) to:

- Create a temporary copy of the folder
- Generate the ZIP file locally before sending it to the network

Because of this, the system requires approximately:

> 2× the folder size in free disk space on the TEMP drive

Example:
- Folder size: 500 MB
- Required free space: ~1 GB on C: drive

If there is NOT enough free space on the TEMP drive, or 7-Zip fails / is not found, the script will automatically log a warning and perform a **normal mirror backup (robocopy)** instead.  
The backup will NOT fail.
  
---
## System Requirements

Laboratory PCs:
- Windows 10/11
- PowerShell 5.1 or higher
- Network access to backup storage
- 7-Zip installed (required if compression is used - <a href="https://www.7-zip.org/" target="_blank">https://www.7-zip.org/</a>)

Central PC:
- Windows 10/11
- External backup disk (recommended)
- Access to network backup path

Note:
If compression is disabled (`compress: false`), 7-Zip is not required.

---

# PART 5 - Scheduling Automatic Backups (Recommended)

## Create a Scheduled Task (Windows Task Scheduler)

1. Open "Task Scheduler"
2. Click "Create Basic Task"
3. Name: `Lab Backup`
4. Trigger:

   * Daily (recommended)
   * Or at system startup
5. Action: Start a program

Program:

```
powershell.exe
```

Arguments:

```
-ExecutionPolicy Bypass -File "C:\BackupLab\backup_lab.ps1" -Mode backup
```

Start in:

```
C:\BackupLab\
```

Finish the wizard.

Now the backup will run automatically without user interaction.

---

# PART 6 - Installation on Central Computer (pc_central)

The central PC is responsible for:

* Copying selected lab PCs (`pcsToCopy`) from the network
* Copying its own local folders defined in `folders`
* Storing backups on an external hard drive
* Future cloud sync (rclone, OneDrive, Dropbox)

## Step 1 - Create Central Backup Folder

Example external disk:

```
E:\CentralBackups\
```

## Step 2 - Copy Files

Create:

```
C:\BackupCentral\
```

Copy:

* `backup_central.ps1`
* `config_central.json`

---

## Step 3 - Configure config_central.json

Example:

```json
{
  "pcName": "pc7222",
  "networkBackupPath": "\\\\fitxers3\\fitxers\\__Caracteritzacio Electrica_ICTS\\_BACKUPS",
  "localMirrorPath": "F:\\BACKUPS\\_BACKUPS",
  "logPath": "C:\\BackupCentral\\logs",
  "pcsToCopy": ["pc471", "pc684", "pc6132"],
  "deleteAfterCopy": false,
  "folders": [
    {
      "name": "Medidas",
      "source": "D:\\Documentos\\MESURES",
      "compress": false
    }
  ],
  "email": {
    "enabled": true,
    "smtpServer": "smtp.gmail.com",
    "smtpPort": 587,
    "useSsl": true,
    "from": "imbcnm.labs@gmail.com",
    "to": "sergi.sanchez@imb-cnm.csic.es",
    "username": "imbcnm.labs@gmail.com",
    "password": "TU_APP_PASSWORD_GMAIL"
  }
}
```

networkBackupPath → Network folder where lab PC backups are located
localMirrorPath → Local path for the central backup mirror

Important fields:

* `pcName` → Name of central PC (for log files)
* `networkBackupPath` → Network folder where lab PC backups are located
* `localMirrorPath` → Local path for the central backup mirror (external disk)
* `logPath` → Local folder for logs
* `pcsToCopy` → List of lab PCs to copy from network; if empty, skip network copy
* `deleteAfterCopy` → Delete source backup after copy (true/false)
* `folders` → Local folders to backup from central PC
* `compress` (optional) →
    * `true`  = ZIP compression using 7-Zip
    * `false` = Fast mirror backup (robocopy)
    * Not declared → defaults to `false` (mirror)
      
    * If compression fails or disk space is insufficient, the backup automatically falls back to mirror mode
 
* `email` (optional) → Configure email options to send a notification at the end of the backup to the lab responsible
    * If `enabled = False` or the email section is not defined, no email will be sent
    * If the email section is defined and `enabled = True`, the email will be sent

---

# PART 7 - Safety Features Included

The system includes multiple protections:

* Network availability check before backup
* Confirmation before deletion (unless -Force is used)
* Security check to avoid deleting wrong paths
* Fast cleanup using robocopy mirror method
* Independent logs per PC
* Automatic fallback to non-compressed backup if compression fails or disk space is insufficient (applies to both lab PCs and central PC)
* UTF-8 output to avoid encoding issues
* Central PC respects copy history and only copies newer backups if needed

---

# PART 8 - Best Practices for Laboratory Deployment

Recommended setup:

* One scheduled backup per lab PC (daily at night)
* One central backup (weekly to external disk)
* Periodic check of log files in network folder
* Use unique PC names in each config file
* Use compression only for large or archival folders
* Avoid compression for active measurement data (faster with mirror mode)
* Ensure enough free space in C: drive if compression is enabled
* Test backup manually before automation

---

# PART 9 - Future Cloud Integration (Optional)

The system is prepared to support:

* rclone + OneDrive
* rclone + Dropbox
* Hybrid backup (Network + Cloud + External Disk)

Cloud configuration will be added later in the central PC script without modifying lab PCs.

---

# Final Notes

* Do not modify the script unless necessary
* Always test with manual backup first
* Ensure network path permissions are correct
* Keep at least one external backup copy (recommended)



