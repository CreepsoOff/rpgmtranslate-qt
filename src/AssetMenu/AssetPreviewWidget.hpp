#pragma once

#include "Aliases.hpp"
#include "CodeViewer.hpp"
#include "GraphicsAssetViewer.hpp"

#ifdef ENABLE_ASSET_PLAYBACK
#include "MediaPlayer.hpp"
#endif

#include <QGraphicsScene>
#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QStackedWidget>
#include <QString>
#include <QVBoxLayout>
#include <QWidget>

// TODO: JS/Ruby beautifier. Claude should vibe-code it so I don't have to
// suffer

class AssetPreviewWidget final : public QWidget {
    Q_OBJECT

   public:
    explicit AssetPreviewWidget(QWidget* parent = nullptr);
    ~AssetPreviewWidget() override;

    void showAsset(const QString& path);
    void clear();

   private:
    enum class Page : u8 {
        Error,
        Graphics,
        Media,
        Text,
    };

    void showPage(Page page, const QString& error = QString());

    void loadGraphicsAsset(const QString& path);
    void loadFontAsset(const QString& path);
    void loadAudioAsset(const QString& path);
    void loadVideoAsset(const QString& path);
    void loadTextAsset(const QString& path);

    constexpr static u8 HEADER_LENGTH = 16;

#ifdef ENABLE_ASSET_PLAYBACK
    MediaPlayer mediaPlayer;
#endif

    CodeViewer codeViewer;

    QStackedWidget stack = QStackedWidget(this);

    QLabel errorLabel;
    QLabel supportedWritingSystemsLabel;

    QWidget toolbar = QWidget(this);
    QPushButton locateButton = QPushButton(tr("Locate file"), &toolbar);
    QPushButton openButton = QPushButton(tr("Open in default app"), &toolbar);
    QPushButton beautifyButton = QPushButton(tr("Beautify"), &toolbar);

    QHBoxLayout toolbarLayout = QHBoxLayout(&toolbar);
    QVBoxLayout mainLayout = QVBoxLayout(this);

    QString currentPath;
    QString lastTempFile;

    QByteArray codeUtf8;

    QGraphicsScene graphicsScene;
    GraphicsAssetViewer graphicsViewer;

#if defined(ENABLE_JSON_HIGHLIGHTING) || defined(ENABLE_JS_HIGHLIGHTING) || \
    defined(ENABLE_RUBY_HIGHLIGHTING)
    TreeSitterHighlighter* highlighter = nullptr;
#endif
};