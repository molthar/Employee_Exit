#This process is to fully lockout a user from their email and AD accounts as well as create a record of the process.

param (
	# [Parameter(Mandatory=$true)]
	[string] $username,
	[string] $email,
	[string] $path_to_backup,
	[string] $supervisor_email,
	[string] $your_gsuite_email,
	[string] $super_admin_y_or_n
)
#Setting the parameters that will be used throughout the script.

$drive_folder = "$username backup_$(get-date -Format yyyy-MM-dd-hhmmss)"
#setting a parameter for a google drive folder name for the backup to google drive. Ex: E00000000_backup_01-25-2015
$current_dir = pwd
#sets current directory
$today = (get-date -Format yyyy-MM-dd-hhmm)
#sets current date and time
$pre = Get-Command
#gets list of all Functions and commands before the scripts functions are set

function AD_AccountInfo {
	param (
	[string] $username
	)
	Write-Host ""; `
	Write-Host "Getting AD Account Info"; `
	get-ADUser $username `
	-properties Enabled `
	| select sAMAccountName,name,enabled,userPrincipalname,distinguishedname `
}
#Retrieves basic AD Account info such as sAMAccountName,name, and if they are Enabled. Also gets the current groups the user is a member of.

Function AD_GroupInfo {
	param (
		[string] $username
	)
	Write-Host " "; `
	Write-Host "Member Of"; `
	Write-Host "--------------------------------"
	Get-ADPrincipalGroupMembership $username `
	| select -Expand name; `
	Write-Host ""
}
#retrieves a list of all Groups the user was a member of in AD

Function Gsuite_Account_Info {
	param (
	[string] $email
	)
	gam info `
	user $email ; `
	gam print mobile `
	query $email ; `
	gam user $email `
	show asps `
}
#gets GSuite Account info including list of mobile devices and AppSpecific passwords

function DisableAccount {
	param (
	[string] $username
	)
	disable-adaccount $username `
	-confirm:$false `
	-verbose
}
#Disables AD Account

function GroupRemoval {
	param (
	[string] $username
	)
	Get-ADPrincipalGroupMembership `
	-Identity $Username `
	| where {$_.Name -notlike "Domain Users"} `
	| % {Remove-ADPrincipalGroupMembership `
	-Identity $Username -MemberOf $_ -Confirm:$false -Verbose}
}
#Filters and Removes user from all groups but Domain Users.

function DelegateEmail_Admin {
	param (
	[string] $email,
	[string] $supervisor_email
	)
	$env:OAUTHFILE="C:\GAM-CUI\oauth2.txt-cui.edu_delegate-only"; `
	gam `
		user "$email" `
		delegate to `
		$supervisor_email; `
	$env:OAUTHFILE="C:\GAM-CUI\oauth2.txt"
}
#Sets the correct oauth file for email delegation and delegates the users email to their supervisor,
#changes the oauth file back to the "correct one" for non Gsuite superadmins, then changes the Oauth back when done.
#If you are a super user in Google Apps you don't need the oauth file, this is for lower privilege admins.
#The oauth file is located in the IT Services Client FT Google Drive.

function DelegateEmail_Superadmin {
	param (
	[string] $email,
	[string] $supervisor_email
	)
	gam `
	user "$email" `
	delegate to `
	$supervisor_email
}
#email delegation function for use by super admins

Function GAL_off {
	param (
	[string] $email
	)
	gam update user `
	$email `
	gal off
}
#removes user from Global Access list

function CheckGSuiteEmail {
	if(-not($email)) {
		try {
			Throw "Please enter a G Suite email address for -cui_email"
		}
		catch {
			Write-Host
			Write-Host "Exception Message: $($_.Exception.Message)"
			Write-Host
			exit 10
		}
	}
}


function CheckPathToBackup {
	if(-not($path_to_backup)) {
		try {
			Throw "Please enter a path to backup for -path_to_backup WITHOUT THE TRAILING SLASH"
		}
		catch {
			Write-Host
			Write-Host "Exception Message: $($_.Exception.Message)"
			Write-Host
			exit 20
		}
	}
}


function CreateDriveFolder {
	param (
		[string] $dir_name,
		[string] $par_name
	)
    gam `
		user "$email" `
		add drivefile `
		drivefilename "$dir_name" `
		mimetype gfolder `
		parentname "$par_name"
}


function BackupFilesToDrive {
		param (
		[string] $backup_path,
		[string] $par_name
	)
	Set-Location $backup_path
    Get-ChildItem -File | `
		% {`
			gam `
				user "$email" `
				add drivefile `
				localfile "$_" `
				parentname "$par_name"
		}
}


function Recurse1 {
	$directories1 = (Get-ChildItem -Directory).FullName
	foreach ($directory1 in $directories1) {
		$dir_name = (Get-Item $directory1).Name
		$par_name = (Get-Item $directory1).Parent.Name
		$backup_path = (Get-Item $directory1).FullName

		CreateDriveFolder -dir_name $dir_name -par_name $drive_folder
		BackupFilesToDrive -backup_path $backup_path -par_name $dir_name

		Recurse2
	}
}


function Recurse2 {
	$directories2 = (Get-ChildItem -Directory -Recurse).FullName
	foreach ($directory2 in $directories2) {
		$dir_name = (Get-Item $directory2).Name
		$par_name = (Get-Item $directory2).Parent.Name
		$backup_path = (Get-Item $directory2).FullName

		CreateDriveFolder -dir_name $dir_name -par_name $par_name
		BackupFilesToDrive -backup_path $backup_path -par_name $dir_name
	}
}

function Transfer_Drive {
	param (
	[string] $email,
	[string] $supervisor_email
	)
	gam user `
	$email `
	transfer drive `
	$supervisor_email
}
#Transfers all google drive content to supervisor

Function Check_Gsuite_Permissions {
	param(
	[string] $email
	)
	gam user `
	$email `
	show filelist todrive name permissions
}
#creates and opens a list of all files in users google drive. Used to check for external sharing/ownership of CUI files
#this will display or appear in your google drive under the filename "user user@dom.com Drive files"

Function Remove_GSuite_Groups {
	param (
	[string] $email
	)
	gam `
		user $email `
		delete groups
}
#Removes user from all GSuite groups

Function GSuite_OU_Update {
	param (
	[string] $email
	)
	gam `
		update user `
		$email `
		org Inactive_Users
}
#Moves user to Inactive_Users OU, this disables POP/IMAP if it was not already.

Function Deprovision_GSuite {
		param (
		[string] $email
		)
		gam user `
		$email deprovision
}
#deprovisions Gsuite account. This removes app specific password, OAuth tokens, and backup codes

Function Get_Mobile_ID_List {
		param (
		[string] $email,
		[string] $your_gsuite_email,
		[string] $today,
		[string] $username
		)
		gam print `
		mobile query `
		$email todrive; `
		gam user `
		$your_gsuite_email `
		update drivefile drivefilename `
		"cui.edu - Mobile" newfilename `
		"($username)_MDL_($today)"; `
		gam user `
		$your_gsuite_email `
		get drivefile drivefilename `
		"($username)_MDL_($today)" `
		format csv targetfolder `
		"\\cui.edu\files\IT_Services\Mobile_Device_Lists_Exits"
}
#retrieves mobile device list for user, and sends it to your google drive. File is renamed and then downloaded to the ITS shares
#upload to gdrive is necessary to prevent errors with formatting

Function Wipe_Account_Mobile {
	gam csv `
	"\\cui.edu\files\IT_Services\Mobile_Device_Lists_Exits\($username)_MDL_($today).csv" `
	gam update mobile `
	~resourceId `
	action account_wipe
}
#uses file created from Get_Mobile_ID_List to wipe account off of all mobile devices

Function Network_Drive_Backup {
	param (
	[string] $path_to_backup,
	[string] $email
)
	CheckGSuiteEmail;
	CheckPathToBackup;

$backup_path = (Get-Item $path_to_backup).FullName;
$bk_dir = (Get-Item $path_to_backup).Name;

CreateDriveFolder -dir_name $drive_folder -par_name "/ of $email Drive Account";
BackupFilesToDrive -backup_path $backup_path -par_name $drive_folder;
Recurse1
}
#Function that runs CheckGSuiteEmail, CheckPathToBackup, and CreateDriveFolder, BackupFilesToDrive
#Below this is attached to a switch that skips this step if $path is not specified

$post = Get-Command

Function Func_List {
diff $pre $post | select InputObject
}

if ($username -eq "" -or $email -eq "" -or $supervisor_email -eq "" -or $your_gsuite_email -eq "" -or $super_admin_y_or_n -eq "") {
	write-host "---------------------------------------------------------"; `
	Write-Host "All parameters not set, but functions have been loaded. " ; `
	Write-Host "---------------------------------------------------------"; `
	Write-Host "To view list of Available Functions enter Func_List"; `
	Write-Host "---------------------------------------------------------"; `
		break }

Start-Transcript -path "\\cui.edu\files\IT_Services\Employee_Exit_Transcript\$username.txt"

Write-Host "---------------------"
Write-Host "Pre Account Summary"
Write-Host "---------------------"
AD_AccountInfo -username $username
Write-Host "---------------------"
AD_GroupInfo -username $username
Write-Host "---------------------"
Gsuite_Account_Info -email $email

Write-Host "---------------------"
Write-Host "Disabling AD Account"
Write-Host "---------------------"
DisableAccount -username $username

GroupRemoval -username $username
Write-Host "---------------------"
Write-Host "Delegating Email"
Write-Host "---------------------"
if ($super_admin_y_or_n -eq 'y') {

			#DelegateEmail_Superadmin -email $email -supervisor_email $supervisor_email

} ElseIf ($super_admin_y_or_n -eq 'n') {

			DelegateEmail_Admin -email $email -supervisor_email $supervisor_email

}
Write-Host "---------------------"
Write-Host "Removing from GAL"
Write-Host "---------------------"
GAL_off -email $email
Write-Host "-----------------------"
Write-Host "Removing GSuite Groups"
Write-Host "-----------------------"
Remove_GSuite_Groups -email $email
Write-Host "-----------------------------"
Write-Host "Moving to Inactive_Users OU"
Write-Host "-----------------------------"
GSuite_OU_Update -email $email
Write-Host "-----------------------"
Write-Host "Deprovisioning Account"
Write-Host "-----------------------"
Deprovision_GSuite -email $email
Write-Host "---------------------------"
Write-Host "Retrieving Mobile ID List"
Write-Host "---------------------------"
Get_Mobile_ID_List -email $email -your_gsuite_email $your_gsuite_email -today $today -username $username
Write-Host "---------------------"
Write-Host "Wiping Mobile ID"
Write-Host "---------------------"
Wipe_Account_Mobile
Write-Host "-----------------------------------------------"
Write-Host "Checking Google Drive Shared with Permissions"
Write-Host "-----------------------------------------------"
Check_Gsuite_Permissions -email $email
Write-Host "---------------------"
Write-Host "Backing up P: Drive"
Write-Host "---------------------"
if ($path_to_backup -eq "") {
Write-Host "Path Value Not Specified"
} Else {
Network_Drive_Backup -path_to_backup $path_to_backup -email $email
}
Write-Host "-----------------------------------------------------"
Write-Host "Transferring All Drive Files to $supervisor_email"
Write-Host "-----------------------------------------------------"
Transfer_Drive -email $email -supervisor_email $supervisor_email

Write-Host "---------------------"
Write-Host "Post Account Summary"
Write-Host "---------------------"
AD_AccountInfo -username $username
Write-Host "---------------------"
AD_GroupInfo -username $username
Write-Host "---------------------"
Gsuite_Account_Info -email $email

cd $current_dir

Stop-Transcript
