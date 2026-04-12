#pragma once

#include <QGraphicsView>

class GraphicsAssetViewer final : public QGraphicsView {
   public:
    using QGraphicsView::QGraphicsView;

   protected:
    void wheelEvent(QWheelEvent* event) override;
};