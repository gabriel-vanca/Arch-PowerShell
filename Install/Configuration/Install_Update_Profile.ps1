if(!(Test-Path -path $PROFILE))  
{
    Remove-Item $PROFILE

    Write-Host "Old PowerShell profile has been deleted: " $PROFILE.AllUsersCurrentHost
}

#Download profile
https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Profile/Microsoft.PowerShell_profile.ps1 -o $PROFILE.AllUsersCurrentHost 

if(Test-Path -path $PROFILE.AllUsersCurrentHost)  
{    
    Write-Host "PowerShell profile has been succesfully created at: " $PROFILE.AllUsersCurrentHost
} else {
    Write-Error "Failed to create the PowerShell profile at: " $PROFILE.AllUsersCurrentHost
}

# Reload profile
& $profile