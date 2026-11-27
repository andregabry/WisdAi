# WisdAI V5 — Personalidade Conversacional, Prompts e Naturalidade

**Módulos envolvidos:**  
- [`VoiceConversationEngine.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceConversationEngine.swift)  
- [`VoiceBehaviorEngine.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceBehaviorEngine.swift)  
- [`VoiceOrchestrator.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceOrchestrator.swift)

---

## 1. Prompts por Idioma & Personalidade (`buildLocalBrainInstructions` + `systemPromptInstructions`)

- **Identidade JARVIS (`VoicePersonalityStyle.jarvisExecutive`)**:
  - Instrui o cérebro local (`Qwen3-1.7B` / `Apple FoundationModels`) a adotar postura lúcida, estratégica, calma e direta — com discrição refinada e zero aberturas repetitivas ou encerramentos robóticos.
  - Em **`en-GB`**, orienta fraseado britânico articulado e conciso.
  - Em **`pt-BR`** e **`pt-PT`**, adapta o registro oral mantendo termos técnicos legíveis via `TechnicalPronunciationDictionary`.
- **Higienização anti-vazamento**:
  - `ConversationalBehaviorPlan.stripBehaviorMetadataFromSpeech` remove metadados JSON ou colchetes caso modelos locais pequenos tentem ecoar instruções de tom.
  - `LocalQueryComplexityAnalyzer.extractSpecialistEscalation` separa `[CONSULTAR_ESPECIALISTA: ...]` para acionar agentes somente-leitura sem falar tags técnicas em voz alta.

---

## 2. Planejamento Comportamental Não Repetitivo (`ConversationalBehaviorPlanner` + `NaturalSpeechComposer`)

- **Anti-repetição estrita:** `turnsSinceLastLeadVocalization` impede inserção automática de "Hmm…"/"Certo…" em turnos seguidos; especificamente para `.jarvis`, interjeições coloquiais como `"Olha,"` em explicações técnicas são substituídas por marcadores mais sóbrios como `"Certo…"`.
- **Pausas e fluidez:** `NaturalSpeechComposer` remove fórmulas engessadas (`stiffOpeners` / `roboticSignOffRegexPatterns`), suaviza listas numeradas em fala corrida e preserva identificadores exatos de código/arquivos quando discutidos tecnicamente.
- **Orquestração paralela:** `VoiceActionRiskTier` e `onDelegateTaskToAgent` garantem que o utilizador possa conversar naturalmente enquanto Codex, Antigravity ou Claude executam tarefas no workspace.
