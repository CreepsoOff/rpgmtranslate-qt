#pragma once

#include <QLabel>

class ClickableLabel final : public QLabel {
    Q_OBJECT

   public:
    using QLabel::QLabel;

   signals:
    void clicked();

   protected:
    void mousePressEvent(QMouseEvent* const event) override {
        emit clicked();
        QLabel::mousePressEvent(event);
    };
};
