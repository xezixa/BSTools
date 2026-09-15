[CmdletBinding()] 
param() 

# loads AD module for username resolution 
if (Get-Module -ListAvailable ActiveDirectory) { 
    Import-Module ActiveDirectory 
} 

# keeps script running unless you type 'Q' 
while ($true) { 
    Clear-Host 
    
    # reset search state
    $ADUser = $null
    $SearchString = $null

    # cool banner
    Write-Host "          =================BSTools=================" -ForegroundColor Blue
    Write-Host "                  BlueStarIT Lookup Tool v1.8" -ForegroundColor White
    Write-Host "                  Developed by: Chase Bezilla" -ForegroundColor DarkGray
    Write-Host "                   For BlueStar, Inc. (2026)" -ForegroundColor DarkGray
    Write-Host "          ============github.com/xezixa============" -ForegroundColor Blue
    
    # prompt for target computer name, username, or full name 
    Write-Host "`n[?] Enter BlueStar Computer Name, Username, or Employee Name: " -ForegroundColor Yellow -NoNewLine
    $SearchTarget = Read-Host

    Write-Host "`n---------------------------------------------------" -ForegroundColor Yellow
    
    if ($SearchTarget -eq 'q' -or $SearchTarget -eq 'Q') { break } 
    if ([string]::IsNullOrWhiteSpace($SearchTarget)) { continue } 

    # DEVICE RESOLUTION LOGIC 
    $ComputerName = $SearchTarget 
    $ComputerDesc = ""

    if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) { 
        
        # if input doesn't look like a BlueStar computer name, try to resolve it anyway
        if ($SearchTarget -notmatch "^BS(US|CA|MX|LA)\d+") { 
            $SearchString = $SearchTarget 
            
            # if no spaces, determine if it is a username or first name 
            if ($SearchTarget -notmatch "\s") { 
                try { 
                    # attempt to find an AD User with this exact username (sAMAccountName) 
                    $ADUser = Get-ADUser -Identity $SearchTarget -Properties GivenName, Surname, DisplayName, Office, Title, Department, Manager, Mail, PasswordLastSet, "msDS-UserPasswordExpiryTimeComputed", PasswordNeverExpires, physicalDeliveryOfficeName -Server "bluestarinc.com" -ErrorAction Stop 
                    
                    # if found, format to "first last" to match computer description 
                    $SearchString = "$($ADUser.GivenName) $($ADUser.Surname)".Trim() 
                    Write-Host "`n[*] Username Found!: '$SearchTarget' | Employee Name: $SearchString" -ForegroundColor Cyan 
                }  
                catch { 
                    # if Get-ADUser fails then it's not a valid username. treat it as a first name. 
                    Write-Host "`n[*] No exact username match. Treating input as First Name: $SearchString" -ForegroundColor Cyan 
                } 
            } else { 
                Write-Host "`n[+] Full Name detected! Searching for: $SearchString" -ForegroundColor DarkGreen 
            } 

            Write-Host "[-] Searching for computer(s)..." -ForegroundColor Gray 
            
            # prefix search for description 
            $LDAPFilter = "(&(description=$SearchString*)(|(name=BSUS*)(name=BSLA*)(name=BSCA*)(name=BSMX*)))" 
            
            # exec search against the domain 
            $MatchedPCs = Get-ADComputer -LDAPFilter $LDAPFilter -Properties Description -Server "bluestarinc.com" -ErrorAction SilentlyContinue 
            
            if ($MatchedPCs) { 
                $PCArray = @($MatchedPCs) | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } | Sort-Object Name -Descending  
                
                Write-Host "[+] Device(s) detected. Pinging to ensure connection..." -ForegroundColor DarkGreen 
                
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
                    $ComputerDesc = $ActivePCs[0].Description
                    Write-Host "[+] Beginning lookup on: $ComputerName ($ComputerDesc)" -ForegroundColor DarkGreen 
                } else { 
                    # if multiple active devices found; prompt user to select one 
                    Write-Host "`n[!] Multiple ACTIVE devices found under '$SearchString':" -ForegroundColor Red 
                    for ($i = 0; $i -lt $ActivePCs.Count; $i++) { 
                        Write-Host "  [$($i + 1)] $($ActivePCs[$i].Name) - $($ActivePCs[$i].Description)" 
                    } 
                    
                    $Selection = 0 
                    while ($Selection -lt 1 -or $Selection -gt $ActivePCs.Count) { 
                        Write-Host "`n[?] Enter the number of the device you want to query: " -NoNewline -ForegroundColor Yellow
                        $Input = Read-Host 
                        if ([int]::TryParse($Input, [ref]$Selection)) { 
                            if ($Selection -lt 1 -or $Selection -gt $ActivePCs.Count) { 
                                Write-Host "Invalid selection. Please pick a number from the list." -ForegroundColor Red 
                            } 
                        } 
                    } 
                    $ComputerName = $ActivePCs[$Selection - 1].Name 
                    $ComputerDesc = $ActivePCs[$Selection - 1].Description
                    Write-Host "`n[+] Beginning lookup on: $ComputerName ($ComputerDesc)" -ForegroundColor DarkGreen 
                } 
            } else { 
                Write-Warning "[-] No computers found starting with BSUS, BSLA, BSCA, or BSMX assigned to $SearchString." 
                Read-Host "`nPress Enter to try again..." 
                continue 
            } 
        } else {
            Write-Host "`n[+] Beginning lookup on: $ComputerName" -ForegroundColor DarkGreen
        }
    } else { 
        if ($SearchTarget -notmatch "^BS(US|CA|MX|LA)") { 
            Write-Warning "ActiveDirectory module missing. Searching by name/username requires RSAT tools installed." 
        } 
    } 
    # ------------------------------- 

    Write-Host "`n---------------------------------------------------" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "             - Connected to: $ComputerName -" -ForegroundColor Green
    Write-Host ""
    Write-Host "[-] Grabbing useful information..." -ForegroundColor White

    # final ping check (primarily for manually entered computer names) 
    if (-not (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue)) { 
        Write-Warning "Computer '$ComputerName' is offline or unreachable." 
        Read-Host "`nPress Enter to try again..." 
        continue 
    } 

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
            # attempt 2: DCOM 
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

    # DISPLAY SYSTEM & ACCOUNT INFO 
    if ($DataGathered) { 
        Write-Host "[*] Protocol Used: $ProtocolUsed" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "---------------------------------------------------`n" -ForegroundColor Yellow
        
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
                $MfgDate = "$CpuYear (via CPU Gen.)" 
            } 
        } 

        # LAST RESORT BIOS FALLBACK 
        if ($MfgDate -eq "Unknown" -or $MfgDate -match "Parse Error") { 
            $MfgDate = if ($BIOS.ReleaseDate) { "$($BIOS.ReleaseDate.ToString('MMMM yyyy')) (BIOS Flashed Date)" } else { "Unknown" } 
        } 

        $CSizeGB = if ($Disk) { [math]::Round(($Disk.Size / 1GB), 2) } else { 0 } 
        $CFreeGB = if ($Disk) { [math]::Round(($Disk.FreeSpace / 1GB), 2) } else { 0 } 

        # ACCOUNT RESOLUTION LOGIC
        $ADAccount = $null
        $TargetUsername = $null

        if ($CurrentUser -and $CurrentUser -ne "None / System") {
            $TargetUsername = $CurrentUser.Split('\')[-1]
        } elseif ($ADUser) {
            $TargetUsername = $ADUser.sAMAccountName
        }

        if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
            if ($TargetUsername) {
                $ADAccount = Get-ADUser -Identity $TargetUsername -Properties DisplayName, Office, Title, Department, Manager, sAMAccountName, Mail, PasswordLastSet, "msDS-UserPasswordExpiryTimeComputed", PasswordNeverExpires, physicalDeliveryOfficeName -Server "bluestarinc.com" -ErrorAction SilentlyContinue
            } elseif ($SearchString -and ($SearchTarget -notmatch "^BS(US|CA|MX|LA)\d+")) {
                $ADAccount = Get-ADUser -Filter "DisplayName -like '$SearchString*' -or Name -like '$SearchString*'" -Properties DisplayName, Office, Title, Department, Manager, sAMAccountName, Mail, PasswordLastSet, "msDS-UserPasswordExpiryTimeComputed", PasswordNeverExpires, physicalDeliveryOfficeName -Server "bluestarinc.com" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
        }

        # ACCOUNT INFORMATION DISPLAY
        Write-Host "- - - ACCOUNT INFORMATION - - -" -ForegroundColor Blue
        Write-Host ""
        if ($ADAccount) {
            $Username = $ADAccount.sAMAccountName
            $FullName = if ($ADAccount.DisplayName) { $ADAccount.DisplayName } else { "$($ADAccount.GivenName) $($ADAccount.Surname)".Trim() }
            $EmailAddress = if ($ADAccount.Mail) { $ADAccount.Mail } elseif ($ADAccount.UserPrincipalName) { $ADAccount.UserPrincipalName } else { "None" }

            $Office = if ($ADAccount.Office) { $ADAccount.Office } elseif ($ADAccount.physicalDeliveryOfficeName) { $ADAccount.physicalDeliveryOfficeName } else { "None" }
            $Department = if ($ADAccount.Department) { $ADAccount.Department } else { "None" }
            $Position = if ($ADAccount.Title) { $ADAccount.Title } else { "None" }
            
            $ReportsTo = "None"
            if ($ADAccount.Manager) {
                if ($ADAccount.Manager -match "^CN=([^,]+)") {
                    $ReportsTo = $Matches[1]
                } else {
                    $ReportsTo = $ADAccount.Manager
                }
            }

            $PasswordLastSet = if ($ADAccount.PasswordLastSet) { $ADAccount.PasswordLastSet.ToString("MM/dd/yyyy hh:mm tt") } else { "Unknown" }

            $PasswordExpires = "Unknown"
            if ($ADAccount.PasswordNeverExpires) {
                $PasswordExpires = "Never"
            } elseif ($ADAccount."msDS-UserPasswordExpiryTimeComputed") {
                $val = $ADAccount."msDS-UserPasswordExpiryTimeComputed"
                try {
                    if ($val -eq 0x7FFFFFFFFFFFFFFF) {
                        $PasswordExpires = "Never"
                    } elseif ($val -is [int64] -or $val -is [long]) {
                        $PasswordExpires = ([DateTime]::FromFileTime($val)).ToString("MM/dd/yyyy hh:mm tt")
                    } elseif ($val -is [DateTime]) {
                        $PasswordExpires = $val.ToString("MM/dd/yyyy hh:mm tt")
                    }
                } catch {
                    $PasswordExpires = "Calculation Error"
                }
            }

            Write-Host "Username:           $Username"
            Write-Host "Full Name:          $FullName"
            Write-Host "Email Address:      $EmailAddress`n"

            Write-Host "Office:             $Office"
            Write-Host "Department:         $Department"
            Write-Host "Position:           $Position"
            Write-Host "Reports To:         $ReportsTo`n"

            Write-Host "Password Last Set:  $PasswordLastSet"
            Write-Host "Password Expires:   $PasswordExpires`n"
        } else {
            Write-Host " [~] No active domain account detected for this session.`n" -ForegroundColor DarkGray
        }
        Write-Host ""
        
        # DEVICE INFORMATION DISPLAY
        Write-Host "- - - DEVICE INFORMATION - - -" -ForegroundColor Blue
        Write-Host ""
        Write-Host "Device Name:        $ComputerName"
        Write-Host "Logged On:          $CurrentUser`n"

        Write-Host "Device Model:       $ModelString" 
        Write-Host "Est. MFG Year:      $MfgDate"  
        Write-Host "Serial Number:      $SN`n" 

        Write-Host "IPv4 Address:       $IPAddress" 
        Write-Host "Windows Version:    $($OS.Caption) ($($OS.Version))" 
        Write-Host "Current Uptime:     $UptimeString`n" 
        Write-Host ""

        Write-Host "- - - SPECIFICATIONS  - - -" -ForegroundColor Blue
        Write-Host ""
        Write-Host "CPU:                $($CPU.Name)" 
        Write-Host "C Drive:            $CSizeGB GB (Free: $CFreeGB GB)" 
        Write-Host "RAM:                $RamGB GB`n" 
        Write-Host ""
    } 

    $UserProfilesPath = "\\$ComputerName\C$\Users" 
    
    if (Test-Path $UserProfilesPath) { 
        
        # determine the target user (Currently Logged On)
        $Users = @()
        if ($CurrentUser -and $CurrentUser -ne "None / System") {
            $ActiveUserFolder = $CurrentUser.Split('\')[-1]
            $ActiveUserPath = Join-Path $UserProfilesPath $ActiveUserFolder
            
            if (Test-Path $ActiveUserPath) {
                $Users += [PSCustomObject]@{
                    Name = $ActiveUserFolder
                    FullName = $ActiveUserPath
                }
            }
        }
        
        # OUTLOOK DATA FILE CHECKER
        Write-Host "- - - OUTLOOK DATA FILE CHECKER - - -" -ForegroundColor Blue
        Write-Host ""
        
        $FoundOutlookFiles = $false 
        
        foreach ($User in $Users) { 
            $OstPath = Join-Path $User.FullName "AppData\Local\Microsoft\Outlook" 
            $PstPath = Join-Path $User.FullName "Documents\Outlook Files"
            
            $OstFiles = @()
            $PstFiles = @()

            if (Test-Path $OstPath -ErrorAction SilentlyContinue) { 
                $OstFiles = Get-ChildItem -Path $OstPath -Filter *.ost -File -ErrorAction SilentlyContinue 
                $PstFiles += Get-ChildItem -Path $OstPath -Filter *.pst -File -ErrorAction SilentlyContinue
            } 
            
            if (Test-Path $PstPath -ErrorAction SilentlyContinue) {
                $PstFiles += Get-ChildItem -Path $PstPath -Filter *.pst -File -ErrorAction SilentlyContinue
            }

            if ($OstFiles.Count -gt 0 -or $PstFiles.Count -gt 0) {
                foreach ($File in $OstFiles) { 
                    $FoundOutlookFiles = $true 
                    $FileSizeGB = [math]::Round(($File.Length / 1GB), 2) 
                    $Pct = [math]::Round((($File.Length / 1GB) / 50) * 100, 1)
                    
                    $LocalDir = $File.Directory.FullName.Replace("\\$ComputerName\C$", "C:").Replace("\\$ComputerName\c$", "C:")
                    
                    Write-Host "Live Data (.OST)" -ForegroundColor Magenta
                    Write-Host "File Name:          $($File.Name)" -ForegroundColor Gray
                    Write-Host "File Size:          $FileSizeGB GB / 50 GB | $Pct% Full" -ForegroundColor Gray
                    Write-Host "Location:           $LocalDir" -ForegroundColor Gray
                    Write-Host ""
                } 

                foreach ($File in $PstFiles) { 
                    $FoundOutlookFiles = $true 
                    $FileSizeGB = [math]::Round(($File.Length / 1GB), 2) 
                    $Pct = [math]::Round((($File.Length / 1GB) / 50) * 100, 1)
                    
                    $LocalDir = $File.Directory.FullName.Replace("\\$ComputerName\C$", "C:").Replace("\\$ComputerName\c$", "C:")
                    
                    Write-Host "Archive Data (.PST)" -ForegroundColor Magenta
                    Write-Host "File Name:          $($File.Name)" -ForegroundColor Gray
                    Write-Host "File Size:          $FileSizeGB GB / 50 GB | $Pct% Full" -ForegroundColor Gray
                    Write-Host "Location:           $LocalDir" -ForegroundColor Gray
                    Write-Host ""
                }
            }
        } 
        
        if (-not $FoundOutlookFiles) { 
            Write-Host " [~] No Outlook data files found for active user." -ForegroundColor DarkGray 
            Write-Host ""
        } 

        # FOLDER SIZES PROMPT
        if ($Users.Count -gt 0) {
            $TargetUser = $Users[0].Name
            
            Write-Host "[?] Would you like to begin directory scan to capture $($TargetUser)'s folder sizes? (Y/N): " -NoNewline -ForegroundColor Yellow
            $ScanPrompt = Read-Host
            
            if ($ScanPrompt -match "^[Yy]") {
                Write-Host "`n- - - FOLDER SIZES - - -" -ForegroundColor Blue
                Write-Host "`nScanning active user directories... [Press 'S' at any time to skip a folder]" -ForegroundColor DarkGray
                Write-Host ""
                
                foreach ($User in $Users) { 
                    Write-Host "User: $($User.Name)" -ForegroundColor Gray
                    
                    $TargetFolders = @()
                    $TargetFolders += [PSCustomObject]@{ Name = "Downloads"; Path = Join-Path $User.FullName "Downloads" }
                    $TargetFolders += [PSCustomObject]@{ Name = "Documents"; Path = Join-Path $User.FullName "Documents" }
                    $TargetFolders += [PSCustomObject]@{ Name = "Desktop"; Path = Join-Path $User.FullName "Desktop" }
                    $TargetFolders += [PSCustomObject]@{ Name = "Pictures"; Path = Join-Path $User.FullName "Pictures" }
                    $TargetFolders += [PSCustomObject]@{ Name = "Videos"; Path = Join-Path $User.FullName "Videos" }

                    foreach ($FolderObj in $TargetFolders) {
                        $FPath = $FolderObj.Path
                        $FName = $FolderObj.Name
                        
                        $FBytes = 0
                        $Skipped = $false
                        $FileCount = 0

                        if (Test-Path $FPath) {
                            try {
                                # uses labeled loop to safely break out of just this folder's pipeline
                                :ScanLoop do {
                                    Get-ChildItem -Path $FPath -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                                        
                                        # listens for the 'S' key
                                        if ([System.Console]::KeyAvailable) {
                                            $key = [System.Console]::ReadKey($true)
                                            if ($key.Key -eq 'S' -or $key.Key -eq 's') {
                                                $Skipped = $true
                                                break ScanLoop
                                            }
                                        }
                                        
                                        $FBytes += $_.Length
                                        $FileCount++
                                        
                                        # updates banner every 50 files to prevent performance issues
                                        if ($FileCount % 50 -eq 0) {
                                            $SizeMB = [math]::Round(($FBytes / 1MB), 2)
                                            Write-Progress -Activity "Scanning $($User.Name)\$FName..." -Status "Files: $FileCount | Size: $SizeMB MB [Press 'S' to Skip]"
                                        }
                                    }
                                } while ($false)
                            } catch {
                                # catch pipeline break exceptions
                            }
                            
                            Write-Progress -Activity "Scanning $($User.Name)\$FName..." -Completed
                            
                            if ($Skipped) {
                                $PaddedName = "$FName`:"
                                Write-Host "$($PaddedName.PadRight(18)) [SKIPPED by User]" -ForegroundColor Yellow
                                
                                # flushes buffer so held-down keys don't bleed into other prompts
                                while ([System.Console]::KeyAvailable) {
                                    $null = [System.Console]::ReadKey($true)
                                }
                            } else {
                                $FSizeGB = [math]::Round(($FBytes / 1GB), 2)
                                $PaddedName = "$FName`:"
                                Write-Host "$($PaddedName.PadRight(18)) $FSizeGB GB" -ForegroundColor Gray
                            }
                        } else {
                            $PaddedName = "$FName`:"
                            Write-Host "$($PaddedName.PadRight(18)) 0 GB (Not Found)" -ForegroundColor DarkGray
                        }
                    }
                }
            } else {
                Write-Host "`nSkipping directory scan for $TargetUser." -ForegroundColor DarkGray
            }
        } else {
            Write-Host "No active user profile found on C:\ to run folder scans." -ForegroundColor Gray
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
