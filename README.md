<h1><center>🛠️ BSTools 🛠️</center></h1>

<br>

<center><b>BlueStarTools</b> is a collection of homemade PowerShell utilities developed for IT purposes at BlueStar. </center>

<br>
<br>

---

<h1> Toolbelt: </h1>
<h2> - BlueStarIT Lookup Tool - </h2>

> **File:** `DeviceInfoLookup.ps1`

*A thorough PowerShell utility designed for Service Desk technicians and SysAdmins.*

*Streamlines troubleshooting by aggregating critical Active Directory, hardware, and remote network data into a single, highly readable console dashboard.*

<img width="1418" height="1374" alt="image" src="https://github.com/user-attachments/assets/23d17814-03c8-4222-a4b0-0682a16d58ef" />

<h2>List of Features:</h2>

<h3>Active Target Resolution</h3>

- <b>Search Flexibility</b>  |  <i>(Search by username, hostname, full name, or first name!)</i>
- <b>Auto-Discovery</b>  |  <i>(Auto-queries AD to find all devices assigned to a specific name)</i>
- <b>Multiple-Device Detection</b>  |  <i>(When multiple devices are found, user is prompted with a multiple-choice menu.)</i>

<br>

<h3>Account & Identity Details</h3>

- <b>Live AD Data</b> | <i>(Extracts real-time AD account info for currently logged-on user)</i>
- <b>User Info</b> | <i>(Displays Full Name, Username, Email, Office, Department, Position, and Direct Manager)</i>
- <b>Password Lifecycle</b> | <i>(Calculates and displays when the password was last set and when it expires)</i>
- <b>Smart Formatting</b> | <i>(Color-codes password expiration dates: Red for <30 days, Yellow for <60 days)</i>

<br>

<h3>Hardware & System Health</h3>

- <b>Intelligent Device Age Calc</b> | <i>(Dynamically calculates the approx. age of a machine using fallback methods like HP serials, or CPU/BIOS parsing)</i>
- <b>Uptime Tracking</b> | <i>(Displays system uptime, colored yellow for >3 days. Red for >5 days to spot reboot issues)</i>
- <b>Simplified Specs</b> | <i>(Cleans up verbose WMI strings for OS version and CPU models to keep dashboard clean)</i>

<br>

<h3>Network & Connectivity</h3>

- <b>Adapter Parsing</b> | <i>(Scans active IP adapters to display Network Name, IPv4, MAC address, and Connection Type)</i>
- <b>VPN Detection</b> | <i>(Identifies if the user is connected via a virtual private network)</i>
- <b>Link Speed Monitoring</b> | <i>(Color-codes sub-100Mbps connections to quickly identify faulty cables or poor Wi-Fi signals)</i>

<br>

<h3>Storage & Data Diagnostics</h3>

- <b>Storage Dashboard</b> | <i>(Displays a visual progress bar for C:\ drive capacity and free space)</i>
- <b>Outlook File Scanner</b> | <i>(Scans standard directories for .ost and .pst files, generating a visual progress bar relative to a 50GB mailbox limit)</i>
- <b>Optional Folder Size Scanner</b> | <i>(Allows technicians to manually trigger a size scan for specific user directories)</i>
<br>

---

<br>


<h2> - BlueStar Quick On/Off - </h2>

> **File:** `QuickLocalOnboard.ps1`

*A lightweight, Windows Forms-based PowerShell utility built to streamline and standardize Active Directory user lifecycle management.* 

*Eliminates manual AD configuration steps, ensuring all new hires and terminations are processed consistently, securely, and rapidly.*

<img width="329" height="483" alt="1" src="https://github.com/user-attachments/assets/a56c236b-9ee2-4417-b58b-3e8508be6a7e" /> <img width="335" height="489" alt="2" src="https://github.com/user-attachments/assets/c002628c-cec2-4251-96fc-3ac50c8e3fb1" />




--- 

<br>

<h2>List of Features:</h2>

<h3>Automated Employee Onboarding</h3>

- <b>Dynamic Form Logic</b> | <i>(Selecting a primary region (US, CA, LA, MX) automatically populates the correct information for that specific location)</i>
- <b>Smart Account Gen</b> | <i>(Automatically creates `sAMAccountName` & `UserPrincipalName` using standard corporate naming conventions)</i>
- <b>Precision OU Routing</b> | <i>(Ensures new user object is placed in the correct Organizational Unit based on region and dept.)</i>
- <b>Standardized Group Assignment</b> | <i>(Adds every new hire to standard baseline security and distribution groups)</i>
- <b>Seamless Mailbox Provisioning</b> | <i>(Auto-triggers mailbox provisioning tool directly from the UI)</i>

<br>

<h3>1-Click Offboarding</h3>

- <b>Intelligent AD Search</b> | <i>(Locate departing users instantly via username, full name, or display name)</i>
- <b>Automatic Offboard Sequence</b> | <i>(Automates the standard offboarding tasks in one click.)</i>

<br>

<h3>90-Day Permanent Deletion (Clean-up)</h3>

- <b>Safety Check</b> | <i>(Enforces a strict manual validation prompt requiring the technician to "type the exact expected name" before allowing any destructive actions, preventing accidental deletions of similarly named accounts)</i>
