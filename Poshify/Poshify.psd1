@{
    # Module metadata
    RootModule = 'Poshify.psm1'
    ModuleVersion = '1.1.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Poshify Module'
    CompanyName = 'Poshify'
    Copyright = '(c) 2024 Poshify Module. All rights reserved.'
    
    # Module description
    Description = 'A PowerShell module for managing oh-my-posh themes. Provides functions to discover, install, and switch between oh-my-posh themes with ease.'
    
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
        'Find-PoshifyTheme',
        'Install-PoshifyTheme',
        'Set-PoshifyTheme',
        'Reset-PoshifyTheme',
        'Poshify'
    )
    
    # Aliases to export
    AliasesToExport = @(
        'poshify-theme-get',
        'poshify-theme-find',
        'poshify-theme-install',
        'poshify-theme-set',
        'poshify-theme-reset'
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
Version 1.1.0 - Reliable profile handling
- Profile is managed through one marked block that is written once; switching themes no longer rewrites the profile
- Fixed repeated Set-PoshifyTheme calls piling up oh-my-posh init lines in the profile
- Fixed Reset-PoshifyTheme leaving the theme active and restoring stale profile backups
- Reset-PoshifyTheme no longer edits oh-my-posh setup it did not create
- Blocks written by 1.0.x are migrated automatically
- Exact theme names take precedence over partial matches; ambiguous names error instead of prompting
- Themes bundled with oh-my-posh (POSH_THEMES_PATH) are listed and can be set without downloading
- Set-PoshifyTheme applies the theme to the current session immediately
- Fixed single search results being dropped on Windows PowerShell 5.1
- Fixed module path on Linux and macOS
- Profile encoding and line endings are preserved
- Added -WhatIf/-Confirm, Install-PoshifyTheme -Force, pipeline input and tab completion

Version 1.0.1 - CI/CD Fix
- Fixed CI/CD workflow by removing invalid PowerShell setup actions
- GitHub runners already have PowerShell pre-installed

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