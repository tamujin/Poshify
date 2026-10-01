# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-10-01

### Changed
- The profile is managed through a single marked block (`# >>> poshify >>>` … `# <<< poshify <<<`)
  that is written once. The selected theme is stored in `~/.poshthemes/current`, so switching
  themes no longer rewrites the profile.
- `Get-PoshifyTheme` now returns `Poshify.Theme` objects (`Name`, `Source`, `Current`, `Path`)
  and also lists themes bundled with oh-my-posh (`$env:POSH_THEMES_PATH`).
- Exact theme names take precedence over partial matches. Ambiguous names now produce an error
  listing the candidates instead of an interactive prompt.
- `Reset-PoshifyTheme` only removes Poshify's own block and warns about other oh-my-posh setup
  instead of editing it. Profile backups are no longer created or restored.
- Status messages use the verbose/warning streams instead of `Write-Host`.

### Added
- `Set-PoshifyTheme` applies the theme to the current session (`-NoApply` to skip).
- `-WhatIf`/`-Confirm` on `Set-`, `Reset-` and `Install-PoshifyTheme`.
- `Install-PoshifyTheme -Force` and pipeline input (`Find-PoshifyTheme power* | Install-PoshifyTheme`).
- Tab completion for local theme names.
- YAML and TOML theme files are recognised.
- Pester test suite.

### Fixed
- Repeated `Set-PoshifyTheme` calls accumulated `oh-my-posh init` lines in the profile.
- `Reset-PoshifyTheme` left the theme active, or restored a backup that already contained a theme.
- `Reset-PoshifyTheme` could leave a broken profile when removing oh-my-posh setup it did not create.
- A search with exactly one result returned nothing on Windows PowerShell 5.1.
- Installing `agnoster` was skipped when `agnosterplus` was already present.
- The module failed to resolve its theme folder on Linux and macOS.
- Profile encoding and line endings are preserved; a missing profile directory is created.
- Failed downloads no longer leave partial theme files behind.
- Profiles modified by 1.0.x are cleaned up automatically on the next `Set-` or `Reset-PoshifyTheme`.

## [1.0.1]

### Fixed
- CI/CD workflow no longer uses invalid PowerShell setup actions.

## [1.0.0] - 2024-01-01

### Added
- Initial release of Poshify module
- Get-PoshifyTheme: List available local themes
- Find-PoshifyTheme: Discover themes from oh-my-posh repository
- Install-PoshifyTheme: Download and install themes
- Set-PoshifyTheme: Apply themes to PowerShell prompt
- Reset-PoshifyTheme: Restore default PowerShell prompt
- Poshify: Main CLI utility command
- PowerShell profile backup and restoration
- Comprehensive error handling and user feedback
- Comment-based help for all functions
- Aliases for common operations

### Security
- Safe profile modification with automatic backups
- Input validation on all parameters
- Secure web requests for theme downloads

[Unreleased]: https://github.com/tamujin/Poshify/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/tamujin/Poshify/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/tamujin/Poshify/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/tamujin/Poshify/releases/tag/v1.0.0