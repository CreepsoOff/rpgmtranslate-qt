#pragma once

#include "Aliases.hpp"
#include "Enums.hpp"
#include "PersistentMenu.hpp"
#include "ProjectSettings.hpp"

#include <QDir>
#include <QDirListing>
#include <QGraphicsPixmapItem>
#include <QGraphicsView>
#include <QHBoxLayout>
#include <QLabel>
#include <QTreeWidget>
#include <QWheelEvent>
#include <QWidget>

// TODO: Asset search
class GraphicsAssetView final : public QGraphicsView {
   public:
    using QGraphicsView::QGraphicsView;

   protected:
    void wheelEvent(QWheelEvent* const event) override {
        const f32 scaleFactor = 1.15F;

        if (event->angleDelta().y() > 0) {
            scale(scaleFactor, scaleFactor);
        } else {
            scale(1.0F / scaleFactor, 1.0F / scaleFactor);
        }
    }
};

class AssetMenu final : public PersistentMenu {
    Q_OBJECT

   public:
    explicit AssetMenu(QWidget* const parent = nullptr) :
        PersistentMenu(parent) {
        tree.setUniformRowHeights(true);
        tree.setHeaderHidden(true);
        tree.setSelectionMode(QTreeWidget::SingleSelection);
        tree.setEditTriggers(QTreeWidget::NoEditTriggers);
        tree.setDragDropMode(QTreeWidget::NoDragDrop);
        tree.setAcceptDrops(false);

        layout.addWidget(&tree);
        setLayout(&layout);

        graphicsAssetView.setDragMode(QGraphicsView::ScrollHandDrag);
        graphicsAssetView.setTransformationAnchor(
            QGraphicsView::AnchorUnderMouse
        );
        graphicsAssetView.setResizeAnchor(QGraphicsView::AnchorUnderMouse);
        graphicsAssetView.setRenderHints(
            QPainter::Antialiasing | QPainter::SmoothPixmapTransform
        );

        connect(
            &tree,
            &QTreeWidget::itemClicked,
            this,
            [this](const QTreeWidgetItem* const item, const i32 column)
                -> void {
            const QString path = item->data(0, Qt::UserRole).toString();

            if (path.isEmpty()) {
                return;
            }

            // TODO: Based on type, display correctly
        }
        );
    };

    void init(shared_ptr<ProjectSettings> projectSettings) {
        this->projectSettings = std::move(projectSettings);
        refresh();
    };

    void clear() {
        tree.clear();
        graphicsScene.clear();
    }

   private:
    void refresh() {
        clear();

        if (!projectSettings) {
            return;
        }

        const bool isNew = projectSettings->engineType == EngineType::New;
        const QString& base = projectSettings->projectPath;

        auto* const audioItem = new QTreeWidgetItem(&tree, { tr("Audio") });
        auto* const imagesItem = new QTreeWidgetItem(&tree, { tr("Images") });
        auto* const iconsItem = new QTreeWidgetItem(&tree, { tr("Icons") });
        auto* const fontsItem = new QTreeWidgetItem(&tree, { tr("Fonts") });

        auto* const moviesItem = new QTreeWidgetItem(&tree, { tr("Movies") });
        QTreeWidgetItem* jsItem = nullptr;

        if (isNew) {
            jsItem = new QTreeWidgetItem(&tree, { tr("JS") });
        }

        const QSVList audioExts =
            isNew ? QSVList{ u"ogg_", u"m4a_", u"rpgmvo", u"rpgmvm" }
                  : QSVList{ u"ogg", u"m4a" };

        const QSVList imageExts =
            isNew ? QSVList{ u"png_", u"rpgmvp" } : QSVList{ u"png", u"jpg" };

        const QSVList videoExts =
            isNew ? QSVList{ u"webm", u"mp4" } : QSVList{ u"ogv" };

        const QSVList fontExts = { u"ttf", u"otf" };
        const QSVList jsExts = { u"js" };

        const auto toNameFilters = [](const QSVList& exts) -> QStringList {
            QStringList filters;
            filters.reserve(exts.size());

            for (const QStringView ext : exts) {
                filters.append(u"*."_s + ext);
            }

            return filters;
        };

        const auto populate = [&toNameFilters](
                                  QTreeWidgetItem* const parent,
                                  const QString& dirPath,
                                  const QSVList& exts
                              ) -> void {
            if (parent == nullptr || dirPath.isEmpty() ||
                !QFile::exists(dirPath)) {
                return;
            }

            const auto listing = QDirListing(
                dirPath,
                toNameFilters(exts),
                QDirListing::IteratorFlag::Recursive |
                    QDirListing::IteratorFlag::FilesOnly
            );

            for (const auto& entry : listing) {
                auto* const item =
                    new QTreeWidgetItem(parent, { entry.fileName() });

                item->setData(0, Qt::UserRole, entry.filePath());
            }
        };

        const bool wwwExists = QFile::exists(base + u"/www");

        if (isNew) {
            populate(
                audioItem,
                base + (wwwExists ? u"/www/audio" : u"/audio"),
                audioExts
            );
            populate(
                imagesItem,
                base + (wwwExists ? u"/www/img" : u"/img"),
                imageExts
            );
            populate(
                iconsItem,
                base + (wwwExists ? u"/www/icon" : u"/icon"),
                imageExts
            );
            populate(
                moviesItem,
                base + (wwwExists ? u"/www/movies" : u"/movies"),
                videoExts
            );
            populate(
                fontsItem,
                base + (wwwExists ? u"/www/fonts" : u"/fonts"),
                fontExts
            );
            populate(jsItem, base + (wwwExists ? u"/www/js" : u"/js"), jsExts);
        } else {
            populate(audioItem, base + u"/Audio", audioExts);
            populate(imagesItem, base + u"/Graphics", imageExts);
            populate(moviesItem, base + u"/Movies", videoExts);
        }
    };

    void loadGraphicsAsset(const QString& path) {
        // TODO: Decrypt encrypted
        QPixmap assetPixmap;
        assetPixmap.load(path);

        const auto* const item = graphicsScene.addPixmap(assetPixmap);

        graphicsAssetView.fitInView(item, Qt::KeepAspectRatio);
        graphicsAssetView.show();
    }

    QHBoxLayout layout;
    QTreeWidget tree;
    QGraphicsScene graphicsScene;
    GraphicsAssetView graphicsAssetView;

    shared_ptr<ProjectSettings> projectSettings;
};