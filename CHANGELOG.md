# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.0] - 2026-10-01

Combines the 2.0.0 feature work with a rework of profile handling. 2.0.0 was never published
to the PowerShell Gallery; its new commands were not exported by the module, so this is the first
release where they are usable.

### Added
- `Poshify setup` / `Initialize-Poshify`: one command that installs oh-my-posh (winget, Homebrew or
  the official script) and Meslo Nerd Font if missing, switches Windows Terminal's default font to
  the Nerd Font (keeping a backup of its settings), checks that each PowerShell edition can run your
  profile, and sets a theme picked from previews. Safe to re-run; supports `-Force` and `-WhatIf`.
- On Windows, `Set-PoshifyTheme` sets up both the PowerShell 7 and Windows PowerShell profiles. A
  missing profile for the other edition is only created when its execution policy lets it run.
- `Set-PoshifyTheme` warns when an execution policy will stop the profile from loading, and shows the
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` command to allow it. Poshify never changes
  the policy itself.
- Per-folder themes: a `.poshify` file sets the theme for a folder and everything below it, and
  existing `.ompconfig` files are honoured too. Managed with `Set-`, `Clear-`, `Get-` and
  `Approve-PoshifyFolderTheme` (`Poshify folder set|clear|show|trust`). A folder file that points to
  a theme file outside your theme folders is ignored until trusted, because themes can run commands;
  trust is tied to the file's content.
- `Set-PoshifyTheme -Random [-FromFavorites]` (`Poshify theme set random`): a different theme in
  every new session.
- `Get-PoshifyCurrentTheme` reports the theme for the current folder (or `-Path`) and a
  `SelectedBy` property saying whether it comes from a folder file, the default or a random pick.
- The profile block now loads a generated `~/.poshthemes/init.ps1`, which applies folder themes
  without loading the module and passes the last command's status and exit code through to
  oh-my-posh. Poshify updates that file itself, so later versions don't need to edit your profile.
- `Set-PoshifyTheme` downloads a theme that isn't installed when its name exactly matches an online theme.
- `Show-PoshifyTheme` previews themes that aren't installed, using a temporary download.
- `Get-PoshifyCurrentTheme`: the theme selected with `Set-PoshifyTheme`.
- `Update-PoshifyTheme [-Name | -All]`: re-downloads themes whose content changed upstream,
  detected by comparing git blob hashes (no extra requests).
- `Remove-PoshifyTheme`: deletes a downloaded theme. Exact names only; refuses bundled themes and,
  without `-Force`, the current theme.
- `Show-PoshifyTheme`: renders the theme's prompt with `oh-my-posh print preview`
  (replaces 2.0.0's `Test-PoshifyTheme`).
- `Get-PoshifyRandomTheme [-FromFavorites]`: returns a random theme other than the current one;
  pipe it to `Set-PoshifyTheme` (in 2.0.0 it applied the theme itself).
- `Add-`, `Remove-`, `Get-PoshifyFavorite`, and a `Favorite` property on `Get-PoshifyTheme` output.
- `Find-PoshifyTheme -ForceRefresh`; the online list is cached for an hour and a stale cache is
  used when GitHub is unreachable.
- CLI: `Poshify theme current|show|update|remove|random` and `Poshify favorite list|add|remove|random`.
- `Set-PoshifyTheme` applies the theme to the current session (`-NoApply` to skip).
- `-WhatIf`/`-Confirm` on all commands that change files.
- `Install-PoshifyTheme -Force` and pipeline input (`Find-PoshifyTheme power* | Install-PoshifyTheme`).
- Tab completion for theme and favorite names.
- YAML and TOML theme files are recognised.
- Pester test suite, run in CI on Windows, Linux, macOS and Windows PowerShell 5.1.

### Changed
- The profile is managed through a single marked block (`# >>> poshify >>>` … `# <<< poshify <<<`)
  that is written once. The selected theme is stored in `~/.poshthemes/current`, so switching
  themes no longer rewrites the profile.
- `Get-PoshifyTheme` now returns `Poshify.Theme` objects (`Name`, `Source`, `Current`, `Favorite`,
  `SizeKB`, `LastModified`, `Path`) instead of file objects, and also lists themes bundled with
  oh-my-posh (`$env:POSH_THEMES_PATH`). This replaces 2.0.0's `-Detailed` switch.
- Exact theme names take precedence over partial matches. Ambiguous names now produce an error
  listing the candidates instead of an interactive prompt.
- `Reset-PoshifyTheme` only removes Poshify's own block and warns about other oh-my-posh setup
  instead of editing it. Profile backups are no longer created or restored.
- Status messages use the verbose/warning streams instead of `Write-Host`; no command prompts with
  `Read-Host` any more.
- 2.0.0's GitHub rate-limit tracking was removed (it read headers `Invoke-RestMethod` doesn't return);
  caching keeps requests low and a rate-limit error is reported clearly.

### Fixed
- 2.0.0's new commands were missing from `Export-ModuleMember` and could not be called.
- Adding a second favorite in 2.0.0 merged the names into one string (`agnosteratomic`).
- 2.0.0's `.gitignore` ignored `*.psd1` and `*.psm1`, the module's own source files.
- Repeated `Set-PoshifyTheme` calls accumulated `oh-my-posh init` lines in the profile.
- `Reset-PoshifyTheme` left the theme active, or restored a backup that already contained a theme.
- `Reset-PoshifyTheme` could leave a broken profile when removing oh-my-posh setup it did not create.
- A search with exactly one result returned nothing on Windows PowerShell 5.1.
- Installing `agnoster` was skipped when `agnosterplus` was already present.
- The module failed to resolve its theme folder on Linux and macOS.
- Profile encoding and line endings are preserved; a missing profile directory is created.
- Failed downloads no longer leave partial theme files behind.
- Profiles modified by 1.0.x or 2.0.0 are cleaned up automatically on the next `Set-` or `Reset-PoshifyTheme`.

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

[Unreleased]: https://github.com/tamujin/Poshify/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/tamujin/Poshify/compare/v1.0.1...v2.1.0
[1.0.1]: https://github.com/tamujin/Poshify/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/tamujin/Poshify/releases/tag/v1.0.0