<#
.SYNOPSIS
Script to TeamCity Build Server with new Build configs for branches

.DESCRIPTION
Uses TeamCity REST api to Clone off new Build Configs

.EXAMPLE
$creds = Get-Credential -Credential 'giftcert\aburkeadmin';
Example of Credential input

.\Clone-TeamCityBuildConfigs.ps1 -targetbranch 1606 -usercreds $creds -Dbg

.NOTES
Author: Aaron Burke
Last Update: 8-10-2016
#>

[CmdletBinding()]
Param (
	[string] $workdir = "$env:temp\TC-XML-Data",
	[string] $hostanddomainurl = 'https://ci.hallmarkbusiness.com',
	[string] $RESTURLFragment = '/httpAuth/app/rest',
	[string] $parentproject = 'IrisCd',
	[string] $currentbranch = '1607',
	[string[]] $targetbranch = @('1608'),
	[System.Management.Automation.PSCredential] $usercreds,
	[switch] $SkipCleanUp,
	[switch] $WhatIf,
	[switch] $Dbg
)

function Pause-Execution() {
	Read-Host -Prompt "Press Enter to continue...";
}

function Get-VCSRootData([xml] $xmldata, $currentbranch) {
	[string] $rootdata = $null;
	$xmldata.SelectNodes("//*") | foreach {
		$node=$_;
		@("id") | foreach {
			$nodename=$_;
			if ( $node.GetAttribute($nodename) | where { $_ -like "*$($currentbranch)*"} ) {
				if ($nodename -eq "id") { 
					$rootdata = $node.GetAttribute($nodename); 
				}
			}
		}
	}
	return $rootdata;
}

function Update-VCRRootXMLData([xml] $inboundxmldata, $currentbranch, $targetbranch){
	$inboundxmldata.SelectNodes("//*") | foreach {
		$node=$_;
		@("id","name","value","href") | foreach {
			$nodename=$_;
			if ( $node.GetAttribute($nodename) | where { $_ -like "*$($currentbranch)*"} ) {
				$currentNodeValue = $node.GetAttribute($nodename);
				#$replacedNodeValue = $(($currentNodeValue).replace($currentbranch,$targetbranch));
				Write-Verbose "Found Node $nodename with value of $($currentNodeValue)";
				$node.SetAttribute($nodename, $(($currentNodeValue).replace($currentbranch,$targetbranch)));
				Write-Verbose "`tReplaced with new value of $(($currentNodeValue).replace($currentbranch,$targetbranch))";
			}
		}
	}
	return $inboundxmldata;
}

function Update-ConfigSettingsAndParams($RESTURLNewConfig, [System.Management.Automation.PSCredential] $usercreds) {
	$contenttype = "text/plain";
	$HTTPMethod = 'PUT';
	
	# Update settings and parameters
	write-verbose "Updating settings and parameters for the $newBuildConfigId build config"
	$setting = 'settings/buildNumberCounter';
	$textdata = [string] '1000';
	$result = Run-RESTCommand "$($RESTURLNewConfig)/$setting" $HTTPMethod $usercreds $textdata $contenttype;
	if ($Dbg) { "$result`n`n"; Pause-Execution; }
	
	$setting = 'parameters/Build%2EBranch';
	$textdata = [string] $targetbranch;	
	$result = Run-RESTCommand "$($RESTURLNewConfig)/$setting" $HTTPMethod $usercreds $textdata $contenttype;
	if ($Dbg) { "$result`n`n"; Pause-Execution; }
	
	# Update build config description
	write-verbose "Updating build config description for $newBuildConfigId"
	$setting = 'description';
	$textdata = [string] $newBuildConfigDescription;
	$result = Run-RESTCommand "$($RESTURLNewConfig)/$setting" $HTTPMethod $usercreds $textdata $contenttype;
	if ($Dbg) { "$result`n`n"; Pause-Execution; }	
}

function Set-BuildConfigPause($RESTURLNewConfig, [System.Management.Automation.PSCredential] $usercreds, [string]$textdata, $newBuildConfigId) {
	$contenttype = "text/plain";
	$HTTPMethod = 'PUT';

	# Resume or Pause new build config
	if ($textdata -eq 'false') {
		write-verbose "Resuming $newBuildConfigId build config"
	} 
	else {
		write-verbose "Pausing $newBuildConfigId build config"
	}

	$setting = 'paused';
	$result = Run-RESTCommand "$($RESTURLNewConfig)/$setting" $HTTPMethod $usercreds $textdata $contenttype;
	if ($Dbg) { "$result`n`n"; Pause-Execution;}
}

function Run-RESTCommand([string] $RESTURL, [string] $HTTPMethod, [System.Management.Automation.PSCredential] $usercreds, [object] $inData, $contenttype) {
	$result = $null; 
	$data = $null;
	[int] $timeout = 300;
	
	switch ($contenttype) {
		'application/xml' { $data = [xml] $inData; }
		'application/json' { $data = (@{ undefined=$inData }) | ConvertTo-Json; }
		'text/plain' { $data = [string] $inData; }
		default { $data = [string] $inData; }
	}
	
	switch ($HTTPMethod) {
		{ ($_ -eq 'PUT') -or ($_ -eq 'POST') } {
			if (($data -ne $null) -or ($data -ne '')) {
				if (!($WhatIf)) {
					write-verbose "Invoke-RestMethod -Method $HTTPMethod -Uri $RESTURL -Credential $($usercreds.username) -Body $($data) -ContentType $contenttype";
					try {
						$result = Invoke-RestMethod -Method $HTTPMethod -Uri $RESTURL -Credential $($usercreds) -Body $($data) -ContentType $contenttype -TimeoutSec $timeout;
					}
					catch {
						Write-Error -Exception $_.exception -ErrorAction stop;
					}
				} 
				else {
					$result = "WhatIf invoked the following command will be skipped:`n `
					`tInvoke-RestMethod -Method $HTTPMethod -Uri $RESTURL -Credential $($usercreds.username) -Body $($data) -ContentType $contenttype`n";
				}
			}
		}
		{ ($_ -eq 'DELETE') -or ($_ -eq 'GET') } {
			if (!($WhatIf)) {
				write-verbose "Invoke-RestMethod -Method $HTTPMethod -Uri $RESTURL -Credential $($usercreds.username)";
				try {
					$result = Invoke-RestMethod -Method $HTTPMethod -Uri $RESTURL -Credential $($usercreds) -TimeoutSec $timeout;
				}
				catch {
					Write-Error -Exception $_.exception -ErrorAction stop;
				}
			} 
			else {
				$result = "WhatIf invoked the following command will be skipped:`n `
				`tInvoke-RestMethod -Method $HTTPMethod -Uri $RESTURL -Credential $($usercreds.username)`n";
			}
		}
	}
	
	return $result
}


$BaseRESTURL = "$($hostanddomainurl)$($RESTURLFragment)"
$ResturlProjectBuildTypes = "$($BaseRESTURL)/projects/id:$($parentproject)/buildTypes"
if ($usercreds -eq $null) {
	$usercreds = (Get-Credential `
	-UserName "$env:USERDOMAIN\$env:USERNAME" `
	-Message "Enter Credentials for your REST API connection");
}

$count = 0;
$execute = $true;
$HTTPMethod = 'GET';
$ResturlBuildTypes = "$($BaseRESTURL)/buildTypes";

$xmldata = [xml] (Run-RESTCommand $ResturlBuildTypes $HTTPMethod $usercreds);
$xmldata.SelectNodes("//*") | foreach {
	if ($Dbg) { "$($_.InnerXml)"; Pause-Execution; }
	$_.buildType | where { $_.id -match "$($parentproject)_$($parentproject)\w*$($currentbranch)" } | foreach {
		if ($Dbg) { "$($_.InnerXml)"; Pause-Execution; }
		$oldBuildConfigId = $_.id;
		$strippedConfig = ($oldBuildConfigId).replace("$($parentproject)_",'');
		
		$projectName = (($strippedConfig).replace($($currentbranch),'')).replace($parentproject,'');
		$newBuildConfigIdName = ($strippedConfig).replace($($currentbranch),$($targetbranch));
		$newBuildConfigId = ($oldBuildConfigId).replace($($currentbranch),$($targetbranch));
		$newBuildConfigName = ($_.name).replace($($currentbranch),$($targetbranch));
		$newBuildConfigDescription = ($_.description).replace($($currentbranch),$($targetbranch));
		$newBuildConfigUrlFrag = ($_.href).replace($($currentbranch),$($targetbranch));
		$newBuildConfigwebUrl= ($_.webUrl).replace($($currentbranch),$($targetbranch));
		
		write-verbose "`tprojectName = $projectName`n `
			`toldBuildConfigId = $oldBuildConfigId`n `
			`tnewBuildConfigId = $newBuildConfigId`n `
			`tnewBuildConfigIdName = $newBuildConfigIdName`n `
			`tnewBuildConfigName = $newBuildConfigName`n `
			`tnewBuildConfigDescription = $newBuildConfigDescription`n `
			`tnewBuildConfigUrlFrag = $newBuildConfigUrlFrag`n `
			`tnewBuildConfigwebUrl = $newBuildConfigwebUrl`n";
		if ($Dbg) { Pause-Execution; }
		
		write-verbose "`nEvaluating $newBuildConfigId now...";
		try {
			# Clone new Build config
			write-verbose "Cloning new Build config"
			$xmldata = [xml]"<newBuildTypeDescription name='$($newBuildConfigName)' sourceBuildTypeLocator='id:$($oldBuildConfigId)' copyAllAssociatedSettings='true' shareVCSRoots='false' />"
			$contenttype = "application/xml";
			$HTTPMethod = 'POST';
			$RESTURL = $ResturlProjectBuildTypes;
			$result = Run-RESTCommand $RESTURL $HTTPMethod $usercreds $xmldata $contenttype;
			if ($Dbg) { "$($result.InnerXml)`n`n"; Pause-Execution; }
			
			$RESTURLNewConfig = "$($ResturlBuildTypes)/id:$($newBuildConfigId)"
			# Pause new build config
			Set-BuildConfigPause $RESTURLNewConfig $usercreds 'true' $newBuildConfigId;

			Update-ConfigSettingsAndParams $RESTURLNewConfig $usercreds;
			
			write-verbose "Getting currently attached VCS roots"
			$HTTPMethod = 'GET';
			$RESTURL = "$($RESTURLNewConfig)/vcs-root-entries";
			$xmldata = [xml] (Run-RESTCommand $RESTURL $HTTPMethod $usercreds);
			if ($Dbg) { "$($xmldata.InnerXml)`n`n"; Pause-Execution; }
			
			$oldVCSRoot = [string] (Get-VCSRootData $xmldata $currentbranch)
			if ($Dbg) {  "Old VCS Root: $oldVCSRoot`n`n"; Pause-Execution; }
			
			if (!($oldVCSRoot -eq $null)) {
				$HTTPMethod = 'GET';
				$RESTURL = "$($RESTURLNewConfig)/vcs-root-entries/$($oldVCSRoot)";
				$xmldata = [xml] (Run-RESTCommand $RESTURL $HTTPMethod $usercreds);
				if ($Dbg) { "$($xmldata.InnerXml)"; Pause-Execution; }
				
				$idReplacedNodeValue = $(($oldVCSRoot).replace($currentbranch,$targetbranch));
				write-verbose "Updating VCS Root with $idReplacedNodeValue";
				
				$xmldata = [xml] (Update-VCRRootXMLData $xmldata $currentbranch $targetbranch);
				if ($Dbg) { "$($xmldata.InnerXml)`n`n"; Pause-Execution; }
				# Attach updated VCSRoot
				write-verbose "Attaching updated VCSRoot";
				$contenttype = "application/xml";
				$HTTPMethod = 'POST';
				$RESTURL = "$($RESTURLNewConfig)/vcs-root-entries";
				$result = [xml] (Run-RESTCommand $RESTURL $HTTPMethod $usercreds $xmldata $contenttype);
				if ($Dbg) { "$($xmldata.InnerXml)`n`n"; Pause-Execution; }
				
				write-verbose "Removing previous VCS Root: $oldVCSRoot";
				# Remove Old VCSRoot
				write-verbose "Removing Old VCS Root";
				$HTTPMethod = 'DELETE'; 
				$RESTURL = "$($RESTURLNewConfig)/vcs-root-entries/$($oldVCSRoot)";
				$result = Run-RESTCommand $RESTURL $HTTPMethod $usercreds;
				if ($Dbg) { "$result`n`n"; Pause-Execution; }
			}
			
			# Resume build config
			[int] $sleepTime = 2;
			"Pausing for $($sleepTime) second(s) to allow for API status to update";
			Start-Sleep $sleepTime;

			Set-BuildConfigPause $RESTURLNewConfig $usercreds 'false' $newBuildConfigId

		}
        catch {
            Write-Error -Exception $_.exception -ErrorAction stop;
        }
		finally {
			$count++;
			#if ($count -gt 0) {break;}
			Write-host "Updated $count site(s) so far..."
		}
	}
}

# TODO: Cleanup?
Write-host "Updated $count site(s) total."
 