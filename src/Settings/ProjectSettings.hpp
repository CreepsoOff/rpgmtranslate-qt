#pragma once

#include "Aliases.hpp"
#include "Constants.hpp"
#include "rpgmtranslate.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QStringList>

struct ColumnInfo {
    QString name;
    u16 width;
};

enum class SourceDirectory : u8 {
    None,
    UppercaseData,
    LowercaseData,
    WwwLowercaseData,
};

struct ProjectSettings {
    vector<u128> hashes;
    QStringList completedFiles;

    vector<ColumnInfo> columns;

    QString projectPath;
    QString spellcheckDictionary;
    QString sourceLockPath;
    QString lastSeenGameDataFingerprint;
    QString lastPromptedGameDataFingerprint;

    QString projectContext;
    HashMap<QString, QString> fileContexts;

    u16 sourceColumnWidth = DEFAULT_COLUMN_WIDTH;
    u16 lineLengthHint = 0;

    EngineType engineType = EngineType::New;

    Algorithm sourceLang = Algorithm::None;
    Algorithm translationLang = Algorithm::None;

    DuplicateMode duplicateMode = DuplicateMode::Allow;
    BaseFlags flags = BaseFlags(0);

    SourceDirectory sourceDirectory = SourceDirectory::None;

    [[nodiscard]] auto programDataPath() const -> QString {
        return projectPath + PROGRAM_DATA_DIRECTORY;
    }

    [[nodiscard]] auto sourcePath() const -> QString {
        switch (sourceDirectory) {
            case SourceDirectory::UppercaseData:
                return projectPath + u"/Data";
            case SourceDirectory::LowercaseData:
                return projectPath + u"/data";
            case SourceDirectory::WwwLowercaseData:
                return projectPath + u"/www/data";
            default:
                return {};
        }
    }

    [[nodiscard]] auto resolvedSourcePath() const -> QString {
        return sourceLockPath.isEmpty() ? sourcePath() : sourceLockPath;
    }

    [[nodiscard]] auto translationPath() const -> QString {
        return programDataPath() + TRANSLATION_DIRECTORY;
    }

    [[nodiscard]] auto projectSettingsPath() const -> QString {
        return programDataPath() + PROJECT_SETTINGS_FILE;
    }

    [[nodiscard]] auto backupPath() const -> QString {
        return programDataPath() + BACKUP_DIRECTORY;
    }

    [[nodiscard]] auto outputPath() const -> QString {
        return programDataPath() + OUTPUT_DIRECTORY;
    }

    [[nodiscard]] auto glossaryPath() const -> QString {
        return programDataPath() + GLOSSARY_FILE;
    }

    [[nodiscard]] auto serializeTranslationColumns() const -> QJsonArray;
    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj)
        -> ProjectSettings;
};
