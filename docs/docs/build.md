# Building from Source

## Prerequisites

- Git
- Rust 1.87+
- C++23-compatible compiler (`clang`, `gcc`, `msvc`)
- CMake
- Qt6 (>= 6.8.2), with support for PNG and SVG
- Nuspell (optional, via ENABLE_NUSPELL)
- LanguageTool (optional, via ENABLE_LANGUAGETOOL)
- libgit2 (optional, via ENABLE_LIBGIT2)

## Building Process

Clone the repository: `git clone https://github.com/RPG-Maker-Translation-Tools/rpgmtranslate-qt`.

We provide configure scripts - `build.ps1` for PowerShell and `build.sh` for sh/bash.

You can get the list of available options using `./configure --help`.

After running configure with the desired arguments, you can `cd` to the build directory and run `cmake --build . -j`, that will build the application.

Build artifacts are output to `build/target` directory.

Default builds of the program include:

- Qt6 built with the following configuration:
  - Windows: `-c++std c++23 -platform win32-msvc -ltcg -static -static-runtime -release -nomake tests -nomake examples -nomake benchmarks -no-feature-testlib -no-opengl -qt-harfbuzz -qt-freetype -qt-libpng -qt-libjpeg -qt-webp -qt-tiff -qt-zlib -qt-doubleconversion -qt-pcre -no-emojisegmenter -no-icu -no-gif -gui -widgets -submodules qtbase,qtimageformats,qttools -qpa "windows" -disable-deprecated-up-to 0x068200 QT_SKIP_EXCEPTIONS=ON`
