# Changelog

## v1.0.0-rc.5

This release candidate introduces asset inspector support. Next release candidate will further improve user experience and correct some parts of the program. Git client will be implemented in the final v1.0.0 release.

### Changes

- Updated to `rvpacker-txt-rs-lib` v12.1.0:
    - Fix EOF parsing bug: flush final translation section in initialize_translation by @CreepsoOff
    - Changed `generate_file` function in `json` module to also accept filename argument, and have a special case for `Scripts` files.
    - Added `set_game_title` argument to `Reader` for compatibility with RPG Maker XP/VX/VXAce. This allows user to manually decode game title from Game.ini file and pass it here as UTF-8, since system file not always contains game title.
    - Documentation fixes.
- Fixed wrong extraction of encrypted archives which resulted in an unreadable project.
- When reading RPG Maker XP/VX/VXAce projects, read menu will now have option to use the game title from Game.ini file. Since Game.ini is not necessarily UTF-8 encoded, this allows user to manually find the encoding and use correct game title.
- Fixed possible panics on read.
- Added information about libarchive, libgit2 and FFmpeg to about window.
- Fixed clipping text in tab panel items.
- Massively improved documentation.
- Implemented asset inspector: currently supports browsing through images, audio, video, scripts, and inspecting each of those, along with media player, syntax highligthing and more.

## v1.0.0-rc.4

A couple more fixes.

### Changes

- Fixed outputting none/not all files when writing.
- Fixed possible crash when applying batch translation. Still requires more testing.
- Fixed absolutely idiotic issue, where the application would batch translate all maps, that end with the number of the selected map. For example, if map1 is selected, application would try to batch translate all other maps, that end with 1 (e.g. map11, map21, map31 etc.).
- Fixed possible crash when getting error while opening/reading the project or aborting the read.
- To avoid losing project settings and glossary in result of program abort, each backup will also save project settings and glossary.
- To avoid losing settings in result of program abort, settings will be saved when closing settings window.

## v1.0.0-rc.3

A couple of fixes.

### Changes

- Fixed undefined behavior when processing hashes on read which would lead to unexpected side effects, such as wrong engine being recognized.
- Fixed base URL validation in settings.
- Fixed outputting write results to `.rpgmtranslate/.rpgmtranslate/output` instead of `.rpgmtranslate/output`.
- Fixed possible panic when tinkering with options in settings window.
- Changed some checkboxes in settings window to show "custom" label instead of "enabled".
- Added description for endpoint list.
- Added description of different endpoint types.

## v1.0.0-rc.2

The second release candidate implements some scratches for the future features, like git client and asset inspector, along with a couple of fixes. It's expected to be the last release candidate before the final release.

### Changes

- Updated to `rvpacker-txt-rs-lib` v11.2.0.
- Fixed read menu not showing itself when trying to open an unparsed project, which would effectively lead to a complete unability to open a new project using the program.
- Fixed possible deadlock on program startup if `.rpgmtranslate` directory disappears in the saved project.
- Fixed possible empty translation files when parsing the project.
- Fixed leading slash (`/`) in status bar notifications about backups.
- Implemented dictionaries support.
- Fixed multiple translation lints overwriting each other.
- Fixed not shifting row indices in the bookmark menu, when a new bookmark is added.
- Implemented built-in git client.
- Implemented built-in asset inspector.
- Allowed to move dock widgets around.
- Reimplemented tab panel as a dock widget.
- Improved the look of tab panel.
- Added "Locate project directory" button next to the game title.
- Made API key, Yandex folder ID and base URL inputs' contents hidden by default.
- Translation settings rewrite.
- Translations menu overhaul, not complete though.
- Implemented a little bit more of documentation. Not yet finished.
- Overall polishing.

### Note

Git client and asset inspector are not yet fully implemented and usable.

### Coming next

- Replace bare labels in translations menu to scroll areas.
- Finished implementation for git client and asset inspector.
- LanguageTool support;
- More linting (syntax highlighting for Yanfly Message Core, more than two spaces etc.)

## v1.0.0-rc.1

The first release candidate of the rewrite of the original project in C++.

### Changes

- Overall, improved user experience with the application.
- Added tracking of the currently executing tasks, such as batch actions, search and replace.
- No more temporary files. `maps.txt` is parsed to sections and stored in-memory for the duration of the project, while matches are tightly packed into a memory-efficient way, and stored in-memory as long as they're displayed in the search panel.
- Added stubs for LanguageTool and spell check, but those aren't currently implemented.
