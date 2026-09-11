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

    Write-Host "Grabbing useful specs..." -ForegroundColor Cyan
    $CimSession = $null
    $DataGathered = $false

    # DATA GATHERING (WinRM or DCOM as Fallback)
    try {
        # attempt 1: WinRM
        $CimSession = New-CimSession -ComputerName $ComputerName -ErrorAction Stop
        
        $OS   = Get-CimInstance Win32_OperatingSystem -CimSession $CimSession -ErrorAction Stop
        $CS   = Get-CimInstance Win32_ComputerSystem -CimSession $CimSession -ErrorAction Stop
        $BIOS = Get-CimInstance Win32_BIOS -CimSession $CimSession -ErrorAction Stop
        $Net  = Get-CimInstance Win32_NetworkAdapterConfiguration -CimSession $CimSession -Filter "IPEnabled = 'True'" -ErrorAction SilentlyContinue
        $CPU  = Get-CimInstance Win32_Processor -CimSession $CimSession -ErrorAction Stop
        $Disk = Get-CimInstance Win32_LogicalDisk -CimSession $CimSession -Filter "DeviceID='C:'" -ErrorAction Stop
        $CSP  = Get-CimInstance Win32_ComputerSystemProduct -CimSession $CimSession -ErrorAction SilentlyContinue
        
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
            $CSP  = Get-CimInstance Win32_ComputerSystemProduct -CimSession $CimSession -ErrorAction SilentlyContinue
            
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
        
        $Manufacturer = $CS.Manufacturer
        $SN = $BIOS.SerialNumber
        $MfgDate = "Unknown"
        $ModelString = $CS.Model

        # SMART LENOVO LOGIC
        if ($Manufacturer -match "Lenovo") {
            
            # cleans up the device model string
            $FriendlyName = $CS.Model
            
            if ($CS.SystemSKUNumber -match "_FM_(.*)") {
                $FriendlyName = $Matches[1]
            } elseif ($CSP -and $CSP.Version -and $CSP.Version -notmatch "^Lenovo$|^ThinkPad$") {
                $FriendlyName = $CSP.Version
            }
            $ModelString = "$FriendlyName ($($CS.Model))"

            # attempt 1: query the smart battery 1st
            try {
                $Battery = Get-CimInstance -Namespace root\wmi -Class BatteryStaticData -CimSession $CimSession -ErrorAction Stop | Select-Object -First 1
                if ($Battery -and $Battery.ManufactureDate -gt 0) {
                    $DateInt = $Battery.ManufactureDate
                    $Day = $DateInt -band 31
                    $Month = ($DateInt -shr 5) -band 15
                    $Year = ($DateInt -shr 9) + 1980
                    
                    # only take battery date if it's realistic (prevents weird firmware glitches)
                    $CurrentYear = (Get-Date).Year
                    if ($Year -ge 2015 -and $Year -le $CurrentYear) {
                        $BatDate = Get-Date -Year $Year -Month $Month -Day $Day
                        $MfgDate = "$($BatDate.ToString('MMMM yyyy')) (captured via Battery Sensor)"
                    }
                }
            } catch {}

            # attempt 2: CPU Gen. Inference (foolproof fallback)
            if ($MfgDate -eq "Unknown") {
                $CpuName = $CPU.Name
                $CpuYear = $null
                
                # 1. check for explicit "Xth Gen" tag
                if ($CpuName -match "\b(\d{1,2})(?:th|st|nd|rd)\s+Gen") {
                    $gen = [int]$Matches[1]
                    if ($gen -ge 6 -and $gen -le 14) {
                        $CpuYear = 2010 + $gen
                    }
                }
                # 2. check for Intel Core Ultra (e.g. Ultra 5 125U) - 2024
                elseif ($CpuName -match "Ultra\s+[3579]\s+[12]\d{2}[A-Z]") {
                    $CpuYear = 2024
                } 
                # 3. fallback for Intel Core i-Series without the "Gen" tag (i7-8250U or i7-1255U)
                elseif ($CpuName -match "i[3579]-(\d+)") {
                    $modelNum = $Matches[1]
                    if ($modelNum.Length -eq 4) {
                        # handles both 8250 (Gen 8) and 1255 (Gen 12)
                        $firstTwo = [int]$modelNum.Substring(0, 2)
                        if ($firstTwo -ge 10) { $CpuYear = 2010 + $firstTwo } 
                        else { $CpuYear = 2010 + [int]$modelNum.Substring(0, 1) }
                    } elseif ($modelNum.Length -eq 5) {
                        # handles 12700 (Gen 12)
                        $CpuYear = 2010 + [int]$modelNum.Substring(0, 2)
                    }
                }
                # 4. check for AMD Ryzen series (Ryzen 7 5700U -> 5000 series)
                elseif ($CpuName -match "Ryzen\s+[3579].*?\b(\d)\d{3}") {
                    $gen = [int]$Matches[1]
                    if ($gen -ge 3 -and $gen -le 8) {
                        $CpuYear = 2016 + $gen
                    }
                }

                if ($CpuYear) {
                    $MfgDate = "Est. MFG Year: $CpuYear (via CPU Gen.)"
                }
            }
        } 
        
        # SMART HP LOGIC
        elseif ($Manufacturer -match "HP|Hewlett-Packard" -and $SN.Length -ge 6) {
            $ModelString = if ($CS.SystemSKUNumber) { "$($CS.Model) ($($CS.SystemSKUNumber))" } else { $($CS.Model) }
            
            try {
                $YearDigit = [int][string]$SN[3]
                $WeekDigit = [int]$SN.Substring(4, 2)
                $BaseYear = if ($YearDigit -ge 7) { 2010 } else { 2020 }
                $CalculatedYear = $BaseYear + $YearDigit
                
                $ApproxDate = (Get-Date -Year $CalculatedYear -Month 1 -Day 1).AddDays(($WeekDigit - 1) * 7)
                $MfgDate = "$($ApproxDate.ToString('MMMM yyyy')) (via HP SN Decode)"
            } catch {
                $MfgDate = "Parse Error (Check HP SN format)"
            }
        } 
        
        # FALLBACK LOGIC
        if ($MfgDate -eq "Unknown") {
            $MfgDate = if ($BIOS.ReleaseDate) { "$($BIOS.ReleaseDate.ToString('MMMM yyyy')) (BIOS Flashed Date)" } else { "Unknown" }
        }

        # storage calc for C:\ drive
        $CSizeGB = if ($Disk) { [math]::Round(($Disk.Size / 1GB), 2) } else { 0 }
        $CFreeGB = if ($Disk) { [math]::Round(($Disk.FreeSpace / 1GB), 2) } else { 0 }
        
        Write-Host "- - - DEVICE INFORMATION - - -" -ForegroundColor Yellow
        Write-Host "Logged On:         $CurrentUser"
        Write-Host "Device Model:      $ModelString"
        Write-Host "MFG Date:          $MfgDate" 
        Write-Host "Serial Number:     $SN"
        Write-Host "IPv4 Address:      $IPAddress"
        Write-Host "Windows Version:   $($OS.Caption) ($($OS.Version))"
        Write-Host "Current Uptime:    $UptimeString"
        
        Write-Host "`n- - - SPECS - - -" -ForegroundColor Yellow
        Write-Host "C Drive:           $CSizeGB GB (Free: $CFreeGB GB)"
        Write-Host "CPU:               $($CPU.Name)"
        Write-Host "RAM:               $RamGB GB"
    }

    # - - - OUTLOOK DATA FILES - - -
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
                    Write-Host "User: $($User.Name)     File: $($File.Name) | Size: $DisplaySize"
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
