<#
.SYNOPSIS
    GUI based AD onboard/offboard tool 
#>

Requires -Modules ActiveDirectory
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==============================================================================
# CONFIGURATION DATA
# ==============================================================================
$Domain = "bluestarinc.com"
$BaseDN = "DC=bluestarinc,DC=com"

# master config for locations, departments, and offices
$Global:ConfigData = @{
    "BlueStar US" = @{
        ADName = "BlueStar_US"
        Departments = @("Accounting", "Administration", "Business Analytics", "Executive", "IT", "Marketing", "Purchasing", "Sales", "Tech Support", "Warehouse", "Users")
        Offices = @{
            "Hebron" = @{ Phone="(859) 371-4423 Ext. "; Company="BlueStar US"; Street="3345 Point Pleasant Road"; City="Hebron"; State="KY"; Zip="41048"; Country="US" }
            "California" = @{ Phone="(949) 783-3388 Ext. "; Company="BlueStar US"; Street="23161 Mill Creek Drive | Suite 200"; City="Laguna Hills"; State="CA"; Zip="92653"; Country="US" }
            "Cleveland" = @{ Phone="(800) 354-9776 Ext. "; Company="BlueStar US"; Street="212782 Prospect Road, Floor 2"; City="Strongsville"; State="OH"; Zip="44149"; Country="US" }
        }
    }
    "BlueStar CA" = @{
        ADName = "BlueStar_CA"
        Departments = @("Accounting", "Administration", "Customer Service", "Executive", "Marketing", "Sales", "Tech Support", "Warehouse", "Users")
        Offices = @{
            "Toronto" = @{ Phone="(800) 317-1132 Ext. "; Company="BlueStar Canada"; Street="6790 Century Ave. Suite 404"; City="Mississauga"; State="ON"; Zip="L5N2V8"; Country="Canada" }
            "Montreal" = @{ Phone="(800) 317-2323 Ext. "; Company="BlueStar Canada"; Street="6830 Côte-de-Liesse"; City="Montreal"; State="QC"; Zip="H4T2A1"; Country="Canada" }
        }
    }
    "BlueStar LA" = @{
        ADName = "BlueStar_LA"
        Departments = @("Accounting", "Customer Service", "Executive", "Marketing", "Purchasing", "Sales", "Technical", "Warehouse", "Users")
        Offices = @{
            "Miramar" = @{ Phone="(954) 485-1931 Ext. "; Company="BlueStar Latin America"; Street="3561 Enterprise Way"; City="Miramar"; State="FL"; Zip="33025"; Country="US" }
        }
    }
    "BlueStar MX" = @{
        ADName = "BlueStar_MX"
        Departments = @("Accounting", "Customer Service", "Executive", "Marketing", "Purchasing", "Sales", "Technical", "Warehouse", "Users")
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

# ==============================================================================
# GUI SETUP
# ==============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Onboarding/Offboarding Tool"
$form.Size = New-Object System.Drawing.Size(450, 600) 
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
$pnlOnboard.Controls.Add($btnMailbox)

$btnBackMain = New-Object System.Windows.Forms.Button
$btnBackMain.Text = "← Back"
$btnBackMain.Size = New-Object System.Drawing.Size(75, 30)
$btnBackMain.Location = New-Object System.Drawing.Point(10, 10)
$btnBackMain.Add_Click({ $pnlOnboard.Visible = $false; $pnlMain.Visible = $true })
$pnlOnboard.Controls.Add($btnBackMain)

# NEW HIRE ENTRY FORM
$pnlNewHire = New-Object System.Windows.Forms.Panel
$pnlNewHire.Size = $form.ClientSize
$pnlNewHire.Visible = $false

$btnBackOnboard = New-Object System.Windows.Forms.Button
$btnBackOnboard.Text = "← Back"
$btnBackOnboard.Size = New-Object System.Drawing.Size(75, 30)
$btnBackOnboard.Location = New-Object System.Drawing.Point(10, 10)
$btnBackOnboard.Add_Click({ $pnlNewHire.Visible = $false; $pnlOnboard.Visible = $true })
$pnlNewHire.Controls.Add($btnBackOnboard)

# helper func to gen labels/inputs
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
$Global:ConfigData.Keys | Sort-Object | ForEach-Object { [void]$cmbLocation.Items.Add($_) }
Add-FormField "Location:" $cmbLocation

$cmbOffice = New-Object System.Windows.Forms.ComboBox; $cmbOffice.DropDownStyle = 'DropDownList'
Add-FormField "Office:" $cmbOffice

$cmbDept = New-Object System.Windows.Forms.ComboBox; $cmbDept.DropDownStyle = 'DropDownList'
Add-FormField "Department:" $cmbDept

# location event handler (updates Office and Dept dropdowns dynamically)
$cmbLocation.Add_SelectedIndexChanged({
    $selectedLocation = $cmbLocation.SelectedItem
    $locData = $Global:ConfigData[$selectedLocation]

    # update offices
    $cmbOffice.Items.Clear()
    $locData.Offices.Keys | Sort-Object | ForEach-Object { [void]$cmbOffice.Items.Add($_) }
    if ($cmbOffice.Items.Count -gt 0) { $cmbOffice.SelectedIndex = 0 }

    # update departments
    $cmbDept.Items.Clear()
    $locData.Departments | Sort-Object | ForEach-Object { [void]$cmbDept.Items.Add($_) }
    if ($cmbDept.Items.Count -gt 0) { $cmbDept.SelectedIndex = 0 }
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

# submit & status
$script:y += 10
$btnSubmit = New-Object System.Windows.Forms.Button
$btnSubmit.Text = "Provision AD User"
$btnSubmit.Size = New-Object System.Drawing.Size(150, 40)
$btnSubmit.Location = New-Object System.Drawing.Point(150, $y)
$pnlNewHire.Controls.Add($btnSubmit)

$script:y += 50
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(30, $y)
$lblStatus.Size = New-Object System.Drawing.Size(370, 60)
$lblStatus.ForeColor = [System.Drawing.Color]::Blue
$pnlNewHire.Controls.Add($lblStatus)

# triggers initial data load
if ($cmbLocation.Items.Count -gt 0) { $cmbLocation.SelectedIndex = 0 }

# ==============================================================================
# AD CREATION LOGIC
# ==============================================================================
$btnSubmit.Add_Click({
    $lblStatus.ForeColor = [System.Drawing.Color]::Black
    $lblStatus.Text = "Processing..."
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
    
    # dynamically builds target path
    if ($deptString -eq "Users") {
        $targetPath = "CN=Users,$BaseDN"
    } else {
        $targetPath = "OU=$deptString,OU=$($locData.ADName),$BaseDN"
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

    # create the AD User Object
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

        $lblStatus.ForeColor = [System.Drawing.Color]::Green
        $lblStatus.Text = "Success! Created user $sam in $deptString.`nDefault groups assigned."
        
        # clear fields for next entry
        $txtFirst.Clear(); $txtLast.Clear(); $txtJobTitle.Clear(); $txtManager.Clear()
        
    } catch {
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
        $lblStatus.Text = "Error: $($_.Exception.Message)"
    }
})

# add panels and launch
$form.Controls.Add($pnlMain)
$form.Controls.Add($pnlOnboard)
$form.Controls.Add($pnlNewHire)
[void]$form.ShowDialog()
