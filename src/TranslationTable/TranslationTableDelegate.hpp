#pragma once

#include "Aliases.hpp"
#include "FWD.hpp"
#include "Settings.hpp"

#ifdef ENABLE_NUSPELL
#include <nuspell/dictionary.hxx>
#endif

#include <QList>
#include <QStyledItemDelegate>

class TranslationTableDelegate final : public QStyledItemDelegate {
    Q_OBJECT

   public:
    explicit TranslationTableDelegate(QObject* parent = nullptr);

#ifdef ENABLE_NUSPELL
    [[nodiscard]] auto initializeDictionary() -> result<void, QString>;
#endif

    void init(
        const u16* const hint,
        const bool* const enabled,
        const QString* const dictionaryPath
    ) {
        lengthHint = hint;
        this->whitespaceHighlightingEnabled = enabled;
        this->dictionaryPath = dictionaryPath;
    }

    void initPreview(
        const bool* const previewEnabled,
        const QList<TagRule>* const customRules
    ) {
        previewTagsEnabled_ = previewEnabled;
        customTagRules_ = customRules;
    }

    void setText(const QString& text);
    auto createEditor(
        QWidget* parent,
        const QStyleOptionViewItem& option,
        const QModelIndex& index
    ) const -> QWidget* override;
    void
    setEditorData(QWidget* editor, const QModelIndex& index) const override;
    void setModelData(
        QWidget* editor,
        QAbstractItemModel* model,
        const QModelIndex& index
    ) const override;
    [[nodiscard]] auto sizeHint(
        const QStyleOptionViewItem& option,
        const QModelIndex& index
    ) const -> QSize override;
    void paint(
        QPainter* painter,
        const QStyleOptionViewItem& option,
        const QModelIndex& index
    ) const override;
    auto eventFilter(QObject* editor, QEvent* event) -> bool override;

   signals:
    void inputFocused();
    void textChanged(const QString& text);

   private:
#ifdef ENABLE_NUSPELL
    mutable nuspell::Dictionary dictionary;
    mutable bool dictionaryReady;
#endif

    static constexpr u8 PAD_X = 4;
    static constexpr u8 PAD_Y = 4;

    const u16* lengthHint;
    const bool* whitespaceHighlightingEnabled;
    const QString* dictionaryPath;

    const bool* previewTagsEnabled_ = nullptr;
    const QList<TagRule>* customTagRules_ = nullptr;

    mutable QPlainTextEdit* activeInput = nullptr;
    mutable u32 activeRow;
};
