# Síntese Neural Local e Integração Nativa Kokoro-82M

## 1. Descoberta Crítica de Versão (`sherpa-onnx` v1.13.8 vs v2.0.3)

Durante a auditoria dos cabeçalhos C oficiais do projeto `k2-fsa/sherpa-onnx` (`c-api.h`), identificou-se uma diferença arquitetural determinante:
- A partir da versão **v2.0.0 / v2.0.3**, `sherpa-onnx` **removeu e desativou `data_dir` (`espeak-ng-data`)** na API padrão em razão da separação de licença GPL-3.0, exigindo fonetização externa ou léxicos pré-gerados (existindo apenas léxicos oficiais para `en-us` e `zh`).
- Já a versão **`sherpa-onnx v1.13.8`** (`sherpa-onnx-v1.13.8-osx-arm64-shared-lib.tar.bz2`, `8,773,198` B, SHA-256 `ae77050cdae565496059d96f5ab33d77b397a0864282a4e4a26e3b3b3effb948`) mantém o backend G2P `espeak-ng` completo habilitado via `data_dir`, permitindo **português do Brasil (`pt-br`), inglês (`en-us`) e espanhol (`es`)** diretamente via C ABI.
- Além disso, constatou-se empiricamente na inspeção de `scripts/kokoro/` e na execução real dos pesos que:
  - Os pacotes `v1_1` (`kokoro-multi-lang-v1_1`) correspondem ao conjunto chinês/inglês (`zf_*`, `zm_*`, `af_maple`), sem falantes em português.
  - O conjunto verdadeiro com **54 vozes multilíngues** (incluindo `pf_dora`, `pm_alex`, `pm_santa`) é o **`kokoro-int8-multi-lang-v1_0.tar.bz2`** (`132,353,410` B, Apache-2.0, SHA-256 `72c347230107ef8a31098ec4d468a605244beef5f1ed00db97efa13518800653`) e sua contraparte FP32 `kokoro-multi-lang-v1_0.tar.bz2` (`349,886,476` B, SHA-256 `60703707bc05ccd48d60e1eb723f38b07d6e474795a0b6a588d7220400e0f7a4`).
  - Na chamada C++ (`CallPhonemizeEspeak`), códigos curtos como `"p"` falharam com *"Failed to set eSpeak-ng voice 'p'"*; o código real verificado na árvore `espeak-ng-data/lang/` e validado por síntese WAV é **`"pt-br"`** (`pt-BR`), **`"en-us"`** (`en-US`) e **`"es"`** (`es-ES`).

---

## 2. Contrato C ABI e Execução em Memória (`KokoroNeuralTTSProvider`)

- **Ligação Dinâmica Segura:** `VoiceNeuralRuntime.swift` carrega dinamicamente `libonnxruntime.*.dylib` (`RTLD_NOW | RTLD_GLOBAL`) seguida por `libsherpa-onnx-c-api.dylib` (`RTLD_NOW | RTLD_LOCAL`) exclusivamente do diretório de runtimes autorizado pelo usuário, sem embutir bibliotecas GPL no binário principal nem no DMG do WisdAI.
- **Alinhamento Binário Verificado:** `SherpaOfflineTtsConfigC` (`stride = 448 B`, `kokoro_offset = 128 B`) e `SherpaGenerationConfigC` (`size = 56 B`) foram aferidos com `clang -arch arm64` contra `sherpa-onnx v1.13.8 c-api.h`.
- **Streaming por Cláusulas e Cancelamento Precoce:** o callback C `SherpaOnnxGeneratedAudioProgressCallbackWithArg` encaminha chunks PCM 24 kHz imediatamente ao `AdaptiveJitterBuffer` e retorna `0` assim que `cancelAll()` avança `cancelledEpoch`, abortando a geração C++ em caso de barge-in.

---

## 3. Vozes Kokoro Integradas e Limitações Declaradas com Honestidade

| Preset (`KokoroVoicePreset`) | ID (`sid`) | Idioma (`espeak-ng`) | Uso no WisdAI |
| :--- | :---: | :--- | :--- |
| `pf_dora` | `42` | `pt-br` (Português Brasil) | **Aurora / Aria** (Feminina padrão PT-BR) |
| `pm_alex` | `43` | `pt-br` (Português Brasil) | **Atlas** (Masculina padrão PT-BR; preferida sobre `pm_santa` após auditoria auditiva) |
| `pm_santa` | `44` | `pt-br` (Português Brasil) | Opção alternativa grave masculina PT-BR |
| `af_heart`, `af_bella`, `af_nova`, `am_fenrir`, `am_michael` | `3, 2, 7, 14, 16` | `en-us` | Vozes femininas e masculinas EN-US |
| `ef_dora`, `em_alex`, `em_santa` | `28, 29, 53` | `es` | Vozes femininas e masculinas ES |

- **Restrição Explícita para `pt-PT`:** Kokoro-82M **não suporta Português Europeu (`pt-PT`) nativo**. Quando o idioma selecionado é `.portuguesePT`, `KokoroNeuralTTSProvider.resolvePreset` retorna `nil`, o Laboratório de Voz exibe aviso explícito e o orquestrador direciona honestamente para `Apple Voz Natural (Joana pt-PT)`.
- **Controles Sem Mentira de UI:** `VoiceTTSEngineKind.kokoro82M.supportsExplicitEmotionSlider == false`; a interface não exibe sliders falsos de "emoção contínua" que o modelo não possui, expondo apenas controle real de velocidade (`0.75×` a `1.30×`) e seleção de voz/idioma.

---

## 4. Comparativo Honesto com Alternativas Avaliadas

| Motor | Status no WisdAI V2 | Razão Técnica / Jurídica |
| :--- | :--- | :--- |
| **Kokoro-82M INT8 (ONNX via `sherpa-onnx`)** | **Operacional Nativo (Opt-In)** | 126 MB compactado, carga em ~612–667 ms, PT-BR fluido superior às vozes nativas compactas do macOS. |
| **Apple Voz Natural (`AVSpeechSynthesizer.write`)** | **Operacional Integrado ($0)** | Latência curtíssima (`99.1 ms` P50 em cláusula curta), zero download e suporte nativo `pt-PT`, porém timbre metálico na Luciana/Joana compactas. |
| **CosyVoice2-0.5B** | Catálogo Técnico (`Incompatível` sem Python) | Alta expressividade, porém exige ambiente Python/PyTorch/FunASR externo (~2.1 GB+). |
| **Chatterbox (MIT)** | Catálogo Técnico (`Incompatível` em 8 GB) | Pesos ~13.2 GB e inferência PyTorch incompatíveis com Apple Silicon 8 GB. |
| **Sesame CSM-1B** | Catálogo Técnico (`Incompatível` em 8 GB) | ~18.6 GB, apenas inglês, foco em GPU dedicada / >= 24 GB RAM. |
| **F5-TTS** | **Bloqueado para Distribuição Comercial** | Licença **`CC-BY-NC-4.0`** incompatível com uso comercial; marcada explicitamente com alerta laranja no catálogo. |
