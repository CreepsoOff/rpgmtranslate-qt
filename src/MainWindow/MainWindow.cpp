#include "MainWindow.hpp"

#include "AboutWindow.hpp"
#include "AssetMenu.hpp"
#include "AutoUpdater.hpp"
#include "BatchMenu.hpp"
#include "BookmarkMenu.hpp"
#include "Constants.hpp"
#include "Enums.hpp"
#include "GlossaryMenu.hpp"
#include "MatchMenu.hpp"
#include "PopupInput.hpp"
#include "ProjectSettings.hpp"
#include "PurgeMenu.hpp"
#include "ReadMenu.hpp"
#include "SearchMenu.hpp"
#include "SearchPanelDock.hpp"
#include "SettingsWindow.hpp"
#include "TabListModel.hpp"
#include "TranslationTable.hpp"
#include "TranslationTableModel.hpp"
#include "TranslationsMenu.hpp"
#include "Types.hpp"
#include "Utils.hpp"
#include "WriteMenu.hpp"
#include "rpgmtranslate.h"
#include "ui_MainWindow.h"
#include "version.h"

#include <QCheckBox>
#include <QCloseEvent>
#include <QDesktopServices>
#include <QFileDialog>
#include <QJsonParseError>
#include <QMessageBox>
#include <QProcess>
#include <QProgressDialog>
#include <QStyleHints>
#include <QTranslator>
#include <QVersionNumber>
#include <archive.h>
#include <archive_entry.h>

// TODO: Display entry in search panel/bookmark menu, but make it optional
// through settings.

MainWindow::MainWindow(QWidget* const parent) :
    QMainWindow(parent),

    ui(setupUi()),

    translator(new QTranslator(this)),

    searchMenu(new SearchMenu(this)),
    batchMenu(new BatchMenu(this)),
    glossaryMenu(new GlossaryMenu(this)),
    translationsMenu(new TranslationsMenu(this)),
    bookmarkMenu(new BookmarkMenu(this)),

    readMenu(new ReadMenu(this)),
    writeMenu(new WriteMenu(this)),
    purgeMenu(new PurgeMenu(this)),

    assetMenu(new AssetMenu(this)),

    linesStatusLabel(new QLabel(this)),
    progressStatusLabel(new QLabel(this)),
    tabNameStatusLabel(new QLabel(this)),

    ffiLogger(FFILogger::instance()),
    taskWorker(new TaskWorker()) {
    actionSave->setShortcut(QKeySequence::Save);
    actionWrite->setShortcut(u"Ctrl+W"_s);
    actionSearch->setShortcut(QKeySequence::Find);

    addAction(actionSave);
    addAction(actionTabPanel);
    addAction(actionSearchPanel);
    addAction(actionGoToRow);
    addAction(actionBatchMenu);
    addAction(actionSearch);
    addAction(actionBookmarkMenu);
    addAction(actionMatchMenu);

    actionTabPanel->setEnabled(false);
    actionSave->setEnabled(false);
    actionWrite->setEnabled(false);
    actionSearch->setEnabled(false);
    actionBatchMenu->setEnabled(false);
    actionGlossaryMenu->setEnabled(false);
    actionMatchMenu->setEnabled(false);
    actionTranslationsMenu->setEnabled(false);
    actionBookmarkMenu->setEnabled(false);
    actionSearchPanel->setEnabled(false);
    actionSourceControl->setEnabled(false);
    actionAssets->setEnabled(false);

    ui->tabPanelButton->setDefaultAction(actionTabPanel);
    ui->saveButton->setDefaultAction(actionSave);
    ui->writeButton->setDefaultAction(actionWrite);
    ui->openFolderButton->setDefaultAction(ui->actionOpenFolder);
    ui->searchButton->setDefaultAction(actionSearch);
    ui->batchButton->setDefaultAction(actionBatchMenu);
    ui->glossaryButton->setDefaultAction(actionGlossaryMenu);
    ui->matchMenuButton->setDefaultAction(actionMatchMenu);
    ui->translationsButton->setDefaultAction(actionTranslationsMenu);
    ui->bookmarksButton->setDefaultAction(actionBookmarkMenu);
    ui->sourceControlButton->setDefaultAction(actionSourceControl);
    ui->assetsButton->setDefaultAction(actionAssets);
    ui->locateProjectDirButton->setDefaultAction(actionLocateProjectDir);
    ui->searchPanelButton->setDefaultAction(actionSearchPanel);

    taskWorker->start();

    connect(
        &ffiLogger,
        &FFILogger::logReceived,
        this,
        [this](const u8 level, const QString& message) -> void {
        switch (level) {
            case 0:
                qCritical() << message;
                break;
            case 1:
                qWarning() << message;
                break;
            case 2:
                qInfo() << message;
                break;
            default:
                qDebug() << message;
                break;
        }

        const bool purging = message.endsWith("purged."_L1);
        const bool writing = message.endsWith("written."_L1);
        const bool reading = message.endsWith("read."_L1);

        if (purging || writing || reading) {
            ui->taskProgressBar->setEnabled(true);
            ui->taskProgressBar->setMaximum(ui->taskProgressBar->maximum() + 1);
            ui->taskProgressBar->setValue(ui->taskProgressBar->value() + 1);

            QString taskName;
            if (purging) {
                taskName = tr("Purging");
            } else if (writing) {
                taskName = tr("Writing");
            } else {
                taskName = tr("Reading");
            }

            const u32 spacePos = message.indexOf(u' ') + 1;
            ui->taskLabel->setText("%1: %2"_L1.arg(taskName).arg(
                QStringView(message)
                    .sliced(spacePos, message.lastIndexOf(u':') - spacePos)
            ));
        }
    }
    );

    init_rust_logger(&FFILogger::rustLogCallback);

#ifdef ENABLE_LIBGIT2
    ui->sourceControlDock->init(
        ui->branchSelect,
        ui->gitChangesList,
        ui->commitList,

        ui->commitButton,
        ui->commitOptionsButton,
        ui->commitMessageInput,

        ui->copyTranslationButton,
        ui->refreshChangesButton
    );
#else
    ui->sourceControlDock->hide();
#endif

    ui->matchMenu->init(ui->clearMatchMenuButton, ui->matchMenuTable);
    ui->searchPanel->init(
        ui->fileSelect,
        ui->searchResultList,
        ui->clearSearchPanelButton
    );
    ui->searchPanel->hide();

    auto* const statusBarPermanentWidget = new QWidget(ui->statusBar);
    auto* const statusBarPermanentWidgetLayout =
        new QHBoxLayout(statusBarPermanentWidget);
    statusBarPermanentWidgetLayout->setContentsMargins(8, 0, 8, 0);
    statusBarPermanentWidgetLayout->setSpacing(8);

    statusBarPermanentWidgetLayout->addWidget(linesStatusLabel);
    statusBarPermanentWidgetLayout->addWidget(progressStatusLabel);
    statusBarPermanentWidgetLayout->addWidget(tabNameStatusLabel);
    ui->statusBar->addPermanentWidget(statusBarPermanentWidget);

    initializeSettings();

    connect(ui->actionExit, &QAction::triggered, this, [this] -> void {
        exit();
    });

    connect(ui->actionAbout, &QAction::triggered, this, [this] -> void {
        showAboutWindow();
    });

    connect(ui->actionSettings, &QAction::triggered, this, [this] -> void {
        showSettingsWindow();
    });

    connect(ui->actionCloseProject, &QAction::triggered, this, [this] -> void {
        const auto result = saveEverything();

        if (!result) {
            return;
        }

        closeProject();
    });

    connect(ui->actionCloseTab, &QAction::triggered, this, [this] -> void {
        ui->tabPanel->changeTab(QString());
    });

    connect(
        bookmarkMenu,
        &BookmarkMenu::bookmarkClicked,
        this,
        [this](const QL1SV file, const u32 row) -> void {
        ui->tabPanel->changeTab(file);

        QTimer::singleShot(1, [this, row] -> void {
            ui->translationTable->scrollTo(
                ui->translationTable->model()->index(i32(row), 0),
                TranslationTable::PositionAtCenter
            );
        });
    }
    );

    connect(ui->actionDocumentation, &QAction::triggered, this, [] -> void {
        QDesktopServices::openUrl(QUrl(
            u"https://RPG-Maker-Translation-Tools.github.io/rpgmtranslate-qt"_s
        ));
    });

    connect(ui->actionEnglish, &QAction::triggered, this, [this] -> void {
        retranslate(QLocale::English);
    });

    connect(ui->actionRussian, &QAction::triggered, this, [this] -> void {
        retranslate(QLocale::Russian);
    });

    connect(
        ui->actionCheckForUpdates,
        &QAction::triggered,
        this,
        [this] -> void { checkForUpdates(true); }
    );

    connect(actionGoToRow, &QAction::triggered, this, [this] -> void {
        if (ui->tabPanel->currentTabName().isEmpty()) {
            return;
        }

        auto* const popupInput = new PopupInput(this);
        popupInput->setValidator(new QIntValidator(0, INT32_MAX, popupInput));
        popupInput->setMaxLength(10);
        popupInput->setFixedWidth(256);
        popupInput->setPlaceholderText(
            tr("Input line from %1 to %2")
                .arg(1)
                .arg(linesStatusLabel->text().split(u' ').first())
        );

        popupInput->move((width() / 2) - 128, x() + 64);
        popupInput->show();
        popupInput->setFocus();

        connect(
            popupInput,
            &PopupInput::inputRejected,
            this,
            [this, popupInput] -> void { delete popupInput; },
            Qt::SingleShotConnection
        );

        connect(
            popupInput,
            &PopupInput::editingFinished,
            this,
            [this, popupInput] -> void {
            const i32 rowIndex = popupInput->text().toInt() - 1;

            ui->translationTable->scrollTo(
                ui->translationTable->model()->index(rowIndex, 0),
                TranslationTable::PositionAtCenter
            );

            delete popupInput;
        },
            Qt::SingleShotConnection
        );
    });

    connect(ui->tabPanel, &TabPanel::tabChanged, this, &MainWindow::changeTab);

    connect(actionTabPanel, &QAction::triggered, this, [this] -> void {
        ui->tabPanel->setHidden(!ui->tabPanel->isHidden());
    });

    connect(actionSave, &QAction::triggered, this, [this] -> void {
        const auto saveSuccess = saveCurrentTab();

        if (!saveSuccess) {
            return;
        }

        const auto saveSuccess2 = saveMaps();

        if (!saveSuccess2) {
            return;
        }
    });

    connect(actionWrite, &QAction::triggered, this, [this] -> void {
        const QString sourcePath = projectSettings->sourcePath();

        if (!QFile::exists(sourcePath)) {
            QMessageBox::warning(
                this,
                tr("No source files"),
                tr("Cannot write, source files are absent.")
            );
            return;
        }

        const QString gameTitle = ui->gameTitleInput->placeholderText();

        QMetaObject::invokeMethod(
            taskWorker,
            &TaskWorker::write,
            Qt::QueuedConnection,
            gameTitle,
            // TODO: Right now, no mechanism for specifying skipped files for
            // write
            Selected()
        );

        connect(
            taskWorker,
            &TaskWorker::writeFinished,
            this,
            [this](const std::tuple<FFIString, f32> results) -> void {
            QTimer::singleShot(3000, [this] -> void {
                ui->taskLabel->setText(tr("No Tasks"));
                ui->taskProgressBar->setMaximum(0);
                ui->taskProgressBar->setValue(0);
                ui->taskProgressBar->setEnabled(false);
            });

            const auto [error, elapsed] = results;

            if (error.ptr != nullptr) {
                QMessageBox::critical(
                    this,
                    tr("Write failed"),
                    QString::fromUtf8(error.ptr, isize(error.len))
                );

                rpgm_string_free(error);
            }

            QMessageBox::information(
                this,
                tr("Written successfully"),
                tr("Elapsed: %1s.").arg(QString::number(elapsed, 10, 2))
            );
        },
            Qt::SingleShotConnection
        );
    });

    connect(actionSearch, &QAction::triggered, this, [this] -> void {
        searchMenu->setHidden(!searchMenu->isHidden());

        if (!searchMenu->mouseMoved()) {
            searchMenu->move(ui->searchButton->mapToGlobal(
                QPoint(0, ui->searchButton->height())
            ));
        }
    });

    connect(actionBatchMenu, &QAction::triggered, this, [this] -> void {
        batchMenu->setHidden(!batchMenu->isHidden());
        batchMenu->move(
            ui->batchButton->mapToGlobal(QPoint(0, ui->batchButton->height()))
        );
    });

    connect(actionGlossaryMenu, &QAction::triggered, this, [this] -> void {
        glossaryMenu->setHidden(!glossaryMenu->isHidden());

        if (!glossaryMenu->mouseMoved()) {
            glossaryMenu->move(ui->glossaryButton->mapToGlobal(
                QPoint(0, ui->glossaryButton->height())
            ));
        }
    });

    connect(actionMatchMenu, &QAction::triggered, this, [this] -> void {
        ui->matchMenu->setHidden(!ui->matchMenu->isHidden());
    });

    connect(actionTranslationsMenu, &QAction::triggered, this, [this] -> void {
        translationsMenu->setHidden(!translationsMenu->isHidden());

        if (!translationsMenu->mouseMoved()) {
            translationsMenu->move(ui->translationsButton->mapToGlobal(
                QPoint(0, ui->translationsButton->height())
            ));
        }
    });

    connect(actionBookmarkMenu, &QAction::triggered, this, [this] -> void {
        bookmarkMenu->setHidden(!bookmarkMenu->isHidden());

        bookmarkMenu->move(ui->bookmarksButton->mapToGlobal(
            QPoint(0, ui->bookmarksButton->height())
        ));
    });

    connect(actionSourceControl, &QAction::triggered, this, [this] -> void {
#ifdef ENABLE_LIBGIT2
        ui->sourceControlDock->setHidden(!ui->sourceControlDock->isHidden());
#else
        QMessageBox::warning(
            this,
            tr("Libgit2 support is disabled"),
            tr(
                "Program was compiled without support for libgit2, so it's impossible to access source control."
            )
        );
#endif
    });

    connect(actionAssets, &QAction::triggered, this, [this] -> void {
        if (assetMenu->isHidden()) {
            assetMenu->move(ui->assetsButton->mapToGlobal(
                QPoint(0, ui->assetsButton->height())
            ));
            assetMenu->show();
            assetMenu->adjustSize();
        } else {
            assetMenu->hide();
        }
    });

    connect(ui->rvpackerButton, &QPushButton::pressed, this, [this] -> void {
        auto menu = QMenu(this);

        const QAction* const readAction = menu.addAction(tr("Read"));
        const QAction* const purgeAction = menu.addAction(tr("Purge"));

        const QAction* const selectedAction =
            menu.exec(ui->rvpackerButton->mapToGlobal(
                QPoint(0, ui->rvpackerButton->height())
            ));

        if (selectedAction == readAction) {
            readMenu->show();
            readMenu->move(ui->rvpackerButton->mapToGlobal(
                QPoint(0, ui->rvpackerButton->height())
            ));
        } else if (selectedAction == purgeAction) {
            purgeMenu->show();
            purgeMenu->move(ui->rvpackerButton->mapToGlobal(
                QPoint(0, ui->rvpackerButton->height())
            ));
        }
    });

    connect(actionLocateProjectDir, &QAction::triggered, this, [this] -> void {
        QDesktopServices::openUrl(
            QUrl::fromLocalFile(projectSettings->projectPath)
        );
    });

    connect(actionSearchPanel, &QAction::triggered, this, [this] -> void {
        ui->searchPanel->setHidden(!ui->searchPanel->isHidden());
    });

    connect(
        searchMenu,
        &SearchMenu::actionRequested,
        this,
        [this](
            const Selected selected,
            const SearchMenu::Action action,
            const QString& searchText,
            const QString& replaceText,
            const SearchLocation searchLocation,
            const i8 columnIndex,
            const SearchFlags searchFlags
        ) -> void {
        const auto saveSuccess = saveCurrentTab();

        if (!saveSuccess) {
            return;
        }

        QMetaObject::invokeMethod(
            taskWorker,
            &TaskWorker::search,
            Qt::QueuedConnection,
            action,
            selected,
            searchText,
            searchLocation,
            columnIndex,
            searchFlags,
            ui->tabPanel->tabCount()
        );

        connect(
            taskWorker,
            &TaskWorker::searchFinished,
            this,
            [this,
             selected,
             action,
             searchText,
             replaceText,
             searchLocation,
             columnIndex,
             searchFlags](HashMap<FilenameArray, vector<CellMatch>> results)
                -> void {
            if (action == SearchMenu::Action::Search) {
                ui->searchPanel->showMatches(
                    std::move(results),
                    mapSections,
                    projectSettings
                );
            } else {
                const QString currentTabName = ui->tabPanel->currentTabName();

                for (const auto filenameArray :
                     selected.filenames(projectSettings->engineType)) {
                    if (QL1SV(filenameArray.data()) == currentTabName) {
                        ui->tabPanel->changeTab(QString());
                    }
                }

                QMetaObject::invokeMethod(
                    taskWorker,
                    &TaskWorker::replace,
                    Qt::QueuedConnection,
                    std::move(results),
                    selected,
                    action,
                    searchText,
                    replaceText,
                    searchLocation,
                    columnIndex,
                    searchFlags
                );
            }
        },
            Qt::SingleShotConnection
        );
    }
    );

    connect(
        ui->translationTable,
        &TranslationTable::translatedChanged,
        this,
        [this](const i8 count) -> void {
        ui->globalProgressBar->setValue(ui->globalProgressBar->value() + count);
        ui->tabPanel->setCurrentTranslated(count);
        progressStatusLabel->setText(tr("%1 Translated / %2 Total")
                                         .arg(ui->tabPanel->currentTranslated())
                                         .arg(ui->tabPanel->currentTotal()));
    }
    );

    connect(
        ui->translationTable,
        &TranslationTable::bookmarkChanged,
        this,
        [this](const u32 row) -> void {
        bookmarkMenu->updateBookmark(
            row,
            *ui->translationTable->model()->item(i32(row), 1).text()
        );
    }
    );

    connect(
        ui->translationTable,
        &TranslationTable::columnAdded,
        this,
        [this] -> void {
        projectSettings->columns.emplace_back(
            tr("Translation"),
            DEFAULT_COLUMN_WIDTH
        );
        searchMenu->addColumn(tr("Translation"));
        batchMenu->addColumn(tr("Translation"));
    }
    );

    connect(
        ui->translationTable,
        &TranslationTable::columnRenamed,
        this,
        [this](const u8 index, const QString& name) -> void {
        projectSettings->columns[index].name = name;
        searchMenu->renameColumn(index, name);
        batchMenu->renameColumn(index, name);
    }
    );

    connect(
        ui->translationTable,
        &TranslationTable::columnResized,
        this,
        [this](const u8 index, const u16 width) -> void {
        projectSettings->columns[index].width = width;
    }
    );

    connect(
        ui->translationTable,
        &TranslationTable::rowRemoved,
        this,
        [this](const RemovedRowInfo info) -> void {
        if ((info.flags() & CommentFlag) == 0) {
            ui->globalProgressBar->setMaximum(
                ui->globalProgressBar->maximum() - 1
            );
            ui->tabPanel->setCurrentTotal(
                i32(ui->tabPanel->currentTotal() - 1)
            );

            if ((info.flags() & TranslatedFlag) != 0) {
                ui->tabPanel->setCurrentTotal(
                    i32(ui->tabPanel->currentTotal() - 1)
                );
                ui->globalProgressBar->setValue(
                    ui->globalProgressBar->value() - 1
                );
            }
        } else if ((info.flags() & BookmarkFlag) != 0) {
            bookmarkMenu->removeBookmark(info.row());
        }

        bookmarkMenu->shiftIndices(ui->tabPanel->currentTabName(), info.row());

        linesStatusLabel->setText(
            tr("%1 Lines / %2 Comments")
                .arg(ui->translationTable->model()->rowCount())
                .arg(
                    ui->translationTable->model()->rowCount() -
                    ui->tabPanel->currentTotal()
                )
        );
    }
    );

    connect(ui->tabPanel, &TabPanel::displayToggled, this, [this] -> void {
        settings->appearance.displayPercents =
            !settings->appearance.displayPercents;
    });

    connect(
        ui->tabPanel,
        &TabPanel::completedToggled,
        this,
        [this](const QString& tabName, const bool completed) -> void {
        if (completed) {
            projectSettings->completedFiles.append(tabName);
        } else {
            projectSettings->completedFiles.removeIf(
                [&tabName](const QString& pred) -> bool {
                return pred == tabName;
            }
            );
        }
    }
    );

    connect(
        batchMenu,
        &BatchMenu::actionRequested,
        this,
        [this](
            Selected selected,
            const BatchAction action,
            const u8 columnIndex,
            const std::
                variant<BatchMenu::TrimFlags, std::tuple<u8, QString>, u8>&
                    variant
        ) -> void {
        const QString currentTabName = ui->tabPanel->currentTabName();

        for (const auto filenameArray :
             selected.filenames(projectSettings->engineType)) {
            if (QL1SV(filenameArray.data()) == currentTabName) {
                ui->tabPanel->changeTab(QString());
            }
        }

        if (action == BatchAction::Translate) {
            if (projectSettings->sourceLang == Algorithm::None) {
                QMessageBox::warning(
                    this,
                    tr("Source language is not set"),
                    tr(
                        "Cannot perform batch-translate. You need to set source language in Settings > Project first."
                    )
                );
                return;
            }

            if (projectSettings->translationLang == Algorithm::None) {
                QMessageBox::warning(
                    this,
                    tr("Translation language is not set"),
                    tr(
                        "Cannot perform batch-translate. You need to set translation language in Settings > Project first."
                    )
                );
                return;
            }
        }

        QMetaObject::invokeMethod(
            taskWorker,
            &TaskWorker::performBatchAction,
            Qt::QueuedConnection,
            selected,
            action,
            columnIndex,
            variant,
            action == BatchAction::Translate ? glossaryMenu->glossary()
                                             : Glossary{}
        );

        if (action == BatchAction::Translate) {
            connect(
                taskWorker,
                &TaskWorker::translateFinished,
                this,
                [this, columnIndex, selected](
                    const expected<
                        std::tuple<ByteBuffer, ByteBuffer>,
                        FFIString>& results
                ) -> void {
                if (!results) {
                    const auto error = results.error();

                    QMessageBox::warning(
                        this,
                        tr("Batch translation failed"),
                        tr("Batch translation failed with error: %1")
                            .arg(fromffistr(error))
                    );

                    rpgm_string_free(error);
                    return;
                }

                const auto [translatedFiles, translatedFilesFFI] =
                    results.value();

                const auto stringsArray = span(
                    ras<const ByteBuffer*>(translatedFilesFFI.ptr),
                    translatedFilesFFI.len
                );

                u16 skippedCount = 0;
                auto filenames =
                    selected.filenames(projectSettings->engineType);

                u32 total = 0;
                u32 progress = 0;

                for (const auto [idx, filenameArray] :
                     views::enumerate(filenames)) {
                    if (stringsArray[idx].len == 0) {
                        qInfo() << "Translated strings array at index "_L1
                                << idx << "in file "_L1 << QL1SV(filenameArray)
                                << " is empty."_L1;
                        continue;
                    }

                    const auto strings = span(
                        ras<const FFIString*>(stringsArray[idx].ptr),
                        stringsArray[idx].len
                    );

                    const auto filename = QL1SV(filenameArray.data());

                    if (ui->tabPanel->currentTabName() == filename) {
                        ui->tabPanel->changeTab(QString());
                    }
                    lockedFile = filename;

                    constexpr string_view COMMENT_PREFIX_UTF8 = "<!--";
                    constexpr string_view SEPARATOR_UTF8 = "<#>";

                    QByteArray content;
                    unique_ptr<QFile> file;

                    const bool isMap = filename.startsWith("map"_L1);
                    const u16 mapNumber =
                        isMap ? filename.sliced(3).toUInt() : 0;

                    if (isMap) {
                        content = mapSections[mapNumber].toUtf8();
                    } else {
                        const QString path =
                            projectSettings->translationPath() + u'/' +
                            filename + u".txt";
                        file = make_unique<QFile>(path);

                        if (!file->open(QFile::ReadWrite)) {
                            qWarning()
                                << "Failed to open file %1: %2"_L1.arg(path)
                                       .arg(file->errorString());

                            std::swap(
                                filenames[idx],
                                filenames[skippedCount++]
                            );
                            continue;
                        }

                        content = file->readAll();
                    }

                    auto filteredStrings = views::filter(
                        strings,
                        [](const FFIString element) -> bool {
                        constexpr string_view COMMENT_PREFIX_BYTES = "<!--";

                        return element.len < COMMENT_PREFIX_BYTES.size() ||
                               std::memcmp(
                                   element.ptr,
                                   COMMENT_PREFIX_BYTES.data(),
                                   COMMENT_PREFIX_BYTES.size()
                               ) != 0;
                    }
                    );

                    const auto countNonEmptyLines =
                        [](const QByteArray& buffer) -> u32 {
                        const cstr data = buffer.constData();
                        const isize size = buffer.size();

                        u32 lineCount = 0;
                        isize lineStart = 0;

                        while (lineStart < size) {
                            isize lineEnd = lineStart;

                            while (lineEnd < size && data[lineEnd] != u'\n') {
                                ++lineEnd;
                            }

                            if (lineEnd != lineStart) {
                                ++lineCount;
                            }

                            lineStart = lineEnd + 1;
                        }

                        return lineCount;
                    };

                    total += countNonEmptyLines(content);

                    QByteArray replaced;
                    replaced.reserve(content.size());

                    auto stringsIterator = filteredStrings.begin();
                    const char* const data = content.constData();
                    const isize size = content.size();

                    isize lineStart = 0;
                    bool hasLines = false;

                    while (lineStart < size) {
                        isize lineEnd = lineStart;

                        while (lineEnd < size && data[lineEnd] != u'\n') {
                            ++lineEnd;
                        }

                        if (lineEnd != lineStart) {
                            updateTask(
                                TaskWorker::Task::BatchTranslate,
                                ++progress,
                                total
                            );

                            if (hasLines) {
                                replaced.push_back(u'\n');
                            }
                            hasLines = true;

                            const cstr linePtr = data + lineStart;
                            const isize lineSize = lineEnd - lineStart;
                            const string_view lineView(
                                linePtr,
                                as<usize>(lineSize)
                            );

                            if (lineView.starts_with(COMMENT_PREFIX_UTF8)) {
                                replaced.append(linePtr, lineSize);
                            } else {
                                usize fieldStart = 0;
                                bool malformed = false;

                                for (u8 column = 0; column < columnIndex;
                                     ++column) {
                                    const usize separatorPos = lineView.find(
                                        SEPARATOR_UTF8,
                                        fieldStart
                                    );

                                    if (separatorPos == string_view::npos) {
                                        malformed = true;
                                        break;
                                    }

                                    fieldStart =
                                        separatorPos + SEPARATOR_UTF8.size();
                                }

                                const auto translated = *stringsIterator++;

                                if (malformed) {
                                    replaced.append(linePtr, lineSize);
                                } else {
                                    const usize fieldEnd = lineView.find(
                                        SEPARATOR_UTF8,
                                        fieldStart
                                    );

                                    replaced.append(linePtr, isize(fieldStart));
                                    replaced.append(
                                        translated.ptr,
                                        isize(translated.len)
                                    );

                                    if (fieldEnd != string_view::npos) {
                                        replaced.append(
                                            linePtr + isize(fieldEnd),
                                            lineSize - isize(fieldEnd)
                                        );
                                    }
                                }
                            }
                        }

                        lineStart = lineEnd + 1;
                    }

                    const u16 tabIndex = ui->tabPanel->tabIndex(filename);

                    const u32 total = ui->tabPanel->tabTotal(tabIndex);
                    const u32 translated =
                        ui->tabPanel->tabTranslated(tabIndex);

                    ui->tabPanel->setTabTranslated(tabIndex, total);

                    ui->globalProgressBar->setValue(i32(
                        (ui->globalProgressBar->value() - translated) + total
                    ));

                    if (isMap) {
                        mapSections.insert_or_assign(
                            mapNumber,
                            QString::fromUtf8(replaced)
                        );
                    } else {
                        file->seek(0);
                        file->resize(replaced.size());
                        file->write(replaced);
                    }
                }

                rpgm_free_translated_files(translatedFiles, translatedFilesFFI);

                if (skippedCount != 0) {
                    QString skippedString;

                    for (const auto filename :
                         views::take(filenames, skippedCount)) {
                        skippedString += QL1SV(filename.data());
                        skippedString += u'\n';
                    }

                    QMessageBox::warning(
                        nullptr,
                        tr("Files were skipped"),
                        tr(
                            "The program was unable to open the following files:\n %1"
                        )
                            .arg(skippedString)
                    );
                }

                lockedFile = QString();
            },
                Qt::SingleShotConnection
            );
        }
    }
    );

    connect(
        glossaryMenu,
        &GlossaryMenu::checkRequested,
        this,
        [this](
            const Selected selected,
            const std::variant<Glossary, Term>& variant
        ) -> void {
        auto filenames = selected.filenames(projectSettings->engineType);
        u16 skippedCount = 0;

        for (const auto [idx, filenameArray] : views::enumerate(filenames)) {
            const auto filename = QL1SV(filenameArray.data());

            const auto result =
                fileLines(filename, mapSections, projectSettings);

            if (!result) {
                std::swap(filenames[idx], filenames[skippedCount++]);
                continue;
            }

            const QSVList lines = result.value().lines;

            for (const u32 idx : range<u32>(0, lines.size())) {
                const QStringView line = lines[idx];

                const QSVList parts = lineParts(line, idx, filename);
                const QStringView source = getSource(parts);
                const QStringView translation =
                    getTranslation(parts).translation;

                if (variant.index() == 0) {
                    for (const auto& term : std::get<0>(variant).terms) {
                        appendMatches(filename, source, translation, term, idx);
                    }
                } else if (variant.index() == 1) {
                    appendMatches(
                        filename,
                        source,
                        translation,
                        std::get<1>(variant),
                        idx
                    );
                } else {
                    std::unreachable();
                }
            }
        }

        if (skippedCount != 0) {
            QString skippedString;

            for (const auto filename : views::take(filenames, skippedCount)) {
                skippedString += QL1SV(filename.data());
                skippedString += u'\n';
            }

            QMessageBox::warning(
                this,
                tr("Files were skipped"),
                tr("The program was unable to open the following files:\n %1")
                    .arg(skippedString)
            );
        }

        ui->matchMenu->show();
    }
    );

    connect(
        ui->searchPanel,
        &SearchPanelDock::actionRequested,
        this,
        [this](
            const SearchPanelDock::Action action,
            const QString& filename,
            const i32 rowIndex,
            const u8 columnIndex,
            span<const TextMatch> matches,
            SearchResultListItem& item
        ) -> void {
        switch (action) {
            case SearchPanelDock::Action::GoTo:
                ui->tabPanel->changeTab(filename);

                QTimer::singleShot(1, this, [this, rowIndex] -> void {
                    ui->translationTable->scrollTo(
                        ui->translationTable->model()->index(rowIndex, 0),
                        TranslationTable::PositionAtCenter
                    );
                });
                break;

            case SearchPanelDock::Action::Put:
            case SearchPanelDock::Action::Replace: {
                if (filename == ui->tabPanel->currentTabName()) {
                    ui->tabPanel->changeTab(QString());
                }

                const QString replaceText = searchMenu->replaceText();

                QMetaObject::invokeMethod(
                    taskWorker,
                    &TaskWorker::replaceSingle,
                    Qt::QueuedConnection,
                    replaceText,
                    action,
                    filename,
                    rowIndex,
                    columnIndex,
                    matches
                );

                connect(
                    taskWorker,
                    &TaskWorker::singleReplaceFinished,
                    this,
                    [this, &item, matches](
                        const std::tuple<QString, TextMatch*>& results
                    ) -> void {
                    const auto [text, newMatches] = results;

                    item.title = text;
                    memcpy(
                        item.cellMatch.matches,
                        newMatches,
                        matches.size() * sizeof(TextMatch)
                    );

                    delete[] newMatches;
                },
                    Qt::SingleShotConnection
                );

                break;
            }
        }
    }
    );

    connect(
        ui->translationTable,
        &TranslationTable::textChanged,
        this,
        [this](const QString& translation) -> void {
        const bool sourceLangUnset =
            projectSettings->sourceLang == Algorithm::None;
        const bool translationLangUnset =
            projectSettings->translationLang == Algorithm::None;

        if (sourceLangUnset || translationLangUnset) {
            const QString message =
                sourceLangUnset && translationLangUnset
                    ? tr(
                          "Set source and translation languages in Settings > Project to show glossary matches."
                      )
                : sourceLangUnset
                    ? tr(
                          "Set source language in Settings > Project to show glossary matches."
                      )
                    : tr(
                          "Set translation language in Settings > Project to show glossary matches."
                      );

            auto* const model = ui->matchMenuTable->model();
            if (model->rowCount() == 1 && model->row(0).info == message) {
                return;
            }

            ui->matchMenu->clear();

            MatchTableModel::Row row;
            row.sourceText = message;
            row.info = message;
            model->appendRow(std::move(row));
            return;
        }

        const QModelIndex index = ui->translationTable->currentIndex();

        if (!index.isValid()) {
            return;
        }

        const auto& sourceItem =
            ui->translationTable->model()->item(index.row(), 0);

        const QString* const source = sourceItem.text();

        if (translation.isEmpty()) {
            return;
        }

        ui->matchMenu->clear();

        const QString currentTab = ui->tabPanel->currentTabName();
        for (const Term& term : glossaryMenu->glossary().terms) {
            appendMatches(
                currentTab,
                QStringView(source->data(), source->size()),
                translation,
                term,
                ui->translationTable->currentIndex().row()
            );
        }
    }
    );

    connect(
        ui->translationTable,
        &TranslationTable::inputFocused,
        this,
        [this] -> void {
        if (settings->translation.endpoints.empty() ||
            ranges::all_of(
                settings->translation.endpoints,
                [](const auto& endpoint) -> bool {
            return !endpoint.singleTranslation;
        }
            )) {
            return;
        };

        if (projectSettings->sourceLang != Algorithm::None &&
            projectSettings->translationLang != Algorithm::None) {
            const auto& sourceItem = ui->translationTable->model()->item(
                ui->translationTable->currentIndex().row(),
                0
            );
            const QString* const text = sourceItem.text();
            const Glossary glossary = glossaryMenu->glossary();

            QMetaObject::invokeMethod(
                taskWorker,
                &TaskWorker::translateSingle,
                Qt::QueuedConnection,
                ui->tabPanel->currentTabName(),
                *text,
                glossary
            );

            connect(
                taskWorker,
                &TaskWorker::singleTranslateFinished,
                this,
                [this](const vector<QString>& translations) -> void {
                translationsMenu->showTranslations(translations, settings);
            },
                Qt::SingleShotConnection
            );
        } else {
            const bool sourceLangUnset =
                projectSettings->sourceLang == Algorithm::None;
            const bool translationLangUnset =
                projectSettings->translationLang == Algorithm::None;

            const QString message =
                sourceLangUnset && translationLangUnset
                    ? tr(
                          "Set source and translation languages in Settings > Project to show translations."
                      )
                : sourceLangUnset
                    ? tr(
                          "Set source language in Settings > Project to show translations."
                      )
                    : tr(
                          "Set translation language in Settings > Project to show translations."
                      );

            translationsMenu->showError(message);
        }

        // TODO: Call to FFI for language tool lints
    }
    );

    connect(
        ui->translationTable,
        &TranslationTable::bookmarked,
        this,
        [this](const u32 row) -> void {
        bookmarkMenu->addBookmark(
            ui->tabPanel->currentTabName(),
            QStringView(),
            row - 1
        );
    }
    );

    connect(ui->actionOpenFolder, &QAction::triggered, this, [this] -> void {
        const QString dir =
            QFileDialog::getExistingDirectory(this, tr("Select a game folder"));

        if (dir.isEmpty()) {
            return;
        }

        openProject(dir, true);
    });

    connect(readMenu, &ReadMenu::accepted, this, [this] -> void {
        if (firstReadPending) {
            return;
        }

        const QString& projectPath = projectSettings->projectPath;
        const QString sourcePath = projectSettings->sourcePath();
        const QString translationPath = projectSettings->translationPath();

        QMetaObject::invokeMethod(
            taskWorker,
            &TaskWorker::read,
            Qt::QueuedConnection,
            sourcePath,
            translationPath,
            readMenu->readMode(),
            projectSettings->engineType,
            readMenu->duplicateMode(),
            readMenu->selected(true),
            readMenu->flags(),
            readMenu->parseMapEvents(),
            ByteBuffer{ .ptr = ras<const u8*>(projectSettings->hashes.data()),
                        .len = u32(projectSettings->hashes.size()) },
            readMenu->title()
        );

        connect(
            taskWorker,
            &TaskWorker::readFinished,
            this,
            [this](const std::tuple<FFIString, ByteBuffer> results) -> void {
            QTimer::singleShot(3000, [this] -> void {
                ui->taskLabel->setText(tr("No Tasks"));
                ui->taskProgressBar->setMaximum(0);
                ui->taskProgressBar->setValue(0);
                ui->taskProgressBar->setEnabled(false);
            });

            const auto [error, hashes] = results;

            if (error.ptr != nullptr) {
                const QString errorString =
                    QString::fromUtf8(error.ptr, isize(error.len));
                rpgm_string_free(error);

                QMessageBox::warning(this, tr("Read failed"), errorString);
                return;
            }

            if (hashes.ptr != nullptr) {
                const u128* const input = ras<const u128*>(hashes.ptr);

                projectSettings->hashes.resize(hashes.len);
                memcpy(
                    projectSettings->hashes.data(),
                    input,
                    hashes.len * sizeof(u128)
                );

                rpgm_buffer_free(hashes);
            }

            openProject(projectSettings->projectPath, false);
        },
            Qt::SingleShotConnection
        );
    });

    connect(purgeMenu, &PurgeMenu::accepted, this, [this] -> void {
        QMetaObject::invokeMethod(
            taskWorker,
            &TaskWorker::purge,
            Qt::QueuedConnection,
            ui->gameTitleInput->placeholderText(),
            purgeMenu->selected(true)
        );

        connect(
            taskWorker,
            &TaskWorker::purgeFinished,
            this,
            [this](const FFIString error) -> void {
            QTimer::singleShot(3000, [this] -> void {
                ui->taskLabel->setText(tr("No Tasks"));
                ui->taskProgressBar->setMaximum(0);
                ui->taskProgressBar->setValue(0);
                ui->taskProgressBar->setEnabled(false);
            });

            if (error.ptr != nullptr) {
                QMessageBox::information(
                    this,
                    tr("Purge failed"),
                    tr("Purge failed with error: %1").arg(fromffistr(error))
                );

                rpgm_string_free(error);
                return;
            }

            openProject(settings->core.projectPath, false);
        },
            Qt::SingleShotConnection
        );
    });

    connect(writeMenu, &WriteMenu::accepted, this, [this] -> void {
        QMetaObject::invokeMethod(
            taskWorker,
            &TaskWorker::write,
            Qt::QueuedConnection,
            ui->gameTitleInput->placeholderText(),
            writeMenu->selected(true)
        );

        connect(
            taskWorker,
            &TaskWorker::writeFinished,
            this,
            [this](const std::tuple<FFIString, f32>& results) -> void {
            QTimer::singleShot(3000, [this] -> void {
                ui->taskLabel->setText(tr("No Tasks"));
                ui->taskProgressBar->setMaximum(0);
                ui->taskProgressBar->setValue(0);
                ui->taskProgressBar->setEnabled(false);
            });

            const auto [error, elapsed] = results;

            if (error.ptr != nullptr) {
                QMessageBox::warning(
                    this,
                    tr("Write failed"),
                    tr("Write failed with error: %1").arg(fromffistr(error))
                );
                rpgm_string_free(error);
                return;
            }

            QMessageBox::information(
                this,
                tr("Write finished"),
                tr("Elapsed: %1").arg(elapsed)
            );
        },
            Qt::SingleShotConnection
        );
    });

    connect(&backupTimer, &QTimer::timeout, this, [this] -> void {
        saveBackup();
    });

    connect(
        taskWorker,
        &TaskWorker::lockFile,
        this,
        [this](const QString& lockFile) -> void { lockedFile = lockFile; }
    );

    connect(
        taskWorker,
        &TaskWorker::message,
        this,
        [this](const QString& message) -> void {
        ui->statusBar->showMessage(message);
    }
    );

    connect(
        taskWorker,
        &TaskWorker::progressChanged,
        this,
        [this](const TaskWorker::Task task, const i32 progress, const i32 total)
            -> void { updateTask(task, progress, total); }
    );

    connect(
        translationsMenu,
        &TranslationsMenu::translationClicked,
        this,
        [this](const QString& translation) -> void {
        ui->translationTable->insertTranslation(translation);
    }
    );

    auto* const recentProjectsMenu = new QMenu(this);

    for (const auto& recentProject : settings->core.recentProjects) {
        const QAction* const action =
            recentProjectsMenu->addAction(recentProject);

        connect(
            action,
            &QAction::triggered,
            this,
            [this, recentProject] -> void { openProject(recentProject, true); }
        );
    }

    ui->actionRecentProjects->setMenu(recentProjectsMenu);

    checkForUpdates();

    if (!settings->core.projectPath.isEmpty()) {
        openProject(settings->core.projectPath, false);
    } else {
        ui->statusBar->showMessage(
            tr("Open a project by using 'Open Folder' button!")
        );
    }
}

MainWindow::~MainWindow() {
    delete ui;
}

void MainWindow::initializeSettings() {
    auto settingsFile = QFile(qApp->applicationDirPath() + SETTINGS_PATH);

    if (settingsFile.open(QFile::ReadOnly)) {
        const QByteArray jsonData = settingsFile.readAll();

        QJsonParseError jsonError;
        const QJsonObject settingsObject =
            QJsonDocument::fromJson(jsonData, &jsonError).object();

        if (jsonError.error != QJsonParseError::NoError) {
            qWarning() << "Parsing settings.json failed: "_L1
                       << jsonError.errorString();
            settings = make_shared<Settings>();
        } else {
            settings =
                make_shared<Settings>(Settings::fromJSON(settingsObject));
        }
    } else {
        qWarning() << "Failed to open settings.json: "_L1
                   << settingsFile.errorString();
        settings = make_shared<Settings>();
    }

    loadSettings();
}

void MainWindow::loadSettings() {
    qApp->setStyle(settings->appearance.style);
    qApp->styleHints()->setColorScheme(settings->appearance.theme);

    QString fontName;
    u8 fontSize;

    if (settings->appearance.translationTableFont.isEmpty()) {
        fontName = font().family();
    } else {
        fontName = settings->appearance.translationTableFont;
    }

    if (settings->appearance.translationTableFontSize == 0) {
        fontSize = font().pointSize();
    } else {
        fontSize = settings->appearance.translationTableFontSize;
    }

    ui->translationTable->setFont(QFont(fontName, fontSize));

    ui->tabPanel->setProgressDisplay(settings->appearance.displayPercents);

    actionTabPanel->setShortcut(settings->controls.tabPanel);
    actionSearchPanel->setShortcut(settings->controls.searchPanel);
    actionGoToRow->setShortcut(settings->controls.goToRow);
    actionBatchMenu->setShortcut(settings->controls.batchMenu);
    actionBookmarkMenu->setShortcut(settings->controls.bookmarkMenu);
    actionMatchMenu->setShortcut(settings->controls.matchMenu);
    actionGlossaryMenu->setShortcut(settings->controls.glossaryMenu);
    actionTranslationsMenu->setShortcut(settings->controls.translationsMenu);

#ifdef ENABLE_NUSPELL
    if (projectSettings != nullptr) {
        ui->translationTable->initializeDictionary();
    }
#endif

    batchMenu->setEndpoints(settings->translation.endpoints);

    retranslate(settings->appearance.language);
}

auto MainWindow::saveSettings() -> bool {
start:
    QString path = qApp->applicationDirPath() + SETTINGS_PATH;
    auto settingsFile = make_unique<QFile>(path);

    if (!settingsFile->open(QFile::WriteOnly | QFile::Truncate)) {
        const auto result = handleOpenError(path, settingsFile->errorString());
        const auto index = result.index();

        switch (index) {
            case 0:
                break;
            case 1: {
                const QString& dir = std::get<1>(result).s;
                path = dir + SETTINGS_PATH;
                settingsFile = make_unique<QFile>(path);

                if (!settingsFile->open(QFile::WriteOnly | QFile::Truncate)) {
                    QMessageBox::critical(
                        this,
                        tr("Failed to open file"),
                        tr(
                            "Failed to open file %1: %2. Starting from the beginning."
                        )
                            .arg(path)
                            .arg(settingsFile->errorString())
                    );

                    goto start;
                }

                break;
            }
            case 2:
                return false;
                break;
            case 3:
                goto start;
                break;
            default:
                std::unreachable();
        }
    }

    settingsFile->write(
        QJsonDocument(settings->toJSON()).toJson(QJsonDocument::Compact)
    );

    return true;
}

auto MainWindow::saveGlossary() -> bool {
start:
    QString path = projectSettings->glossaryPath();
    auto glossaryFile = make_unique<QFile>(path);

    if (!glossaryFile->open(QFile::WriteOnly | QFile::Truncate)) {
        const auto result = handleOpenError(path, glossaryFile->errorString());
        const auto index = result.index();

        switch (index) {
            case 0:
                break;
            case 1: {
                const QString& dir = std::get<1>(result).s;
                path = dir + GLOSSARY_FILE;
                glossaryFile = make_unique<QFile>(path);

                if (!glossaryFile->open(QFile::WriteOnly | QFile::Truncate)) {
                    QMessageBox::critical(
                        this,
                        tr("Failed to open file"),
                        tr(
                            "Failed to open file %1: %2. Starting from the beginning."
                        )
                            .arg(path)
                            .arg(glossaryFile->errorString())
                    );

                    goto start;
                }

                break;
            }
            case 2:
                return false;
                break;
            case 3:
                goto start;
                break;
            default:
                std::unreachable();
        }
    }

    glossaryFile->write(QJsonDocument(glossaryMenu->glossary().toJSON())
                            .toJson(QJsonDocument::Compact));

    return true;
}

auto MainWindow::saveProjectSettings() -> bool {
start:
    QString path = projectSettings->projectSettingsPath();
    auto projectSettingsFile = make_unique<QFile>(path);

    if (!projectSettingsFile->open(QFile::WriteOnly | QFile::Truncate)) {
        const auto result =
            handleOpenError(path, projectSettingsFile->errorString());
        const auto index = result.index();

        switch (index) {
            case 0:
                break;
            case 1: {
                const QString& dir = std::get<1>(result).s;
                path = dir + PROJECT_SETTINGS_FILE;
                projectSettingsFile = make_unique<QFile>(path);

                if (!projectSettingsFile->open(
                        QFile::WriteOnly | QFile::Truncate
                    )) {
                    QMessageBox::critical(
                        this,
                        tr("Failed to open file"),
                        tr(
                            "Failed to open file %1: %2. Starting from the beginning."
                        )
                            .arg(path)
                            .arg(projectSettingsFile->errorString())
                    );

                    goto start;
                }

                break;
            }
            case 2:
                return false;
                break;
            case 3:
                goto start;
                break;
            default:
                std::unreachable();
        }
    }

    projectSettingsFile->write(
        QJsonDocument(projectSettings->toJSON()).toJson(QJsonDocument::Compact)
    );

    QString metadataPath =
        projectSettings->translationPath() + u"/.rvpacker-metadata";
    auto metadataFile = make_unique<QFile>(metadataPath);

    if (!metadataFile->open(QFile::WriteOnly | QFile::Truncate)) {
        const auto result =
            handleOpenError(metadataPath, metadataFile->errorString());
        const auto index = result.index();

        switch (index) {
            case 0:
                break;
            case 1: {
                const QString& dir = std::get<1>(result).s;
                metadataPath = dir + u"/.rvpacker-metadata";
                metadataFile = make_unique<QFile>(metadataPath);

                if (!metadataFile->open(QFile::WriteOnly | QFile::Truncate)) {
                    QMessageBox::critical(
                        this,
                        tr("Failed to open file"),
                        tr(
                            "Failed to open file %1: %2. Starting from the beginning."
                        )
                            .arg(metadataPath)
                            .arg(metadataFile->errorString())
                    );

                    goto start;
                }

                break;
            }
            case 2:
                return false;
                break;
            case 3:
                goto start;
                break;
            default:
                std::unreachable();
        }
    }

    // TODO: Fill metadata
    QVariantHash metadata;

    metadataFile->write(
        QJsonDocument(QJsonObject::fromVariantHash(metadata)).toJson()
    );

    return true;
}

auto MainWindow::saveEverything() -> bool {
    if (!saveSettings()) {
        return false;
    }

    if (projectSettings != nullptr) {
        if (!saveCurrentTab()) {
            return false;
        }

        if (!saveMaps()) {
            return false;
        }

        if (!saveProjectSettings()) {
            return false;
        }

        if (!saveGlossary()) {
            return false;
        }
    }

    return true;
}

void MainWindow::retranslate(const QLocale::Language language) {
    qApp->removeTranslator(translator);
    delete translator;

    translator = new QTranslator(this);
    const bool success = translator->load(
        ":/%1.qm"_L1.arg(QLocale(language).bcp47Name().split(u'-').first())
    );

    qApp->installTranslator(translator);

    ui->retranslateUi(this);
}

void MainWindow::showSettingsWindow() {
    if (projectSettings == nullptr) {
        QMessageBox::warning(
            this,
            tr("Cannot open settings window"),
            tr("Settings can only be changed after opening a project.")
        );
        return;
    }

    auto* const settingsWindow = new SettingsWindow(
        settings,
        projectSettings,
        ui->tabPanel->tabs(),
        this
    );
    settingsWindow->setAttribute(Qt::WA_DeleteOnClose);
    settingsWindow->show();

    connect(settingsWindow, &QDialog::destroyed, this, [this] -> void {
        loadSettings();
        saveSettings();
    });
}

void MainWindow::showAboutWindow() {
    auto* const aboutWindow = new AboutWindow(this);
    aboutWindow->setAttribute(Qt::WA_DeleteOnClose);
    aboutWindow->show();
}

void MainWindow::exit() {
    if (projectSettings == nullptr) {
        qApp->quit();
        return;
    }

    const auto success = saveEverything();

    if (success) {
        qApp->quit();
    }
}

auto MainWindow::setupUi() -> Ui::mainWindow* {
    auto* const ui_ = new Ui::mainWindow();
    ui_->setupUi(this);
    return ui_;
};

void MainWindow::checkForUpdates(bool manual) {
    if (!settings->core.checkForUpdates && !manual) {
        return;
    }

    auto* const updater = new AutoUpdater(this);

    connect(
        updater,
        &AutoUpdater::updateDownloaded,
        this,
        [this](const QByteArray& archiveData) -> void {
        const QString appDir = qApp->applicationDirPath();

#ifdef Q_OS_WINDOWS
        const QString exePath = qApp->applicationFilePath();
        QFile::rename(exePath, appDir + u"/rpgmtranslate-old.exe");
#endif

        archive* const archive_ = archive_read_new();
        archive* const disk = archive_write_disk_new();

        const auto cleanup = [archive_, disk] -> void {
            archive_read_close(archive_);
            archive_read_free(archive_);
            archive_write_close(disk);
            archive_write_free(disk);
        };

#ifdef Q_OS_WINDOWS
        archive_read_support_format_7zip(archive_);
        archive_read_support_filter_none(archive_);
#else
        archive_read_support_format_tar(archive_);
        archive_read_support_filter_xz(archive_);
        archive_read_support_filter_lzma(archive_);
#endif

        archive_write_disk_set_options(
            disk,
            ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_SECURE_NODOTDOT
        );

        if (archive_read_open_memory(
                archive_,
                archiveData.constData(),
                usize(archiveData.size())
            ) != ARCHIVE_OK) {
            qWarning() << "libarchive failed to open archive:"_L1
                       << archive_error_string(archive_);

            QMessageBox::information(
                this,
                tr("Update failed"),
                tr("Failed to open update archive")
            );

            cleanup();
            return;
        }

#ifdef Q_OS_WINDOWS
        static constexpr string_view targetEntry =
            "rpgmtranslate/rpgmtranslate.exe";
        const QByteArray outputPath = (appDir + u"/rpgmtranslate.exe").toUtf8();
#else
        static constexpr string_view targetEntry = "rpgmtranslate";
        const QByteArray outputPath = (appDir + u"/rpgmtranslate").toUtf8();
#endif

        bool extracted = false;
        archive_entry* entry;

        while (archive_read_next_header(archive_, &entry) == ARCHIVE_OK) {
            if (archive_entry_pathname_utf8(entry) != targetEntry) {
                archive_read_data_skip(archive_);
                continue;
            }

            archive_entry_set_pathname(entry, outputPath.constData());

            if (archive_write_header(disk, entry) != ARCHIVE_OK) {
                qWarning() << "libarchive write_header failed:"_L1
                           << archive_error_string(disk);
                break;
            }

            const void* buffer;
            usize size;
            i64 offset;
            bool writeOk = true;

            while (true) {
                const i32 read =
                    archive_read_data_block(archive_, &buffer, &size, &offset);

                if (read == ARCHIVE_EOF) {
                    break;
                }

                if (read != ARCHIVE_OK) {
                    qWarning() << "libarchive read_data_block failed:"_L1
                               << archive_error_string(archive_);
                    writeOk = false;
                    break;
                }

                if (archive_write_data_block(disk, buffer, size, offset) !=
                    ARCHIVE_OK) {
                    qWarning() << "libarchive write_data_block failed:"_L1
                               << archive_error_string(disk);
                    writeOk = false;
                    break;
                }
            }

            archive_write_finish_entry(disk);
            extracted = writeOk;
            break;
        }

        cleanup();

        if (!extracted) {
            QMessageBox::information(
                this,
                tr("Update failed"),
                tr("Failed to extract update archive")
            );
            return;
        }

#ifdef Q_OS_LINUX
        QFile::setPermissions(
            appDir + u"/rpgmtranslate",
            QFileDevice::ReadOwner | QFileDevice::WriteOwner |
                QFileDevice::ExeOwner | QFileDevice::ReadGroup |
                QFileDevice::ExeGroup | QFileDevice::ReadOther |
                QFileDevice::ExeOther
        );
#endif

        // TODO: MacOS

        qApp->quit();
        QProcess::startDetached(qApp->arguments()[0]);
    },
        Qt::SingleShotConnection
    );

    connect(
        updater,
        &AutoUpdater::versionFetched,
        this,
        [=, this](const QString& version) -> void {
        const auto newVersion = QVersionNumber::fromString(version);
        const auto currentVersion =
            QVersionNumber::fromString(QString::fromLatin1(APP_VERSION));

        if (newVersion <= currentVersion) {
            if (manual) {
                QMessageBox::information(
                    this,
                    tr("Up to date"),
                    tr("Program is up-to-date.")
                );
            } else {
                qInfo() << "Up to date."_L1;
            }

            return;
        }

        auto msgBox = QMessageBox(this);
        auto* const checkbox = new QCheckBox(tr("Don't remind me"), &msgBox);
        msgBox.setWindowTitle(tr("New version is available"));
        msgBox.setText(tr("Version %1 is available.\nCurrent version is %2.")
                           .arg(version)
                           .arg(QString::fromLatin1(APP_VERSION)));
        const QPushButton* const installButton =
            msgBox.addButton(tr("Install"), QMessageBox::AcceptRole);
        const QPushButton* const skipButton =
            msgBox.addButton(tr("Skip"), QMessageBox::RejectRole);
        msgBox.setCheckBox(checkbox);

        msgBox.exec();
        const auto* const clickedButton = msgBox.clickedButton();

        if (clickedButton == installButton) {
            updater->downloadUpdate();

            updateProgressDialog = new QProgressDialog(
                tr("Installing update..."),
                tr("Abort"),
                0,
                1,
                this
            );
            updateProgressDialog->setWindowModality(Qt::WindowModal);

            connect(
                updateProgressDialog,
                &QProgressDialog::canceled,
                this,
                [updater] -> void { updater->abortDownload(); }
            );

            connect(
                updater,
                &AutoUpdater::updateDownloadProgress,
                this,
                [this](const u64 received, const u64 total) -> void {
                updateProgressDialog->setMaximum(i32(total));
                updateProgressDialog->setValue(i32(received));
            }
            );
        } else if (clickedButton == skipButton) {
            if (checkbox->isChecked()) {
                settings->core.checkForUpdates = false;
            }

            updater->deleteLater();
        }
    },
        Qt::SingleShotConnection
    );

    connect(
        updater,
        &AutoUpdater::updateFailed,
        this,
        [=, this](const QNetworkReply::NetworkError error) -> void {
        QMessageBox::warning(
            this,
            tr("Update failed"),
            tr("Update failed with error: %1").arg(error)
        );

        updater->deleteLater();
    }
    );

    connect(
        ui->translationTable,
        &TranslationTable::multilineAction,
        this,
        [this](const TranslationTable::MultilineAction action, const u32 count)
            -> void {
        switch (action) {
            case TranslationTable::MultilineAction::Cut:
                ui->statusBar->showMessage(tr("%1 rows cut.").arg(count));
                break;
            case TranslationTable::MultilineAction::Copy:
                ui->statusBar->showMessage(tr("%1 rows copied.").arg(count));
                break;
            case TranslationTable::MultilineAction::Paste:
                ui->statusBar->showMessage(tr("%1 rows pasted.").arg(count));
                break;
        }
    }
    );

    updater->checkForUpdates();
}

// Awful
void MainWindow::openProject(const QString& folder, const bool newProject) {
    if (!QFile::exists(folder)) {
        QMessageBox::critical(
            this,
            tr("Failed to open project"),
            tr("Folder does not exist.")
        );
        return;
    }

    closeProject();

    if (!newProject &&
        !QFile::exists(settings->core.projectPath + PROGRAM_DATA_DIRECTORY)) {
        QMessageBox::critical(
            this,
            tr("Failed to open project"),
            tr(
                "Failed to opened project because couldn't locate `.rpgmtranslate` program directory that was previously located at this path: %1. If this is intentional, please reopen the directory manually."
            )
                .arg(folder + PROGRAM_DATA_DIRECTORY)
        );
        return;
    }

    auto tempProjectSettings = make_shared<ProjectSettings>();
    tempProjectSettings->projectPath = folder;

    const QString rootTranslationPath = folder + TRANSLATION_DIRECTORY;

    const auto postRead = [this, folder, tempProjectSettings, newProject](
                              const std::tuple<FFIString, ByteBuffer> results
                          ) -> result<void, QString> {
        const auto [error, hashes] = results;

        if (error.ptr != nullptr) {
            const QString errorString =
                QString::fromUtf8(error.ptr, isize(error.len));
            rpgm_string_free(error);

            return Err(errorString);
        }

        if (hashes.ptr != nullptr) {
            const u128* const input = ras<const u128*>(hashes.ptr);
            const u32 size = hashes.len;

            tempProjectSettings->hashes.resize(size);
            memcpy(
                tempProjectSettings->hashes.data(),
                input,
                size * sizeof(u128)
            );

            rpgm_buffer_free(hashes);
        }

        const QString projectSettingsPath =
            folder + PROGRAM_DATA_DIRECTORY + PROJECT_SETTINGS_FILE;

        auto projectSettingsFile = QFile(projectSettingsPath);

        if (projectSettingsFile.open(QFile::ReadOnly)) {
            const QByteArray jsonData = projectSettingsFile.readAll();

            QJsonParseError jsonError;
            const QJsonObject settingsObject =
                QJsonDocument::fromJson(jsonData, &jsonError).object();

            if (jsonError.error != QJsonParseError::NoError) {
                qWarning() << "Parsing project-settings.json failed: "_L1
                           << jsonError.errorString();
                //! Could use improper settings, if application aborted (because
                //! of crash, power outage etc.).
                // We guard against it by saving project settings in backup and
                // after creating them
                projectSettings = tempProjectSettings;
            } else {
                projectSettings = make_shared<ProjectSettings>(
                    ProjectSettings::fromJSON(settingsObject)
                );
            }
        } else {
            qWarning() << "Failed to open project-settings.json: %1"_L1
                       << projectSettingsFile.errorString();

            projectSettings = tempProjectSettings;
        }

        projectSettings->projectPath = folder;
        settings->core.projectPath = folder;

        QDir().mkdir(projectSettings->backupPath());
        QDir().mkdir(projectSettings->translationPath());

        u32 totalLines = 0;
        u32 totalTranslated = 0;

        u8 columnCount = max<u8>(2, projectSettings->columns.size());

        const auto translationFiles =
            QDir(projectSettings->translationPath())
                .entryInfoList({ u"*.txt"_s }, QDir::Files);

        vector<TabListItem> tabs;

        // TODO: Explicitly notify the user about the lines that couldn't be
        // splitted.

        for (const auto& fileInfo : translationFiles) {
            auto file = QFile(fileInfo.filePath());

            if (!file.open(QFile::ReadWrite)) {
                qWarning() << "Failed to open file %1: %2"_L1
                                  .arg(fileInfo.filePath())
                                  .arg(file.errorString());
                continue;
            }

            const QByteArray normalized =
                file.readAll().removeIf([](const char byte) -> bool {
                return byte == u'\r';
            });

            file.seek(0);
            file.resize(normalized.size());
            file.write(normalized);

            QString basename = fileInfo.baseName();
            const bool isMap = basename.startsWith("map"_L1);
            const bool isSystem = basename.startsWith("system"_L1);

            const QString content = QString::fromUtf8(normalized);
            const auto contentView = QStringView(content);
            const u32 size = contentView.size();

            u32 pos = 0;
            u32 lineIndex = 0;

            u32 fileTotal = 0;
            u32 fileTranslated = 0;

            QStringView mapID;
            QStringView entry;
            u32 mapSectionStart = 0;

            while (pos < size) {
                const u32 lineStart = pos;
                u32 newlinePos = contentView.indexOf(u'\n', pos);

                if (newlinePos == u32(-1)) {
                    newlinePos = size;
                }

                u32 lineEnd = newlinePos;

                if (lineEnd > lineStart && contentView[lineEnd - 1] == u'\r') {
                    lineEnd--;
                }

                const QStringView line =
                    contentView.sliced(lineStart, lineEnd - lineStart);
                pos = newlinePos + 1;

                if (isSystem && pos >= size) {
                    break;
                }

                if (line.trimmed().isEmpty()) {
                    continue;
                }

                columnCount = max<u8>(columnCount, line.count(SEPARATORL1) + 1);

                if (line.startsWith(BOOKMARK_COMMENT)) {
                    const u32 left =
                        line.indexOf(SEPARATORL1) + SEPARATORL1.size();
                    const isize right = line.indexOf(SEPARATORL1, left);

                    bookmarkMenu->addBookmark(
                        basename,
                        right == -1 ? line.sliced(left)
                                    : line.sliced(left, right - left),
                        lineIndex
                    );

                    lineIndex++;
                    continue;
                }

                if (isMap && line.startsWith(ID_COMMENT)) {
                    if (!mapID.isEmpty()) {
                        if (fileTotal != 0) {
                            const QString tempMapName = u"map"_s + mapID;

                            tabs.emplace_back(
                                tempMapName,
                                fileTotal,
                                fileTranslated,
                                projectSettings->completedFiles.contains(
                                    basename
                                )
                            );

                            totalLines += fileTotal;
                            totalTranslated += fileTranslated;

                            fileTotal = 0;
                            fileTranslated = 0;

                            mapSections.insert(
                                { mapID.toUInt(),
                                  content.sliced(
                                      mapSectionStart,
                                      lineStart - mapSectionStart
                                  ) }
                            );
                        }
                    }

                    mapSectionStart = lineStart;
                    mapID = line.sliced(
                        line.indexOf(SEPARATORL1) + SEPARATORL1.size()
                    );
                    const isize end = mapID.indexOf(SEPARATORL1);

                    if (end != -1) {
                        mapID = mapID.sliced(0, end);
                    }

                    lineIndex++;
                    continue;
                }

                if (!line.startsWith(COMMENT_PREFIX)) {
                    fileTotal++;

                    const QStringView translation =
                        getTranslation(lineParts(line, lineIndex, basename))
                            .translation;

                    if (!translation.isEmpty()) {
                        fileTranslated++;
                    }
                }

                lineIndex++;
            }

            if (fileTotal == 0) {
                continue;
            }

            totalLines += fileTotal;
            totalTranslated += fileTranslated;

            if (isMap) {
                mapSections.insert(
                    { mapID.toUInt(),
                      content.sliced(mapSectionStart, size - mapSectionStart) }
                );
                basename = u"map"_s + mapID;
            }

            tabs.emplace_back(
                basename,
                fileTotal,
                fileTranslated,
                projectSettings->completedFiles.contains(basename)
            );

            if (isSystem &&
                contentView.lastIndexOf("<!-- ID --><#>8"_L1) != -1) {
                const QStringView titleLine =
                    contentView.sliced(contentView.lastIndexOf(u'\n') + 1);
                const QSVList parts = lineParts(titleLine, 0, basename);
                const QStringView translation =
                    getTranslation(parts).translation;
                const QStringView source = getSource(parts);

                ui->gameTitleInput->setPlaceholderText(source.toString());

                if (translation.isEmpty()) {
                    ui->gameTitleInput->setText(source.toString());

                } else {
                    ui->gameTitleInput->setText(translation.toString());
                }

                const u16 textWidth =
                    QFontMetrics(qApp->font())
                        .horizontalAdvance(ui->gameTitleInput->text());

                const QMargins margins = ui->gameTitleInput->textMargins();

                const u16 frame = ui->gameTitleInput->style()->pixelMetric(
                                      QStyle::PM_DefaultFrameWidth
                                  ) *
                                  2;

                constexpr u8 GAME_TITLE_INPUT_PADDING = 32;
                const u16 finalWidth = textWidth + margins.left() +
                                       margins.right() + frame +
                                       GAME_TITLE_INPUT_PADDING;

                ui->gameTitleInput->setMinimumWidth(finalWidth);
                ui->gameTitleInput->setCursorPosition(0);
            }

            qInfo() << tr("%1: Successfully parsed.").arg(fileInfo.filePath());
        }

        searchMenu->setFiles(tabs);
        batchMenu->setFiles(tabs);
        glossaryMenu->setFiles(tabs);
        readMenu->setFiles(tabs);
        purgeMenu->setFiles(tabs);
        writeMenu->setFiles(tabs);
        bookmarkMenu->setFiles(tabs);
        ui->searchPanel->setFiles(tabs);
        ui->tabPanel->setTabs(std::move(tabs));

        {
            auto glossaryFile = QFile(projectSettings->glossaryPath());

            if (glossaryFile.open(QFile::ReadOnly)) {
                QJsonParseError jsonError;

                const QJsonArray glossaryArray =
                    QJsonDocument::fromJson(glossaryFile.readAll(), &jsonError)
                        .array();

                if (jsonError.error != QJsonParseError::NoError) {
                    qWarning() << "Parsing glossary.json failed: "_L1
                               << jsonError.errorString();
                } else {
                    glossaryMenu->fill(Glossary::fromJSON(glossaryArray));
                }
            } else {
                qWarning() << "Failed to open glossary.json: "_L1
                           << glossaryFile.errorString();
            }
        }

        if (projectSettings->columns.empty()) {
            projectSettings->columns.emplace_back(
                tr("Source"),
                DEFAULT_COLUMN_WIDTH
            );
        }

        while (columnCount > projectSettings->columns.size()) {
            projectSettings->columns.emplace_back(
                tr("Translation"),
                DEFAULT_COLUMN_WIDTH
            );
        }

        for (const auto& column : views::drop(projectSettings->columns, 1)) {
            batchMenu->addColumn(column.name);
            searchMenu->addColumn(column.name);
        }

        assetMenu->init(projectSettings);
        readMenu->init(projectSettings);
        taskWorker->init(settings, projectSettings, &mapSections);

        ui->translationTable->init(
            &projectSettings->lineLengthHint,
            &settings->appearance.displayTrailingWhitespace,
            &projectSettings->spellcheckDictionary
        );

        actionTabPanel->setEnabled(true);
        actionSave->setEnabled(true);
        actionWrite->setEnabled(true);
        actionSearch->setEnabled(true);
        actionBatchMenu->setEnabled(true);
        actionGlossaryMenu->setEnabled(true);
        actionMatchMenu->setEnabled(true);
        actionTranslationsMenu->setEnabled(true);
        actionBookmarkMenu->setEnabled(true);
        actionSourceControl->setEnabled(true);
        actionAssets->setEnabled(true);
        ui->rvpackerButton->setEnabled(true);
        ui->gameTitleInput->setEnabled(true);
        actionLocateProjectDir->setEnabled(true);
        actionSearchPanel->setEnabled(true);

        ui->globalProgressBar->setEnabled(true);
        ui->globalProgressBar->setMaximum(i32(totalLines));
        ui->globalProgressBar->setValue(i32(totalTranslated));

        if (settings->core.backup.enabled) {
            backupTimer.start((settings->core.backup.period * SECOND_MS));
        }

        if (!settings->core.recentProjects.contains(folder)) {
            settings->core.recentProjects.append(folder);
            const QAction* const action =
                ui->actionRecentProjects->menu()->addAction(folder);

            connect(action, &QAction::triggered, this, [this, folder] -> void {
                openProject(folder, true);
            });
        }

        if (settings->core.recentProjects.size() > MAX_RECENT_PROJECTS) {
            settings->core.recentProjects.removeFirst();
            ui->actionRecentProjects->menu()->removeAction(
                as<QAction*>(ui->actionRecentProjects->menu()->children()[0])
            );
        }

        ui->statusBar->showMessage(tr(
            "Before working with the program, check out documentation in Help > Documentation!"
        ));

        saveProjectSettings();

#ifdef ENABLE_LIBGIT2
        ui->sourceControlDock->setProjectPath(projectSettings->projectPath);
#endif

        firstReadPending = false;

        return {};
    };

    const auto postArchive = [this, tempProjectSettings, postRead](
                                 const QString& sourcePath,
                                 const QString& translationPath,
                                 const QString& title
                             ) {
        QMetaObject::invokeMethod(
            taskWorker,
            &TaskWorker::read,
            Qt::QueuedConnection,
            sourcePath,
            translationPath,
            ReadMode::Default,
            tempProjectSettings->engineType,
            readMenu->duplicateMode(),
            Selected{},
            readMenu->flags(),
            readMenu->parseMapEvents(),
            ByteBuffer{ .ptr = nullptr, .len = 0 },
            title
        );

        connect(
            taskWorker,
            &TaskWorker::readFinished,
            this,
            [this, postRead](const std::tuple<FFIString, ByteBuffer> results)
                -> void {
            const auto result = postRead(results);

            if (!result) {
                QMessageBox::critical(
                    this,
                    tr("Failed to load project"),
                    result.error()
                );
            }

            QTimer::singleShot(3000, [this] -> void {
                ui->taskLabel->setText(tr("No Tasks"));
                ui->taskProgressBar->setMaximum(0);
                ui->taskProgressBar->setValue(0);
                ui->taskProgressBar->setEnabled(false);
            });
        },
            Qt::SingleShotConnection
        );
    };

    const auto startOpening = [this,
                               folder,
                               rootTranslationPath,
                               tempProjectSettings,
                               postRead,
                               postArchive] -> result<void, QString> {
        if (QFile::exists(folder + u"/Data")) {
            tempProjectSettings->sourceDirectory =
                SourceDirectory::UppercaseData;
        }

        if (QFile::exists(folder + u"/data")) {
            tempProjectSettings->sourceDirectory =
                SourceDirectory::LowercaseData;
        }

        if (!QFile::exists(
                folder + PROGRAM_DATA_DIRECTORY + TRANSLATION_DIRECTORY
            )) {
            bool copied = false;

            if (QFile::exists(rootTranslationPath)) {
                const auto selected = QMessageBox::question(
                    this,
                    tr("Existing translation folder"),
                    tr(
                        "Translation folder is found in the root of the project. Use it?"
                    )
                );

                if (selected == QMessageBox::Yes) {
                    QDir().mkpath(
                        folder + PROGRAM_DATA_DIRECTORY + TRANSLATION_DIRECTORY
                    );

                    try {
                        fs::copy(
                            rootTranslationPath.toStdString(),
                            (folder + PROGRAM_DATA_DIRECTORY +
                             TRANSLATION_DIRECTORY)
                                .toStdString(),
                            fs::copy_options::recursive |
                                fs::copy_options::overwrite_existing
                        );
                        copied = true;
                    } catch (const fs::filesystem_error& err) {
                        // TODO: Add directory name
                        qWarning()
                            << u"Failed to copy directory: "_s << err.what();
                    }
                }
            }

            if (!copied) {
                QString archivePath;
                bool systemExists = false;

                if (QFile::exists(
                        tempProjectSettings->sourcePath() + u"/System.json"
                    )) {
                    tempProjectSettings->engineType = EngineType::New;
                    systemExists = true;
                } else if (
                    QFile::exists(
                        tempProjectSettings->sourcePath() + u"/System.rvdata2"
                    )
                ) {
                    tempProjectSettings->engineType = EngineType::VXAce;
                    systemExists = true;
                } else if (
                    QFile::exists(
                        tempProjectSettings->sourcePath() + u"/System.rvdata"
                    )
                ) {
                    tempProjectSettings->engineType = EngineType::VX;
                    systemExists = true;
                } else if (
                    QFile::exists(
                        tempProjectSettings->sourcePath() + u"/System.rxdata"
                    )
                ) {
                    tempProjectSettings->engineType = EngineType::XP;
                    systemExists = true;
                }

                if (!systemExists) {
                    bool archiveExists = false;

                    if (archivePath =
                            tempProjectSettings->projectPath + u"/Game.rgssad";
                        QFile::exists(archivePath)) {
                        tempProjectSettings->engineType = EngineType::XP;
                        archiveExists = true;
                    } else if (
                        archivePath =
                            tempProjectSettings->projectPath + u"/Game.rgss2a";
                        QFile::exists(archivePath)
                    ) {
                        tempProjectSettings->engineType = EngineType::VX;
                        archiveExists = true;
                    } else if (
                        archivePath =
                            tempProjectSettings->projectPath + u"/Game.rgss3a";
                        QFile::exists(archivePath)
                    ) {
                        tempProjectSettings->engineType = EngineType::VXAce;
                        archiveExists = true;
                    }

                    if (!archiveExists) {
                        return Err(tr(
                            "Source files, translation or archive file do not exist."
                        ));
                    }

                    tempProjectSettings->sourceDirectory =
                        SourceDirectory::UppercaseData;
                }

                firstReadPending = true;

                readMenu->show();
                readMenu->move(
                    (width() / 2) - (readMenu->width() / 2),
                    (height() / 2) - (readMenu->height() / 2)
                );

                if (readMenu->exec(
                        tempProjectSettings->projectPath,
                        tempProjectSettings->engineType
                    ) != QDialog::Accepted) {
                    return Err(tr("Read was rejected by user."));
                }

                connect(
                    taskWorker,
                    &TaskWorker::extractFinished,
                    this,
                    [this,
                     tempProjectSettings,
                     postArchive](const FFIString error) -> void {
                    if (error.ptr != nullptr) {
                        QMessageBox::critical(
                            this,
                            tr("Failed to load project"),
                            QString::fromUtf8(error.ptr, isize(error.len))
                        );
                        rpgm_string_free(error);
                        return;
                    }

                    postArchive(
                        tempProjectSettings->sourcePath(),
                        tempProjectSettings->translationPath(),
                        readMenu->title()
                    );
                },
                    Qt::SingleShotConnection
                );

                if (!systemExists) {
                    QMetaObject::invokeMethod(
                        taskWorker,
                        &TaskWorker::extractArchive,
                        Qt::QueuedConnection,
                        archivePath,
                        folder
                    );
                }

                emit taskWorker->extractFinished({});
            }
        }

        return postRead({ { .ptr = nullptr, .len = 0 }, {} });
    };

    const auto result = startOpening();

    if (!result) {
        QMessageBox::critical(
            this,
            tr("Failed to load project"),
            result.error()
        );
        return;
    }
}

void MainWindow::closeEvent(QCloseEvent* const event) {
    exit();
    event->ignore();
}

void MainWindow::changeTab(
    const QString& tabName,
    const QString& previousTabName
) {
    // TODO: ui->tabPanel->changeTab(previousTabName) may not work as expected

    if (!previousTabName.isEmpty()) {
        const bool success = saveCurrentTab(previousTabName);

        if (!success) {
            ui->tabPanel->changeTab(previousTabName);
            return;
        }
    }

    if (tabName.isEmpty()) {
        ui->translationTable->model()->clear();
        linesStatusLabel->clear();
        progressStatusLabel->clear();
        tabNameStatusLabel->clear();
    } else {
        if (tabName == lockedFile) {
            QMessageBox::warning(
                this,
                tr("File is unavailable"),
                tr("File is currently processed and is being locked.")
            );
            ui->tabPanel->changeTab(previousTabName);
            return;
        }

        const auto result =
            fileLines(QL1SV(tabName.toLatin1()), mapSections, projectSettings);

        if (!result) {
            QMessageBox::warning(
                this,
                tr("Failed to open file"),
                tr("Failed to open tab: %1.").arg(result.error())
            );
            ui->tabPanel->changeTab(previousTabName);
            return;
        }

        QSVList lines = result.value().lines;

        const bool isSystem = tabName.startsWith("system"_L1);
        const bool gameTitleAbsent =
            !ui->gameTitleInput->placeholderText().isEmpty();

        ui->translationTable->fill(
            views::drop(lines, isSystem && gameTitleAbsent ? 1 : 0),
            projectSettings->columns,
            tabName
        );

        linesStatusLabel->setText(
            tr("%1 Lines / %2 Comments")
                .arg(lines.size())
                .arg(lines.size() - ui->tabPanel->currentTotal())
        );
        progressStatusLabel->setText(tr("%1 Translated / %2 Total")
                                         .arg(ui->tabPanel->currentTranslated())
                                         .arg(ui->tabPanel->currentTotal()));
        tabNameStatusLabel->setText(tabName);

        // TODO: Display total source words/characters in the status bar
    }
}

auto MainWindow::saveCurrentTab(QString tabName) -> bool {
start:
    QString* mapSection = nullptr;

    if (tabName.isEmpty()) {
        tabName = ui->tabPanel->currentTabName();

        if (tabName.isEmpty()) {
            return true;
        }
    }

    if (tabName.startsWith("map"_L1)) {
        mapSection =
            &mapSections.find(QStringView(tabName).sliced(3).toUInt())->second;
        mapSection->clear();
    }

    unique_ptr<QFile> file;
    unique_ptr<QTextStream> stream;

    if (mapSection == nullptr) {
        QString filePath;

        if (!tabName.startsWith("map"_L1)) {
            filePath = projectSettings->translationPath();
        }

        filePath += u'/' + tabName + TXT_EXTENSION;
        file = make_unique<QFile>(filePath);

        if (!file->open(QFile::WriteOnly | QFile::Truncate)) {
            const auto result = handleOpenError(filePath, file->errorString());
            const auto index = result.index();

            switch (index) {
                case 0:
                    break;
                case 1: {
                    const QString& dir = std::get<1>(result).s;
                    filePath = dir + u'/' + tabName + TXT_EXTENSION;
                    file = make_unique<QFile>(filePath);

                    if (!file->open(QFile::WriteOnly | QFile::Truncate)) {
                        QMessageBox::critical(
                            this,
                            tr("Failed to open file"),
                            tr(
                                "Failed to open file %1: %2. Starting from the beginning."
                            )
                                .arg(filePath)
                                .arg(file->errorString())
                        );

                        goto start;
                    }

                    break;
                }
                case 2:
                    return false;
                    break;
                case 3:
                    goto start;
                    break;
                default:
                    std::unreachable();
            }
        }

        stream = make_unique<QTextStream>(file.get());
        stream->setEncoding(QStringConverter::Utf8);
    } else {
        stream = make_unique<QTextStream>(mapSection, QFile::ReadOnly);
    }

    TranslationTableModel* const model = ui->translationTable->model();

    for (const i32 row : range(0, model->rowCount())) {
        if ((model->flags(model->index(row, 1)) & Qt::ItemIsEditable) == 0) {
            *stream << *model->item(row, 0).text();
        } else {
            auto fields = QStringList(model->columnCount());

            for (const u8 column : range<u8>(0, model->columnCount())) {
                const auto item = model->item(row, column);

                if (item.text()->isNull()) {
                    qWarning() << u"Item at row %1 and column %2 is nullptr."_s
                                      .arg(row, column);
                    continue;
                }

                const QString* const text = item.text();
                fields[column] = qsvReplace(
                    QStringView(text->data(), text->size()),
                    LINE_FEED,
                    NEW_LINE
                );
            }

            *stream << fields.join(SEPARATORL1);
        }

        *stream << u'\n';
    }

    if (tabName == "system"_L1) {
        const QString placeholder = ui->gameTitleInput->placeholderText();
        const QString text = ui->gameTitleInput->text();

        *stream << placeholder;
        *stream << SEPARATORL1;

        if (text != placeholder) {
            *stream << ui->gameTitleInput->text();
        }
    }

    ui->statusBar->showMessage(
        tr("Tab %1 saved.")
            .arg(tabName.isEmpty() ? ui->tabPanel->currentTabName() : tabName)
    );

    return true;
}

auto MainWindow::saveMaps() -> bool {
start:

    QString mapsPath = projectSettings->translationPath() + u"/maps.txt";
    auto mapsFile = make_unique<QFile>(mapsPath);

    if (!mapsFile->open(QFile::WriteOnly | QFile::Truncate)) {
        const auto result = handleOpenError(mapsPath, mapsFile->errorString());
        const auto index = result.index();

        switch (index) {
            case 0:
                break;
            case 1: {
                const QString& dir = std::get<1>(result).s;
                mapsPath = dir + u"/maps.txt";
                mapsFile = make_unique<QFile>(mapsPath);

                if (!mapsFile->open(QFile::WriteOnly | QFile::Truncate)) {
                    QMessageBox::critical(
                        this,
                        tr("Failed to open file"),
                        tr(
                            "Failed to open file %1: %2. Starting from the beginning."
                        )
                            .arg(mapsPath)
                            .arg(mapsFile->errorString())
                    );

                    goto start;
                }

                break;
            }
            case 2:
                return false;
                break;
            case 3:
                goto start;
                break;
            default:
                std::unreachable();
        }
    }

    auto stream = QTextStream(mapsFile.get());

    auto keys = ranges::to<std::vector>(views::keys(mapSections));
    ranges::sort(keys);

    for (const auto key : keys) {
        const auto& content = mapSections[key];
        stream << content;
    }

    ui->statusBar->showMessage(tr("maps.txt saved."));

    return true;
}

void MainWindow::saveBackup() {
    const auto saveSuccess = saveCurrentTab();

    if (!saveSuccess) {
        return;
    }

    const QString backupPath = projectSettings->backupPath();
    const QList<QFileInfo> entries =
        QDir(backupPath).entryInfoList(QDir::Dirs, QDir::Time);

    if (entries.size() > settings->core.backup.max) {
        QFile::remove(entries.first().filePath());
    }

    const auto date = QDate::currentDate();
    const auto time = QTime::currentTime();

    auto backupDirName = u"/%1-%2-%3_%4-%5-%6"_s.arg(date.day())
                             .arg(date.month())
                             .arg(date.year())
                             .arg(time.hour())
                             .arg(time.minute())
                             .arg(time.second());

    try {
        fs::copy(
            projectSettings->translationPath().toStdString(),
            (projectSettings->backupPath() + backupDirName).toStdString(),
            fs::copy_options::recursive | fs::copy_options::overwrite_existing
        );
    } catch (const fs::filesystem_error& error) {
        qWarning() << u"Failed to save backup: " << error.what();
        return;
    }

    saveGlossary();
    saveProjectSettings();

    ui->statusBar->showMessage(
        tr("Backup %1 created.").arg(backupDirName.slice(1))
    );
}

void MainWindow::appendMatches(
    const QString& filename,
    const QStringView source,
    const QStringView translation,
    const Term& term,
    const u32 idx
) {
    const QByteArray sourceUtf8 = source.toUtf8();
    const QByteArray termUtf8 = term.term.toUtf8();
    const QByteArray termTranslationUtf8 = term.translation.toUtf8();
    const QByteArray translationUtf8 = translation.toUtf8();

    ByteBuffer matches;

    const FFIString error = rpgm_find_all_matches(
        toffistr(sourceUtf8),
        toffistr(termUtf8),
        term.sourceMatchMode,
        toffistr(translationUtf8),
        toffistr(termTranslationUtf8),
        term.translationMatchMode,
        Algorithm::English,
        Algorithm::Russian,
        &matches
    );

    if (error.ptr != nullptr) {
        QMessageBox::critical(
            this,
            tr("Matching failed"),
            QString::fromUtf8(error.ptr, isize(error.len))
        );
        rpgm_string_free(error);
        return;
    }

    ui->matchMenu->appendMatch(
        filename,
        idx + 1,
        term.term,
        term.translation,
        source,
        translation,
        matches
    );

    rpgm_buffer_free(matches);
}

void MainWindow::closeProject() {
    glossaryMenu->hide();
    bookmarkMenu->hide();
    searchMenu->hide();
    batchMenu->hide();
    searchMenu->hide();
    ui->matchMenu->hide();
    translationsMenu->hide();
    assetMenu->hide();

    ui->tabPanel->changeTab(QString());

    mapSections.clear();

    ui->tabPanel->clear();

    glossaryMenu->clear();
    bookmarkMenu->clear();
    searchMenu->clear();
    batchMenu->clear();
    searchMenu->clear();
    ui->matchMenu->clear();
    translationsMenu->clear();
    assetMenu->clear();

    ui->searchPanel->clear();

    readMenu->clear();
    purgeMenu->clear();
    writeMenu->clear();

    actionTabPanel->setEnabled(false);
    actionSave->setEnabled(false);
    actionWrite->setEnabled(false);
    actionSearch->setEnabled(false);
    actionBatchMenu->setEnabled(false);
    actionGlossaryMenu->setEnabled(false);
    actionMatchMenu->setEnabled(false);
    actionTranslationsMenu->setEnabled(false);
    actionBookmarkMenu->setEnabled(false);
    actionSourceControl->setEnabled(false);
    actionAssets->setEnabled(false);
    ui->rvpackerButton->setEnabled(false);

    ui->gameTitleInput->setEnabled(false);
    ui->gameTitleInput->clear();
    ui->gameTitleInput->setPlaceholderText(QString());

    actionLocateProjectDir->setEnabled(false);
    actionSearchPanel->setEnabled(false);

    ui->globalProgressBar->setMaximum(0);
    ui->globalProgressBar->setValue(0);
    ui->globalProgressBar->setEnabled(false);

    ui->taskProgressBar->setMaximum(0);
    ui->taskProgressBar->setValue(0);
    ui->taskProgressBar->setEnabled(false);
    ui->taskLabel->setText(tr("No Tasks"));

    ui->statusBar->clearMessage();

    backupTimer.stop();

    projectSettings.reset();
}

auto MainWindow::handleOpenError(const QString& path, const QString& error)
    -> ControlFlow {
    qWarning() << "Failed to save file %1: %2"_L1.arg(path).arg(error);

    auto messageBox = QMessageBox(this);
    messageBox.setIcon(QMessageBox::Warning);
    messageBox.setWindowTitle(tr("Warning"));
    messageBox.setText(tr("Saving file failed"));
    messageBox.setInformativeText(
        tr(
            "Unable to save file %1: %2. You may try to save the file to a custom location. It's strongly advised to you to better close the program and fix the underlying issue before continuing your work."
        )
            .arg(path)
            .arg(error)
    );

    const QPushButton* const continueBtn =
        messageBox.addButton(tr("Continue anyway"), QMessageBox::AcceptRole);
    QPushButton* const retryBtn =
        messageBox.addButton(tr("Retry"), QMessageBox::ResetRole);
    const QPushButton* const saveButton = messageBox.addButton(
        tr("Save to custom location"),
        QMessageBox::ActionRole
    );
    QPushButton* const abortBtn =
        messageBox.addButton(tr("Abort"), QMessageBox::RejectRole);

    messageBox.setDefaultButton(retryBtn);
    messageBox.setEscapeButton(abortBtn);

    messageBox.exec();
    const auto* const clicked = messageBox.clickedButton();

    if (clicked == continueBtn) {
        return ContinueAnyway();
    }

    if (clicked == retryBtn) {
        return Retry();
    }

    if (clicked == saveButton) {
        const QString dir = QFileDialog::getExistingDirectory(this);

        return Continue(dir);
    }

    return Abort();
}

void MainWindow::updateTask(
    const TaskWorker::Task task,
    const u32 progress,
    const u32 total
) {
    ui->taskProgressBar->setEnabled(true);
    ui->taskProgressBar->setMaximum(i32(total));
    ui->taskProgressBar->setValue(i32(progress));

    const bool finished = progress == total;

    switch (task) {
        case TaskWorker::Task::Search:
            ui->taskLabel->setText(
                finished ? tr("Search finished.") : tr("Searching...")
            );
            break;
        case TaskWorker::Task::Replace:
            ui->taskLabel->setText(
                finished ? tr("Replace finished.") : tr("Replacing...")
            );
            break;
        case TaskWorker::Task::Put:
            ui->taskLabel->setText(
                finished ? tr("Put finished.") : tr("Putting...")
            );
            break;
        case TaskWorker::Task::BatchTrim:
            ui->taskLabel->setText(
                finished ? tr("Trim finished.") : tr("Trimming...")
            );
            break;
        case TaskWorker::Task::BatchTranslate:
            if (progress == 0 && total == 0) {
                ui->taskLabel->setText(tr("Sending translation request..."));
                return;
            }

            ui->taskLabel->setText(
                finished ? tr("Translate finished.") : tr("Translating...")
            );
            break;
        case TaskWorker::Task::BatchWrap:
            ui->taskLabel->setText(
                finished ? tr("Wrap finished.") : tr("Wrapping...")
            );
            break;
    }

    if (finished) {
        QTimer::singleShot(3000, [this] -> void {
            ui->taskLabel->setText(tr("No Tasks"));
            ui->taskProgressBar->setMaximum(0);
            ui->taskProgressBar->setValue(0);
            ui->taskProgressBar->setEnabled(false);
        });
    }
};
