<# BlueStar GUI based AD onboard/offboard tool #>

Requires -Modules ActiveDirectory
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.DirectoryServices

# ==============================================================================
# CONFIG DATA
# ==============================================================================
$Domain = "bluestarinc.com"
$BaseDN = "DC=bluestarinc,DC=com"

# master config using to enforce specific dropdown sequences
$Global:ConfigData = [ordered]@{
    "BlueStar US" = @{
        ADName = "BlueStar_US"
        Departments = @("Accounting", "Administration", "Business Analytics", "Executive", "IT", "Marketing", "Purchasing", "Sales", "Tech Support", "Warehouse")
        Offices = [ordered]@{
            "Corporate" = @{ Phone="(859) 371-4423 Ext. "; Company="BlueStar US"; Street="3345 Point Pleasant Road"; City="Hebron"; State="KY"; Zip="41048"; Country="US" }
            "California" = @{ Phone="(949) 783-3388 Ext. "; Company="BlueStar US"; Street="23161 Mill Creek Drive | Suite 200"; City="Laguna Hills"; State="CA"; Zip="92653"; Country="US" }
            "Cleveland" = @{ Phone="(800) 354-9776 Ext. "; Company="BlueStar US"; Street="212782 Prospect Road, Floor 2"; City="Strongsville"; State="OH"; Zip="44149"; Country="US" }
        }
    }
    "BlueStar CA" = @{
        ADName = "BlueStar_CA"
        Departments = @("Accounting", "Administration", "Customer Service", "Executive", "Marketing", "Sales", "Tech Support", "Warehouse")
        Offices = @{
            "Toronto" = @{ Phone="(800) 317-1132 Ext. "; Company="BlueStar Canada"; Street="6790 Century Ave. Suite 404"; City="Mississauga"; State="ON"; Zip="L5N2V8"; Country="CA" }
            "Montreal" = @{ Phone="(800) 317-2323 Ext. "; Company="BlueStar Canada"; Street="6830 Côte-de-Liesse"; City="Montreal"; State="QC"; Zip="H4T2A1"; Country="CA" }
        }
    }
    "BlueStar LA" = @{
        ADName = "BlueStar_LA"
        Departments = @("Accounting", "Customer Service", "Executive", "Marketing", "Purchasing", "Sales", "Technical", "Warehouse")
        Offices = @{
            "Miramar" = @{ Phone="(954) 485-1931 Ext. "; Company="BlueStar Latin America"; Street="3561 Enterprise Way"; City="Miramar"; State="FL"; Zip="33025"; Country="US" }
        }
    }
    "BlueStar MX" = @{
        ADName = "BlueStar_MX"
        Departments = @("Accounting", "Customer Service", "Executive", "Marketing", "Purchasing", "Sales", "Technical", "Warehouse")
        Offices = @{
            "Mexico" = @{ Phone="+52 (55) 5357-0087 Ext. "; Company="BlueStar Mexico"; Street="Av. San Isidro # 97 piso 2 Col. San Francisco Tetecala"; City="Azcapotzalco"; State="CP"; Zip="02760"; Country="MX" }
        }
    }
}

$DefaultGroups = @(
    "Webex_User", "VPN_USERS", "Service Desk Users", 
    "Secure_Wifi", "PasswordAccountLockout_Standard", 
    "OWA_2FA", "BlueStar Barracuda"
)

# Variable to hold the name of the last successfully created user
$script:provisionedUser = ""

# Script paths for mailbox provisioning
$script:mailboxScriptPath_Manual = "\\bsqnap\PST\RemoteMailboxProvisioning\Create-RemoteMailboxV2.ps1"
$script:mailboxScriptPath_Auto = "C:\Users\cbezilla\Documents\Skrips\MailboxProvisionTool_Parameter.ps1"

# ==============================================================================
# HELPER FUNCT.
# ==============================================================================
function Show-NameValidationPrompt {
    param([string]$ExpectedName)
    $inputForm = New-Object System.Windows.Forms.Form
    $inputForm.Text = "Final Confirmation"
    $inputForm.Size = New-Object System.Drawing.Size(350, 160)
    $inputForm.StartPosition = "CenterParent"
    $inputForm.FormBorderStyle = "FixedDialog"
    $inputForm.MaximizeBox = $false
    $inputForm.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "To confirm permanent deletion, type the exact name:`n$ExpectedName"
    $lbl.Location = New-Object System.Drawing.Point(15, 15)
    $lbl.AutoSize = $true
    $inputForm.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(15, 55)
    $txt.Size = New-Object System.Drawing.Size(300, 25)
    $inputForm.Controls.Add($txt)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Confirm"
    $btnOk.Location = New-Object System.Drawing.Point(75, 85)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $inputForm.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(185, 85)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $inputForm.Controls.Add($btnCancel)

    $inputForm.AcceptButton = $btnOk
    $inputForm.CancelButton = $btnCancel

    $result = $inputForm.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $txt.Text
    }
    return $null
}


# ==============================================================================
# GUI SETUP
# ==============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Onboarding/Offboarding Tool"
$form.Size = New-Object System.Drawing.Size(450, 650)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$defaultFont = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Font = $defaultFont

# MAIN MENU
$pnlMain = New-Object System.Windows.Forms.Panel
$pnlMain.Size = $form.ClientSize
$pnlMain.Visible = $true

$btnOnboarding = New-Object System.Windows.Forms.Button
$btnOnboarding.Text = "Onboarding"
$btnOnboarding.Size = New-Object System.Drawing.Size(200, 50)
$btnOnboarding.Location = New-Object System.Drawing.Point(115, 150)
$btnOnboarding.Add_Click({ $pnlMain.Visible = $false; $pnlOnboard.Visible = $true })
$pnlMain.Controls.Add($btnOnboarding)

$btnOffboarding = New-Object System.Windows.Forms.Button
$btnOffboarding.Text = "Offboarding"
$btnOffboarding.Size = New-Object System.Drawing.Size(200, 50)
$btnOffboarding.Location = New-Object System.Drawing.Point(115, 220)
$btnOffboarding.Add_Click({ $pnlMain.Visible = $false; $pnlOffboard.Visible = $true })
$pnlMain.Controls.Add($btnOffboarding)

# ONBOARD SUB-MENU
$pnlOnboard = New-Object System.Windows.Forms.Panel
$pnlOnboard.Size = $form.ClientSize
$pnlOnboard.Visible = $false

$btnNewHire = New-Object System.Windows.Forms.Button
$btnNewHire.Text = "Create New Hire"
$btnNewHire.Size = New-Object System.Drawing.Size(200, 50)
$btnNewHire.Location = New-Object System.Drawing.Point(115, 150)
$btnNewHire.Add_Click({ $pnlOnboard.Visible = $false; $pnlNewHire.Visible = $true })
$pnlOnboard.Controls.Add($btnNewHire)

$btnMailbox = New-Object System.Windows.Forms.Button
$btnMailbox.Text = "Mailbox Provisioning"
$btnMailbox.Size = New-Object System.Drawing.Size(200, 50)
$btnMailbox.Location = New-Object System.Drawing.Point(115, 220)
$btnMailbox.Add_Click({
    try {
        $psArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $script:mailboxScriptPath_Manual
        )
        Start-Process powershell.exe -ArgumentList $psArgs -Verb RunAs
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to launch Mailbox Provisioning script.", "Error", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})
$pnlOnboard.Controls.Add($btnMailbox)

$btnBackMain = New-Object System.Windows.Forms.Button
$btnBackMain.Text = "< Back"
$btnBackMain.Size = New-Object System.Drawing.Size(75, 30)
$btnBackMain.Location = New-Object System.Drawing.Point(10, 10)
$btnBackMain.Add_Click({ $pnlOnboard.Visible = $false; $pnlMain.Visible = $true })
$pnlOnboard.Controls.Add($btnBackMain)


# OFFBOARD SUB-MENU
$pnlOffboard = New-Object System.Windows.Forms.Panel
$pnlOffboard.Size = $form.ClientSize
$pnlOffboard.Visible = $false

$btnOffboardEmp = New-Object System.Windows.Forms.Button
$btnOffboardEmp.Text = "Offboard Employee"
$btnOffboardEmp.Size = New-Object System.Drawing.Size(200, 50)
$btnOffboardEmp.Location = New-Object System.Drawing.Point(115, 150)
$btnOffboardEmp.Add_Click({ $pnlOffboard.Visible = $false; $pnlOffboardEmp.Visible = $true })
$pnlOffboard.Controls.Add($btnOffboardEmp)

$btn90Day = New-Object System.Windows.Forms.Button
$btn90Day.Text = "90-Day Deletion"
$btn90Day.Size = New-Object System.Drawing.Size(200, 50)
$btn90Day.Location = New-Object System.Drawing.Point(115, 220)
$btn90Day.Add_Click({ $pnlOffboard.Visible = $false; $pnl90Day.Visible = $true })
$pnlOffboard.Controls.Add($btn90Day)

$btnBackMainOff = New-Object System.Windows.Forms.Button
$btnBackMainOff.Text = "< Back"
$btnBackMainOff.Size = New-Object System.Drawing.Size(75, 30)
$btnBackMainOff.Location = New-Object System.Drawing.Point(10, 10)
$btnBackMainOff.Add_Click({ $pnlOffboard.Visible = $false; $pnlMain.Visible = $true })
$pnlOffboard.Controls.Add($btnBackMainOff)


# OFFBOARD EMPLOYEE PANEL
$pnlOffboardEmp = New-Object System.Windows.Forms.Panel
$pnlOffboardEmp.Size = $form.ClientSize
$pnlOffboardEmp.Visible = $false

$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "Enter Employee Full Name or Username:"
$lblSearch.Location = New-Object System.Drawing.Point(30, 80)
$lblSearch.AutoSize = $true
$pnlOffboardEmp.Controls.Add($lblSearch)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(30, 110)
$txtSearch.Size = New-Object System.Drawing.Size(250, 25)
$pnlOffboardEmp.Controls.Add($txtSearch)

$btnSearchOffboard = New-Object System.Windows.Forms.Button
$btnSearchOffboard.Text = "Search domain"
$btnSearchOffboard.Location = New-Object System.Drawing.Point(30, 150)
$btnSearchOffboard.Size = New-Object System.Drawing.Size(150, 40)
$pnlOffboardEmp.Controls.Add($btnSearchOffboard)

$lblOffboardStatus = New-Object System.Windows.Forms.Label
$lblOffboardStatus.Location = New-Object System.Drawing.Point(30, 210)
$lblOffboardStatus.Size = New-Object System.Drawing.Size(380, 180) 
$pnlOffboardEmp.Controls.Add($lblOffboardStatus)

$btnBackOffboardMenu = New-Object System.Windows.Forms.Button
$btnBackOffboardMenu.Text = "< Back"
$btnBackOffboardMenu.Size = New-Object System.Drawing.Size(75, 30)
$btnBackOffboardMenu.Location = New-Object System.Drawing.Point(10, 10)
$btnBackOffboardMenu.Add_Click({ 
    $pnlOffboardEmp.Visible = $false; $pnlOffboard.Visible = $true
    $lblOffboardStatus.Text = ""
    $txtSearch.Clear()
})
$pnlOffboardEmp.Controls.Add($btnBackOffboardMenu)


# 90-DAY DELETION PANEL
$pnl90Day = New-Object System.Windows.Forms.Panel
$pnl90Day.Size = $form.ClientSize
$pnl90Day.Visible = $false

$lbl90DayTitle = New-Object System.Windows.Forms.Label
$lbl90DayTitle.Text = "Permanent Employee Account Deletion"
$lbl90DayTitle.Location = New-Object System.Drawing.Point(30, 50)
$lbl90DayTitle.AutoSize = $true
$lbl90DayTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$pnl90Day.Controls.Add($lbl90DayTitle)

$lblSearch90 = New-Object System.Windows.Forms.Label
$lblSearch90.Text = "Enter Employee Full Name or Username:"
$lblSearch90.Location = New-Object System.Drawing.Point(30, 90)
$lblSearch90.AutoSize = $true
$pnl90Day.Controls.Add($lblSearch90)

$txtSearch90 = New-Object System.Windows.Forms.TextBox
$txtSearch90.Location = New-Object System.Drawing.Point(30, 120)
$txtSearch90.Size = New-Object System.Drawing.Size(250, 25)
$pnl90Day.Controls.Add($txtSearch90)

$btnSearch90Day = New-Object System.Windows.Forms.Button
$btnSearch90Day.Text = "Search domain"
$btnSearch90Day.Location = New-Object System.Drawing.Point(30, 160)
$btnSearch90Day.Size = New-Object System.Drawing.Size(150, 40)
$pnl90Day.Controls.Add($btnSearch90Day)

$lbl90DayStatus = New-Object System.Windows.Forms.Label
$lbl90DayStatus.Location = New-Object System.Drawing.Point(30, 220)
$lbl90DayStatus.Size = New-Object System.Drawing.Size(380, 150)
$pnl90Day.Controls.Add($lbl90DayStatus)

$btnBack90Day = New-Object System.Windows.Forms.Button
$btnBack90Day.Text = "< Back"
$btnBack90Day.Size = New-Object System.Drawing.Size(75, 30)
$btnBack90Day.Location = New-Object System.Drawing.Point(10, 10)
$btnBack90Day.Add_Click({ 
    $pnl90Day.Visible = $false; $pnlOffboard.Visible = $true
    $lbl90DayStatus.Text = ""
    $txtSearch90.Clear()
})
$pnl90Day.Controls.Add($btnBack90Day)


# NEW HIRE ENTRY FORM
$pnlNewHire = New-Object System.Windows.Forms.Panel
$pnlNewHire.Size = $form.ClientSize
$pnlNewHire.Visible = $false

# function to generate labels/inputs
$y = 60
function Add-FormField ($labelText, $control) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $labelText
    $lbl.Location = New-Object System.Drawing.Point(30, ($script:y + 3))
    $lbl.AutoSize = $true
    $pnlNewHire.Controls.Add($lbl)

    $control.Location = New-Object System.Drawing.Point(150, $script:y)
    $control.Size = New-Object System.Drawing.Size(250, 25)
    $pnlNewHire.Controls.Add($control)
    
    $script:y += 35
}

# dynamic fields
$cmbLocation = New-Object System.Windows.Forms.ComboBox; $cmbLocation.DropDownStyle = 'DropDownList'
$Global:ConfigData.Keys | ForEach-Object { [void]$cmbLocation.Items.Add($_) }
Add-FormField "Location:" $cmbLocation

$cmbOffice = New-Object System.Windows.Forms.ComboBox; $cmbOffice.DropDownStyle = 'DropDownList'
Add-FormField "Office:" $cmbOffice

$cmbDept = New-Object System.Windows.Forms.ComboBox; $cmbDept.DropDownStyle = 'DropDownList'
Add-FormField "Department:" $cmbDept

# location event handler (updates Office and Dept dropdowns)
$cmbLocation.Add_SelectedIndexChanged({
    $selectedLocation = $cmbLocation.SelectedItem
    $locData = $Global:ConfigData[$selectedLocation]

    # update offices
    $cmbOffice.Items.Clear()
    $locData.Offices.Keys | ForEach-Object { [void]$cmbOffice.Items.Add($_) }
    
    # auto-select the office if location is LA or MX (each have only 1 location)
    if ($selectedLocation -eq "BlueStar LA" -or $selectedLocation -eq "BlueStar MX") {
        $cmbOffice.SelectedIndex = 0
    } else {
        $cmbOffice.SelectedIndex = -1
    }

    # update departments
    $cmbDept.Items.Clear()
    $locData.Departments | Sort-Object | ForEach-Object { [void]$cmbDept.Items.Add($_) }
    $cmbDept.SelectedIndex = -1
})

# static fields
$txtFirst = New-Object System.Windows.Forms.TextBox
Add-FormField "First Name:" $txtFirst

$txtLast = New-Object System.Windows.Forms.TextBox
Add-FormField "Last Name:" $txtLast

$txtJobTitle = New-Object System.Windows.Forms.TextBox
Add-FormField "Job Title:" $txtJobTitle

$cmbDesc = New-Object System.Windows.Forms.ComboBox; $cmbDesc.DropDownStyle = 'DropDownList'
"Hybrid", "Office", "Remote" | ForEach-Object { [void]$cmbDesc.Items.Add($_) }
Add-FormField "Office/Hybrid:" $cmbDesc

$txtManager = New-Object System.Windows.Forms.TextBox
Add-FormField "Manager (Name):" $txtManager

# submit button
$script:y += 10
$btnSubmit = New-Object System.Windows.Forms.Button
$btnSubmit.Text = "Create AD User"
$btnSubmit.Size = New-Object System.Drawing.Size(150, 40)
$btnSubmit.Location = New-Object System.Drawing.Point(150, $y)
$pnlNewHire.Controls.Add($btnSubmit)

# status label 
$script:y += 50
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(30, $y)
$lblStatus.Size = New-Object System.Drawing.Size(400, 60)
$lblStatus.ForeColor = [System.Drawing.Color]::Blue
$pnlNewHire.Controls.Add($lblStatus)

# proceed to Mailbox prompt
$script:y += 65
$lblMailboxPrompt = New-Object System.Windows.Forms.Label
$lblMailboxPrompt.Text = "Proceed to Mailbox Provisioning?"
$lblMailboxPrompt.AutoSize = $true
$lblMailboxPrompt.Location = New-Object System.Drawing.Point(135, $y)
$lblMailboxPrompt.Visible = $false
$pnlNewHire.Controls.Add($lblMailboxPrompt)

# mailbox Yes/No btns
$script:y += 25
$btnMailboxYes = New-Object System.Windows.Forms.Button
$btnMailboxYes.Text = "Yes"
$btnMailboxYes.Size = New-Object System.Drawing.Size(70, 30)
$btnMailboxYes.Location = New-Object System.Drawing.Point(145, $y)
$btnMailboxYes.Visible = $false
$btnMailboxYes.Add_Click({
    try {
        $psArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $script:mailboxScriptPath_Auto,
            "-AutoUser", $script:provisionedUser
        )
        Start-Process powershell.exe -ArgumentList $psArgs -Verb RunAs
        
        # return to Menu and reset form state
        $pnlNewHire.Visible = $false
        $pnlMain.Visible = $true
        
        $lblStatus.Text = ""
        $lblMailboxPrompt.Visible = $false
        $btnMailboxYes.Visible = $false
        $btnMailboxNo.Visible = $false
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to launch Mailbox Provisioning script.", "Error", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})
$pnlNewHire.Controls.Add($btnMailboxYes)

$btnMailboxNo = New-Object System.Windows.Forms.Button
$btnMailboxNo.Text = "No"
$btnMailboxNo.Size = New-Object System.Drawing.Size(70, 30)
$btnMailboxNo.Location = New-Object System.Drawing.Point(235, $y)
$btnMailboxNo.Visible = $false
$btnMailboxNo.Add_Click({
    [System.Windows.Forms.MessageBox]::Show("Skipped Mailbox Provisioning for $script:provisionedUser.", "Notice", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
    
    $pnlNewHire.Visible = $false
    $pnlMain.Visible = $true
    
    $lblStatus.Text = ""
    $lblMailboxPrompt.Visible = $false
    $btnMailboxYes.Visible = $false
    $btnMailboxNo.Visible = $false
})
$pnlNewHire.Controls.Add($btnMailboxNo)

# back btn
$btnBackOnboard = New-Object System.Windows.Forms.Button
$btnBackOnboard.Text = "< Back"
$btnBackOnboard.Size = New-Object System.Drawing.Size(75, 30)
$btnBackOnboard.Location = New-Object System.Drawing.Point(10, 10)
$btnBackOnboard.Add_Click({ 
    $pnlNewHire.Visible = $false; $pnlOnboard.Visible = $true 
    $lblStatus.Text = ""
    $lblMailboxPrompt.Visible = $false
    $btnMailboxYes.Visible = $false
    $btnMailboxNo.Visible = $false
})
$pnlNewHire.Controls.Add($btnBackOnboard)

# trigger init data load - defaults to US
$cmbLocation.SelectedItem = "BlueStar US"

# ==============================================================================
# AD ONBOARDING LOGIC
# ==============================================================================
$btnSubmit.Add_Click({
    $lblStatus.ForeColor = [System.Drawing.Color]::Black
    $lblStatus.Text = "Processing..."
    
    # hide mailbox prompt during processing
    $lblMailboxPrompt.Visible = $false
    $btnMailboxYes.Visible = $false
    $btnMailboxNo.Visible = $false
    $form.Refresh()

    # input validation
    if (-not $cmbLocation.SelectedItem -or -not $cmbOffice.SelectedItem -or -not $cmbDept.SelectedItem -or -not $txtFirst.Text -or -not $txtLast.Text) {
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
        $lblStatus.Text = "Error: Location, Office, Department, First, and Last Name are required."
        return
    }

    $first = $txtFirst.Text.Trim()
    $last = $txtLast.Text.Trim()
    
    $locName = $cmbLocation.SelectedItem
    $officeName = $cmbOffice.SelectedItem
    $deptString = $cmbDept.SelectedItem
    
    $locData = $Global:ConfigData[$locName]
    $officeData = $locData.Offices[$officeName]
    
    # builds target path for AD
    if ($deptString -eq "Users") {
        $targetPath = "CN=Users,$BaseDN"
        $explorerPath = "$Domain\Users"
    } else {
        $targetPath = "OU=$deptString,OU=$($locData.ADName),$BaseDN"
        $explorerPath = "$Domain\$locName\$deptString" 
    }

    # generate logon name (f-last logic with collision check)
    $sam = ("$($first.Substring(0,1))$last" -replace '\s','').ToLower()
    if (Get-ADUser -Filter "sAMAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        $sam = ("$first$last" -replace '\s','').ToLower()
    }
    
    $upn = "$sam@$Domain"
    $email = "$sam@$Domain"
    $display = "$first $last"
    
    # manager DN lookup
    $managerDN = $null
    if ($txtManager.Text) {
        $mgr = Get-ADUser -Filter "Name -eq '$($txtManager.Text)'" -ErrorAction SilentlyContinue
        if ($mgr) { 
            $managerDN = $mgr.DistinguishedName 
        } else {
            [System.Windows.Forms.MessageBox]::Show("Manager '$($txtManager.Text)' not found in AD. Creating user without manager field.", "Warning", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    }

    # Create the AD User Object
    try {
        $pass = ConvertTo-SecureString "Password1!" -AsPlainText -Force
        
        $userParams = @{
            Name              = $display
            SamAccountName    = $sam
            UserPrincipalName = $upn
            GivenName         = $first
            Surname           = $last
            DisplayName       = $display
            Description       = $cmbDesc.SelectedItem
            Office            = $officeName
            OfficePhone       = $officeData.Phone
            EmailAddress      = $email
            HomePage          = "www.$Domain"
            Title             = $txtJobTitle.Text
            Department        = $deptString
            Company           = $officeData.Company
            StreetAddress     = $officeData.Street
            City              = $officeData.City
            State             = $officeData.State
            PostalCode        = $officeData.Zip
            Country           = $officeData.Country
            AccountPassword   = $pass
            Enabled           = $true
            Path              = $targetPath
        }

        if ($managerDN) { $userParams.Add("Manager", $managerDN) }

        # save the created user directly into a variable
        $newUser = New-ADUser @userParams -PassThru

        # add to Security Groups using newly created user object
        foreach ($group in $DefaultGroups) {
            Add-ADGroupMember -Identity $group -Members $newUser -ErrorAction SilentlyContinue
        }

        # store SAM account name globally so the 'Yes' button can reference it
        $script:provisionedUser = $sam

        # success message
        $lblStatus.ForeColor = [System.Drawing.Color]::Green
        $lblStatus.Text = "User '$sam' created.`nPlease double-check the user properties in Active Directory:`n$explorerPath"
        
        # reveal Mailbox prompt
        $lblMailboxPrompt.Visible = $true
        $btnMailboxYes.Visible = $true
        $btnMailboxNo.Visible = $true
        
        # clear fields for next entry
        $txtFirst.Clear(); $txtLast.Clear(); $txtJobTitle.Clear(); $txtManager.Clear()
        $cmbOffice.SelectedIndex = -1; $cmbDept.SelectedIndex = -1; $cmbDesc.SelectedIndex = -1
        $cmbLocation.SelectedItem = "BlueStar US"
        
    } catch {
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
        $lblStatus.Text = "Error: $($_.Exception.Message)"
    }
})


# ==============================================================================
# AD OFFBOARDING LOGIC
# ==============================================================================
$btnSearchOffboard.Add_Click({
    $lblOffboardStatus.Text = "Searching Active Directory..."
    $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Black
    $form.Refresh()

    $searchTerm = $txtSearch.Text.Trim()
    
    if (-not $searchTerm) {
        $lblOffboardStatus.Text = "Please enter a name or username."
        $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Red
        return
    }

    # find user in AD
    $targetUser = $null
    try {
        $targetUser = Get-ADUser -Filter "SamAccountName -eq '$searchTerm' -or Name -eq '$searchTerm' -or DisplayName -eq '$searchTerm'" -Properties DisplayName -ErrorAction Stop
    } catch {
        $lblOffboardStatus.Text = "Error communicating with Active Directory."
        $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Red
        return
    }

    # handle multiple or 0 matches
    if ($null -eq $targetUser) {
        $lblOffboardStatus.Text = "User '$searchTerm' not found in Active Directory."
        $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Red
        return
    } elseif ($targetUser.Count -gt 1) {
        $lblOffboardStatus.Text = "Multiple users found. Please search again using the exact username (SamAccountName)."
        $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Red
        return
    }

    # conf prompt
    $msgResult = [System.Windows.Forms.MessageBox]::Show("Are you sure you would like to proceed with offboarding $($targetUser.Name)?", "Confirm Offboarding", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    
    # if NO, back out to menu
    if ($msgResult -eq 'No') {
        $pnlOffboardEmp.Visible = $false
        $pnlMain.Visible = $true
        $txtSearch.Clear()
        $lblOffboardStatus.Text = ""
        return
    }

    # if YES, continue with offboarding
    try {
        $lblOffboardStatus.Text = "Offboarding $($targetUser.Name)..."
        $form.Refresh()

        # 1. change the password to Terminated1!
        $pass = ConvertTo-SecureString "Terminated1!" -AsPlainText -Force
        Set-ADAccountPassword -Identity $targetUser -NewPassword $pass -Reset -ErrorAction Stop

        # 2. disable account
        Disable-ADAccount -Identity $targetUser -ErrorAction Stop

        # 3. enable 'User cannot change password'
        $userDN = $targetUser.DistinguishedName
        $acl = Get-Acl "AD:\$userDN"
        $sid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-10") # Principal 'Self'
        $guid = New-Object Guid("ab721a53-1e2f-11d0-9819-00aa0040529b") # Change Password Extended Right
        $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, 'ExtendedRight', 'Deny', $guid)
        $acl.AddAccessRule($ace)
        Set-Acl "AD:\$userDN" $acl

        # 4. remove all groups except 'Domain Users'
        $userGroups = Get-ADPrincipalGroupMembership -Identity $targetUser | Where-Object { $_.Name -ne 'Domain Users' }
        if ($userGroups) {
            Remove-ADPrincipalGroupMembership -Identity $targetUser -MemberOf $userGroups -Confirm:$false -ErrorAction Continue
        }

        # 5. clear Department and IP Phone tab
        Set-ADUser -Identity $targetUser -Clear Department, ipPhone -ErrorAction Stop

        # final Success State formatting using a here-string for clean line breaks
        $successText = @"
Complete! $($targetUser.Name) has been successfully offboarded.
- Password changed to: Terminated1!
- User Cannot Change Password
- Account Disabled
- Deleted Security & Email Groups (Member Of)
- Removed Department text (Organization)
- Phone extension removed (Telephones)
"@
        
        $lblOffboardStatus.Text = $successText
        $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Green
        $txtSearch.Clear()

    } catch {
        $lblOffboardStatus.Text = "Error during offboarding: $($_.Exception.Message)"
        $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Red
    }
})


# ==============================================================================
# AD 90-DAY DELETION LOGIC
# ==============================================================================
$btnSearch90Day.Add_Click({
    $lbl90DayStatus.Text = "Searching Active Directory..."
    $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Black
    $form.Refresh()

    $searchTerm = $txtSearch90.Text.Trim()
    
    if (-not $searchTerm) {
        $lbl90DayStatus.Text = "Please enter a name or username."
        $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red
        return
    }

    # find user in AD
    $targetUser = $null
    try {
        $targetUser = Get-ADUser -Filter "SamAccountName -eq '$searchTerm' -or Name -eq '$searchTerm' -or DisplayName -eq '$searchTerm'" -ErrorAction Stop
    } catch {
        $lbl90DayStatus.Text = "Error communicating with Active Directory."
        $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red
        return
    }

    # handle multiple or 0 matches
    if ($null -eq $targetUser) {
        $lbl90DayStatus.Text = "User '$searchTerm' not found in Active Directory."
        $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red
        return
    } elseif ($targetUser.Count -gt 1) {
        $lbl90DayStatus.Text = "Multiple users found. Please search again using the exact username (SamAccountName)."
        $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red
        return
    }

    # 1st prompt: full name check
    $nameInput = Show-NameValidationPrompt -ExpectedName $targetUser.Name
    
    # if user cancelled input, abort.
    if (-not $nameInput) {
        $lbl90DayStatus.Text = "Deletion cancelled by technician."
        $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red
        return
    }

    # verify the name matches exactly before triggering the warning
    if ($nameInput -ne $targetUser.Name) {
        [System.Windows.Forms.MessageBox]::Show("The name entered did not match '$($targetUser.Name)'. Deletion aborted.", "Validation Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        $lbl90DayStatus.Text = "Validation failed. Deletion aborted."
        $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red
        return
    }

    # 2nd prompt: warning conf
    $msgResult = [System.Windows.Forms.MessageBox]::Show("WARNING: This will permanently delete the account from Active Directory. Are you sure you want to do this?", "Confirm Deletion", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    
    # if NO, back out to menu
    if ($msgResult -eq 'No') {
        $pnl90Day.Visible = $false
        $pnlMain.Visible = $true
        $txtSearch90.Clear()
        $lbl90DayStatus.Text = ""
        return
    }

    # if YES, execute deletion
    try {
        $lbl90DayStatus.Text = "Deleting $($targetUser.Name)..."
        $form.Refresh()

        # ensure "Protect object from accidental deletion" is unchecked
        Set-ADObject -Identity $targetUser.DistinguishedName -ProtectedFromAccidentalDeletion $false -ErrorAction SilentlyContinue

        # execute Deletion recursively using Remove-ADObject. 
        # critical for users who have Exchange ActiveSync leaf objects linked to them. Standard Remove-ADUser fails on these.
        Remove-ADObject -Identity $targetUser.DistinguishedName -Recursive -Confirm:$false -ErrorAction Stop

        $lbl90DayStatus.Text = "Complete! $($targetUser.Name) has been permanently deleted from Active Directory."
        $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Green
        $txtSearch90.Clear()
    } catch {
        $lbl90DayStatus.Text = "Error during deletion: $($_.Exception.Message)"
        $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red
    }
})


# add panels and launch
$form.Controls.Add($pnlMain)
$form.Controls.Add($pnlOnboard)
$form.Controls.Add($pnlNewHire)
$form.Controls.Add($pnlOffboard)
$form.Controls.Add($pnlOffboardEmp)
$form.Controls.Add($pnl90Day)

[void]$form.ShowDialog()
