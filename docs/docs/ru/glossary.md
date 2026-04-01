# Функции CAT и глоссарий

RPGMTranslate предоставляет некоторые функции [CAT](https://ru.wikipedia.org/wiki/%D0%90%D0%B2%D1%82%D0%BE%D0%BC%D0%B0%D1%82%D0%B8%D0%B7%D0%B8%D1%80%D0%BE%D0%B2%D0%B0%D0%BD%D0%BD%D1%8B%D0%B9_%D0%BF%D0%B5%D1%80%D0%B5%D0%B2%D0%BE%D0%B4).

## Глоссарий

Меню глоссария содержит все представленные в переводе термины, позволяет добавлять новые и проверять консистенцию.

Вы можете создавать новые термины кнопкой "+". Термин и его перевод необходимы.

Глоссарий позволяет искать определённые термины и предоставляет кнопку `QC` для проверки качества: она проверит сходства всего текста в файлах, выбранных в меню файлов.

Инфлексии не поддерживаются.

### Настройки термина/перевода

#### Режим

Режим определяет, как проверять сходства текста:

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
