#pragma once

#include "Aliases.hpp"

#ifdef ENABLE_NUSPELL
#include <nuspell/dictionary.hxx>

#include <QRegularExpression>
#endif

#include <QSyntaxHighlighter>
#include <QTextCharFormat>

class TranslationHighlighter final : public QSyntaxHighlighter {
    Q_OBJECT

   public:
    explicit TranslationHighlighter(
        bool whitespaceHighlightingEnabled,
#ifdef ENABLE_NUSPELL
        const nuspell::Dictionary* dictionary,
        const bool* dictionaryReady,
#endif
        QTextDocument* document
    );

   protected:
    void highlightBlock(const QString& text) override;

   private:
    QTextCharFormat whitespaceFormat;

#ifdef ENABLE_NUSPELL
    [[nodiscard]] auto isMisspelled(const QString& word) const -> bool;

    QTextCharFormat misspelledFormat;

    const nuspell::Dictionary* const dictionary;
    const bool* const isDictionaryReady;

    static inline const QRegularExpression wordRegex = QRegularExpression(
        uR"(\b[\p{L}']+\b)"_s,
        QRegularExpression::UseUnicodePropertiesOption
    );
#endif

    bool whitespaceHighlightingEnabled;
};
