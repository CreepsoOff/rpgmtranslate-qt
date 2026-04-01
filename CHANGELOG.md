# Changelog

## v1.0.0-rc.2

The second release candidate implements some scratches for the future features, like git client and asset inspector, along with a couple of fixes. It's expected to be the last release candidate before the final release.

### Changes

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
