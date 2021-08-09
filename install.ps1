<#

.SYNOPSIS
Installer for Lepton

.DESCRIPTION
Installs Lepton onto selected Firefox profiles

.INPUTS
TODO: input directories for installation?
Would need to discuss a non-interactive install system

.OUTPUTS
TODO: output directories that Lepton has been installed to?

.PARAMETER u
Specifies whether to update a current installation
Defaults to false

.PARAMETER f
Specifies a custom path to look for Firefox profiles in

.PARAMETER p
Specifies a custom name to use when creating a profile

.PARAMETER h
Shows this help message

.PARAMETER ?
Shows this help message

.PARAMETER WhatIf
Runs the installer without actioning any file copies/moves
Equivelant to a dry-run

.EXAMPLE
PS> .\Install.ps1 -u -f C:\Users\someone\ff-profiles
Updates current installations in the profile directory 'C:\Users\someone\ff-profiles'

.LINK
https://github.com/black7375/Firefox-UI-Fix#readme

#>

[CmdletBinding(
  SupportsShouldProcess = $true,
  PositionalBinding = $false
)]

param(
  [Alias("u")]
  [Switch]$updateMode,
  [Alias("f")]
  [string]$profileDir,
  [Alias("p")]
  [string]$profileName,
  [Alias("h")]
  [Switch]$help = $false
)

#** Helper Utils ***************************************************************
#== Message ====================================================================
function Lepton-ErrorMessage() {
  Write-Error "FAILED: ${args}"
  exit -1
}

function Lepton-OKMessage() {
  $local:SIZE = 50
  $local:FILLED = ""
  for ($i = 0; $i -le ($SIZE - 2); $i++) {
    $FILLED += "."
  }
  $FILLED += "OK"

  $local:message = "${args}"
  Write-Host ${message}(${FILLED}.Substring(${message}.Length))
}

$PSMinSupportedVersion = 2
function Verify-PowerShellVersion {
  Write-Host -NoNewline "Checking PowerShell version... "
  $PSVersion = [int](Select-Object -Property Major -First 1 -ExpandProperty Major -InputObject $PSVersionTable.PSVersion)

  Write-Host "[$PSVersion]"
  if ($PSVersion -lt $PSMinSupportedVersion) {
      Write-Error -Category NotInstalled "You need a minimum PowerShell version of [$PSMinSupportedVersion] to use this installer"
      exit -1
  }
}

#== Required Tools =============================================================
function Install-Choco() {
  # https://chocolatey.org/install
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
  iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}

function Check-Git() {
  if( -Not (Get-Command git) ) {
    if ( -Not (Get-Command choco)) {
      Install-Choco
    }
    choco install git -y
  }

  Lepton-OKMessage "Required - git"
}

#== PATH / File ================================================================
$currentDir = (Get-Location).path

function Filter-Path() {
  Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string[]] $pathList,
    [Parameter(Position=1)]
    [string]   $option = "Any"
  )

  return $pathList.Where({ Test-Path -Path "$_" -PathType "${option}" })
}

function Copy-Auto() {
  Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string] $file,
    [Parameter(Mandatory=$true, Position=1)]
    [string] $target
  )

  if ( "${file}" -eq "${target}" ) {
    Write-Host "'${file}' and ${target} are same file"
    return 0
  }

  if ( Test-Path -Path "${target}" ) {
    Write-Host "${target} alreay exist."
    Write-Host "Now Backup.."
    Copy-Auto "${target}" "${target}.bak"
    Write-Host ""
  }

  Copy-Item -Path "${file}" -Destination "${target}" -Force -Recurse
}

function Move-Auto() {
  Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string] $file,
    [Parameter(Mandatory=$true, Position=1)]
    [string] $target
  )

  if ( "${file}" -eq "${target}" ) {
    Write-Host "'${file}' and ${target} are same file"
    return 0
  }

  if ( Test-Path -Path "${target}" ) {
    Write-Host "${target} alreay exist."
    Write-Host "Now Backup.."
    Move-Auto "${target}" "${target}.bak"
    Write-Host ""
  }

  Get-ChildItem -Path "${target}" -Recurse | Move-Item -Path "${file}" -Destination "${target}" -Force
}

 function Restore-Auto() {
  Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string] $file
  )
  $local:target = "${file}.bak"

  if ( Test-Path -Path "${file}" ) {
    Remove-Item "${file}" -Recurse -Force
  }
  Get-ChildItem -Path "${target}" -Recurse | Move-Item -Destination "${file}" -Force

  $local:lookupTarget = "${target}.bak"
  if ( Test-Path -Path "${lookupTarget}" ) {
    Restore-Auto "${target}"
  }
}

function Write-File() {
  Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string] $filePath,
    [Parameter(Position=1)]
    [string] $fileContent = ""
  )

  if ( "${fileContent}" -eq "" ) {
    New-Item -Path "${filePath}" -Force
  }
  else {
    Out-File -FilePath "${filePath}" -InputObject "${fileContent}" -Force
  }
}

#== INI File ================================================================
# https://devblogs.microsoft.com/scripting/use-powershell-to-work-with-any-ini-file/
function Get-IniContent () {
  Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string] $filePath
  )

  $ini = @{}
  switch -regex -file $filePath {
    "^\[(.+)\]" {
      # Section
      $section = $matches[1]
      $ini[$section] = @{}
      $CommentCount = 0
    }
    "^(;.*)$" {
      # Comment
      $value = $matches[1]
      $CommentCount = $CommentCount + 1
      $name = “Comment” + $CommentCount
      $ini[$section][$name] = $value
    }
    "(.+?)\s*=(.*)" {
      # For compatibility
      if ( $section -eq $null ) {
        $section = "Info"
        $ini[$section] = @{}
      }

      # Key
      $name,$value = $matches[1..2]
      $ini[$section][$name] = $value
    }
  }
  return $ini
}

function Out-IniFile() {
  Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string] $filePath,
    [Parameter(Position=1)]
    [hashtable] $iniObject = @{}
  )

  # Create new file
  $local:outFile = New-Item -ItemType file -Path "${filepath}" -Force

  foreach ($i in $iniObject.keys) {
    if (!($($iniObject[$i].GetType().Name) -eq "Hashtable")) {
      #No Sections
      Add-Content -Path $outFile -Value "$i=$($iniObject[$i])"
    }
    else {
      #Sections
      Add-Content -Path $outFile -Value "[$i]"
      Foreach ($j in ($iniObject[$i].keys | Sort-Object)) {
        if ($j -match "^Comment[\d]+") {
          Add-Content -Path $outFile -Value "$($iniObject[$i][$j])"
        }
        else {
          Add-Content -Path $outFile -Value "$j=$($iniObject[$i][$j])"
        }

      }
      Add-Content -Path $outFile -Value ""
    }
  }
}

#** Select Menu ****************************************************************
# https://github.com/chrisseroka/ps-menu
function Check-PsMenu() {
  if(-Not (Get-InstalledModule ps-menu -ErrorAction silentlycontinue)) {
    Set-PSRepository PSGallery -InstallationPolicy Trusted
    Install-Module -Name ps-menu -Confirm:$False -Force
  }
}

function DrawMenu {
  param ($menuItems, $menuPosition, $Multiselect, $selection)
  $l = $menuItems.length
  for ($i = 0; $i -le $l; $i++) {
    if ($menuItems[$i] -ne $null){
      $item = $menuItems[$i]
      if ($Multiselect) {
        if ($selection -contains $i){
          $item = '[x] ' + $item
        }
        else {
          $item = '[ ] ' + $item
        }
      }
      if ($i -eq $menuPosition) {
        Write-Host "> $($item)" -ForegroundColor Green
      }
      else {
	Write-Host "  $($item)"
      }
    }
  }
}

function Toggle-Selection {
  param ($pos, [array]$selection)
  if ($selection -contains $pos){
    $result = $selection | where {$_ -ne $pos}
  }
  else {
    $selection += $pos
    $result = $selection
  }
  $result
}

function Menu {
  param ([array]$menuItems, [switch]$ReturnIndex=$false, [switch]$Multiselect)
  $vkeycode = 0
  $pos = 0
  $selection = @()
  if ($menuItems.Length -gt 0) {
    try {
      [console]::CursorVisible=$false #prevents cursor flickering
      DrawMenu $menuItems $pos $Multiselect $selection
      While ($vkeycode -ne 13 -and $vkeycode -ne 27) {
        $press = $host.ui.rawui.readkey("NoEcho,IncludeKeyDown")
        $vkeycode = $press.virtualkeycode
        If ($vkeycode -eq 38 -or $press.Character -eq 'k') {$pos--}
        If ($vkeycode -eq 40 -or $press.Character -eq 'j') {$pos++}
        If ($vkeycode -eq 36) { $pos = 0 }
        If ($vkeycode -eq 35) { $pos = $menuItems.length - 1 }
        If ($press.Character -eq ' ') { $selection = Toggle-Selection $pos $selection }
        if ($pos -lt 0) {$pos = 0}
        If ($vkeycode -eq 27) {$pos = $null }
        if ($pos -ge $menuItems.length) {$pos = $menuItems.length -1}
        if ($vkeycode -ne 27) {
          $startPos = [System.Console]::CursorTop - $menuItems.Length
          [System.Console]::SetCursorPosition(0, $startPos)
          DrawMenu $menuItems $pos $Multiselect $selection
        }
      }
    }
    finally {
      [System.Console]::SetCursorPosition(0, $startPos + $menuItems.Length)
      [console]::CursorVisible = $true
    }
  }
  else {
    $pos = $null
  }

  if ($ReturnIndex -eq $false -and $pos -ne $null)  {
    if ($Multiselect){
      return $menuItems[$selection]
    }
    else {
      return $menuItems[$pos]
    }
  }
  else {
    if ($Multiselect) {
      return $selection
    }
    else {
      return $pos
    }
  }
}

#** Profile ********************************************************************
#== Profile Dir ================================================================
# $HOME = (get-psprovider 'FileSystem').Home
$firefoxProfileDirPaths = @(
  "${HOME}\AppData\Roaming\Mozilla\Firefox",
  "${HOME}\AppData\Roaming\LibreWolf"
)

function Check-ProfileDir() {
  Param (
    [Parameter(Position=0)]
    [string] $profileDir = ""
  )

  if ( "${profileDir}" -ne "" ) {
    $global:firefoxProfileDirPaths = @("${profileDir}")
  }


  $global:firefoxProfileDirPaths = Filter-Path $global:firefoxProfileDirPaths "Container"

  if ( $firefoxProfileDirPaths.Length -eq 0 ) {
    Lepton-ErrorMessage "Unable to find firefox profile dir."
  }

  Lepton-OKMessage "Profiles dir found"
}

#== Profile Info ===============================================================
$PROFILEINFOFILE="profiles.ini"
function Check-ProfileIni() {
  foreach ( $profileDir in $global:firefoxProfileDirPaths ) {
    if ( -Not (Test-Path -Path "${profileDir}\${PROFILEINFOFILE}" -PathType "Leaf") ) {
      Lepton-ErrorMessage "Unable to find ${PROFILEINFOFILE} at ${profileDir}"
    }
  }

  Lepton-OKMessage "Profiles info file found"
}

#== Profile PATH ===============================================================
$firefoxProfilePaths = @()
function Update-ProfilePaths() {
  foreach ( $profileDir in $global:firefoxProfileDirPaths ) {
    $local:iniContent = Get-IniContent "${profileDir}\${PROFILEINFOFILE}"
    $global:firefoxProfilePaths += $iniContent.Values.Path | ForEach-Object  { "${profileDir}\${PSItem}" }
  }

  if ( $firefoxProfilePaths.Length -ne 0 ) {
    Lepton-OkMessage "Profile paths updated"
  }
  else {
    Lepton-ErrorMessage "Doesn't exist profiles"
  }
}

# TODO: Multi select support
function Select-Profile() {
  Param (
    [Parameter(Position=0)]
    [string] $profileName = ""
  )

  if ( "${profileName}" -ne "" ) {
    $local:targetPath = ""
    foreach ( $profilePath in $global:firefoxProfilePaths ) {
      if ( "${profilePath}" -like "*${profileName}" ) {
        $targetPath = "${profilePath}"
        break
      }
    }

    if ( "${targetPath}" -ne "" ) {
      Lepton-OkMessage "Profile, `"${profileName}`" found"
      $global:firefoxProfilePaths = @("${targetPath}")
    }
    else {
      Lepton-ErrorMessage "Unable to find ${profileName}"
    }
  }
  else {
    if ( $firefoxProfilePaths.Length -eq 1 ) {
      Lepton-OkMessage "Auto detected profile"
    }
    else {
      $global:firefoxProfilePaths = Menu $firefoxProfilePaths

      if ( $firefoxProfilePaths.Length -eq 0 ) {
        Lepton-ErrorMessage "Please select profiles"
      }

      Lepton-OkMessage "Selected profile"
    }
  }
}

#** Lepton Info File ***********************************************************
# If you interst RFC, see install.sh

#== Lepton Info ================================================================
$LEPTONINFOFILE ="lepton.ini"
function Check-LeptonIni() {
  foreach ( $profileDir in $global:firefoxProfileDirPaths ) {
    if ( -Not (Test-Path -Path "${profileDir}\${LEPTONINFOFILE}") ) {
      Lepton-ErrorMessage "Unable to find ${LEPTONINFOFILE} at ${profileDir}"
    }
  }

  Lepton-OkMessage "Lepton info file found"
}

#== Create info file ===========================================================
# We should always create a new one, as it also takes into account the possibility of setting it manually.
# Updates happen infrequently, so the creation overhead  is less significant.

function Get-ProfileDir() {
  Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string] $profilePath
  )
  foreach ( $profileDir in $firefoxProfileDirPaths ) {
    if ( "$profilePath" -like "${profileDir}*" ) {
      return "$profileDir"
    }
  }
}

$CHROMEINFOFILE="LEPTON"
function Write-LeptonInfo() {
  # Init info
  $local:output     = @{}
  $local:prevDir    = $firefoxProfileDirPaths[0]
  $local:latestPath = ( $firefoxProfilePaths | Select-Object -Last 1 )
  foreach ( $profilePath in $global:firefoxProfilePaths ) {
    $local:LEPTONINFOPATH = "${profilePath}\chrome\${CHROMEINFOFILE}"
    $local:LEPTONGITPATH  = "${profilePath}\chrome\.git"

    # Profile info
    $local:Type   = ""
    $local:Ver    = ""
    $local:Branch = ""
    $local:Path   = ""
    if ( Test-Path -Path "${LEPTONINFOPATH}" ) {
      if ( Test-Path -Path "${LEPTONGITPATH}" -PathType "Container" ) {
        $Type   = "Git"
        $Ver    = $(git --git-dir "${LEPTONGITPATH}" rev-parse HEAD)
        $Branch = $(git --git-dir "${LEPTONGITPATH}" rev-parse --abbrev-ref HEAD)
      }
      else {
        $local:iniContent = Get-IniContent "${LEPTONINFOPATH}"
        $Type   = $iniContent["Info"]["Type"]
        $Ver    = $iniContent["Info"]["Ver"]
        $Branch = $iniContent["Info"]["Branch"]

        if ( "${Type}" -eq "" ) {
          $Type = "Local"
        }
      }

      $Path = "${profilePath}"
    }

    # Flushing
    $local:profileDir  = Get-ProfileDir "${profilePath}"
    $local:profileName = Split-Path "${profilePath}" -Leaf
    if ( "${prevDir}" -ne "${profileDir}" ) {
      Out-IniFile "${prevDir}\${LEPTONINFOFILE}" $output
      $output = @{}
    }

    # Make output contents
    foreach ( $key in @("Type", "Branch", "Ver", "Path") ) {
      $local:value = (Get-Variable -Name "${key}").Value
      if ( "$value" -ne "" ) {
        $output["${profileName}"] += @{"${key}" = "${value}"}
      }
    }

    # Latest element flushing
    if ( "${profilePath}" -eq "${latestPath}" ) {
      Out-IniFile "${profileDir}\${LEPTONINFOFILE}" $output
    }
    $prevDir = "${profileDir}"
  }

  # Verify
  Check-LeptonIni
  Lepton-OkMessage "Lepton info file created"
}

#** Install ********************************************************************
#== Install Types ==============================================================
$updateMode   = $false
$leptonBranch = "master"
function Select-Distribution() {
  while ( $true ) {
    $local:selected = $false
    $local:selectedDistribution = Menu @("Original(default)", "Photon-Style", "Proton-Style", "Update")
    switch ( $selectedDistribution ) {
      "Original(default)" { $global:leptonBranch = "master"      ; $selected = $true }
      "Photon-Style"      { $global:leptonBranch = "photon-style"; $selected = $true }
      "Proton-Style"      { $global:leptonBranch = "proton-style"; $selected = $true }
      "Update"            { $global:updateMode   = $true         ; $selected = $true }
      default             { Write-Host "Invalid option, reselect please." }
    }

    if ( $selected -eq $true ) {
      break
    }
  }
  Lepton-OkMessage "Selected ${selectedDistribution}"
}

$leptonInstallType = "Network" # Other types: Local, Release
function Check-InstallType() {
  Param (
    [Parameter(Mandatory=$true, Position=0)]
    [string[]] $targetList,
    [Parameter(Mandatory=$true, Position=1)]
    [string] $installType
  )

  $local:targetCount = $targetList.Length
  $local:foundCount  = (Filter-Path $targetList ).Length

  if ( "${targetCount}" -eq "${foundCount}" ) {
    $global:leptonInstallType="${installType}"
  }
}

$checkLocalFiles = @(
  "userChrome.css",
  "userContent.css",
  "icons"
)
$checkReleaseFiles = @(
  "user.js"
  "chrome\userChrome.css"
  "chrome\userContent.css"
  "chrome\icons"
)
function Check-InstallTypes() {
  Check-InstallType $checkLocalFiles   "Local"
  Check-InstallType $checkReleaseFiles "Release"

  Lepton-OkMessage "Checked install type: ${leptonInstallType}"
  if ( "${leptonInstallType}" -eq "Network" ) {
    Select-Distribution
  }
  if ( "${leptonInstallType}" -eq "Local" ) {
    if ( Test-Path -Path ".git" -PathType "Container" ) {
      Select-Distribution
      git checkout "${leptonBranch}"
    }
  }
}

#== Install Helpers ============================================================
$chromeDuplicate = $false
function Check-ChromeExist() {
  if ( (Test-Path -Path "chrome") -and (-Not (Test-Path -Path "chrome\${LEPTONINFOFILE}")) ) {
    $global:chromeDuplicate = $true
    Move-Auto "chrome" "chrome.bak"
    Lepton-OkMessage "Backup files"
  }
}
function Check-ChromeRestore() {
  if ( "${chromeDuplicate}" -eq $true ) {
    Restore-Auto "chrome"
    Lepton-OkMessage "End restore files"
  }
  Lepton-OkMessage "End check restore files"
}

function Clean-Lepton() {
  if ( $chromeDuplicate -ne $true ) {
    Remove-Item "chrome" -Recurse -Force
  }
  Lepton-OkMessage "End clean files"
}
function Clone-Lepton() {
  Param (
    [Parameter(Position=0)]
    [string] $branch = ""
  )

  if ( "${branch}" -eq "" ) {
    $branch = "${leptonBranch}"
  }

  git clone -b "${branch}" https://github.com/black7375/Firefox-UI-Fix.git chrome
  if ( -Not (Test-Path -Path "chrome" -PathType "Container") ) {
    Lepton-ErrorMessage "Unable to find downloaded files"
  }
}

function Copy-Lepton() {
  Param (
    [Parameter(Position=0)]
    [string] $chromeDir = "chrome",
    [Parameter(Position=0)]
    [string] $userJSPath = "${chromeDir}\user.js"
  )

  foreach ( $profilePath in $global:firefoxProfilePaths ) {
    Copy-Auto "${userJSPath}" "${profilePath}\user.js"
    Copy-Auto "${chromeDir}"  "${profilePath}\chrome"
  }

  Lepton-OkMessage "End profile copy"
}

#== Each Install ===============================================================
function Install-Local() {
  Copy-Lepton "${currentDir}" "user.js"
}

function Install-Release() {
  Copy-Lepton "chrome" "user.js"
}

function Install-Network() {
  Check-ChromeExist
  Check-Git

  Clone-Lepton
  Copy-Lepton

  Clean-Lepton
  Check-ChromeRestore
}

function Install-Profile() {
  Lepton-OkMessage "Started install"

  switch ( "${leptonInstallType}" ) {
    "Local"   { Install-Local   }
    "Release" { Install-Release }
    "Network" { Install-Network }
  }

  Lepton-OkMessage "End install"
}

#** Update *********************************************************************
function Update-Profile() {
  Check-Git
  foreach ( $profileDir in $global:firefoxProfileDirPaths ) {
    $local:LEPTONINFOPATH = "${profileDir}\${LEPTONINFOFILE}"
    $local:LEPTONINFO     = Get-IniContent "${LEPTONINFOPATH}"
    $local:sections       = $LEPTONINFO.Keys
    if ( $sections.Length -ne 0 ) {
      foreach ( $section in $sections ) {
        $local:Type   = $LEPTONINFO["${section}"]["Type"]
        $local:Branch = $LEPTONINFO["${section}"]["Branch"]
        $local:Path   = $LEPTONINFO["${section}"]["Path"]

        $local:LEPTONGITPATH="${Path}\chrome\.git"
        if ( "${Type}" -eq "Git" ){
          git --git-dir "${LEPTONGITPATH}" checkout "${Branch}"
          git --git-dir "${LEPTONGITPATH}" pull --no-edit
        }
        elseif ( "${Type}" -eq "Local" -or "${Type}" -eq "Release" ) {
          Check-ChromeExist
          Clone-Lepton

          $firefoxProfilePaths = @("${Path}")
          Copy-Lepton

          if ( "${Branch}" -eq $null ) {
            $Branch = "${leptonBranch}"
          }
          git --git-dir "${LEPTONGITPATH}" checkout "${Branch}"

          if ( "${Type}" -eq "Release" ) {
            $local:Ver=$(git --git-dir "${LEPTONINFOFILE}" describe --tags --abbrev=0)
            git --git-dir "${LEPTONGITPATH}" checkout "tags/${Ver}"
          }
        }
        else {
          Lepton-ErrorMessage "Unable to find update type, ${Type} at ${section}"
        }
      }
    }
  }
  Clean-Lepton
  Check-ChromeRestore
}

#** Main ***********************************************************************
function Check-Help {
  # Cheap and dirty way of getting the same output as '-?' for '-h' and '-Help'
  if ($help) {
    Get-Help "$PSCommandPath"
    exit 0
  }
}

function Install-Lepton {
  Verify-PowerShellVersion  # Check installed version meets minimum
  Check-InstallTypes

  Check-ProfileDir $profileDir
  Check-ProfileIni
  Update-ProfilePaths
  Write-LeptonInfo

  if ( $updateMode ) {
    Update-Profile
  }
  else {
    Select-Profile $profileName
    Install-Profile
  }

  Write-LeptonInfo
}

Check-Help
Install-Lepton
