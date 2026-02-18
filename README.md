# Lab Backup System - Installation and Usage Guide

## Overview

This repository contains two backup scripts designed for a laboratory environment:

* `pc_labs` → Script for each laboratory PC (sends backups to network storage)
* `pc_central` → Script for the central computer (copies backups to external disk / future cloud)

The system is designed to:

* Automatically backup selected folders
* Store backups in a network path (for example: `\\FITXERS3\fitxers\Backups`)
* Generate log files with date, time and PC name
* Allow cleaning backups safely
* Work manually or via Windows Task Scheduler

---

# Repository Structure

```
backup-system/
│
├── pc_labs/
│   ├── script_backup.ps1
│   └── config_lab.json
│
├── pc_central/
│   ├── script_central.ps1
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
\\FITXERS3\fitxers\Backups\
```

Inside this folder, each PC will automatically create:

```
\\FITXERS3\fitxers\Backups\PC_NAME\
```

Example:

```
\\FITXERS3\fitxers\Backups\PC471\
\\FITXERS3\fitxers\Backups\PC312\
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

* `script_backup.ps1`
* `config_lab.json`

Final structure:

```
C:\BackupLab\script_backup.ps1
C:\BackupLab\config_lab.json
```

---

## Step 3 - Configure config_lab.json

Example configuration:

```json
{
  "pcName": "PC471",
  "networkBackupPath": "\\\\FITXERS3\\fitxers\\Backups",
  "logPath": "C:\\BackupLab\\logs",
  "folders": [
    {
      "name": "Documents",
      "source": "C:\\Users\\Lab\\Documents"
    },
    {
      "name": "Projects",
      "source": "D:\\Projects"
    }
  ]
}
```

Important fields:

* `pcName` → Unique name of the PC
* `networkBackupPath` → Shared backup folder
* `logPath` → Local folder for logs
* `folders` → List of folders to backup

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
.\script_backup.ps1
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
.\script_backup.ps1 -Mode backup
```

### Clean Backup of Current PC (with confirmation)

```powershell
.\script_backup.ps1 -Mode clean-pc
```

### Clean Backup Without Confirmation (for automation)

```powershell
.\script_backup.ps1 -Mode clean-pc -Force
```

### Clean ALL Backups (DANGEROUS)

```powershell
.\script_backup.ps1 -Mode clean-all
```

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
\\FITXERS3\fitxers\Backups\PC_NAME\
```

This allows the central computer to:

* Verify last successful backup
* Detect failed backups
* Monitor backup history per PC

---

# PART 4 - Scheduling Automatic Backups (Recommended)

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
-ExecutionPolicy Bypass -File "C:\BackupLab\script_backup.ps1" -Mode backup
```

Start in:

```
C:\BackupLab\
```

Finish the wizard.

Now the backup will run automatically without user interaction.

---

# PART 5 - Installation on Central Computer (pc_central)

The central PC is responsible for:

* Copying all lab backups
* Storing them on an external hard drive
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

* `script_central.ps1`
* `config_central.json`

---

## Step 3 - Configure config_central.json

Example:

```json
{
  "networkSource": "\\\\FITXERS3\\fitxers\\Backups",
  "localDestination": "E:\\CentralBackups",
  "logPath": "C:\\BackupCentral\\logs"
}
```

---

# PART 6 - Safety Features Included

The system includes multiple protections:

* Network availability check before backup
* Confirmation before deletion (unless -Force is used)
* Security check to avoid deleting wrong paths
* Fast cleanup using robocopy mirror method
* Independent logs per PC
* UTF-8 output to avoid encoding issues

---

# PART 7 - Best Practices for Laboratory Deployment

Recommended setup:

* One scheduled backup per lab PC (daily at night)
* One central backup (weekly to external disk)
* Periodic check of log files in network folder
* Use unique PC names in each config file
* Test backup manually before automation

---

# PART 8 - Future Cloud Integration (Optional)

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
