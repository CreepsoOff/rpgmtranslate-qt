#pragma once

#include "Aliases.hpp"
#include "AssetPreviewWidget.hpp"
#include "PersistentMenu.hpp"
#include "ProjectSettings.hpp"

#include <QGraphicsPixmapItem>
#include <QHBoxLayout>
#include <QLineEdit>
#include <QTreeWidget>

class AssetMenu final : public PersistentMenu {
    Q_OBJECT

   public:
    explicit AssetMenu(QWidget* parent = nullptr);

    void init(shared_ptr<ProjectSettings> projectSettings);
    void clear();

   private:
    static auto applyFilter(QTreeWidgetItem* item, const QString& lowerFilter)
        -> bool;

    void filterTree(const QString& text);
    void refresh();

    AssetPreviewWidget assetPreviewWidget;
    QVBoxLayout layout = QVBoxLayout(this);
    QLineEdit searchInput = QLineEdit(this);
    QTreeWidget tree = QTreeWidget(this);
    QGraphicsScene graphicsScene = QGraphicsScene(this);

    shared_ptr<ProjectSettings> projectSettings;
};
