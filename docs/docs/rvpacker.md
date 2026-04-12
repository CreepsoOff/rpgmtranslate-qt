# Rvpacker features

`rvpacker-txt-rs` is responsible for reading the text from the RPG Maker games and writing it back. Its features are accessible through `rv` button. It includes three main features.

## Read

Read is the crucial part of translating. It defines, how game text will be parsed.

All read settings are self-descriptive, you can analyze them in the interface.

## Write

Write is accessible through the write button. It just writes the translation back to game files.

## Purge

Purge gets rid of the untranslated lines, and optionally creates `.rvpacker-ignore` file to prevent those lines appearing again after read.
