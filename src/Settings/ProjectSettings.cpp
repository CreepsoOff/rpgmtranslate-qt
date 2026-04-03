#include "ProjectSettings.hpp"

auto tou128(const QString& str) -> u128 {
    u128 result = 0;

    for (const QChar chr : str) {
        result = (result * 10) + (chr.toLatin1() - '0');
    }

    return result;
}

#ifdef Q_CC_MSVC
[[nodiscard]] auto uint128_to_string(u128 value) -> QString {
    constexpr u64 BASE = 10000000000000000000ULL;
    array<u64, 3> parts{};
    i32 idx = 0;

    while (value > 0) {
        parts[idx++] = u64(value % BASE);
        value /= BASE;
    }

    QString result = QString::number(parts[idx - 1]);

    for (i32 j = idx - 2; j >= 0; --j) {
        QString chunk = QString::number(parts[j]);
        result += QString(19 - chunk.length(), u'0') + chunk;
    }

    return result;
}
#endif

[[nodiscard]] auto ProjectSettings::toJSON() const -> QJsonObject {
    QJsonArray hashes;

    for (const u128 hash : this->hashes) {
        hashes.append(
#ifdef Q_CC_MSVC
            uint128_to_string(hash)
#else
            QString::fromLatin1(std::format("{}", hash))
#endif
        );
    }

    QJsonArray contexts;

    for (const auto& [key, value] : fileContexts) {
        contexts.append(QJsonArray{ key, value });
    }

    return { {
        { u"engineType"_s, u8(engineType) },
        { u"sourceLang"_s, i8(sourceLang) },
        { u"translationLang"_s, i8(translationLang) },
        { u"duplicateMode"_s, u8(duplicateMode) },
        { u"flags"_s, u8(flags) },
        { u"hashes"_s, hashes },
        { u"completed"_s, QJsonArray::fromStringList(completedFiles) },
        { u"lineLengthHint"_s, lineLengthHint },
        { u"sourceColumnWidth"_s, sourceColumnWidth },
        { u"translationColumns"_s, serializeTranslationColumns() },
        { u"sourceDirectory"_s, u8(sourceDirectory) },
        { u"spellcheckDictionaryPath"_s, spellcheckDictionary },
        { u"projectContext"_s, projectContext },
        { u"fileContexts"_s, contexts },
    } };
}

auto ProjectSettings::fromJSON(const QJsonObject& obj) -> ProjectSettings {
    ProjectSettings settings;

    settings.engineType = EngineType(obj["engineType"_L1].toInt());
    settings.sourceLang = Algorithm(obj["sourceLang"_L1].toInt());
    settings.translationLang = Algorithm(obj["translationLang"_L1].toInt());
    settings.duplicateMode = DuplicateMode(obj["duplicateMode"_L1].toInt());
    settings.flags = BaseFlags(obj["flags"_L1].toInt());

    QStringList hashes = obj["hashes"_L1].toVariant().toStringList();
    settings.hashes.reserve(hashes.size());

    for (const auto& hash : hashes) {
        settings.hashes.emplace_back(tou128(hash));
    }

    settings.completedFiles = obj["completed"_L1].toVariant().toStringList();

    settings.lineLengthHint = obj["lineLengthHint"_L1].toInt();
    settings.sourceColumnWidth = obj["sourceColumnWidth"_L1].toInt();

    settings.sourceDirectory =
        SourceDirectory(obj["sourceDirectory"_L1].toInt());

    settings.spellcheckDictionary =
        obj["spellcheckDictionaryPath"_L1].toString();
    settings.projectContext = obj["projectContext"_L1].toString();

    auto contextsArray = obj["fileContexts"_L1].toArray();
    settings.fileContexts.reserve(contextsArray.size());

    for (const auto& pair : contextsArray) {
        const auto pairArray = pair.toArray();

        settings.fileContexts.insert(
            { pairArray[0].toString(), pairArray[1].toString() }
        );
    }

    const auto columns = obj["translationColumns"_L1].toArray();
    settings.columns.reserve(columns.size());

    for (const auto& value : columns) {
        const auto arr = value.toArray();
        settings.columns.emplace_back(arr[0].toString(), u16(arr[1].toInt()));
    }

    return settings;
}

[[nodiscard]] auto ProjectSettings::serializeTranslationColumns() const
    -> QJsonArray {
    QJsonArray array;

    for (const auto& column : columns) {
        QJsonArray jsonColumn = { column.name, column.width };
        array.append(jsonColumn);
    }

    return array;
}
