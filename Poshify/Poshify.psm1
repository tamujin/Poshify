<#
.SYNOPSIS
    Poshify - A PowerShell module for managing oh-my-posh themes

.DESCRIPTION
    This module provides functions to list, install, update, remove, preview and switch between
    oh-my-posh themes, and to keep a list of favorite themes.

    Poshify adds a single marked block to your PowerShell profile that loads whichever theme
    is currently selected. Switching themes only changes that selection, so the rest of your
    profile is never rewritten.
#>

# Module variables
$script:PoshifyHome = Join-Path $HOME '.poshthemes'
$script:OhMyPoshGitHubThemesUrl = 'https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/contents/themes'
$script:ThemeFilePattern = '\.omp\.(json|ya?ml|toml)$'
$script:ProfileBlockStart = '# >>> poshify >>>'
$script:ProfileBlockEnd = '# <<< poshify <<<'
$script:CacheMaxAge = [TimeSpan]::FromMinutes(60)
$script:DefaultTheme = 'jandedobbeleer'
$script:SetupThemeChoices = 'jandedobbeleer', 'atomic', 'paradox', 'powerlevel10k_rainbow', 'catppuccin_mocha', 'tokyonight_storm', 'night-owl', 'pure'
$script:NerdFontName = 'Meslo'
$script:NerdFontFamily = 'MesloLGM Nerd Font'
$script:OhMyPoshInstallUrl = 'https://ohmyposh.dev/docs/installation'

# Show a compact table by default; the remaining properties are still on the objects
Update-TypeData -TypeName 'Poshify.Theme' -DefaultDisplayPropertySet 'Name', 'Source', 'Current', 'Favorite' -Force
Update-TypeData -TypeName 'Poshify.OnlineTheme' -DefaultDisplayPropertySet 'Name', 'SizeKB' -Force

#region Private helpers

function Test-PoshifyWindows {
    $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows
}

function Get-PoshifyEditionName {
    param([string]$Edition)
    if ($Edition -eq 'Desktop') { 'Windows PowerShell' } else { 'PowerShell 7' }
}

# Profiles Poshify manages: the running edition's, plus on Windows the other edition's, so the
# theme shows up in both Windows PowerShell and PowerShell 7
function Get-PoshifyProfileTarget {
    [PSCustomObject]@{ Edition = $PSVersionTable.PSEdition; Path = $PROFILE.CurrentUserAllHosts; IsCurrent = $true }

    if (-not (Test-PoshifyWindows)) {
        return
    }
    $documents = [Environment]::GetFolderPath('MyDocuments')
    if ($PSVersionTable.PSEdition -eq 'Core') {
        [PSCustomObject]@{ Edition = 'Desktop'; Path = (Join-Path $documents 'WindowsPowerShell\profile.ps1'); IsCurrent = $false }
    }
    elseif (Get-Command -Name pwsh -CommandType Application -ErrorAction SilentlyContinue) {
        [PSCustomObject]@{ Edition = 'Core'; Path = (Join-Path $documents 'PowerShell\profile.ps1'); IsCurrent = $false }
    }
}

# Execution policy a new terminal of the given edition will run with
function Get-PoshifyExecutionPolicy {
    param([string]$Edition)

    if (-not (Test-PoshifyWindows)) {
        return 'Unrestricted'
    }

    $exe = if ($Edition -eq $PSVersionTable.PSEdition) { (Get-Process -Id $PID).Path }
    elseif ($Edition -eq 'Desktop') { 'powershell.exe' }
    else { 'pwsh.exe' }

    # A process-scoped policy (e.g. -ExecutionPolicy Bypass) is inherited through this variable;
    # hide it so the child reports what a fresh terminal gets
    $inherited = $env:PSExecutionPolicyPreference
    $env:PSExecutionPolicyPreference = $null
    try {
        $policy = & $exe -NoLogo -NoProfile -NonInteractive -Command 'Get-ExecutionPolicy' 2>$null | Select-Object -First 1
        if ($policy) { "$policy".Trim() } else { 'Unknown' }
    }
    catch {
        'Unknown'
    }
    finally {
        $env:PSExecutionPolicyPreference = $inherited
    }
}

function Test-PoshifyPolicyBlocksProfile {
    param([string]$Policy)
    $Policy -in 'Restricted', 'AllSigned', 'Undefined'
}

function Get-PoshifyPolicyAdvice {
    param([string]$Edition, [string]$Policy)
    $name = Get-PoshifyEditionName $Edition
    "$name can't run your profile because its execution policy is $Policy, so the theme won't load there. " +
    "To allow local scripts, run this in ${name}: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
}

function Get-OhMyPoshCommand {
    Get-Command -Name oh-my-posh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Invoke-OhMyPosh {
    param([string[]]$ArgumentList)
    & (Get-OhMyPoshCommand) @ArgumentList
}

# File that holds the full path of the selected theme; read by the profile block at startup
function Get-PoshifyCurrentThemeFile {
    Join-Path $script:PoshifyHome 'current'
}

function Get-PoshifyCacheFile {
    Join-Path $script:PoshifyHome '.cache/themes.json'
}

function Get-PoshifyFavoritesFile {
    Join-Path $script:PoshifyHome '.favorites.json'
}

function Get-PoshifyCurrentThemePath {
    $file = Get-PoshifyCurrentThemeFile
    if (Test-Path -LiteralPath $file) {
        Get-Content -LiteralPath $file -TotalCount 1
    }
}

function Get-PoshifyThemeName {
    param([string]$FileName)
    $FileName -replace $script:ThemeFilePattern, ''
}

# Directories searched for themes, in priority order. Themes downloaded by Poshify shadow
# the ones bundled with oh-my-posh (POSH_THEMES_PATH), which may not exist on every install.
function Get-PoshifyThemeSource {
    [PSCustomObject]@{ Name = 'Poshify'; Path = $script:PoshifyHome }
    if ($env:POSH_THEMES_PATH) {
        [PSCustomObject]@{ Name = 'oh-my-posh'; Path = $env:POSH_THEMES_PATH }
    }
}

function ConvertTo-PoshifyThemeObject {
    param(
        [System.IO.FileInfo]$File,
        [string]$Source,
        [string]$CurrentPath,
        [string[]]$Favorites
    )

    $name = Get-PoshifyThemeName $File.Name
    [PSCustomObject]@{
        PSTypeName   = 'Poshify.Theme'
        Name         = $name
        Source       = $Source
        Current      = $File.FullName -eq $CurrentPath
        Favorite     = $name -in $Favorites
        SizeKB       = [math]::Round($File.Length / 1KB, 2)
        LastModified = $File.LastWriteTime
        Path         = $File.FullName
    }
}

function ConvertTo-PoshifyOnlineTheme {
    param($Entry)

    [PSCustomObject]@{
        PSTypeName  = 'Poshify.OnlineTheme'
        Name        = Get-PoshifyThemeName $Entry.name
        FileName    = $Entry.name
        SizeKB      = [math]::Round($Entry.size / 1KB, 2)
        DownloadUrl = $Entry.download_url
        Sha         = $Entry.sha
    }
}

# Exact name match wins; otherwise wildcards are honoured and plain text is a substring search
function Select-PoshifyThemeMatch {
    param(
        [object[]]$Theme,
        [string]$Name
    )

    $exact = @($Theme | Where-Object { $_.Name -eq $Name })
    if ($exact.Count -gt 0) {
        return $exact
    }

    $pattern = if ([WildcardPattern]::ContainsWildcardCharacters($Name)) { $Name } else { "*$Name*" }
    @($Theme | Where-Object { $_.Name -like $pattern })
}

function Resolve-PoshifySingleTheme {
    param(
        [object[]]$Match,
        [string]$Name,
        [string]$Location
    )

    if ($Match.Count -eq 1) {
        return $Match[0]
    }

    if ($Match.Count -eq 0) {
        Write-Error -Message "Theme '$Name' not found $Location." -Category ObjectNotFound -TargetObject $Name
        return
    }

    $names = ($Match | Select-Object -First 10 -ExpandProperty Name) -join ', '
    if ($Match.Count -gt 10) {
        $names += ", ... ($($Match.Count) total)"
    }
    Write-Error -Message "Theme name '$Name' is ambiguous $Location. Matches: $names" -Category InvalidArgument -TargetObject $Name
}

# Resolves -Name or -ThemePath to an object with Name and Path, writing an error if that fails.
# With -IncludeOnline, a name with no local match that exactly matches an online theme returns
# that Poshify.OnlineTheme (which has no Path) so the caller can download it.
function Resolve-PoshifyThemeFile {
    param(
        [string]$Name,
        [string]$ThemePath,
        [switch]$IncludeOnline
    )

    if ($ThemePath) {
        $item = Get-Item -LiteralPath $ThemePath -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) {
            Write-Error -Message "Theme file not found: $ThemePath" -Category ObjectNotFound -TargetObject $ThemePath
            return
        }
        return [PSCustomObject]@{ Name = Get-PoshifyThemeName $item.Name; Path = $item.FullName }
    }

    $local = @(Select-PoshifyThemeMatch -Theme (Get-PoshifyTheme) -Name $Name)
    if ($local.Count -eq 0 -and $IncludeOnline) {
        $online = @(Get-PoshifyOnlineThemeList) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if ($online) {
            return $online
        }
    }

    $location = if ($local.Count -gt 1) { 'locally' }
    elseif ($IncludeOnline) { 'locally or online. Use Find-PoshifyTheme to search' }
    else { 'locally. Use Find-PoshifyTheme and Install-PoshifyTheme to get it' }
    Resolve-PoshifySingleTheme -Match $local -Name $Name -Location $location
}

# Online theme list, cached for an hour. A stale cache is used when GitHub can't be reached.
function Get-PoshifyOnlineThemeList {
    param([switch]$ForceRefresh)

    $cacheFile = Get-PoshifyCacheFile
    $cache = $null
    $cachedAt = $null
    if (Test-Path -LiteralPath $cacheFile) {
        try {
            $cache = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
            $cachedAt = $cache.CachedAt -as [datetime]
        }
        catch {
            Write-Verbose "Ignoring unreadable theme cache: $cacheFile"
        }
    }

    if (-not $ForceRefresh -and $cachedAt -and ([datetime]::UtcNow - $cachedAt.ToUniversalTime()) -lt $script:CacheMaxAge) {
        Write-Verbose "Using theme list cached at $cachedAt"
        return $cache.Themes | ForEach-Object { ConvertTo-PoshifyOnlineTheme $_ }
    }

    Write-Verbose "Fetching theme list from $script:OhMyPoshGitHubThemesUrl"
    try {
        $response = Invoke-RestMethod -Uri $script:OhMyPoshGitHubThemesUrl -Method Get -ErrorAction Stop
    }
    catch {
        $message = "Failed to fetch themes from GitHub: $($_.Exception.Message)"
        if ("$($_.ErrorDetails.Message) $($_.Exception.Message)" -match 'rate limit') {
            $message = 'GitHub API rate limit reached (60 requests per hour without authentication).'
        }
        if ($cache) {
            Write-Warning "$message Using the theme list cached at $cachedAt."
            return $cache.Themes | ForEach-Object { ConvertTo-PoshifyOnlineTheme $_ }
        }
        Write-Error -Message "$message Try again later." -Exception $_.Exception -Category ConnectionError
        return
    }

    $entries = @($response | Where-Object { $_.name -match $script:ThemeFilePattern } |
            Select-Object -Property name, size, download_url, sha)

    try {
        $json = ConvertTo-Json -Depth 3 -InputObject ([ordered]@{
                CachedAt = [datetime]::UtcNow.ToString('o')
                Themes   = $entries
            })
        Write-PoshifyTextFile -Path $cacheFile -Text $json
    }
    catch {
        Write-Verbose "Could not write theme cache: $($_.Exception.Message)"
    }

    $entries | ForEach-Object { ConvertTo-PoshifyOnlineTheme $_ }
}

# Downloads to a temporary name first so a failed download never leaves a broken theme behind
function Save-PoshifyThemeFile {
    param(
        $Theme,
        [string]$Path
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $downloadPath = "$Path.download"
    try {
        Invoke-WebRequest -Uri $Theme.DownloadUrl -OutFile $downloadPath -UseBasicParsing -ErrorAction Stop
        Move-Item -LiteralPath $downloadPath -Destination $Path -Force
        $true
    }
    catch {
        Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
        Write-Error -Message "Failed to download theme '$($Theme.Name)': $($_.Exception.Message)" -Exception $_.Exception -Category ConnectionError
        $false
    }
}

# Git blob hash of a file, comparable to the 'sha' GitHub reports for repository files
function Get-PoshifyGitBlobSha {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $sha1.TransformBlock($header, 0, $header.Length, $null, 0) | Out-Null
        $sha1.TransformFinalBlock($bytes, 0, $bytes.Length) | Out-Null
        -join ($sha1.Hash | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        $sha1.Dispose()
    }
}

function Get-PoshifyFavoriteList {
    $file = Get-PoshifyFavoritesFile
    if (-not (Test-Path -LiteralPath $file)) {
        return
    }

    try {
        $parsed = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Ignoring unreadable favorites file: $file"
        return
    }
    $parsed | Where-Object { $_ -is [string] -and $_ }
}

function Save-PoshifyFavoriteList {
    param([string[]]$Name)

    $sorted = @($Name | Sort-Object -Unique)
    Write-PoshifyTextFile -Path (Get-PoshifyFavoritesFile) -Text (ConvertTo-Json -InputObject $sorted)
}

# Reads a text file keeping its encoding, so rewriting a profile never mangles non-ASCII text.
# Windows PowerShell treats BOM-less files as ANSI, so non-UTF-8 content falls back to that.
function Read-PoshifyTextFile {
    param([string]$Path)

    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $reader = New-Object System.IO.StreamReader($Path, $strictUtf8, $true)
    try {
        $text = $reader.ReadToEnd()
        $encoding = $reader.CurrentEncoding
    }
    catch [System.Text.DecoderFallbackException] {
        $encoding = [System.Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
        $text = [System.IO.File]::ReadAllText($Path, $encoding)
    }
    finally {
        $reader.Dispose()
    }

    [PSCustomObject]@{ Text = $text; Encoding = $encoding }
}

function Write-PoshifyTextFile {
    param(
        [string]$Path,
        [string]$Text,
        # UTF-8 with BOM is read correctly by both Windows PowerShell and PowerShell 7
        [System.Text.Encoding]$Encoding = (New-Object System.Text.UTF8Encoding($true))
    )

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, $Encoding)
}

#region Theme resolution
# These two functions are also copied into the generated init.ps1, which runs at shell startup
# without loading the module, so they must not call anything else in this module.

# Theme set by the nearest .poshify (or .ompconfig) file at or above a folder. Returns nothing when
# no folder file applies; otherwise Marker and Value, plus Path when the theme can be used or
# Message explaining why not.
function Resolve-PoshifyLocationTheme {
    param(
        [string]$Path,
        [string]$PoshifyHome
    )

    $themeDirs = @($PoshifyHome, $env:POSH_THEMES_PATH) | Where-Object { $_ }
    $directory = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    while ($directory) {
        foreach ($markerName in '.poshify', '.ompconfig') {
            $marker = Join-Path $directory.FullName $markerName
            if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
                continue
            }

            $value = Get-Content -LiteralPath $marker -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and -not $_.StartsWith('#') } |
                Select-Object -First 1
            $result = [PSCustomObject]@{ Marker = $marker; Value = $value; Status = $null; Path = $null; File = $null; Message = $null }
            if (-not $value) {
                $result.Status = 'Empty'
                $result.Message = "$marker is empty."
                return $result
            }

            # A theme name, looked up in the theme folders
            if ($value -notmatch '[\\/]') {
                $fileNames = if ($value -match '\.omp\.(json|ya?ml|toml)$') { , $value } else { 'json', 'yaml', 'yml', 'toml' | ForEach-Object { "$value.omp.$_" } }
                foreach ($themeDir in $themeDirs) {
                    foreach ($fileName in $fileNames) {
                        $candidate = Join-Path $themeDir $fileName
                        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                            $result.Status = 'Active'
                            $result.Path = $candidate
                            $result.File = $candidate
                            return $result
                        }
                    }
                }
            }

            # A path to a theme file, relative to the folder file
            $file = if ([IO.Path]::IsPathRooted($value)) { $value } else { Join-Path $directory.FullName $value }
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                $result.Status = 'NotFound'
                $result.Message = "theme '$value' from $marker was not found. Install it with: Poshify theme install $value"
                return $result
            }
            $file = (Resolve-Path -LiteralPath $file).ProviderPath
            $result.File = $file

            # Theme files can run commands, so files outside the theme folders must be trusted first
            $inThemeDir = $themeDirs | Where-Object { $file.StartsWith((Join-Path $_ ''), [StringComparison]::OrdinalIgnoreCase) }
            $trustFile = Join-Path $PoshifyHome 'trusted'
            $trusted = $inThemeDir -or ((Test-Path -LiteralPath $trustFile) -and
                (Get-Content -LiteralPath $trustFile) -contains "$((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash) $file")
            if ($trusted) {
                $result.Status = 'Active'
                $result.Path = $file
            }
            else {
                $result.Status = 'Untrusted'
                $result.Message = "$marker uses a theme file that isn't trusted yet ($file). Theme files can run commands; if you trust it, run 'Poshify folder trust' in $($directory.FullName)."
            }
            return $result
        }
        $directory = $directory.Parent
    }
}

# Theme file to use where no folder file applies: the selected theme, or a random one when the
# selection is 'random' or 'random:favorites'
function Select-PoshifyDefaultThemeFile {
    param([string]$PoshifyHome)

    $selection = Get-Content -LiteralPath (Join-Path $PoshifyHome 'current') -TotalCount 1 -ErrorAction SilentlyContinue
    if (-not $selection) {
        return
    }
    if ($selection -notlike 'random*') {
        if (Test-Path -LiteralPath $selection -PathType Leaf) { $selection }
        return
    }

    $themes = foreach ($themeDir in @($PoshifyHome, $env:POSH_THEMES_PATH)) {
        if ($themeDir) {
            Get-ChildItem -LiteralPath $themeDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.omp\.(json|ya?ml|toml)$' }
        }
    }
    if ($selection -eq 'random:favorites') {
        $favorites = $null
        try {
            $favorites = Get-Content -LiteralPath (Join-Path $PoshifyHome '.favorites.json') -Raw -ErrorAction Stop | ConvertFrom-Json
        }
        catch {
            $favorites = $null
        }
        $favorites = @($favorites | ForEach-Object { $_ })
        $themes = $themes | Where-Object { ($_.Name -replace '\.omp\.(json|ya?ml|toml)$', '') -in $favorites }
    }
    $themes | Get-Random | ForEach-Object { $_.FullName }
}

#endregion

function Get-PoshifyInitScriptPath {
    Join-Path $script:PoshifyHome 'init.ps1'
}

# Script loaded by the profile block at startup. It picks the theme for the current folder and
# re-initializes oh-my-posh whenever a prompt is drawn in a folder that needs a different theme.
function Get-PoshifyInitScript {
    $template = @'
# Generated by Poshify. Don't edit this file: Poshify rewrites it.
# It is loaded by the Poshify block in your PowerShell profile.
if (-not (Get-Command -Name oh-my-posh -CommandType Application -ErrorAction SilentlyContinue)) {
    return
}

function global:Resolve-PoshifyLocationTheme {
__RESOLVE__
}

function global:Select-PoshifyDefaultThemeFile {
__DEFAULT__
}

$global:_poshifyHome = '__HOME__'
$global:_poshifyActiveConfig = $null
$global:_poshifyLastLocation = $null
$global:_poshifyWarned = @{}
$global:_poshifyDefaultConfig = Select-PoshifyDefaultThemeFile -PoshifyHome $global:_poshifyHome

$global:_poshifyUpdate = {
    $location = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
    if ($location -eq $global:_poshifyLastLocation) {
        return
    }
    $global:_poshifyLastLocation = $location

    $config = $global:_poshifyDefaultConfig
    $folder = Resolve-PoshifyLocationTheme -Path $location -PoshifyHome $global:_poshifyHome
    if ($folder.Path) {
        $config = $folder.Path
    }
    elseif ($folder.Message -and -not $global:_poshifyWarned.ContainsKey($folder.Marker)) {
        $global:_poshifyWarned[$folder.Marker] = $true
        Write-Warning "Poshify: $($folder.Message)"
    }

    if (-not $config -or $config -eq $global:_poshifyActiveConfig) {
        return
    }
    $global:_poshifyActiveConfig = $config

    $init = (oh-my-posh init pwsh --config $config) -join [Environment]::NewLine
    if (-not $init.Trim()) {
        return
    }
    Invoke-Expression $init

    # oh-my-posh installs its own prompt; keep it as the base and wrap it again
    $prompt = (Get-Item -Path Function:\prompt).ScriptBlock
    if ($prompt.ToString() -ne $global:_poshifyPrompt.ToString()) {
        $global:_poshifyBasePrompt = $prompt
    }
    Set-Item -Path Function:global:prompt -Value $global:_poshifyPrompt
}

$global:_poshifyPrompt = {
    # Pass the last command's status through to oh-my-posh, which reads this variable when set
    $global:NVS_ORIGINAL_LASTEXECUTIONSTATUS = $?
    $exitCode = $global:LASTEXITCODE
    & $global:_poshifyUpdate
    $global:LASTEXITCODE = $exitCode
    if ($global:_poshifyBasePrompt) {
        & $global:_poshifyBasePrompt
    }
    else {
        "PS $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($NestedPromptLevel + 1)) "
    }
}

& $global:_poshifyUpdate
'@

    $template.Replace('__HOME__', ($script:PoshifyHome -replace "'", "''")).
        Replace('__RESOLVE__', ${function:Resolve-PoshifyLocationTheme}.ToString().Trim()).
        Replace('__DEFAULT__', ${function:Select-PoshifyDefaultThemeFile}.ToString().Trim()).
        Replace("`r`n", "`n")
}

function Write-PoshifyInitScript {
    $path = Get-PoshifyInitScriptPath
    $content = Get-PoshifyInitScript
    if ((Test-Path -LiteralPath $path) -and ((Read-PoshifyTextFile -Path $path).Text -ceq $content)) {
        return
    }
    Write-PoshifyTextFile -Path $path -Text $content
}

# Loads (or reloads) the init script into this session, applying the theme for the current folder
function Invoke-PoshifyInitScript {
    $path = Get-PoshifyInitScriptPath
    if (Test-Path -LiteralPath $path) {
        . $path
    }
}

# Undoes the init script in this session and restores PowerShell's default prompt
function Clear-PoshifySessionPrompt {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Session state shared with the generated init script')]
    param()

    Get-Module -Name oh-my-posh-core | Remove-Module -Force

    if ($global:_poshifyPrompt) {
        Set-Item -Path Function:global:prompt -Value { "PS $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($NestedPromptLevel + 1)) " }
    }
    Remove-Variable -Scope Global -ErrorAction SilentlyContinue -Name @(
        '_poshifyPrompt', '_poshifyUpdate', '_poshifyBasePrompt', '_poshifyHome', '_poshifyActiveConfig',
        '_poshifyLastLocation', '_poshifyWarned', '_poshifyDefaultConfig', 'NVS_ORIGINAL_LASTEXECUTIONSTATUS'
    )
    Remove-Item -Path Function:global:Resolve-PoshifyLocationTheme, Function:global:Select-PoshifyDefaultThemeFile -ErrorAction SilentlyContinue
}

function Get-PoshifyProfileBlock {
    param([string]$NewLine)

    $initScript = (Get-PoshifyInitScriptPath) -replace "'", "''"
    @(
        $script:ProfileBlockStart
        '# Managed by Poshify - use Set-PoshifyTheme / Reset-PoshifyTheme instead of editing this block.'
        "`$poshifyInit = '$initScript'"
        'if (Test-Path -LiteralPath $poshifyInit) { . $poshifyInit }'
        'Remove-Variable -Name poshifyInit -ErrorAction SilentlyContinue'
        $script:ProfileBlockEnd
    ) -join $NewLine
}

# Returns profile text with the Poshify block replaced in place (or appended), or removed with -Remove.
# Also cleans up the unmarked blocks written by Poshify 1.0.x and 2.0.0, including the partial
# leftovers that their broken cleanup regex used to leave behind.
function Merge-PoshifyProfileBlock {
    param(
        [AllowEmptyString()]
        [string]$Content,
        [switch]$Remove
    )

    $newLine = if ($Content -match "`r`n") { "`r`n" } elseif ($Content -match "`n") { "`n" } else { [Environment]::NewLine }
    $markedPattern = '(?ms)^{0}[ \t]*\r?$.*?^{1}[ \t]*(\r?\n)?' -f [regex]::Escape($script:ProfileBlockStart), [regex]::Escape($script:ProfileBlockEnd)
    $legacyPattern = '(?m)^(?:# Poshify Theme - Generated by Poshify Module\r?\n)?# Theme: .*\r?\n# Generated on: .*\r?\n(?:[ \t]*\r?\n)*oh-my-posh init pwsh --config ".*" \| Invoke-Expression[ \t]*(?:\r?\n)?'

    $result = $Content -replace $legacyPattern, ''

    if ($Remove) {
        $result = $result -replace $markedPattern, ''
    }
    else {
        $block = (Get-PoshifyProfileBlock -NewLine $newLine) + $newLine
        $marked = [regex]::new($markedPattern)
        $existing = $marked.Match($result)
        if ($existing.Success) {
            # Keep the block where the user put it; drop any duplicates after it
            $rest = $marked.Replace($result.Substring($existing.Index + $existing.Length), '')
            $result = $result.Substring(0, $existing.Index) + $block + $rest
        }
        else {
            $result = $result.TrimEnd()
            $result = if ($result) { $result + $newLine + $newLine + $block } else { $block }
        }
    }

    if ($result -cne $Content) {
        $result = $result.TrimEnd()
        if ($result) { $result += $newLine }
    }
    $result
}

# Adds, refreshes or removes the Poshify block in every managed profile
function Write-PoshifyProfileBlock {
    param([switch]$Remove)

    if (-not $Remove) {
        Write-PoshifyInitScript
    }

    foreach ($target in Get-PoshifyProfileTarget) {
        $exists = Test-Path -LiteralPath $target.Path
        if ($Remove -and -not $exists) {
            continue
        }

        $original = if ($exists) { Read-PoshifyTextFile -Path $target.Path }
        $content = Merge-PoshifyProfileBlock -Content $original.Text -Remove:$Remove
        if ($content -ceq $original.Text) {
            continue
        }

        if ($Remove) {
            Write-PoshifyTextFile -Path $target.Path -Text $content -Encoding $original.Encoding
            Write-Verbose "Removed Poshify block from $($target.Path)"
            continue
        }

        $policy = Get-PoshifyExecutionPolicy -Edition $target.Edition
        $blocked = Test-PoshifyPolicyBlocksProfile $policy
        if ($blocked -and -not $exists -and -not $target.IsCurrent) {
            # Creating a profile that can't run would only add an error to every new session
            Write-Verbose "Skipping the $(Get-PoshifyEditionName $target.Edition) profile: its execution policy is $policy"
            continue
        }

        if ($original) {
            Write-PoshifyTextFile -Path $target.Path -Text $content -Encoding $original.Encoding
        }
        else {
            Write-PoshifyTextFile -Path $target.Path -Text $content
        }
        Write-Verbose "Updated Poshify block in $($target.Path)"

        if ($blocked) {
            Write-Warning (Get-PoshifyPolicyAdvice -Edition $target.Edition -Policy $policy)
        }
    }
}

# How to install oh-my-posh on this platform, or nothing if no supported installer is available
function Get-PoshifyOhMyPoshInstaller {
    if (Test-PoshifyWindows) {
        if (Get-Command -Name winget -ErrorAction SilentlyContinue) {
            [PSCustomObject]@{ Description = 'winget'; FilePath = 'winget'; ArgumentList = @('install', 'JanDeDobbeleer.OhMyPosh', '--source', 'winget', '--scope', 'user') }
        }
    }
    elseif ($IsMacOS -and (Get-Command -Name brew -ErrorAction SilentlyContinue)) {
        [PSCustomObject]@{ Description = 'Homebrew'; FilePath = 'brew'; ArgumentList = @('install', 'jandedobbeleer/oh-my-posh/oh-my-posh') }
    }
    elseif ((Get-Command -Name curl -ErrorAction SilentlyContinue) -and (Get-Command -Name bash -ErrorAction SilentlyContinue)) {
        [PSCustomObject]@{ Description = 'the official install script'; FilePath = 'bash'; ArgumentList = @('-c', 'curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin') }
    }
}

function Invoke-PoshifyInstaller {
    param($Installer)
    & $Installer.FilePath @($Installer.ArgumentList)
}

# Picks up PATH entries added by an installer without discarding this session's own entries
function Sync-PoshifySessionPath {
    $separator = [IO.Path]::PathSeparator
    $entries = if (Test-PoshifyWindows) {
        foreach ($scope in 'Machine', 'User') {
            [Environment]::GetEnvironmentVariable('Path', $scope) -split $separator
        }
    }
    else {
        Join-Path $HOME '.local/bin'
        '/opt/homebrew/bin'
        '/usr/local/bin'
    }

    $current = $env:PATH -split $separator
    $missing = $entries | Where-Object { $_ -and $_ -notin $current -and (Test-Path -LiteralPath $_) }
    if ($missing) {
        $env:PATH = (@($current) + @($missing)) -join $separator
    }
}

# Families of installed Nerd Fonts, e.g. 'MesloLGM Nerd Font'
function Get-PoshifyNerdFont {
    $names = if (Test-PoshifyWindows) {
        foreach ($key in 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts', 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts') {
            $fonts = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            if ($fonts) { $fonts.PSObject.Properties.Name }
        }
    }
    elseif ($IsMacOS) {
        Get-ChildItem -Path (Join-Path $HOME 'Library/Fonts'), '/Library/Fonts' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName }
    }
    elseif (Get-Command -Name fc-list -ErrorAction SilentlyContinue) {
        fc-list : family
    }

    $names | ForEach-Object { if ($_ -match '^(.*?Nerd ?Font)') { $Matches[1] } } | Sort-Object -Unique
}

function Test-PoshifyNerdFontFace {
    param([string]$Face)
    $Face -match 'Nerd ?Font|\bNF[MP]?\b'
}

function Get-PoshifyTerminalSettingsPath {
    if (-not (Test-PoshifyWindows)) {
        return
    }
    @(
        Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'
        Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json'
    ) | Where-Object { Test-Path -LiteralPath $_ }
}

function Read-PoshifyTerminalConfig {
    param([string]$Path)

    $text = [IO.File]::ReadAllText($Path)
    $parameters = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        $parameters.DateKind = 'String'
    }
    [PSCustomObject]@{
        Text     = $text
        Settings = $text | ConvertFrom-Json @parameters
    }
}

# Default font face of a Windows Terminal settings file
function Get-PoshifyTerminalFont {
    param([string]$Path)

    $defaults = (Read-PoshifyTerminalConfig -Path $Path).Settings.profiles.defaults
    if ($defaults.font.face) { $defaults.font.face }
    elseif ($defaults.fontFace) { $defaults.fontFace }
    else { 'Cascadia Mono' }
}

# Sets the default font of a Windows Terminal settings file, keeping a backup next to it.
# Returns $false (with a warning) when the file can't be rewritten safely.
function Write-PoshifyTerminalFont {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Face
    )

    $manual = "Set the font manually in Windows Terminal: Settings > Defaults > Appearance > Font face > '$Face'."
    if ($PSVersionTable.PSEdition -ne 'Core') {
        Write-Warning "Changing Windows Terminal settings needs PowerShell 7. $manual"
        return $false
    }

    $file = Read-PoshifyTerminalConfig -Path $Path
    if ($file.Text -match '(?m)^\s*//|/\*') {
        Write-Warning "Windows Terminal's settings contain comments that would be lost. $manual"
        return $false
    }

    $profiles = $file.Settings.profiles
    if ($null -eq $profiles -or $profiles -is [array]) {
        Write-Warning "Windows Terminal's settings use an unsupported layout. $manual"
        return $false
    }
    if ($null -eq $profiles.defaults) {
        $profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([PSCustomObject]@{})
    }
    $defaults = $profiles.defaults
    if ($null -eq $defaults.font) {
        $defaults | Add-Member -NotePropertyName font -NotePropertyValue ([PSCustomObject]@{})
    }
    if ($defaults.font.PSObject.Properties['face']) {
        $defaults.font.face = $Face
    }
    else {
        $defaults.font | Add-Member -NotePropertyName face -NotePropertyValue $Face
    }
    if ($defaults.PSObject.Properties['fontFace']) {
        $defaults.PSObject.Properties.Remove('fontFace')
    }

    Copy-Item -LiteralPath $Path -Destination "$Path.poshify-backup" -Force
    $json = $file.Settings | ConvertTo-Json -Depth 64
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))

    $overrides = @($profiles.list | Where-Object { $_.font.face -and -not (Test-PoshifyNerdFontFace $_.font.face) } | ForEach-Object { $_.name })
    if ($overrides) {
        Write-Warning "These Windows Terminal profiles set their own font and won't use '$Face': $($overrides -join ', ')"
    }
    $true
}

#endregion

<#
.SYNOPSIS
    Gets available local oh-my-posh themes

.DESCRIPTION
    Lists oh-my-posh theme files downloaded by Poshify (~/.poshthemes) and the themes bundled
    with oh-my-posh ($env:POSH_THEMES_PATH). A theme downloaded by Poshify takes precedence
    over a bundled theme with the same name.

    Each theme also has SizeKB, LastModified and Path properties; use Format-List * to see them.

.PARAMETER Name
    Theme name to look up. An exact match is returned if one exists; otherwise the name is
    treated as a wildcard pattern, or as a substring if it contains no wildcard characters.

.EXAMPLE
    Get-PoshifyTheme
    Lists all available local themes

.EXAMPLE
    Get-PoshifyTheme -Name "agnoster"
    Gets the agnoster theme

.EXAMPLE
    Get-PoshifyTheme | Where-Object Favorite
    Lists local themes marked as favorites

.OUTPUTS
    Poshify.Theme
#>
function Get-PoshifyTheme {
    [CmdletBinding()]
    [OutputType('Poshify.Theme')]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )

    $currentPath = Get-PoshifyCurrentThemePath
    $favorites = @(Get-PoshifyFavoriteList)
    $seen = @{}

    $themes = foreach ($source in Get-PoshifyThemeSource) {
        if (-not (Test-Path -LiteralPath $source.Path)) {
            Write-Verbose "Theme directory not found: $($source.Path)"
            continue
        }

        Get-ChildItem -LiteralPath $source.Path -File |
            Where-Object { $_.Name -match $script:ThemeFilePattern } |
            ForEach-Object {
                $themeName = Get-PoshifyThemeName $_.Name
                if ($seen.ContainsKey($themeName)) { return }
                $seen[$themeName] = $true
                ConvertTo-PoshifyThemeObject -File $_ -Source $source.Name -CurrentPath $currentPath -Favorites $favorites
            }
    }
    $themes = @($themes | Sort-Object -Property Name)

    if (-not $Name) {
        return $themes
    }

    $found = Select-PoshifyThemeMatch -Theme $themes -Name $Name
    if (-not $found) {
        Write-Error -Message "Theme '$Name' not found locally. Use Find-PoshifyTheme to search online." -Category ObjectNotFound -TargetObject $Name
        return
    }
    $found
}

<#
.SYNOPSIS
    Gets the oh-my-posh theme in use for a folder

.DESCRIPTION
    Returns the theme Poshify uses in the current folder (or -Path): the theme from the nearest
    .poshify file, otherwise your default theme from Set-PoshifyTheme. The SelectedBy property
    says which. Returns nothing if no theme applies.

    A theme file outside the Poshify and oh-my-posh theme folders is reported with Source 'Custom'.

.PARAMETER Path
    Folder to check instead of the current one.

.EXAMPLE
    Get-PoshifyCurrentTheme
    Shows the theme for the current folder

.EXAMPLE
    Get-PoshifyCurrentTheme | Select-Object Name, SelectedBy
    Shows the theme and why it applies

.OUTPUTS
    Poshify.Theme
#>
function Get-PoshifyCurrentTheme {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Session state shared with the generated init script')]
    [CmdletBinding()]
    [OutputType('Poshify.Theme')]
    param(
        [string]$Path
    )

    $location = if ($Path) { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath }
    else { $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath }

    $folder = Resolve-PoshifyLocationTheme -Path $location -PoshifyHome $script:PoshifyHome
    if ($folder.Path) {
        $themePath = $folder.Path
        $selectedBy = "Folder ($($folder.Marker))"
    }
    else {
        if ($folder.Message) {
            Write-Warning $folder.Message
        }

        $selection = Get-PoshifyCurrentThemePath
        if (-not $selection) {
            Write-Verbose 'No theme is selected. Use Set-PoshifyTheme to select one.'
            return
        }
        if ($selection -like 'random*') {
            # The init script picks the random theme when a session starts
            $themePath = $global:_poshifyDefaultConfig
            if (-not $themePath) {
                Write-Verbose 'A random theme is picked when each session starts.'
                return
            }
            $selectedBy = if ($selection -eq 'random:favorites') { 'Random favorite (this session)' } else { 'Random (this session)' }
        }
        else {
            $themePath = $selection
            $selectedBy = 'Default'
        }
    }

    $theme = Get-PoshifyTheme | Where-Object { $_.Path -eq $themePath }
    if (-not $theme) {
        $file = Get-Item -LiteralPath $themePath -ErrorAction SilentlyContinue
        if (-not $file) {
            Write-Warning "The selected theme file no longer exists: $themePath"
            return
        }
        $theme = ConvertTo-PoshifyThemeObject -File $file -Source 'Custom' -CurrentPath (Get-PoshifyCurrentThemePath) -Favorites @(Get-PoshifyFavoriteList)
    }
    $theme | Add-Member -NotePropertyName SelectedBy -NotePropertyValue $selectedBy -PassThru
}

<#
.SYNOPSIS
    Finds oh-my-posh themes available online

.DESCRIPTION
    Lists the oh-my-posh themes available in the official GitHub repository.
    The list is cached for an hour to stay well within GitHub's limit of 60 unauthenticated
    API requests per hour. If GitHub can't be reached, an older cached list is used.

.PARAMETER Name
    Theme name to search for. Exact match first, then wildcard or substring match.

.PARAMETER ForceRefresh
    Ignore the cache and fetch the list from GitHub.

.EXAMPLE
    Find-PoshifyTheme
    Lists all available online themes

.EXAMPLE
    Find-PoshifyTheme -Name "agnoster"
    Searches for themes containing "agnoster" in their name

.EXAMPLE
    Find-PoshifyTheme -Name "power*" | Install-PoshifyTheme
    Installs every theme whose name starts with "power"

.OUTPUTS
    Poshify.OnlineTheme
#>
function Find-PoshifyTheme {
    [CmdletBinding()]
    [OutputType('Poshify.OnlineTheme')]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [switch]$ForceRefresh
    )

    $themes = @(Get-PoshifyOnlineThemeList -ForceRefresh:$ForceRefresh)

    if (-not $Name) {
        return $themes
    }

    $found = Select-PoshifyThemeMatch -Theme $themes -Name $Name
    if (-not $found) {
        if ($themes.Count -gt 0) {
            Write-Warning "No online themes found matching '$Name'"
        }
        return
    }
    $found
}

<#
.SYNOPSIS
    Installs an oh-my-posh theme

.DESCRIPTION
    Downloads a theme from the official oh-my-posh repository into ~/.poshthemes.
    If the theme is already available locally (including themes bundled with oh-my-posh),
    the local theme is returned instead unless -Force is used.

.PARAMETER Name
    The name of the theme to install. Must match exactly one online theme.

.PARAMETER Force
    Download the theme even if it is already available locally, overwriting any previous download.

.EXAMPLE
    Install-PoshifyTheme -Name "agnoster"
    Downloads and installs the agnoster theme

.EXAMPLE
    Install-PoshifyTheme -Name "powerlevel10k_rainbow" -Force
    Downloads the theme again, replacing the local copy

.OUTPUTS
    Poshify.Theme
#>
function Install-PoshifyTheme {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Poshify.Theme')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [string]$Name,

        [switch]$Force
    )

    begin {
        $onlineThemes = $null
    }

    process {
        if (-not $Force) {
            $existing = @(Get-PoshifyTheme | Where-Object { $_.Name -eq $Name })
            if ($existing.Count -gt 0) {
                Write-Warning "Theme '$Name' is already available locally ($($existing[0].Source)). Use -Force to download it again."
                return $existing[0]
            }
        }

        # Fetch the online list once per pipeline, not once per piped theme
        if ($null -eq $onlineThemes) {
            $onlineThemes = @(Get-PoshifyOnlineThemeList)
        }
        if ($onlineThemes.Count -eq 0) {
            return
        }

        $theme = Resolve-PoshifySingleTheme -Match (Select-PoshifyThemeMatch -Theme $onlineThemes -Name $Name) -Name $Name -Location 'online'
        if (-not $theme) {
            return
        }

        $themePath = Join-Path $script:PoshifyHome $theme.FileName
        if (-not $PSCmdlet.ShouldProcess($themePath, "Download theme '$($theme.Name)'")) {
            return
        }

        if (Save-PoshifyThemeFile -Theme $theme -Path $themePath) {
            Write-Verbose "Theme '$($theme.Name)' installed to $themePath"
            Get-PoshifyTheme | Where-Object { $_.Path -eq $themePath }
        }
    }
}

<#
.SYNOPSIS
    Updates themes installed by Poshify

.DESCRIPTION
    Compares themes downloaded by Poshify with the official oh-my-posh repository and downloads
    the ones that changed. Themes bundled with oh-my-posh are updated with oh-my-posh itself.

.PARAMETER Name
    Name of the theme to update. Accepts pipeline input from Get-PoshifyTheme.

.PARAMETER All
    Update every theme installed by Poshify.

.EXAMPLE
    Update-PoshifyTheme -Name "agnoster"
    Updates the agnoster theme if it changed online

.EXAMPLE
    Update-PoshifyTheme -All
    Updates all installed themes

.OUTPUTS
    Poshify.Theme for each theme that was updated
#>
function Update-PoshifyTheme {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    [OutputType('Poshify.Theme')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByName', ValueFromPipelineByPropertyName = $true)]
        [string[]]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [switch]$All
    )

    begin {
        $onlineThemes = $null
    }

    process {
        $installed = @(Get-PoshifyTheme | Where-Object { $_.Source -eq 'Poshify' })
        $targets = if ($All) {
            $installed
        }
        else {
            foreach ($themeName in $Name) {
                Resolve-PoshifySingleTheme -Match (Select-PoshifyThemeMatch -Theme $installed -Name $themeName) -Name $themeName `
                    -Location 'among themes installed by Poshify'
            }
        }
        if (-not $targets) {
            Write-Verbose 'No themes to update'
            return
        }

        if ($null -eq $onlineThemes) {
            $onlineThemes = @(Get-PoshifyOnlineThemeList -ForceRefresh)
        }
        if ($onlineThemes.Count -eq 0) {
            return
        }

        foreach ($theme in $targets) {
            $fileName = Split-Path -Path $theme.Path -Leaf
            $remote = $onlineThemes | Where-Object { $_.FileName -eq $fileName } | Select-Object -First 1
            if (-not $remote) {
                Write-Warning "Theme '$($theme.Name)' is no longer in the oh-my-posh repository; keeping the local copy."
                continue
            }

            if ($remote.Sha -and (Get-PoshifyGitBlobSha -Path $theme.Path) -eq $remote.Sha) {
                Write-Verbose "Theme '$($theme.Name)' is up to date"
                continue
            }

            if ($PSCmdlet.ShouldProcess($theme.Path, "Update theme '$($theme.Name)'")) {
                if (Save-PoshifyThemeFile -Theme $remote -Path $theme.Path) {
                    Get-PoshifyTheme | Where-Object { $_.Path -eq $theme.Path }
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Removes a theme installed by Poshify

.DESCRIPTION
    Deletes a theme file downloaded by Poshify. Themes bundled with oh-my-posh can't be removed.
    The name must match exactly. The current theme is only removed with -Force.

.PARAMETER Name
    Exact name of the theme to remove. Accepts pipeline input from Get-PoshifyTheme.

.PARAMETER Force
    Remove the theme even if it is the current theme.

.EXAMPLE
    Remove-PoshifyTheme -Name "agnoster"
    Removes the agnoster theme

.EXAMPLE
    Get-PoshifyTheme | Where-Object { $_.Source -eq 'Poshify' -and -not $_.Favorite } | Remove-PoshifyTheme -WhatIf
    Shows which downloaded themes that aren't favorites would be removed

.OUTPUTS
    None
#>
function Remove-PoshifyTheme {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [string]$Name,

        [switch]$Force
    )

    process {
        $theme = Get-PoshifyTheme | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if (-not $theme) {
            Write-Error -Message "Theme '$Name' not found locally. Remove-PoshifyTheme needs the exact theme name." -Category ObjectNotFound -TargetObject $Name
            return
        }

        if ($theme.Source -ne 'Poshify') {
            Write-Error -Message "Theme '$Name' is bundled with oh-my-posh and can't be removed by Poshify." -Category InvalidOperation -TargetObject $Name
            return
        }

        if ($theme.Current -and -not $Force) {
            Write-Error -Message "Theme '$Name' is the current theme. Switch to another theme first, or use -Force." -Category InvalidOperation -TargetObject $Name
            return
        }

        if ($PSCmdlet.ShouldProcess($theme.Path, "Remove theme '$Name'")) {
            Remove-Item -LiteralPath $theme.Path -Force
            if ($theme.Current) {
                Write-Warning "Removed the current theme '$Name'. New sessions will use the default prompt until you set another theme."
            }
        }
    }
}

<#
.SYNOPSIS
    Sets the current oh-my-posh theme

.DESCRIPTION
    Selects a theme, makes sure your PowerShell profiles contain the Poshify block that loads the
    selected theme at startup, and applies the theme to the current session.

    On Windows, both the PowerShell 7 and Windows PowerShell profiles are set up, so the theme
    appears in both. A profile that doesn't exist yet is only created for the other edition when
    its execution policy allows it to run; otherwise you get a warning explaining how to allow it.

    The profile block is written once and kept where it is; switching themes afterwards only
    changes the selection stored in ~/.poshthemes/current.

    This is your default theme. Folders with a .poshify file (see Set-PoshifyFolderTheme) use
    their own theme instead.

.PARAMETER Name
    The name of a local theme (see Get-PoshifyTheme). If no local theme matches, a theme with
    exactly this name in the oh-my-posh repository is downloaded first.

.PARAMETER ThemePath
    Direct path to a theme file. Accepts pipeline input from Get-PoshifyTheme.

.PARAMETER Random
    Use a different random local theme in every new session.

.PARAMETER FromFavorites
    With -Random, only pick from favorite themes.

.PARAMETER NoApply
    Only update the selection and profile; leave the prompt of the current session unchanged.

.EXAMPLE
    Set-PoshifyTheme -Name "agnoster"
    Sets the agnoster theme as the current prompt

.EXAMPLE
    Set-PoshifyTheme -ThemePath "C:\path\to\custom.omp.json"
    Sets a custom theme file as the current prompt

.EXAMPLE
    Set-PoshifyTheme -Random -FromFavorites
    Uses a random favorite theme in every new session

.EXAMPLE
    Get-PoshifyRandomTheme | Set-PoshifyTheme
    Switches to a random theme once and keeps it

.OUTPUTS
    None
#>
function Set-PoshifyTheme {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByName', Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByPath', ValueFromPipelineByPropertyName = $true)]
        [Alias('Path', 'FullName')]
        [string]$ThemePath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Random')]
        [switch]$Random,

        [Parameter(ParameterSetName = 'Random')]
        [switch]$FromFavorites,

        [switch]$NoApply
    )

    process {
        if (-not (Get-OhMyPoshCommand)) {
            Write-Error -Message "oh-my-posh is not installed or not in PATH. Run 'Poshify setup' to install it, or see $script:OhMyPoshInstallUrl" -Category NotInstalled
            return
        }

        if ($Random) {
            # Fails with a helpful error when there is nothing to pick from
            if (-not (Get-PoshifyRandomTheme -FromFavorites:$FromFavorites)) {
                return
            }
            $selection = if ($FromFavorites) { 'random:favorites' } else { 'random' }
            $description = if ($FromFavorites) { 'a random favorite theme in each session' } else { 'a random theme in each session' }
        }
        else {
            $theme = Resolve-PoshifyThemeFile -Name $Name -ThemePath $ThemePath -IncludeOnline
            if (-not $theme) {
                return
            }

            if (-not $theme.Path) {
                # Only available online: download it first
                Write-Verbose "Theme '$($theme.Name)' is not installed; downloading it"
                $theme = Install-PoshifyTheme -Name $theme.Name
                if (-not $theme) {
                    return
                }
            }
            $selection = $theme.Path
            $description = "'$($theme.Name)'"
        }

        $profilePaths = (Get-PoshifyProfileTarget | ForEach-Object { $_.Path }) -join ', '
        if (-not $PSCmdlet.ShouldProcess($profilePaths, "Set oh-my-posh theme to $description")) {
            return
        }

        Write-PoshifyTextFile -Path (Get-PoshifyCurrentThemeFile) -Text $selection
        Write-PoshifyProfileBlock

        if (-not $NoApply) {
            Invoke-PoshifyInitScript
        }

        Write-Verbose "Theme set to $description"
    }
}

<#
.SYNOPSIS
    Resets the PowerShell prompt to default

.DESCRIPTION
    Removes the Poshify block from your PowerShell profiles, clears the theme selection, and
    unloads oh-my-posh from the current session. Any oh-my-posh setup in your profile that
    Poshify did not create is left untouched and reported as a warning.

.EXAMPLE
    Reset-PoshifyTheme
    Resets the prompt to default PowerShell appearance

.OUTPUTS
    None
#>
function Reset-PoshifyTheme {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $profilePaths = @(Get-PoshifyProfileTarget | ForEach-Object { $_.Path } | Where-Object { Test-Path -LiteralPath $_ })
    if (-not $PSCmdlet.ShouldProcess(($profilePaths -join ', '), 'Remove Poshify theme configuration')) {
        return
    }

    Write-PoshifyProfileBlock -Remove

    foreach ($profilePath in $profilePaths) {
        Select-String -LiteralPath $profilePath -Pattern 'oh-my-posh(\.exe)?[''"]?\s+init' | ForEach-Object {
            Write-Warning "$profilePath still initializes oh-my-posh outside Poshify (line $($_.LineNumber)): $($_.Line.Trim())"
        }
    }

    Remove-Item -LiteralPath (Get-PoshifyCurrentThemeFile), (Get-PoshifyInitScriptPath) -Force -ErrorAction SilentlyContinue
    Clear-PoshifySessionPrompt
}

function Resolve-PoshifyFolderPath {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.PSIsContainer -or $item.PSProvider.Name -ne 'FileSystem') {
        Write-Error -Message "Folder not found: $Path" -Category ObjectNotFound -TargetObject $Path
        return
    }
    $item.FullName
}

function Add-PoshifyTrust {
    param([string]$File)

    $trustFile = Join-Path $script:PoshifyHome 'trusted'
    $entries = @(if (Test-Path -LiteralPath $trustFile) { Get-Content -LiteralPath $trustFile }) |
        Where-Object { $_ -and -not $_.EndsWith(" $File") }
    $hash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
    Write-PoshifyTextFile -Path $trustFile -Text (((@($entries) + "$hash $File") -join "`n") + "`n")
}

# Makes this session pick up a folder theme change at the next prompt
function Sync-PoshifySessionTheme {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Session state shared with the generated init script')]
    param()

    if ($global:_poshifyUpdate) {
        $global:_poshifyLastLocation = $null
    }
    else {
        Invoke-PoshifyInitScript
    }
}

<#
.SYNOPSIS
    Sets the theme for a folder

.DESCRIPTION
    Writes a .poshify file in the folder. Poshify uses that theme in the folder and everything
    below it, instead of your default theme. The nearest .poshify file wins.

    Existing .ompconfig files work the same way, so folders set up for other per-folder theme
    scripts keep working.

.PARAMETER Name
    Theme name. Downloaded first if it isn't installed and exactly matches an online theme.

.PARAMETER ThemePath
    A theme file instead of a theme name, for example one kept in the project. It is stored
    relative to the folder when it is inside it, and trusted (see Approve-PoshifyFolderTheme).

.PARAMETER Path
    The folder. Defaults to the current folder.

.EXAMPLE
    Set-PoshifyFolderTheme dracula
    Uses the dracula theme in the current folder and below

.EXAMPLE
    Set-PoshifyFolderTheme -ThemePath .\tools\project.omp.json
    Uses a theme file kept in the project

.OUTPUTS
    None
#>
function Set-PoshifyFolderTheme {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByPath')]
        [string]$ThemePath,

        [string]$Path = '.'
    )

    $folder = Resolve-PoshifyFolderPath -Path $Path
    if (-not $folder) {
        return
    }

    $trust = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
        $item = Get-Item -LiteralPath $ThemePath -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) {
            Write-Error -Message "Theme file not found: $ThemePath" -Category ObjectNotFound -TargetObject $ThemePath
            return
        }
        $prefix = Join-Path $folder ''
        $value = if ($item.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $item.FullName.Substring($prefix.Length) } else { $item.FullName }
        $display = "'$($item.Name)'"
        $trust = $item.FullName
    }
    else {
        $theme = Resolve-PoshifyThemeFile -Name $Name -IncludeOnline
        if (-not $theme) {
            return
        }
        if (-not $theme.Path) {
            $theme = Install-PoshifyTheme -Name $theme.Name
            if (-not $theme) {
                return
            }
        }
        $value = $theme.Name
        $display = "'$($theme.Name)'"
    }

    $marker = Join-Path $folder '.poshify'
    if (-not $PSCmdlet.ShouldProcess($marker, "Set folder theme to $display")) {
        return
    }

    Write-PoshifyTextFile -Path $marker -Text "$value`n" -Encoding (New-Object System.Text.UTF8Encoding($false))
    if ($trust) {
        Add-PoshifyTrust -File $trust
    }

    # The profile block loads the init script that applies folder themes
    Write-PoshifyProfileBlock
    Sync-PoshifySessionTheme
}

<#
.SYNOPSIS
    Removes the theme set for a folder

.DESCRIPTION
    Deletes the .poshify (and .ompconfig) file in the folder. The folder then uses the theme of
    the nearest parent folder that has one, or your default theme.

.PARAMETER Path
    The folder. Defaults to the current folder.

.EXAMPLE
    Clear-PoshifyFolderTheme
    Removes the theme set for the current folder

.OUTPUTS
    None
#>
function Clear-PoshifyFolderTheme {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path = '.'
    )

    $folder = Resolve-PoshifyFolderPath -Path $Path
    if (-not $folder) {
        return
    }

    $markers = @('.poshify', '.ompconfig' | ForEach-Object { Join-Path $folder $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($markers.Count -eq 0) {
        Write-Warning "No folder theme is set in $folder."
    }
    foreach ($marker in $markers) {
        if ($PSCmdlet.ShouldProcess($marker, 'Remove folder theme')) {
            Remove-Item -LiteralPath $marker -Force
        }
    }

    if (-not $WhatIfPreference) {
        $inherited = Resolve-PoshifyLocationTheme -Path $folder -PoshifyHome $script:PoshifyHome
        if ($inherited) {
            Write-Warning "This folder still gets a theme from $($inherited.Marker)."
        }
        Sync-PoshifySessionTheme
    }
}

<#
.SYNOPSIS
    Shows the folder theme that applies to a folder

.DESCRIPTION
    Returns the theme set by the nearest .poshify (or .ompconfig) file at or above the folder,
    with a Status of Active, Untrusted, NotFound or Empty. Returns nothing when no folder theme
    applies, which means your default theme is used.

.PARAMETER Path
    The folder. Defaults to the current folder.

.EXAMPLE
    Get-PoshifyFolderTheme
    Shows the folder theme for the current folder

.OUTPUTS
    Poshify.FolderTheme
#>
function Get-PoshifyFolderTheme {
    [CmdletBinding()]
    [OutputType('Poshify.FolderTheme')]
    param(
        [string]$Path = '.'
    )

    $folder = Resolve-PoshifyFolderPath -Path $Path
    if (-not $folder) {
        return
    }

    $result = Resolve-PoshifyLocationTheme -Path $folder -PoshifyHome $script:PoshifyHome
    if (-not $result) {
        Write-Verbose "No folder theme applies to $folder; your default theme is used."
        return
    }

    [PSCustomObject]@{
        PSTypeName = 'Poshify.FolderTheme'
        Theme      = if ($result.File) { Get-PoshifyThemeName (Split-Path -Path $result.File -Leaf) } else { $result.Value }
        Status     = $result.Status
        Marker     = $result.Marker
        ThemePath  = $result.File
        Message    = $result.Message
    }
}

<#
.SYNOPSIS
    Trusts the theme file used by a folder

.DESCRIPTION
    oh-my-posh themes can run commands, so a .poshify file that points to a theme file outside
    your theme folders (for example one inside a cloned repository) is ignored until you trust
    that file. Trust is tied to the file's content: if it changes, it must be trusted again.

    Review the theme file before trusting it.

.PARAMETER Path
    The folder. Defaults to the current folder.

.EXAMPLE
    Approve-PoshifyFolderTheme
    Trusts the theme file used by the current folder

.OUTPUTS
    None
#>
function Approve-PoshifyFolderTheme {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path = '.'
    )

    $folder = Resolve-PoshifyFolderPath -Path $Path
    if (-not $folder) {
        return
    }

    $result = Resolve-PoshifyLocationTheme -Path $folder -PoshifyHome $script:PoshifyHome
    if (-not $result) {
        Write-Error -Message "No .poshify or .ompconfig file applies to $folder." -Category ObjectNotFound -TargetObject $folder
        return
    }
    if ($result.Status -eq 'Active') {
        Write-Verbose "The theme for $folder is already usable."
        return
    }
    if ($result.Status -ne 'Untrusted') {
        Write-Error -Message $result.Message -Category ObjectNotFound -TargetObject $result.Marker
        return
    }

    if ($PSCmdlet.ShouldProcess($result.File, 'Trust theme file')) {
        Add-PoshifyTrust -File $result.File
        Sync-PoshifySessionTheme
    }
}

<#
.SYNOPSIS
    Previews an oh-my-posh theme

.DESCRIPTION
    Renders what the prompt looks like with a theme, without changing your current theme.
    Themes that aren't installed can be previewed too; they are downloaded to a temporary file.

.PARAMETER Name
    The name of a local theme (see Get-PoshifyTheme), or the exact name of an online theme.

.PARAMETER ThemePath
    Direct path to a theme file. Accepts pipeline input from Get-PoshifyTheme.

.EXAMPLE
    Show-PoshifyTheme -Name "agnoster"
    Shows the agnoster prompt

.EXAMPLE
    Get-PoshifyTheme | Where-Object Favorite | Show-PoshifyTheme
    Shows every favorite theme

.OUTPUTS
    System.String
#>
function Show-PoshifyTheme {
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByName', Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByPath', ValueFromPipelineByPropertyName = $true)]
        [Alias('Path', 'FullName')]
        [string]$ThemePath
    )

    process {
        if (-not (Get-OhMyPoshCommand)) {
            Write-Error -Message "oh-my-posh is not installed or not in PATH. Run 'Poshify setup' to install it, or see $script:OhMyPoshInstallUrl" -Category NotInstalled
            return
        }

        $theme = Resolve-PoshifyThemeFile -Name $Name -ThemePath $ThemePath -IncludeOnline
        if (-not $theme) {
            return
        }

        if ($theme.Path) {
            "== $($theme.Name) =="
            Invoke-OhMyPosh -ArgumentList 'print', 'preview', '--config', $theme.Path
            return
        }

        # Not installed: preview from a temporary download
        $previewPath = Join-Path ([IO.Path]::GetTempPath()) "poshify-preview-$([guid]::NewGuid().ToString('N'))-$($theme.FileName)"
        try {
            if (Save-PoshifyThemeFile -Theme $theme -Path $previewPath) {
                "== $($theme.Name) (not installed) =="
                Invoke-OhMyPosh -ArgumentList 'print', 'preview', '--config', $previewPath
            }
        }
        finally {
            Remove-Item -LiteralPath $previewPath -Force -ErrorAction SilentlyContinue
        }
    }
}

<#
.SYNOPSIS
    Gets a random local theme

.DESCRIPTION
    Picks a random local theme, other than the current one when possible. Pipe it to
    Set-PoshifyTheme to apply it.

.PARAMETER FromFavorites
    Only pick from favorite themes that are available locally.

.EXAMPLE
    Get-PoshifyRandomTheme | Set-PoshifyTheme
    Applies a random theme

.EXAMPLE
    Get-PoshifyRandomTheme -FromFavorites | Set-PoshifyTheme
    Applies a random favorite theme

.OUTPUTS
    Poshify.Theme
#>
function Get-PoshifyRandomTheme {
    [CmdletBinding()]
    [OutputType('Poshify.Theme')]
    param(
        [switch]$FromFavorites
    )

    $candidates = @(Get-PoshifyTheme)
    if ($FromFavorites) {
        $candidates = @($candidates | Where-Object { $_.Favorite })
        if ($candidates.Count -eq 0) {
            Write-Error -Message 'None of your favorite themes are available locally. Use Add-PoshifyFavorite and Install-PoshifyTheme first.' -Category ObjectNotFound
            return
        }
    }
    elseif ($candidates.Count -eq 0) {
        Write-Error -Message 'No local themes found. Use Find-PoshifyTheme and Install-PoshifyTheme to get some.' -Category ObjectNotFound
        return
    }

    $others = @($candidates | Where-Object { -not $_.Current })
    if ($others.Count -gt 0) {
        $candidates = $others
    }
    $candidates | Get-Random
}

<#
.SYNOPSIS
    Adds a theme to favorites

.DESCRIPTION
    Saves a theme name to the favorites list. If the name matches a local theme, the theme's
    exact name is stored. Themes that aren't installed yet can be added too.

.PARAMETER Name
    The theme to add. Accepts pipeline input from Get-PoshifyTheme and Find-PoshifyTheme.

.EXAMPLE
    Add-PoshifyFavorite -Name "agnoster"
    Adds agnoster to favorites

.OUTPUTS
    None
#>
function Add-PoshifyFavorite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [string]$Name
    )

    process {
        $local = @(Select-PoshifyThemeMatch -Theme (Get-PoshifyTheme) -Name $Name)
        if ($local.Count -gt 1) {
            $null = Resolve-PoshifySingleTheme -Match $local -Name $Name -Location 'locally'
            return
        }

        $themeName = if ($local.Count -eq 1) { $local[0].Name } else { $Name }
        if ($local.Count -eq 0) {
            Write-Warning "Theme '$Name' is not installed locally. It is added to favorites, but won't be picked by Get-PoshifyRandomTheme -FromFavorites until installed."
        }

        $favorites = @(Get-PoshifyFavoriteList)
        if ($themeName -in $favorites) {
            Write-Verbose "Theme '$themeName' is already a favorite"
            return
        }

        Save-PoshifyFavoriteList -Name ($favorites + $themeName)
        Write-Verbose "Added '$themeName' to favorites"
    }
}

<#
.SYNOPSIS
    Removes a theme from favorites

.PARAMETER Name
    Exact name of the theme to remove from favorites.

.EXAMPLE
    Remove-PoshifyFavorite -Name "agnoster"
    Removes agnoster from favorites

.OUTPUTS
    None
#>
function Remove-PoshifyFavorite {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [string]$Name
    )

    process {
        $favorites = @(Get-PoshifyFavoriteList)
        if ($Name -notin $favorites) {
            Write-Error -Message "Theme '$Name' is not in favorites." -Category ObjectNotFound -TargetObject $Name
            return
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Remove from favorites')) {
            Save-PoshifyFavoriteList -Name @($favorites | Where-Object { $_ -ne $Name })
        }
    }
}

<#
.SYNOPSIS
    Gets the list of favorite themes

.EXAMPLE
    Get-PoshifyFavorite
    Lists all favorite theme names

.EXAMPLE
    Get-PoshifyTheme | Where-Object Favorite
    Lists favorite themes that are available locally, with details

.OUTPUTS
    System.String
#>
function Get-PoshifyFavorite {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Get-PoshifyFavoriteList
}

# Shows previews of a few popular themes and asks which one to use
function Select-PoshifySetupTheme {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup wizard')]
    param([switch]$Interactive)

    $choices = $script:SetupThemeChoices
    if (-not $Interactive) {
        return $script:DefaultTheme
    }

    Write-Host '  Popular themes:'
    for ($i = 0; $i -lt $choices.Count; $i++) {
        Write-Host ''
        Write-Host ('  {0}. {1}' -f ($i + 1), $choices[$i]) -ForegroundColor Cyan
        Show-PoshifyTheme -Name $choices[$i] -ErrorAction SilentlyContinue | Select-Object -Skip 1 | Out-Host
    }

    Write-Host ''
    Write-Host "  Or type 'random' (or 'random-favorites') for a different theme in each session."
    $answer = try { Read-Host "  Pick a number, or type any theme name (Enter for $($choices[0]))" } catch { '' }
    $number = $answer -as [int]
    if (-not $answer) { $choices[0] }
    elseif ($number -ge 1 -and $number -le $choices.Count) { $choices[$number - 1] }
    else { $answer.Trim() }
}

<#
.SYNOPSIS
    Sets up oh-my-posh and a Poshify theme in one go

.DESCRIPTION
    Walks through everything a working themed prompt needs and fixes what it can:

    1. oh-my-posh: offers to install it (winget on Windows, Homebrew on macOS, the official
       install script on Linux).
    2. Nerd Font: offers to install Meslo Nerd Font, which most themes need for their icons.
    3. Terminal font: offers to switch Windows Terminal's default font to that Nerd Font.
    4. Execution policy: checks that each PowerShell edition can run your profile and explains
       how to allow it if not. Poshify never changes the execution policy itself.
    5. Theme: lets you pick a theme from previews (or uses -Theme) and sets it up in your profiles.

    Steps that are already fine are skipped, so running it again is safe. Every change asks for
    confirmation unless -Force is used, and -WhatIf shows what would change.

.PARAMETER Theme
    Theme to use instead of choosing from previews. Downloaded if it isn't installed.

.PARAMETER Force
    Apply every fix without asking. Without -Theme, keeps the current theme or uses the
    oh-my-posh default theme.

.PARAMETER SkipFont
    Don't check or install fonts.

.EXAMPLE
    Initialize-Poshify
    Interactive setup

.EXAMPLE
    Initialize-Poshify -Theme atomic -Force
    Unattended setup with the atomic theme

.OUTPUTS
    None
#>
function Initialize-Poshify {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive setup wizard')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Theme,
        [switch]$Force,
        [switch]$SkipFont
    )

    $report = {
        param([string]$Status, [string]$Message)
        $color = switch ($Status) { 'ok' { 'Green' } 'done' { 'Cyan' } 'skip' { 'DarkGray' } default { 'Yellow' } }
        Write-Host ('  [{0,-4}] {1}' -f $Status, $Message) -ForegroundColor $color
    }

    # Honours -WhatIf/-Confirm, then asks unless -Force
    $approve = {
        param([string]$Target, [string]$Action, [string]$Question)
        if (-not $PSCmdlet.ShouldProcess($Target, $Action)) {
            return $false
        }
        if ($Force) {
            return $true
        }
        try {
            $PSCmdlet.ShouldContinue($Question, 'Poshify setup')
        }
        catch {
            & $report 'skip' 'Cannot ask for confirmation in this session; run with -Force to apply fixes.'
            $false
        }
    }

    # 1. oh-my-posh
    Write-Host 'oh-my-posh' -ForegroundColor White
    if (-not (Get-OhMyPoshCommand)) {
        $installer = Get-PoshifyOhMyPoshInstaller
        if (-not $installer) {
            & $report 'todo' "oh-my-posh is not installed and no supported installer was found. Install it from $script:OhMyPoshInstallUrl, then run setup again."
            return
        }
        if (-not (& $approve 'oh-my-posh' "Install with $($installer.Description)" "oh-my-posh is not installed. Install it now with $($installer.Description)?")) {
            & $report 'todo' "oh-my-posh is required. Install it from $script:OhMyPoshInstallUrl, then run setup again."
            return
        }

        Invoke-PoshifyInstaller -Installer $installer
        Sync-PoshifySessionPath
        if (-not (Get-OhMyPoshCommand)) {
            & $report 'todo' 'oh-my-posh was installed but is not on PATH yet. Open a new terminal and run setup again.'
            return
        }
        & $report 'done' "Installed oh-my-posh with $($installer.Description)"
        if (-not (Test-PoshifyWindows)) {
            & $report 'info' 'Make sure the folder containing oh-my-posh is on PATH in new sessions too.'
        }
    }
    & $report 'ok' "oh-my-posh $(Invoke-OhMyPosh -ArgumentList 'version')"

    # 2. Fonts
    Write-Host 'Font' -ForegroundColor White
    if ($SkipFont) {
        & $report 'skip' 'Font checks skipped'
    }
    else {
        $fonts = @(Get-PoshifyNerdFont)
        if ($fonts) {
            $listed = ($fonts | Select-Object -First 3) -join ', '
            if ($fonts.Count -gt 3) { $listed += " and $($fonts.Count - 3) more" }
            & $report 'ok' "Nerd Fonts installed: $listed"
        }
        elseif (& $approve $script:NerdFontFamily 'Install font' "Most themes need a Nerd Font to show their icons. Install $script:NerdFontFamily now?") {
            Invoke-OhMyPosh -ArgumentList 'font', 'install', $script:NerdFontName
            $fonts = @(Get-PoshifyNerdFont)
            if ($fonts) {
                & $report 'done' "Installed $script:NerdFontFamily"
            }
            else {
                & $report 'todo' "The font may need a new session to show up. If icons look like boxes, run: oh-my-posh font install $script:NerdFontName"
            }
        }
        else {
            & $report 'todo' "No Nerd Font found, so theme icons will show as boxes. Install one with: oh-my-posh font install $script:NerdFontName"
        }

        $face = if ($script:NerdFontFamily -in $fonts) { $script:NerdFontFamily } else { $fonts | Select-Object -First 1 }
        if (-not $face) {
            $face = $script:NerdFontFamily
        }

        $terminals = @(Get-PoshifyTerminalSettingsPath)
        foreach ($settingsPath in $terminals) {
            try {
                $currentFace = Get-PoshifyTerminalFont -Path $settingsPath
            }
            catch {
                & $report 'todo' "Could not read Windows Terminal settings ($settingsPath). Set its font to '$face' manually."
                continue
            }

            if (Test-PoshifyNerdFontFace $currentFace) {
                & $report 'ok' "Windows Terminal font: $currentFace"
            }
            elseif (-not $fonts) {
                & $report 'todo' "Windows Terminal uses '$currentFace'. Switch it to a Nerd Font once one is installed."
            }
            elseif (& $approve $settingsPath "Set default font to '$face'" "Windows Terminal uses '$currentFace', which has no icons. Change its default font to '$face'? A backup of its settings is kept.") {
                if (Write-PoshifyTerminalFont -Path $settingsPath -Face $face) {
                    & $report 'done' "Windows Terminal font set to '$face' (backup: $settingsPath.poshify-backup)"
                }
            }
            else {
                & $report 'todo' "Windows Terminal uses '$currentFace'. Set its font to '$face' to see theme icons."
            }
        }

        if ($env:TERM_PROGRAM -eq 'vscode') {
            & $report 'info' "In VS Code, set ""terminal.integrated.fontFamily"" to '$face' to see theme icons in its terminal."
        }
        elseif (-not $terminals) {
            & $report 'info' "Make sure your terminal's font is a Nerd Font such as '$face'."
        }
    }

    # 3. Execution policy
    Write-Host 'Execution policy' -ForegroundColor White
    foreach ($target in Get-PoshifyProfileTarget) {
        $policy = Get-PoshifyExecutionPolicy -Edition $target.Edition
        if (Test-PoshifyPolicyBlocksProfile $policy) {
            & $report 'todo' (Get-PoshifyPolicyAdvice -Edition $target.Edition -Policy $policy)
        }
        else {
            & $report 'ok' "$(Get-PoshifyEditionName $target.Edition) can run your profile ($policy)"
        }
    }

    # 4. Theme
    Write-Host 'Theme' -ForegroundColor White
    $selection = Get-PoshifyCurrentThemePath
    $choice = if ($Theme) {
        $Theme
    }
    elseif ($selection -like 'random*') {
        & $report 'ok' "Keeping random themes. Use 'Poshify theme set <name>' to pick a fixed one."
        $selection
    }
    elseif ($selection -and (Test-Path -LiteralPath $selection)) {
        & $report 'ok' "Keeping your default theme '$(Get-PoshifyThemeName (Split-Path -Path $selection -Leaf))'. Use 'Poshify theme set <name>' to change it."
        $selection
    }
    else {
        Select-PoshifySetupTheme -Interactive:(-not $Force)
    }

    $setParameters = switch -Regex ($choice) {
        '^random(-favorites|:favorites)$' { @{ Random = $true; FromFavorites = $true }; break }
        '^random$' { @{ Random = $true }; break }
        '[\\/]' { @{ ThemePath = $choice }; break }
        default { @{ Name = $choice } }
    }

    Set-PoshifyTheme @setParameters -ErrorVariable setError
    if ($setError -or $WhatIfPreference) {
        return
    }

    foreach ($target in Get-PoshifyProfileTarget) {
        $name = Get-PoshifyEditionName $target.Edition
        if ((Test-Path -LiteralPath $target.Path) -and (Select-String -LiteralPath $target.Path -SimpleMatch $script:ProfileBlockStart -Quiet)) {
            & $report 'ok' "$name profile loads the theme ($($target.Path))"
        }
        else {
            & $report 'skip' "$name profile not set up (its execution policy doesn't allow profiles)"
        }
    }
    $summary = if ($setParameters.Random) { 'a random theme in each new session' } else { "'$(Get-PoshifyThemeName (Split-Path -Path (Get-PoshifyCurrentThemePath) -Leaf))'" }
    & $report 'done' "Default theme: $summary. Folders with a .poshify file use their own theme ('Poshify folder set <name>')."
}

# Create CLI-friendly aliases for common operations
New-Alias -Name 'poshify-theme-get' -Value 'Get-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-find' -Value 'Find-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-install' -Value 'Install-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-set' -Value 'Set-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-reset' -Value 'Reset-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-current' -Value 'Get-PoshifyCurrentTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-remove' -Value 'Remove-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-update' -Value 'Update-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-show' -Value 'Show-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-favorite-add' -Value 'Add-PoshifyFavorite' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-favorite-remove' -Value 'Remove-PoshifyFavorite' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-favorite-get' -Value 'Get-PoshifyFavorite' -ErrorAction SilentlyContinue

# Create a main Poshify command that acts as a CLI utility
function Poshify {
    <#
    .SYNOPSIS
        Main Poshify CLI utility command

    .DESCRIPTION
        Provides a command-line interface for managing oh-my-posh themes.

        Setup:            Poshify setup (installs and configures everything; see Initialize-Poshify)
        Theme actions:    list, find, install, set, reset, current, show, update, remove, random
        Favorite actions: list, add, remove, random
        Folder actions:   set, clear, show, trust (theme for the current folder and below)

        'Poshify theme set random' (or random-favorites) uses a different theme in each session.

    .EXAMPLE
        Poshify setup
        Installs oh-my-posh and a Nerd Font if needed, and sets up a theme

    .EXAMPLE
        Poshify theme install agnoster
        Downloads and installs the agnoster theme

    .EXAMPLE
        Poshify theme set agnoster
        Sets the agnoster theme as current

    .EXAMPLE
        Poshify theme show agnoster
        Previews the agnoster theme

    .EXAMPLE
        Poshify theme update
        Updates all themes installed by Poshify

    .EXAMPLE
        Poshify favorite add agnoster
        Adds agnoster to favorites

    .EXAMPLE
        Poshify favorite random
        Applies a random favorite theme

    .EXAMPLE
        Poshify theme reset
        Resets theme to default PowerShell prompt
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive CLI front-end')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateSet('theme', 'favorite', 'folder', 'setup')]
        [string]$Command,

        [Parameter(Position = 1)]
        [ValidateSet('list', 'find', 'install', 'set', 'reset', 'current', 'show', 'update', 'remove', 'random', 'add', 'clear', 'trust')]
        [string]$Action,

        [Parameter(Position = 2)]
        [string]$ThemeName
    )

    if ($Command -eq 'setup') {
        Initialize-Poshify
        return
    }

    $actions = @{
        theme    = 'list', 'find', 'install', 'set', 'reset', 'current', 'show', 'update', 'remove', 'random'
        favorite = 'list', 'add', 'remove', 'random'
        folder   = 'set', 'clear', 'show', 'trust'
    }
    $needsName = 'theme install', 'theme set', 'theme show', 'theme remove', 'favorite add', 'favorite remove', 'folder set'

    if (-not $Action) {
        Write-Error "Missing action for '$Command'. Available actions: $($actions[$Command] -join ', ')"
        return
    }

    if ($Action -notin $actions[$Command]) {
        Write-Error "Unknown action '$Action' for '$Command'. Available actions: $($actions[$Command] -join ', ')"
        return
    }

    if ("$Command $Action" -in $needsName -and -not $ThemeName) {
        Write-Error "Theme name is required for '$Command $Action'"
        Write-Host "Usage: Poshify $Command $Action <theme-name>" -ForegroundColor Yellow
        return
    }

    switch ("$Command $Action") {
        'theme list' {
            $themes = Get-PoshifyTheme
            if (-not $themes) {
                Write-Host 'No local themes found. Use "Poshify theme find" and "Poshify theme install <name>" to get some.' -ForegroundColor Yellow
            }
            $themes
        }
        'theme find' {
            Find-PoshifyTheme -Name $ThemeName
        }
        'theme install' {
            $theme = Install-PoshifyTheme -Name $ThemeName
            if ($theme) {
                Write-Host "Theme '$($theme.Name)' is ready. Apply it with: Poshify theme set $($theme.Name)" -ForegroundColor Green
            }
        }
        'theme set' {
            if ($ThemeName -in 'random', 'random-favorites') {
                Set-PoshifyTheme -Random -FromFavorites:($ThemeName -eq 'random-favorites') -ErrorVariable setError
                $message = 'New sessions will each use a random theme.'
            }
            else {
                Set-PoshifyTheme -Name $ThemeName -ErrorVariable setError
                $message = "Default theme set to '$ThemeName'."
            }
            if (-not $setError) {
                Write-Host $message -ForegroundColor Green
                $folderTheme = Get-PoshifyFolderTheme
                if ($folderTheme) {
                    Write-Host "This folder uses its own theme '$($folderTheme.Theme)' from $($folderTheme.Marker)." -ForegroundColor Yellow
                }
            }
        }
        'theme reset' {
            Reset-PoshifyTheme
            Write-Host 'Poshify theme removed. Open a new session if your prompt has not changed.' -ForegroundColor Green
        }
        'theme current' {
            $theme = Get-PoshifyCurrentTheme
            if ($theme) {
                Write-Host "$($theme.Name) - $($theme.SelectedBy)" -ForegroundColor Green
            }
            elseif ((Get-PoshifyCurrentThemePath) -like 'random*') {
                Write-Host 'A random theme is picked when each session starts.' -ForegroundColor Yellow
            }
            else {
                Write-Host 'No theme is selected. Use "Poshify theme set <name>" to select one.' -ForegroundColor Yellow
            }
        }
        'folder set' {
            Set-PoshifyFolderTheme -Name $ThemeName -ErrorVariable setError
            if (-not $setError) {
                Write-Host "This folder and everything below it now use '$ThemeName'." -ForegroundColor Green
            }
        }
        'folder clear' {
            Clear-PoshifyFolderTheme
        }
        'folder show' {
            $folderTheme = Get-PoshifyFolderTheme
            if (-not $folderTheme) {
                Write-Host 'No folder theme applies here; your default theme is used.' -ForegroundColor Yellow
            }
            elseif ($folderTheme.Status -eq 'Active') {
                Write-Host "$($folderTheme.Theme) (from $($folderTheme.Marker))" -ForegroundColor Green
            }
            else {
                Write-Host "$($folderTheme.Status): $($folderTheme.Message)" -ForegroundColor Yellow
            }
        }
        'folder trust' {
            Approve-PoshifyFolderTheme
        }
        'theme show' {
            Show-PoshifyTheme -Name $ThemeName
        }
        'theme update' {
            $updated = if ($ThemeName) { @(Update-PoshifyTheme -Name $ThemeName) } else { @(Update-PoshifyTheme -All) }
            Write-Host "$($updated.Count) theme(s) updated." -ForegroundColor Green
            $updated
        }
        'theme remove' {
            Remove-PoshifyTheme -Name $ThemeName
        }
        { $_ -in 'theme random', 'favorite random' } {
            $theme = Get-PoshifyRandomTheme -FromFavorites:($Command -eq 'favorite')
            if ($theme) {
                $theme | Set-PoshifyTheme -ErrorVariable setError
                if (-not $setError) {
                    Write-Host "Theme set to '$($theme.Name)'." -ForegroundColor Green
                }
            }
        }
        'favorite list' {
            $favorites = Get-PoshifyFavorite
            if (-not $favorites) {
                Write-Host 'No favorite themes yet. Use "Poshify favorite add <name>" to add one.' -ForegroundColor Yellow
            }
            $favorites
        }
        'favorite add' {
            Add-PoshifyFavorite -Name $ThemeName
        }
        'favorite remove' {
            Remove-PoshifyFavorite -Name $ThemeName
        }
    }
}

# Tab completion for theme names
$localThemeCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if ($commandName -eq 'Poshify') {
        $command = "$($fakeBoundParameters['Command']) $($fakeBoundParameters['Action'])"
        if ($command -eq 'favorite remove') {
            Get-PoshifyFavorite | Where-Object { $_ -like "$wordToComplete*" }
            return
        }
        # Install and find work with online themes; don't suggest local names there
        if ($command -notin 'theme set', 'theme show', 'theme update', 'theme remove', 'favorite add', 'folder set') {
            return
        }
    }

    Get-PoshifyTheme | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Path)
    }
}
$favoriteCompleter = {
    param($commandName, $parameterName, $wordToComplete)
    Get-PoshifyFavorite | Where-Object { $_ -like "$wordToComplete*" }
}
Register-ArgumentCompleter -ParameterName 'Name' -ScriptBlock $localThemeCompleter -CommandName @(
    'Get-PoshifyTheme', 'Set-PoshifyTheme', 'Show-PoshifyTheme', 'Update-PoshifyTheme', 'Remove-PoshifyTheme', 'Add-PoshifyFavorite', 'Set-PoshifyFolderTheme'
)
Register-ArgumentCompleter -CommandName 'Remove-PoshifyFavorite' -ParameterName 'Name' -ScriptBlock $favoriteCompleter
Register-ArgumentCompleter -CommandName 'Poshify' -ParameterName 'ThemeName' -ScriptBlock $localThemeCompleter

# Export module functions and aliases
Export-ModuleMember -Function @(
    'Get-PoshifyTheme',
    'Get-PoshifyCurrentTheme',
    'Find-PoshifyTheme',
    'Install-PoshifyTheme',
    'Update-PoshifyTheme',
    'Remove-PoshifyTheme',
    'Set-PoshifyTheme',
    'Reset-PoshifyTheme',
    'Show-PoshifyTheme',
    'Get-PoshifyRandomTheme',
    'Add-PoshifyFavorite',
    'Remove-PoshifyFavorite',
    'Get-PoshifyFavorite',
    'Initialize-Poshify',
    'Set-PoshifyFolderTheme',
    'Clear-PoshifyFolderTheme',
    'Get-PoshifyFolderTheme',
    'Approve-PoshifyFolderTheme',
    'Poshify'
) -Alias @(
    'poshify-theme-get',
    'poshify-theme-find',
    'poshify-theme-install',
    'poshify-theme-set',
    'poshify-theme-reset',
    'poshify-theme-current',
    'poshify-theme-remove',
    'poshify-theme-update',
    'poshify-theme-show',
    'poshify-favorite-add',
    'poshify-favorite-remove',
    'poshify-favorite-get'
)
