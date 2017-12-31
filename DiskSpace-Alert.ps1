# ASL's Disk Space Alert by JRF, started in 2014
param(
    [string]$computerRename = "BetterName", 
    [int]$percentWarning = 10,
    [int]$percentCritical = 3 
	)
# for above, see https://technet.microsoft.com/en-us/library/jj554301.aspx

# example command line with all (optional) params passed:
# > powershell.exe -ExecutionPolicy Bypass -File .\DiskSpace-Alert.ps1 -computerRename DS2034 -percentWarning 5 -percentCritical 2

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

# Script does NOT generate a report when Available Disk space reaches specified Threshold (Checks for disk space issues)

$ErrorActionPreference = "SilentlyContinue";
$scriptpath = $MyInvocation.MyCommand.Definition 
$dir = Split-Path $scriptpath 

# Variables to configure (note that a smtpUserPassw dictates the allowed "from" by IP configured on Sparkpost)
$smtpServer = "smtp.sparkpostmail.com" 
$smtpPort = 587;
$smtpUsername = "SMTP_Injection"
# $smtpUserPassw = "" # ASL-DS2034-DS4302-DS2035
$smtpUserPassw = "" # ASL-DS3095
$ReportSender = "hostAdmin@accuraty.com" 
$users = "hostAdmin@accuraty.com"  <###, "user1@mydomain.com", "user2@mydomain.com"; ###>
$MailSubject = "ASL/Hosting - DiskSpace Issue on "

# No changes needed from here on down!!!
$reportPath = "$dir\DiskSpace-Alert_Logs\" # add if !exists then create folder
$reportName = "dsa$(get-date -format yyyyMMdd).htm";
$diskReport = $reportPath + $reportName
If (Test-Path $diskReport) { Remove-Item $diskReport } # prevent needing to overwrite if report name is the same
$redColor = "#FF0000"
$orangeColor = "#FBB917"
$whiteColor = "#FFFFFF"
$i = 0; # not really being used anymore
$sendEmail = $FALSE
# $datetime = Get-Date -Format "yyyy-MM-dd_HHmmss";
$titleDate = Get-Date -Format  "ddd, MMM d, yyyy"

$header = Get-Content .\email-header.txt -Raw
$header = $header -replace "{{DateDay}}", $titleDate

 Add-Content $diskReport $header
 $tableHeader = "
 <table width='100%'><tbody>
	<tr bgcolor=#CCCCCC>
    <td width='10%' align='center'>Server (Name)</td>
	<td width='5%' align='center'>Drive Label</td>
	<td width='15%' align='center'>Drive Name (Letter)</td>
	<td width='10%' align='center'>Capacity (GB)</td>
	<td width='10%' align='center'>Used (GB)</td>
	<td width='10%' align='center'>Free (GB)</td>
	<td width='5%' align='center'>Free</td>
	</tr>
"
Add-Content $diskReport $tableHeader
### should we be doing this another way? https://www.red-gate.com/simple-talk/sysadmin/powershell/powershell-day-to-day-admin-tasks-monitoring-performance/
$disks = Get-WmiObject -ComputerName . -Class Win32_Volume -Filter "DriveType = 3" | Where-Object {$_.Label -ne "System Reserved"}
foreach($disk in $disks)
{        
	$computer = $disk.SystemName;
	if ($computerRename -ne "")
		{ $computer = $computerRename }
	$computerName = $disk.PSComputerName;
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
	
	if($percentFree -lt $percentWarning) 
	{ 
		$backgroundColor = $orangeColor 
		$sendEmail = $TRUE
	}
	if($percentFree -lt $percentCritical) 
	{ 
		$backgroundColor = $redColor 
		$sendEmail = $TRUE
	}

	$dataRow = "
		<tr>
		<td width='10%'>$computer ($computerName)</td>
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
	$i++		
}

$tableDescription = "
 </table><br />
 <table width='50%'>
	<tr bgcolor='White'>
		<td width='50%' align='center' bgcolor='#FBB917'>Warning less than $percentWarning% free space</td>
		<td width='50%' align='center' bgcolor='#FF0000'>Critical less than $percentCritical% free space</td>
	</tr>
</table>
"

Add-Content $diskReport $tableDescription
Add-Content $diskReport "</body></html>"

if ($sendEmail)
{
	foreach ($user in $users)
	{
		Write-Host "Sending Email notification to $user"
		
		$smtp = New-Object Net.Mail.SmtpClient($smtpServer, $smtpPort)
		$smtp.EnableSsl = $True
		$smtp.Credentials = New-Object System.Net.NetworkCredential($smtpUsername, $smtpUserPassw)
		$msg = New-Object Net.Mail.MailMessage
		$msg.To.Add($user)
		$msg.From = $ReportSender
		if ($computerRename -eq "")
			{ $msg.Subject = $MailSubject + $computer }
		else
			{ $msg.Subject = $MailSubject + $computerRename }
		$msg.IsBodyHTML = $True
		$msg.Body = Get-Content $diskReport
		$smtp.Send($msg)
		# $body = ""
	}
}
