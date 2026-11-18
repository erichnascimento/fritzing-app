#!/bin/bash -e
# Recompila o Fritzing (Apple Silicon, Qt 6.10.3, Xcode 27) e prepara o Fritzing.app.
# Veja MACOS-ARM64-BUILD.md. Dependências já compiladas ficam ao lado do fritzing-app (boost, libgit2, quazip, Clipper1, svgpp, ngspice).
# Este script fica em fritzing-app/tools; $ROOT é a pasta que contém o fritzing-app.
#
# Uso: build_fritzing_mac_arm64.sh [--install]
#   --install  copia o app (autocontido) para /Applications/Fritzing.app e o registra no LaunchServices
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
MARKER="Contents/Resources/.fritzing-local-build"   # identifica um app montado por este script

# libpolyclipping vem com install name sem caminho; aponta para o rpath
install_name_tool -change libpolyclipping.22.dylib @rpath/libpolyclipping.22.dylib "$M/Fritzing" 2>/dev/null || true

# Deploy: frameworks e plugins do Qt, quazip e polyclipping em Contents/Frameworks, qt.conf
"$QT/bin/macdeployqt" "$APP" -verbose=1 \
  -libpath="$ROOT/quazip-$(basename "$(dirname "$QT")")-1.4intuisphere/lib" -libpath="$ROOT/Clipper1-6.4.2/lib" \
  -libpath="$QT/lib"
# A polyclipping vem com install name sem caminho; dentro do bundle passa a ser @rpath
install_name_tool -id @rpath/libpolyclipping.22.dylib "$APP/Contents/Frameworks/libpolyclipping.22.dylib"
# Só o driver SQLite é usado (banco de peças); os outros dependem de libs que não vêm no bundle
rm -f "$APP"/Contents/PlugIns/sqldrivers/libqsql{mimer,odbc,psql}.dylib
# Remove os rpaths absolutos (dependências em $ROOT e ~/Qt); fica só @executable_path/../Frameworks
otool -l "$M/Fritzing" | awk '/LC_RPATH/{f=1} f&&/ path /{print $2; f=0}' | grep '^/' | while read -r r; do
  install_name_tool -delete_rpath "$r" "$M/Fritzing"
done
otool -l "$M/Fritzing" | grep -q '@executable_path/../Frameworks' || \
  install_name_tool -add_rpath @executable_path/../Frameworks "$M/Fritzing"

# Simulador: o Fritzing procura a dylib em QCoreApplication::libraryPaths() (inclui Contents/MacOS)
# e carrega ngspice/analog.cm ao lado dela; o spinit do prefixo do ngspice não é necessário
cp "$ROOT/ngspice-42/lib/libngspice.0.dylib" "$M/"
install_name_tool -id @rpath/libngspice.0.dylib "$M/libngspice.0.dylib"
rm -rf "$M/ngspice" && cp -R "$ROOT/ngspice-42/lib/ngspice" "$M/"

# Peças dentro do bundle, com o .git (o atualizador de peças usa libgit2 nesta pasta).
# Ficam em Resources: em Contents/MacOS o codesign trata o ".git" como código aninhado e a assinatura falha.
# O symlink relativo em MacOS é o primeiro lugar onde FolderUtils::getApplicationSubFolder procura.
mkdir -p "$APP/Contents/Resources/fritzing-parts"
rsync -a --delete "$ROOT/fritzing-parts/" "$APP/Contents/Resources/fritzing-parts/"
rm -rf "$M/fritzing-parts" && ln -s ../Resources/fritzing-parts "$M/fritzing-parts"

# Arquivos de runtime: exemplos, ajuda, traduções
rm -rf "$M/sketches" "$M/help" && cp -R "$ROOT/fritzing-app/sketches" "$ROOT/fritzing-app/help" "$M/"
mkdir -p "$M/translations"
for ts in "$ROOT"/fritzing-app/translations/*.ts; do
  "$QT/bin/lrelease" -silent "$ts" -qm "$M/translations/$(basename "${ts%.ts}").qm"
done
find "$M/translations" -name "*.qm" -size -128c -delete
# Realce de sintaxe da janela de código (programwindow.cpp carrega translations/syntax/styles.xml)
mkdir -p "$M/translations/syntax" && cp "$ROOT"/fritzing-app/translations/syntax/*.xml "$M/translations/syntax/"

touch "$APP/$MARKER"
codesign --force --deep -s - "$APP"
codesign -v --strict "$APP"
echo "Pronto: $APP"

if [ "$INSTALL" = 1 ]; then
  DEST="/Applications/Fritzing.app"
  if [ -e "$DEST" ]; then
    # Só substitui um app instalado por este script: bundle id do Fritzing + marcador
    # (ou o symlink fritzing-parts das versões anteriores do script)
    BID="$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$DEST/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$BID" != "org.fritzing.Fritzing" ] || \
       { [ ! -e "$DEST/$MARKER" ] && [ ! -L "$DEST/Contents/MacOS/fritzing-parts" ]; }; then
      echo "Erro: $DEST existe e não foi instalado por este script; remova-o manualmente." >&2
      exit 1
    fi
    rm -rf "$DEST"
  fi
  ditto "$APP" "$DEST"
  codesign --force --deep -s - "$DEST"
  codesign -v --strict "$DEST"
  # Launchpad/Spotlight/open -a devem abrir a cópia instalada, não a de _build
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREGISTER" -u "$APP" || true
  "$LSREGISTER" -f "$DEST"
  echo "Instalado: $DEST"
fi
