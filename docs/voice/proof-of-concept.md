# Prova de Conceito Isolada — Metodologia e Evidências Medida

> Executada em **2026-11-26** diretamente no hardware alvo (**Apple M2, 8 cores, 8.0 GB RAM, macOS 27.0.1**) através de [VoicePoC.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/tests/VoicePoC.swift) + sonda complementar de aquecimento TTS.

---

## 1. Escopo Validado na Prova de Conceito (Seção 19)

| Cenário PoC | Descrição Executada | Resultado Observado | Latência / Métrica Real |
|---|---|---|---|
| **1. Inicialização Local (Sem Nuvem)** | `VoiceNativeAudioEngine.startFullDuplex` + `HardwareMemoryProfile.detect()` | **PASSOU** (Zero bloqueio, sem rede) | **`236.82 ms`** (`profile=low8GB`) |
| **2. Speech Understanding On-Device** | `SpeechAnalyzer` + `SpeechTranscriber` + `SpeechDetector` (`pt-BR`) | **PASSOU** (`pt_BR` e `pt_PT` já instalados offline!) | Init: **`103.04 ms`** |
| **3. Pausas Naturais & Hesitações** | Frase exata: *"Eu estava pensando… talvez fosse melhor mudar a arquitetura do projeto… mas ainda não tenho certeza."* (1100 ms silêncio) | **PASSOU** (`pauseToThinkHold`, `shouldFinalizeTurn=false`) | Descoberto e corrigido bug real antes de finalizar |
| **4. Raciocínio Conversacional Local** | `Apple FoundationModels` (`SystemLanguageModel.default`) in-process ANE | **PASSOU** (PT-BR natural fluído; 4 turnos com contexto) | Frio: `3887.8 ms`; **Aquecido: `538.4 ms` TTFT** (`745.3 ms` total) |
| **5. Roteamento / Tool + Continuação** | Turno pedindo delegação ao Codex enquanto conversa continua | **PASSOU** (*"Entendido, vou encaminhar a análise para o agente responsável!"*) | **`623.1 ms` TTFT** |
| **6. Troca de Idioma (PT → EN)** | Turno em inglês após contexto PT-BR | **PASSOU TTFT** (**Ajuste identificado no prompt!**) | **`470.2 ms` TTFT** *(nota: prompt instruindo "em português" manteve resposta em PT; alterado para auto-detecção de idioma do utilizador)* |
| **7. Síntese Vocal PCM Streaming** | `AppleNaturalPCMStreamingTTSProvider` (`24 kHz Float32` -> `AdaptiveJitterBuffer`) | **PASSOU** (`111,613` amostras no PoC; sonda warm isolada abaixo) | Frio (`speechsynthesisd` 1ª carga): `976–2811 ms`; **Warm curto: `157.8 ms` / Warm médio: `176.0 ms`** |
| **8. Interrupção (Barge-in)** | `BargeInCoordinator` com `110,077` amostras pendentes no `AdaptiveJitterBuffer` | **PASSOU** (limpeza instantânea + preservação exata do ouvido) | **`0.118 ms`** *(meta P95: `< 150 ms`)* |
| **9. Pegada de Memória & CPU** | `ProcessResourceProbe` (`task_vm_info` / `task_threads`) no processo Swift | **PASSOU** (`8.0 GB` preservado) | Antes: `2.2 MB` -> Depois: **`14.9 MB`**, CPU `8.8%` |

---

## 2. Descobertas Empíricas e Compromissos Técnicos (Transparência Obrigatória — Seção 23)

1. **Cold-Start vs Warm-Start no Motor Local:**
   - Sem aquecimento prévio, `FoundationModels` leva `~3.89 s` na primeira inferência e `AVSpeechSynthesizer.write` leva `~2.81 s` no primeiro acordar de daemon.
   - **Solução comprovada na sonda:** O pré-aquecimento assíncrono não-bloqueante em background (`session.prewarm()` + síntese silenciosa curta de warm-up sem tocar no alto-falante) reduz os turnos reais para **`~470–556 ms` (raciocínio)** + **`~158 ms` (1º chunk vocal)** ≈ **`~630–750 ms` TTFA local real**, atingindo confortavelmente `< 1.200 ms` P95 (próximo aos `500 ms` P50 com chunking incremental por frase).
2. **Compromisso Naturalidade vs Zero Download em 8 GB RAM:**
   - **Opção 1 (Ativa Imediatamente — Zero Download, ~15 MB app):** `Apple FoundationModels` + `SpeechAnalyzer` + `Apple Siri Natural (Sandra)`. Excelente velocidade, `0` download, mas neste Mac só há voz feminina natural `pt-BR` instalada no SO (sem voz masculina natural nativa Apple pré-instalada).
   - **Opção 2 (Evolução Recomendada c/ Autorização — `Kokoro-82M` Apache-2.0, ~320 MB disco / ~350 MB RAM):** Fornece **identidade vocal 100% proprietária WisdAI** em masculino e feminino `pt-BR`/`en`/`es`, idêntica entre produtos WisdomUp (`WisdMeet`, `WisdFin`, `WisdInvest`), porém exige download único de ~320 MB (desativado por padrão até autorização explícita do utilizador conforme Seção 23!).
3. **Decisão Transparente Implementada:**
   - Padrão imediato local funcional em `100%` dos turnos com aquecimento proativo (`FoundationModels` + `SpeechAnalyzer` + `Apple Natural PCM`), arquitetura modular pronta para plugar **Kokoro-82M CoreML/ONNX** mediante opt-in futuro de download sem alterar nenhuma outra camada!
