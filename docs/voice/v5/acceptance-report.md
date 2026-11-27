# WisdAI V5 — Relatório Final de Aceitação Técnica & Validação

**Branch:** `feature/voice-identity-jarvis-v5`  
**Escopo validado:** Correção definitiva P0 de seleção de voz + Motor `Supertonic-3` (44.1 kHz Flow Matching) + Identidade Executiva Masculina **JARVIS** + Voice Design Engine + Reestruturação do Laboratório de Voz.

---

## 1. Critérios de Aceitação Verificados

| Critério | Evidência Direta Observada | Status |
| :--- | :--- | :--- |
| **P0 — Fonte Única de Verdade (`VoiceIdentityManager`)** | Migração automática de chaves conflitantes (`wisdcode.voice.gender` × `wisdai.voice.kokoroPreset`), sincronização bidirecional entre Settings, Popover, Voice HUD e Voice Laboratory sem ciclo reentrante; chave unificada `wisdai.voice.unifiedConfig.v5`. | Aprovado |
| **P0 — Troca Real entre Voz Feminina e Masculina** | Medição acústica F0 direta nos buffers PCM gerados pelo runtime: Kokoro `pf_dora = 173.9 Hz` vs. `pm_alex = 130.4 Hz` e `bm_george = 139.5 Hz`; Supertonic-3 `M2 = 90.0 Hz` e `M4 = 117.9 Hz` vs. `F1 = 185.3 Hz`. | Aprovado |
| **P0 — Fallback Apple Natural Honesto** | Seleção masculina em `AppleNatural` não aceita silenciosamente voz feminina (`Sandra`/`Luciana`) quando solicitado perfil masculino; `en-GB` seleciona `Daniel`; diagnóstico explícito quando não há voz PT-BR masculina instalada no macOS. | Aprovado |
| **P0 — Isolamento de Cache & Troca ao Vivo** | Diretórios legados sem prefixo `v5_` expurgados uma única vez; novos caches isolados por hash de 8 campos; troca em sessão limpa apenas playback com `bargeInFlushPlayback()` sem reiniciar `AVAudioEngine` (0 ocorrências de CoreAudio `-10875` em 32 ciclos VPIO + troca de rota). | Aprovado |
| **P1 — Novo Motor Neural Embarcado (`Supertonic-3 INT8`)** | Modelo `sherpa-onnx-supertonic-3-tts-int8-2026-05-11` (`122.8 MB`, SHA-256 verificado) operacional em `libsherpa-onnx-c-api.dylib v1.13.8`, nativo arm64, `44.1 kHz`, Flow Matching `num_steps = 4...12`, `RTF = 0.199` (smoke) / `0.23–0.28` (`num_steps=10`). | Aprovado |
| **P1 — Identidade JARVIS & Idioma `en-GB`** | Persona `.jarvis` e estilo `.jarvisExecutive` integrados no cérebro (`qwen3-1.7b`), `ConversationalBehaviorPlanner` e pronúncia técnica; inglês britânico funcional tanto no Supertonic (`en`) quanto no Kokoro (`en-GB-x-rp`). | Aprovado |
| **P1 — Amostras Comparativas & Aprovação Aberta** | 22 arquivos WAV gerados pelo runtime real (3 candidatos JARVIS principais × 5 categorias PT-BR + variações M5/`en-GB` + controles) em `voice_samples_v5/`. Escolha estética final permanece aberta ao utilizador. | Aprovado (aguardando escuta do utilizador) |
| **P2 — Documentação Completa V5** | 11 documentos publicados em `docs/voice/v5/`. | Aprovado |

---

## 2. Resultados das Suítes Executadas Pós-Edição Final

Executadas integralmente após a última edição em código Swift (`VoiceBehaviorEngine.swift` + `VoiceNeuralRuntime.swift`):

1. **`bash codex/desktop/macos/tests/run-voice-smoke.sh`** — exit `0` (`VOICE_SMOKE_ALL_PASS`):
   - Todas as verificações V1–V5 aprovadas, incluindo:
     - `PASS: Real Kokoro-82M neural synthesis (load=567ms, ptBR=3033ms/117129@24kHz, en=3083ms, es=2747ms)`
     - `PASS: Real llama.cpp Metal + Qwen3-1.7B inference (load=6600ms, TTFT=105ms, total=736ms, replyChars=142)`
     - `PASS: Kokoro Acoustic Differentiation pf_dora=173.9Hz vs pm_alex=130.4Hz | EN-GB bm_george=139.5Hz`
     - `PASS: Supertonic-3 Flow Matching 44.1kHz (RTF=0.199 | M2=90.0Hz M4=117.9Hz vs F1=185.3Hz)`
     - `PASS: V5 Unified VoiceIdentityManager, Live Controller Bridge, Supertonic-3 & JARVIS Male Verification`
     - `PASS: Native AudioEngine 32-cycle VPIO, concurrency serialization, split-engine Continuity & route switch regression`
2. **`bash codex/desktop/macos/tests/run-state-smoke.sh`** — exit `0`:
   - `PASS: project edits/removal preserve files; ... Codex-style Mulher/Homem voice assistant & prosody verified; ... natural voice greeting + fast conversational routing verified`
3. **`bash codex/desktop/macos/tests/run-recovery-smoke.sh`** — exit `0`:
   - `PASS: strict limits; model/account fallback; same-thread context; ... restart and ephemeral privacy`

---

## 3. Verificação Auditiva & Pendências para Fechamento Humano

- **Validado por escuta direta:** regeneração das amostras `04` confirmou eliminação da soletração de `"hmm"` (`"agá eme eme"`) no Kokoro e eliminação do gaguejo em reticências no Supertonic.
- **Limitações honestas documentadas:**
  - `pt-PT` neural idiomático nativo segue ausente no Kokoro-82M (`en`/`pt-br`/`es`); para `pt-PT` o WisdAI usa `Supertonic-3` (`pt`, sotaque mais próximo porém compartilhado com `pt`) ou `Apple Natural` (`Joana`) com aviso transparente.
  - Motores baseados em PyTorch/MLX/Qwen3-TTS exigem Python ≥ 3.10 externo (`127.0.0.1`) porque este host possui Apple Python `3.9.6` e `8 GB` de RAM compartilhada.
- **Próximo passo humano:** audição comparativa dos candidatos **A (`supertonic:m2`)**, **B (`supertonic:m4`)** e **C (`kokoro pm_alex` / `bm_george`)** pelo utilizador para definição oficial da voz padrão do JARVIS antes de qualquer merge na `main`.
