#![allow(clippy::too_many_arguments)]
use language_tokenizer::{
    Algorithm, MatchMode, MatchResult, find_all_matches as find_all_matches_,
    tokenize,
};
#[cfg(feature = "languagetool")]
use languagetool_rust::api::{
    check::Request as LTRequest, server::ServerClient,
};
use llm_connector::{
    LlmClient, LlmConnectorError,
    types::{ChatRequest, Message, Role},
};
use log::{debug, info};
use regex::Regex;
use rpgmad_lib::{Decrypter, ExtractError};
use rvpacker_txt_rs_lib::{
    BaseFlags, DuplicateMode, EngineType, FileFlags, GameType, PurgerBuilder,
    ReadMode, ReaderBuilder, WriterBuilder, constants::NEW_LINE, get_ini_title,
    get_system_title,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, from_str, to_string};
use std::{
    collections::HashMap,
    fs::{self, create_dir_all, read_to_string},
    io::{self},
    path::{Path, PathBuf},
    str::FromStr,
    sync::{Arc, LazyLock, Mutex},
    time::{Duration, Instant},
};
use thiserror::Error;
use tiktoken_rs::o200k_base;
use whatlang::detect;

pub fn to_bcp47(algorithm: Algorithm) -> &'static str {
    match algorithm {
        Algorithm::None => "",

        Algorithm::Arabic => "ar",
        Algorithm::Armenian => "hy",
        Algorithm::Basque => "eu",
        Algorithm::Catalan => "ca",
        Algorithm::Danish => "da",
        Algorithm::Dutch | Algorithm::DutchPorter => "nl",
        Algorithm::English | Algorithm::Lovins | Algorithm::Porter => "en",
        Algorithm::Esperanto => "eo",
        Algorithm::Estonian => "et",
        Algorithm::Finnish => "fi",
        Algorithm::French => "fr",
        Algorithm::German => "de",
        Algorithm::Greek => "el",
        Algorithm::Hindi => "hi",
        Algorithm::Hungarian => "hu",
        Algorithm::Indonesian => "id",
        Algorithm::Irish => "ga",
        Algorithm::Italian => "it",
        Algorithm::Lithuanian => "lt",
        Algorithm::Nepali => "ne",
        Algorithm::Norwegian => "nb",
        Algorithm::Portuguese => "pt",
        Algorithm::Romanian => "ro",
        Algorithm::Russian => "ru",
        Algorithm::Serbian => "sr",
        Algorithm::Spanish => "es",
        Algorithm::Swedish => "sv",
        Algorithm::Tamil => "ta",
        Algorithm::Turkish => "tr",
        Algorithm::Yiddish => "yi",

        Algorithm::Japanese => "ja",
        Algorithm::Chinese => "zh",
        Algorithm::Korean => "ko",

        Algorithm::Thai => "th",
        Algorithm::Burmese => "my",
        Algorithm::Lao => "lo",
        Algorithm::Khmer => "km",
    }
}

static CHECKED_LANGS: LazyLock<Arc<Mutex<HashMap<&'static str, f64>>>> =
    LazyLock::new(|| Arc::new(Mutex::new(HashMap::new())));

fn get_game_type(
    game_title: &str,
    disable_custom_processing: bool,
) -> GameType {
    if disable_custom_processing {
        GameType::None
    } else {
        let lowercased = game_title.to_lowercase();

        if unsafe { Regex::new(r"\btermina\b").unwrap_unchecked() }
            .is_match(&lowercased)
        {
            GameType::Termina
        } else if unsafe { Regex::new(r"\blisa\b").unwrap_unchecked() }
            .is_match(&lowercased)
        {
            GameType::LisaRPG
        } else {
            GameType::None
        }
    }
}

#[derive(Clone, Copy)]
pub(crate) struct MatchModeInfo {
    pub(crate) mode: MatchMode,
    pub(crate) case_sensitive: bool,
    pub(crate) permissive: bool,
}

#[derive(Debug, Error)]
pub(crate) enum Error {
    #[error("{0}: IO error occurred: {1}")]
    Io(PathBuf, io::Error),
    #[error(transparent)]
    Rvpacker(#[from] rvpacker_txt_rs_lib::Error),
    #[error(transparent)]
    Extract(#[from] ExtractError),
    #[error(transparent)]
    Translators(#[from] translators::Error),
    #[error(transparent)]
    LLMConnectorError(#[from] LlmConnectorError),
    #[error(transparent)]
    Yandex(#[from] yandex_translate_v2::Error),
    #[error("Yandex folder ID is not specified. Input it in settings.")]
    YandexFolderNotSpecified,
    #[error(transparent)]
    JSON(#[from] serde_json::Error),
    #[error(transparent)]
    DeepL(#[from] deepl::Error),
    #[error(transparent)]
    DeepLLangConvert(#[from] deepl::LangConvertError),
    #[error(transparent)]
    LanguageTokenizer(#[from] language_tokenizer::Error),
    #[cfg(feature = "languagetool")]
    #[error(transparent)]
    LanguageTool(#[from] languagetool_rust::error::Error),
    #[error(transparent)]
    AssetDecrypt(#[from] rpgm_asset_decrypter_lib::Error),
    #[error("{0}")]
    GoogleNew(String),
    #[error(transparent)]
    Reqwest(#[from] reqwest::Error),
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TranslationEndpoint {
    Google,
    Yandex,
    DeepL,

    Aliyun,
    Anthropic,
    DeepSeek,
    Gemini,
    Koboldcpp,
    Longcat,
    Moonshot,
    Mistral,
    Ollama,
    OpenAI,
    OpenAICompatible,
    Volcengine,
    Xiaomi,
    Xinference,
    Zhipu,
    Lingva,
    GoogleNew,
}

impl Default for TranslationEndpoint {
    fn default() -> Self {
        TranslationEndpoint::Google
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GlossaryEntry<'a> {
    term: &'a str,
    translation: &'a str,
    note: &'a str,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct Request<'a> {
    source_language: &'a str,
    translation_language: &'a str,
    project_context: &'a str,
    local_context: &'a str,
    glossary: &'a [GlossaryEntry<'a>],
    files: &'a HashMap<&'a str, Vec<String>>,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct SingleRequest<'a> {
    source_language: &'a str,
    translation_language: &'a str,
    project_context: &'a str,
    local_context: &'a str,
    glossary: &'a [GlossaryEntry<'a>],
    text: &'a str,
}

pub(crate) fn write(
    source_path: &Path,
    translation_path: &Path,
    output_path: &Path,
    engine_type: EngineType,
    duplicate_mode: DuplicateMode,
    game_title: &str,
    flags: BaseFlags,
    skip_files: FileFlags,
) -> Result<f32, Error> {
    let start_time = Instant::now();
    let game_type = get_game_type(
        game_title,
        flags.contains(BaseFlags::DisableCustomProcessing),
    );

    // Some projects legitimately do not have every translation file
    // (for example `armors.txt` when source data is effectively null).
    // Skip missing translation files automatically instead of failing Write.
    let mut effective_skip_files = skip_files;
    let mut auto_skipped = Vec::<&'static str>::new();
    let mut auto_skip = |flag: FileFlags, filename: &'static str| {
        if !translation_path.join(filename).exists() {
            effective_skip_files |= flag;
            auto_skipped.push(filename);
        }
    };

    auto_skip(FileFlags::Map, "maps.txt");
    auto_skip(FileFlags::Actors, "actors.txt");
    auto_skip(FileFlags::Armors, "armors.txt");
    auto_skip(FileFlags::Classes, "classes.txt");
    auto_skip(FileFlags::CommonEvents, "commonevents.txt");
    auto_skip(FileFlags::Enemies, "enemies.txt");
    auto_skip(FileFlags::Items, "items.txt");
    auto_skip(FileFlags::Skills, "skills.txt");
    auto_skip(FileFlags::States, "states.txt");
    auto_skip(FileFlags::Troops, "troops.txt");
    auto_skip(FileFlags::Weapons, "weapons.txt");
    auto_skip(FileFlags::System, "system.txt");

    // Engine-dependent naming for scripts/plugins.
    if !translation_path.join("scripts.txt").exists()
        && !translation_path.join("plugins.txt").exists()
    {
        effective_skip_files |= FileFlags::Scripts;
        auto_skipped.push("scripts/plugins.txt");
    }

    if !auto_skipped.is_empty() {
        info!(
            "Write: auto-skipping missing translation file(s): {}",
            auto_skipped.join(", ")
        );
    }

    let mut writer = WriterBuilder::new()
        .with_files(FileFlags::all() & !effective_skip_files)
        .with_flags(flags)
        .game_type(game_type)
        .duplicate_mode(duplicate_mode)
        .build();

    writer.write(source_path, translation_path, output_path, engine_type)?;

    Ok(start_time.elapsed().as_secs_f32())
}

pub(crate) fn read(
    project_path: &Path,
    source_path: &Path,
    translation_path: &Path,
    read_mode: ReadMode,
    engine_type: EngineType,
    duplicate_mode: DuplicateMode,
    skip_files: FileFlags,
    flags: BaseFlags,
    map_events: bool,
    hashes: Vec<u128>,
) -> Result<Vec<u128>, Error> {
    let game_title: String = if engine_type.is_new() {
        let system_file_path = source_path.join("System.json");
        let system_file_content = read_to_string(&system_file_path)
            .map_err(|err| Error::Io(system_file_path, err))?;
        get_system_title(&system_file_content)?
    } else {
        let ini_file_path = Path::new(project_path).join("Game.ini");
        let ini_file_content = fs::read(&ini_file_path)
            .map_err(|err| Error::Io(ini_file_path, err))?;
        let title = get_ini_title(&ini_file_content)?;
        String::from_utf8_lossy(&title).into_owned()
    };

    let game_type = get_game_type(
        &game_title,
        flags.contains(BaseFlags::DisableCustomProcessing),
    );

    let mut reader = ReaderBuilder::new()
        .with_files(FileFlags::all().difference(skip_files))
        .with_flags(flags)
        .game_type(game_type)
        .read_mode(read_mode)
        .duplicate_mode(duplicate_mode)
        .map_events(map_events)
        .hashes(hashes)
        .build();

    reader.read(source_path, translation_path, engine_type)?;

    Ok(reader.hashes())
}

pub(crate) fn purge(
    source_path: &Path,
    translation_path: &Path,
    engine_type: EngineType,
    duplicate_mode: DuplicateMode,
    game_title: &str,
    flags: BaseFlags,
    skip_files: FileFlags,
) -> Result<(), Error> {
    let game_type = get_game_type(
        game_title,
        flags.contains(BaseFlags::DisableCustomProcessing),
    );

    PurgerBuilder::new()
        .with_files(FileFlags::all() & !skip_files)
        .with_flags(flags)
        .game_type(game_type)
        .duplicate_mode(duplicate_mode)
        .build()
        .purge(source_path, translation_path, engine_type)?;

    Ok(())
}

pub(crate) async fn get_models(
    endpoint: TranslationEndpoint,
    api_key: &str,
    base_url: &str,
) -> Result<Vec<String>, Error> {
    Ok(match endpoint {
        TranslationEndpoint::Google
        | TranslationEndpoint::Yandex
        | TranslationEndpoint::DeepL
        | TranslationEndpoint::Lingva
        | TranslationEndpoint::GoogleNew => unreachable!(),
        TranslationEndpoint::OpenAI
        | TranslationEndpoint::Longcat
        | TranslationEndpoint::Moonshot
        | TranslationEndpoint::DeepSeek
        | TranslationEndpoint::Koboldcpp
        | TranslationEndpoint::OpenAICompatible
        | TranslationEndpoint::Xiaomi
        | TranslationEndpoint::Mistral => {
            LlmClient::openai_compatible(
                api_key,
                base_url,
                match endpoint {
                    TranslationEndpoint::OpenAI => "openai",
                    TranslationEndpoint::Longcat => "longcat",
                    TranslationEndpoint::DeepSeek => "deepseek",
                    TranslationEndpoint::Moonshot => "moonshot",
                    TranslationEndpoint::Mistral => "mistral",
                    TranslationEndpoint::Koboldcpp => "koboldcpp",
                    TranslationEndpoint::OpenAICompatible => "",
                    TranslationEndpoint::Xiaomi => "xiaomi",
                    _ => unreachable!(),
                },
            )?
            .models()
            .await?
        }
        TranslationEndpoint::Anthropic => {
            LlmClient::anthropic(api_key, base_url)?.models().await?
        }
        TranslationEndpoint::Gemini => {
            LlmClient::google(api_key, base_url)?.models().await?
        }
        TranslationEndpoint::Ollama => {
            LlmClient::ollama(base_url)?.models().await?
        }
        TranslationEndpoint::Aliyun => {
            LlmClient::aliyun(api_key, base_url)?.models().await?
        }
        TranslationEndpoint::Volcengine => {
            LlmClient::volcengine(api_key, base_url)?.models().await?
        }
        TranslationEndpoint::Xinference => {
            LlmClient::xinference(base_url)?.models().await?
        }
        TranslationEndpoint::Zhipu => {
            LlmClient::zhipu(api_key, base_url)?.models().await?
        }
    })
}

fn parse_google_new_json_translation(json: &Value) -> String {
    if let Some(text) = json.as_str() {
        return text.to_string();
    }

    let Some(top) = json.as_array() else {
        return String::new();
    };

    let Some(first) = top.first() else {
        return String::new();
    };

    if let Some(text) = first.as_str() {
        return text.to_string();
    }

    let Some(first_arr) = first.as_array() else {
        return String::new();
    };

    if let Some(text) = first_arr.first().and_then(Value::as_str) {
        return text.to_string();
    }

    first_arr
        .first()
        .and_then(Value::as_array)
        .and_then(|nested| nested.first())
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn parse_google_mobile_translation(body: &str) -> Option<String> {
    static RESULT_REGEX: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(
            r#"(?s)<div[^>]*class=['"]result-container['"][^>]*>(?P<text>.*?)</div>"#,
        )
        .expect("Google mobile result regex must be valid")
    });

    let captures = RESULT_REGEX.captures(body)?;
    let html = captures.name("text")?.as_str();
    let text = html
        .replace("&amp;", "&")
        .replace("&#39;", "'")
        .replace("&quot;", "\"")
        .replace("&lt;", "<")
        .replace("&gt;", ">");
    Some(text)
}

const GOOGLE_NEW_DIRECT_MAX_CHARS: usize = 5_000;
const GOOGLE_NEW_CHUNK_MAX_CHARS: usize = 1_500;
const GOOGLE_NEW_MAX_CHUNKS: usize = 128;

fn is_google_mobile_endpoint(base_url: &str) -> bool {
    let Some(url) = reqwest::Url::parse(base_url).ok() else {
        return false;
    };

    let is_translate_google = url
        .host_str()
        .map(|host| host.eq_ignore_ascii_case("translate.google.com"))
        .unwrap_or(false);
    let normalized_path = url.path().trim_end_matches('/');

    is_translate_google && normalized_path.eq_ignore_ascii_case("/m")
}

fn split_text_for_google_new(
    text: &str,
    max_chars: usize,
    max_chunks: usize,
) -> Option<Vec<String>> {
    if text.is_empty() {
        return Some(vec![String::new()]);
    }

    let mut chunks = Vec::new();
    let mut current = String::new();
    let mut current_chars = 0usize;

    let push_piece = |piece: &str, chunks: &mut Vec<String>| -> bool {
        let mut piece_buf = String::new();
        let mut piece_chars = 0usize;

        for ch in piece.chars() {
            piece_buf.push(ch);
            piece_chars += 1;

            if piece_chars >= max_chars {
                chunks.push(std::mem::take(&mut piece_buf));
                piece_chars = 0;

                if chunks.len() > max_chunks {
                    return false;
                }
            }
        }

        if !piece_buf.is_empty() {
            chunks.push(piece_buf);
        }

        chunks.len() <= max_chunks
    };

    for segment in text.split_inclusive('\n') {
        let segment_chars = segment.chars().count();

        if segment_chars > max_chars {
            if !current.is_empty() {
                chunks.push(std::mem::take(&mut current));
                current_chars = 0;

                if chunks.len() > max_chunks {
                    return None;
                }
            }

            if !push_piece(segment, &mut chunks) {
                return None;
            }

            continue;
        }

        if current_chars + segment_chars > max_chars {
            chunks.push(std::mem::take(&mut current));
            current_chars = 0;

            if chunks.len() > max_chunks {
                return None;
            }
        }

        current.push_str(segment);
        current_chars += segment_chars;
    }

    if !current.is_empty() {
        chunks.push(current);
    }

    (chunks.len() <= max_chunks).then_some(chunks)
}

fn build_google_new_client() -> Result<reqwest::Client, Error> {
    Ok(reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(40))
        .pool_max_idle_per_host(4)
        .build()?)
}

async fn request_google_new_once(
    client: &reqwest::Client,
    base_url: &str,
    source_language: &str,
    translation_language: &str,
    text: &str,
    use_post: bool,
    is_mobile_endpoint: bool,
) -> Result<String, Error> {
    let source_language = if source_language.is_empty() {
        "auto"
    } else {
        source_language
    };

    let request = if use_post {
        if is_mobile_endpoint {
            client.post(base_url).form(&[
                ("sl", source_language),
                ("tl", translation_language),
                ("q", text),
            ])
        } else {
            client.post(base_url).form(&[
                ("client", "dict-chrome-ex"),
                ("sl", source_language),
                ("tl", translation_language),
                ("dt", "t"),
                ("q", text),
            ])
        }
    } else if is_mobile_endpoint {
        client.get(base_url).query(&[
            ("sl", source_language),
            ("tl", translation_language),
            ("q", text),
        ])
    } else {
        client.get(base_url).query(&[
            ("client", "dict-chrome-ex"),
            ("sl", source_language),
            ("tl", translation_language),
            ("dt", "t"),
            ("q", text),
        ])
    };

    let body = request
        .header(
            "User-Agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        )
        .header(
            "Accept",
            if is_mobile_endpoint {
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
            } else {
                "application/json,text/plain,*/*"
            },
        )
        .header("Referer", "https://translate.google.com/")
        .send()
        .await?;

    let status = body.status();
    let text_body = body.text().await?;

    if !status.is_success() {
        return Err(Error::GoogleNew(format!(
            "Google NEW request failed with HTTP status {}.",
            status.as_u16()
        )));
    }

    if let Ok(json) = serde_json::from_str::<Value>(&text_body) {
        return Ok(parse_google_new_json_translation(&json));
    }

    if let Some(parsed) = parse_google_mobile_translation(&text_body) {
        return Ok(parsed);
    }

    Err(Error::GoogleNew(
        "Google NEW returned an unsupported response format.".to_string(),
    ))
}

async fn translate_google_new_chunked(
    client: &reqwest::Client,
    base_url: &str,
    source_language: &str,
    translation_language: &str,
    text: &str,
    is_mobile_endpoint: bool,
) -> Result<String, Error> {
    let Some(chunks) = split_text_for_google_new(
        text,
        GOOGLE_NEW_CHUNK_MAX_CHARS,
        GOOGLE_NEW_MAX_CHUNKS,
    ) else {
        return Err(Error::GoogleNew(format!(
            "Google NEW payload is too large ({} chars). Reduce batch size or use another provider for this file.",
            text.chars().count()
        )));
    };

    debug!(
        "Google NEW chunking enabled: {} chunks for {} chars",
        chunks.len(),
        text.chars().count()
    );

    let mut translated = String::new();
    let total_chunks = chunks.len();

    for (chunk_index, chunk) in chunks.into_iter().enumerate() {
        if total_chunks > 1 {
            info!(
                "Google NEW chunk {}/{} ({} chars)",
                chunk_index + 1,
                total_chunks,
                chunk.chars().count()
            );
        }

        let translated_chunk = if is_mobile_endpoint {
            request_google_new_once(
                client,
                base_url,
                source_language,
                translation_language,
                &chunk,
                false,
                true,
            )
            .await?
        } else {
            match request_google_new_once(
                client,
                base_url,
                source_language,
                translation_language,
                &chunk,
                false,
                false,
            )
            .await
            {
                Ok(value) => value,
                Err(_) => {
                    request_google_new_once(
                        client,
                        base_url,
                        source_language,
                        translation_language,
                        &chunk,
                        true,
                        false,
                    )
                    .await?
                }
            }
        };

        translated.push_str(&translated_chunk);
    }

    Ok(translated)
}

async fn translate_google_new(
    client: &reqwest::Client,
    base_url: &str,
    source_language: &str,
    translation_language: &str,
    text: &str,
) -> Result<String, Error> {
    let is_mobile_endpoint = is_google_mobile_endpoint(base_url);
    let input_chars = text.chars().count();

    if !is_mobile_endpoint && input_chars > GOOGLE_NEW_DIRECT_MAX_CHARS {
        return translate_google_new_chunked(
            client,
            base_url,
            source_language,
            translation_language,
            text,
            is_mobile_endpoint,
        )
        .await;
    }

    let direct_result = if is_mobile_endpoint {
        request_google_new_once(
            client,
            base_url,
            source_language,
            translation_language,
            text,
            false,
            true,
        )
        .await
    } else {
        match request_google_new_once(
            client,
            base_url,
            source_language,
            translation_language,
            text,
            false,
            false,
        )
        .await
        {
            Ok(result) => Ok(result),
            Err(_) => {
                request_google_new_once(
                    client,
                    base_url,
                    source_language,
                    translation_language,
                    text,
                    true,
                    false,
                )
                .await
            }
        }
    };

    match direct_result {
        Ok(translated) => Ok(translated),
        Err(error) => {
            if !is_mobile_endpoint && input_chars > GOOGLE_NEW_CHUNK_MAX_CHARS {
                translate_google_new_chunked(
                    client,
                    base_url,
                    source_language,
                    translation_language,
                    text,
                    is_mobile_endpoint,
                )
                .await
            } else {
                Err(error)
            }
        }
    }
}

pub(crate) async fn translate_single<'a>(
    endpoint_settings: &str,
    source_language: Algorithm,
    translation_language: Algorithm,
    project_context: &str,
    local_context: &str,
    text: &str,
    glossary: Vec<GlossaryEntry<'a>>,
) -> Result<String, Error> {
    let source_language = to_bcp47(source_language);
    let translation_language = to_bcp47(translation_language);

    let endpoint_settings: Value =
        unsafe { serde_json::from_str(endpoint_settings).unwrap_unchecked() };
    let endpoint = unsafe {
        std::mem::transmute(
            endpoint_settings["type"].as_u64().unwrap_unchecked() as u8,
        )
    };

    let translated = match endpoint {
        TranslationEndpoint::Google => {
            use translators::{GoogleTranslator, Translator};

            GoogleTranslator::default()
                .translate_async(text, source_language, translation_language)
                .await?
        }

        TranslationEndpoint::Lingva => {
            let base_url = unsafe {
                endpoint_settings["baseUrl"].as_str().unwrap_unchecked()
            };
            let encoded = urlencoding::encode(text);
            let url = format!(
                "{}/api/v1/{}/{}/{}",
                base_url, source_language, translation_language, encoded
            );
            let json: serde_json::Value =
                reqwest::get(&url).await?.json().await?;
            json["translation"].as_str().unwrap_or("").to_string()
        }

        TranslationEndpoint::GoogleNew => {
            let base_url = unsafe {
                endpoint_settings["baseUrl"].as_str().unwrap_unchecked()
            };
            let client = build_google_new_client()?;
            translate_google_new(
                &client,
                base_url,
                source_language,
                translation_language,
                text,
            )
            .await?
        }

        _ => {
            let api_key = unsafe {
                endpoint_settings["apiKey"].as_str().unwrap_unchecked()
            };

            match endpoint {
                TranslationEndpoint::Yandex => {
                    use yandex_translate_v2::{
                        TranslateRequest, YandexTranslateClient,
                    };

                    let yandex_folder_id = unsafe {
                        endpoint_settings["folderId"]
                            .as_str()
                            .unwrap_unchecked()
                    };

                    let client = YandexTranslateClient::with_api_key(api_key)?;
                    let response = client
                        .translate(&TranslateRequest {
                            folder_id: yandex_folder_id,
                            texts: &[text],
                            target_language_code: translation_language,
                            source_language_code: Some(source_language),
                        })
                        .await?;

                    response
                        .translations
                        .into_iter()
                        .next()
                        .map(|x| x.text)
                        .unwrap_or_default()
                }

                TranslationEndpoint::DeepL => {
                    use deepl::*;

                    let client = DeepLApi::with(api_key).new();
                    client
                        .translate_text(
                            text,
                            Lang::from_str(translation_language)?,
                        )
                        .await?
                        .to_string()
                }

                _ => {
                    let base_url = unsafe {
                        endpoint_settings["baseUrl"].as_str().unwrap_unchecked()
                    };

                    let client = match endpoint {
                        TranslationEndpoint::Google
                        | TranslationEndpoint::Yandex
                        | TranslationEndpoint::DeepL
                        | TranslationEndpoint::Lingva
                        | TranslationEndpoint::GoogleNew => unreachable!(),
                        TranslationEndpoint::OpenAI
                        | TranslationEndpoint::Longcat
                        | TranslationEndpoint::Moonshot
                        | TranslationEndpoint::Mistral
                        | TranslationEndpoint::DeepSeek
                        | TranslationEndpoint::Koboldcpp
                        | TranslationEndpoint::OpenAICompatible
                        | TranslationEndpoint::Xiaomi => {
                            LlmClient::openai_compatible(
                                api_key,
                                base_url,
                                match endpoint {
                                    TranslationEndpoint::OpenAI => "openai",
                                    TranslationEndpoint::Longcat => "longcat",
                                    TranslationEndpoint::DeepSeek => "deepseek",
                                    TranslationEndpoint::Moonshot => "moonshot",
                                    TranslationEndpoint::Mistral => "moonshot",
                                    TranslationEndpoint::Koboldcpp => {
                                        "koboldcpp"
                                    }
                                    TranslationEndpoint::OpenAICompatible => "",
                                    _ => unreachable!(),
                                },
                            )?
                        }
                        TranslationEndpoint::Anthropic => {
                            LlmClient::anthropic(api_key, base_url)?
                        }
                        TranslationEndpoint::Gemini => {
                            LlmClient::google(api_key, base_url)?
                        }
                        TranslationEndpoint::Ollama => {
                            LlmClient::ollama(base_url)?
                        }
                        TranslationEndpoint::Aliyun => {
                            LlmClient::aliyun(api_key, base_url)?
                        }
                        TranslationEndpoint::Volcengine => {
                            LlmClient::volcengine(api_key, base_url)?
                        }
                        TranslationEndpoint::Xinference => {
                            LlmClient::xinference(base_url)?
                        }
                        TranslationEndpoint::Zhipu => {
                            LlmClient::zhipu(api_key, base_url)?
                        }
                    };

                    let prompt = SingleRequest {
                        source_language,
                        translation_language,
                        project_context,
                        local_context,
                        glossary: &glossary,
                        text,
                    };

                    let model = unsafe {
                        endpoint_settings["model"].as_str().unwrap_unchecked()
                    };
                    let thinking = unsafe {
                        endpoint_settings["thinking"]
                            .as_bool()
                            .unwrap_unchecked()
                    };
                    let temperature = unsafe {
                        endpoint_settings["temperature"]
                            .as_f64()
                            .unwrap_unchecked()
                    };

                    let request = ChatRequest {
                        model: model.to_string(),
                        messages: vec![
                            Message::text(Role::System, unsafe {
                                endpoint_settings["singleTranslationSystemPrompt"].as_str().unwrap_unchecked()
                            }),
                            Message::text(Role::User, to_string(&prompt)?),
                        ],
                        enable_thinking: Some(thinking),
                        temperature: Some(temperature as f32),
                        ..Default::default()
                    };

                    let response = client.chat(&request).await?;
                    response.content
                }
            }
        }
    };

    Ok(translated)
}

pub(crate) async fn translate<'a>(
    endpoint_settings: &str,
    source_language: Algorithm,
    translation_language: Algorithm,
    project_context: &str,
    local_context: &str,
    files: HashMap<&str, Vec<String>>,
    glossary: Vec<GlossaryEntry<'a>>,
) -> Result<HashMap<String, Vec<String>>, Error> {
    let source_language = to_bcp47(source_language);
    let translation_language = to_bcp47(translation_language);

    let mut response: HashMap<String, Vec<String>> =
        HashMap::with_capacity(files.len());

    let endpoint_settings: Value =
        unsafe { serde_json::from_str(endpoint_settings).unwrap_unchecked() };
    let endpoint = unsafe {
        std::mem::transmute(
            endpoint_settings["type"].as_u64().unwrap_unchecked() as u8,
        )
    };

    let result: HashMap<String, Vec<String>> = match endpoint {
        TranslationEndpoint::Google => {
            use translators::{GoogleTranslator, Translator};
            let translator = GoogleTranslator::default();

            for (&file, strings) in &files {
                response.insert(
                    file.to_string(),
                    Vec::with_capacity(strings.len()),
                );
                let response_file = response.get_mut(file).unwrap();

                for string in strings {
                    let translated = translator
                        .translate_async(
                            string,
                            source_language,
                            translation_language,
                        )
                        .await?;
                    response_file.push(translated.replace('\n', NEW_LINE));
                }
            }

            response
        }

        TranslationEndpoint::Lingva => {
            let base_url = unsafe {
                endpoint_settings["baseUrl"].as_str().unwrap_unchecked()
            };
            let client = reqwest::Client::new();

            for (&file, strings) in &files {
                response.insert(
                    file.to_string(),
                    Vec::with_capacity(strings.len()),
                );
                let response_file = response.get_mut(file).unwrap();

                for string in strings {
                    let encoded = urlencoding::encode(string);
                    let url = format!(
                        "{}/api/v1/{}/{}/{}",
                        base_url,
                        source_language,
                        translation_language,
                        encoded
                    );
                    let json: serde_json::Value =
                        client.get(&url).send().await?.json().await?;
                    let translated =
                        json["translation"].as_str().unwrap_or("").to_string();
                    response_file.push(translated.replace('\n', NEW_LINE));
                }
            }

            response
        }

        TranslationEndpoint::GoogleNew => {
            let base_url = unsafe {
                endpoint_settings["baseUrl"].as_str().unwrap_unchecked()
            };
            let client = build_google_new_client()?;

            for (&file, strings) in &files {
                response.insert(
                    file.to_string(),
                    Vec::with_capacity(strings.len()),
                );
                let response_file = response.get_mut(file).unwrap();
                let total = strings.len();
                let report_every = std::cmp::max(1, total / 10);

                info!("Google NEW batch: file '{}' ({} strings)", file, total);

                for (idx, string) in strings.iter().enumerate() {
                    if idx == 0 || (idx + 1) % report_every == 0 || idx + 1 == total {
                        info!(
                            "Google NEW progress '{}' {}/{}",
                            file,
                            idx + 1,
                            total
                        );
                    }

                    let translated = translate_google_new(
                        &client,
                        base_url,
                        source_language,
                        translation_language,
                        string,
                    )
                    .await?;
                    response_file.push(translated.replace('\n', NEW_LINE));
                }
            }

            response
        }

        _ => {
            let api_key = unsafe {
                endpoint_settings["apiKey"].as_str().unwrap_unchecked()
            };

            match endpoint {
                TranslationEndpoint::Yandex => {
                    use yandex_translate_v2::{
                        TranslateRequest, YandexTranslateClient,
                    };

                    let yandex_folder_id = unsafe {
                        endpoint_settings["folderId"]
                            .as_str()
                            .unwrap_unchecked()
                    };

                    if yandex_folder_id.is_empty() {
                        return Err(Error::YandexFolderNotSpecified);
                    }

                    for (&file, strings) in &files {
                        response.insert(
                            file.to_string(),
                            Vec::with_capacity(strings.len()),
                        );
                        let response_file = response.get_mut(file).unwrap();

                        let client =
                            YandexTranslateClient::with_api_key(api_key)?;
                        let response = client
                            .translate(&TranslateRequest {
                                folder_id: yandex_folder_id,
                                texts: &strings
                                    .iter()
                                    .map(|s| s.as_str())
                                    .collect::<Vec<_>>(),
                                target_language_code: translation_language,
                                source_language_code: Some(source_language),
                            })
                            .await?;
                        let strings = response
                            .translations
                            .into_iter()
                            .map(|x| x.text.replace('\n', NEW_LINE))
                            .collect();

                        *response_file = strings;
                    }

                    response
                }

                TranslationEndpoint::DeepL => {
                    use deepl::{glossary::*, *};

                    let client = DeepLApi::with(api_key).new();
                    let _ = client
                        .create_glossary("glossary")
                        .entries(
                            glossary.iter().map(|e| (e.term, e.translation)),
                        )
                        .source_lang(GlossaryLanguage::from_str(
                            source_language,
                        )?)
                        .target_lang(GlossaryLanguage::from_str(
                            translation_language,
                        )?)
                        .send()
                        .await?;

                    for (&file, strings) in &files {
                        response.insert(
                            file.to_string(),
                            Vec::with_capacity(strings.len()),
                        );
                        let response_file = response.get_mut(file).unwrap();

                        let mut new_strings = Vec::with_capacity(files.len());

                        for string in strings {
                            let translated = client
                                .translate_text(
                                    string.as_str(),
                                    Lang::from_str(translation_language)?,
                                )
                                .await?
                                .to_string();

                            new_strings
                                .push(translated.replace('\n', NEW_LINE));
                        }

                        *response_file = new_strings;
                    }

                    response
                }

                _ => {
                    let base_url = unsafe {
                        endpoint_settings["baseUrl"].as_str().unwrap_unchecked()
                    };

                    let client = match endpoint {
                        TranslationEndpoint::Google
                        | TranslationEndpoint::Yandex
                        | TranslationEndpoint::DeepL
                        | TranslationEndpoint::Lingva
                        | TranslationEndpoint::GoogleNew => unreachable!(),
                        TranslationEndpoint::OpenAI
                        | TranslationEndpoint::Longcat
                        | TranslationEndpoint::Moonshot
                        | TranslationEndpoint::Mistral
                        | TranslationEndpoint::DeepSeek
                        | TranslationEndpoint::Koboldcpp
                        | TranslationEndpoint::OpenAICompatible
                        | TranslationEndpoint::Xiaomi => {
                            LlmClient::openai_compatible(
                                api_key,
                                base_url,
                                match endpoint {
                                    TranslationEndpoint::OpenAI => "openai",
                                    TranslationEndpoint::Longcat => "longcat",
                                    TranslationEndpoint::DeepSeek => "deepseek",
                                    TranslationEndpoint::Moonshot => "moonshot",
                                    TranslationEndpoint::Mistral => "mistral",
                                    TranslationEndpoint::Koboldcpp => {
                                        "koboldcpp"
                                    }
                                    TranslationEndpoint::OpenAICompatible => "",
                                    TranslationEndpoint::Xiaomi => "xiaomi",
                                    _ => unreachable!(),
                                },
                            )?
                        }
                        TranslationEndpoint::Anthropic => {
                            LlmClient::anthropic(api_key, base_url)?
                        }
                        TranslationEndpoint::Gemini => {
                            LlmClient::google(api_key, base_url)?
                        }
                        TranslationEndpoint::Ollama => {
                            LlmClient::ollama(base_url)?
                        }
                        TranslationEndpoint::Aliyun => {
                            LlmClient::aliyun(api_key, base_url)?
                        }
                        TranslationEndpoint::Volcengine => {
                            LlmClient::volcengine(api_key, base_url)?
                        }
                        TranslationEndpoint::Xinference => {
                            LlmClient::xinference(base_url)?
                        }
                        TranslationEndpoint::Zhipu => {
                            LlmClient::zhipu(api_key, base_url)?
                        }
                    };

                    let token_limit = unsafe {
                        endpoint_settings["tokenLimit"]
                            .as_u64()
                            .unwrap_unchecked()
                    } as u32;
                    let output_token_limit = unsafe {
                        endpoint_settings["tokenLimit"]
                            .as_u64()
                            .unwrap_unchecked()
                    } as u32;
                    let model = unsafe {
                        endpoint_settings["model"].as_str().unwrap_unchecked()
                    };
                    let system_prompt = unsafe {
                        endpoint_settings["systemPrompt"]
                            .as_str()
                            .unwrap_unchecked()
                    };
                    let thinking = unsafe {
                        endpoint_settings["thinking"]
                            .as_bool()
                            .unwrap_unchecked()
                    };
                    let temperature = unsafe {
                        endpoint_settings["temperature"]
                            .as_f64()
                            .unwrap_unchecked()
                    } as f32;

                    let mut limited_files: Vec<HashMap<&str, Vec<String>>> =
                        vec![HashMap::new()];
                    let mut entry: &mut HashMap<&str, Vec<String>> =
                        limited_files.first_mut().unwrap();
                    let mut limit = 0;

                    let tokenizer = o200k_base().unwrap();

                    for (file, strings) in files {
                        for string in &strings {
                            let tokens =
                                tokenizer.encode_with_special_tokens(string);
                            limit += tokens.len();
                        }

                        if limit < token_limit as usize {
                            entry.insert(file, strings);
                        } else {
                            limit = 0;
                            limited_files.push(HashMap::new());
                            entry = limited_files.last_mut().unwrap();
                        }
                    }

                    let mut result: HashMap<String, Vec<String>> =
                        HashMap::new();

                    let mut request = ChatRequest {
                        model: model.to_string(),
                        messages: vec![
                            Message::text(Role::System, system_prompt),
                            Message::default(),
                        ],
                        enable_thinking: Some(thinking),
                        temperature: Some(temperature),
                        max_tokens: Some(output_token_limit),
                        ..Default::default()
                    };

                    for files in limited_files {
                        let prompt = Request {
                            source_language,
                            translation_language,
                            project_context,
                            local_context,
                            glossary: &glossary,
                            files: &files,
                        };

                        request.messages[1] =
                            Message::text(Role::User, to_string(&prompt)?);

                        let response = client.chat(&request).await?;

                        let response = from_str::<HashMap<String, Vec<String>>>(
                            &response.content,
                        )?;

                        result.extend(response);
                    }

                    for strings in result.values_mut() {
                        for string in strings.iter_mut() {
                            *string = string.replace('\n', NEW_LINE);
                        }
                    }

                    result
                }
            }
        }
    };

    Ok(result)
}

pub(crate) fn extract_archive(
    input_path: &Path,
    output_path: &Path,
) -> Result<(), Error> {
    debug!("Decrypting archive: {}", input_path.display());

    let mut bytes = fs::read(input_path)
        .map_err(|err| Error::Io(input_path.to_path_buf(), err))?;

    let mut decrypter = Decrypter::new();
    let decrypted_entries = decrypter.decrypt(&mut bytes)?;

    for file in decrypted_entries {
        let path = String::from_utf8_lossy(&file.path);
        debug!("Decrypting archive entry: {}", path);

        let output_file_path = output_path.join(path.as_ref());

        if let Some(parent) = output_file_path.parent() {
            create_dir_all(parent)
                .map_err(|err| Error::Io(parent.to_path_buf(), err))?;
        }

        fs::write(&output_file_path, file.data)
            .map_err(|err| Error::Io(output_file_path, err))?;

        info!("Decrypted archive entry: {}", path);
    }

    info!("Decrypted archive: {}", input_path.display());

    Ok(())
}

pub(crate) fn find_all_matches(
    source_haystack: &str,
    source_needle: &str,
    source_mode: MatchModeInfo,
    tr_haystack: &str,
    tr_needle: &str,
    tr_mode: MatchModeInfo,
    source_algorithm: Algorithm,
    tr_algorithm: Algorithm,
) -> Result<
    Option<(Vec<MatchResult>, Vec<MatchResult>)>,
    language_tokenizer::Error,
> {
    let source_haystack = tokenize(
        source_haystack,
        source_algorithm,
        source_mode.case_sensitive,
    )?;
    let source_needle =
        tokenize(source_needle, source_algorithm, source_mode.case_sensitive)?;
    let tr_haystack =
        tokenize(tr_haystack, tr_algorithm, tr_mode.case_sensitive)?;
    let tr_needle = tokenize(tr_needle, tr_algorithm, tr_mode.case_sensitive)?;

    let source_matches = find_all_matches_(
        &source_haystack,
        &source_needle,
        source_mode.mode,
        source_mode.permissive,
    );

    let source_has_needle = !source_matches.is_empty();

    Ok(if source_has_needle {
        let translation_matches = find_all_matches_(
            &tr_haystack,
            &tr_needle,
            tr_mode.mode,
            tr_mode.permissive,
        );

        Some((source_matches, translation_matches))
    } else {
        None
    })
}

pub(crate) fn detect_lang(str: &str) {
    let lang = detect(str);

    if let Some(lang) = lang {
        let mut lock = CHECKED_LANGS.lock().unwrap();
        let entry = lock.entry(lang.lang().eng_name()).or_default();
        *entry += lang.confidence();
    }
}

pub(crate) fn get_lang() -> Option<&'static str> {
    CHECKED_LANGS
        .lock()
        .unwrap()
        .drain()
        .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
        .and_then(|x| Some(x.0))
}

pub(crate) fn count_words(
    text: &str,
    algorithm: Algorithm,
) -> Result<u32, Error> {
    let tokens = tokenize(text, algorithm, false)?;
    Ok(tokens.len() as u32)
}

// TODO
#[cfg(feature = "languagetool")]
pub(crate) async fn language_tool_lint(
    text: &str,
    base_url: &str,
    api_key: &str,
    algorithm: Algorithm,
) -> Result<(), Error> {
    let client = ServerClient::new(base_url, "");
    let mut request = LTRequest::default()
        .with_language(to_bcp47(algorithm).to_string())
        .with_text(text);

    if !api_key.is_empty() {
        request.api_key = Some(api_key.to_string());
    }

    let response = client.check(&request).await?;

    Ok(())
}

pub(crate) fn decrypt_asset(path: &Path) -> Result<Vec<u8>, Error> {
    use rpgm_asset_decrypter_lib::{
        FileType, MV_M4A_EXT, MV_OGG_EXT, MZ_M4A_EXT, MZ_OGG_EXT,
        decrypt_in_place,
    };

    let mut file_content =
        fs::read(path).map_err(|err| Error::Io(path.to_path_buf(), err))?;
    let extension = unsafe { path.extension().unwrap_unchecked() };

    let file_type = if extension == MV_M4A_EXT || extension == MZ_M4A_EXT {
        FileType::M4A
    } else if extension == MV_OGG_EXT || extension == MZ_OGG_EXT {
        FileType::OGG
    } else {
        FileType::PNG
    };

    decrypt_in_place(&mut file_content, file_type)?;

    return Ok(file_content);
}
