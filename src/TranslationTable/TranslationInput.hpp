#pragma once

#include "Aliases.hpp"

#include <QPlainTextEdit>

class TranslationInput final : public QPlainTextEdit {
    Q_OBJECT

   public:
    explicit TranslationInput(u16 hint, QWidget* parent = nullptr);

   protected:
    void keyPressEvent(QKeyEvent* event) override;
    void paintEvent(QPaintEvent* event) override;

   signals:
    void contentHeightChanged(i32 height);
    void editingFinished();

   private:
    struct Replacement {
        QL1SV original;
        QStringView replacement;
        i32 position;
    };

    void onTextChanged();
    void updateContentHeight();
    void performAutoReplacements();

    vector<Replacement> lastReplacements;

    u16 lengthHint;

    i32 lastContentHeight = 0;
    bool blockTextChanged = false;
};
