# Matriz de Licenciamento e Conformidade Legal

Todas as dependências Python do ambiente gerenciado em `~/Library/Application Support/WisdAI/OpenJarvis/venv` foram inspecionadas diretamente via `importlib.metadata`, além da verificação dos modelos neurais e repositórios de referência.

## 1. Repositórios de Referência Avaliados

| Origem | Commit auditado | Licença | Uso no WisdAI | Parecer de conformidade |
| --- | --- | --- | --- | --- |
| `open-jarvis/OpenJarvis` | `8b07c88e26e401ac00d2db558a069d604c4f0477` | `Apache-2.0` | **Adotado e empacotado** em `OpenJarvisRuntime/src/openjarvis` + `prompts/` | Compatível com distribuição comercial; texto integral incluído em `LICENSE-OPENJARVIS.txt` e referenciado em `codex/NOTICE`. |
| `lancejames221b/openjarvis` | `4582aacd2a31c08917f6c9eee249d9d65117d93f` | `MIT` | **Não adotado em runtime** (arquitetura Discord/CUDA Linux) | Apenas referência documental; zero código copiado em produção. |
| `huggingface.co/jgkawell/jarvis` | `37f8763122312665f091d1fc760abaf1f79b02cc` | Card declara `mit`; base VITS Piper `en-gb-x-rp` | **Não empacotado nem adotado como voz padrão** | Sem dataset declarado no model card, acoplamento típico a `piper-tts` (`GPL-3.0-or-later`), inadequado para PT-BR (pronúncia inglesa) e potencial semelhança de identidade cinematográfica. Substituído por vozes limpas próprias/permissivas (`Supertonic-3 M4/M5` e `Kokoro bm_george`). |

## 2. Exclusão Estrita de Bloat e Dependências Copyleft (`GPL`/`LGPL`)

O manifesto [requirements-clean.txt](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/OpenJarvisRuntime/requirements-clean.txt) exclui intencionalmente extras opcionais `[voice]`/`[telegram]` do upstream que puxariam pacotes copyleft ou bloat de RAM incompatível com Apple M2 8 GB:

- **Excluídos do runtime:** `piper-tts` (`GPL-3.0-or-later`), `phonemizer-fork` (`GPL-3.0`), `python-telegram-bot` (`LGPL-3.0-only`), `torch`/`PyTorch` (`~595 MB` + pico de `~1 GB RSS`) e `kokoro==0.9.4` baseado em `espeakng-loader`.
- **Fronteira nativa do `sherpa-onnx`:** a síntese Kokoro usa `libsherpa-onnx-c-api.dylib` (`Apache-2.0`) em modo C-ABI isolado (processo/chamada de síntese) sem nenhuma biblioteca Python GPL carregada pelo `OpenJarvisRuntime`.

## 3. Inventário Completo Verificado no Ambiente `venv` (`66` pacotes)

Distribuições inspecionadas no `venv` instalado (100% em licenças permissivas OSI):

- **Apache-2.0:** `aiohttp` (`Apache-2.0 AND MIT`), `aiosignal`, `flatbuffers`, `frozenlist`, `hf-xet`, `huggingface_hub`, `multidict`, `openai`, `opentelemetry-api`, `packaging` (`Apache-2.0 OR BSD-2-Clause`), `propcache`, `python-multipart`, `requests`, `sniffio` (`MIT OR Apache-2.0`), `tokenizers`, `tzdata`, `wisdai-openjarvis-runtime`, `yarl`.
- **MIT / MIT-0:** `annotated-doc`, `annotated-types`, `anyio`, `attrs`, `cffi` (`MIT-0`), `charset-normalizer`, `croniter`, `ctranslate2`, `fastapi`, `faster-whisper`, `filelock`, `h11`, `jiter`, `markdown-it-py`, `mdurl`, `onnxruntime`, `pydantic`, `pydantic_core`, `PyYAML`, `rich`, `tomlkit`, `truststore`, `typing-inspection`, `urllib3`.
- **BSD-2-Clause / BSD-3-Clause:** `av`, `click`, `fsspec`, `httpcore`, `httpcore2`, `httpx`, `httpx2`, `idna`, `numpy` (`BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0`), `protobuf`, `psutil`, `pycparser`, `Pygments` (`BSD-2-Clause`), `python-dateutil`, `soundfile`, `starlette`, `uvicorn`, `websockets`.
- **PSF-2.0 / MPL-2.0:** `aiohappyeyeballs` (`PSF-2.0`), `typing_extensions` (`PSF-2.0`), `certifi` (`MPL-2.0`), `tqdm` (`MPL-2.0 AND MIT`).

**Total de pacotes GPL / LGPL / AGPL instalados:** **`0`**.

## 4. Modelos Neurais e Atribuição no App

- **Qwen3-1.7B-Q4_K_M** (`Apache-2.0`) executado sobre `llama.cpp` Metal (`MIT`).
- **Supertonic-3 ONNX** (`MIT`, `44,1 kHz`) e **Kokoro-82M int8 ONNX** (`Apache-2.0`, `24 kHz`) via `sherpa-onnx` (`Apache-2.0`) e `onnxruntime` (`MIT`).
- **Faster-Whisper `base` int8** (`MIT`) via `ctranslate2` (`MIT`).
- As atribuições e avisos legais estão consolidadas em [codex/NOTICE](file:///Users/andregabry/Project/WisdAI/codex/NOTICE) e [LICENSE-OPENJARVIS.txt](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/OpenJarvisRuntime/LICENSE-OPENJARVIS.txt), ambas copiadas para `WisdAI.app/Contents/Resources/` em [build-dmg.sh](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/build-dmg.sh).
