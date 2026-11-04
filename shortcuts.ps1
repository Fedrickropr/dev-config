# Locate Alacritty, including a fresh Chocolatey installation.
$alacrittyCommand = Get-Command alacritty.exe -ErrorAction SilentlyContinue
$alacritty = if ($alacrittyCommand) {
    $alacrittyCommand.Source
} else {
    "$env:ChocolateyInstall\bin\alacritty.exe"
}

if (-not (Test-Path $alacritty)) {
    throw 'Cannot find alacritty.exe.'
}

# Register "al" for shell launches, including Win+R.
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\al.exe'
New-Item -Path $key -Force | Out-Null
Set-Item -Path $key -Value $alacritty

# Add a searchable Start-menu shortcut.
$programs = [Environment]::GetFolderPath('Programs')
$shortcutPath = Join-Path $programs 'al.lnk'

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $alacritty
$shortcut.Description = 'Alacritty with Git Bash'
$shortcut.WorkingDirectory = $env:USERPROFILE
$shortcut.Save()
