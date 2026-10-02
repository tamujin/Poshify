@{
    # Module metadata
    RootModule = 'Poshify.psm1'
    ModuleVersion = '2.1.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Poshify Module'
    CompanyName = 'Poshify'
    Copyright = '(c) 2024 Poshify Module. All rights reserved.'
    
    # Module description
    Description = 'A PowerShell module for managing oh-my-posh themes. Discover, install, preview, update and switch between oh-my-posh themes, with favorites and safe profile management.'
    
    # PowerShell version requirements
    PowerShellVersion = '5.1'
    
    # Supported editions
    CompatiblePSEditions = @('Desktop', 'Core')
    
    # Required modules
    RequiredModules = @()
    
    # Required assemblies
    RequiredAssemblies = @()
    
    # Script files to process
    ScriptsToProcess = @()
    
    # Type files to load
    TypesToProcess = @()
    
    # Format files to load
    FormatsToProcess = @()
    
    # Nested modules
    NestedModules = @()
    
    # Functions to export
    FunctionsToExport = @(
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
    )
    
    # Aliases to export
    AliasesToExport = @(
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
    
    # Cmdlets to export
    CmdletsToExport = @()
    
    # Variables to export
    VariablesToExport = ''
    
    # List of all modules packaged with this module
    ModuleList = @()
    
    # List of all files packaged with this module
    FileList = @(
        'Poshify.psd1',
        'Poshify.psm1'
    )
    
    # Private data to pass to the module
    PrivateData = @{
        PSData = @{
            # Tags for module discovery
            Tags = @('oh-my-posh', 'theme', 'prompt', 'powershell', 'terminal', 'cli', 'productivity')
            
            # License URI
            LicenseUri = 'https://opensource.org/licenses/MIT'
            
            # Project URI
            ProjectUri = 'https://github.com/tamujin/Poshify'
            
            # Icon URI
            IconUri = ''
            
            # Release notes
            ReleaseNotes = @'
Version 2.1.0
Upgrading from 1.0.x: your profile is migrated automatically the next time you run
Set-PoshifyTheme or Reset-PoshifyTheme. (2.0.0 was not published to the Gallery.)

Profile handling
- The profile is managed through one marked block that is written once; switching themes
  only updates ~/.poshthemes/current and no longer rewrites the profile
- Fixed repeated Set-PoshifyTheme calls piling up oh-my-posh init lines in the profile
- Fixed Reset-PoshifyTheme leaving the theme active or restoring a stale profile backup
- Reset-PoshifyTheme no longer edits oh-my-posh setup it did not create
- Profile encoding and line endings are preserved
- Set-PoshifyTheme applies the theme to the current session immediately

Setup
- Poshify setup (Initialize-Poshify): installs oh-my-posh and a Nerd Font if missing, switches the
  Windows Terminal font, checks execution policies and sets a theme picked from previews
- Both PowerShell 7 and Windows PowerShell profiles are set up on Windows
- Set-PoshifyTheme downloads themes that aren't installed yet; Show-PoshifyTheme previews them

Per-folder themes
- A .poshify file sets the theme for a folder and everything below it; .ompconfig files work too
- Set-, Clear-, Get-, Approve-PoshifyFolderTheme (Poshify folder set|clear|show|trust)
- Theme files outside your theme folders must be trusted first, since themes can run commands
- Set-PoshifyTheme -Random [-FromFavorites]: a different theme in every new session

New commands
- Get-PoshifyCurrentTheme: the selected theme
- Update-PoshifyTheme: re-download themes that changed upstream (-All for every theme)
- Remove-PoshifyTheme: delete a downloaded theme
- Show-PoshifyTheme: render a preview of a theme's prompt
- Get-PoshifyRandomTheme: pick a random (favorite) theme to pipe into Set-PoshifyTheme
- Add-, Remove-, Get-PoshifyFavorite: manage favorite themes
- Poshify CLI: theme current/show/update/remove/random and favorite list/add/remove/random

Improvements
- Themes bundled with oh-my-posh (POSH_THEMES_PATH) are listed and can be set without downloading
- The online theme list is cached for an hour (Find-PoshifyTheme -ForceRefresh to bypass)
- Exact theme names take precedence over partial matches; ambiguous names error instead of prompting
- -WhatIf/-Confirm, pipeline input and tab completion; YAML and TOML themes are recognised
- Fixed single search results being dropped on Windows PowerShell 5.1
- Fixed the theme folder location on Linux and macOS

Version 1.0.1 - CI/CD Fix
- Fixed CI/CD workflow by removing invalid PowerShell setup actions

Version 1.0.0 - Initial Release
- Get-PoshifyTheme: List available local themes
- Find-PoshifyTheme: Discover themes from oh-my-posh repository
- Install-PoshifyTheme: Download and install themes
- Set-PoshifyTheme: Apply themes to PowerShell prompt
- Reset-PoshifyTheme: Restore default PowerShell prompt
'@
            
            # Prerelease string
            Prerelease = ''
            
            # Require license acceptance
            RequireLicenseAcceptance = $false
            
            # External module dependencies
            ExternalModuleDependencies = @()
        }
    }
    
    # Help info URI
    HelpInfoURI = ''
    
    # Default prefix for commands
    DefaultCommandPrefix = ''
}