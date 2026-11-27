# Naturalidade Conversacional, Adaptação Oral e Identidade Vocal WisdAI

## 1. Identidade Própria WisdAI (Desacoplada dos Agentes de Código)

A identidade vocal pertence ao ecossistema WisdAI e permanece invariante independentemente de estar conectada a Codex, Claude, Gemini ou operando 100% off-line (`VoiceIdentityDescriptor` em `VoiceIdentityProfile.swift`):
- **Aurora (`pf_dora`, PT-BR Feminina · cadência `1.00×`):** timbre padrão acolhedor, natural e direto.
- **Atlas (`pm_alex`, PT-BR Masculina · cadência `0.96×`):** voz masculina equilibrada e firme; alterada de `pm_santa` para `pm_alex` após inspeção auditiva real das amostras WAV comprovar naturalidade superior em `pm_alex`.
- **Aria (`pf_dora`, PT-BR Dinâmica · cadência `1.07×`):** perfil para brainstorming ágil.

No `VoiceOrchestrator.swift`, a sincronização entre `voiceIdentity.persona` e `selectedKokoroPreset` foi tratada via `hasExplicitKokoroPresetOverride` / `isSyncingKokoroFromPersona`, assegurando que trocas de persona atualizem automaticamente o preset vocal mantendo `effectiveTTSVoicePreference() == "persona:\(persona)"` quando não há override manual de locutor.

---

## 2. Adaptação Oral e Pronúncia Multilíngue Verificada por Audição

`VoiceResponseAdapter.adaptForSpeech(_:profile:customDictionary:)` (`VoiceConversationEngine.swift`) executa antes de enviar texto ao motor de síntese:
1. Resume blocos de código cercados (` ```...``` `) mantendo o código íntegro apenas no chat visual.
2. Remove sintaxe Markdown (`**`, `#`, `- `, backticks) e converte links `[texto](url)` ou URLs cruas para referências faladas naturais.
3. Substitui tabelas Markdown densas por resumo oral (*"A tabela detalhada está visível na tela do chat"*).
4. Aplica `TechnicalPronunciationDictionary` específico por idioma:
   - Na auditoria multimodal do áudio `04_enus_kokoro_heart_af_heart.wav`, detectou-se que `"Wisd A I"` em inglês fazia o `espeak-ng` pronunciar `"U-S D-A-I"`. O dicionário de `.englishUS` foi ajustado para `"Wiz D A I"`, e a amostra regenerada comprovou pronúncia nítida e compreensível.
   - Em português (`pt-BR` / `pt-PT`), `"WisdAI"` é adaptado foneticamente para `"Uísdêi-ái"`, `"SQLite"` para `"És-quê-él-lait"` e `"WebRTC"` para `"Uéb R T C"`.

---

## 3. Anti-Repetição e Diretrizes Conversacionais

- Remoção do sufixo artificial `"[Responda naturalmente em português brasileiro] "` dentro do texto do usuário em `LocalIntelligenceEngine.swift`.
- `LocalConversationalBrain` rastreia as últimas aberturas (`recentAssistantOpenings`) para evitar respostas robóticas repetitivas em turnos seguidos e instrui o modelo local a responder de forma concisa (1–3 frases objetivas adequadas à audição humana).
