#Requires -Modules ActiveDirectory

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# config
$Global:DomainController = "bsi-ad2.bluestarinc.com"
# globally ignored outliers
$Global:Outliers = @("BSUS7643", "BSUS9999","BSUS9998","BSUS-9990")

function Get-NextDeviceName {
    param([string]$Prefix)

    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

        # reads computers matching the prefix from the specific domain controller
        $computers = Get-ADComputer -Filter "Name -like '$Prefix*'" -Server $Global:DomainController -ErrorAction Stop | Select-Object -ExpandProperty Name
        
        $maxNum = 0
        $existingNumbers = @()

        foreach ($comp in $computers) {
            # match the prefix followed by 4 numbers (e.g., BSUS7475)
            if ($comp -match "^$Prefix(\d{4})$") {
                $num = [int]$matches[1]
                $existingNumbers += $num
                
                # ignore known pc's with larger numbers so they don't artificially inflate the number
                if ($comp -notin $Global:Outliers) {
                    if ($num -gt $maxNum) {
                        $maxNum = $num
                    }
                }
            }
        }

        if ($maxNum -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No existing computers found for $Prefix. Please check AD connection.", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        # calc next number
        $nextNum = $maxNum + 1

        # check against ALL existing numbers (including outliers) to prevent duplicates
        while ($existingNumbers -contains $nextNum) {
            $nextNum++
        }

        $nextName = "$Prefix$nextNum"

        # pop-up alert with the device name
        [System.Windows.Forms.MessageBox]::Show("The next available device name is:`n`n$nextName", "$Prefix Generated", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::None)

    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to query Active Directory. Error: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

# --- GUI ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "BlueStar Device Namer"
$form.Size = New-Object System.Drawing.Size(280, 240)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$label = New-Object System.Windows.Forms.Label
$label.Text = "Select a location:"
$label.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$label.Location = New-Object System.Drawing.Point(75, 20)
$label.AutoSize = $true
$form.Controls.Add($label)

# BSUS btn
$btnBSUS = New-Object System.Windows.Forms.Button
$btnBSUS.Text = "BSUS"
$btnBSUS.Location = New-Object System.Drawing.Point(30, 60)
$btnBSUS.Size = New-Object System.Drawing.Size(90, 40)
$btnBSUS.Add_Click({ Get-NextDeviceName -Prefix "BSUS" })
$form.Controls.Add($btnBSUS)

# BSCA btn
$btnBSCA = New-Object System.Windows.Forms.Button
$btnBSCA.Text = "BSCA"
$btnBSCA.Location = New-Object System.Drawing.Point(140, 60)
$btnBSCA.Size = New-Object System.Drawing.Size(90, 40)
$btnBSCA.Add_Click({ Get-NextDeviceName -Prefix "BSCA" })
$form.Controls.Add($btnBSCA)

# BSMX btn
$btnBSMX = New-Object System.Windows.Forms.Button
$btnBSMX.Text = "BSMX"
$btnBSMX.Location = New-Object System.Drawing.Point(30, 120)
$btnBSMX.Size = New-Object System.Drawing.Size(90, 40)
$btnBSMX.Add_Click({ Get-NextDeviceName -Prefix "BSMX" })
$form.Controls.Add($btnBSMX)

# BSLA btn
$btnBSLA = New-Object System.Windows.Forms.Button
$btnBSLA.Text = "BSLA"
$btnBSLA.Location = New-Object System.Drawing.Point(140, 120)
$btnBSLA.Size = New-Object System.Drawing.Size(90, 40)
$btnBSLA.Add_Click({ Get-NextDeviceName -Prefix "BSLA" })
$form.Controls.Add($btnBSLA)

# launch GUI
$form.ShowDialog() | Out-Null
