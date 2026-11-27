# Guia de Compilação e Execução do WisdAI para Windows

Este documento descreve a arquitetura, instruções de compilação, execução e empacotamento do **WisdAI Desktop** para o sistema operacional Windows (x64 e ARM64).

---

## 1. Visão Geral da Arquitetura

O WisdAI no Windows é composto por duas camadas principais:

1. **Motor de Execução (Backend Rust / Codex)**:
   - Fornece o `codex.exe app-server` (servidor JSON-RPC via stdio), gerenciamento de threads, rollback de arquivos, sandbox e execução de ferramentas.
   - Fornece o helper `codex-code-mode-host.exe` para execução local de código.
   - Integração com múltiplos provedores de IA (OpenAI, Gemini via `agy`, Claude via `claude`, DeepSeek e NVIDIA).

2. **Interface Gráfica (Frontend Desktop Windows)**:
   - Localizada em `codex/desktop/windows/`.
   - Desenvolvida com Electron + HTML5/CSS3 moderno com foco em **100% de paridade visual com a interface ChatGPT**.
   - Conecta-se diretamente ao `codex.exe app-server` e armazena credenciais e histórico localmente em `%APPDATA%\WisdAI`.

---

## 2. Artefatos Pré-Compilados Disponíveis

Os pacotes executáveis para Windows x64 estão gerados e disponíveis em `dist/windows/`:

1. **Executável Portátil Direto (Single-File .exe)**:
   - [WisdAI-0.7.1-portable.exe](file:///Users/andregabry/Project/WisdAI/dist/windows/WisdAI-0.7.1-portable.exe) (73 MB)
   - Checksum SHA-256: `dist/windows/WisdAI-0.7.1-portable.exe.sha256`
   - *Basta dar duplo-clique no arquivo `.exe` para iniciar o WisdAI no Windows imediatamente.*

2. **Pacote Completo Descompactável (Zip)**:
   - [WisdAI-Desktop-0.7.1-windows-x64.zip](file:///Users/andregabry/Project/WisdAI/dist/windows/WisdAI-Desktop-0.7.1-windows-x64.zip) (108 MB)
   - Checksum SHA-256: `dist/windows/WisdAI-Desktop-0.7.1-windows-x64.zip.sha256`

3. **Agente CLI para Terminal (Command Prompt / PowerShell)**:
   - Localizado em [dist/windows/bin/](file:///Users/andregabry/Project/WisdAI/dist/windows/bin)
   - Execute `wisdai.cmd` no cmd ou PowerShell para iniciar o agente em modo terminal.

---

## 3. Como Compilar no Windows (Nativo)

### Pré-requisitos
1. **Windows 10 ou 11 (64-bit)**
2. **Node.js v20+** com npm (baixe em [nodejs.org](https://nodejs.org))
3. **Rust e Cargo** (instale via [rustup.rs](https://rustup.rs) com o target `x86_64-pc-windows-msvc`)
4. **Visual Studio C++ Build Tools** (necessário para compilar o Rust no Windows)

### Passo a Passo Rápido

Você pode compilar com um único comando usando os scripts automatizados:

#### Opção A: Via Prompt de Comando (CMD)
```cmd
cd codex\desktop\windows
build-windows.bat
```

#### Opção B: Via PowerShell
```powershell
cd codex\desktop\windows
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\build-windows.ps1
```

O script irá:
1. Compilar o motor Rust `codex.exe` e `codex-code-mode-host.exe`.
2. Instalar as dependências do aplicativo desktop.
3. Empacotar o executável do WisdAI e os instaladores (NSIS Installer e Portable).
4. Copiar os arquivos gerados para a pasta `dist\windows\`.

---

## 4. Compilação Automatizada via CI/CD (GitHub Actions)

O repositório inclui a workflow configurada em:
`.github/workflows/wisdai-desktop-windows.yml`

Toda vez que uma alteração é enviada para a branch `main` ou o workflow é disparado manualmente:
1. O GitHub Actions inicia uma máquina virtual Windows (`windows-latest`).
2. Compila os binários Rust nativos MSVC.
3. Empacota o cliente desktop com `electron-builder`.
4. Disponibiliza o instalador `WisdAI-Setup-0.7.1-x64.exe` para download na aba **Actions**.

---

## 5. Estrutura de Arquivos do Windows Desktop

```
codex/desktop/windows/
├── assets/
│   ├── icon.ico          # Ícone nativo do Windows (multi-resolução)
│   ├── icon.png          # Ícone em alta resolução
│   └── BrandLogo.png     # Logotipo oficial WisdAI
├── src/
│   ├── main/
│   │   ├── index.js      # Processo principal Electron (janela frameless, ciclo de vida)
│   │   ├── engine.js     # Gerenciador de conexão com o motor codex.exe e provedores
│   │   └── preload.js    # ContextBridge seguro para comunicação IPC
│   └── renderer/
│       ├── index.html    # Layout completo estilo ChatGPT
│       ├── styles.css    # Estilos escuro/claro, botões, responsividade
│       └── app.js        # Lógica de chat, histórico, streaming, configurações e espaço
├── build-windows.bat     # Script de compilação em lote para Windows
├── build-windows.ps1     # Script de compilação PowerShell
├── installer/
│   └── WisdAI.iss        # Script do Inno Setup para instalador executável
└── package.json          # Metadados do projeto e scripts npm
```
