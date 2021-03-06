#Force run as admin
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
if (-not $myWindowsPrincipal.IsInRole($adminRole)) {
    $scriptpath = $MyInvocation.MyCommand.Definition
    $scriptpaths = "'$scriptPath'"
    Start-Process -FilePath PowerShell.exe -Verb runAs -ArgumentList "& $scriptPaths"
    exit
    }

#If we're not using Area42 creds, then default to the domain of the creds we are using
if ((whoami) -match ".adm" -and (whoami) -notmatch "area42\\") {
    #$credsDomain = (whoami).split("\")[0].toUpper().replace("S","")
    Write-Host "Run the script again with AREA42 credentials."
    Read-Host
    exit
    }

$OutputArray = @()

foreach ($NetBiosDomainName in @("ACC","ACCROOT","AFMC")) {
    
    switch ($NetBiosDomainName) {
        "ACC" {
            $QueryDC = Get-ADDomainController -Server "acc.accroot.ds.af.smil.mil" | select -ExpandProperty hostname
            $DomainFQDN = "acc.accroot.ds.af.smil.mil"
            $DCOU = "OU=Domain Controllers,DC=acc,DC=accroot,DC=ds,DC=af,DC=smil,DC=mil"
            }
        "ACCROOT" {
            $QueryDC = Get-ADDomainController -Server "accroot.ds.af.smil.mil" | select -ExpandProperty hostname
            $DomainFQDN = "accroot.ds.af.smil.mil"
            $DCOU = "OU=Domain Controllers,DC=accroot,DC=ds,DC=af,DC=smil,DC=mil"
            }
        "AFMC" {
            $QueryDC = Get-ADDomainController -Server "afmc.ds.af.smil.mil" | select -ExpandProperty hostname
            $DomainFQDN = "afmc.ds.af.smil.mil"
            $DCOU = "OU=Domain Controllers,DC=afmc,DC=ds,DC=af,DC=smil,DC=mil"
            }
        }

    #Get all the DCs 
    $DCs = Get-ADComputer -Server $QueryDC -SearchBase $DCOU -Filter * | select -ExpandProperty dnshostname

    foreach ($dc in $DCs) {
        try {
            $info = Get-WmiObject -ComputerName $dc Win32_Operatingsystem -EA Stop #| select FreePhysicalMemory,TotalVisibleMemorySize,LastBootUpTime
            $memUtil = ($info.TotalVisibleMemorySize - $info.FreePhysicalMemory) * 100 / $info.TotalVisibleMemorySize
            $Uptime = ((get-date) - $info.ConvertToDateTime($info.LastBootUpTime)).TotalDays
            $FreeMem = $info.FreePhysicalMemory / 1MB
            $TotalMem = $info.TotalVisibleMemorySize / 1MB
            }
        catch {
            switch ($NetBiosDomainName) {
                "ACC" {
                    $RemoteDC = "ACC-DC-001.acc.accroot.ds.af.smil.mil"
                    if ($QueryDC-match "ACC-DC-00") {$RemoteDC = "MUHJ-DC-001.acc.accroot.ds.af.smil.mil"}
                    $RemoteDC = $dc
                    }
                "ACCROOT" {
                    $RemoteDC = "ACCROOT-DC-001.accroot.ds.af.smil.mil"
                    if ($QueryDC -match "ACCROOT-DC-00(1|2)") {$RemoteDC = "ACCROOT-DC-003.accroot.ds.af.smil.mil"}
                    $RemoteDC = $dc
                    }
                "AFMC" {
                    $RemoteDC = "ZHTV-DC-001P.afmc.ds.af.smil.mil"
                    if ($QueryDC -match "ZHTV-DC-001P") {$RemoteDC = "UHHZ-DC-001V.afmc.ds.af.smil.mil"}
                    $RemoteDC = $dc
                    }
                }
            try {
                $info = Invoke-Command -ComputerName $RemoteDC -ScriptBlock {param($dc);Get-WmiObject -ComputerName $dc Win32_Operatingsystem} -ArgumentList $dc -EA Stop
                $memUtil = ($info.TotalVisibleMemorySize - $info.FreePhysicalMemory) * 100 / $info.TotalVisibleMemorySize
                $Uptime = ((get-date) - $info.ConvertToDateTime($info.LastBootUpTime)).TotalDays
                $FreeMem = $info.FreePhysicalMemory / 1MB
                $TotalMem = $info.TotalVisibleMemorySize / 1MB
                }
            catch {$memUtil = "Could Not Remotely Access from $QueryDC or $remoteDC";$UpTime = $TotalMem = $FreeMem = "N/A"}
            }

        $OutputArray += New-Object PSObject -Property @{
            DC = $dc
            "MemUsage(%)" = $memUtil
            "UpTime(Days)" = $UpTime
            "FreeMem(GB)" = $FreeMem
            "TotalMem(GB)" = $TotalMem
            Domain = $DomainFQDN
            }
        }
    }

$timestamp = Get-Date -Format yyyy-MM-dd.HH-mm-ss
$OutputArray | sort Domain,DC | select DC,"MemUsage(%)",Domain,"UpTime(Days)","FreeMem(GB)","TotalMem(GB)" | Export-Csv -NoTypeInformation "$env:userprofile\desktop\ACCMemUtil_$timestamp.csv"
