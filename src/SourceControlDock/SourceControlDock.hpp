#pragma once

#ifdef ENABLE_LIBGIT2
#include "Aliases.hpp"
#include "FWD.hpp"
#include "GitChangesList.hpp"
#include "ezgit2.hpp"

#include <QDockWidget>
#include <QFileSystemWatcher>

class SourceControlDock final : public QDockWidget {
    Q_OBJECT

   public:
    using QDockWidget::QDockWidget;

    void init(
        QComboBox* branchSelect,
        GitChangesList* changesList,
        GitCommitList* commitList,

        QPushButton* commitButton,
        QToolButton* commitOptionsButton,

        QPlainTextEdit* commitMessageInput,

        QPushButton* copyTranslationButton,
        QToolButton* refreshChangesButton
    );
    [[nodiscard]] auto setProjectPath(const QString& projectPath)
        -> result<void, QString>;

   private:
    ezgit2::ezgit2 ezgit2;
    ezgit2::Repository repo;

    QPushButton* commitButton;
    QToolButton* commitOptionsButton;

    QPlainTextEdit* commitMessageInput;

    QComboBox* branchSelect;
    GitChangesList* changesList;
    GitCommitList* commitList;
};
#else
#include <QDockWidget>

class SourceControlDock final : public QDockWidget {
   public:
    using QDockWidget::QDockWidget;
};
#endif
