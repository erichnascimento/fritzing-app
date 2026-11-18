#!/bin/bash -e
# Recompila o Fritzing (Apple Silicon, Qt 6.10.3, Xcode 27) e prepara o Fritzing.app.
# Veja MACOS-ARM64-BUILD.md. Dependências já compiladas ficam ao lado do fritzing-app (boost, libgit2, quazip, Clipper1, svgpp, ngspice).
# Este script fica em fritzing-app/tools; $ROOT é a pasta que contém o fritzing-app.
#
# Uso: build_fritzing_mac_arm64.sh [--install]
#   --install  copia o app para /Applications/Fritzing.app (com symlink para $ROOT/fritzing-parts)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QT="${QT:-$HOME/Qt/6.10.3/macos}"

INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    *) echo "Opção desconhecida: $arg" >&2; echo "Uso: $0 [--install]" >&2; exit 2 ;;
  esac
done

mkdir -p "$ROOT/_build/fritzing" && cd "$ROOT/_build/fritzing"

# -include arm_acle.h : o Qt 6.10 usa __yield sem incluir arm_acle.h (erro no clang do Xcode 27)
# -after ...=arm64    : o phoenix.pro força build universal (x86_64 arm64); aqui só arm64
"$QT/bin/qmake" "$ROOT/fritzing-app/phoenix.pro" CONFIG+=release CONFIG+=sdk_no_version_check \
  "QMAKE_CXXFLAGS+=-include arm_acle.h" -after QMAKE_APPLE_DEVICE_ARCHS=arm64
make -j"$(sysctl -n hw.ncpu)" release

APP="$ROOT/_build/release64/Fritzing.app"
M="$APP/Contents/MacOS"

# libpolyclipping vem com install name sem caminho; aponta para o rpath
install_name_tool -change libpolyclipping.22.dylib @rpath/libpolyclipping.22.dylib "$M/Fritzing" 2>/dev/null || true

# Arquivos de runtime: simulador, exemplos, ajuda, traduções
cp "$ROOT/ngspice-42/lib/libngspice.0.dylib" "$M/"
rm -rf "$M/ngspice" && cp -R "$ROOT/ngspice-42/lib/ngspice" "$M/"
rm -rf "$M/sketches" "$M/help" && cp -R "$ROOT/fritzing-app/sketches" "$ROOT/fritzing-app/help" "$M/"
mkdir -p "$M/translations"
for ts in "$ROOT"/fritzing-app/translations/*.ts; do
  "$QT/bin/lrelease" -silent "$ts" -qm "$M/translations/$(basename "${ts%.ts}").qm"
done
find "$M/translations" -name "*.qm" -size -128c -delete
# Realce de sintaxe da janela de código (programwindow.cpp carrega translations/syntax/styles.xml)
mkdir -p "$M/translations/syntax" && cp "$ROOT"/fritzing-app/translations/syntax/*.xml "$M/translations/syntax/"

codesign --force --deep -s - "$APP"
echo "Pronto: $APP"

if [ "$INSTALL" = 1 ]; then
  DEST="/Applications/Fritzing.app"
  if [ -e "$DEST" ]; then
    # Só substitui uma instalação feita por este script (bundle id do Fritzing + symlink de peças)
    BID="$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$DEST/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$BID" != "org.fritzing.Fritzing" ] || [ ! -L "$DEST/Contents/MacOS/fritzing-parts" ]; then
      echo "Erro: $DEST existe e não foi instalado por este script; remova-o manualmente." >&2
      exit 1
    fi
    rm -rf "$DEST"
  fi
  ditto "$APP" "$DEST"
  # Fora de $ROOT, subir pastas a partir do executável não acha o fritzing-parts;
  # FolderUtils::getApplicationSubFolder procura primeiro em applicationDirPath()/fritzing-parts
  ln -s "$ROOT/fritzing-parts" "$DEST/Contents/MacOS/fritzing-parts"
  codesign --force --deep -s - "$DEST"
  echo "Instalado: $DEST"
fi
