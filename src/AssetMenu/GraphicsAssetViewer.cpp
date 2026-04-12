#include "GraphicsAssetViewer.hpp"

#include "Aliases.hpp"

#include <QWheelEvent>

void GraphicsAssetViewer::wheelEvent(QWheelEvent* const event) {
    const f32 scaleFactor = 1.15F;

    if (event->angleDelta().y() > 0) {
        scale(scaleFactor, scaleFactor);
    } else {
        scale(1.0F / scaleFactor, 1.0F / scaleFactor);
    }
}
