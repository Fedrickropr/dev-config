# Requires Chocolatey. Run elevated as your normal Windows account.
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Config {
    param(
        [string] $Path,
        [string] $Content
    )

    $Content = $Content.Replace("`r`n", "`n").TrimEnd() + "`n"

    if (Test-Path -LiteralPath $Path) {
        if ([IO.File]::ReadAllText($Path) -eq $Content) {
            return
        }

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        Copy-Item -LiteralPath $Path -Destination "$Path.backup-$timestamp"
    }

    [IO.File]::WriteAllText($Path, $Content, $utf8)
}

# Install applications.
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    throw 'Install Chocolatey first: https://chocolatey.org/install'
}

choco install alacritty git -y --no-progress
if ($LASTEXITCODE -notin @(0, 1641, 3010)) {
    throw "Chocolatey failed with exit code $LASTEXITCODE."
}

# Locate Git Bash.
$candidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
if ($gitCommand) {
    $gitRoot = Split-Path (Split-Path $gitCommand.Source)
    $candidates += Join-Path $gitRoot 'bin\bash.exe'
}

$bash = $candidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1

if (-not $bash) {
    throw 'Git Bash was not found. Add its installation path to $candidates.'
}

# Install ble.sh once. A prebuilt archive avoids build dependencies.
$installBle = @'
set -e
export PATH="/usr/bin:/bin:$PATH"

if [[ ! -f "$HOME/.local/share/blesh/ble.sh" ]]; then
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    curl -fL \
        https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz \
        -o "$temp_dir/ble.tar.xz"

    tar -xJf "$temp_dir/ble.tar.xz" -C "$temp_dir"
    bash "$temp_dir/ble-nightly/ble.sh" --install "$HOME/.local/share"
fi
'@

$tempScript = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText(
        $tempScript,
        $installBle.Replace("`r`n", "`n"),
        $utf8
    )

    & $bash --noprofile --norc ($tempScript.Replace('\', '/'))
    if ($LASTEXITCODE -ne 0) {
        throw "ble.sh installation failed with exit code $LASTEXITCODE."
    }
} finally {
    Remove-Item -LiteralPath $tempScript -ErrorAction SilentlyContinue
}

# Generate an explicit startup file instead of modifying existing profiles.
$configDir = Join-Path $env:APPDATA 'alacritty'
New-Item -ItemType Directory -Path $configDir -Force | Out-Null

$bashrcPath = Join-Path $configDir 'bashrc'
$bashrc = @'
# Prefer Git's Unix utilities while preserving the Windows PATH.
export PATH="/usr/bin:/bin:$PATH"
export USER="${USER:-$(id -un)}"
export LANG="${LANG:-en_US.UTF-8}"

set -o vi

# Ignore previous .blerc configuration and attach after setup.
source "$HOME/.local/share/blesh/ble.sh" \
    --attach=none --rcfile /dev/null

# Keep syntax colours without filesystem-based highlighting.
bleopt highlight_filename=

# Configure completion after its module is available.
ble-import core-complete -C '
    bleopt complete_auto_complete_opts=syntax-disabled
    ble-bind -m auto_complete -f C-i auto_complete/insert
    ble-bind -m auto_complete -f TAB auto_complete/insert
'

# Alacritty sends Ctrl+Backspace as Ctrl+underscore.
# An eword consists of letters and digits, with punctuation as boundaries.
blehook/eval-after-load keymap_vi '
    ble-bind -m vi_imap -f C-_ delete-backward-eword
'

PS1='\u@\h \w \$ '
ble-attach
'@

Write-Config -Path $bashrcPath -Content $bashrc

# JSON quoting is compatible with these TOML string values.
$bashJson = ConvertTo-Json -InputObject ($bash.Replace('\', '/')) -Compress
$rcJson = ConvertTo-Json -InputObject ($bashrcPath.Replace('\', '/')) -Compress

$alacrittyConfig = @"
[terminal.shell]
program = $bashJson
args = ["--noprofile", "--rcfile", $rcJson, "-i"]

[[keyboard.bindings]]
key = "Back"
mods = "Control"
mode = "~Vi"
chars = "\u001f"
"@

Write-Config `
    -Path (Join-Path $configDir 'alacritty.toml') `
    -Content $alacrittyConfig

Write-Host 'Done. Open Alacritty normally from Start.'
Write-Host 'Esc: Vim normal mode. Tab: accept suggestion. Ctrl+Backspace: delete word.'
