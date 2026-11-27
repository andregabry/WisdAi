# WisdAI V5 — Causa Raiz Crítica da Seleção de Voz Quebrada

**Prioridade:** P0 (Resolvido em `feature/voice-identity-jarvis-v5`)  
**Sintoma reportado:** Ao selecionar voz masculina (ou qualquer outra voz) nas configurações do app, o assistente continuava reproduzindo exclusivamente uma voz feminina em todas as sessões conversacionais.

---

## 1. Diagnóstico Empírico na Máquina do Utilizador (`UserDefaults` antes da V5)

A inspeção direta de `defaults read local.wisdai.desktop` comprovou a divisão de estado entre dois subsistemas desconectados:

| Domínio | Chave persistida | Valor real observado antes da V5 | Efeito |
| :--- | :--- | :--- | :--- |
| Legado (`VoiceController`) | `wisdcode.voice.gender` | `"male"` | Usuário clicou em **Homem** na interface |
| Legado (`VoiceController`) | `wisdcode.voice.codexVoice` | `"cedar"` | Usuário escolheu timbre masculino Codex |
| Legado (`VoiceController`) | `wisdcode.voice.identifier` | `"auto"` | Sem identificador Apple explícito |
| Orquestrador V2/V3 | `wisdai.voice.kokoroPreset` | `"pf_dora"` | **Preset feminino** mantido ativo em disco |
| Orquestrador V2/V3 | `wisdai.voice.identity.v1` | *(ausente)* | Caía para `VoiceIdentityDescriptor.wisdAIDefault` = **`.aurora` (feminina)** |

Mesmo com o usuário tendo explicitamente selecionado `male` / `cedar`, a sessão conversacional lia exclusivamente `wisdai.voice.identity.v1` e `wisdai.voice.kokoroPreset`, reproduzindo `pf_dora` em 100% dos turnos.

---

## 2. Os 5 Pontos de Falha Identificados no Código

### Falha 1 — Dois mundos de estado sem ponte (`DesktopSettings.swift`, `DesktopShell.swift`, `DesktopVoice.swift`)
- [`DesktopSettings.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/DesktopSettings.swift): `VoiceGenderCard` e `VoiceSelectorPopoverView` alteravam somente `voice.voiceGender` e `voice.selectedCodexVoiceID` em `VoiceController`, sem atualizar `orchestrator.voiceIdentity` nem `orchestrator.selectedKokoroPreset`.
- [`DesktopShell.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/DesktopShell.swift): o menu de contexto de voz e o popover do chat também mutavam apenas `workspace.voice.voiceGender`.
- [`DesktopVoice.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/DesktopVoice.swift): `startConversationalChatMode(...)` encaminhava apenas `selectedVoiceID` (que era `"auto"`), ignorando `voiceGender` e `selectedCodexVoiceID`.

### Falha 2 — Prévia e conversa usavam motores e vozes diferentes
- [`DesktopVoice.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/DesktopVoice.swift): `previewVoice()` ("Testar voz") e `startLocalNaturalSpeech(...)` ("Ouvir resposta") chamavam `AVSpeechSynthesizer` legado no `VoiceController`, enquanto a conversa por voz rodava `WisdVoiceOrchestrator` via `KokoroNeuralTTSProvider`.

### Falha 3 — Sobrescrita silenciosa & dessincronia memória vs. disco (`VoiceOrchestrator.swift`)
- Alterar `voiceIdentity` resetava `hasExplicitKokoroPresetOverride = false` e atualizava `selectedKokoroPreset` dentro de `isSyncingKokoroFromPersona = true`, **pulando a persistência** de `wisdai.voice.kokoroPreset` em `UserDefaults` (`pf_dora` ficava congelado em disco).
- `prewarmVocalizationCache()` e o fallback `appleTTS` em `runTTSQueue()` passavam `"persona:\(voiceIdentity.persona.rawValue)"`, ignorando qualquer preset explícito.

### Falha 4 — Fallback Apple TTS forçava voz feminina em PT-BR (`VoiceGateway.swift`)
- Em [`AppleNaturalPCMStreamingTTSProvider.selectBestNaturalVoice`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceGateway.swift): `wantsMale` checava literalmente apenas `preferredIdentifier == "persona:atlas"`. Passar `"pm_alex"`, `"pm_santa"` ou `"auto"` resultava em `wantsMale == false`, selecionando `com.apple.siri.natural.Sandra` (feminina).
- Além disso, a auditoria de `AVSpeechSynthesisVoice.speechVoices()` neste macOS mostrou que a única voz PT-BR não-Eloquence pré-instalada é `com.apple.voice.compact.pt-BR.Luciana` (feminina), sem voz Siri/Enhanced masculina instalada no sistema.

### Falha 5 — Kokoro Britânico (`en-GB`) falhava por código eSpeak case-sensitive + cache sub-isolada
- Passar `"en-gb"` em [`KokoroNeuralTTSProvider`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceNeuralRuntime.swift) falhava em `espeak-ng-data` com `Failed to set eSpeak-ng voice 'en-gb'`, exigindo o identificador real `en-GB-x-rp` + `lexicon-gb-en.txt`.
- [`VocalizationIdentityContext`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceVocalizationCache.swift) não incluía `modelID`, `modelVersion`, `identityID`, `speakerID`, `speechRate` e `prosodySignature`.

---

## 3. Fluxo Unificado após a Correção (V5)

```
Qualquer Controle de UI (Ajustes, Popover, ContextMenu, HUD, Voice Laboratory)
        │
        ▼
VoiceIdentityManager (Fonte Única de Verdade · wisdai.voice.unifiedConfig.v5)
   ├─ Sincroniza bi-direcionalmente VoiceController & WisdVoiceOrchestrator
   ├─ Emite RequestedSnapshot ──▶ ConfiguredSnapshot (SID C exato + Modelo + Idioma)
   ├─ Dispara troca de voz ao vivo SEM parar AVAudioEngine (zero risco -10875)
   ├─ Invalida VocalizationCacheEngine (assinatura SHA-256 v5|...|r...|prosody)
   └─ Execução TTS real (Supertonic-3 / Kokoro-82M / Apple) ──▶ InferredSnapshot (F0 Hz real + SID + alerta se divergir)
```
