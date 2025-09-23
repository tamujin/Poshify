# Contributing to Poshify

First off, thank you for considering contributing to Poshify! It's people like you that make Poshify such a great tool for the PowerShell community.

## 🚀 Getting Started

### Prerequisites

- PowerShell 5.1 or higher
- Git
- A GitHub account

### Development Setup

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```powershell
   git clone https://github.com/your-username/Poshify.git
   cd Poshify
   ```

3. Import the module for testing:
   ```powershell
   Import-Module .\Poshify\Poshify.psd1 -Force
   ```

4. Verify the module loads correctly:
   ```powershell
   Get-Command -Module Poshify
   ```

## 📝 Types of Contributions

### 🐛 Bug Reports

Before creating bug reports, please check the existing issues to see if the problem has already been reported. When you are creating a bug report, please include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples to demonstrate the steps**
- **Describe the behavior you observed and what behavior you expected**
- **Include code samples and error messages**

### 💡 Feature Requests

Feature requests are welcome! Please provide:

- **Use a clear and descriptive title**
- **Provide a step-by-step description of the suggested enhancement**
- **Provide specific examples to demonstrate the enhancement**
- **Explain why this enhancement would be useful**

### 🔧 Pull Requests

1. Create a new branch from `main`:
   ```powershell
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following our coding standards (see below)

3. Test your changes thoroughly:
   ```powershell
   # Run PSScriptAnalyzer
   Invoke-ScriptAnalyzer -Path .\Poshify -Settings PSGallery -Recurse
   
   # Test module manifest
   Test-ModuleManifest -Path .\Poshify\Poshify.psd1
   
   # Test functionality
   Import-Module .\Poshify\Poshify.psd1 -Force
   # Test your specific changes
   ```

4. Commit your changes with a clear commit message:
   ```powershell
   git commit -m "Add: Brief description of your changes"
   ```

5. Push to your fork and submit a pull request

## 🎯 Coding Standards

### PowerShell Best Practices

- **Use approved verbs**: Use `Get-Verb` to see approved PowerShell verbs
- **Follow PowerShell naming conventions**: `Verb-Noun` format
- **Use parameter validation**: Always validate input parameters
- **Include help documentation**: Use comment-based help for all functions
- **Handle errors gracefully**: Use try-catch blocks and provide meaningful error messages
- **Use Write-* cmdlets**: Use appropriate Write cmdlets (Write-Output, Write-Verbose, Write-Warning, Write-Error)

### Code Style

```powershell
# Good
function Get-PoshifyTheme {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )
    
    try {
        # Implementation
    }
    catch {
        Write-Error "Failed to get themes: $($_.Exception.Message)"
    }
}

# Bad
function getPoshifytheme($name) {
    # implementation
}
```

### Documentation Standards

All functions must include comment-based help:

```powershell
<#
.SYNOPSIS
    Brief description of the function

.DESCRIPTION
    Detailed description of what the function does

.PARAMETER ParameterName
    Description of the parameter

.EXAMPLE
    Example of how to use the function

.EXAMPLE
    Another example if applicable

.OUTPUTS
    Type of output the function returns

.NOTES
    Any additional notes or requirements
#>
```

### Error Handling

Always include proper error handling:

```powershell
try {
    # Your code here
}
catch {
    Write-Error "Failed to [action]: $($_.Exception.Message)"
    Write-Verbose "Error details: $($_.Exception)"
    throw  # Re-throw if you want calling function to handle it
}
```

## 🧪 Testing

### Manual Testing

Before submitting a PR, manually test:

1. **Module import**: `Import-Module .\Poshify\Poshify.psd1 -Force`
2. **Command discovery**: `Get-Command -Module Poshify`
3. **Help functionality**: `Get-Help Function-Name`
4. **Basic operations**: Test the main functionality of your changes
5. **Error scenarios**: Test with invalid inputs and edge cases

### Automated Testing

Run these commands before submitting:

```powershell
# PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path .\Poshify -Settings PSGallery -Recurse

# Module manifest validation
Test-ModuleManifest -Path .\Poshify\Poshify.psd1

# Syntax checking
$scripts = Get-ChildItem -Path .\Poshify -Filter "*.psm1" -Recurse
foreach ($script in $scripts) {
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script -Raw), [ref]$null)
}
```

## 📋 Commit Message Guidelines

Use clear and meaningful commit messages:

- **Add**: For new features or functions
- **Fix**: For bug fixes
- **Update**: For improvements to existing functionality
- **Remove**: For removing code or features
- **Docs**: For documentation changes
- **Refactor**: For code refactoring

Examples:
```
Add: New function to export theme configurations
Fix: Handle empty theme directory in Get-PoshifyTheme
Update: Improve error messages in Install-PoshifyTheme
Docs: Add examples to Set-PoshifyTheme help
```

## 🔄 Pull Request Process

1. **Update documentation** if needed
2. **Update the module version** in `Poshify.psd1` if applicable
3. **Add tests** for new functionality
4. **Ensure all tests pass**
5. **Update CHANGELOG.md** with your changes
6. **Reference any related issues** in your PR description

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Manual testing completed
- [ ] PSScriptAnalyzer passes
- [ ] Module manifest validates

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated
```

## 🆘 Getting Help

If you need help:

1. Check existing documentation and issues
2. Ask in discussions
3. Join our community channels

## 🏆 Recognition

Contributors will be recognized in:

- The project README
- Release notes
- Special thanks section

Thank you for contributing to Poshify! 🎉