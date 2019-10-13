# Accuraty's Disk Space Alert by JRF, started in 2014 and rarely worked on ;)
# Updated to work on Powershell Core 6.1+ in Feb 2019

param(
	[string]$computerRename = "", # option to override and give this device a better name
	[int]$percentWarning = 10,
	[int]$percentCritical = 3 
)
# for above, see https://technet.microsoft.com/en-us/library/jj554301.aspx

# example command line with all (optional) params passed:
# > powershell.exe -ExecutionPolicy Bypass -File .\DiskSpace-Alert.ps1 -computerRename DS2034 -percentWarning 5 -percentCritical 2
## note that the above is normally added as a Schedule Task or Cron job

<# show passed in variables to see what we are overriding
Write-Host "Num Args: " $args.Length;
foreach ($arg in $args)
{
  Write-Host "Arg: $arg";
}
Write-Host "Param: $computerRename";
Write-Host "Param: $percentWarning";
Write-Host "Param: $percentCritical"; 
#>

# Script does NOT generate a report until Available Disk space reaches specified Threshold (Checks for disk space issues)
 
$ErrorActionPreference = "SilentlyContinue"; # what are the other options??
$scriptpath = $MyInvocation.MyCommand.Definition 
$dir = Split-Path $scriptpath 

# Variables to configure (note that a smtpUserPassw dictates the allowed "from" by IP configured on Sparkpost)
$smtpServer = "smtp.sparkpostmail.com" 
$smtpPort = 587;
$smtpSsl = $True; # works on DS2035
$smtpUsername = "SMTP_Injection"
$smtpUserPassw = Get-Content .\keys\sample-key.txt -Raw
# Write-Host "key is $smtpUserPassw"
$ReportSender = "hostAdmin@accuraty.com" 
$users = "hostAdmin@accuraty.com"  <###, "user1@mydomain.com", "user2@mydomain.com"; ###>
$MailSubject = "ASL/Hosting - DiskSpace Issue on "

# No changes needed from here on down!!!
$reportPath = "$dir\DiskSpace-Alert_Logs\" # add if !exists then manually create folder
$reportName = "dsa$(get-date -format yyyyMMdd).htm";
$diskReport = $reportPath + $reportName
If (Test-Path $diskReport) { Remove-Item $diskReport } # prevent needing to overwrite if report name is the same
$redColor = "#FF0000"
$orangeColor = "#FBB917"
$whiteColor = "#FFFFFF"
$sendEmail = $FALSE
# $datetime = Get-Date -Format "yyyy-MM-dd_HHmmss";
$titleDate = Get-Date -Format  "ddd, MMM d, yyyy"

# start building the HTML Body of the email
$emailHeader = Get-Content .\email-header.html -Raw
$emailHeader = $emailHeader -replace "##DayDate##", $titleDate
Add-Content $diskReport $emailHeader

### should we be doing this another way? 
### https://www.red-gate.com/simple-talk/sysadmin/powershell/powershell-day-to-day-admin-tasks-monitoring-performance/
## "Get-WmiObject" no longer works in Powershell 6+ (Core)
## $disks = Get-WmiObject -ComputerName . -Class Win32_Volume -Filter "DriveType = 3" | Where-Object {$_.Label -ne "System Reserved"}
## new version based on Powershell Core docs (Example 5) here; https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-psdrive?view=powershell-6
## below in English; hey Windows, give me a list of Volumes of DriveType 3 that are not system volumes
$disks = Get-CimInstance -Class Win32_Volume -Filter "DriveType=3" | Where-Object { !$_.SystemVolume }
 
# add a row for each volume to the table
foreach ($disk in $disks) {   
	if ($disk.Label -ne "Recovery") {
		$computer = $disk.SystemName;
		if ($computerRename -ne "")
		{ $computer = $computerRename }
		$computerName = $disk.PSComputerName;
		if ($computer -ne $computerName) 
		{ $computer = [string]::Format("{0} ({1})", $computer, $computerName) }
		$deviceID = $disk.Label;
		$volName = $disk.Name;
		$driveLetter = $disk.DriveLetter;
		[float]$size = $disk.Capacity;
		[float]$freespace = $disk.FreeSpace; 
		$percentFree = [Math]::Round(($freespace / $size) * 100, 2);
		$sizeGB = [Math]::Round($size / 1073741824, 2);
		$freeSpaceGB = [Math]::Round($freespace / 1073741824, 2);
		$usedSpaceGB = [Math]::Round($sizeGB - $freeSpaceGB, 2);
		$backgroundColor = $whiteColor;
		
		if ($percentFree -lt $percentWarning) { 
			$backgroundColor = $orangeColor 
			$sendEmail = $TRUE
		}
		if ($percentFree -lt $percentCritical) { 
			$backgroundColor = $redColor 
			$sendEmail = $TRUE
		}
	
		$dataRow = "
			<tr>
			<td width='10%'>$computer</td>
			<td width='5%' align='center'>$deviceID</td>
			<td width='15%' >$volName ($driveLetter)</td>
			<td width='10%' align='center'>$sizeGB</td>
			<td width='10%' align='center'>$usedSpaceGB</td>
			<td width='10%' align='center'>$freeSpaceGB</td>
			<td width='5%' bgcolor=`'$backgroundColor`' align='center'>$percentFree %</td>
			</tr>
			"
	
		Add-Content $diskReport $dataRow;
		Write-Host -ForegroundColor DarkYellow "$computer $deviceID percentage free space = $percentFree";
	}
}

$emailFooter = Get-Content .\email-footer.html -Raw
$emailFooter = $emailFooter -replace "##percentWarning##", $percentWarning
$emailFooter = $emailFooter -replace "##percentCritical##", $percentCritical
Add-Content $diskReport $emailFooter

if ($sendEmail) {
	foreach ($user in $users) {
		Write-Host "Sending Email notification to $user via $smtpServer (SSL $smtpSsl)"
		
		System.Net.ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12
		$smtp = New-Object Net.Mail.SmtpClient($smtpServer, $smtpPort)
		$smtp.EnableSsl = $smtpSsl
		$smtp.Credentials = New-Object System.Net.NetworkCredential($smtpUsername, $smtpUserPassw)
		
		# Build the email message
		$msg = New-Object Net.Mail.MailMessage
		$msg.To.Add($user)
		$msg.From = $ReportSender
		if ($computerRename -eq "")
		{ $msg.Subject = $MailSubject + $computer }
		else
		{ $msg.Subject = $MailSubject + $computerRename }
		$msg.IsBodyHTML = $True
		$msg.Body = Get-Content $diskReport
		try {
			$smtp.Send($msg)
		}
		catch {
			"An error occurred on smtp.Send()", $_.Exception.Message
			, "and", $_.Exception.InnerException
			, "and ", $_.Exception.InnerException.InnerException 
  }
		# $body = ""
		## Send-MailMessage -From $ReportSender -To $user -Subject $MailSubject + $computer -Body $msg.Body -BodyAsHtml 1 -Port $smtpPort -SmtpServer $smtpServer -UserSsl 1

	}
}
