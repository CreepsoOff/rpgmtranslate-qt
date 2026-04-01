# Билдинг из исходного кода

## Требования

- Git
- Rust 1.87+
- C++23-сомвестимый компилятор (`clang`, `gcc`, `msvc`)
- CMake
- Qt6 (>= 6.8.2), с поддержкой PNG и SVG
- Nuspell (опционально, с ENABLE_NUSPELL)
- libgit2 (опционально, с ENABLE_LIBGIT2)
- FFmpeg (>= 7.1.1) (опционально, с ENABLE_FFMPEG)

## Процесс

Клонируйте репозиторий: `git clone https://github.com/RPG-Maker-Translation-Tools/rpgmtranslate-qt`.

Мы предоставляем скрипты конфигурации - `build.ps1` для PowerShell и `build.sh` для sh/bash.

Вы можете узнать список доступных опций используя `./configure --help`.

После конфигурации с необходимыми аргументами, вы можете сделать `cd` в директорию билда и запустить `cmake --build . -j`, это забилдит приложение.

Артефакты билда выводятся в директорию `build/target`.

Стандартные билды программы включают:

- Qt6, построенный со следующей конфигурацией:
  - Windows: `-c++std c++23 -platform win32-msvc -ltcg -static -static-runtime -release -nomake tests -nomake examples -nomake benchmarks -no-feature-testlib -no-opengl -qt-harfbuzz -qt-freetype -qt-libpng -qt-libjpeg -qt-webp -qt-tiff -qt-zlib -qt-doubleconversion -qt-pcre -no-emojisegmenter -no-icu -no-gif -gui -widgets -submodules qtbase,qtimageformats,qttools -qpa "windows" -disable-deprecated-up-to 0x068200 QT_SKIP_EXCEPTIONS=ON`
