# Scripts de build local — rpgmtranslate-qt (Windows)

Ces trois scripts PowerShell permettent de produire le livrable
`rpgmtranslate.exe` **entièrement statique** (aucune DLL Qt requise) sur
Windows x64.

---

## Ordre d'exécution

```
01-check-prerequisites.ps1   ← vérifier / installer les outils
02-build-qt-static.ps1       ← compiler Qt 6 statique (une seule fois)
03-build-rpgmtranslate.ps1   ← compiler l'application
```

> **Note :** Lancez ces scripts depuis la racine du dépôt **ou** depuis le
> dossier `scripts/`. Les deux fonctionnent.

---

## Prérequis

| Outil | Version min. | Rôle |
|---|---|---|
| Windows 10 / 11 | — | OS cible |
| Visual Studio 2022 | 17.x | Compilateur MSVC (workload *Desktop C++*) |
| CMake | **3.31** | Système de build de l'application |
| Ninja | toute | Build de Qt (détecté automatiquement par configure) |
| Git | toute | SCM |
| Rust (stable MSVC) | **1.87** | Bibliothèque Rust (`edition = "2024"`) |
| cbindgen | **0.29.2** | Génération du header C depuis Rust |
| vcpkg | toute | LibArchive (`x64-windows-static`, triplet /MT) |
| 7-Zip | toute | Extraction des sources Qt |

---

## Étape 1 — Vérification des prérequis

```powershell
.\scripts\01-check-prerequisites.ps1
```

Vérifie la présence et la version de chaque outil. Affiche
`[OK]` / `[WARN]` / `[FAIL]` avec chemin et version.

Passer `-Fix` pour tenter d'installer les outils manquants via
`winget` / `cargo` (sans confirmation interactive) :

```powershell
.\scripts\01-check-prerequisites.ps1 -Fix
```

---

## Étape 2 — Build Qt statique (une seule fois par version Qt)

```powershell
.\scripts\02-build-qt-static.ps1
```

**Durée estimée : 30 à 90 minutes** selon le CPU.

Si `C:\Qt\static\Qt-6.9.2\lib\cmake\Qt6\Qt6Config.cmake` existe déjà,
le script se termine immédiatement — aucun rebuild inutile.

### Ce que fait le script
1. Télécharge `qt-everywhere-src-6.9.2.tar.xz` (~500 MB) avec barre de
   progression.
2. Extrait via 7-Zip.
3. Détecte les flags disponibles en exécutant `configure.bat -help` :
   les flags absents dans la version choisie (ex. `-no-emojisegmenter`
   supprimé dans Qt ≥ 6.9) sont **automatiquement ignorés**.
4. Appelle `configure.bat` depuis le répertoire source avec `-B <builddir>`
   (convention Qt 6) via un `.bat` temporaire — aucun problème de guillemets
   PowerShell → cmd.
5. Build Ninja (parallèle).
6. Installation dans le préfixe.

### Paramètres principaux

| Paramètre | Défaut | Description |
|---|---|---|
| `-QtVersion` | `6.9.2` | Version Qt à builder |
| `-InstallPrefix` | `C:\Qt\static\Qt-<version>` | Répertoire d'installation |
| `-DownloadDir` | `%TEMP%\qt-src` | Dossier temporaire |
| `-Jobs` | nb cœurs | Parallélisme Ninja |
| `-SkipDownload` | — | Réutiliser l'archive déjà téléchargée |
| `-SkipExtract` | — | Réutiliser le dossier source déjà extrait |

```powershell
# Exemple avec paramètres personnalisés
.\scripts\02-build-qt-static.ps1 `
    -QtVersion 6.9.2 `
    -InstallPrefix D:\Qt\static\Qt-6.9.2 `
    -Jobs 16

# Reprendre un build interrompu
.\scripts\02-build-qt-static.ps1 -SkipDownload -SkipExtract
```

---

## Étape 3 — Build de l'application

```powershell
.\scripts\03-build-rpgmtranslate.ps1 -QtRoot C:\Qt\static\Qt-6.9.2
```

Si `-QtRoot` est omis, le script cherche Qt automatiquement dans
`QT_ROOT`, `Qt6_DIR`, `C:\Qt\static\*`.

### Ce que fait le script
1. Vérifie CMake ≥ 3.31, Rust ≥ 1.87, cbindgen ≥ 0.29.2.
2. Active l'environnement VS 2022 x64 si `cl.exe` n'est pas sur le PATH.
3. Installe `libarchive:x64-windows-static` via vcpkg si absent.
4. Télécharge `rapidhash.h` si absent (`deps\rapidhash\rapidhash.h`).
5. Configure CMake (Visual Studio 17 2022, x64).
6. Build Release.
7. Vérifie via `dumpbin /dependents` qu'aucune `Qt*.dll` n'est importée
   (confirmation du build 100 % statique).

L'exécutable final est dans :
```
build\target\bin\Release\rpgmtranslate.exe
```

### Paramètres principaux

| Paramètre | Défaut | Description |
|---|---|---|
| `-QtRoot` | auto-détecté | Racine Qt |
| `-BuildDir` | `build` | Répertoire CMake (relatif au dépôt) |
| `-BuildType` | `Release` | `Release` ou `Debug` |
| `-VcpkgRoot` | env var / auto | Racine vcpkg |
| `-RapidHashDir` | `deps\rapidhash` | Emplacement de `rapidhash.h` |
| `-Fresh` | — | Supprime le build dir avant de reconfigurer |
| `-SkipDependencyCheck` | — | Ne pas exécuter dumpbin |

---

## Conseils

- La politique d'exécution PowerShell doit autoriser les scripts locaux :
  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
  ```
- Lancer depuis un **x64 Native Tools Command Prompt for VS 2022** est
  recommandé mais pas obligatoire : les scripts activent l'environnement
  VS automatiquement si `cl.exe` est absent du PATH.
- Le triplet `x64-windows-static` pour LibArchive garantit la cohérence
  avec `CMAKE_MSVC_RUNTIME_LIBRARY = "MultiThreaded"` du `CMakeLists.txt`
  (runtime `/MT`). Ne pas utiliser `x64-windows` (runtime `/MD`).
