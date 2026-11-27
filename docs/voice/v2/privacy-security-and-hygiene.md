# Privacidade, Segurança e Higiene Estrutural de Memória

## 1. Controles de Privacidade e Rede Local (`VoicePolicyPreferences` & Loopback)

- **Privacidade Padrão Estrita:** `allowPaidVoiceAPIs = false`, `externalAudioConsentGranted = false`, `preferOnDeviceSpeechOnly = true`, `allowPersistentVoiceMemory = false`, `storeRawAudioRecordings = false` (`VoiceGateway.swift`).
- **Isolamento Loopback:** `LocalLlamaServerBrainRuntime` vincula `--host 127.0.0.1` em porta efêmera obtida via `socket/bind(0)/getsockname` e `LocalMLXClientRuntime` restringe consultas exclusivamente ao endereço `127.0.0.1:<porta>`.
- **Armazenamento de Chaves:** chaves opcionais de provedores externos (`Deepgram`, `ElevenLabs`) ficam protegidas exclusivamente no macOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), jamais em logs ou JSON em texto claro.
- **Logs Sanitizados:** `VoiceLogRedactor.redact(...)` mascara tokens e credenciais antes de salvar eventos em memória ou exportar relatórios (`exportSanitizedDiagnosticsReport()`).

---

## 2. Consentimento e Integridade de Artefatos (`VoiceModelAssetManager`)

- **Bloqueio de Download Automático:** nenhum binário ou peso (> 50 MB ou runtime) é baixado sem ação explícita do usuário (`requestDownloadConsent` → `.awaitingConsent` → `confirmAndStartAuthorizedDownload`).
- **Verificação Criptográfica SHA-256:** após o download em arquivo temporário, `CryptoKit.SHA256` calcula o hash completo em blocos de 1 MB antes da extração (`/usr/bin/tar`) para `~/Library/Application Support/WisdAI/Voice/{Runtimes,Models}/`. Divergências abortam e removem o arquivo temporário.
- **Alertas de Licença:** `f5-tts-noncommercial` destaca obrigatoriamente a restrição `CC-BY-NC-4.0`.

---

## 3. Quarentena FTS5 e Higiene Estrutural de Deriva ASR (`VoiceMemoryAndTelemetry.swift`)

- **Proteção contra Prompt Injection no FTS5:** registros externos/não confiáveis marcados como `.untrusted` ficam em quarentena no `voice_knowledge_fts.sqlite` e são filtrados fora de `searchRecallableFacts`.
- **Higiene Estrutural sem Listas de Palavras Hardcoded:** `VoiceMemoryHygieneAnalyzer` identifica anomalias puramente por estrutura linguística/comportamental:
  1. Prefixos repetidos crescentes entre turnos consecutivos (`detectContaminatedIndices`, ex.: `"Molina"` → `"Molina. Comendo"` → `"Molina. Comendo."`).
  2. Reemissões idênticas ou com pontuação residual de ASR.
  3. Fragmentos sem alfanuméricos ou curtos em sequência repetitiva.
- **Resultado da Auditoria no Host (Somente Leitura):** ao escanear os arquivos reais deste usuário, `VoiceMemoryHygieneAnalyzer.scan` detectou **`11` registros contaminados** em `~/.codex/realtime-voice-continuity.json` (incluindo as duplicatas ASR e a cadeia `"Molina" / "Molina. Comendo"`), preservando **100% do histórico legítimo** para revisão manual no **Laboratório de Voz** (nenhuma exclusão silenciosa foi aplicada).
- **Trace 11 Estágios Opt-In:** `enablePipelineDiagnosticsTrace` inicia sempre em `false` e descarta todos os eventos da memória ao ser desligado.
