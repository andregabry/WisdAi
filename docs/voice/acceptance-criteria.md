# Critérios Formais de Aceitação (Seção 22)

O **WisdAI Autonomous Voice Intelligence Engine** só será declarado concluído mediante evidência verificável de cada item abaixo:

| # | Critério Obrigatório | Forma de Validação Exigida |
|---|---|---|
| 1 | **WisdAI possui identidade vocal independente** | Testes + inspeção UI confirmando identidade própria (`Aurora`/`Atlas`/`Aria`), separada dos fornecedores. |
| 2 | **A voz não depende do agente ativo** | Teste automatizado trocando `Codex` ↔ `Antigravity` ↔ `Claude` mantendo exatamente mesmo provedor vocal e perfil. |
| 3 | **Inicialização local funciona sem conexão eterna** | Sem `"Conectando voz"` infinito: falha de WebRTC Codex removida, timeout máximo <= 2.5s garantido; teste real validando transição rápida de `.connecting` -> `.listening` / `.assistantSpeaking`. |
| 4 | **Conversação com naturalidade comprovada** | Saída do `LocalIntelligenceEngine` + `VoiceResponseAdapter` em linguagem natural sem Markdown/URLs/introduções robóticas + PoC real executado. |
| 5 | **Utilizador pode interromper o assistente (Barge-in)** | Teste real + medição `BargeInCoordinator` com flush de `AdaptiveJitterBuffer` < 150 ms e cancelamento de síntese/geração. |
| 6 | **Assistente compreende pausas naturais** | Teste reproduzindo *"Eu estava pensando… talvez fosse melhor mudar a arquitetura do projeto… mas ainda não tenho certeza."* segurando turno sem interromper. |
| 7 | **Conversação preserva contexto** | Contexto contínuo multi-turno + truncagem exata ao trecho ouvido no barge-in + memória SQLite FTS5 & compactação. |
| 8 | **Motor consegue consultar agentes externos** | `LocalIntelligenceEngine` roteando solicitações complexas/de projeto via ferramentas para `Codex`/`Antigravity`/`Claude`. |
| 9 | **Tarefas dos agentes não bloqueiam a conversa** | Execução assíncrona de `ActiveThreadTask` enquanto o canal de voz permanece escutando e respondendo normalmente. |
| 10 | **Troca de conta não altera identidade vocal** | Troca simulada e verificada em `StateSmoke` / `VoiceSmokeTests` sem mudança no `VoiceIdentityProfile`. |
| 11 | **Troca de agente não elimina contexto** | `PortableVoiceContextSnapshot` + `VoiceMemoryStore` preservam histórico ao alternar entre agentes. |
| 12 | **Nenhuma dependência obrigatória de APIs pagas de voz** | Modo padrão opera `100%` com motores locais (`Apple SpeechAnalyzer`, `FoundationModels`, `Apple Natural PCM`), sem exigir chaves externas. |
| 13 | **Requisitos de hardware documentados** | [hardware-requirements.md](hardware-requirements.md) completo (`8` a `64+ GB`) + detecção automática ativa. |
| 14 | **Resultados de desempenho comprovados** | Benchmarks reais publicados em [benchmarks.md](benchmarks.md) e [proof-of-concept.md](proof-of-concept.md) com medições honestas. |
| 15 | **Testes automatizados aprovados** | `run-voice-smoke.sh`, `run-state-smoke.sh`, `run-recovery-smoke.sh` e `VoicePoC` passando após a última edição. |
| 16 | **Funcionalidades existentes sem regressões** | App completo compilado em Release `-O`, assinado `--deep --strict`, inicializado e validado nos fluxos de chat, projetos, contas e recuperação. |
