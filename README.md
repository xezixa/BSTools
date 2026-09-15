 # BSTools

BlueStarTools: A collection of homemade PowerShell utilities developed for IT purposes at BlueStar.


Current Tools:


BlueStarIT Lookup Tool (DeviceInfoLookup.ps1)

 A thorough PowerShell utility designed for ServiceDesk technicians and SysAdmins.

 Streamlines troubleshooting by aggregating critical Active Directory, hardware,

  and remote network data into a single, highly readable console dashboard.


  Features:

  

  **Active Target Resolution**

  - Flexible Input: Accept an AD username, first name, or exact hostname.

  - Auto-Discovery: Automatically queries AD to find all devices assigned to a specific user

  - Active Connection Verification: Pings discovered devices and prompts the user with a select-able menu if multiple active devices are found.


  **Account & Identity Details**

  - Extracts real-time AD account info for the currently logged-on user.

  - Displays Full Name, Username, Email, Office, Department, Position, and Direct Manager.

  - Password Lifecycle: Calculates and displays when the password was last set and when it expires.

  - Smart Formatting: Color-codes password expiration dates (Red for <30 days, Yellow for <60 days).


  **Hardware & System Health**

  - Intelligent Device Age Calc: Dynamically calculates the physical age of the machine using multiple fallback methods:

    - HP: Parses the serial number string for year/week manufacturing codes.

    - Lenovo: Attempts to check SMBIOS and Battery Manufacture Date via WMI.

    - Universal: Falls back to CPU Generation parsing or BIOS release date.

  - Uptime Tracking: Displays system uptime, highlighting in yellow (>3 days) or red (>5 days) to easily spot reboot issues.

  - Simplified Specs: Cleans up verbose WMI strings for OS version and CPU models to keep the dashboard clean.


  **Network & Connectivity**

  - Parses active IP adapters to display Network Name, IPv4, MAC addr., and Connection Type

  - VPN Detection

  - Link Speed Monitoring: color-coding sub-100Mbps connections to quickly identify faulty cables or poor Wi-Fi signals.


  **Storage & Data Diagnostics**

  - Storage Dashboard: Displays progress bar for C:\ drive capacity and free space.

  - Outlook File Scanner: Scans the active user's standard AppData and Documents directories to locate .ost and .pst files

    - Generates visual progress bar relative to a 50GB mailbox limit to spot full Outlook files.

  - Optional Folder Size Scanner

    


BlueStar Quick On/Off (QuickLocalOnboard.ps1)

 A lightweight, Windows Forms-based PowerShell utility built to streamline and standardize

  Active Directory user lifecycle management. It eliminates manual AD configuration steps, ensuring

   all new hires and terminations are processed consistently, securely, and rapidly.


  Features:


**Automated Employee Onboarding**

- Dynamic Form Logic: Cascading drop-downs where selecting a primary region (US, CA, LA, MX) automatically populates the correct corporate Offices and Departments for that specific location.

- Smart Account Gen: Automatically generates the sAMAccountName and UserPrincipalName using standard corporate naming conventions

- Precision OU Routing: Builds DN path to ensure the user object is placed in the exact correct Organizational unit based on region and dept.

- Standardized Group Assignment: Automatically adds every new hire to standard baseline security and distribution groups.

- Seamless Mailbox Provision Handoff


**One-Click Initial Offboarding**

- AD Search: Allows techs to locate departing users instantly via exact username, full name, or display name.

- Complete Termination Sequence: Automates the standard offboarding checklist in one click:

  - 1. Resets password to standardized term string

  - 2. Disables the Active Directory account

  - 3. Modifies ACLs to check the "User cannot change password" box

  - 4. Strips the user from all Security and Distribution groups

  - 5. Wipes the Department (Organization) and Extension (Telephones) attributes to clear them from the Global Address List.

   

**90-Day Permanent Deletion (Clean-up)**

- Safety Checks: Enforces a manual "type exact expected name" validation prompt before allowing any destructive actions, preventing accidental deletions of similarly-named accounts. 
