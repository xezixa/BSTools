[CmdletBinding()]
param()

# loads AD module for username resolution
if (Get-Module -ListAvailable ActiveDirectory) {
    Import-Module ActiveDirectory
}

# keeps script running unless you type 'Q'
while ($true) {
    Clear-Host
    
    # prompt for target computer name, username, or full name
    $SearchTarget = Read-Host "Enter BlueStar Computer Name, Username, Employee Name | ('Q' to quit)"
    
    if ($SearchTarget -eq 'q' -or $SearchTarget -eq 'Q') { break }
    if ([string]::IsNullOrWhiteSpace($SearchTarget)) { continue }

    # DEVICE RESOLUTION LOGIC
    $ComputerName = $SearchTarget

    if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
        
        # if input doesn't look like a BlueStar computer name, try to resolve it
        if ($SearchTarget -notmatch "^BS(US|CA|MX|LA)\d+") {
            $SearchString = $SearchTarget
            
            # if no spaces, determine if it is a username or first name
            if ($SearchTarget -notmatch "\s") {
                try {
                    # attempt to find an AD User with this exact username (sAMAccountName)
                    $ADUser = Get-ADUser -Identity $SearchTarget -Properties GivenName, Surname -Server "bluestarinc.com" -ErrorAction Stop
                    
                    # if found, format to "first last" to match computer description
                    $SearchString = "$($ADUser.GivenName) $($ADUser.Surname)".Trim()
                    Write-Host "`n[*] Username '$SearchTarget' found. Full Name: $SearchString" -ForegroundColor Cyan
                } 
                catch {
                    # if Get-ADUser fails then it's not a valid username. treat it as a first name.
                    Write-Host "`n[*] No username match. Treating input as First Name: $SearchString" -ForegroundColor Cyan
                }
            } else {
                Write-Host "`n[*] Full Name detected. Searching for: $SearchString" -ForegroundColor Cyan
            }

            Write-Host "[*] Querying domain for associated computer(s)..." -ForegroundColor Yellow
            
            # prefix search for description
            $LDAPFilter = "(&(description=$SearchString*)(|(name=BSUS*)(name=BSLA*)(name=BSCA*)(name=BSMX*)))"
            
            # exec search against the domain
            $MatchedPCs = Get-ADComputer -LDAPFilter $LDAPFilter -Properties Description -Server "bluestarinc.com" -ErrorAction SilentlyContinue
            
            if ($MatchedPCs) {
                $PCArray = @($MatchedPCs) | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } | Sort-Object Name -Descending 
                
                Write-Host "`n[+] Found $($PCArray.Count) associated device(s) in AD. Pinging to find active machines..." -ForegroundColor Cyan
                
                # ping sweep to display only active machines
                $ActivePCs = @()
                foreach ($PC in $PCArray) {
                    if (Test-Connection -ComputerName $PC.Name -Count 1 -Quiet -ErrorAction SilentlyContinue) {
                        $ActivePCs += $PC
                    }
                }

                if ($ActivePCs.Count -eq 0) {
                    Write-Warning "Devices were found in AD for '$SearchString', but they are all currently offline."
                    Read-Host "`nPress Enter to reset..."
                    continue
                } elseif ($ActivePCs.Count -eq 1) {
                    $ComputerName = $ActivePCs[0].Name
                    Write-Host "[+] Detected active device: $ComputerName ($($ActivePCs[0].Description))" -ForegroundColor Green
                } else {
                    # if multiple active devices found; prompt user to select one
                    Write-Host "`n[!] Multiple ACTIVE devices found under '$SearchString':" -ForegroundColor Yellow
                    for ($i = 0; $i -lt $ActivePCs.Count; $i++) {
                        Write-Host "  [$($i + 1)] $($ActivePCs[$i].Name) - $($ActivePCs[$i].Description)"
                    }
                    
                    $Selection = 0
                    while ($Selection -lt 1 -or $Selection -gt $ActivePCs.Count) {
                        $Input = Read-Host "`nEnter the number of the device you want to query"
                        if ([int]::TryParse($Input, [ref]$Selection)) {
                            if ($Selection -lt 1 -or $Selection -gt $ActivePCs.Count) {
                                Write-Host "Invalid selection. Please pick a number from the list." -ForegroundColor Red
                            }
                        }
                    }
                    $ComputerName = $ActivePCs[$Selection - 1].Name
                    Write-Host "[+] Selected: $ComputerName" -ForegroundColor Green
                }
            } else {
                Write-Warning "[-] No computers found starting with BSUS, BSLA, BSCA, or BSMX assigned to $SearchString."
                Read-Host "`nPress Enter to try again..."
                continue
            }
        }
    } else {
        if ($SearchTarget -notmatch "^BS(US|CA|MX|LA)") {
            Write-Warning "ActiveDirectory module missing. Searching by name/username requires RSAT tools installed."
        }
    }
    # -------------------------------

    Write-Host "`nEstablishing connection to $ComputerName..." -ForegroundColor Cyan

    # final ping check (primarily for manually entered computer names)
    if (-not (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        Write-Warning "Computer '$ComputerName' is offline or unreachable."
        Read-Host "`nPress Enter to try again..."
        continue
    }

    Write-Host "Grabbing useful specs..." -ForegroundColor Cyan
    $CimSession = $null
    $DataGathered = $false
    $ProtocolUsed = "None"

    # DATA GATHERING (WinRM with DCOM Fallback)
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
        $ProtocolUsed = "WinRM"
    } catch {
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
            $ProtocolUsed = "DCOM"
        } catch {
            Write-Warning "Remote management failed on $ComputerName. Both WinRM and DCOM are unreachable."
        }
    }

    # DISPLAY SYSTEM INFO
    if ($DataGathered) {
        Write-Host "Using Protocol: $ProtocolUsed" -ForegroundColor Green
        
        $RamGB = [math]::Round(($CS.TotalPhysicalMemory / 1GB), 2)
        $Uptime = (Get-Date) - $OS.LastBootUpTime
        $UptimeString = "$($Uptime.Days) Days, $($Uptime.Hours) Hours, $($Uptime.Minutes) Minutes"
        $IPAddress = if ($Net) { $Net.IPAddress[0] } else { "Unknown" }
        $CurrentUser = if ($CS.UserName) { $CS.UserName } else { "None / System" }
        
        $Manufacturer = $CS.Manufacturer
        $SN = $BIOS.SerialNumber
        $MfgDate = "Unknown"
        $ModelString = $CS.Model

        # LENOVO/HP LOGIC
        if ($Manufacturer -match "Lenovo") {
            $FriendlyName = $CS.Model
            if ($CS.SystemSKUNumber -match "_FM_(.*)") {
                $FriendlyName = $Matches[1]
            } elseif ($CSP -and $CSP.Version -and $CSP.Version -notmatch "^Lenovo$|^ThinkPad$") {
                $FriendlyName = $CSP.Version
            }
            $ModelString = "$FriendlyName ($($CS.Model))"

            try {
                $Battery = Get-CimInstance -Namespace root\wmi -Class BatteryStaticData -CimSession $CimSession -ErrorAction Stop | Select-Object -First 1
                if ($Battery -and $Battery.ManufactureDate -gt 0) {
                    $DateInt = $Battery.ManufactureDate
                    $Day = $DateInt -band 31
                    $Month = ($DateInt -shr 5) -band 15
                    $Year = ($DateInt -shr 9) + 1980
                    
                    $CurrentYear = (Get-Date).Year
                    if ($Year -ge 2015 -and $Year -le $CurrentYear) {
                        $BatDate = Get-Date -Year $Year -Month $Month -Day $Day
                        $MfgDate = "$($BatDate.ToString('MMMM yyyy')) (via Battery Sensor)"
                    }
                }
            } catch {}
        } 
        
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
        
        # CPU INFERENCE FALLBACK
        if ($MfgDate -eq "Unknown" -or $MfgDate -match "Parse Error") {
            $CpuName = $CPU.Name
            $CpuYear = $null
            
            if ($CpuName -match "\b(\d{1,2})(?:th|st|nd|rd)\s+Gen") {
                $gen = [int]$Matches[1]
                if ($gen -ge 6 -and $gen -le 14) { $CpuYear = 2010 + $gen }
            } 
            elseif ($CpuName -match "Core(?:\(TM\))?\s+(?:Ultra\s+)?[3579]\s+([12])\d{2}[A-Z]") {
                $CpuYear = 2023 + [int]$Matches[1]
            } 
            elseif ($CpuName -match "i[3579]-(\d+)") {
                $modelNum = $Matches[1]
                if ($modelNum.Length -eq 4) {
                    $firstTwo = [int]$modelNum.Substring(0, 2)
                    if ($firstTwo -ge 10) { $CpuYear = 2010 + $firstTwo } 
                    else { $CpuYear = 2010 + [int]$modelNum.Substring(0, 1) }
                } elseif ($modelNum.Length -eq 5) {
                    $CpuYear = 2010 + [int]$modelNum.Substring(0, 2)
                }
            } 
            elseif ($CpuName -match "Ryzen\s+[3579].*?\b(\d)\d{3}") {
                $gen = [int]$Matches[1]
                if ($gen -ge 3 -and $gen -le 8) { $CpuYear = 2016 + $gen }
            }

            if ($CpuYear) {
                $MfgDate = "Est. Model Year: $CpuYear (via CPU Gen.)"
            }
        }

        # LAST RESORT BIOS FALLBACK
        if ($MfgDate -eq "Unknown" -or $MfgDate -match "Parse Error") {
            $MfgDate = if ($BIOS.ReleaseDate) { "$($BIOS.ReleaseDate.ToString('MMMM yyyy')) (BIOS Flashed Date)" } else { "Unknown" }
        }

        $CSizeGB = if ($Disk) { [math]::Round(($Disk.Size / 1GB), 2) } else { 0 }
        $CFreeGB = if ($Disk) { [math]::Round(($Disk.FreeSpace / 1GB), 2) } else { 0 }
        
        Write-Host "`n- - - DEVICE INFORMATION - - -" -ForegroundColor Yellow
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

    # OUTLOOK DATA FILES
    Write-Host "`n- - - OUTLOOK DATA FILE CHECK - - -" -ForegroundColor Yellow
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
            Write-Host "No Outlook data file found." -ForegroundColor Gray
        }
    } else {
        Write-Warning "Could not access administrative share to (\\$ComputerName\C$). This machine may be offline, blocking SMB, or you lack local admin rights."
    }
    
    # cleans up session memory before moving to next PC
    if ($CimSession) {
        Remove-CimSession $CimSession -ErrorAction SilentlyContinue
    }

    Write-Host "`n"
    Read-Host "Press Enter to search another computer..."
}
