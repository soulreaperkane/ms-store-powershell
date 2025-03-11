# Function to check if the script is running as administrator
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Relaunch the script as administrator if not already running as admin
if (-not (Test-Admin)) {
    Write-Host "This script requires administrative privileges. Attempting to restart as administrator..."
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Determine architecture
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64") { "x64" } else { "x86" }

# Set the current directory
Set-Location -Path $PSScriptRoot

# Define the list of files to search for
$filesToSearch = @(
    "DesktopAppInstaller.AppxBundle",
    "DesktopAppInstaller.xml",
    "NET.Native.Framework.x64.Appx",
    "NET.Native.Framework.x86.Appx",
    "NET.Native.Runtime.x64.Appx",
    "NET.Native.Runtime.x86.Appx",
    "StorePurchaseApp.xml",
    "StorePurchaseApp.AppxBundle",
    "VCLibs.x64.Appx",
    "VCLibs.x86.Appx",
    "WindowsStore.xml",
    "WindowsStore.AppxBundle",
    "XboxIdentityProvider.xml",
    "XboxIdentityProvider.AppxBundle"
)

# Initialize an array to hold found file paths
$foundFiles = @()

# Search for each file
foreach ($file in $filesToSearch) {
    Write-Host "Searching for: $file"
    try {
        $results = Get-ChildItem -Path "C:\" -Filter $file -Recurse -ErrorAction Stop -Force
        if ($results) {
            $foundFiles += $results.FullName
        }
    } catch {
        Write-Host "Error searching for ${file}: $_"
    }
}

# Output the results
if ($foundFiles.Count -eq 0) {
    Write-Host "No files found."
} else {
    Write-Host "Found the following files:"
    $foundFiles | ForEach-Object { Write-Host $_ }
}

# Check for required files
$storeFiles = Get-ChildItem -Filter "*WindowsStore*.appxbundle"
$xmlFiles = Get-ChildItem -Filter "*WindowsStore*.xml"
if (-not $storeFiles -or -not $xmlFiles) {
    Write-Host "============================================================"
    Write-Host "Error: Required files are missing in the current directory"
    Write-Host "============================================================"
    exit
}

# Initialize package variables
$Store = Get-ChildItem -Filter "*WindowsStore*.appxbundle" | Select-Object -First 1
$Framework6X64 = Get-ChildItem -Filter "*NET.Native.Framework*1.6*.appx" | Where-Object { $_.Name -like "*x64*" } | Select-Object -First 1
$Framework6X86 = Get-ChildItem -Filter "*NET.Native.Framework*1.6*.appx" | Where-Object { $_.Name -like "*x86*" } | Select-Object -First 1
$Runtime6X64 = Get-ChildItem -Filter "*NET.Native.Runtime*1.6*.appx" | Where-Object { $_.Name -like "*x64*" } | Select-Object -First 1
$Runtime6X86 = Get-ChildItem -Filter "*NET.Native.Runtime*1.6*.appx" | Where-Object { $_.Name -like "*x86*" } | Select-Object -First 1
$VCLibsX64 = Get-ChildItem -Filter "*VCLibs*140*.appx" | Where-Object { $_.Name -like "*x64*" } | Select-Object -First 1
$VCLibsX86 = Get-ChildItem -Filter "*VCLibs*140*.appx" | Where-Object { $_.Name -like "*x86*" } | Select-Object -First 1

# Set dependency packages
if ($arch -eq "x64") {
    $DepStore = "$VCLibsX64,$VCLibsX86,$Framework6X64,$Framework6X86,$Runtime6X64,$Runtime6X86"
    $DepPurchase = "$VCLibsX64,$VCLibsX86,$Framework6X64,$Framework6X86,$Runtime6X64,$Runtime6X86"
    $DepXbox = "$VCLibsX64,$VCLibsX86,$Framework6X64,$Framework6X86,$Runtime6X64,$Runtime6X86"
    $DepInstaller = "$VCLibsX64,$VCLibsX86"
} else {
    $DepStore = "$VCLibsX86,$Framework6X86,$Runtime6X86"
    $DepPurchase = "$VCLibsX86,$Framework6X86,$Runtime6X86"
    $DepXbox = "$VCLibsX86,$Framework6X86,$Runtime6X86"
    $DepInstaller = "$VCLibsX86"
}

# Check if dependencies exist
foreach ($dep in $DepStore -split ',') {
    if (-not (Test-Path $dep)) {
        Write-Host "============================================================"
        Write-Host "Error: Required files are missing in the current directory"
        Write-Host "============================================================"
        exit
    }
}

# PowerShell command for adding packages
$PScommand = "Add-AppxProvisionedPackage -Online -PackagePath"

Write-Host "============================================================"
Write-Host "Adding Microsoft Store"
Write-Host "============================================================"
Invoke-Expression "$PScommand $Store.FullName -DependencyPackagePath $DepStore -LicensePath Microsoft.WindowsStore_8wekyb3d8bbwe.xml"
foreach ($dep in $DepStore -split ',') {
    Invoke-Expression "Add-AppxPackage -Path $dep"
}
Invoke-Expression "Add-AppxPackage -Path $Store.FullName"

# Check and add other applications if defined
$PurchaseApp = Get-ChildItem -Filter "*StorePurchaseApp*.appxbundle" | Select-Object -First 1
if ($PurchaseApp) {
    Write-Host "============================================================"
    Write-Host "Adding Store Purchase App"
    Write-Host "============================================================"
    Invoke-Expression "$PScommand $PurchaseApp.FullName -DependencyPackagePath $DepPurchase -LicensePath Microsoft.StorePurchaseApp_8wekyb3d8bbwe.xml"
    Invoke-Expression "Add-AppxPackage -Path $PurchaseApp.FullName"
}

$AppInstaller = Get-ChildItem -Filter "*DesktopAppInstaller*.appxbundle" | Select-Object -First 1
if ($AppInstaller) {
    Write-Host "============================================================"
    Write-Host "Adding App Installer"
    Write-Host "============================================================"
    Invoke-Expression "$PScommand $AppInstaller.FullName -DependencyPackagePath $DepInstaller -LicensePath Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.xml"
    Invoke-Expression "Add-AppxPackage -Path $AppInstaller.FullName"
}

$XboxIdentity = Get-ChildItem -Filter "*XboxIdentityProvider*.appxbundle" | Select-Object -First 1
if ($XboxIdentity) {
    Write-Host "============================================================"
    Write-Host "Adding Xbox Identity Provider"
    Write-Host "============================================================"
    Invoke-Expression "$PScommand $XboxIdentity.FullName -DependencyPackagePath $DepXbox -LicensePath Microsoft.XboxIdentityProvider_8wekyb3d8bbwe.xml"
    Invoke-Expression "Add-AppxPackage -Path $XboxIdentity.FullName"
}

# Indicate completion
Write-Host "============================================================"
Write-Host "Done"
Write-Host "============================================================"

# Exit the script automatically
exit
