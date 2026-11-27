# WisdAI V5 — Identidade Vocal & Personalidade JARVIS

**Identidade:** `WisdVoicePersona.jarvis` (`"JARVIS · Executivo WisdAI"`)  
**Estilo comportamental:** `VoicePersonalityStyle.jarvisExecutive` (`ConversationalBehaviorPlanner` + `VoicePersonalityProfile`)

---

## 1. Concepção Original (Sem Imitar Propriedade Intelectual de Terceiros)

A identidade **JARVIS** no WisdAI foi projetada como um interlocutor executivo original — calmo, lúcido, articulado, estratégico e sereno sob pressão — evitando caricaturas cinematográficas, referências fictícias e frases clichês de chatbot ("Certamente!", "Estou à disposição!").

### Atributos da Personalidade (`VoicePersonalityProfile`)
- **Warmth (`0.72`)**: próximo e colaborativo, mas contido.
- **Directness (`0.90`)**: objetivo, estruturado, focado em decisão e clareza técnica.
- **Cadence (`0.97`–`0.98×`)**: ritmo firme e equilibrado, evitando fala apressada ou arrastada.
- **Backchanneling (`0.48`)**: escuta ativa discreta ("Certo…", "Interessante…", "Hmm…"), evitando interjeições coloquiais em excesso.
- **Idiomas ativos:** Português (`pt-BR` prioritário; `pt-PT` via Supertonic-3 ou Apple Natural), **Inglês Britânico (`en-GB`)**, Inglês Americano (`en-US`) e Espanhol (`es-ES`).

---

## 2. Mapeamento Multi-Motor dos Candidatos JARVIS

Em vez de travar unilateralmente uma voz antes da avaliação humana, a arquitetura expõe três candidatos operacionais distintos (mais variação britânica em `en-GB`):

| Candidato | Motor | Speaker / SID | Idiomas Reais | Taxa | Perfil Acústico |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Candidato A — Barítono Sereno** | Supertonic-3 Flow Matching (`num_steps=10`) | `supertonic:m2` (`sid=6`) | PT, EN, ES | 44.1 kHz | Barítono profundo e calmo (~89–90 Hz em PT) |
| **Candidato B — Executivo Articulado** | Supertonic-3 Flow Matching (`num_steps=10`) | `supertonic:m4` (`sid=8`) | PT, EN, ES | 44.1 kHz | Tenor-barítono dinâmico e claro (~111–132 Hz em PT) |
| **Candidato C — Clássico PT-BR / Britânico EN-GB** | Kokoro-82M Neural (`int8`) | `pm_alex` (`sid=43`, PT-BR) / `bm_george` (`sid=26`, `en-GB-x-rp`) | PT-BR, EN-GB, EN-US, ES | 24 kHz | Fonética brasileira idiomática (`pm_alex` ~122–130 Hz) e sotaque britânico refinado (`bm_george` ~140 Hz em `en-GB`) |

> **Observação honesta sobre aprovação humana:** Conforme exigido na especificação V5, nenhuma dessas opções é declarada como escolha estética final sem audição e validação explícita do utilizador. Todas estão operacionais e selecionáveis ao vivo tanto no **Laboratório de Voz** quanto no **Popover/Ajustes**.

---

## 3. Continuidade Multiagente & Memória na Identidade JARVIS

A inteligência executiva pré-existente foi preservada integralmente:
- **Action Narrator & Delegação Paralela:** quando o usuário solicita análise de código/repositório ao Codex, Antigravity ou Claude, o JARVIS confirma em 1 frase serena e continua conversando sem bloquear a fala.
- **Working Memory & Higiene FTS5:** mantém separação por trust-tier (`verified`, `user_stated`, `untrusted`) e nunca injeta conteúdo de sessões externas sem filtro.
- **Full-Duplex e Barge-In:** interrupções imediatas mantêm a janela de eco (`AcousticEchoSuppressor`) e o corte exato de contexto ouvido.
