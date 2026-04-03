#pragma once

#include "Aliases.hpp"
#include "UnfocusLineEdit.hpp"
#include "Utils.hpp"

#include <QCheckBox>
#include <QHBoxLayout>
#include <QIntValidator>
#include <QLabel>
#include <QLineEdit>
#include <QSignalBlocker>
#include <QSlider>
#include <QWidget>

// CheckBox, Slider and Line Edit
class CBSLIWidget final : public QWidget {
    Q_OBJECT

   public:
    explicit CBSLIWidget(
        const bool checkable = false,
        QWidget* const parent = nullptr
    ) :
        QWidget(parent),
        label_(new QLabel(QString(), this)),
        checkbox_(checkable ? new QCheckBox(tr("Custom"), this) : nullptr),
        slider_(new QSlider(Qt::Horizontal, this)),
        lineEdit_(new UnfocusLineEdit(this)) {
        lineEdit_->setAlignment(Qt::AlignRight);

        auto* const layout = new QHBoxLayout(this);
        layout->setContentsMargins(0, 0, 0, 0);
        layout->addWidget(label_);

        if (checkable) {
            layout->addWidget(checkbox_);
        }

        layout->addWidget(slider_, 1);
        layout->addWidget(lineEdit_);

        connect(
            slider_,
            &QSlider::valueChanged,
            this,
            &CBSLIWidget::onSliderValueChanged
        );

        connect(
            lineEdit_,
            &UnfocusLineEdit::editingFinished,
            this,
            &CBSLIWidget::onEditCommitted
        );

        connect(
            lineEdit_,
            &UnfocusLineEdit::returnPressed,
            this,
            &CBSLIWidget::onEditCommitted
        );
    }

    void setCheckable(const bool checkable) {
        if (checkable) {
            if (checkbox_ != nullptr) {
                return;
            }

            checkbox_ = new QCheckBox(tr("Custom"), this);
            as<QHBoxLayout*>(layout())->insertWidget(1, checkbox_);
        } else {
            delete checkbox_;
            checkbox_ = nullptr;
        }
    }

    void setLabel(const QString& label) { label_->setText(label); }

    void setChecked(const bool checked) { checkbox_->setChecked(checked); }

    void setRange(const f32 floatMin, const f32 floatMax) {
        const i32 minimum = i32(floatMin * FLOAT_FACTOR);
        const i32 maximum = i32(floatMax * FLOAT_FACTOR);

        floatFormat = true;
        slider_->setRange(minimum, maximum);

        lineEdit_->setValidator(
            new QDoubleValidator(floatMin, floatMax, 3, lineEdit_)
        );
        lineEdit_->setMaxLength(intLen(i32(floatMax)) + 1 + 3);

        setValue(clamp(minimum, value<i32>(), maximum));
    }

    void setRange(const i32 minimum, const i32 maximum) {
        floatFormat = false;
        slider_->setRange(minimum, maximum);

        lineEdit_->setValidator(new QIntValidator(minimum, maximum, lineEdit_));
        lineEdit_->setMaxLength(intLen(maximum));

        setValue(clamp(minimum, value<i32>(), maximum));
    }

    void setValue(i32 value) {
        value = clamp(slider_->minimum(), value, slider_->maximum());

        {
            QSignalBlocker blocker(slider_);
            slider_->setValue(value);
        }

        {
            QSignalBlocker blocker(lineEdit_);
            lineEdit_->setText(
                floatFormat
                    ? QString::number(f32(value) / FLOAT_FACTOR, u'f', 3)
                    : QString::number(value)
            );
        }

        emit valueChanged(value);
    }

    void setValue(f32 floatVal) {
        i32 value = i32(floatVal * FLOAT_FACTOR);

        value = clamp(slider_->minimum(), value, slider_->maximum());

        {
            QSignalBlocker blocker(slider_);
            slider_->setValue(value);
        }

        {
            QSignalBlocker blocker(lineEdit_);
            lineEdit_->setText(
                floatFormat
                    ? QString::number(f32(value) / FLOAT_FACTOR, u'f', 3)
                    : QString::number(value)
            );
        }

        emit valueChanged(value);
    }

    [[nodiscard]] auto isChecked() const -> bool {
        return checkbox_ == nullptr ? true : checkbox_->isChecked();
    }

    template <typename T = i32>
        requires std::is_arithmetic_v<T>
    [[nodiscard]] auto value() const -> T {
        if constexpr (std::is_floating_point_v<T>) {
            return f32(slider_->value()) / FLOAT_FACTOR;

        } else {
            return slider_->value();
        }
    }

    [[nodiscard]] auto label() const -> QLabel* { return label_; }

    [[nodiscard]] auto slider() const -> QSlider* { return slider_; }

    [[nodiscard]] auto lineEdit() const -> UnfocusLineEdit* {
        return lineEdit_;
    }

   signals:
    void valueChanged(i32 value);

   private:
    void onSliderValueChanged(const i32 value) {
        QSignalBlocker blocker(lineEdit_);
        lineEdit_->setText(
            floatFormat ? QString::number(f32(value) / FLOAT_FACTOR, u'f', 3)
                        : QString::number(value)
        );
        emit valueChanged(value);
    }

    void onEditCommitted() {
        bool correct = false;
        i32 value;

        if (floatFormat) {
            const f32 dbl = f32(lineEdit_->text().toDouble(&correct));
            value = i32(dbl * FLOAT_FACTOR);
        } else {
            value = lineEdit_->text().toInt(&correct);
        }

        if (!correct) {
            QSignalBlocker blocker(lineEdit_);
            lineEdit_->setText(
                floatFormat ? QString::number(
                                  f32(slider_->value()) / FLOAT_FACTOR,
                                  u'f',
                                  3
                              )
                            : QString::number(slider_->value())
            );
            return;
        }

        value = clamp(slider_->minimum(), value, slider_->maximum());
        setValue(value);
    }

    static constexpr u16 FLOAT_FACTOR = 1000;

    QLabel* const label_;
    QCheckBox* checkbox_;
    QSlider* const slider_;
    UnfocusLineEdit* const lineEdit_;

    bool floatFormat = false;
};