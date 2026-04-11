#![allow(unsafe_op_in_unsafe_fn)]
use crate::api::*;
use language_tokenizer::{Algorithm, MatchResult};
use log::{Log, Metadata, Record};
use rvpacker_txt_rs_lib::{
    BaseFlags, DuplicateMode, EngineType, FileFlags, ReadMode,
};
use std::{
    collections::HashMap,
    ffi::c_char,
    fs::{self, read_to_string},
    mem::{self},
    path::Path,
    ptr::{self},
    sync::{LazyLock, OnceLock},
};
use tokio::runtime::{Builder, Runtime};

// TODO: Docs for all this

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Bitset2048 {
    data: [u8; 256],
}

impl Bitset2048 {
    #[inline]
    pub fn is_set(&self, bit: usize) -> bool {
        let byte = unsafe { *self.data.get_unchecked(bit >> 3) };
        (byte >> (bit & 7)) & 1 == 1
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Selected {
    map_indices: Bitset2048,
    valid_indices: Bitset2048,
    map_count: u16,
    file_flags: FileFlags,
    padding: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
/// Byte buffer with FFI-compatible layout.
///
/// This struct shouldn't be used for UTF-8 string. Instead, [`FFIString`] should be used.
///
/// If `cap == 0`, then this is just a view.
pub struct ByteBuffer {
    pub ptr: *const u8,
    pub len: u32,
    pub cap: u32,
}

impl ByteBuffer {
    pub const fn null() -> Self {
        Self {
            ptr: ptr::null(),
            len: 0,
            cap: 0,
        }
    }
}

static TOKIO_RT: LazyLock<Runtime> =
    LazyLock::new(|| Builder::new_multi_thread().enable_all().build().unwrap());

#[repr(C)]
#[derive(Clone, Copy)]
/// UTF-8 string with FFI-compatible layout.
///
/// Use [`str_to_ffi`] and [`ffi_to_str`] for conversions.
///
/// Use [`FFIString::null`] to default-initialize to null.
///
/// If `cap == 0`, then this is just a view.
pub struct FFIString {
    pub ptr: *const c_char,
    pub len: u32,
    pub cap: u32,
}

impl FFIString {
    pub const fn null() -> Self {
        Self {
            ptr: ptr::null(),
            len: 0,
            cap: 0,
        }
    }
}

#[inline]
unsafe fn ffi_to_str<'a>(string: FFIString) -> &'a str {
    let slice = std::slice::from_raw_parts(
        string.ptr.cast::<u8>(),
        string.len as usize,
    );
    str::from_utf8_unchecked(slice)
}

#[inline]
fn str_to_ffi(str: &String) -> FFIString {
    let len = str.len();
    let ptr = str.as_ptr().cast::<c_char>();
    FFIString {
        ptr,
        len: len as u32,
        cap: str.capacity() as u32,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rpgm_string_free(ffi_string: FFIString) {
    if ffi_string.cap == 0 {
        return;
    }

    let _ = Vec::from_raw_parts(
        ffi_string.ptr.cast_mut(),
        ffi_string.len as usize,
        ffi_string.cap as usize,
    );
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rpgm_buffer_free(buffer: ByteBuffer) {
    if buffer.cap == 0 {
        return;
    }

    let _ = Vec::from_raw_parts(
        buffer.ptr.cast_mut(),
        buffer.len as usize,
        buffer.cap as usize,
    );
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rpgm_free_translated_files(
    translated_files: ByteBuffer,
    translated_files_ffi: ByteBuffer,
) {
    let rebuilt_files_ffi: Vec<ByteBuffer> = Vec::from_raw_parts(
        translated_files_ffi.ptr.cast_mut().cast::<ByteBuffer>(),
        translated_files_ffi.len as usize,
        translated_files_ffi.cap as usize,
    );

    for buffer in &rebuilt_files_ffi {
        if buffer.ptr.is_null() || buffer.len == 0 {
            continue;
        }

        let _: Vec<FFIString> = Vec::from_raw_parts(
            buffer.ptr.cast_mut().cast::<FFIString>(),
            buffer.len as usize,
            buffer.cap as usize,
        );
    }

    let _: Vec<Vec<String>> = Vec::from_raw_parts(
        translated_files.ptr.cast_mut().cast::<Vec<String>>(),
        translated_files.len as usize,
        translated_files.cap as usize,
    );
}

#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_read(
    source_path: FFIString,
    translation_path: FFIString,
    read_mode: ReadMode,
    engine_type: EngineType,
    duplicate_mode: DuplicateMode,
    selected: Selected,
    flags: BaseFlags,
    map_events: bool,
    hashes: ByteBuffer,
    ini_title: FFIString,
    out_hashes: *mut ByteBuffer,
) -> FFIString {
    let result = (|| -> Result<_, Error> {
        let source_path = ffi_to_str(source_path);
        let translation_path = ffi_to_str(translation_path);
        let ini_title = ffi_to_str(ini_title);

        let hashes = if hashes.ptr.is_null() {
            &[]
        } else {
            std::slice::from_raw_parts(
                hashes.ptr.cast::<u128>(),
                hashes.len as usize,
            )
        };

        let out = read(
            Path::new(&source_path),
            Path::new(&translation_path),
            read_mode,
            engine_type,
            duplicate_mode,
            selected.file_flags,
            flags,
            map_events,
            hashes.to_vec(),
            ini_title,
        )?;

        Ok(out)
    })();

    match result {
        Ok(mut serialized) => {
            *out_hashes = ByteBuffer {
                ptr: serialized.as_mut_ptr().cast::<u8>(),
                len: serialized.len() as u32,
                cap: serialized.capacity() as u32,
            };

            mem::forget(serialized);

            FFIString::null()
        }
        Err(err) => {
            let msg = err.to_string();
            let ffi = str_to_ffi(&msg);
            mem::forget(msg);
            ffi
        }
    }
}

#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_write(
    source_path: FFIString,
    translation_path: FFIString,
    output_path: FFIString,
    engine_type: EngineType,
    duplicate_mode: DuplicateMode,
    game_title: FFIString,
    flags: BaseFlags,
    selected: Selected,
    elapsed_out: *mut f32,
) -> FFIString {
    let result = (|| -> Result<f32, Error> {
        let source_path = ffi_to_str(source_path);
        let translation_path = ffi_to_str(translation_path);
        let output_path = ffi_to_str(output_path);
        let game_title = ffi_to_str(game_title);

        let elapsed = write(
            Path::new(&source_path),
            Path::new(&translation_path),
            Path::new(&output_path),
            engine_type,
            duplicate_mode,
            &game_title,
            flags,
            selected.file_flags,
        )?;

        Ok(elapsed)
    })();

    match result {
        Ok(elapsed) => {
            *elapsed_out = elapsed;
            FFIString::null()
        }
        Err(error) => {
            let err = error.to_string();
            let ffi = str_to_ffi(&err);
            mem::forget(err);
            ffi
        }
    }
}

#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_purge(
    source_path: FFIString,
    translation_path: FFIString,
    engine_type: EngineType,
    duplicate_mode: DuplicateMode,
    game_title: FFIString,
    flags: BaseFlags,
    selected: Selected,
) -> FFIString {
    let result = (|| -> Result<(), Error> {
        let source_path = ffi_to_str(source_path);
        let translation_path = ffi_to_str(translation_path);
        let game_title = ffi_to_str(game_title);

        purge(
            Path::new(&source_path),
            Path::new(&translation_path),
            engine_type,
            duplicate_mode,
            &game_title,
            flags,
            selected.file_flags,
        )?;

        Ok(())
    })();

    match result {
        Ok(_) => FFIString::null(),
        Err(error) => {
            let err = error.to_string();
            let ffi = str_to_ffi(&err);
            mem::forget(err);
            ffi
        }
    }
}

#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_extract_archive(
    input_path: FFIString,
    output_path: FFIString,
) -> FFIString {
    let result = (|| -> Result<(), Error> {
        let input_path = ffi_to_str(input_path);
        let output_path = ffi_to_str(output_path);
        extract_archive(Path::new(&input_path), Path::new(&output_path))?;
        Ok(())
    })();

    match result {
        Ok(()) => FFIString::null(),
        Err(error) => {
            let err = error.to_string();
            let ffi = str_to_ffi(&err);
            mem::forget(err);
            ffi
        }
    }
}

#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_get_models(
    endpoint: TranslationEndpoint,
    api_key: FFIString,
    base_url: FFIString,
    out: *mut ByteBuffer,
) -> FFIString {
    let result = (|| -> Result<_, Error> {
        let api_key = ffi_to_str(api_key);
        let base_url = ffi_to_str(base_url);
        let models = TOKIO_RT.block_on(async move {
            get_models(endpoint, &api_key, &base_url).await
        })?;
        Ok(models)
    })();

    match result {
        Ok(models) => {
            let mut buffer: Vec<u8> = Vec::new();
            buffer.extend_from_slice(&(models.len() as u32).to_le_bytes());

            for string in models {
                buffer.extend_from_slice(&(string.len() as u32).to_le_bytes());
                buffer.extend_from_slice(string.as_bytes());
            }

            *out = ByteBuffer {
                ptr: buffer.as_mut_ptr(),
                len: buffer.len() as u32,
                cap: buffer.capacity() as u32,
            };

            mem::forget(buffer);
            FFIString::null()
        }
        Err(error) => {
            let err = error.to_string();
            let ffi = str_to_ffi(&err);
            mem::forget(err);
            ffi
        }
    }
}

#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_translate_single(
    endpoint_settings: FFIString,
    project_context: FFIString,
    local_context: FFIString,
    source_language: Algorithm,
    translation_language: Algorithm,
    text: FFIString,
    glossary: FFIString,
    out_string: *mut FFIString,
) -> FFIString {
    let project_context = ffi_to_str(project_context);
    let local_context = ffi_to_str(local_context);
    let text = ffi_to_str(text);
    let glossary = ffi_to_str(glossary);
    let endpoint_settings = ffi_to_str(endpoint_settings);

    let glossary: Vec<GlossaryEntry> =
        unsafe { serde_json::from_str(glossary).unwrap_unchecked() };

    let result = (|| -> Result<_, Error> {
        let results = TOKIO_RT.block_on(async move {
            translate_single(
                endpoint_settings,
                source_language,
                translation_language,
                &project_context,
                &local_context,
                &text,
                glossary,
            )
            .await
        })?;

        Ok(results)
    })();

    match result {
        Ok(results) => {
            let str = str_to_ffi(&results);
            mem::forget(results);
            *out_string = str;
            FFIString::null()
        }
        Err(error) => {
            let err = error.to_string();
            let ffi = str_to_ffi(&err);
            mem::forget(err);
            ffi
        }
    }
}

unsafe fn take<'a>(buf: &'a [u8], pos: &mut usize, n: usize) -> &'a [u8] {
    let end = pos.checked_add(n).unwrap_unchecked();
    let out = &buf[*pos..end];
    *pos = end;
    out
}

unsafe fn read_u32_le(buf: &[u8], pos: &mut usize) -> u32 {
    let b = take(buf, pos, 4);
    u32::from_le_bytes(*b.as_ptr().cast::<[u8; 4]>())
}

pub unsafe fn parse_strings<'a>(buf: &'a [u8]) -> Vec<&'a str> {
    let mut pos = 0;

    let count = read_u32_le(buf, &mut pos) as usize;
    let mut out = Vec::with_capacity(count);

    for _ in 0..count {
        let n = read_u32_le(buf, &mut pos) as usize;
        let bytes = take(buf, &mut pos, n);
        let s = str::from_utf8_unchecked(bytes);
        out.push(s);
    }

    out
}

pub fn split_into_sections(input: &str) -> Vec<&str> {
    const MARKER: &str = "<!-- ID -->";

    let mut starts: Vec<usize> = Vec::from([0]);

    let bytes = input.as_bytes();
    let mut i = 0;

    while i < bytes.len() {
        if bytes[i] == b'\n' {
            let line_start = i + 1;

            if line_start + MARKER.len() <= bytes.len()
                && input[line_start..].starts_with(MARKER)
            {
                starts.push(line_start);
            }
        }

        i += 1;
    }

    let mut out = Vec::with_capacity(starts.len());
    for w in 0..starts.len() {
        let s = starts[w];

        let e = if w + 1 < starts.len() {
            starts[w + 1]
        } else {
            input.len()
        };

        out.push(&input[s..e]);
    }

    out
}

#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_translate<'a>(
    endpoint_settings: FFIString,
    project_context: FFIString,
    local_context: FFIString,
    translation_path: FFIString,
    source_language: Algorithm,
    translation_language: Algorithm,
    filenames: ByteBuffer,
    glossary: FFIString,
    out_translated: *mut ByteBuffer,
    out_translated_ffi: *mut ByteBuffer,
) -> FFIString {
    let project_context = ffi_to_str(project_context);
    let local_context = ffi_to_str(local_context);
    let glossary = ffi_to_str(glossary);
    let glossary: Vec<GlossaryEntry> =
        unsafe { serde_json::from_str(glossary).unwrap_unchecked() };

    let translation_path = ffi_to_str(translation_path);
    let endpoint_settings = ffi_to_str(endpoint_settings);

    let map_content = String::new();
    let mut sections: Vec<&str> = Vec::new();

    let result = (|| -> Result<_, Error> {
        let filenames = std::slice::from_raw_parts::<[u8; 13]>(
            filenames.ptr.cast::<[u8; 13]>(),
            filenames.len as usize,
        );

        let mut files: HashMap<&str, Vec<String>> =
            HashMap::with_capacity(filenames.len());

        for filename in filenames {
            let filename = str::from_utf8_unchecked(filename);
            let filename = &filename
                [..=filename.rfind(|chr| chr != '\0').unwrap_unchecked()];

            if filename.starts_with("map") {
                if map_content.is_empty() {
                    let path = Path::new(translation_path).join("maps.txt");

                    #[allow(invalid_reference_casting)]
                    unsafe {
                        *(&mut *(&map_content as *const String
                            as *mut String)) = read_to_string(&path)
                            .map_err(|err| Error::Io(path, err))?;
                    }

                    sections = split_into_sections(&map_content);
                }

                files.insert(filename, Vec::new());
                let entry =
                    unsafe { files.get_mut(filename).unwrap_unchecked() };
                let id = &filename[3..];

                for &section in &sections {
                    let id_line =
                        &section[..section.find('\n').unwrap_or(section.len())];
                    let id_part = &id_line
                        [id_line.find("<#>").unwrap_or(id_line.len()) + 3..];

                    if id_part != id {
                        continue;
                    }

                    for (i, line) in section.split('\n').enumerate() {
                        if line.is_empty() {
                            continue;
                        }

                        if i == 0 {
                            entry.push(line.to_string());
                            continue;
                        }

                        let not_name = !line.starts_with("<!-- NAME");
                        let not_in_game_name =
                            !line.starts_with("<!-- IN-GAME");
                        let not_map_name = !line.starts_with("<!-- MAP NAME");

                        if line.starts_with("<!--")
                            && not_name
                            && not_in_game_name
                            && not_map_name
                        {
                            continue;
                        }

                        if not_name && not_in_game_name && not_map_name {
                            if let Some(separator_pos) = line.find("<#>") {
                                entry.push(line[..separator_pos].to_string());
                            } else {
                                log::error!(
                                    "Failed to split line {i} in file {filename}"
                                );
                            }
                        } else {
                            entry.push(line.to_string());
                        }
                    }
                }
            } else {
                let path = Path::new(&translation_path)
                    .join(filename)
                    .with_extension("txt");
                let content = read_to_string(&path)
                    .map_err(|err| Error::Io(path, err))?;
                let lines = content.split('\n');

                files.insert(filename, Vec::new());

                for (idx, line) in lines.enumerate() {
                    if line.is_empty()
                        || line.starts_with("<!--")
                            && !line.starts_with("<!-- ID")
                            && !line.starts_with("<!-- NAME")
                    {
                        continue;
                    }

                    let entry = files.get_mut(filename).unwrap_unchecked();

                    if !line.starts_with("<!-- ID")
                        && !line.starts_with("<!-- NAME")
                    {
                        if let Some(separator_pos) = line.rfind("<#>") {
                            entry.push(line[0..separator_pos].to_string());
                        } else {
                            log::error!(
                                "Failed to split line {idx} in file {filename}"
                            );
                        }
                    } else {
                        entry.push(line.to_string());
                    }
                }
            }
        }

        let results = TOKIO_RT.block_on(async move {
            translate(
                endpoint_settings,
                source_language,
                translation_language,
                &project_context,
                &local_context,
                files,
                glossary,
            )
            .await
        })?;

        let mut translations: Vec<Vec<String>> =
            Vec::with_capacity(results.len());

        for translated in results.into_values() {
            translations.push(translated);
        }

        Ok(translations)
    })();

    match result {
        Ok(translated_files) => {
            let mut translated_files_ffi =
                Vec::with_capacity(translated_files.len());

            for translated_strings in translated_files.iter() {
                let mut strings_ffi: Vec<FFIString> =
                    Vec::with_capacity(translated_strings.len());

                if translated_strings.is_empty() {
                    translated_files_ffi.push(ByteBuffer {
                        ptr: ptr::null(),
                        len: 0,
                        cap: 0,
                    });
                }

                for string in translated_strings {
                    strings_ffi.push(str_to_ffi(string));
                }

                translated_files_ffi.push(ByteBuffer {
                    ptr: strings_ffi.as_ptr().cast::<u8>(),
                    len: strings_ffi.len() as u32,
                    cap: strings_ffi.capacity() as u32,
                });

                mem::forget(strings_ffi);
            }

            *out_translated_ffi = ByteBuffer {
                ptr: translated_files_ffi.as_ptr().cast::<u8>(),
                len: translated_files_ffi.len() as u32,
                cap: translated_files_ffi.capacity() as u32,
            };

            *out_translated = ByteBuffer {
                ptr: translated_files.as_ptr().cast::<u8>(),
                len: translated_files.len() as u32,
                cap: translated_files.capacity() as u32,
            };

            mem::forget(translated_files);
            mem::forget(translated_files_ffi);

            FFIString::null()
        }
        Err(error) => {
            let err = error.to_string();
            let ffi = str_to_ffi(&err);
            mem::forget(err);
            ffi
        }
    }
}

#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_find_all_matches(
    source_haystack: FFIString,
    source_needle: FFIString,
    source_mode: MatchModeInfo,
    tr_haystack: FFIString,
    tr_needle: FFIString,
    tr_mode: MatchModeInfo,
    source_algorithm: Algorithm,
    tr_algorithm: Algorithm,
    out: *mut ByteBuffer,
) -> FFIString {
    let result = (|| -> Result<_, Error> {
        let source_haystack = ffi_to_str(source_haystack);
        let source_needle = ffi_to_str(source_needle);
        let tr_haystack = ffi_to_str(tr_haystack);
        let tr_needle = ffi_to_str(tr_needle);

        let m = find_all_matches(
            &source_haystack,
            &source_needle,
            source_mode,
            &tr_haystack,
            &tr_needle,
            tr_mode,
            source_algorithm,
            tr_algorithm,
        )?;

        let bytes = match m {
            None => Vec::new(),
            Some((src, tr)) => {
                let mut vec = Vec::with_capacity(
                    4 + (src.len() * (size_of::<MatchResult>() / 2))
                        + (tr.len() * (size_of::<MatchResult>() / 2)),
                );

                vec.extend((src.len() as u32).to_le_bytes());

                for m in src {
                    match m {
                        MatchResult::Exact { offset, len } => {
                            vec.extend((offset as u32).to_le_bytes());
                            vec.extend((len as u32).to_le_bytes());
                            vec.extend(0f32.to_le_bytes());
                        }
                        MatchResult::Fuzzy { offset, len, score } => {
                            vec.extend((offset as u32).to_le_bytes());
                            vec.extend((len as u32).to_le_bytes());
                            vec.extend((score as f32).to_le_bytes());
                        }
                    }
                }

                vec.extend((tr.len() as u32).to_le_bytes());

                for m in tr {
                    match m {
                        MatchResult::Exact { offset, len } => {
                            vec.extend((offset as u32).to_le_bytes());
                            vec.extend((len as u32).to_le_bytes());
                            vec.extend(0f32.to_le_bytes());
                        }
                        MatchResult::Fuzzy { offset, len, score } => {
                            vec.extend((offset as u32).to_le_bytes());
                            vec.extend((len as u32).to_le_bytes());
                            vec.extend((score as f32).to_le_bytes());
                        }
                    }
                }

                vec
            }
        };

        Ok(bytes)
    })();

    match result {
        Ok(mut serialized) => {
            *out = ByteBuffer {
                ptr: serialized.as_mut_ptr(),
                len: serialized.len() as u32,
                cap: serialized.capacity() as u32,
            };

            mem::forget(serialized);

            FFIString::null()
        }
        Err(error) => {
            let err = error.to_string();
            let ffi = str_to_ffi(&err);
            mem::forget(err);
            ffi
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rpgm_add_detect_lang(string: FFIString) {
    let s = ffi_to_str(string);
    detect_lang(&s);
}

#[unsafe(no_mangle)]
pub extern "C" fn rpgm_get_detected_lang(out_string: *mut FFIString) {
    let lang = get_lang().unwrap_or("");

    unsafe {
        *out_string = str_to_ffi(&lang.to_string());
    }
}

type LogCallback = extern "C" fn(level: u8, str: FFIString);

static LOG_CALLBACK: OnceLock<LogCallback> = OnceLock::new();

struct FFILogger;

impl Log for FFILogger {
    fn enabled(&self, _: &Metadata) -> bool {
        true
    }

    fn log(&self, record: &Record) {
        let Some(cb) = LOG_CALLBACK.get() else { return };

        let text = format!("[{}] {}", record.target(), record.args());

        cb(record.level() as u8, str_to_ffi(&text));
        mem::forget(text);
    }

    fn flush(&self) {}
}

#[unsafe(no_mangle)]
pub extern "C" fn init_rust_logger(callback: LogCallback) {
    if LOG_CALLBACK.set(callback).is_err() {
        return;
    }

    log::set_logger(Box::leak(Box::new(FFILogger)))
        .expect("logger already set");
    log::set_max_level(log::LevelFilter::Trace);

    log::info!("Rust FFI initialized");
}

#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_count_words(
    text: FFIString,
    algorithm: Algorithm,
    out: *mut u32,
) -> FFIString {
    let result = (|| -> Result<_, Error> {
        let count = count_words(&ffi_to_str(text), algorithm)?;
        Ok(count)
    })();

    match result {
        Ok(count) => {
            *out = count;
            FFIString::null()
        }
        Err(error) => {
            let err = error.to_string();
            let ffi = str_to_ffi(&err);
            mem::forget(err);
            ffi
        }
    }
}

#[cfg(feature = "languagetool")]
#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_language_tool_lint(
    text: FFIString,
    base_url: FFIString,
    api_key: FFIString,
    algorithm: Algorithm,
) -> FFIString {
    // TODO

    FFIString::null()
}

#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_decrypt_asset(
    path: FFIString,
    out: *mut ByteBuffer,
) -> FFIString {
    let result = (|| -> Result<_, Error> {
        let decrypted = decrypt_asset(Path::new(&ffi_to_str(path)))?;
        Ok(decrypted)
    })();

    match result {
        Ok(decrypted) => {
            *out = ByteBuffer {
                ptr: decrypted.as_ptr(),
                len: decrypted.len() as u32,
                cap: decrypted.capacity() as u32,
            };

            mem::forget(decrypted);

            FFIString::null()
        }
        Err(error) => {
            let err = error.to_string();
            let ffi = str_to_ffi(&err);
            mem::forget(err);
            ffi
        }
    }
}

#[cfg(any(
    feature = "json-highlighting",
    feature = "js-highlighting",
    feature = "ruby-highlighting"
))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rpgm_highlight_code(
    input: FFIString,
    lang: HighlightLanguage,
    out: *mut ByteBuffer,
) {
    let input = ffi_to_str(input);
    let tokens = highlight_code(input, lang);

    *out = ByteBuffer {
        ptr: tokens.as_ptr().cast::<u8>(),
        len: tokens.len() as u32,
        cap: tokens.capacity() as u32,
    };

    mem::forget(tokens);
}

#[unsafe(no_mangle)]
#[must_use]
pub unsafe extern "C" fn rpgm_generate_json(
    content: FFIString,
    filename: FFIString,
    json_out: *mut FFIString,
) -> FFIString {
    let result = (|| -> Result<_, Error> {
        let json = generate_json(
            ffi_to_str(content).as_bytes(),
            ffi_to_str(filename),
        )?;
        Ok(json)
    })();

    match result {
        Ok(json) => {
            *json_out = str_to_ffi(&json);
            mem::forget(json);

            FFIString::null()
        }
        Err(err) => {
            let err = err.to_string();
            let ffi = str_to_ffi(&err);
            mem::forget(err);
            ffi
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rpgm_beautify_json(
    json: FFIString,
    out: *mut FFIString,
) {
    let beautified = beautify_json(ffi_to_str(json));
    *out = str_to_ffi(&beautified);
    mem::forget(beautified);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rpgm_get_ini_title(
    project_path: FFIString,
    out: *mut ByteBuffer,
) -> FFIString {
    let project_path = ffi_to_str(project_path);

    let result = (|| -> Result<_, Error> {
        let title = get_ini_title(project_path)?;
        Ok(title)
    })();

    match result {
        Ok(title) => {
            *out = ByteBuffer {
                ptr: title.as_ptr(),
                len: title.len() as u32,
                cap: title.capacity() as u32,
            };

            mem::forget(title);

            FFIString::null()
        }
        Err(err) => {
            let err = err.to_string();
            let ffi = str_to_ffi(&err);
            mem::forget(err);
            ffi
        }
    }
}
