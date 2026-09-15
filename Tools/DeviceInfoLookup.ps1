[CmdletBinding()] 
param() 

if (Get-Module -ListAvailable ActiveDirectory) { 
    Import-Module ActiveDirectory 
} 

# DASHBOARD
$Global:DashWidth = 100

function Truncate-Str ($Str, $Len) {
    if ([string]::IsNullOrEmpty($Str)) { return "".PadRight($Len) }
    $Str = [string]$Str
    if ($Str.Length -gt $Len) { return $Str.Substring(0, $Len - 3) + "..." }
    return $Str.PadRight($Len)
}

function Get-ProgressBar ($Pct, $Length = 16) {
    $Filled = [math]::Round(($Pct / 100) * $Length)
    if ($Filled -lt 0) { $Filled = 0 }
    if ($Filled -gt $Length) { $Filled = $Length }
    $Empty = $Length - $Filled
    
    $BlockStr = [string][char]9608
    $DimStr   = [string][char]9617
    
    return "[$($BlockStr * $Filled)$($DimStr * $Empty)]"
}

function Write-SectionHeader ($Title) {
    Write-Host "`n─── $Title " -NoNewline -ForegroundColor DarkCyan
    $DashCount = $Global:DashWidth - 5 - $Title.Length
    if ($DashCount -gt 0) { Write-Host "$('─' * $DashCount)" -ForegroundColor DarkCyan } else { Write-Host "" }
}

function Write-2Col ($L1, $V1, $L2, $V2, $C1="White", $C2="White") {
    Write-Host "  " -NoNewline
    Write-Host (Truncate-Str $L1 14) -NoNewline -ForegroundColor DarkGray
    Write-Host (Truncate-Str $V1 32) -NoNewline -ForegroundColor $C1
    Write-Host " │  " -NoNewline -ForegroundColor DarkGray
    Write-Host (Truncate-Str $L2 14) -NoNewline -ForegroundColor DarkGray
    Write-Host (Truncate-Str $V2 32) -ForegroundColor $C2
}

function Write-1Col ($L1, $V1, $C1="White") {
    Write-Host "  " -NoNewline
    Write-Host (Truncate-Str $L1 19) -NoNewline -ForegroundColor DarkGray
    Write-Host (Truncate-Str $V1 77) -ForegroundColor $C1
}
# ────────────────────────────

while ($true) { 
    Clear-Host 
    
    $ADUser = $null
    $SearchString = $null

    Write-Host "          =================BSTools=================" -ForegroundColor Blue
    Write-Host "                  BlueStarIT Lookup Tool v2.0" -ForegroundColor White
    Write-Host "                  Developed by: Chase Bezilla" -ForegroundColor DarkGray
    Write-Host "                   For BlueStar, Inc. (2026)" -ForegroundColor DarkGray
    Write-Host "          ============github.com/xezixa============" -ForegroundColor Blue
    
    Write-Host "`n[?] Enter BlueStar Computer Name, Username, or Employee Name: " -ForegroundColor Yellow -NoNewLine
    $SearchTarget = Read-Host

    Write-Host "`n---------------------------------------------------" -ForegroundColor Yellow
    
    if ($SearchTarget -eq 'q' -or $SearchTarget -eq 'Q') { break } 
    if ([string]::IsNullOrWhiteSpace($SearchTarget)) { continue } 

    $ComputerName = $SearchTarget 
    $ComputerDesc = ""

    if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) { 
        if ($SearchTarget -notmatch "^BS(US|CA|MX|LA)\d+") { 
            $SearchString = $SearchTarget 
            if ($SearchTarget -notmatch "\s") { 
                try { 
                    $ADUser = Get-ADUser -Identity $SearchTarget -Properties GivenName, Surname, DisplayName, Office, Title, Department, Manager, Mail, PasswordLastSet, "msDS-UserPasswordExpiryTimeComputed", PasswordNeverExpires -Server "bluestarinc.com" -ErrorAction Stop 
                    $SearchString = "$($ADUser.GivenName) $($ADUser.Surname)".Trim() 
                    Write-Host "`n[*] Username Found!: '$SearchTarget' | Employee Name: $SearchString" -ForegroundColor Cyan 
                } catch { 
                    Write-Host "`n[*] No exact username match. Treating input as First Name: $SearchString" -ForegroundColor Cyan 
                } 
            } else { 
                Write-Host "`n[+] Full Name detected! Searching for: $SearchString" -ForegroundColor DarkGreen 
            } 

            Write-Host "[-] Searching for computer(s)..." -ForegroundColor Gray 
            
            $LDAPFilter = "(&(description=$SearchString*)(|(name=BSUS*)(name=BSLA*)(name=BSCA*)(name=BSMX*)))" 
            $MatchedPCs = Get-ADComputer -LDAPFilter $LDAPFilter -Properties Description -Server "bluestarinc.com" -ErrorAction SilentlyContinue 
            
            if ($MatchedPCs) { 
                $PCArray = @($MatchedPCs) | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } | Sort-Object Name -Descending  
                Write-Host "[+] Device(s) detected. Pinging to ensure connection..." -ForegroundColor DarkGreen 
                
                $ActivePCs = @() 
                foreach ($PC in $PCArray) { 
                    if (Test-Connection -ComputerName $PC.Name -Count 1 -Quiet -ErrorAction SilentlyContinue) { $ActivePCs += $PC } 
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
                    Write-Host "`n[!] Multiple ACTIVE devices found under '$SearchString':" -ForegroundColor Red 
                    for ($i = 0; $i -lt $ActivePCs.Count; $i++) { 
                        Write-Host "  [$($i + 1)] $($ActivePCs[$i].Name) - $($ActivePCs[$i].Description)" 
                    } 
                    
                    $Selection = 0 
                    while ($Selection -lt 1 -or $Selection -gt $ActivePCs.Count) { 
                        Write-Host "`n[?] Enter the number of the device you want to query: " -NoNewline -ForegroundColor Yellow
                        $Input = Read-Host 
                        if ([int]::TryParse($Input, [ref]$Selection)) { 
                            if ($Selection -lt 1 -or $Selection -gt $ActivePCs.Count) { Write-Host "Invalid selection." -ForegroundColor Red } 
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
        if ($SearchTarget -notmatch "^BS(US|CA|MX|LA)") { Write-Warning "ActiveDirectory module missing." } 
    } 

    Write-Host "[-] Grabbing useful information..." -ForegroundColor Gray

    if (-not (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue)) { 
        Write-Warning "Computer '$ComputerName' is offline or unreachable." 
        Read-Host "`nPress Enter to try again..." 
        continue 
    } 

    $CimSession = $null 
    $DataGathered = $false 
    $ProtocolUsed = "None" 

    try { 
        $CimSession = New-CimSession -ComputerName $ComputerName -ErrorAction Stop 
        $OS   = Get-CimInstance Win32_OperatingSystem -CimSession $CimSession -ErrorAction Stop 
        $CS   = Get-CimInstance Win32_ComputerSystem -CimSession $CimSession -ErrorAction Stop 
        $BIOS = Get-CimInstance Win32_BIOS -CimSession $CimSession -ErrorAction Stop 
        $Net  = Get-CimInstance Win32_NetworkAdapterConfiguration -CimSession $CimSession -Filter "IPEnabled = 'True'" -ErrorAction SilentlyContinue 
        $CPU  = Get-CimInstance Win32_Processor -CimSession $CimSession -ErrorAction Stop 
        $Disk = Get-CimInstance Win32_LogicalDisk -CimSession $CimSession -Filter "DeviceID='C:'" -ErrorAction Stop 
        $CSP  = Get-CimInstance Win32_ComputerSystemProduct -CimSession $CimSession -ErrorAction SilentlyContinue 
        $PhysMem = Get-CimInstance Win32_PhysicalMemory -CimSession $CimSession -ErrorAction SilentlyContinue | Select-Object -First 1
        $DataGathered = $true 
        $ProtocolUsed = "WinRM" 
    } catch { 
        if ($CimSession) { Remove-CimSession $CimSession -ErrorAction SilentlyContinue } 
        try { 
            $DcomOption = New-CimSessionOption -Protocol Dcom 
            $CimSession = New-CimSession -ComputerName $ComputerName -SessionOption $DcomOption -ErrorAction Stop 
            $OS   = Get-CimInstance Win32_OperatingSystem -CimSession $CimSession -ErrorAction Stop 
            $CS   = Get-CimInstance Win32_ComputerSystem -CimSession $CimSession -ErrorAction Stop 
            $BIOS = Get-CimInstance Win32_BIOS -CimSession $CimSession -ErrorAction Stop 
            $Net  = Get-CimInstance Win32_NetworkAdapterConfiguration -CimSession $CimSession -Filter "IPEnabled = 'True'" -ErrorAction SilentlyContinue 
            $CPU  = Get-CimInstance Win32_Processor -CimSession $CimSession -ErrorAction Stop 
            $Disk = Get-CimInstance Win32_LogicalDisk -CimSession $CimSession -Filter "DeviceID='C:'" -ErrorAction Stop 
            $CSP  = Get-CimInstance Win32_ComputerSystemProduct -CimSession $CimSession -ErrorAction SilentlyContinue 
            $PhysMem = Get-CimInstance Win32_PhysicalMemory -CimSession $CimSession -ErrorAction SilentlyContinue | Select-Object -First 1
            $DataGathered = $true 
            $ProtocolUsed = "DCOM" 
        } catch { 
            Write-Warning "Remote management failed on $ComputerName." 
        } 
    } 

    if ($DataGathered) { 
        Clear-Host
        Write-Host "[✓] Target Resolved: " -ForegroundColor DarkGreen -NoNewline
        Write-Host "$ComputerName " -ForegroundColor Green -NoNewline
        if ($SearchString) { Write-Host "($SearchString) " -ForegroundColor Gray -NoNewline }
        Write-Host "[Protocol: $ProtocolUsed]" -ForegroundColor DarkCyan
        
        $IPAddress = if ($Net) { $Net.IPAddress[0] } else { "Unknown" } 
        
        # get rid of domain prefix from logged on user
        $CurrentUser = if ($CS.UserName) { $CS.UserName.Split('\')[-1] } else { "None / System" } 
        
        # simplifies OS string
        $SimpOS = $OS.Caption -replace '(?i)Microsoft\s*', ''
        
        # simplifies CPU string
        $SimpCPU = $CPU.Name -replace '\(R\)|\(TM\)', '' -replace '(?i)Core\s+', '' -replace '(?i)\s+CPU\s+@.*', '' -replace '\s+', ' '
        $SimpCPU = $SimpCPU.Trim()

        # uptime calc
        $Uptime = (Get-Date) - $OS.LastBootUpTime 
        if ($Uptime.Days -gt 0) {
            $UptimeString = "$($Uptime.Days) Days, $($Uptime.Hours) Hrs, $($Uptime.Minutes) Mins" 
        } else {
            $UptimeString = "$($Uptime.Hours) Hrs, $($Uptime.Minutes) Mins" 
        }

        $Manufacturer = $CS.Manufacturer 
        $SN = $BIOS.SerialNumber 
        $MfgDate = "Unknown" 
        $ModelString = $CS.Model 

        if ($Manufacturer -match "Lenovo") { 
            $FriendlyName = $CS.Model 
            if ($CS.SystemSKUNumber -match "_FM_(.*)") { $FriendlyName = $Matches[1] } 
            elseif ($CSP -and $CSP.Version -and $CSP.Version -notmatch "^Lenovo$|^ThinkPad$") { $FriendlyName = $CSP.Version } 
            $ModelString = "$FriendlyName ($($CS.Model))" 
            try { 
                $Battery = Get-CimInstance -Namespace root\wmi -Class BatteryStaticData -CimSession $CimSession -ErrorAction Stop | Select-Object -First 1 
                if ($Battery -and $Battery.ManufactureDate -gt 0) { 
                    $DateInt = $Battery.ManufactureDate 
                    $Day = $DateInt -band 31; $Month = ($DateInt -shr 5) -band 15; $Year = ($DateInt -shr 9) + 1980 
                    if ($Year -ge 2015 -and $Year -le (Get-Date).Year) { 
                        $BatDate = Get-Date -Year $Year -Month $Month -Day $Day 
                        $MfgDate = "$($BatDate.ToString('MMM yyyy')) (via Battery)" 
                    } 
                } 
            } catch {} 
        }  
        elseif ($Manufacturer -match "HP|Hewlett-Packard" -and $SN.Length -ge 6) { 
            $ModelString = if ($CS.SystemSKUNumber) { "$($CS.Model) ($($CS.SystemSKUNumber))" } else { $($CS.Model) } 
            try { 
                $YearDigit = [int][string]$SN[3]; $WeekDigit = [int]$SN.Substring(4, 2) 
                $BaseYear = if ($YearDigit -ge 7) { 2010 } else { 2020 } 
                $CalculatedYear = $BaseYear + $YearDigit 
                $ApproxDate = (Get-Date -Year $CalculatedYear -Month 1 -Day 1).AddDays(($WeekDigit - 1) * 7) 
                $MfgDate = "$($ApproxDate.ToString('MMM yyyy')) (via HP SN)" 
            } catch { $MfgDate = "Parse Error" } 
        }  
        
        if ($MfgDate -eq "Unknown" -or $MfgDate -match "Parse Error") { 
            $CpuYear = $null 
            if ($CPU.Name -match "\b(\d{1,2})(?:th|st|nd|rd)\s+Gen") { 
                $gen = [int]$Matches[1] 
                if ($gen -ge 6 -and $gen -le 14) { $CpuYear = 2010 + $gen } 
            }  
            elseif ($CPU.Name -match "Core(?:\(TM\))?\s+(?:Ultra\s+)?[3579]\s+([12])\d{2}[A-Z]") { $CpuYear = 2023 + [int]$Matches[1] }  
            elseif ($CPU.Name -match "i[3579]-(\d+)") { 
                $modelNum = $Matches[1] 
                if ($modelNum.Length -eq 4) { 
                    $firstTwo = [int]$modelNum.Substring(0, 2) 
                    if ($firstTwo -ge 10) { $CpuYear = 2010 + $firstTwo } else { $CpuYear = 2010 + [int]$modelNum.Substring(0, 1) } 
                } elseif ($modelNum.Length -eq 5) { $CpuYear = 2010 + [int]$modelNum.Substring(0, 2) } 
            }  
            elseif ($CPU.Name -match "Ryzen\s+[3579].*?\b(\d)\d{3}") { 
                $gen = [int]$Matches[1] 
                if ($gen -ge 3 -and $gen -le 8) { $CpuYear = 2016 + $gen } 
            } 
            if ($CpuYear) { $MfgDate = "$CpuYear (via CPU Gen.)" } 
        } 

        if ($MfgDate -eq "Unknown" -or $MfgDate -match "Parse Error") { 
            $MfgDate = if ($BIOS.ReleaseDate) { "$($BIOS.ReleaseDate.ToString('MMM yyyy')) (BIOS Date)" } else { "Unknown" } 
        } 

        # system age calc
        if ($MfgDate -ne "Unknown" -and $MfgDate -notmatch "Parse Error") { 
            if ($MfgDate -match "(\d{4})") {
                $calcYear = [int]$Matches[1]
                $ageYears = (Get-Date).Year - $calcYear
                $sourceText = if ($MfgDate -match "(\(.*\))") { $Matches[1] } else { "" }
                
                if ($ageYears -eq 0) { $MfgDate = "< 1 Year $sourceText" }
                elseif ($ageYears -eq 1) { $MfgDate = "1 Year $sourceText" }
                else { $MfgDate = "$ageYears Years $sourceText" }
            }
        }

        # RAM capture/rounding
        $RamGB = [math]::Round(($CS.TotalPhysicalMemory / 1GB), 0)
        $RamType = ""
        if ($PhysMem) {
            $SMBIOS = $PhysMem.SMBIOSMemoryType
            if ($SMBIOS -eq 20) { $RamType = " DDR" }
            elseif ($SMBIOS -eq 21) { $RamType = " DDR2" }
            elseif ($SMBIOS -eq 24) { $RamType = " DDR3" }
            elseif ($SMBIOS -eq 26) { $RamType = " DDR4" }
            elseif ($SMBIOS -eq 34) { $RamType = " DDR5" }
        }
        $RamString = "$RamGB GB$RamType"

        $CSizeGB = if ($Disk) { [math]::Round(($Disk.Size / 1GB), 2) } else { 0 } 
        $CFreeGB = if ($Disk) { [math]::Round(($Disk.FreeSpace / 1GB), 2) } else { 0 } 

        $ADAccount = $null
        $TargetUsername = $null

        if ($CurrentUser -and $CurrentUser -ne "None / System") { $TargetUsername = $CurrentUser } 
        elseif ($ADUser) { $TargetUsername = $ADUser.sAMAccountName }

        if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
            if ($TargetUsername) {
                $ADAccount = Get-ADUser -Identity $TargetUsername -Properties DisplayName, Office, Title, Department, Manager, sAMAccountName, Mail, PasswordLastSet, "msDS-UserPasswordExpiryTimeComputed", PasswordNeverExpires, physicalDeliveryOfficeName -Server "bluestarinc.com" -ErrorAction SilentlyContinue
            } elseif ($SearchString -and ($SearchTarget -notmatch "^BS(US|CA|MX|LA)\d+")) {
                $ADAccount = Get-ADUser -Filter "DisplayName -like '$SearchString*' -or Name -like '$SearchString*'" -Properties DisplayName, Office, Title, Department, Manager, sAMAccountName, Mail, PasswordLastSet, "msDS-UserPasswordExpiryTimeComputed", PasswordNeverExpires, physicalDeliveryOfficeName -Server "bluestarinc.com" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
        }

        $FullName = "None"; $Office = "None"; $Role = "None"; $Department = "None"; $ReportsTo = "None"
        $Username = "None"; $EmailAddress = "None"; $PasswordLastSet = "Unknown"; $PasswordExpires = "Unknown"

        if ($ADAccount) {
            $FullName = if ($ADAccount.DisplayName) { $ADAccount.DisplayName } else { "$($ADAccount.GivenName) $($ADAccount.Surname)".Trim() }
            $Office = if ($ADAccount.Office) { $ADAccount.Office } elseif ($ADAccount.physicalDeliveryOfficeName) { $ADAccount.physicalDeliveryOfficeName } else { "None" }
            $Role = if ($ADAccount.Title) { $ADAccount.Title } else { "None" }
            $Department = if ($ADAccount.Department) { $ADAccount.Department } else { "None" }
            if ($ADAccount.Manager) { if ($ADAccount.Manager -match "^CN=([^,]+)") { $ReportsTo = $Matches[1] } else { $ReportsTo = $ADAccount.Manager } }
            $Username = $ADAccount.sAMAccountName
            $EmailAddress = if ($ADAccount.Mail) { $ADAccount.Mail } elseif ($ADAccount.UserPrincipalName) { $ADAccount.UserPrincipalName } else { "None" }
            $PasswordLastSet = if ($ADAccount.PasswordLastSet) { $ADAccount.PasswordLastSet.ToString("MM/dd/yyyy hh:mm tt") } else { "Unknown" }

            if ($ADAccount.PasswordNeverExpires) {
                $PasswordExpires = "Never"
            } elseif ($ADAccount."msDS-UserPasswordExpiryTimeComputed") {
                $val = $ADAccount."msDS-UserPasswordExpiryTimeComputed"
                try {
                    if ($val -eq 0x7FFFFFFFFFFFFFFF) { $PasswordExpires = "Never" } 
                    elseif ($val -is [int64] -or $val -is [long]) { $PasswordExpires = ([DateTime]::FromFileTime($val)).ToString("MM/dd/yyyy hh:mm tt") } 
                    elseif ($val -is [DateTime]) { $PasswordExpires = $val.ToString("MM/dd/yyyy hh:mm tt") }
                } catch { $PasswordExpires = "Calculation Error" }
            }
        }
        
        $UptimeColor = "White"
        if ($Uptime.Days -ge 30) { $UptimeColor = "Red" } elseif ($Uptime.Days -ge 14) { $UptimeColor = "Yellow" }

        $PwdColor = "White"
        if ($PasswordExpires -ne "Never" -and $PasswordExpires -match "\d") {
            try {
                $ExpDate = [datetime]::ParseExact($PasswordExpires, "MM/dd/yyyy hh:mm tt", $null)
                $DaysLeft = ($ExpDate - (Get-Date)).Days
                if ($DaysLeft -le 0) { $PwdColor = "Red" } elseif ($DaysLeft -le 14) { $PwdColor = "Yellow" } else { $PwdColor = "Green" }
            } catch {}
        }
        
        # DRAW MAPPED DASHBOARD 
        Write-SectionHeader "ACCOUNT DETAILS"
        Write-2Col "" "" "Full Name:" $FullName
        Write-2Col "Username:" $Username "" ""
        Write-2Col "Email:" $EmailAddress "Office:" $Office
        Write-2Col "" "" "Department:" $Department
        Write-2Col "Pwd Set:" $PasswordLastSet "Position:" $Role
        Write-2Col "Pwd Expires:" $PasswordExpires "" "" $PwdColor "White"
        Write-2Col "" "" "Reports To:" $ReportsTo
        
        Write-SectionHeader "SYSTEM INFO"
        Write-2Col "Device Name:" $ComputerName "Device Model:" $ModelString
        Write-2Col "Logged On:" $CurrentUser "Device Age:" $MfgDate
        Write-2Col "Uptime:" $UptimeString "Serial Num:" $SN "White" $UptimeColor
        Write-2Col "" "" "" ""
        Write-2Col "IPv4 Address:" $IPAddress "RAM:" $RamString
        Write-2Col "OS Ver:" $SimpOS "CPU:" $SimpCPU
    } 

    $UserProfilesPath = "\\$ComputerName\C$\Users" 
    
    if (Test-Path $UserProfilesPath) { 
        
        $Users = @()
        if ($CurrentUser -and $CurrentUser -ne "None / System") {
            $ActiveUserFolder = $CurrentUser
            $ActiveUserPath = Join-Path $UserProfilesPath $ActiveUserFolder
            if (Test-Path $ActiveUserPath) {
                $Users += [PSCustomObject]@{ Name = $ActiveUserFolder; FullName = $ActiveUserPath }
            }
        }
        
        Write-SectionHeader "STORAGE & DATA"
        
        $PctUsed = 0
        if ($Disk -and $Disk.Size -gt 0) { $PctUsed = [math]::Round((($Disk.Size - $Disk.FreeSpace) / $Disk.Size) * 100, 1) }
        $StorageBar = Get-ProgressBar $PctUsed 25
        Write-1Col "Available Storage:" "$StorageBar $PctUsed% Used ($CFreeGB GB free of $CSizeGB GB)"

        $FoundOutlookFiles = $false 
        foreach ($User in $Users) { 
            $OstPath = Join-Path $User.FullName "AppData\Local\Microsoft\Outlook" 
            $PstPath = Join-Path $User.FullName "Documents\Outlook Files"
            $OstFiles = @(); $PstFiles = @()

            if (Test-Path $OstPath -ErrorAction SilentlyContinue) { 
                $OstFiles = Get-ChildItem -Path $OstPath -Filter *.ost -File -ErrorAction SilentlyContinue 
                $PstFiles += Get-ChildItem -Path $OstPath -Filter *.pst -File -ErrorAction SilentlyContinue
            } 
            if (Test-Path $PstPath -ErrorAction SilentlyContinue) {
                $PstFiles += Get-ChildItem -Path $PstPath -Filter *.pst -File -ErrorAction SilentlyContinue
            }

            if ($OstFiles.Count -gt 0 -or $PstFiles.Count -gt 0) {
                $UserShareBase = "\\$ComputerName\C$\Users\$($User.Name)"
                
                foreach ($File in $OstFiles) { 
                    $FoundOutlookFiles = $true 
                    $FileSizeGB = [math]::Round(($File.Length / 1GB), 2) 
                    $Pct = [math]::Round((($File.Length / 1GB) / 50) * 100, 1)
                    $LocalDir = $File.DirectoryName -replace [regex]::Escape($UserShareBase), "~" -replace "(?i)\\\\$ComputerName\\c\$", "C:"
                    $Bar = Get-ProgressBar $Pct 16
                    
                    Write-Host ""
                    Write-1Col ".OST:" "$Bar $FileSizeGB GB ($Pct%)  |  $($File.Name)" "Cyan"
                    Write-1Col "" "Path: $LocalDir" "DarkGray"
                } 
                foreach ($File in $PstFiles) { 
                    $FoundOutlookFiles = $true 
                    $FileSizeGB = [math]::Round(($File.Length / 1GB), 2) 
                    $Pct = [math]::Round((($File.Length / 1GB) / 50) * 100, 1)
                    $LocalDir = $File.DirectoryName -replace [regex]::Escape($UserShareBase), "~" -replace "(?i)\\\\$ComputerName\\c\$", "C:"
                    $Bar = Get-ProgressBar $Pct 16
                    
                    Write-Host ""
                    Write-1Col ".PST:" "$Bar $FileSizeGB GB ($Pct%)  |  $($File.Name)" "Cyan"
                    Write-1Col "" "Path: $LocalDir" "DarkGray"
                }
            }
        } 
        
        if (-not $FoundOutlookFiles) { 
            Write-Host ""
            Write-1Col "Outlook Files:" "None found in standard directories for active user." "DarkGray"
        } 

        Write-Host "`n$('─' * $Global:DashWidth)" -ForegroundColor DarkCyan

        if ($Users.Count -gt 0) {
            $TargetUser = $Users[0].Name
            Write-Host "`n[?] Scan directory to capture $($TargetUser)'s folder sizes? (Y/N): " -NoNewline -ForegroundColor Yellow
            $ScanPrompt = Read-Host
            
            if ($ScanPrompt -match "^[Yy]") {
                Write-SectionHeader "DIRECTORY SIZES ($TargetUser)"
                
                foreach ($User in $Users) { 
                    $TargetFolders = @()
                    $TargetFolders += [PSCustomObject]@{ Name = "Downloads"; Path = Join-Path $User.FullName "Downloads" }
                    $TargetFolders += [PSCustomObject]@{ Name = "Documents"; Path = Join-Path $User.FullName "Documents" }
                    $TargetFolders += [PSCustomObject]@{ Name = "Desktop"; Path = Join-Path $User.FullName "Desktop" }
                    $TargetFolders += [PSCustomObject]@{ Name = "Pictures"; Path = Join-Path $User.FullName "Pictures" }
                    $TargetFolders += [PSCustomObject]@{ Name = "Videos"; Path = Join-Path $User.FullName "Videos" }

                    foreach ($FolderObj in $TargetFolders) {
                        $FPath = $FolderObj.Path
                        $FName = $FolderObj.Name
                        $FBytes = 0; $Skipped = $false; $FileCount = 0

                        if (Test-Path $FPath) {
                            try {
                                :ScanLoop do {
                                    Get-ChildItem -Path $FPath -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                                        if ([System.Console]::KeyAvailable) {
                                            $key = [System.Console]::ReadKey($true)
                                            if ($key.Key -eq 'S' -or $key.Key -eq 's') { $Skipped = $true; break ScanLoop }
                                        }
                                        $FBytes += $_.Length
                                        $FileCount++
                                        if ($FileCount % 50 -eq 0) {
                                            $SizeMB = [math]::Round(($FBytes / 1MB), 2)
                                            Write-Progress -Activity "Scanning $($User.Name)\$FName..." -Status "Files: $FileCount | Size: $SizeMB MB [Press 'S' to Skip]"
                                        }
                                    }
                                } while ($false)
                            } catch {}
                            
                            Write-Progress -Activity "Scanning $($User.Name)\$FName..." -Completed
                            
                            if ($Skipped) {
                                while ([System.Console]::KeyAvailable) { $null = [System.Console]::ReadKey($true) }
                                Write-1Col "${FName}:" "[SKIPPED]" "Yellow"
                            } else {
                                $FSizeGB = [math]::Round(($FBytes / 1GB), 2)
                                Write-1Col "${FName}:" "$FSizeGB GB" "White"
                            }
                        } else {
                            Write-1Col "${FName}:" "0 GB (Not Found)" "DarkGray"
                        }
                    }
                }
            }
        } else {
            Write-Host "No active user profile found on C:\ to run folder scans." -ForegroundColor Gray
        }
    } else { 
        Write-Warning "Could not access administrative share (\\$ComputerName\C$). This machine may be offline, blocking SMB, or you lack local admin rights." 
    } 
    
    if ($CimSession) { Remove-CimSession $CimSession -ErrorAction SilentlyContinue } 
    Write-Host "`n" 
    Read-Host "Press Enter to search another computer..." 
}
