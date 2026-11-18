# Compilando o Fritzing no macOS (Apple Silicon)

Este guia registra como o Fritzing foi compilado e executado a partir do código-fonte num Mac com Apple Silicon e toolchain recente. Ele não usa Homebrew nem conta da Qt.

Ambiente testado:

| Item | Versão |
|---|---|
| Hardware | Apple Silicon (arm64) |
| macOS | 27.0.1 |
| Xcode | 27.2 (SDK macOS 27.2, clang 21) |
| Qt | 6.10.3 (o `phoenix.pro` aceita de 6.5.3 a 6.10.10) |

O script [`tools/build_fritzing_mac_arm64.sh`](tools/build_fritzing_mac_arm64.sh) automatiza a compilação do Fritzing e a montagem do `.app` (seções 3 e 4). Com `--install`, ele também instala o app em `/Applications` (seção 4.1).

---

## 1. Estrutura de pastas

Os arquivos `pri/*detect.pri` procuram as dependências **ao lado** do `fritzing-app`. Por isso, tudo fica numa pasta de trabalho comum, chamada aqui de `$WORKSPACE`:

```
$WORKSPACE/
├── fritzing-app/                    # este repositório
├── fritzing-parts/                  # repositório de peças
├── boost_1_85_0/                    # headers do Boost
├── svgpp-1.3.1/                     # headers do svgpp
├── libgit2-1.7.1/                   # libgit2 instalada (include/, lib/libgit2.a)
├── Clipper1-6.4.2/                  # Clipper instalado (include/polyclipping, lib/)
├── quazip-6.10.3-1.4intuisphere/    # QuaZip instalado (o sufixo "intuisphere" é exigido pelo quazipdetect.pri)
├── ngspice-42/                      # ngspice instalado (include/ngspice, lib/libngspice.0.dylib)
├── _src/  _build/                   # fontes e builds intermediários (pastas descartáveis)
```

```bash
cd fritzing-app                   # rode a partir do clone deste repositório
export WORKSPACE="$(cd .. && pwd)" # a pasta que contém o fritzing-app
cd "$WORKSPACE"
export PATH="$HOME/Qt/Tools/CMake/CMake.app/Contents/bin:$HOME/Qt/Tools/Ninja:$PATH"
```

## 2. Dependências

### 2.1 Qt 6.10.3, CMake e Ninja (via aqtinstall, sem conta Qt)

[aqtinstall](https://github.com/miurahr/aqtinstall) baixa os mesmos binários oficiais dos mirrors da Qt.

```bash
python3 -m venv "$WORKSPACE/_tools/aqtvenv"
AQT="$WORKSPACE/_tools/aqtvenv/bin/aqt"
"$WORKSPACE/_tools/aqtvenv/bin/pip" install aqtinstall

"$AQT" install-qt mac desktop 6.10.3 clang_64 -O ~/Qt -m qtserialport qtimageformats qt5compat
"$AQT" install-tool mac desktop tools_cmake -O ~/Qt
"$AQT" install-tool mac desktop tools_ninja -O ~/Qt
```

- `qtserialport`: obrigatório para o Fritzing.
- `qt5compat`: obrigatório para o QuaZip 1.4 com Qt 6.
- Alternativa: o Qt Online Installer, marcando os mesmos módulos.

### 2.2 Boost 1.85 e svgpp 1.3.1 (só headers)

O `boostdetect.pri` procura especificamente por `boost_1_85_0`.

```bash
curl -fL -o boost.tar.gz https://archives.boost.io/release/1.85.0/source/boost_1_85_0.tar.gz
tar xzf boost.tar.gz
curl -fL -o svgpp.tar.gz https://github.com/svgpp/svgpp/archive/refs/tags/v1.3.1.tar.gz
tar xzf svgpp.tar.gz
```

### 2.3 libgit2 1.7.1 (estática)

```bash
mkdir -p _src
curl -fL https://github.com/libgit2/libgit2/archive/refs/tags/v1.7.1.tar.gz | tar xz -C _src
cmake -S _src/libgit2-1.7.1 -B _build/libgit2 -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF -DBUILD_CLI=OFF -DUSE_SSH=OFF \
  -DUSE_HTTPS=SecureTransport -DREGEX_BACKEND=builtin \
  -DUSE_BUNDLED_ZLIB=OFF \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_INSTALL_PREFIX="$WORKSPACE/libgit2-1.7.1"
cmake --build _build/libgit2 && cmake --install _build/libgit2
```

> **Problema:** a zlib embutida na libgit2 1.7.1 define `fdopen` como macro, o que quebra os headers `stdio.h` do SDK 27 (`error: expected identifier or '('`).
> **Correção:** `-DUSE_BUNDLED_ZLIB=OFF`, que passa a usar a zlib do sistema (o Fritzing já linka `-lz`).

### 2.4 Clipper 6.4.2 (polyclipping)

```bash
curl -fL -o clipper.zip "https://sourceforge.net/projects/polyclipping/files/clipper_ver6.4.2.zip/download"
unzip -q clipper.zip -d _src/clipper-6.4.2
cmake -S _src/clipper-6.4.2/cpp -B _build/clipper -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_INSTALL_PREFIX="$WORKSPACE/Clipper1-6.4.2"
cmake --build _build/clipper && cmake --install _build/clipper
```

`CMAKE_POLICY_VERSION_MINIMUM=3.5` é necessário porque o `CMakeLists.txt` do Clipper declara uma versão mínima de CMake antiga demais para as versões atuais.

### 2.5 QuaZip 1.4

```bash
curl -fL https://github.com/stachenov/quazip/archive/refs/tags/v1.4.tar.gz | tar xz -C _src
cmake -S _src/quazip-1.4 -B _build/quazip -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DQUAZIP_QT_MAJOR_VERSION=6 -DCMAKE_PREFIX_PATH="$HOME/Qt/6.10.3/macos" \
  -DQUAZIP_FETCH_LIBS=OFF -DQUAZIP_BZIP2=OFF -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_INSTALL_PREFIX="$WORKSPACE/quazip-6.10.3-1.4intuisphere"
cmake --build _build/quazip && cmake --install _build/quazip
```

O nome da pasta de instalação precisa conter a versão exata do Qt (`quazip-<QT_VERSION>-1.4intuisphere`).

### 2.6 ngspice 42 (simulador)

Para compilar, o Fritzing só precisa do header `sharedspice.h`. Para o simulador funcionar com o app rodando, ele carrega `libngspice.0.dylib`.

```bash
curl -fL -o ngspice-42.tar.gz "https://sourceforge.net/projects/ngspice/files/ng-spice-rework/old-releases/42/ngspice-42.tar.gz/download"
tar xzf ngspice-42.tar.gz -C _src
mkdir -p _build/ngspice && cd _build/ngspice
"$WORKSPACE/_src/ngspice-42/configure" --prefix="$WORKSPACE/ngspice-42" \
  --with-ngshared --enable-xspice --enable-cider --disable-debug --enable-openmp=no \
  CFLAGS="-O2 -arch arm64" CXXFLAGS="-O2 -arch arm64 -Wno-invalid-specialization"
make -j"$(sysctl -n hw.ncpu)" && make install
cd "$WORKSPACE"
```

> **Problema:** o clang 21 rejeita a especialização de `std::is_compound` em `cppduals` (`-Winvalid-specialization`, tratado como erro).
> **Correção:** `-Wno-invalid-specialization` no `CXXFLAGS`.

### 2.7 Peças (fritzing-parts)

```bash
git clone --depth 1 https://github.com/fritzing/fritzing-parts.git
```

O Fritzing encontra essa pasta subindo os diretórios a partir do executável (`FolderUtils::getApplicationSubFolder`), então basta ela estar em `$WORKSPACE`.

## 3. Compilando o Fritzing

O build é feito fora da árvore do repositório (*shadow build*), em `_build/fritzing`:

```bash
mkdir -p _build/fritzing && cd _build/fritzing
~/Qt/6.10.3/macos/bin/qmake ../../fritzing-app/phoenix.pro \
  CONFIG+=release CONFIG+=sdk_no_version_check \
  "QMAKE_CXXFLAGS+=-include arm_acle.h" \
  -after QMAKE_APPLE_DEVICE_ARCHS=arm64
make -j"$(sysctl -n hw.ncpu)" release
```

O app é gerado em `$WORKSPACE/_build/release64/Fritzing.app`.

> **Problema 1:** no Qt 6.10, o `qyieldcpu.h` chama `__yield()` quando `__has_builtin(__yield)` é verdadeiro. O clang do Xcode 27 reconhece o builtin, mas exige a declaração de `<arm_acle.h>`:
> `error: implicitly declaring library function '__yield' with type 'void ()'`
> **Correção:** forçar a inclusão do header com `QMAKE_CXXFLAGS+=-include arm_acle.h`.

> **Problema 2:** o `phoenix.pro` fixa `QMAKE_APPLE_DEVICE_ARCHS = x86_64 arm64` (build universal). Na parte x86_64, `arm_acle.h` falha (`"ACLE intrinsics support not enabled."`), e o valor passado na linha de comando é sobrescrito pelo `.pro`.
> **Correção:** usar `-after QMAKE_APPLE_DEVICE_ARCHS=arm64`, que o qmake aplica depois de ler o projeto.

`CONFIG+=sdk_no_version_check` silencia o aviso de que o Qt 6.10 não foi testado com o SDK 27.

Os avisos do linker do tipo `built for newer 'macOS' version (27.0) than being linked (13.0)` são esperados: as dependências foram compiladas com o deployment target padrão da máquina. Não atrapalham a execução local.

## 4. Montando o Fritzing.app

```bash
APP="$WORKSPACE/_build/release64/Fritzing.app"; M="$APP/Contents/MacOS"

# A libpolyclipping é instalada com install name sem caminho; aponta para o rpath
install_name_tool -change libpolyclipping.22.dylib @rpath/libpolyclipping.22.dylib "$M/Fritzing"

# Simulador: o Fritzing procura a dylib em QCoreApplication::libraryPaths() (inclui Contents/MacOS)
cp "$WORKSPACE/ngspice-42/lib/libngspice.0.dylib" "$M/"
cp -R "$WORKSPACE/ngspice-42/lib/ngspice" "$M/"     # code models (analog.cm etc.)

# Exemplos, ajuda e traduções
cp -R "$WORKSPACE/fritzing-app/sketches" "$WORKSPACE/fritzing-app/help" "$M/"
mkdir -p "$M/translations"
for ts in "$WORKSPACE"/fritzing-app/translations/*.ts; do
  ~/Qt/6.10.3/macos/bin/lrelease -silent "$ts" -qm "$M/translations/$(basename "${ts%.ts}").qm"
done
find "$M/translations" -name "*.qm" -size -128c -delete
# Realce de sintaxe da janela de código (carrega translations/syntax/styles.xml)
mkdir -p "$M/translations/syntax"
cp "$WORKSPACE"/fritzing-app/translations/syntax/*.xml "$M/translations/syntax/"

# Assinatura ad-hoc, obrigatória no Apple Silicon depois de alterar o binário
codesign --force --deep -s - "$APP"

open "$APP"
```

Sem os arquivos de `translations/syntax`, o log de inicialização mostra `Unable to open …/translations/syntax/styles.xml` e `QDomDocument::setContent: Failed to open device`.

Para ver o log de inicialização, rode `"$M/Fritzing" -debug > fritzing-debug.log 2>&1`. Não passe nenhum argumento depois de `-debug`: o Fritzing usa o argumento seguinte como arquivo de saída do log e sobrescreve esse arquivo (por exemplo, um `.fzz`).

### 4.1 Instalando em /Applications (opcional)

```bash
fritzing-app/tools/build_fritzing_mac_arm64.sh --install
```

Depois de montar o app em `_build/release64`, o script:

1. Apaga um `/Applications/Fritzing.app` anterior, mas só se ele tiver sido instalado pelo próprio script (bundle id `org.fritzing.Fritzing` e o symlink de peças descrito abaixo). Se houver outro Fritzing lá, o script para sem apagar nada.
2. Copia o app com `ditto`.
3. Cria o symlink `Contents/MacOS/fritzing-parts -> $WORKSPACE/fritzing-parts`. Fora de `$WORKSPACE`, subir as pastas a partir do executável não encontra as peças. `FolderUtils::getApplicationSubFolder` procura primeiro em `applicationDirPath()/fritzing-parts`.
4. Reassina com `codesign --force --deep -s -`.

O script não usa `sudo`. Se a pasta `/Applications` não puder ser gravada pelo usuário, a cópia falha.

O app instalado **não é autocontido**. Ele continua dependendo de `$WORKSPACE`, que guarda a quazip e o Clipper (via rpath), o `ngspice-42` (caminho gravado na `libngspice`) e o `fritzing-parts` (via symlink). Também depende de `~/Qt/6.10.3`. Se alguma dessas pastas for movida ou apagada, o app instalado deixa de funcionar.

## 5. Limitações conhecidas

- **Só para uso local.** O app gerado roda apenas em arm64 e linka as dependências por caminho absoluto (rpath para `$WORKSPACE` e `~/Qt`). Distribuir exigiria `macdeployqt`, copiar as dylibs para dentro do bundle, assinar com Developer ID e notarizar.
- O `tools/deploy_fritzing_mac.sh` original está desatualizado (Qt 5 em `/usr/local`).
- Na primeira execução (`Fritzing -debug`), enquanto o banco de peças é montado, até 5 peças obsoletas referenciadas pelo bin "Core Parts" podem gerar `SQLITE: couldn't insert part … Parameter count mismatch`. Não impedem o uso.
- **A `libngspice` depende de `$WORKSPACE/ngspice-42` em runtime.** O ngspice grava o prefixo de instalação (`$WORKSPACE/ngspice-42/bin` e `.../share/ngspice`, onde fica o `spinit`). Copiar a dylib para dentro do bundle não remove essa dependência. Se o ngspice for movido, ele precisa ser recompilado com o novo `--prefix` (seção 2.6).
- O binário do Fritzing contém caminhos do tipo `…/_src/libgit2-1.7.1/src/…`. Eles vêm dos `__FILE__` da `libgit2.a` estática e registram onde ela foi compilada. São usados apenas em mensagens internas e não afetam a execução, então não é preciso recompilar a libgit2 depois de mover o `$WORKSPACE`.
- O simulador (ngspice) foi compilado e empacotado, mas ainda não foi testado com o app rodando.

## 6. Docker / cross-compilação

Compilar para macOS a partir de um container Linux é possível na teoria (osxcross + SDK do macOS + Qt host Linux e Qt target macOS), mas é frágil. Além disso, a licença do SDK restringe seu uso a hardware Apple. O próprio `docker/HOWTO.txt` registra que só existem containers para Linux. Para builds automatizados de macOS, o caminho recomendado é um runner macOS (por exemplo, GitHub Actions `macos-14`/`macos-15`).
