<#
.SYNOPSIS
    GUI based AD onboard/offboard & user management tool for BlueStar, Inc. 2026
#>

#req: -Modules ActiveDirectory
Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;
Add-Type -AssemblyName System.DirectoryServices;

# domain info
$Domain = "bluestarinc.com";
$BaseDN = "DC=bluestarinc,DC=com";

# master config
$Global:ConfigData = [ordered]@{
    "BlueStar US" = @{
        ADName = "BlueStar_US";
        Departments = @("Accounting", "Administration", "Business Analytics", "Executive", "IT", "Marketing", "Purchasing", "Sales", "Tech Support", "Warehouse");
        Offices = [ordered]@{
            "Corporate" = @{ Phone="(859) 371-4423 Ext. "; Company="BlueStar US"; Street="3345 Point Pleasant Road"; City="Hebron"; State="KY"; Zip="41048"; Country="US" };
            "California" = @{ Phone="(949) 783-3388 Ext. "; Company="BlueStar US"; Street="23161 Mill Creek Drive, Suite 200"; City="Laguna Hills"; State="CA"; Zip="92653"; Country="US" };
            "Cleveland" = @{ Phone="(800) 354-9776 Ext. "; Company="BlueStar US"; Street="212782 Prospect Road, Floor 2"; City="Strongsville"; State="OH"; Zip="44149"; Country="US" }
        }
    };
    "BlueStar CA" = @{
        ADName = "BlueStar_CA";
        Departments = @("Accounting", "Administration", "Customer Service", "Executive", "Marketing", "Sales", "Tech Support", "Warehouse");
        Offices = @{
            "Toronto" = @{ Phone="(800) 317-1132 Ext. "; Company="BlueStar Canada"; Street="6790 Century Ave. Suite 404"; City="Mississauga"; State="ON"; Zip="L5N2V8"; Country="CA" };
            "Montreal" = @{ Phone="(800) 317-2323 Ext. "; Company="BlueStar Canada"; Street="6830 Côte-de-Liesse"; City="Montreal"; State="QC"; Zip="H4T2A1"; Country="CA" }
        }
    };
    "BlueStar LA" = @{
        ADName = "BlueStar_LA";
        Departments = @("Accounting", "Customer Service", "Executive", "Marketing", "Purchasing", "Sales", "Technical", "Warehouse");
        Offices = @{
            "Miramar" = @{ Phone="(954) 485-1931 Ext. "; Company="BlueStar Latin America"; Street="3561 Enterprise Way"; City="Miramar"; State="FL"; Zip="33025"; Country="US" }
        }
    };
    "BlueStar MX" = @{
        ADName = "BlueStar_MX";
        Departments = @("Accounting", "Customer Service", "Executive", "Marketing", "Purchasing", "Sales", "Technical", "Warehouse");
        Offices = @{
            "Mexico" = @{ Phone="+52 (55) 5357-0087 Ext. "; Company="BlueStar Mexico"; Street="Av. San Isidro # 97 piso 2 Col. San Francisco Tetecala"; City="Azcapotzalco"; State="CP"; Zip="02760"; Country="MX" }
        }
    }
};

$DefaultGroups = @(
    "Webex_User", "VPN_USERS", "Service Desk Users", 
    "Secure_Wifi", "PasswordAccountLockout_Standard", 
    "OWA_2FA", "BlueStar Barracuda"
);

# variables to hold state
$script:provisionedUser = "";
$script:targetUserDN = "";
$script:targetUserSam = "";

# script execution paths
$script:mailboxScriptPath_Manual = "\\bsqnap\PST\RemoteMailboxProvisioning\Create-RemoteMailboxV2.ps1";
$script:mailboxScriptPath_Auto = "S:\IT\it.priv\IT Support Desk\User & Asset Management\BSTools\Employee Onboarding-Offboarding Tool\Content\MailboxProvisionTool_Auto.ps1";
$script:deviceInfoScriptPath = "S:\IT\it.priv\IT Support Desk\User & Asset Management\BSTools\Device Lookup Tool\Content\DeviceInfoLookup.ps1";

# =============
# HELPER FUNCT.
# =============

function Show-PasswordResetPrompt {
    param([string]$TargetUser)
    $inputForm = New-Object System.Windows.Forms.Form;
    $inputForm.Text = "Reset Password";
    $inputForm.Size = New-Object System.Drawing.Size(350, 200);
    $inputForm.StartPosition = "CenterParent";
    $inputForm.FormBorderStyle = "FixedDialog";
    $inputForm.MaximizeBox = $false;
    $inputForm.MinimizeBox = $false;

    $lbl = New-Object System.Windows.Forms.Label;
    $lbl.Text = "Enter a new temporary password for $($TargetUser):";
    $lbl.Location = New-Object System.Drawing.Point(15, 15);
    $lbl.AutoSize = $true;
    $inputForm.Controls.Add($lbl);

    $txt = New-Object System.Windows.Forms.TextBox;
    $txt.Location = New-Object System.Drawing.Point(15, 40);
    $txt.Size = New-Object System.Drawing.Size(300, 25);
    $txt.UseSystemPasswordChar = $true;
    $inputForm.Controls.Add($txt);

    $chk = New-Object System.Windows.Forms.CheckBox;
    $chk.Text = "Require password change at next logon";
    $chk.Location = New-Object System.Drawing.Point(15, 75);
    $chk.Size = New-Object System.Drawing.Size(300, 25);
    $chk.Checked = $true;
    $inputForm.Controls.Add($chk);

    $btnOk = New-Object System.Windows.Forms.Button;
    $btnOk.Text = "Confirm";
    $btnOk.Location = New-Object System.Drawing.Point(75, 115);
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK;
    $inputForm.Controls.Add($btnOk);

    $btnCancel = New-Object System.Windows.Forms.Button;
    $btnCancel.Text = "Cancel";
    $btnCancel.Location = New-Object System.Drawing.Point(185, 115);
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel;
    $inputForm.Controls.Add($btnCancel);

    $inputForm.AcceptButton = $btnOk;
    $inputForm.CancelButton = $btnCancel;

    $result = $inputForm.ShowDialog();
    if (($result) -eq ([System.Windows.Forms.DialogResult]::OK)) { 
        return @{ Password = $txt.Text; RequireChange = $chk.Checked } 
    }
    return $null;
}

function Show-NameValidationPrompt {
    param([string]$ExpectedName)
    $inputForm = New-Object System.Windows.Forms.Form;
    $inputForm.Text = "Final Confirmation";
    $inputForm.Size = New-Object System.Drawing.Size(350, 160);
    $inputForm.StartPosition = "CenterParent";
    $inputForm.FormBorderStyle = "FixedDialog";
    $inputForm.MaximizeBox = $false;
    $inputForm.MinimizeBox = $false;

    $lbl = New-Object System.Windows.Forms.Label;
    $lbl.Text = "To confirm permanent deletion, type the exact name:" + [Environment]::NewLine + $ExpectedName;
    $lbl.Location = New-Object System.Drawing.Point(15, 15);
    $lbl.AutoSize = $true;
    $inputForm.Controls.Add($lbl);

    $txt = New-Object System.Windows.Forms.TextBox;
    $txt.Location = New-Object System.Drawing.Point(15, 55);
    $txt.Size = New-Object System.Drawing.Size(300, 25);
    $inputForm.Controls.Add($txt);

    $btnOk = New-Object System.Windows.Forms.Button;
    $btnOk.Text = "Confirm";
    $btnOk.Location = New-Object System.Drawing.Point(75, 85);
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK;
    $inputForm.Controls.Add($btnOk);

    $btnCancel = New-Object System.Windows.Forms.Button;
    $btnCancel.Text = "Cancel";
    $btnCancel.Location = New-Object System.Drawing.Point(185, 85);
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel;
    $inputForm.Controls.Add($btnCancel);

    $inputForm.AcceptButton = $btnOk;
    $inputForm.CancelButton = $btnCancel;

    $result = $inputForm.ShowDialog();
    if (($result) -eq ([System.Windows.Forms.DialogResult]::OK)) { return $txt.Text; }
    return $null;
}

function Show-InputPrompt {
    param([string]$Title, [string]$Message, [string]$DefaultValue = "", [switch]$IsPassword)
    $inputForm = New-Object System.Windows.Forms.Form;
    $inputForm.Text = $Title;
    $inputForm.Size = New-Object System.Drawing.Size(350, 160);
    $inputForm.StartPosition = "CenterParent";
    $inputForm.FormBorderStyle = "FixedDialog";
    $inputForm.MaximizeBox = $false;
    $inputForm.MinimizeBox = $false;

    $lbl = New-Object System.Windows.Forms.Label;
    $lbl.Text = $Message;
    $lbl.Location = New-Object System.Drawing.Point(15, 15);
    $lbl.AutoSize = $true;
    $inputForm.Controls.Add($lbl);

    $txt = New-Object System.Windows.Forms.TextBox;
    $txt.Location = New-Object System.Drawing.Point(15, 55);
    $txt.Size = New-Object System.Drawing.Size(300, 25);
    $txt.Text = $DefaultValue;
    if ($IsPassword) { $txt.UseSystemPasswordChar = $true }
    $inputForm.Controls.Add($txt);

    $btnOk = New-Object System.Windows.Forms.Button;
    $btnOk.Text = "Confirm";
    $btnOk.Location = New-Object System.Drawing.Point(75, 85);
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK;
    $inputForm.Controls.Add($btnOk);

    $btnCancel = New-Object System.Windows.Forms.Button;
    $btnCancel.Text = "Cancel";
    $btnCancel.Location = New-Object System.Drawing.Point(185, 85);
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel;
    $inputForm.Controls.Add($btnCancel);

    $inputForm.AcceptButton = $btnOk;
    $inputForm.CancelButton = $btnCancel;

    $result = $inputForm.ShowDialog();
    if (($result) -eq ([System.Windows.Forms.DialogResult]::OK)) { return $txt.Text; }
    return $null;
}

# ===
# GUI
# ===
$form = New-Object System.Windows.Forms.Form;
$form.Text = "BSTools - Enterprise Account Hub";
$form.Size = New-Object System.Drawing.Size(660, 780);
$form.StartPosition = "CenterScreen";
$form.FormBorderStyle = "FixedDialog";
$form.MaximizeBox = $false;

$defaultFont = New-Object System.Drawing.Font("Segoe UI", 10);
$form.Font = $defaultFont;

$editToolTip = New-Object System.Windows.Forms.ToolTip;

# ==========
# START MENU
# ==========
$pnlMain = New-Object System.Windows.Forms.Panel;
$pnlMain.Size = $form.ClientSize;
$pnlMain.Visible = $true;

$lblBanner1 = New-Object System.Windows.Forms.Label;
$lblBanner1.Text = "=================== BSTools ===================";
$lblBanner1.ForeColor = [System.Drawing.Color]::Blue;
$lblBanner1.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold);
$lblBanner1.Size = New-Object System.Drawing.Size(650, 20);
$lblBanner1.Location = New-Object System.Drawing.Point(0, 15);
$lblBanner1.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$pnlMain.Controls.Add($lblBanner1);

$lblBanner2 = New-Object System.Windows.Forms.Label;
$lblBanner2.Text = "BlueStar User Management Tool";
$lblBanner2.ForeColor = [System.Drawing.Color]::Black;
$lblBanner2.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold);
$lblBanner2.Size = New-Object System.Drawing.Size(650, 25);
$lblBanner2.Location = New-Object System.Drawing.Point(0, 35);
$lblBanner2.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$pnlMain.Controls.Add($lblBanner2);

$lblBanner3 = New-Object System.Windows.Forms.Label;
$lblBanner3.Text = "Developed by: Chase Bezilla";
$lblBanner3.ForeColor = [System.Drawing.Color]::DarkGray;
$lblBanner3.Size = New-Object System.Drawing.Size(650, 20);
$lblBanner3.Location = New-Object System.Drawing.Point(0, 65);
$lblBanner3.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$pnlMain.Controls.Add($lblBanner3);

$lblBanner4 = New-Object System.Windows.Forms.Label;
$lblBanner4.Text = "For BlueStar, Inc. (2026)";
$lblBanner4.ForeColor = [System.Drawing.Color]::DarkGray;
$lblBanner4.Size = New-Object System.Drawing.Size(650, 20);
$lblBanner4.Location = New-Object System.Drawing.Point(0, 85);
$lblBanner4.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$pnlMain.Controls.Add($lblBanner4);

$lblBanner5 = New-Object System.Windows.Forms.Label;
$lblBanner5.Text = "=============== github.com/xezixa ===============";
$lblBanner5.ForeColor = [System.Drawing.Color]::Blue;
$lblBanner5.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold);
$lblBanner5.Size = New-Object System.Drawing.Size(650, 20);
$lblBanner5.Location = New-Object System.Drawing.Point(0, 105);
$lblBanner5.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$pnlMain.Controls.Add($lblBanner5);

$btnUserMgmtMain = New-Object System.Windows.Forms.Button;
$btnUserMgmtMain.Text = "User Management";
$btnUserMgmtMain.BackColor = [System.Drawing.Color]::LightSteelBlue;
$btnUserMgmtMain.Size = New-Object System.Drawing.Size(200, 50);
$btnUserMgmtMain.Location = New-Object System.Drawing.Point(225, 200);
$btnUserMgmtMain.Add_Click({ 
    $pnlMain.Visible = $false; 
    $pnlUserMgmtSearch.Visible = $true; 

    # cache AD for user smart-search
    if ($txtSearchUser.AutoCompleteCustomSource.Count -eq 0) {
        try {
            $users = Get-ADUser -Filter * -Properties DisplayName -ErrorAction SilentlyContinue;
            $source = New-Object System.Windows.Forms.AutoCompleteStringCollection;
            foreach ($u in $users) {
                if ($u.Name) { [void]$source.Add($u.Name); }
            }
            $txtSearchUser.AutoCompleteCustomSource = $source;
        } catch { }
    }
});
$pnlMain.Controls.Add($btnUserMgmtMain);

$lblMenuDivider = New-Object System.Windows.Forms.Label;
$lblMenuDivider.BackColor = [System.Drawing.Color]::LightSteelBlue;
$lblMenuDivider.Size = New-Object System.Drawing.Size(220, 2);
$lblMenuDivider.Location = New-Object System.Drawing.Point(215, 275);
$pnlMain.Controls.Add($lblMenuDivider);

$btnOnboarding = New-Object System.Windows.Forms.Button;
$btnOnboarding.Text = "Onboarding";
$btnOnboarding.BackColor = [System.Drawing.Color]::LightGreen;
$btnOnboarding.Size = New-Object System.Drawing.Size(200, 50);
$btnOnboarding.Location = New-Object System.Drawing.Point(225, 305);
$btnOnboarding.Add_Click({ $pnlMain.Visible = $false; $pnlOnboard.Visible = $true; });
$pnlMain.Controls.Add($btnOnboarding);

$btnOffboarding = New-Object System.Windows.Forms.Button;
$btnOffboarding.Text = "Offboarding";
$btnOffboarding.BackColor = [System.Drawing.Color]::LightCoral;
$btnOffboarding.Size = New-Object System.Drawing.Size(200, 50);
$btnOffboarding.Location = New-Object System.Drawing.Point(225, 375);
$btnOffboarding.Add_Click({ 
    $pnlMain.Visible = $false; 
    $pnlOffboard.Visible = $true; 
});
$pnlMain.Controls.Add($btnOffboarding);


# ===============
# ONBOARD SUBMENU
# ===============
$pnlOnboard = New-Object System.Windows.Forms.Panel;
$pnlOnboard.Size = $form.ClientSize;
$pnlOnboard.Visible = $false;

$lblOnboardMenuTitle = New-Object System.Windows.Forms.Label;
$lblOnboardMenuTitle.Text = "Employee Onboarding";
$lblOnboardMenuTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold);
$lblOnboardMenuTitle.Size = New-Object System.Drawing.Size(650, 30);
$lblOnboardMenuTitle.Location = New-Object System.Drawing.Point(0, 80);
$lblOnboardMenuTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$pnlOnboard.Controls.Add($lblOnboardMenuTitle);

$btnNewHire = New-Object System.Windows.Forms.Button;
$btnNewHire.Text = "Create New Hire";
$btnNewHire.BackColor = [System.Drawing.Color]::LightGreen;
$btnNewHire.Size = New-Object System.Drawing.Size(200, 50);
$btnNewHire.Location = New-Object System.Drawing.Point(225, 150);
$btnNewHire.Add_Click({ $pnlOnboard.Visible = $false; $pnlNewHire.Visible = $true; });
$pnlOnboard.Controls.Add($btnNewHire);

$btnMailbox = New-Object System.Windows.Forms.Button;
$btnMailbox.Text = "Mailbox Provisioning";
$btnMailbox.BackColor = [System.Drawing.Color]::LightBlue;
$btnMailbox.Size = New-Object System.Drawing.Size(200, 50);
$btnMailbox.Location = New-Object System.Drawing.Point(225, 220);
$btnMailbox.Add_Click({
    try {
        $psArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script:mailboxScriptPath_Manual);
        Start-Process powershell.exe -ArgumentList $psArgs -Verb RunAs;
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to launch Mailbox Provisioning script.", "Error", 0, [System.Windows.Forms.MessageBoxIcon]::Error);
    }
});
$pnlOnboard.Controls.Add($btnMailbox);

$btnBackMain = New-Object System.Windows.Forms.Button;
$btnBackMain.Text = "< Back";
$btnBackMain.Size = New-Object System.Drawing.Size(75, 30);
$btnBackMain.Location = New-Object System.Drawing.Point(10, 10);
$btnBackMain.Add_Click({ $pnlOnboard.Visible = $false; $pnlMain.Visible = $true; });
$pnlOnboard.Controls.Add($btnBackMain);

# ================
# OFFBOARD SUBMENU
# ================
$pnlOffboard = New-Object System.Windows.Forms.Panel;
$pnlOffboard.Size = $form.ClientSize;
$pnlOffboard.Visible = $false;

$lblOffboardMenuTitle = New-Object System.Windows.Forms.Label;
$lblOffboardMenuTitle.Text = "Employee Offboarding";
$lblOffboardMenuTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold);
$lblOffboardMenuTitle.Size = New-Object System.Drawing.Size(650, 30);
$lblOffboardMenuTitle.Location = New-Object System.Drawing.Point(0, 80);
$lblOffboardMenuTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$pnlOffboard.Controls.Add($lblOffboardMenuTitle);

$btnOffboardEmp = New-Object System.Windows.Forms.Button;
$btnOffboardEmp.Text = "Initial Offboarding";
$btnOffboardEmp.BackColor = [System.Drawing.Color]::LightCoral;
$btnOffboardEmp.Size = New-Object System.Drawing.Size(200, 50);
$btnOffboardEmp.Location = New-Object System.Drawing.Point(225, 150);
$btnOffboardEmp.Add_Click({ 
    $pnlOffboard.Visible = $false; 
    $pnlOffboardEmp.Visible = $true; 
    
    # autofill AD cached entries
    if ($txtSearch.AutoCompleteCustomSource.Count -eq 0) {
        try {
            $users = Get-ADUser -Filter * -Properties DisplayName -ErrorAction SilentlyContinue;
            $source = New-Object System.Windows.Forms.AutoCompleteStringCollection;
            foreach ($u in $users) {
                if ($u.Name) { [void]$source.Add($u.Name); }
            }
            $txtSearch.AutoCompleteCustomSource = $source;
        } catch { }
    }
});
$pnlOffboard.Controls.Add($btnOffboardEmp);

$btn90Day = New-Object System.Windows.Forms.Button;
$btn90Day.Text = "90-Day Deletion";
$btn90Day.BackColor = [System.Drawing.Color]::DarkRed;
$btn90Day.Size = New-Object System.Drawing.Size(200, 50);
$btn90Day.Location = New-Object System.Drawing.Point(225, 220);
$btn90Day.Add_Click({ $pnlOffboard.Visible = $false; $pnl90Day.Visible = $true; });
$pnlOffboard.Controls.Add($btn90Day);

$btnBackMainOff = New-Object System.Windows.Forms.Button;
$btnBackMainOff.Text = "< Back";
$btnBackMainOff.Size = New-Object System.Drawing.Size(75, 30);
$btnBackMainOff.Location = New-Object System.Drawing.Point(10, 10);
$btnBackMainOff.Add_Click({ $pnlOffboard.Visible = $false; $pnlMain.Visible = $true; });
$pnlOffboard.Controls.Add($btnBackMainOff);

# =======================
# OFFBOARD EMPLOYEE PANEL
# =======================
$pnlOffboardEmp = New-Object System.Windows.Forms.Panel;
$pnlOffboardEmp.Size = $form.ClientSize;
$pnlOffboardEmp.Visible = $false;

$lblOffboardEmpTitle = New-Object System.Windows.Forms.Label;
$lblOffboardEmpTitle.Text = "Initial Employee Offboarding";
$lblOffboardEmpTitle.Location = New-Object System.Drawing.Point(0, 50);
$lblOffboardEmpTitle.Size = New-Object System.Drawing.Size(650, 30);
$lblOffboardEmpTitle.AutoSize = $false;
$lblOffboardEmpTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$lblOffboardEmpTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold);
$pnlOffboardEmp.Controls.Add($lblOffboardEmpTitle);

$lblSearch = New-Object System.Windows.Forms.Label;
$lblSearch.Text = "Enter Employee Full Name or Username:";
$lblSearch.Location = New-Object System.Drawing.Point(200, 90);
$lblSearch.AutoSize = $true;
$pnlOffboardEmp.Controls.Add($lblSearch);

$txtSearch = New-Object System.Windows.Forms.TextBox;
$txtSearch.Location = New-Object System.Drawing.Point(200, 120);
$txtSearch.Size = New-Object System.Drawing.Size(250, 25);
$txtSearch.AutoCompleteMode = [System.Windows.Forms.AutoCompleteMode]::SuggestAppend;
$txtSearch.AutoCompleteSource = [System.Windows.Forms.AutoCompleteSource]::CustomSource;
$txtSearch.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $btnSearchOffboard.PerformClick()
        $_.SuppressKeyPress = $true
    }
})
$pnlOffboardEmp.Controls.Add($txtSearch);

$btnSearchOffboard = New-Object System.Windows.Forms.Button;
$btnSearchOffboard.Text = "Search Domain";
$btnSearchOffboard.Location = New-Object System.Drawing.Point(250, 160);
$btnSearchOffboard.Size = New-Object System.Drawing.Size(150, 40);
$pnlOffboardEmp.Controls.Add($btnSearchOffboard);

function Append-ColoredText($rtb, $text, $color) {
    $rtb.SelectionStart = $rtb.TextLength;
    $rtb.SelectionLength = 0;
    $rtb.SelectionColor = $color;
    $rtb.AppendText($text);
    $rtb.SelectionColor = $rtb.ForeColor;
}

$lblOffboardStatus = New-Object System.Windows.Forms.RichTextBox;
$lblOffboardStatus.Location = New-Object System.Drawing.Point(100, 220);
$lblOffboardStatus.Size = New-Object System.Drawing.Size(450, 300); 
$lblOffboardStatus.ReadOnly = $true;
$lblOffboardStatus.BorderStyle = [System.Windows.Forms.BorderStyle]::None;
$lblOffboardStatus.BackColor = $pnlOffboardEmp.BackColor;
$lblOffboardStatus.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::None;
$pnlOffboardEmp.Controls.Add($lblOffboardStatus);

$btnBackOffboardMenu = New-Object System.Windows.Forms.Button;
$btnBackOffboardMenu.Text = "< Back";
$btnBackOffboardMenu.Size = New-Object System.Drawing.Size(75, 30);
$btnBackOffboardMenu.Location = New-Object System.Drawing.Point(10, 10);
$btnBackOffboardMenu.Add_Click({ 
    $pnlOffboardEmp.Visible = $false; $pnlOffboard.Visible = $true; $lblOffboardStatus.Clear(); $txtSearch.Clear();
});
$pnlOffboardEmp.Controls.Add($btnBackOffboardMenu);

# =====================
# 90-DAY DELETION PANEL
# =====================
$pnl90Day = New-Object System.Windows.Forms.Panel;
$pnl90Day.Size = $form.ClientSize;
$pnl90Day.Visible = $false;

$lbl90DayTitle = New-Object System.Windows.Forms.Label;
$lbl90DayTitle.Text = "Permanent Employee Account Deletion";
$lbl90DayTitle.Location = New-Object System.Drawing.Point(0, 50);
$lbl90DayTitle.Size = New-Object System.Drawing.Size(650, 30);
$lbl90DayTitle.AutoSize = $false;
$lbl90DayTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$lbl90DayTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold);
$pnl90Day.Controls.Add($lbl90DayTitle);

$lblSearch90 = New-Object System.Windows.Forms.Label;
$lblSearch90.Text = "Enter Employee Full Name or Username:";
$lblSearch90.Location = New-Object System.Drawing.Point(200, 90);
$lblSearch90.AutoSize = $true;
$pnl90Day.Controls.Add($lblSearch90);

$txtSearch90 = New-Object System.Windows.Forms.TextBox;
$txtSearch90.Location = New-Object System.Drawing.Point(200, 120);
$txtSearch90.Size = New-Object System.Drawing.Size(250, 25);
$pnl90Day.Controls.Add($txtSearch90);

$btnSearch90Day = New-Object System.Windows.Forms.Button;
$btnSearch90Day.Text = "Search domain";
$btnSearch90Day.Location = New-Object System.Drawing.Point(250, 160);
$btnSearch90Day.Size = New-Object System.Drawing.Size(150, 40);
$pnl90Day.Controls.Add($btnSearch90Day);

$lbl90DayStatus = New-Object System.Windows.Forms.Label;
$lbl90DayStatus.Location = New-Object System.Drawing.Point(135, 220);
$lbl90DayStatus.Size = New-Object System.Drawing.Size(380, 150);
$pnl90Day.Controls.Add($lbl90DayStatus);

$btnBack90Day = New-Object System.Windows.Forms.Button;
$btnBack90Day.Text = "< Back";
$btnBack90Day.Size = New-Object System.Drawing.Size(75, 30);
$btnBack90Day.Location = New-Object System.Drawing.Point(10, 10);
$btnBack90Day.Add_Click({ 
    $pnl90Day.Visible = $false; $pnlOffboard.Visible = $true; $lbl90DayStatus.Text = ""; $txtSearch90.Clear();
});
$pnl90Day.Controls.Add($btnBack90Day);

# ===============
# USER MANAGEMENT
# ===============

$pnlUserMgmtSearch = New-Object System.Windows.Forms.Panel;
$pnlUserMgmtSearch.Size = $form.ClientSize;
$pnlUserMgmtSearch.Visible = $false;

$lblUserMgmtTitle = New-Object System.Windows.Forms.Label;
$lblUserMgmtTitle.Text = "User Management";
$lblUserMgmtTitle.Location = New-Object System.Drawing.Point(0, 50);
$lblUserMgmtTitle.Size = New-Object System.Drawing.Size(650, 30);
$lblUserMgmtTitle.AutoSize = $false;
$lblUserMgmtTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$lblUserMgmtTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold);
$pnlUserMgmtSearch.Controls.Add($lblUserMgmtTitle);

$lblUserMgmtSub = New-Object System.Windows.Forms.Label;
$lblUserMgmtSub.Text = "Search Active Directory to load employee profiles and devices.";
$lblUserMgmtSub.Location = New-Object System.Drawing.Point(0, 85);
$lblUserMgmtSub.Size = New-Object System.Drawing.Size(650, 20);
$lblUserMgmtSub.AutoSize = $false;
$lblUserMgmtSub.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$lblUserMgmtSub.ForeColor = [System.Drawing.Color]::DarkGray;
$pnlUserMgmtSearch.Controls.Add($lblUserMgmtSub);

$lblSearchUser = New-Object System.Windows.Forms.Label;
$lblSearchUser.Text = "Enter Employee Name:";
$lblSearchUser.Location = New-Object System.Drawing.Point(165, 140);
$lblSearchUser.AutoSize = $true;
$lblSearchUser.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold);
$pnlUserMgmtSearch.Controls.Add($lblSearchUser);

$txtSearchUser = New-Object System.Windows.Forms.TextBox;
$txtSearchUser.Location = New-Object System.Drawing.Point(165, 165);
$txtSearchUser.Size = New-Object System.Drawing.Size(320, 25);
$txtSearchUser.AutoCompleteMode = [System.Windows.Forms.AutoCompleteMode]::SuggestAppend;
$txtSearchUser.AutoCompleteSource = [System.Windows.Forms.AutoCompleteSource]::CustomSource;

# user search logic
$txtSearchUser.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $btnSearchUserExec.PerformClick()
        $_.SuppressKeyPress = $true
    }
    if ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::A) {
        $txtSearchUser.SelectAll()
        $_.SuppressKeyPress = $true
    }
})
$pnlUserMgmtSearch.Controls.Add($txtSearchUser);

$btnSearchUserExec = New-Object System.Windows.Forms.Button;
$btnSearchUserExec.Text = "Load User Profile";
$btnSearchUserExec.BackColor = [System.Drawing.Color]::LightSteelBlue;
$btnSearchUserExec.Location = New-Object System.Drawing.Point(250, 210);
$btnSearchUserExec.Size = New-Object System.Drawing.Size(150, 45);
$btnSearchUserExec.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold);
$pnlUserMgmtSearch.Controls.Add($btnSearchUserExec);

$lblSearchUserStatus = New-Object System.Windows.Forms.Label;
$lblSearchUserStatus.Location = New-Object System.Drawing.Point(100, 270);
$lblSearchUserStatus.Size = New-Object System.Drawing.Size(450, 50);
$lblSearchUserStatus.TextAlign = [System.Drawing.ContentAlignment]::TopCenter;
$pnlUserMgmtSearch.Controls.Add($lblSearchUserStatus);

$btnBackUserSearch = New-Object System.Windows.Forms.Button;
$btnBackUserSearch.Text = "< Back";
$btnBackUserSearch.Size = New-Object System.Drawing.Size(75, 30);
$btnBackUserSearch.Location = New-Object System.Drawing.Point(10, 10);
$btnBackUserSearch.Add_Click({ 
    $pnlUserMgmtSearch.Visible = $false; $pnlMain.Visible = $true; $lblSearchUserStatus.Text = ""; $txtSearchUser.Clear();
});
$pnlUserMgmtSearch.Controls.Add($btnBackUserSearch);

# =========================
# USER MANAGEMENT DASHBOARD
# =========================

$pnlUserProfile = New-Object System.Windows.Forms.Panel;
$pnlUserProfile.Size = $form.ClientSize;
$pnlUserProfile.Visible = $false;

$btnBackProfile = New-Object System.Windows.Forms.Button;
$btnBackProfile.Text = "< New Search";
$btnBackProfile.Size = New-Object System.Drawing.Size(100, 30);
$btnBackProfile.Location = New-Object System.Drawing.Point(10, 10);
$btnBackProfile.Add_Click({ 
    $pnlUserProfile.Visible = $false; 
    $pnlUserMgmtSearch.Visible = $true; 
    $lblSearchUserStatus.Text = ""; 
    $txtSearchUser.Clear(); 
});
$pnlUserProfile.Controls.Add($btnBackProfile);

# user info header 1
$script:lblProfileName = New-Object System.Windows.Forms.TextBox;
$script:lblProfileName.ReadOnly = $true;
$script:lblProfileName.BorderStyle = [System.Windows.Forms.BorderStyle]::None;
$script:lblProfileName.BackColor = $pnlUserProfile.BackColor;
$script:lblProfileName.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold);
$script:lblProfileName.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center;
$script:lblProfileName.Cursor = [System.Windows.Forms.Cursors]::Hand;
$script:lblProfileName.ForeColor = [System.Drawing.Color]::RoyalBlue;
$script:lblProfileName.Location = New-Object System.Drawing.Point(125, 35);
$script:lblProfileName.Size = New-Object System.Drawing.Size(400, 35);
$editToolTip.SetToolTip($script:lblProfileName, "Double-click to edit");
$pnlUserProfile.Controls.Add($script:lblProfileName);

$script:lblProfileTitle = New-Object System.Windows.Forms.TextBox;
$script:lblProfileTitle.ReadOnly = $true;
$script:lblProfileTitle.BorderStyle = [System.Windows.Forms.BorderStyle]::None;
$script:lblProfileTitle.BackColor = $pnlUserProfile.BackColor;
$script:lblProfileTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular);
$script:lblProfileTitle.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center;
$script:lblProfileTitle.Cursor = [System.Windows.Forms.Cursors]::Hand;
$script:lblProfileTitle.ForeColor = [System.Drawing.Color]::RoyalBlue;
$script:lblProfileTitle.Location = New-Object System.Drawing.Point(125, 70);
$script:lblProfileTitle.Size = New-Object System.Drawing.Size(400, 20);
$editToolTip.SetToolTip($script:lblProfileTitle, "Double-click to edit");
$pnlUserProfile.Controls.Add($script:lblProfileTitle);

$lblProfileDivider = New-Object System.Windows.Forms.Label;
$lblProfileDivider.BackColor = [System.Drawing.Color]::LightSteelBlue;
$lblProfileDivider.Size = New-Object System.Drawing.Size(610, 2);
$lblProfileDivider.Location = New-Object System.Drawing.Point(20, 100);
$pnlUserProfile.Controls.Add($lblProfileDivider);

# user info header 2
function Add-DataRow($panel, $hdrText, $xHdr, $xVal, $y, [switch]$isEditable) {
    $lblH = New-Object System.Windows.Forms.Label
    $lblH.Text = $hdrText
    $lblH.Location = New-Object System.Drawing.Point($xHdr, $y)
    $lblH.AutoSize = $true
    $lblH.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $panel.Controls.Add($lblH)

    $txtV = New-Object System.Windows.Forms.TextBox
    $txtV.Location = New-Object System.Drawing.Point($xVal, $y)
    $txtV.Size = New-Object System.Drawing.Size(220, 20)
    $txtV.ReadOnly = $true
    $txtV.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $txtV.BackColor = $panel.BackColor
    $txtV.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    
    if ($isEditable) {
        $txtV.Cursor = [System.Windows.Forms.Cursors]::Hand
        $txtV.ForeColor = [System.Drawing.Color]::RoyalBlue
        $editToolTip.SetToolTip($txtV, "Double-click to edit")
    } else {
        $txtV.ForeColor = [System.Drawing.Color]::DarkSlateGray
    }
    
    $panel.Controls.Add($txtV)
    return @{ Hdr = $lblH; Val = $txtV }
}

# user info grid
$script:rowDept = Add-DataRow $pnlUserProfile "Department:" 30 115 120 -isEditable
$script:rowUser = Add-DataRow $pnlUserProfile "Username:" 30 115 160 
$script:rowPhone = Add-DataRow $pnlUserProfile "Telephone:" 30 115 200 
$script:rowOU = Add-DataRow $pnlUserProfile "Container:" 30 115 240 
$script:rowOU.Val.Width = 500

$script:rowMgr = Add-DataRow $pnlUserProfile "Manager:" 350 420 120 -isEditable
$script:rowEmail = Add-DataRow $pnlUserProfile "Email:" 350 420 160 
$script:rowLoc = Add-DataRow $pnlUserProfile "Location:" 350 420 200 

# assigned devices
$gbDevices = New-Object System.Windows.Forms.GroupBox;
$gbDevices.Text = "Assigned Devices";
$gbDevices.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold);
$gbDevices.Location = New-Object System.Drawing.Point(20, 310);
$gbDevices.Size = New-Object System.Drawing.Size(300, 85);
$pnlUserProfile.Controls.Add($gbDevices);

$lbDevices = New-Object System.Windows.Forms.ListBox;
$lbDevices.Font = New-Object System.Drawing.Font("Segoe UI", 9);
$lbDevices.Location = New-Object System.Drawing.Point(10, 25);
$lbDevices.Size = New-Object System.Drawing.Size(280, 50);
$gbDevices.Controls.Add($lbDevices);

# sign-on info
$gbSignOn = New-Object System.Windows.Forms.GroupBox;
$gbSignOn.Text = "Sign-On Details";
$gbSignOn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold);
$gbSignOn.Location = New-Object System.Drawing.Point(20, 405);
$gbSignOn.Size = New-Object System.Drawing.Size(300, 130);
$pnlUserProfile.Controls.Add($gbSignOn);

$script:lblPassSet = New-Object System.Windows.Forms.Label; $script:lblPassSet.Location = New-Object System.Drawing.Point(10, 25); $script:lblPassSet.Size = New-Object System.Drawing.Size(280, 20); $script:lblPassSet.Font = New-Object System.Drawing.Font("Segoe UI", 9); $gbSignOn.Controls.Add($script:lblPassSet);
$script:lblPassExp = New-Object System.Windows.Forms.Label; $script:lblPassExp.Location = New-Object System.Drawing.Point(10, 50); $script:lblPassExp.Size = New-Object System.Drawing.Size(280, 20); $script:lblPassExp.Font = New-Object System.Drawing.Font("Segoe UI", 9); $gbSignOn.Controls.Add($script:lblPassExp);
$script:lblLastLogon = New-Object System.Windows.Forms.Label; $script:lblLastLogon.Location = New-Object System.Drawing.Point(10, 75); $script:lblLastLogon.Size = New-Object System.Drawing.Size(280, 20); $script:lblLastLogon.Font = New-Object System.Drawing.Font("Segoe UI", 9); $gbSignOn.Controls.Add($script:lblLastLogon);
$script:lblFailedLogon = New-Object System.Windows.Forms.Label; $script:lblFailedLogon.Location = New-Object System.Drawing.Point(10, 100); $script:lblFailedLogon.Size = New-Object System.Drawing.Size(280, 20); $script:lblFailedLogon.Font = New-Object System.Drawing.Font("Segoe UI", 9); $gbSignOn.Controls.Add($script:lblFailedLogon);

# action buttons
$gbActions = New-Object System.Windows.Forms.GroupBox;
$gbActions.Text = "Administrative Actions";
$gbActions.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold);
$gbActions.Location = New-Object System.Drawing.Point(20, 545); # Shifted down
$gbActions.Size = New-Object System.Drawing.Size(300, 110);
$pnlUserProfile.Controls.Add($gbActions);

$btnResetPass = New-Object System.Windows.Forms.Button;
$btnResetPass.Text = "Reset Password";
$btnResetPass.Font = New-Object System.Drawing.Font("Segoe UI", 9);
$btnResetPass.BackColor = [System.Drawing.Color]::LightGoldenrodYellow;
$btnResetPass.Location = New-Object System.Drawing.Point(15, 35);
$btnResetPass.Size = New-Object System.Drawing.Size(120, 30);
$gbActions.Controls.Add($btnResetPass);

$btnScanDevice = New-Object System.Windows.Forms.Button;
$btnScanDevice.Text = "Scan Device";
$btnScanDevice.Font = New-Object System.Drawing.Font("Segoe UI", 9);
$btnScanDevice.BackColor = [System.Drawing.Color]::LightCyan;
$btnScanDevice.Location = New-Object System.Drawing.Point(145, 35);
$btnScanDevice.Size = New-Object System.Drawing.Size(120, 30);
$gbActions.Controls.Add($btnScanDevice);

$lblActionStatus = New-Object System.Windows.Forms.Label;
$lblActionStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8);
$lblActionStatus.Location = New-Object System.Drawing.Point(15, 80);
$lblActionStatus.Size = New-Object System.Drawing.Size(270, 20);
$lblActionStatus.ForeColor = [System.Drawing.Color]::DarkGreen;
$gbActions.Controls.Add($lblActionStatus);

# security group membership box
$gbGroups = New-Object System.Windows.Forms.GroupBox;
$gbGroups.Text = "Group Memberships";
$gbGroups.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold);
$gbGroups.Location = New-Object System.Drawing.Point(340, 310);
$gbGroups.Size = New-Object System.Drawing.Size(290, 420);
$pnlUserProfile.Controls.Add($gbGroups);

$lbGroups = New-Object System.Windows.Forms.ListBox;
$lbGroups.Font = New-Object System.Drawing.Font("Segoe UI", 9);
$lbGroups.Location = New-Object System.Drawing.Point(10, 25);
$lbGroups.Size = New-Object System.Drawing.Size(270, 350);
$gbGroups.Controls.Add($lbGroups);

$btnCopyGroups = New-Object System.Windows.Forms.Button;
$btnCopyGroups.Text = "Copy List";
$btnCopyGroups.Font = New-Object System.Drawing.Font("Segoe UI", 8);
$btnCopyGroups.Location = New-Object System.Drawing.Point(100, 385);
$btnCopyGroups.Size = New-Object System.Drawing.Size(90, 25);
$gbGroups.Controls.Add($btnCopyGroups);

# ===================
# NEW HIRE ENTRY FORM
# ===================
$pnlNewHire = New-Object System.Windows.Forms.Panel;
$pnlNewHire.Size = $form.ClientSize;
$pnlNewHire.Visible = $false;

$lblNewHireTitle = New-Object System.Windows.Forms.Label;
$lblNewHireTitle.Text = "Enter Employee Information";
$lblNewHireTitle.Location = New-Object System.Drawing.Point(0, 50);
$lblNewHireTitle.Size = New-Object System.Drawing.Size(650, 30);
$lblNewHireTitle.AutoSize = $false;
$lblNewHireTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter;
$lblNewHireTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold);
$pnlNewHire.Controls.Add($lblNewHireTitle);

$y = 90;
function Add-FormField ($labelText, $control) {
    $lbl = New-Object System.Windows.Forms.Label;
    $lbl.Text = $labelText;
    $lbl.Location = New-Object System.Drawing.Point(120, ($script:y + 3));
    $lbl.AutoSize = $true;
    $pnlNewHire.Controls.Add($lbl);

    $control.Location = New-Object System.Drawing.Point(250, $script:y);
    $control.Size = New-Object System.Drawing.Size(250, 25);
    $pnlNewHire.Controls.Add($control);
    
    $script:y += 35;
}

$cmbLocation = New-Object System.Windows.Forms.ComboBox; $cmbLocation.DropDownStyle = 'DropDownList';
foreach ($key in ($Global:ConfigData.Keys)) { [void]($cmbLocation.Items.Add($key)); }
Add-FormField "Location:" $cmbLocation;

$cmbOffice = New-Object System.Windows.Forms.ComboBox; $cmbOffice.DropDownStyle = 'DropDownList';
Add-FormField "Office:" $cmbOffice;

$cmbDept = New-Object System.Windows.Forms.ComboBox; $cmbDept.DropDownStyle = 'DropDownList';
Add-FormField "Department:" $cmbDept;

$cmbLocation.Add_SelectedIndexChanged({
    $selectedLocation = $cmbLocation.SelectedItem;
    $locData = $Global:ConfigData[$selectedLocation];

    $cmbOffice.Items.Clear();
    foreach ($officeKey in ($locData.Offices.Keys)) { [void]($cmbOffice.Items.Add($officeKey)); }
    
    if ((($selectedLocation) -eq "BlueStar LA") -or (($selectedLocation) -eq "BlueStar MX")) {
        $cmbOffice.SelectedIndex = 0;
    } else { $cmbOffice.SelectedIndex = -1; }

    $cmbDept.Items.Clear();
    $deptArray = [System.Collections.ArrayList]($locData.Departments);
    $deptArray.Sort();
    foreach ($dept in ($deptArray)) { [void]($cmbDept.Items.Add($dept)); }
    $cmbDept.SelectedIndex = -1;
});

$txtFirst = New-Object System.Windows.Forms.TextBox; Add-FormField "First Name:" $txtFirst;
$txtLast = New-Object System.Windows.Forms.TextBox; Add-FormField "Last Name:" $txtLast;
$txtJobTitle = New-Object System.Windows.Forms.TextBox; Add-FormField "Job Title:" $txtJobTitle;
$cmbDesc = New-Object System.Windows.Forms.ComboBox; $cmbDesc.DropDownStyle = 'DropDownList';
$descOptions = @("Hybrid", "Office", "Remote");
foreach ($opt in ($descOptions)) { [void]($cmbDesc.Items.Add($opt)); }
Add-FormField "Office/Hybrid:" $cmbDesc;
$txtManager = New-Object System.Windows.Forms.TextBox; Add-FormField "Manager (Name):" $txtManager;

$script:y += 10;
$btnSubmit = New-Object System.Windows.Forms.Button;
$btnSubmit.Text = "Create AD User";
$btnSubmit.Size = New-Object System.Drawing.Size(150, 40);
$btnSubmit.Location = New-Object System.Drawing.Point(250, $y);
$pnlNewHire.Controls.Add($btnSubmit);

$script:y += 50;
$lblStatus = New-Object System.Windows.Forms.Label;
$lblStatus.Location = New-Object System.Drawing.Point(125, $y);
$lblStatus.Size = New-Object System.Drawing.Size(400, 60);
$lblStatus.ForeColor = [System.Drawing.Color]::Blue;
$pnlNewHire.Controls.Add($lblStatus);

$script:y += 65;
$lblMailboxPrompt = New-Object System.Windows.Forms.Label;
$lblMailboxPrompt.Text = "Proceed to Mailbox Provisioning?";
$lblMailboxPrompt.AutoSize = $true;
$lblMailboxPrompt.Location = New-Object System.Drawing.Point(230, $y);
$lblMailboxPrompt.Visible = $false;
$pnlNewHire.Controls.Add($lblMailboxPrompt);

$script:y += 25;
$btnMailboxYes = New-Object System.Windows.Forms.Button;
$btnMailboxYes.Text = "Yes";
$btnMailboxYes.Size = New-Object System.Drawing.Size(70, 30);
$btnMailboxYes.Location = New-Object System.Drawing.Point(240, $y);
$btnMailboxYes.Visible = $false;
$btnMailboxYes.Add_Click({
    try {
        $psArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script:mailboxScriptPath_Auto, "-AutoUser", $script:provisionedUser);
        Start-Process powershell.exe -ArgumentList $psArgs -Verb RunAs;
        $pnlNewHire.Visible = $false; $pnlMain.Visible = $true; $lblStatus.Text = ""; $lblMailboxPrompt.Visible = $false; $btnMailboxYes.Visible = $false; $btnMailboxNo.Visible = $false;
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to launch Mailbox Provisioning script.", "Error", 0, [System.Windows.Forms.MessageBoxIcon]::Error);
    }
});
$pnlNewHire.Controls.Add($btnMailboxYes);

$btnMailboxNo = New-Object System.Windows.Forms.Button;
$btnMailboxNo.Text = "No";
$btnMailboxNo.Size = New-Object System.Drawing.Size(70, 30);
$btnMailboxNo.Location = New-Object System.Drawing.Point(330, $y);
$btnMailboxNo.Visible = $false;
$btnMailboxNo.Add_Click({
    [System.Windows.Forms.MessageBox]::Show("Skipped Mailbox Provisioning for $script:provisionedUser.", "Notice", 0, [System.Windows.Forms.MessageBoxIcon]::Information);
    $pnlNewHire.Visible = $false; $pnlMain.Visible = $true; $lblStatus.Text = ""; $lblMailboxPrompt.Visible = $false; $btnMailboxYes.Visible = $false; $btnMailboxNo.Visible = $false;
});
$pnlNewHire.Controls.Add($btnMailboxNo);

$btnBackOnboard = New-Object System.Windows.Forms.Button;
$btnBackOnboard.Text = "< Back";
$btnBackOnboard.Size = New-Object System.Drawing.Size(75, 30);
$btnBackOnboard.Location = New-Object System.Drawing.Point(10, 10);
$btnBackOnboard.Add_Click({ 
    $pnlNewHire.Visible = $false; $pnlOnboard.Visible = $true; $lblStatus.Text = ""; $lblMailboxPrompt.Visible = $false; $btnMailboxYes.Visible = $false; $btnMailboxNo.Visible = $false;
});
$pnlNewHire.Controls.Add($btnBackOnboard);
$cmbLocation.SelectedItem = "BlueStar US";

# ====================
# LOGIC EVENT HANDLERS
# ====================

# user onboarding logic
$btnSubmit.Add_Click({
    $lblStatus.ForeColor = [System.Drawing.Color]::Black;
    $lblStatus.Text = "Processing...";
    $lblMailboxPrompt.Visible = $false; $btnMailboxYes.Visible = $false; $btnMailboxNo.Visible = $false;
    $form.Refresh();

    if ((-not ($cmbLocation.SelectedItem)) -or (-not ($cmbOffice.SelectedItem)) -or (-not ($cmbDept.SelectedItem)) -or (-not ($txtFirst.Text)) -or (-not ($txtLast.Text))) {
        $lblStatus.ForeColor = [System.Drawing.Color]::Red; $lblStatus.Text = "Error: Location, Office, Department, First, and Last Name are required."; return;
    }

    $first = $txtFirst.Text.Trim(); $last = $txtLast.Text.Trim();
    $locName = $cmbLocation.SelectedItem; $officeName = $cmbOffice.SelectedItem; $deptString = $cmbDept.SelectedItem;
    $locData = $Global:ConfigData[$locName]; $officeData = $locData.Offices[$officeName];
    
    if (($deptString) -eq "Users") {
        $targetPath = "CN=Users,$BaseDN"; $explorerPath = "$Domain\Users";
    } else {
        $targetPath = "OU=$deptString,OU=$($locData.ADName),$BaseDN"; $explorerPath = "$Domain\$locName\$deptString"; 
    }

    $sam = ("$($first.Substring(0,1))$last").Replace(" ", "").ToLower();
    if (Get-ADUser -Filter "sAMAccountName -eq '$sam'" -ErrorAction SilentlyContinue) { $sam = ("$first$last").Replace(" ", "").ToLower(); }
    
    $upn = "$sam@$Domain"; 
    $email = "$sam@$Domain"; 
    $display = "$first $last";
    
    $managerDN = $null;
    if ($txtManager.Text) {
        $mgr = Get-ADUser -Filter "Name -eq '$($txtManager.Text)'" -ErrorAction SilentlyContinue;
        if ($mgr) { $managerDN = $mgr.DistinguishedName; } else {
            [System.Windows.Forms.MessageBox]::Show("Manager '$($txtManager.Text)' not found in AD. Creating user without manager field.", "Warning", 0, [System.Windows.Forms.MessageBoxIcon]::Warning);
        }
    }

    try {
        $pass = ConvertTo-SecureString "Password1!" -AsPlainText -Force;
        $userParams = @{ Name=$display; SamAccountName=$sam; UserPrincipalName=$upn; GivenName=$first; Surname=$last; DisplayName=$display; Description=$cmbDesc.SelectedItem; Office=$officeName; OfficePhone=$officeData.Phone; EmailAddress=$email; HomePage="www.$Domain"; Title=$txtJobTitle.Text; Department=$deptString; Company=$officeData.Company; StreetAddress=$officeData.Street; City=$officeData.City; State=$officeData.State; PostalCode=$officeData.Zip; Country=$officeData.Country; AccountPassword=$pass; Enabled=$true; Path=$targetPath; };
        if ($managerDN) { $userParams.Add("Manager", $managerDN) };

        $newUser = New-ADUser @userParams -PassThru;
        foreach ($group in ($DefaultGroups)) { Add-ADGroupMember -Identity $group -Members $newUser -ErrorAction SilentlyContinue; }
        $script:provisionedUser = $sam;

        $lblStatus.ForeColor = [System.Drawing.Color]::Green; $lblStatus.Text = "User '" + $sam + "' created." + [Environment]::NewLine + "Please double-check the user properties in Active Directory:" + [Environment]::NewLine + $explorerPath;
        $lblMailboxPrompt.Visible = $true; $btnMailboxYes.Visible = $true; $btnMailboxNo.Visible = $true;
        $txtFirst.Clear(); $txtLast.Clear(); $txtJobTitle.Clear(); $txtManager.Clear(); $cmbOffice.SelectedIndex = -1; $cmbDept.SelectedIndex = -1; $cmbDesc.SelectedIndex = -1; $cmbLocation.SelectedItem = "BlueStar US";
    } catch {
        $lblStatus.ForeColor = [System.Drawing.Color]::Red; $lblStatus.Text = "Error: $($_.Exception.Message)";
    }
});

# user offboarding logic
$btnSearchOffboard.Add_Click({$lblOffboardStatus.Text = "Searching Active Directory..."; $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Black; $form.Refresh();

    $searchTerm =$txtSearch.Text.Trim();
    if (-not ($searchTerm)) {$lblOffboardStatus.Text = "Please enter a name or username."; $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Red; return; }

    $targetUser =$null;
    try { $targetUser = Get-ADUser -Filter "SamAccountName -eq '$searchTerm' -or Name -eq '$searchTerm' -or DisplayName -eq '$searchTerm'" -Properties DisplayName -ErrorAction Stop; } catch { $lblOffboardStatus.Text = "Error communicating with Active Directory."; $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Red; return; }

    if (($null) -eq ($targetUser)) { $lblOffboardStatus.Text = "User '" + $searchTerm + "' not found in Active Directory."; $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Red; return; } elseif (($targetUser.Count) -gt 1) {$lblOffboardStatus.Text = "Multiple users found. Please search again using the exact username (SamAccountName)."; $lblOffboardStatus.ForeColor = [System.Drawing.Color]::Red; return; }

    $msgResult = [System.Windows.Forms.MessageBox]::Show("Are you sure you would like to proceed with offboarding $($targetUser.Name)?", "Confirm Offboarding", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning);
    if (($msgResult) -eq 'No') { $pnlOffboardEmp.Visible =$false; $pnlMain.Visible =$true; $txtSearch.Clear();$lblOffboardStatus.Text = ""; return; }

    $lblOffboardStatus.Text = "Offboarding " + $targetUser.Name + "..."; $form.Refresh();

    # password change to Terminated1!
    try { $pass = ConvertTo-SecureString "Terminated1!" -AsPlainText -Force; Set-ADAccountPassword -Identity $targetUser.DistinguishedName -NewPassword $pass -Reset -ErrorAction Stop; } catch { Write-Warning "Password reset failed: $($_.Exception.Message)" }
    
    # disables user account
    try { Disable-ADAccount -Identity $targetUser.DistinguishedName -ErrorAction Stop; } catch { Write-Warning "Disable Account failed: $($_.Exception.Message)" }
    
    # user cannot change password
    try { Set-ADUser -Identity $targetUser.DistinguishedName -CannotChangePassword $true -ErrorAction Stop; } catch { try {$null = & dsacls.exe "$($targetUser.DistinguishedName)" /d "SELF:CA;Change Password"; } catch { Write-Warning "Cannot change password skipped." } }

    # remove local security groups
    $failedGroups = @();
    try {
        $userObj = Get-ADUser -Identity $targetUser.DistinguishedName -Properties MemberOf -ErrorAction Stop;
        if ($userObj.MemberOf) {
            foreach ($groupDN in ($userObj.MemberOf)) {
                $groupName =$groupDN;
                
                if ($groupDN.StartsWith("CN=")) {
                    $commaPos =$groupDN.IndexOf(",");
                    if (($commaPos) -gt 3) {$groupName = $groupDN.Substring(3, ($commaPos - 3)); }
                }

                if ($groupName -eq "Domain Users") { continue }

                try { 
                    Remove-ADGroupMember -Identity $groupDN -Members $targetUser.DistinguishedName -Confirm:$false -ErrorAction Stop; 
                } catch { 
                    $failedGroups +=$groupName; 
                }
            }
        }
    } catch { 
        $failedGroups += "CRITICAL ERROR: Failed to read AD Groups - $($_.Exception.Message)" 
    }

    # clears department & IP phone tab
    try {
        Set-ADUser -Identity $targetUser.DistinguishedName -Clear Department, ipPhone -ErrorAction Stop;
    } catch { Write-Warning "Clear Dept/Phone failed: $($_.Exception.Message)" }

    # output
    $lblOffboardStatus.Clear()
    Append-ColoredText $lblOffboardStatus "Complete! " [System.Drawing.Color]::LimeGreen
    Append-ColoredText $lblOffboardStatus "$($targetUser.Name) has been offboarded in Active Directory.`n`n" [System.Drawing.Color]::Black
    
    Append-ColoredText $lblOffboardStatus "- Account is disabled`n`n" [System.Drawing.Color]::Black

    Append-ColoredText $lblOffboardStatus "- Password changed to: " [System.Drawing.Color]::Black
    Append-ColoredText $lblOffboardStatus "Terminated1! " [System.Drawing.Color]::Red
    Append-ColoredText $lblOffboardStatus "(" [System.Drawing.Color]::Black
    Append-ColoredText $lblOffboardStatus "Account" [System.Drawing.Color]::DodgerBlue
    Append-ColoredText $lblOffboardStatus ")`n`n" [System.Drawing.Color]::Black

    Append-ColoredText $lblOffboardStatus "- User cannot change password (" [System.Drawing.Color]::Black
    Append-ColoredText $lblOffboardStatus "Account" [System.Drawing.Color]::DodgerBlue
    Append-ColoredText $lblOffboardStatus ")`n`n" [System.Drawing.Color]::Black

    Append-ColoredText $lblOffboardStatus "- Removed Department Field (" [System.Drawing.Color]::Black
    Append-ColoredText $lblOffboardStatus "Organization" [System.Drawing.Color]::DodgerBlue
    Append-ColoredText $lblOffboardStatus ")`n`n" [System.Drawing.Color]::Black

    Append-ColoredText $lblOffboardStatus "- Phone Extension Removed (" [System.Drawing.Color]::Black
    Append-ColoredText $lblOffboardStatus "Telephones" [System.Drawing.Color]::DodgerBlue
    Append-ColoredText $lblOffboardStatus ")`n`n" [System.Drawing.Color]::Black

    Append-ColoredText $lblOffboardStatus "- Local Security Groups Removed (" [System.Drawing.Color]::Black
    Append-ColoredText $lblOffboardStatus "Member Of" [System.Drawing.Color]::DodgerBlue
    Append-ColoredText $lblOffboardStatus ")" [System.Drawing.Color]::Black

    # show warning when security/email groups fail to delete locally
    if (($failedGroups.Count) -gt 0) { 
        $failedString =$failedGroups -join ("`n- ")
        Append-ColoredText $lblOffboardStatus "`n`nNote: The following groups could not be removed on-premise. Remove through M365 Admin Center:`n- $failedString" [System.Drawing.Color]::DarkOrange
    }

    $txtSearch.Clear()
});

# 90 day deleton logic
$btnSearch90Day.Add_Click({
    $lbl90DayStatus.Text = "Searching Active Directory..."; $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Black; $form.Refresh();

    $searchTerm = $txtSearch90.Text.Trim();
    if (-not ($searchTerm)) { $lbl90DayStatus.Text = "Please enter a name or username."; $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red; return; }

    $targetUser = $null;
    try { $targetUser = Get-ADUser -Filter "SamAccountName -eq '$searchTerm' -or Name -eq '$searchTerm' -or DisplayName -eq '$searchTerm'" -ErrorAction Stop; } catch { $lbl90DayStatus.Text = "Error communicating with Active Directory."; $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red; return; }

    if (($null) -eq ($targetUser)) { $lbl90DayStatus.Text = "User '" + $searchTerm + "' not found in Active Directory."; $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red; return; } elseif (($targetUser.Count) -gt 1) { $lbl90DayStatus.Text = "Multiple users found. Please search again using the exact username (SamAccountName)."; $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red; return; }

    $nameInput = Show-NameValidationPrompt -ExpectedName $targetUser.Name;
    if (-not ($nameInput)) { $lbl90DayStatus.Text = "Deletion cancelled by technician."; $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red; return; }

    if (($nameInput) -ne ($targetUser.Name)) { [System.Windows.Forms.MessageBox]::Show("The name entered did not match '$($targetUser.Name)'. Deletion aborted.", "Validation Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error); $lbl90DayStatus.Text = "Validation failed. Deletion aborted."; $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red; return; }

    $msgResult = [System.Windows.Forms.MessageBox]::Show("WARNING: This will permanently delete the account from Active Directory. Are you sure you want to do this?", "Confirm Deletion", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning);
    if (($msgResult) -eq 'No') { $pnl90Day.Visible = $false; $pnlMain.Visible = $true; $txtSearch90.Clear(); $lbl90DayStatus.Text = ""; return; }

    try {
        $lbl90DayStatus.Text = "Deleting $($targetUser.Name)..."; $form.Refresh();
        Set-ADObject -Identity $targetUser.DistinguishedName -ProtectedFromAccidentalDeletion $false -ErrorAction SilentlyContinue;
        Remove-ADObject -Identity $targetUser.DistinguishedName -Recursive -Confirm:$false -ErrorAction Stop;
        $lbl90DayStatus.Text = "Complete! " + $targetUser.Name + " has been permanently deleted from Active Directory."; $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Green; $txtSearch90.Clear();
    } catch {
        $lbl90DayStatus.Text = "Error during deletion: $($_.Exception.Message)"; $lbl90DayStatus.ForeColor = [System.Drawing.Color]::Red;
    }
});

# user mgmt logic
$btnSearchUserExec.Add_Click({
    $lblSearchUserStatus.Text = "Searching Active Directory...";
    $lblSearchUserStatus.ForeColor = [System.Drawing.Color]::Black;
    $form.Refresh();

    $searchTerm = $txtSearchUser.Text.Trim();
    if (-not $searchTerm) {
        $lblSearchUserStatus.Text = "Please enter a search term.";
        $lblSearchUserStatus.ForeColor = [System.Drawing.Color]::Red;
        return;
    }

    try {
       $targetUser = Get-ADUser -Filter "Name -eq '$searchTerm'" -Properties EmailAddress, Title, Department, Manager, Office, MemberOf, Description, GivenName, Surname, OfficePhone, PasswordLastSet, LastLogonDate, LastBadPasswordAttempt -ErrorAction Stop;
        
        if ($null -eq $targetUser) {
            $lblSearchUserStatus.Text = "User '$searchTerm' not found.";
            $lblSearchUserStatus.ForeColor = [System.Drawing.Color]::Red;
            return;
        } elseif ($targetUser.Count -gt 1) {
            $lblSearchUserStatus.Text = "Multiple users found. Please use exact Name.";
            $lblSearchUserStatus.ForeColor = [System.Drawing.Color]::Red;
            return;
        }

        $script:targetUserDN = $targetUser.DistinguishedName;
        $script:targetUserSam = $targetUser.SamAccountName;

        # parse mgr
        $mgrName = "None";
        if ($targetUser.Manager) {
            $mgrSplit = ($targetUser.Manager -split ',')[0]
            $mgrName = $mgrSplit -replace 'CN=', ''
        }

        # parse container path
        $ouArray = [System.Collections.ArrayList]($targetUser.DistinguishedName -split ',' | Where-Object { $_ -match '^OU=' } | ForEach-Object { $_ -replace '^OU=', '' })
        $ouArray.Reverse()
        $ouString = $ouArray -join '\'

        # grid properties
        $script:lblProfileName.Text = $targetUser.Name;
        $displayTitle = if ($targetUser.Title) { $targetUser.Title } else { "No Title Defined" }
        $script:lblProfileTitle.Text = $displayTitle;

        $script:rowDept.Val.Text = if ($targetUser.Department) { $targetUser.Department } else { "N/A" }
        $script:rowMgr.Val.Text = if ($mgrName -ne "None") { $mgrName } else { "N/A" }
        $script:rowUser.Val.Text = $targetUser.SamAccountName;
        $script:rowEmail.Val.Text = if ($targetUser.EmailAddress) { $targetUser.EmailAddress } else { "N/A" }
        $script:rowPhone.Val.Text = if ($targetUser.OfficePhone) { $targetUser.OfficePhone } else { "N/A" }
        $script:rowLoc.Val.Text = if ($targetUser.Office) { $targetUser.Office } else { "N/A" }
        $script:rowOU.Val.Text = if ($ouString) { "$Domain\$ouString" } else { "$Domain\Users" }
		
		# sign-on details & expiry coloring
        if ($targetUser.PasswordLastSet) {
            $script:lblPassSet.Text = "Password Last Set: $($targetUser.PasswordLastSet.ToString('MM/dd/yyyy hh:mm tt'))"
            $expDate = $targetUser.PasswordLastSet.AddDays(90)
            $daysLeft = ($expDate - (Get-Date)).Days
            
            $script:lblPassExp.Text = "Expires: $($expDate.ToString('MM/dd/yyyy')) ($daysLeft days left)"
            if ($daysLeft -gt 45) { $script:lblPassExp.ForeColor = [System.Drawing.Color]::DarkGreen }
            elseif ($daysLeft -gt 15) { $script:lblPassExp.ForeColor = [System.Drawing.Color]::Goldenrod }
            else { $script:lblPassExp.ForeColor = [System.Drawing.Color]::Red }
        } else {
            $script:lblPassSet.Text = "Password Last Set: N/A"
            $script:lblPassExp.Text = "Expires: N/A"; $script:lblPassExp.ForeColor = [System.Drawing.Color]::Black
        }

        if ($targetUser.LastLogonDate) { $script:lblLastLogon.Text = "Last Logon: $($targetUser.LastLogonDate.ToString('MM/dd/yyyy hh:mm tt'))" } 
        else { $script:lblLastLogon.Text = "Last Logon: N/A" }

        if ($targetUser.LastBadPasswordAttempt) { $script:lblFailedLogon.Text = "Last Failed Logon: $($targetUser.LastBadPasswordAttempt.ToString('MM/dd/yyyy hh:mm tt'))" } 
        else { $script:lblFailedLogon.Text = "Last Failed Logon: N/A" }
        
        # populate groups
        $lbGroups.Items.Clear();
        if ($targetUser.MemberOf) {
            $sortedGroups = [System.Collections.ArrayList]@();
            foreach ($groupDN in $targetUser.MemberOf) {
                $gName = ($groupDN -split ',')[0] -replace 'CN=', ''
                [void]$sortedGroups.Add($gName)
            }
            $sortedGroups.Sort();
            foreach ($sg in $sortedGroups) { [void]$lbGroups.Items.Add($sg) }
        } else {
            [void]$lbGroups.Items.Add("No Groups Found")
        }

        # filter for devices based on the users name
      $lbDevices.Items.Clear();
        try {
            $searchString = $targetUser.Name
            
            $psFilter = "Description -like '*$searchString*' -and (Name -like 'BSUS*' -or Name -like 'BSLA*' -or Name -like 'BSCA*' -or Name -like 'BSMX*')"

            $userDevices = Get-ADComputer -Filter $psFilter -Server $Domain -Properties Description -ErrorAction Stop;
            
            if (@($userDevices).Count -gt 0) {
                foreach ($dev in $userDevices) {
                    [void]$lbDevices.Items.Add($dev.Name)
                }
				
            } else {
                [void]$lbDevices.Items.Add("No assigned devices found.")
            }
        } catch {
            [void]$lbDevices.Items.Add("Error loading devices.")
        }

        # clears status
        $lblSearchUserStatus.Text = "";
        $pnlUserMgmtSearch.Visible = $false;
        $pnlUserProfile.Visible = $true;

    } catch {
        $lblSearchUserStatus.Text = "Error processing user: $($_.Exception.Message)";
        $lblSearchUserStatus.ForeColor = [System.Drawing.Color]::Red;
    }
});

$btnCopyGroups.Add_Click({
    if ($lbGroups.Items.Count -gt 0) {
        $grpText = $lbGroups.Items -join "`r`n"
        [System.Windows.Forms.Clipboard]::SetText($grpText)
        $lblActionStatus.ForeColor = [System.Drawing.Color]::Blue
        $lblActionStatus.Text = "Group memberships copied to clipboard."
    }
})

# editing & actions 
$script:lblProfileName.Add_DoubleClick({
    if (-not $script:targetUserDN) { return }
    
    $defVal = $script:lblProfileName.Text
    $newVal = Show-InputPrompt -Title "Edit Name" -Message "Enter new Full Name:" -DefaultValue $defVal -IsPassword:$false
    
    if ($newVal -ne $null -and $newVal.Trim() -ne "") {
        try {
            $parts = $newVal.Trim() -split ' '
            $first = $parts[0]
            $last = if ($parts.Count -gt 1) { $parts[-1] } else { "" }
            
            Set-ADUser -Identity $script:targetUserDN -DisplayName $newVal -GivenName $first -Surname $last -ErrorAction Stop
            Rename-ADObject -Identity $script:targetUserDN -NewName $newVal -ErrorAction Stop
            
            $script:targetUserDN = (Get-ADUser -Identity $script:targetUserSam).DistinguishedName
            $script:lblProfileName.Text = $newVal
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to rename object: $($_.Exception.Message)", "Error", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$script:lblProfileTitle.Add_DoubleClick({
    if (-not $script:targetUserDN) { return }
    
    $defVal = if ($script:lblProfileTitle.Text -eq "No Title Defined") { "" } else { $script:lblProfileTitle.Text }
    $newVal = Show-InputPrompt -Title "Edit Title" -Message "Enter new Job Title:" -DefaultValue $defVal -IsPassword:$false
    
    if ($newVal -ne $null) {
        try {
            if ([string]::IsNullOrWhiteSpace($newVal)) {
                Set-ADUser -Identity $script:targetUserDN -Clear Title -ErrorAction Stop
            } else {
                Set-ADUser -Identity $script:targetUserDN -Title $newVal -ErrorAction Stop
            }
            $displayTitle = if([string]::IsNullOrWhiteSpace($newVal)){"No Title Defined"}else{$newVal}
            $script:lblProfileTitle.Text = $displayTitle
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)", "Error", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$script:rowDept.Val.Add_DoubleClick({
    if (-not $script:targetUserDN) { return }
    
    $defVal = if ($script:rowDept.Val.Text -eq "N/A") { "" } else { $script:rowDept.Val.Text }
    $newVal = Show-InputPrompt -Title "Edit Department" -Message "Enter new Department:" -DefaultValue $defVal -IsPassword:$false
    
    if ($newVal -ne $null) {
        try {
            if ([string]::IsNullOrWhiteSpace($newVal)) {
                Set-ADUser -Identity $script:targetUserDN -Clear Department -ErrorAction Stop
                $script:rowDept.Val.Text = "N/A"
            } else {
                Set-ADUser -Identity $script:targetUserDN -Department $newVal -ErrorAction Stop
                $script:rowDept.Val.Text = $newVal
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)", "Error", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$script:rowMgr.Val.Add_DoubleClick({
    if (-not $script:targetUserDN) { return }
    
    $defVal = if ($script:rowMgr.Val.Text -eq "N/A") { "" } else { $script:rowMgr.Val.Text }
    $newVal = Show-InputPrompt -Title "Edit Manager" -Message "Enter Manager's Exact Name:`n(Leave blank to clear manager)" -DefaultValue $defVal -IsPassword:$false
    
    if ($newVal -ne $null) {
        try {
            if ([string]::IsNullOrWhiteSpace($newVal)) {
                Set-ADUser -Identity $script:targetUserDN -Clear Manager -ErrorAction Stop; $script:rowMgr.Val.Text = "N/A"
            } else {
                $mgrObj = Get-ADUser -Filter "Name -eq '$newVal'" -ErrorAction Stop
                if ($mgrObj) {
                    if ($mgrObj.Count -gt 1) { $mgrObj =$mgrObj[0] }
                    Set-ADUser -Identity $script:targetUserDN -Manager $mgrObj.DistinguishedName -ErrorAction Stop
                    $script:rowMgr.Val.Text =$mgrObj.Name
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Manager '$newVal' not found in AD.", "Not Found", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
                }
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)", "Error", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$btnResetPass.Add_Click({$lblActionStatus.Text = "";
    $resetData = Show-PasswordResetPrompt -TargetUser$script:targetUserSam;
    
    if ($resetData -ne $null -and -not [string]::IsNullOrWhiteSpace($resetData.Password)) {
        try {
            $secPass = ConvertTo-SecureString$resetData.Password -AsPlainText -Force;
            Set-ADAccountPassword -Identity $script:targetUserDN -NewPassword $secPass -Reset -ErrorAction Stop;
            Set-ADUser -Identity $script:targetUserDN -ChangePasswordAtLogon $resetData.RequireChange -ErrorAction Stop;
            
            $lblActionStatus.ForeColor = [System.Drawing.Color]::DarkGreen;
            $lblActionStatus.Text = "[$(Get-Date -Format 'HH:mm:ss')] Password reset successfully.";
        } catch {
            $lblActionStatus.ForeColor = [System.Drawing.Color]::Red;
            $lblActionStatus.Text = "Error resetting password: $($_.Exception.Message)";
        }
    } else {
        $lblActionStatus.ForeColor = [System.Drawing.Color]::DarkOrange;
        $lblActionStatus.Text = "Password reset cancelled.";
    }
});

$btnScanDevice.Add_Click({
    $lblActionStatus.Text = "";
    
    # checks if device list is empty or contains error
    if ($lbDevices.Items.Count -eq 0 -or $lbDevices.Items[0] -match "No assigned devices|Error") {
        [System.Windows.Forms.MessageBox]::Show("There are no valid devices assigned to this user to scan.", "Warning", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    # insert the item the user clicked on
    $devName = $lbDevices.SelectedItem

    # if user hasn't clicked device
    if ($null -eq $devName) {
        # if only 1 device, auto-select
        if ($lbDevices.Items.Count -eq 1) {
            $devName = $lbDevices.Items[0]
        } else {
            # if multiple devices, user must choose
            [System.Windows.Forms.MessageBox]::Show("This user has multiple devices. Please click on a specific device in the 'Assigned Devices' list to scan.", "Select Device", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }
    }

    # exec scan on chosen device
    if (Test-Path $script:deviceInfoScriptPath) {
        try {
            $psArgs = @("-NoExit", "-Command", "Write-Output '$devName' | & '$($script:deviceInfoScriptPath)'")
            Start-Process powershell.exe -ArgumentList $psArgs
        } catch {
            $lblActionStatus.ForeColor = [System.Drawing.Color]::Red;
            $lblActionStatus.Text = "Failed to launch script process.";
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Device Info Lookup script not found at $($script:deviceInfoScriptPath)", "Error", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})
# add panels and launch
$form.Controls.Add($pnlMain);
$form.Controls.Add($pnlOnboard);
$form.Controls.Add($pnlNewHire);
$form.Controls.Add($pnlOffboard);
$form.Controls.Add($pnlOffboardEmp);
$form.Controls.Add($pnl90Day);
$form.Controls.Add($pnlUserMgmtSearch);
$form.Controls.Add($pnlUserProfile);

[void]($form.ShowDialog());
