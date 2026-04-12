#pragma once

#include "Aliases.hpp"
#include "Settings.hpp"

#include <QList>
#include <QString>

// Applies visual tag filtering for preview mode.
// Source text is never modified — this is purely a display transform.
class TagFilter {
   public:
    TagFilter() = delete;

    // Apply custom rules first (in order), then built-in VisuStella MZ patterns.
    [[nodiscard]] static auto apply(
        const QString& text,
        const QList<TagRule>& customRules
    ) -> QString;

   private:
    // <br> / <line break> → newline
    [[nodiscard]] static auto builtinNewlinePattern()
        -> const QRegularExpression&;

    // Strip all remaining VisuStella MZ formatting tags
    [[nodiscard]] static auto builtinStripPattern()
        -> const QRegularExpression&;
};
