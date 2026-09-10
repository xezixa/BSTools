[CmdletBinding()]
param()

# keeps script running unless you type 'Q'
while ($true) {
    Clear-Host
    
    # prompt for target computer name on domain
    $ComputerName = Read-Host "Enter BlueStar Device Name ('Q' to quit)"
    
    if ($ComputerName -eq 'q' -or $ComputerName -eq 'Q') { break }
    if ([string]::IsNullOrWhiteSpace($ComputerName)) { continue }

    Write-Host "`nPinging $ComputerName..." -ForegroundColor Cyan

    if (-not (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        Write-Warning "Computer '$ComputerName' is offline or unreachable."
        Read-Host "`nPress Enter to try again..."
        continue
    }

    Write-Host "Finding useful specs..." -ForegroundColor Cyan
    $CimSession = $null
    $DataGathered = $false

    # --- DATA GATHERING (WinRM with DCOM Fallback) ---
    try {
        # attempt 1: WinRM
        $CimSession = New-CimSession -ComputerName $ComputerName -ErrorAction Stop
        
        $OS   = Get-CimInstance Win32_OperatingSystem -CimSession $CimSession -ErrorAction Stop
        $CS   = Get-CimInstance Win32_ComputerSystem -CimSession $CimSession -ErrorAction Stop
        $BIOS = Get-CimInstance Win32_BIOS -CimSession $CimSession -ErrorAction Stop
        $Net  = Get-CimInstance Win32_NetworkAdapterConfiguration -CimSession $CimSession -Filter "IPEnabled = 'True'" -ErrorAction SilentlyContinue
        $CPU  = Get-CimInstance Win32_Processor -CimSession $CimSession -ErrorAction Stop
        $Disk = Get-CimInstance Win32_LogicalDisk -CimSession $CimSession -Filter "DeviceID='C:'" -ErrorAction Stop
        
        $DataGathered = $true
    } catch {
        Write-Host " [!] WinRM query failed - Invalid XML/blocked port. Falling back to DCOM..." -ForegroundColor DarkYellow
        if ($CimSession) { Remove-CimSession $CimSession -ErrorAction SilentlyContinue }
        
        try {
            # attempt 2: DCOM fallback
            $DcomOption = New-CimSessionOption -Protocol Dcom
            $CimSession = New-CimSession -ComputerName $ComputerName -SessionOption $DcomOption -ErrorAction Stop
            
            $OS   = Get-CimInstance Win32_OperatingSystem -CimSession $CimSession -ErrorAction Stop
            $CS   = Get-CimInstance Win32_ComputerSystem -CimSession $CimSession -ErrorAction Stop
            $BIOS = Get-CimInstance Win32_BIOS -CimSession $CimSession -ErrorAction Stop
            $Net  = Get-CimInstance Win32_NetworkAdapterConfiguration -CimSession $CimSession -Filter "IPEnabled = 'True'" -ErrorAction SilentlyContinue
            $CPU  = Get-CimInstance Win32_Processor -CimSession $CimSession -ErrorAction Stop
            $Disk = Get-CimInstance Win32_LogicalDisk -CimSession $CimSession -Filter "DeviceID='C:'" -ErrorAction Stop
            
            $DataGathered = $true
        } catch {
            Write-Warning "Remote management failed on $ComputerName. Both WinRM and DCOM are unreachable."
        }
    }

    # --- DISPLAY SYSTEM INFO ---
    if ($DataGathered) {
        # calc & variables
        $RamGB = [math]::Round(($CS.TotalPhysicalMemory / 1GB), 2)
        $Uptime = (Get-Date) - $OS.LastBootUpTime
        $UptimeString = "$($Uptime.Days) Days, $($Uptime.Hours) Hours, $($Uptime.Minutes) Minutes"
        $IPAddress = if ($Net) { $Net.IPAddress[0] } else { "Unknown" }
        $CurrentUser = if ($CS.UserName) { $CS.UserName } else { "None / System" }
        $MfgDate = if ($BIOS.ReleaseDate) { $BIOS.ReleaseDate.ToString('yyyy-MM-dd') } else { "Unknown" }

        # storage calc for C:\ drive
        $CSizeGB = if ($Disk) { [math]::Round(($Disk.Size / 1GB), 2) } else { 0 }
        $CFreeGB = if ($Disk) { [math]::Round(($Disk.FreeSpace / 1GB), 2) } else { 0 }
        
        Write-Host "--- SYSTEM INFORMATION ---" -ForegroundColor Yellow
        Write-Host "Logged On:       $CurrentUser"
        Write-Host "Device Model:      $($CS.Model)"
        Write-Host "Serial Number:   $($BIOS.SerialNumber)"
        Write-Host "Mfg Date:        $MfgDate"
        Write-Host "IPv4 Address:            $IPAddress"
        Write-Host "Windows Version: $($OS.Caption) ($($OS.Version))"
        Write-Host "Current Uptime:          $UptimeString"
        
        Write-Host "`n--- SPECS ---" -ForegroundColor Yellow
        Write-Host "C:\ Size:   $CSizeGB GB (Free: $CFreeGB GB)"
        Write-Host "CPU:             $($CPU.Name)"
        Write-Host "RAM:       $RamGB GB"
    }

    # --- OUTLOOK DATA FILES ---
    Write-Host "`n--- OUTLOOK DATA FILES ---" -ForegroundColor Yellow
    $UserProfilesPath = "\\$ComputerName\C$\Users"
    
    if (Test-Path $UserProfilesPath) {
        $Users = Get-ChildItem $UserProfilesPath -Directory -ErrorAction SilentlyContinue
        $FoundOutlookFiles = $false
        
        foreach ($User in $Users) {
            $OutlookPath = Join-Path $User.FullName "AppData\Local\Microsoft\Outlook"
            
            if (Test-Path $OutlookPath -ErrorAction SilentlyContinue) {
                $Files = Get-ChildItem -Path $OutlookPath -Include *.ost, *.pst -Recurse -File -ErrorAction SilentlyContinue
                
                foreach ($File in $Files) {
                    $FoundOutlookFiles = $true
                    $FileSizeMB = [math]::Round(($File.Length / 1MB), 2)
                    $FileSizeGB = [math]::Round(($File.Length / 1GB), 2)
                    
                    $DisplaySize = if ($FileSizeGB -ge 1) { "$FileSizeGB GB" } else { "$FileSizeMB MB" }
                    Write-Host "User: $($User.Name) | File: $($File.Name) | Size: $DisplaySize"
                }
            }
        }
        
        if (-not $FoundOutlookFiles) {
            Write-Host "No Outlook data files found." -ForegroundColor Gray
        }
    } else {
        Write-Warning "Could not access administrative share to (\\$ComputerName\C$). This machine may be offline, blocking SMB, or you lack local admin rights."
    }
    
    # cleans up session memory before moving to the next PC
    if ($CimSession) {
        Remove-CimSession $CimSession -ErrorAction SilentlyContinue
    }

    Write-Host "`n"
    Read-Host "Press Enter to search another computer..."
}
