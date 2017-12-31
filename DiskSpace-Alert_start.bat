cd /d %~dp0
powershell.exe -ExecutionPolicy Bypass -File .\DiskSpace-Alert.ps1 %*
