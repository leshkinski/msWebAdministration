function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name
    )

    $Ensure = "Absent"
    $State  = "Stopped"

    #need to import explicitly to run for IIS:\AppPools
    Import-Module WebAdministration

    if(!(Get-Module -ListAvailable -Name WebAdministration))
    {
        Throw "Please ensure that WebAdministration module is installed."
    }

    $AppPool = Get-Item -Path IIS:\AppPools\* | ? {$_.name -eq $Name}

    if($AppPool -ne $null)
    {
        $Ensure       = "Present"
        $State        = $AppPool.state
        $IdentityType = $AppPool.processModel.identityType
        If ($AppPool.processModel.Username -and $AppPool.processModel.Password)
        {
           $Cred = New-Object System.Management.Automation.PSCredential($AppPool.processModel.Username,(ConvertTo-SecureString -AsPlainText -Force -String $AppPool.processModel.Password))
        }
    }

    $returnValue = @{
        Name         = $Name
        Ensure       = $Ensure
        State        = $State
        IdentityType = $IdentityType
        Credential   = $Cred
    }

    return $returnValue
}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure = "Present",

        [ValidateSet("Started","Stopped")]
        [System.String]
        $State = "Started",

        [ValidateSet("SpecificUser","ApplicationPoolIdentity")]
        [System.String]
        $IdentityType,

        [ValidateScript(
        {
            $IdentityType -eq "SpecificUser"
        })]
        [System.Management.Automation.PSCredential]
        $Credential
    )

    if($Ensure -eq "Absent")
    {
        Write-Verbose("Removing the Web App Pool")
        Remove-WebAppPool $Name
    }
    else
    {
        $AppPool = Get-TargetResource -Name $Name
        if($AppPool.Ensure -ne "Present")
        {
            Write-Verbose("Creating the Web App Pool")
            New-WebAppPool $Name
            $AppPool = Get-TargetResource -Name $Name
        }

        if($AppPool.State -ne $State)
        {
            ExecuteRequiredState -Name $Name -State $State
        }
        if($IdentityType -and $IdentityType -ne $AppPool.identityType)
        {
            Write-Verbose "Setting AppPool IdentityType"
            $ApplicationPool = Get-Item -Path IIS:\AppPools\* | ? {$_.name -eq $Name}
            $ApplicationPool.processModel.identityType = $IdentityType
            $ApplicationPool | Set-Item
        }
        if($Credential) 
        { 
            if($Credential.Username -ne $AppPool.Credential.Username -or
                [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)) -ne
                [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AppPool.Credential.Password)))
            {
                Write-Verbose "Setting Credential"
                $ApplicationPool = Get-Item -Path IIS:\AppPools\* | ? {$_.name -eq $Name}
                $ApplicationPool.processModel.Username = $Credential.Username
                $ApplicationPool.processModel.Password = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password))
                $ApplicationPool | Set-Item
            }
        }
        else
        {
            Write-Verbose "Removing Credential information"
            $ApplicationPool = Get-Item -Path IIS:\AppPools\* | ? {$_.name -eq $Name}
            $ApplicationPool.processModel.Username = ""
            $ApplicationPool.processModel.Password = ""
            $ApplicationPool | Set-Item
        }
    }
}


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure  = "Present",

        [ValidateSet("Started","Stopped")]
        [System.String]
        $State = "Started",

        [ValidateSet("SpecificUser","ApplicationPoolIdentity")]
        [System.String]
        $IdentityType,

        [ValidateScript(
        {
            $IdentityType -eq "SpecificUser"
        })]
        [System.Management.Automation.PSCredential]
        $Credential
    )
    $WebAppPool = Get-TargetResource -Name $Name

    if($Ensure -eq "Present")
    {
        if($WebAppPool.Ensure -eq $Ensure -and $WebAppPool.State -eq $state)
                     
        {
            if(-not $Credential)
            {
                return $true
            }
            elseif($Credential.Username -eq $WebAppPool.Credential.Username -and
                [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)) -eq
                [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($WebAppPool.Credential.Password)))
            {
                return $true
            }
        }
    }
    elseif($WebAppPool.Ensure -eq $Ensure)
    {
        return $true
    }



    return $false
}


function ExecuteRequiredState([string] $Name, [string] $State)
{
    if($State -eq "Started")
    {
        Write-Verbose("Starting the Web App Pool")
        start-WebAppPool -Name $Name
    }
    else
    {
        Write-Verbose("Stopping the Web App Pool")
        Stop-WebAppPool -Name $Name
    }
}

Export-ModuleMember -Function *-TargetResource