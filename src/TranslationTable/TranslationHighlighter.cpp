#include "TranslationHighlighter.hpp"

#include <QColor>

TranslationHighlighter::TranslationHighlighter(
    const bool whitespaceHighlightingEnabled,
#ifdef ENABLE_NUSPELL
    const nuspell::Dictionary* const dictionary,
    const bool* const dictionaryReady,
#endif
    QTextDocument* const document
) :
    QSyntaxHighlighter(document),
    whitespaceHighlightingEnabled(whitespaceHighlightingEnabled)
#ifdef ENABLE_NUSPELL
    ,
    dictionary(dictionary),
    isDictionaryReady(dictionaryReady)
#endif
{
    whitespaceFormat.setBackground(QColor(255, 0, 0, 80));

#ifdef ENABLE_NUSPELL
    misspelledFormat.setUnderlineStyle(QTextCharFormat::SpellCheckUnderline);
    misspelledFormat.setUnderlineColor(Qt::red);
#endif
}

// TODO: Syntax highlighting for some Yanfly Message Core sequences
// TODO: Syntax highlighting for more than two spaces
// TODO: Store information about the highlighted sections
void TranslationHighlighter::highlightBlock(const QString& text) {
    if (whitespaceHighlightingEnabled) {
        const i32 size = i32(text.size());

        if (size > 0) {
            i32 lead = 0;
            while (lead < size && text.at(lead).isSpace()) {
                lead++;
            }

            if (lead > 0) {
                setFormat(0, lead, whitespaceFormat);
            }

            i32 lastNonSpace = size - 1;
            while (lastNonSpace >= 0 && text.at(lastNonSpace).isSpace()) {
                lastNonSpace--;
            }

            const i32 trailStart = lastNonSpace + 1;
            const i32 trailLen = size - trailStart;

            if (trailLen > 0 && trailStart >= lead) {
                setFormat(trailStart, trailLen, whitespaceFormat);
            }
        }
    }

#ifdef ENABLE_NUSPELL
    if (dictionary == nullptr || isDictionaryReady == nullptr ||
        !*isDictionaryReady) {
        return;
    }

    const auto matches = wordRegex.globalMatchView(text);

    for (const auto& match : matches) {
        const QString word = match.captured();

        if (isMisspelled(word)) {
            setFormat(
                i32(match.capturedStart()),
                i32(match.capturedLength()),
                misspelledFormat
            );
        }
    }
#endif
}

#ifdef ENABLE_NUSPELL
auto TranslationHighlighter::isMisspelled(const QString& word) const -> bool {
    const QByteArray utf8Word = word.toUtf8();
    return !dictionary->spell(
        std::string_view(utf8Word.data(), utf8Word.size())
    );
}
#endif
