# Change tyrellcorp.us with your domain
$shared_sysmon_folder = '\\tyrellcorp.us\sysvol\tyrellcorp.us\software\sysmon'
# Below is a local path that this script can log and track sysmon
$local_sysmon_folder = 'C:\Windows\sysmon_tracking'
$max_log_file_size = 10 # This is in KB

# Create local path if it does not exist
if (!(Test-Path -PathType Container $local_sysmon_folder)){
    Write-Host "Local folder does not exist - creating it"
    New-Item -ItemType Directory -Force -Path $local_sysmon_folder
}

# DO NOT CHANGE VARIABLES BELOW THIS POINT
$log_output_file = $local_sysmon_folder + "\" + "sysmon_output.txt"
$log_output_backup_file = $local_sysmon_folder + "\" + "sysmon_output.old"
if(Test-Path -Path $log_output_file){
    Write-Host "Prior output file found"
    $log_size = (Get-Item $log_output_file).length/1KB
    # If log size is greater than or equal to $max_log_file_size
    # rotate the file
    if($log_size -ge $max_log_file_size){
        Write-Host "Rotating log file"
        if (Test-Path -Path $log_output_backup_file){
            Remove-Item -Path $log_output_backup_file -Force
            Rename-Item -Path $log_output_file $log_output_backup_file
        } else {
            Rename-Item -Path $log_output_file $log_output_backup_file
        }
    }
}

# Get OS architectrure (32-bit vs 64-bit)
$architecture = $env:PROCESSOR_ARCHITECTURE

# Check if Sysmon is installed
if ($architecture -eq 'AMD64') {
    $service = get-service -name Sysmon64 -ErrorAction SilentlyContinue
    $exe = $shared_sysmon_folder + "\" + "Sysmon64.exe"
} else {
    $service = get-service -name Sysmon -ErrorAction SilentlyContinue
    $exe = $shared_sysmon_folder + "\" + "Sysmon.exe"
}
$sysmon_configuration = $shared_sysmon_folder + "\sysmonconfig.xml"
$sysmon_configuration_file_hash = (Get-FileHash -algorithm SHA1 -Path ($shared_sysmon_folder + "\" + "sysmonconfig.xml")).Hash
$sysmon_current_version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion
$output_version_file_path = $local_sysmon_folder + "\" + "sysmon_version.txt"
$output_configuration_file_hash_path = $local_sysmon_folder + "\" + "sysmon_configuration_file_hash.txt"


function Install-Sysmon {
    # Output the version of Sysmon being installed to output path
    $sysmon_current_version | Out-File -FilePath $output_version_file_path -Force
    # Output the configuration hash being installed to the output path
    $sysmon_configuration_file_hash | Out-File -FilePath $output_configuration_file_hash_path -Force
    # The command below installs Sysmon
    & $exe "-accepteula" "-i" $sysmon_configuration
    # Save the loaded configuration file hash
    $sysmon_configuration_file_hash | Out-File -FilePath $output_configuration_file_hash_path -Force
}

function Remove-Sysmon {
    # The command below uninstalls Sysmon
    & $exe "-accepteula" "-u"
}

function Update-SysmonConfig {
    # The command below updates Sysmon's configuration
    & $exe "-accepteula" "-c" $sysmon_configuration
    # Output the configuration hash used to the output path
    $sysmon_configuration_file_hash | Out-File -FilePath $output_configuration_file_hash_path -Force
}

function Add-Log ($message){
    Get-Date -Format "dddd MM/dd/yyyy HH:mm K" | Out-File -FilePath $log_output_file -Append
    $message | Out-File -FilePath $log_output_file -Append
    Write-Host $message
}

# Install Sysmon if it is not installed
if ($null -eq $service) {
    Add-Log "Installing Sysmon"
    Install-Sysmon
    $installed_version = $sysmon_current_version
    $installed_configuration_hash = $sysmon_configuration_file_hash
} else {
    Add-Log "Sysmon is installed"
    # If Sysmon is installed, get the installed version
    $installed_version = Get-Content -Path $output_version_file_path
    # Also get the current configuration hash
    $installed_configuration_hash = Get-Content -Path $output_configuration_file_hash_path
}

# If Sysmon is installed, check if the version needs upgraded
if ($installed_version -ne $sysmon_current_version) {
    Add-Log "Sysmon version does not match - Reinstalling"
    Remove-Sysmon
    Install-Sysmon
} else {
    Add-Log "Sysmon version matches shared repository version"
    # Check if Sysmon's configuration needs updated
    # Not necessary if Sysmon reinstalled due to version mismatch
    if ($installed_configuration_hash -ne $sysmon_configuration_file_hash){
        Add-Log "Sysmon configuration out of sync - Updating"
        Update-SysmonConfig
    } else {
        Add-Log "Sysmon configuration matches current configuration"
    }
}
