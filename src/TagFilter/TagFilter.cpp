#include "TagFilter.hpp"

#include <QRegularExpression>

// --- Built-in VisuStella MZ patterns ---

// Matches <br> and <line break> (case-insensitive), replaced with \n.
auto TagFilter::builtinNewlinePattern() -> const QRegularExpression& {
    static const QRegularExpression re(
        uR"(<(?:br|line break)>)"_s,
        QRegularExpression::CaseInsensitiveOption
    );
    return re;
}

// Matches all remaining VisuStella MZ formatting tags:
//   \CMD[arg]          - e.g. \V[1], \C[2], \I[5], \FS[24], \OC[3]
//   \CMD<arg>          - e.g. \Effect<Swing>, \NameBoxWindow<Name>
//   \CMD               - e.g. \G, \{, \}, bare letter commands
//   <tag> / </tag>     - e.g. <b>, </b>, <i>, <WordWrap>, <Align:center>
// Note: <br> and <line break> must be substituted first (above).
auto TagFilter::builtinStripPattern() -> const QRegularExpression& {
    static const QRegularExpression re(
        uR"(\\[A-Z]+(?:\[[\w,. ]*\]|<[^>]*>)?|<\/?[A-Za-z][^>]*>)"_s,
        QRegularExpression::CaseInsensitiveOption
    );
    return re;
}

// --- Replacement helpers ---

static auto replacementFor(
    const TagRule& rule,
    const QRegularExpressionMatch& /*match*/
) -> QString {
    switch (rule.replacement) {
        case TagReplacementMode::Remove:
            return {};
        case TagReplacementMode::Space:
            return u" "_s;
        case TagReplacementMode::Newline:
            return u"\n"_s;
        case TagReplacementMode::Custom:
            return rule.customReplacement;
    }
    return {};
}

// --- Public API ---

auto TagFilter::apply(
    const QString& text,
    const QList<TagRule>& customRules
) -> QString {
    QString result = text;

    // 1. Apply custom rules in order
    for (const TagRule& rule : customRules) {
        if (!rule.enabled || rule.pattern.isEmpty()) {
            continue;
        }

        if (rule.isRegex) {
            QRegularExpression::PatternOptions opts =
                QRegularExpression::NoPatternOption;
            if (!rule.caseSensitive) {
                opts |= QRegularExpression::CaseInsensitiveOption;
            }
            const QRegularExpression re(rule.pattern, opts);
            if (!re.isValid()) {
                continue;
            }
            const QString repl = [&rule]() -> QString {
                switch (rule.replacement) {
                    case TagReplacementMode::Remove:  return {};
                    case TagReplacementMode::Space:   return u" "_s;
                    case TagReplacementMode::Newline: return u"\n"_s;
                    case TagReplacementMode::Custom:  return rule.customReplacement;
                }
                return {};
            }();
            result = result.replace(re, repl);
        } else {
            // Exact-match (literal string replacement)
            const Qt::CaseSensitivity cs = rule.caseSensitive
                ? Qt::CaseSensitive
                : Qt::CaseInsensitive;
            const QString repl = [&rule]() -> QString {
                switch (rule.replacement) {
                    case TagReplacementMode::Remove:  return {};
                    case TagReplacementMode::Space:   return u" "_s;
                    case TagReplacementMode::Newline: return u"\n"_s;
                    case TagReplacementMode::Custom:  return rule.customReplacement;
                }
                return {};
            }();
            result = result.replace(rule.pattern, repl, cs);
        }
    }

    // 2. Built-in: replace <br> / <line break> with newline
    result = result.replace(builtinNewlinePattern(), u"\n"_s);

    // 3. Built-in: strip all remaining VisuStella MZ formatting tags
    result = result.replace(builtinStripPattern(), {});

    return result;
}
