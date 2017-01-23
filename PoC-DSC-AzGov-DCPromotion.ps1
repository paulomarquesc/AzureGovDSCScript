<#
.SYNOPSIS
    POC-DSC-AzGov-DCPromotion.ps1 - Script that uses PowerShell DSC to promote an Azure VM as a Domain Controller for Azure Government environment.
.DESCRIPTION
    POC-DSC-AzGov-DCPromotion.ps1 - Script that uses PowerShell DSC to promote an Azure VM as a Domain Controller for Azure Government environment.
    Since Extensions are still not being shown yet in Azure Government Portal, this script must be used in replacement of the steps outlined
    at the Portal Guided Scenario of the Fast Start for IaaS, item 4.1.11.3. 
.PARAMETER
    resourceGroup - resource group where the VM is part of
.PARAMETER
    stagingStorageAccount - existing storage account that will hold the DSC files during deployment
.PARAMETER
    stagingStorageAccountResourceGroup - name of the staging storage account’s resource group
.PARAMETER
    resourceGroup - resource group where the VM is part of
.PARAMETER
    vmName - name of the VM to install/execute the DSC extension
    
.DISCLAIMER
    This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment.
    THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
    INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  
    We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute the object
    code form of the Sample Code, provided that You agree: (i) to not use Our name, logo, or trademarks to market Your software
    product in which the Sample Code is embedded; (ii) to include a valid copyright notice on Your software product in which the
    Sample Code is embedded; and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims
    or lawsuits, including attorneys’ fees, that arise or result from the use or distribution of the Sample Code.
    Please note: None of the conditions outlined in the disclaimer above will supersede the terms and conditions contained
    within the Premier Customer Services Description.
#>
param
(
    [Parameter(Mandatory=$true)]
    [string]$resourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$stagingStorageAccount,

    [Parameter(Mandatory=$true)]
    [string]$stagingStorageAccountResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$vmName

)
$currentFolder = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Definition)
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

#----------------------------------------------------------------------------------------------------------------------
# Functions
#----------------------------------------------------------------------------------------------------------------------
function Create-DSCPackage
{
	param
	(
		[string]$dscScriptsFolder,
		[string]$outputPackageFolder,
		[string]$dscConfigFile
	)
    # Create DSC configuration archive
    if (Test-Path $dscScriptsFolder) {
        Add-Type -Assembly System.IO.Compression.FileSystem
        $ArchiveFile = Join-Path $outputPackageFolder "$dscConfigFile.zip"
        Remove-Item -Path $ArchiveFile -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::CreateFromDirectory($dscScriptsFolder, $ArchiveFile)
    }
	else
	{
		thrown "DSC path $dscScriptsFolder does not exist"
	}
}

function Upload-BlobFile
{
    param
    (
        [string]$ResourceGroupName,
        [string]$storageAccountName,
        [string]$containerName,
        [string]$fullFileName
    )
 
    # Checks if source file exists
    if (!(Test-Path $fullFileName))
    {
        throw "File $fullFileName does not exist."
    }

    $storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName 
   
    if ($storageAccount -ne $null)
    {
        # Create container
        New-AzureStorageContainer -Name $containerName -Context $storageAccount.Context -Permission Container -ErrorAction SilentlyContinue

        # Uploads a file
        $blobName = [System.IO.Path]::GetFileName($fullFileName)

        Set-AzureStorageBlobContent -File $fullFileName -Blob $BlobName -Container $containerName -Context $storageAccount.Context -Force
    }
    else
    {
        throw "Storage Account $storageAccountName could not be found at resource group named $ResourceGroupName"
    }
}

function Invoke-AzureRmPowershellDSCAD
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$OutputPackageFolder,

        [Parameter(Mandatory=$true)]
        [string]$DscScriptsFolder,

        [Parameter(Mandatory=$true)]
        [string]$DscConfigFile,

        [Parameter(Mandatory=$true)]
        [string]$DscConfigFunction,

        [Parameter(Mandatory=$false)]
        [string]$dscConfigDataFile,

        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$VMName,

        [Parameter(Mandatory=$true)]
        [string]$StagingSaName,

        [Parameter(Mandatory=$true)]
        [string]$stagingSaResourceGroupName,

        [Parameter(Mandatory=$false)]
        [PSCredential]$Credentials
    )
    
    $outputPackagePath = Join-Path $outputPackageFolder "$dscConfigFile.zip"
    $configurationPath = Join-Path $dscScriptsFolder $dscConfigFile
    $configurationDataPath = Join-Path $dscScriptsFolder $dscConfigDataFile

    # Create DSC configuration archive
	Create-DSCPackage -dscScriptsFolder $dscScriptsFolder -outputPackageFolder $outputPackageFolder -dscConfigFile $dscConfigFile

    # Uploading DSC configuration archive
    Upload-BlobFile -storageAccountName $StagingSaName -ResourceGroupName $stagingSaResourceGroupName -containerName "windows-powershell-dsc" -fullFileName $outputPackagePath
	
	##
    ## In order to know current extension version, you can use the following cmdlet to obatin it (user must be co-admin of the subscription and a subscription in ASM mode must be set as default)
    ## $dscExt = Get-AzureVMAvailableExtension -ExtensionName DSC -Publisher Microsoft.Powershell
	##

    # Executing Powershell DSC Extension on VM
    Set-AzureRmVMDscExtension   -ResourceGroupName $ResourceGroupName `
                                -VMName $vmName `
                                -ArchiveBlobName "$dscConfigFile.zip" `
                                -ArchiveStorageAccountName $stagingSaName `
                                -ArchiveResourceGroupName $stagingSaResourceGroupName `
                                -ConfigurationData $ConfigurationDataPath `
                                -ConfigurationName $dscConfigFunction `
                                -ConfigurationArgument @{"DomainAdminCredentials"=$Credentials} `
                                -Version "2.19" `
                                -AutoUpdate -Force -Verbose
} 

#----------------------------------------------------------------------------------------------------------------------
# Script Start
#----------------------------------------------------------------------------------------------------------------------
$creds = Get-Credential -Message "Please enter the username and password for the Domain Admin in the new Forest"

# Promoting VM to be a Domain Controller via Powershell DSC
Write-Verbose "Running Powershell DSC to promote vm as Domain Controller" -Verbose
Invoke-AzureRmPowershellDSCAD -OutputPackageFolder $currentFolder `
                            -DscScriptsFolder (Join-Path $currentFolder "DSC") `
                            -DscConfigFile DCConfig.ps1 `
                            -DscConfigFunction DcConfig `
                            -dscConfigDataFile ConfigDataAD.psd1 `
                            -ResourceGroupName $resourceGroup `
                            -VMName $vmName `
                            -StagingSaName $stagingStorageAccount `
                            -stagingSaResourceGroupName $stagingStorageAccountResourceGroup `
                            -Credentials $creds