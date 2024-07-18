<#
.SYNOPSIS
Script to TeamCity Build Server with additional VCS Roots

.DESCRIPTION
Uses TeamCity REST api to Clone off new roots

.EXAMPLE
$creds = Get-Credential -Credential '';
Example of Credential input

.NOTES
Author: 
Last Update: 8-5-2016
#>

[CmdletBinding()]
Param (
	[string] $workdir = "$env:temp\TC-XML-Data",
	[string] $hostanddomainurl = '',
	[string] $RESTURL = '/httpAuth/app/rest/vcs-roots',
	[string] $currentbranch = '1605',
	[string[]] $newbranch = @('1606','1607','1608'),
	[System.Management.Automation.PSCredential] $usercreds = $null,
	[switch] $SkipCleanUp,
	[switch] $WhatIf
)

Begin {
	if (($hostanddomainurl -ne "") -and ($RESTURL -ne "")) {
		[string] $currentResturl = "$($hostanddomainurl)$($RESTURL)"
	}
	if (!(test-path $workdir )) {
		Write-Verbose "$workdir not found! `nCreating $workdir as it does not exist";
		md $workdir | out-null;
	}
	if ($usercreds -eq $null) {
		$usercreds = (Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message "Enter Credentials for your REST API connection");
	}
}

Process {
	Write-Host "Connecting to $currentResturl`n";
	$results = Invoke-RestMethod -Method GET -Uri $currentResturl -Credential $usercreds

	$results.'vcs-roots'.'vcs-root' | where {$_.id -like "IrisCd*$($currentbranch)"} | foreach { 
		Write-Host "Downloading XML info for $($_.id)";
		$Rootresults = Invoke-RestMethod -Method GET -Uri "$($hostanddomainurl)$($_.href)" -Credential $usercreds;
		$Rootresults.Save("$($workdir)\$(($_.id).replace($currentbranch,'')).xml");
	}


	$newbranch | foreach {
		$branch=$_; 
		Write-Verbose "Branch is $branch";
		$branchpath = "$($workdir)\$($branch)";
		Write-Verbose "Branchpath is $branchpath";
		if (!(test-path $branchpath)) {
			Write-Verbose "Creating $branchpath as it does not exist";
			md $branchpath | out-null;
		}
		
		Get-ChildItem $workdir -filter "*.xml" | foreach {
			$curfilename=$_;
			Write-Host "Working on $curfilename";
			$srcfile = "$($workdir)\$($curfilename.name)";
			$dstfile = "$($branchpath)\$($curfilename.name)";
			Write-Verbose "Copying $srcfile to $dstfile";
			copy $srcfile $dstfile
		}

		Get-ChildItem $branchpath -filter "*.xml" | foreach {
			$currentxmlconfig=$_;
			Write-Verbose "`nCurrent working config file is $currentxmlconfig";
			if (test-path "$($currentxmlconfig.fullname)") {
				Write-Host "Found $currentxmlconfig from $currentbranch, working to modify the config for $branch";
				$xml = [xml](Get-Content $currentxmlconfig.fullname)
				$xml.SelectNodes("//*") | foreach {
					$node=$_;
					@("id","name","value","href") | foreach {
						$nodename=$_;
						if ( $node.GetAttribute($nodename) | where { $_ -like "*$($currentbranch)*"} ) {
							$currentNodeValue = $node.GetAttribute($nodename);
							$replacedNodeValue = $(($currentNodeValue).replace($currentbranch,$branch));
							Write-Verbose "Found Node $nodename with value of $($currentNodeValue)";
							$node.SetAttribute($nodename, $replacedNodeValue);
							Write-Verbose "`tReplaced with new value of $replacedNodeValue";
						}
					}
				}
			}
			# Save back modified XML data
			Write-Verbose "Saving back $currentxmlconfig";
			$xml.Save($currentxmlconfig.fullname);
			
			# Upload the corrected files as new VCS roots in Team City
			$data = [xml](Get-Content $currentxmlconfig.fullname);
			Write-Host "Connecting to $currentResturl to POST back $currentxmlconfig for $branch";
			[xml] $results = Invoke-RestMethod -Method POST -Uri $currentResturl -Credential $usercreds -Body $data -ContentType "application/xml";
			$results.SelectNodes("//*") | foreach { 
				Write-Verbose "$_"; 
			}
		}
	}
}

End {
	if (!($SkipCleanUp)) {
		Write-Verbose "Cleaning up the $workdir folder";
		Remove-Item "$($workdir)" -Force -Recurse;
	}
	Write-Host "Script Complete...";
}