Configuration DcConfig
{
	[CmdletBinding()]
	Param
	(
		[string]$NodeName = 'localhost',
		[PSCredential]$DomainAdminCredentials
	)

	Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName xStorage 
    Import-DscResource -ModuleName xComputerManagement 

	Node $AllNodes.Where{$_.Role -eq "Primary DC"}.Nodename
	{             
  		LocalConfigurationManager
		{
			ConfigurationMode = 'ApplyAndAutoCorrect'
			RebootNodeIfNeeded = $true
			ActionAfterReboot = 'ContinueConfiguration'
			AllowModuleOverwrite = $true
		}

		WindowsFeature DNS_RSAT
		{ 
			Ensure = "Present" 
			Name = "RSAT-DNS-Server"
		}

		WindowsFeature ADDS_Install 
		{ 
			Ensure = 'Present' 
			Name = 'AD-Domain-Services' 
		} 

		WindowsFeature RSAT_AD_AdminCenter 
		{
			Ensure = 'Present'
			Name   = 'RSAT-AD-AdminCenter'
		}

		WindowsFeature RSAT_ADDS 
		{
			Ensure = 'Present'
			Name   = 'RSAT-ADDS'
		}

		WindowsFeature RSAT_AD_PowerShell 
		{
			Ensure = 'Present'
			Name   = 'RSAT-AD-PowerShell'
		}

		WindowsFeature RSAT_AD_Tools 
		{
			Ensure = 'Present'
			Name   = 'RSAT-AD-Tools'
		}

		WindowsFeature RSAT_Role_Tools 
		{
			Ensure = 'Present'
			Name   = 'RSAT-Role-Tools'
		}      

		xWaitForDisk Wait_Data_Disk
		{
			DiskNumber = $Node.DataDiskNumber
			RetryCount = $Node.RetryCount
			RetryIntervalSec = $Node.RetryIntervalSec
			DependsOn = '[WindowsFeature]RSAT_Role_Tools'
		}

		xDisk Data_Disk
		{
			DiskNumber = $Node.DataDiskNumber
			DriveLetter = $Node.DataDriveLetter
			AllocationUnitSize = 4096
			DependsOn = '[xWaitforDisk]Wait_Data_Disk'
		}

		xADDomain CreateForest 
		{ 
			DomainName = $Node.DomainName            
			DomainAdministratorCredential = $DomainAdminCredentials
			SafemodeAdministratorPassword = $DomainAdminCredentials
			#DnsDelegationCredential = $DomainAdminCredentials
			DomainNetbiosName = $Node.DomainNetBiosName
			DatabasePath = $Node.DataDriveLetter + ":\NTDS"
			LogPath = $Node.DataDriveLetter + ":\NTDS"
			SysvolPath = $Node.DataDriveLetter + ":\SYSVOL"
			DependsOn = '[xDisk]Data_Disk', '[WindowsFeature]ADDS_Install'
		}
	}
}

function Get-ModuleVersion
{
	param
	(
		[string]$moduleName
	)

	$modules = get-module -ListAvailable -Name $moduleName
	return ($modules | select version -Unique | Sort -Descending)[0].Version.Tostring()

} 