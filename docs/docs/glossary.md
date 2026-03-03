# CAT Features and Glossary

RPGMTranslate introduces some [CAT](https://en.wikipedia.org/wiki/Computer-assisted_translation) features.

## Glossary

Glossary menu contains all the present terms in your translation, allows you to add new, and check the consistensy of those terms.

You can create new terms with the "+" button. Term and translation text are essential.

Glossary allows to search specific terms, and provides a `QC` button to start a quality check: this will match all the text in the files, selected in the file select menu with all the terms.

Inflections are not supported.

### Term/translation settings

#### Mode

Mode defines, how to match the text:

- Exact - only matches the text exactly.
- Fuzzy - only matches the text fuzzily, using a supplied threshold.
- Both - matches the text both exactly and fuzzily, in order.

#### Case sensitivity

If enabled, matches text case-sensitively. Else, case-insensitively.

#### Permissive

If enabled, also matches the text, that's more uppercased than the term, but not more lowercased.

### Note

All the info related to the term and its translation.

### Actions

- Edit: Glossary entries are uneditable by default.
- Remove: Remove the glossary entry.
- Match: Matches the text in the files, selected in the file select menu with the term.

## Match Menu

Results of the text matching are placed in a dedicated menu: match menu. You can access the menu using the button next to the glossary button.

By default, match menu is docked to the bottom side of the screen. It can be undocked and made floating.

### Columns

- File: the file of the matched result.
- Row: the row of the matched result.
- Term: shows the term, its occurrences, and translation occurrences.
- Result: shows the highlighted term in the text.
- Info: the info about the match (e.g. term is not present, translation is not present etc.).
