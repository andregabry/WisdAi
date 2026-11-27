# WisdAI Desktop para Windows

Este subdiretório contém o cliente desktop nativo do **WisdAI** para o Microsoft Windows.

## Estrutura

- `src/main/`: Processo principal (Electron, controle de janela, spawn do motor `codex.exe`).
- `src/renderer/`: Interface do usuário com paridade visual com o ChatGPT, suporte a temas Claro e Escuro, streaming de respostas, catálogo de modelos e espaço de trabalho.
- `assets/`: Ícones e imagens de marca (`icon.ico`, `BrandLogo.png`).
- `build-windows.bat` & `build-windows.ps1`: Scripts de compilação em um clique para Windows.
- `installer/WisdAI.iss`: Script de criação de instalador com Inno Setup.

## Comandos Rápidos

```bash
# Modo desenvolvimento
npm start

# Gerar executável para Windows (pasta descompactada)
npm run pack:win

# Gerar instalador executável (.exe / NSIS)
npm run dist:win
```
