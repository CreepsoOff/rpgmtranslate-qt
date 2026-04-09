# Build Plan (Windows Static)

## Goal
Build a static `rpgmtranslate.exe` on Windows using:
- Qt 6.11.0 static (MSVC static runtime)
- VS Build Tools 2026 (x64 toolchain shell)
- CMake 3.31.11
- clang-cl for app build
- vcpkg static `libarchive`

## Locked Constraints
- Only `custom_scripts/01-check-prerequisites.ps1`, `custom_scripts/02-build-qt-static.ps1`, `custom_scripts/03-build-rpgmtranslate.ps1` are modified.
- Upstream files are untouched (`CMakeLists.txt`, `configure.ps1`, `src/utilities/Aliases.hpp`).

## Script Changes Implemented
1. `custom_scripts/01-check-prerequisites.ps1`
- Strict CMake `3.31.11` enforcement + blocking recheck.
- vcpkg resolution order: `VCPKG_ROOT -> C:\vcpkg -> F:\vcpkg`.
- If no vcpkg found: manual path / auto-install `F:\vcpkg` / skip.

2. `custom_scripts/02-build-qt-static.ps1`
- Qt submodules include `qtsvg`.
- Detect incomplete previous build and fully clean build dir before configure.
- Disable Qt Assistant feature (`-no-feature-assistant`) to avoid assistant/help failure path.
- Strict post-install checks:
  - `bin\qmake.exe`
  - `lib\cmake\Qt6Svg\`
  - `lib\cmake\Qt6LinguistTools\`

3. `custom_scripts/03-build-rpgmtranslate.ps1`
- `VcpkgRoot` resolution:
  - explicit param validation
  - else `VCPKG_ROOT -> C:\vcpkg -> F:\vcpkg`
  - else prompt manual path
- Prints resolved vcpkg path before configure.

## Current Status
- CMake: `3.31.11` active.
- vcpkg: `C:\vcpkg` detected, `libarchive:x64-windows-static` present.
- Qt configure (with current flags): succeeds on clean build dir.
- Full Qt build still failing during long run (see log below).

## Logs
- Qt build log:
  - `custom_scripts/qt-build.log`
  - Absolute path: `F:\Desktop\rpgmtranslate-qt\custom_scripts\qt-build.log`

## Next Steps
1. Inspect latest terminal failure in `qt-build.log` and adjust Qt flags if needed.
2. Re-run `custom_scripts/02-build-qt-static.ps1` from VS 2026 x64 shell.
3. Run `custom_scripts/03-build-rpgmtranslate.ps1`.
4. Validate final exe dependencies with `dumpbin /dependents`.
