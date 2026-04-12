#pragma once

#include "Constants.hpp"
#include "rpgmtranslate.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QList>

enum class TagReplacementMode : u8 {
    Remove = 0,
    Space = 1,
    Newline = 2,
    Custom = 3,
};

struct TagRule {
    QString name;
    QString pattern;
    QString customReplacement;
    TagReplacementMode replacement = TagReplacementMode::Remove;
    bool isRegex = false;
    bool caseSensitive = false;
    bool enabled = true;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj) -> TagRule;
};

struct Backup {
    u16 period = MIN_BACKUP_PERIOD;
    u8 max = MAX_BACKUPS;

    bool enabled = true;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj) -> Backup;
};

struct CoreSettings {
    QStringList recentProjects;
    QString projectPath;

    Backup backup;

    bool checkForUpdates = true;
    bool firstLaunch = true;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj) -> CoreSettings;
};

struct AppearanceSettings {
    QString translationTableFont;
    QString style;

    Qt::ColorScheme theme = Qt::ColorScheme::Unknown;
    QLocale::Language language = QLocale().language();

    u8 translationTableFontSize = 0;

    bool displayPercents = false;
    bool displayTrailingWhitespace = false;
    bool displayWordsAndCharacters = false;
    bool previewTagsEnabled = false;

    QList<TagRule> customTagRules;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj)
        -> AppearanceSettings;
};

struct GoogleEndpointSettings {
    bool singleTranslation = false;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj)
        -> GoogleEndpointSettings;
};

struct YandexEndpointSettings {
    QString apiKey;
    QString folderId;
    bool singleTranslation = false;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj)
        -> YandexEndpointSettings;
};

struct DeepLEndpointSettings {
    QString apiKey;
    bool useGlossary = false;
    bool singleTranslation = false;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj)
        -> DeepLEndpointSettings;
};

struct EndpointSettings {
    constexpr static u16 DEFAULT_TOKEN_LIMIT = 4000;

    QString name;
    QString apiKey;
    QString yandexFolderID;
    QString baseUrl;
    QString model;
    QString systemPrompt;
    QString singleTranslateSystemPrompt;

    optional<f32> temperature;
    optional<f32> frequencyPenalty;
    optional<f32> precensePenalty;
    optional<f32> topP;

    u16 tokenLimit = DEFAULT_TOKEN_LIMIT;
    u16 outputTokenLimit = UINT16_MAX;

    u16 thinkingBudget = UINT16_MAX;

    // TODO: Reasoning effort

    bool useGlossary = false;
    bool thinking = false;

    bool singleTranslation = false;

    TranslationEndpoint type;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj)
        -> EndpointSettings;
};

struct LanguageToolSettings {
    QString baseURL;

    QString apiKey;
    QString username;

    QString level;
    QString motherTongue;
    QString preferredVariants;
    QString dicts;

    QString enabledLints;
    QString disabledLints;

    QString enabledCategories;
    QString disabledCategories;

    bool enabledOnly;

    bool enabled = false;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj)
        -> LanguageToolSettings;
};

struct TranslationSettings {
    LanguageToolSettings languageTool;

    vector<EndpointSettings> endpoints;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    static auto fromJSON(const QJsonObject& obj) -> TranslationSettings;
};

struct ControlSettings {
    QString searchPanel = u"Ctrl+R"_s;
    QString tabPanel = u"Tab"_s;
    QString goToRow = u"Ctrl+G"_s;
    QString batchMenu = u"Ctrl+B"_s;
    QString bookmarkMenu = u"Alt+B"_s;
    QString matchMenu = u"Ctrl+M"_s;
    QString glossaryMenu = u"Alt+B"_s;
    QString translationsMenu = u"Ctrl+S"_s;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj)
        -> ControlSettings;
};

struct Settings {
    CoreSettings core;
    ControlSettings controls;
    AppearanceSettings appearance;
    TranslationSettings translation;

    [[nodiscard]] auto toJSON() const -> QJsonObject;
    [[nodiscard]] static auto fromJSON(const QJsonObject& obj) -> Settings;
};
