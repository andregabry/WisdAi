# Relatório Final de Aceitação — WisdAI Voice Intelligence V2

**Data:** 2026-11-27  
**Branch:** `feature/voice-intelligence-v2` (pronta para Pull Request sem auto-merge em `main`)  
**Status Geral:** Aprovado nos testes automatizados, compilação completa e validação empírica de áudio/LLM local.

---

## 1. Checklist de Conformidade V2

| Requisito | Evidência Verificada | Status |
| :--- | :--- | :---: |
| Estabilidade de sessão e isolamento de turnos/segmentos | `SpeechTranscriber` com `.timeIndexedProgressiveTranscription` + `.processLifetime`, `sessionGenerationID`, `activeTurnGenerationID`, `PlaybackCancellationGate` | **Concluído** |
| Correção definitiva de causa raiz `"Molina"` / `"Comendo"` | Rotação real de segmento STT, ordem correta do tap acústico, referência real de eco + cauda `420 ms` e filtro + limpador de continuidade | **Concluído** |
| Cérebro conversacional intercambiável (`Apple FM` / `llama.cpp` Metal / `MLX`) | `VoiceBrainEngineKind`, servidor loopback `llama-server b12809` com `Qwen3-1.7B-Q4_K_M`, cliente MLX loopback e falha honesta quando ausente | **Concluído** |
| Voz neural local realista sem dependência de API paga | `KokoroNeuralTTSProvider` C ABI (`sherpa-onnx v1.13.8` + `kokoro-int8-multi-lang-v1_0`), 7 amostras WAV reais geradas e auditadas | **Concluído** |
| Honestidade de capacidades, licenças e idiomas | Bloqueio explícito de `pt-PT` no Kokoro (encaminhado para Apple Joana), aviso `CC-BY-NC-4.0` para `F5-TTS`, ausência de sliders falsos de emoção e bloqueio S2S em 8 GB | **Concluído** |
| Configurações → Voz → **Laboratório de Voz** | `VoiceLaboratoryView.swift` com seleção de cérebro/TTS, teste A/B + WAV, perfis de hardware, telemetria, trace 11 estágios (opt-in) e Higiene de Memória | **Concluído** |
| Testes e compilação de release após últimas edições | `run-voice-smoke.sh` (`VOICE_SMOKE_ALL_PASS`), `run-state-smoke.sh` (`PASS`), `run-recovery-smoke.sh` (`PASS`), `FINAL_BINARY_COMPILE_OK` | **Concluído** |

---

## 2. Limitações Conhecidas e Próximos Passos para Teste Humano

1. **Speech-to-Speech nativo (Moshi / MiniCPM-o / PersonaPlex):** permanece desativado (`Incompatível`) no Apple M2 8 GB sem runtime Python/MLX externo e requer máquinas de 16–32+ GB para operação simultânea viável.
2. **`pt-PT` no Kokoro-82M:** Kokoro `kokoro-multi-lang-v1_0` não sintetiza Português Europeu nativo; seleções `pt-PT` são direcionadas transparentemente à voz nativa do macOS (`Joana`).
3. **Validação Interativa com Microfone Real:** a conversa completa por microfone ao vivo em ambiente real (ruído de sala, barge-in falado pelo usuário, aprovação da prosódia final entre `pf_dora`, `pm_alex` e `Apple Natural`) aguarda teste interativo na UI do aplicativo compilado com o usuário.

---

## 3. Como Revisar e Testar

1. Revisar as diferenças entre `feature/voice-intelligence-v2` e `main` no GitHub (Pull Request sem auto-merge).
2. Abrir **Configurações → Voz → Laboratório de Voz** para:
   - Alternar entre `Apple FoundationModels (ANE)` e `Qwen3-1.7B (llama.cpp Metal)`.
   - Ouvir e comparar **Kokoro-82M (`pf_dora` / `pm_alex`)** vs **Apple Voz Natural** na aba **Motores & Voz**.
   - Na aba **Higiene de Memória**, clicar em **Verificar Memória** para revisar os 11 registros antigos detectados e remover apenas os selecionados.
3. Iniciar sessão de voz ao vivo e testar comando paralelo: *"Peça ao Codex para analisar a autenticação do projeto e continue conversando comigo sobre a arquitetura."*
