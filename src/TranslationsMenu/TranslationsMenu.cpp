#include "TranslationsMenu.hpp"

#include "ClickableLabel.hpp"
#include "PersistentMenu.hpp"
#include "Settings.hpp"

#include <QLabel>
#include <QMouseEvent>
#include <QVBoxLayout>

// TODO: Allow to resize this menu and implement translation widgets as
// scrollable wrapping labels

TranslationsMenu::TranslationsMenu(QWidget* const parent) :
    PersistentMenu(parent, Qt::FramelessWindowHint),
    layout(new QVBoxLayout(this)),
    translationsWidget(new QWidget(this)),
    translationsLayout(new QVBoxLayout(translationsWidget)) {
    setDragMoveEnabled(true);

    layout->addWidget(new QLabel(tr("Translations Menu"), this));
    layout->addWidget(translationsWidget);

    layout->setContentsMargins(8, 8, 8, 8);
    layout->setSpacing(8);

    translationsLayout->setContentsMargins(0, 0, 0, 0);
    translationsLayout->setSpacing(8);

    layout->setSizeConstraint(QLayout::SetFixedSize);
}

void TranslationsMenu::showTranslations(
    const vector<QString>& translations,
    const shared_ptr<Settings>& settings
) {
    clear();

    for (const auto& [idx, translation] : views::enumerate(translations)) {
        const QString& name = settings->translation.endpoints[idx].name;

        auto* const translationWidget = new QWidget(this);
        auto* const translationWidgetLayout =
            new QVBoxLayout(translationWidget);

        translationWidgetLayout->setContentsMargins(0, 0, 0, 0);
        translationWidgetLayout->setSpacing(4);

        auto* const translationLabel =
            new ClickableLabel(translation, translationWidget);
        translationLabel->setCursor(QCursor(Qt::PointingHandCursor));

        translationWidgetLayout->addWidget(new QLabel(name, translationWidget));
        translationWidgetLayout->addWidget(translationLabel);

        connect(
            translationLabel,
            &ClickableLabel::clicked,
            this,
            [this, translationLabel] -> void {
            emit translationClicked(translationLabel->text());
        }
        );

        translationsLayout->addWidget(translationWidget);
    }
};

void TranslationsMenu::showError(const QString& error) {
    clear();
    translationsLayout->addWidget(new QLabel(error, this));
};

void TranslationsMenu::clear() {
    while (const auto* const item = translationsLayout->takeAt(0)) {
        delete item->widget();
        delete item;
    }
};
