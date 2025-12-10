# TWMT Build & Release Scripts

Scripts pour automatiser le processus de build et release de TWMT.

## Prérequis

1. **Flutter** installé et dans le PATH
2. **GitHub CLI** (`gh`) installé et authentifié
   ```powershell
   # Installer GitHub CLI
   winget install GitHub.cli

   # S'authentifier
   gh auth login
   ```
3. **Inno Setup** (optionnel, pour créer l'installateur .exe)
   - Télécharger depuis : https://jrsoftware.org/isinfo.php

## Scripts Disponibles

### `release.ps1` - Script Principal

Script complet avec toutes les options.

```powershell
# Usage interactif (prompt pour la version)
.\scripts\release.ps1

# Spécifier la version
.\scripts\release.ps1 -Version "1.2.0"

# Release avec build number spécifique
.\scripts\release.ps1 -Version "1.2.0" -BuildNumber 50

# Créer une pre-release (beta)
.\scripts\release.ps1 -Version "1.3.0-beta.1" -Prerelease

# Créer un draft (non publié)
.\scripts\release.ps1 -Version "2.0.0" -Draft

# Skip certaines étapes
.\scripts\release.ps1 -Version "1.2.0" -SkipBuild      # Si déjà buildé
.\scripts\release.ps1 -Version "1.2.0" -SkipInstaller  # ZIP uniquement
```

### `quick-release.ps1` - Release Rapide

Incrémente automatiquement la version selon le type.

```powershell
# Patch release: 1.0.0 -> 1.0.1 (bug fixes)
.\scripts\quick-release.ps1 patch

# Minor release: 1.0.0 -> 1.1.0 (new features)
.\scripts\quick-release.ps1 minor

# Major release: 1.0.0 -> 2.0.0 (breaking changes)
.\scripts\quick-release.ps1 major
```

### `release.cmd` - Wrapper Batch

Pour lancer depuis cmd.exe :

```cmd
scripts\release.cmd 1.2.0
```

## Processus de Release

Le script effectue automatiquement :

1. **Validation** - Vérifie Flutter, GitHub CLI, authentification
2. **Version Update** - Met à jour `pubspec.yaml`
3. **Clean Build** - `flutter clean && flutter pub get`
4. **Code Generation** - `build_runner build`
5. **Windows Build** - `flutter build windows --release`
6. **Installer** - Crée l'installateur avec Inno Setup (si disponible)
7. **ZIP** - Crée une archive ZIP du build
8. **GitHub Release** - Crée la release avec les assets
9. **Git Commit** - Commit et push du changement de version

## Structure des Releases GitHub

```
Tag: v1.2.0
Title: Version 1.2.0
Assets:
  - twmt-1.2.0-windows-x64-setup.exe  (installateur)
  - twmt-1.2.0-windows-x64.zip        (archive portable)
```

## Semantic Versioning

| Type | Quand l'utiliser | Exemple |
|------|------------------|---------|
| **PATCH** | Bug fixes, corrections mineures | 1.0.0 → 1.0.1 |
| **MINOR** | Nouvelles fonctionnalités (backward compatible) | 1.0.0 → 1.1.0 |
| **MAJOR** | Breaking changes | 1.0.0 → 2.0.0 |

## Dépannage

### "gh: command not found"
```powershell
winget install GitHub.cli
# Puis redémarrer le terminal
```

### "GitHub CLI not authenticated"
```powershell
gh auth login
# Suivre les instructions
```

### "Inno Setup failed"
- Vérifier que Inno Setup est installé
- Le script créera un ZIP à la place

### "Flutter build failed"
```powershell
flutter doctor
flutter clean
flutter pub get
```

## Notes

- Les releases sont automatiquement détectées par l'app au démarrage
- Les utilisateurs verront une notification de mise à jour dans les paramètres
- Les pre-releases (`-Prerelease`) ne sont PAS proposées aux utilisateurs normaux
