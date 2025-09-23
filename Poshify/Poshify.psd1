@{
    # Module metadata
    RootModule = 'Poshify.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Poshify Module'
    CompanyName = 'Poshify'
    Copyright = '(c) 2024 Poshify Module. All rights reserved.'
    
    # Module description
    Description = 'A PowerShell module for managing oh-my-posh themes. Provides functions to discover, install, and switch between oh-my-posh themes with ease.'
    
    # PowerShell version requirements
    PowerShellVersion = '5.1'
    
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