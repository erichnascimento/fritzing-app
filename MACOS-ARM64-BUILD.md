# Compilando o Fritzing no macOS (Apple Silicon)

Este guia registra como o Fritzing foi compilado e executado a partir do código-fonte num Mac com Apple Silicon e toolchain recente. Ele não usa Homebrew nem conta da Qt.

Ambiente testado:

| Item | Versão |
|---|---|
| Hardware | Apple Silicon (arm64) |
| macOS | 27.0.1 |
| Xcode | 27.2 (SDK macOS 27.2, clang 21) |
| Qt | 6.10.3 (o `phoenix.pro` aceita de 6.5.3 a 6.10.10) |

O script [`tools/build_fritzing_mac_arm64.sh`](tools/build_fritzing_mac_arm64.sh) automatiza a compilação do Fritzing e a montagem do `.app` (seções 3 e 4). O app gerado é autocontido. Com `--install`, o script também instala o app em `/Applications` (seção 4.1).

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

## 4. Montando o Fritzing.app (autocontido)

O script faz esta etapa logo depois do `make`. O resultado é um `.app` que não depende de `~/Qt` nem de nenhuma pasta de `$WORKSPACE`:

```bash
APP="$WORKSPACE/_build/release64/Fritzing.app"; M="$APP/Contents/MacOS"; QT=~/Qt/6.10.3/macos

# A libpolyclipping é instalada com install name sem caminho; aponta para o rpath
install_name_tool -change libpolyclipping.22.dylib @rpath/libpolyclipping.22.dylib "$M/Fritzing"

# Qt (frameworks, plugins, qt.conf), quazip e polyclipping em Contents/Frameworks
"$QT/bin/macdeployqt" "$APP" \
  -libpath="$WORKSPACE/quazip-6.10.3-1.4intuisphere/lib" -libpath="$WORKSPACE/Clipper1-6.4.2/lib" -libpath="$QT/lib"
install_name_tool -id @rpath/libpolyclipping.22.dylib "$APP/Contents/Frameworks/libpolyclipping.22.dylib"
rm -f "$APP"/Contents/PlugIns/sqldrivers/libqsql{mimer,odbc,psql}.dylib   # só o SQLite é usado

# Remove os rpaths absolutos ($WORKSPACE, ~/Qt); fica só @executable_path/../Frameworks
otool -l "$M/Fritzing" | awk '/LC_RPATH/{f=1} f&&/ path /{print $2; f=0}' | grep '^/' |
  while read -r r; do install_name_tool -delete_rpath "$r" "$M/Fritzing"; done

# Simulador: o Fritzing procura a dylib em QCoreApplication::libraryPaths() (inclui Contents/MacOS)
cp "$WORKSPACE/ngspice-42/lib/libngspice.0.dylib" "$M/"
install_name_tool -id @rpath/libngspice.0.dylib "$M/libngspice.0.dylib"
cp -R "$WORKSPACE/ngspice-42/lib/ngspice" "$M/"     # code models (analog.cm etc.)

# Peças, com o .git, em Resources, e um symlink relativo em MacOS
rsync -a --delete "$WORKSPACE/fritzing-parts/" "$APP/Contents/Resources/fritzing-parts/"
ln -s ../Resources/fritzing-parts "$M/fritzing-parts"

# Exemplos, ajuda e traduções
cp -R "$WORKSPACE/fritzing-app/sketches" "$WORKSPACE/fritzing-app/help" "$M/"
mkdir -p "$M/translations"
for ts in "$WORKSPACE"/fritzing-app/translations/*.ts; do
  "$QT/bin/lrelease" -silent "$ts" -qm "$M/translations/$(basename "${ts%.ts}").qm"
done
find "$M/translations" -name "*.qm" -size -128c -delete
# Realce de sintaxe da janela de código (carrega translations/syntax/styles.xml)
mkdir -p "$M/translations/syntax"
cp "$WORKSPACE"/fritzing-app/translations/syntax/*.xml "$M/translations/syntax/"

# Assinatura ad-hoc, obrigatória no Apple Silicon depois de alterar os binários
codesign --force --deep -s - "$APP"
codesign -v --strict "$APP"
```

Observações:

- **macdeployqt:** ele mostra `ERROR: no file at …libpq…`, `…libiodbc…` e `…libmimerapi…`. Essas mensagens vêm dos drivers SQL de PostgreSQL, ODBC e Mimer, que dependem de bibliotecas inexistentes na máquina. Esses drivers são apagados logo em seguida, porque o Fritzing só usa o `libqsqlite` (banco de peças). Sem `-libpath="$QT/lib"`, o `QtCore5Compat` (exigido pela quazip) não entra no bundle.
- **ngspice sem o `spinit`:** o Fritzing carrega sozinho o `analog.cm`, que fica ao lado da dylib (`ngspice_simulator.cpp`). O `spinit`, que fica no prefixo de instalação do ngspice, não vai para o bundle. Sem ele, o ngspice só avisa `Note: can't find the initialization file spinit.` e continua. As peças do Fritzing usam modelos nativos (D, BJT, MOS) e o `ilimit` do `analog.cm`. O simulador foi testado assim, com `$WORKSPACE/ngspice-42` e `~/Qt` renomeados: um multímetro medindo 2 pilhas AA marcou 3.000 V.
- **Peças em `Resources`:** em `Contents/MacOS`, o `codesign` trata o `fritzing-parts/.git` como código aninhado e a assinatura falha (`bundle format unrecognized`). Por isso a pasta fica em `Resources`. O symlink relativo `MacOS/fritzing-parts` é o primeiro lugar onde `FolderUtils::getApplicationSubFolder` procura, e um symlink que aponta para dentro do bundle passa no `codesign -v --strict`.
- **O `.git` das peças (29 MB) é mantido:** o atualizador de peças (`partschecker.cpp`) faz fetch, merge e reset com a libgit2 nessa pasta, e regenerar o `parts.db` exige o repositório. Quando o Fritzing atualiza as peças, ele escreve dentro do bundle e a assinatura ad-hoc deixa de valer (`codesign -v` falha). O app continua abrindo, porque as peças são recursos e não código, e um novo `--install` reassina.
- **Arquivos de `translations/syntax`:** sem eles, o log de inicialização mostra `Unable to open …/translations/syntax/styles.xml` e `QDomDocument::setContent: Failed to open device`.
- **Log de inicialização:** rode `"$M/Fritzing" -debug > fritzing-debug.log 2>&1`. Não passe nenhum argumento depois de `-debug`, porque o Fritzing usa o argumento seguinte como arquivo de saída do log e sobrescreve esse arquivo (por exemplo, um `.fzz`).

### 4.1 Instalando em /Applications (opcional)

```bash
fritzing-app/tools/build_fritzing_mac_arm64.sh --install
```

Depois de montar o app em `_build/release64`, o script:

1. Apaga um `/Applications/Fritzing.app` anterior, mas só se ele tiver sido instalado pelo próprio script. A checagem exige o bundle id `org.fritzing.Fritzing` e o marcador `Contents/Resources/.fritzing-local-build` (ou o symlink `fritzing-parts` das versões anteriores do script). Se houver outro Fritzing lá, o script para sem apagar nada.
2. Copia o app com `ditto` e reassina, conferindo com `codesign -v --strict`.
3. Registra o app no LaunchServices: `lsregister -u` na cópia do `_build` e `lsregister -f` na de `/Applications`. Sem isso, `open -a Fritzing`, o Launchpad e o Spotlight podem abrir a cópia do `_build`. O aviso `failed to scan … -10814` do `-u` aparece quando a cópia do `_build` não estava registrada e é inofensivo.

O script não usa `sudo`. Se a pasta `/Applications` não puder ser gravada pelo usuário, a cópia falha.

O app instalado é autocontido. Para validar:

```bash
codesign -v --strict /Applications/Fritzing.app
# nenhum Mach-O do bundle deve referenciar /Users/ ou ~/Qt
find /Applications/Fritzing.app -type f -print0 | xargs -0 file | grep Mach-O
# todas as libs carregadas devem vir do bundle, de /System ou de /usr/lib
DYLD_PRINT_LIBRARIES=1 /Applications/Fritzing.app/Contents/MacOS/Fritzing 2>&1 | grep -v -e /Applications/Fritzing.app -e /System/ -e /usr/lib/
```

## 5. Limitações conhecidas

- **Só para uso local.** O app gerado roda apenas em arm64 e tem assinatura ad-hoc. Distribuir exigiria assinar com Developer ID e notarizar. Para recompilar, as dependências em `$WORKSPACE` e o `~/Qt` continuam necessários.
- O `tools/deploy_fritzing_mac.sh` original está desatualizado (Qt 5 em `/usr/local`).
- Na primeira execução (`Fritzing -debug`), enquanto o banco de peças é montado, até 5 peças obsoletas referenciadas pelo bin "Core Parts" podem gerar `SQLITE: couldn't insert part … Parameter count mismatch`. Não impedem o uso.
- A `libngspice` guarda o prefixo de instalação (`$WORKSPACE/ngspice-42/bin` e `.../share/ngspice`). Dentro do bundle, esse caminho só é usado para procurar o `spinit`, que é opcional (veja a seção 4).
- O binário do Fritzing contém caminhos do tipo `…/_src/libgit2-1.7.1/src/…`. Eles vêm dos `__FILE__` da `libgit2.a` estática e registram onde ela foi compilada. São usados apenas em mensagens internas e não afetam a execução, então não é preciso recompilar a libgit2 depois de mover o `$WORKSPACE`.

## 6. Docker / cross-compilação

Compilar para macOS a partir de um container Linux é possível na teoria (osxcross + SDK do macOS + Qt host Linux e Qt target macOS), mas é frágil. Além disso, a licença do SDK restringe seu uso a hardware Apple. O próprio `docker/HOWTO.txt` registra que só existem containers para Linux. Para builds automatizados de macOS, o caminho recomendado é um runner macOS (por exemplo, GitHub Actions `macos-14`/`macos-15`).
