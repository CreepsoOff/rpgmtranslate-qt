# Text Editing

## Translation Table

When you open a tab, translation table with the content of the tab will be built.

## Translation Input

By double-clicking or single-clicking and pressing a keyboard button on a cell in a translation column, you can trigger editing of the cell. While you're editing it, depending on the enabled options, such as row length hint, whitespace highlighting, spell-check, corresponding decorations will be shown.

## Auto-translation

If you configured the endpoints for [single-translation](./settings.md#translation), they will be used to translate the source text corresponding to the edited translation cell.

## LanguageTool

If you configured the [LanguageTool](./settings.md#languagetool), LanguageTool will be used to lint the translation text.

## Spell-check

An archive the following spell-check dictionaries is supplied with each build of the program:

- English (US)
- German
- Spanish
- Portuguese (Brazilian)
- Italian
- French
- Russian
- Turkish

For any other language, you need to use your own dictionary. More on how to do it is **WIP**.

If spell-check is enabled in translation settings, it will be automatically used when translation input is edited.

## Keyboard Shortcuts

- Shift + ArrowDown - Move to next row (down)
- Shift + ArrowUp - Move to previous row (up)
- Shift + ArrowLeft - Move to the left translation column
- Shift + ArrowRight - Move to the right translation column
- Ctrl + ArrowUp - Move to the top-most row
- Ctrl + ArrowDown - Move to the bottom-most row
- Left-click on source text - Copy the source text

## Batch Select

You can select multiple translation cells by clicking one of them and extending the selection by holding Shift and clicking the other one.

Batch copy/cut/paste is supported.

## Batch Text Processing

Access it through the "Tools" button.

[Documentation on batch processing](./batch-processing.md)
