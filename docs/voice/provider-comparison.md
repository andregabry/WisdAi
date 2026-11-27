# Comparativo Técnico de Provedores e Estratégias de Voz (Auditado)

> Data da Auditoria: 2026-11-26  
> Premissas verificadas na documentação oficial dos fornecedores e em testes reais no hardware alvo (Apple M2, 8 cores, 8 GB RAM, macOS).

---

## 1. Esclarecimento Obrigatório: Assinaturas de Consumo vs. APIs Comerciais

A auditoria nas documentações oficiais da OpenAI, Google e Anthropic confirma uma separação contratual e técnica rígida:

| Assinatura / CLI Local | Inclui API Realtime / API de Áudio Comercial? | Evidência / Limite Técnico Verificado |
|---|---|---|
| **ChatGPT Plus ($20/mês)** | **Não.** | Cobre apenas o app web/mobile oficial do ChatGPT; não inclui créditos de API nem autentica chamadas para `api.openai.com/v1/realtime` ou TTS/STT API. |
| **ChatGPT Pro / Business** | Apenas via créditos vinculados no Developer Platform (quando elegível). | Mesmo nesses planos, a API de desenvolvimento exige chave em `platform.openai.com` com faturamento por token. O fluxo oficial suportado para sessão Codex existente sem extração indevida de token é exclusivamente via `codex app-server` JSON-RPC (`thread/realtime/*`), respeitando os limites e cotas da conta no processo oficial. |
| **Google AI Pro ($19.99/mês) / CLI `agy`** | **Não.** (Exceto bônus promocional separado de Cloud quando resgatado no AI Studio). | "Gemini Live" do app consumidor é diferente da **Gemini Live API (`BidiGenerateContent`)** no Google AI Studio / Vertex AI, que cobra por token ou gera tráfego sujeito às políticas do tier gratuito/pago da API. A CLI `agy` verificada (`--help`) não expõe endpoint de áudio S2S bidirecional, apenas turnos textuais `--output-format stream-json`. |
| **Claude Pro ($20/mês) / CLI `claude`** | **Não.** | Assinatura de consumo não fornece chaves de API nem possui API Speech-to-Speech nativa na Anthropic; uso programático ocorre via Console API paga por token ou CLI de texto. |

**Decisão obrigatória decorrente:** O WisdAI **nunca** assume que uma conta CLI/assinatura do usuário libera acesso gratuito ou ilimitado a APIs Speech-to-Speech. Todas as APIs pagas permanecem **desativadas por padrão**, exigindo chave oficial no macOS Keychain, consentimento explícito de envio de áudio externo e autorização expressa de uso pago antes de transmitir um único frame de áudio.

---

## 2. Comparativo Técnico por Fornecedor e Arquitetura

### 2.1 Arquitetura A — Native Real-Time Speech-to-Speech (S2S)

| Critério | OpenAI Realtime API (`gpt-realtime-2.1` / `-mini`) | Google Gemini Live API (`BidiGenerateContent`, ex. `gemini-3.8-live`) | Codex `app-server` (`thread/realtime/*`) |
|---|---|---|---|
| **Protocolo / Áudio** | WebRTC (cliente) ou WebSocket (`wss://api.openai.com/v1/realtime`); `pcm16` 24 kHz mono / `g711` | WebSocket (`wss://generativelanguage.googleapis.com/...BidiGenerateContent`); Input `pcm16` 16 kHz / Output `pcm16` 24 kHz | JSON-RPC local IPC (`thread/realtime/start`, `appendAudio`, `sdp`, `appendText`) mediado pelo processo oficial `codex` |
| **Naturalidade & Prosódia** | Excelente entonação, pausa e expressão emocional nativa | Muito boa naturalidade, expressividade e alternância multilíngue | Dependente do backend oficial do Codex quando a conta está elegível e sem limite de cota |
| **Qualidade PT-BR / PT-PT / EN** | PT-BR muito bom; EN excelente; PT-PT satisfatório (sotaque tende ao neutro/PT-BR conforme prompt) | PT-BR bom; EN excelente; bom suporte multilíngue e alternância | Mesma base OpenAI quando habilitado na sessão |
| **VAD & Barge-in** | `server_vad` e **`semantic_vad`** nativos + `conversation.item.truncate(audio_end_ms)` | `automaticActivityDetection` configurável + cancelamento automático no turn-taking e `sessionResumption` (necessário ~a cada 10 min) | Barge-in e transcrição gerenciados pelo protocolo `thread/realtime/item/*` |
| **Latência Esperada (E2E)** | ~280–450 ms típico em WebRTC/WS | ~320–550 ms típico em WS | ~350–650 ms (inclui ponte IPC local + sessão remota) |
| **Custo Oficial (Docs)** | Flagship: `$32/1M` audio in, `$64/1M` audio out; Mini: `$10/1M` in, `$20/1M` out | ~$3/1M audio in (~$0.005/min), ~$12/1M audio out (~$0.018/min); **cobrança acumula contexto a cada turno** | Vinculado aos limites da sessão oficial autenticada no `codex` CLI (nesta máquina verificou-se `limit_reached: true` ativo em períodos de uso intenso) |
| **Privacidade / Restrições** | Zero retenção/treino padrão na API comercial mediante termos; requer chave explícita | Tier gratuito pode ser usado para melhoria de produto; Tier pago segue termos de privacidade comercial; limite de ~10 min por conexão WebSocket exige `sessionResumption` | Depende inteiramente da conta conectada ao `codex`; falha graciosamente quando indisponível ou limitado |

---

### 2.2 Arquitetura B — Pipeline Desacoplado (`Streaming STT -> Streaming LLM -> Streaming TTS`)

Esta arquitetura é essencial para:
1. Permitir conversar em voz com **qualquer agente WisdAI** (`Gemini CLI/API`, `Claude`, `DeepSeek`, `Grok`, `Kimi`, `NVIDIA NIM`, `Codex`) sem depender de S2S proprietário.
2. Operar em **modo 100% gratuito / offline ou custo mínimo** usando Speech/Audio nativos do macOS sem chave paga configurada.
3. Reduzir custos drásticos em sessões longas mantendo histórico compactado no `WisdAI`.

#### STT (Speech-to-Text Streaming)

| Opção | Latência | Qualidade PT-BR / PT-PT / EN | Custo | Notas Técnicas e Limites |
|---|---|---|---|---|
| **Apple `SFSpeechRecognizer` (On-Device / Native)** | ~180–350 ms parciais | Muito boa em PT-BR e EN; boa em PT-PT | **$0** (incluído no macOS) | Limite rígido documentado da Apple de **60 s por tarefa** (resolvido por rotação contínua sobreposta no engine). `requiresOnDeviceRecognition = true` mantém áudio 100% no Mac quando o pacote do idioma está baixado; sem pacote offline, avisa o usuário que a Apple pode processar via rede se consentido. |
| **Deepgram (`Nova-3` Multilingual / `Flux`) — Opt-In** | `< 300 ms` streaming; Flux tem detecção de fim de turno `< 300 ms` | Excelente PT-BR, PT-PT e EN (45+ idiomas no Nova-3) | Nova-3 Multi `$0.0058/min` promo (`$0.0092` reg); Flux EN `$0.0065/min` (Multi `$0.0078/min`) | Excelente endpointing para barge-in e vocabulário técnico (`keyterms`); requer chave Deepgram no Keychain + consentimento. |
| **OpenAI Transcription (`gpt-4o-mini-transcribe` / Realtime Transcription) — Opt-In** | ~300–500 ms | Excelente PT-BR, PT-PT, EN e termos de código | API paga por uso | Somente endpoint oficial `/v1/audio/transcriptions` ou Realtime WS com chave oficial OpenAI (nunca `/backend-api/transcribe`). |

#### TTS (Streaming Text-to-Speech)

| Opção | Naturalidade | Latência (TTFA) | PT-BR / PT-PT / EN | Custo | Notas Reais deste Mac (Apple M2 8 GB) |
|---|---|---|---|---|---|
| **ElevenLabs (`eleven_flash_v2_5`) WebSocket — Opt-In** | **Referência comercial (9.5/10)** | **~75–100 ms servidor** (~150–250 ms com rede) | Excelente em 32 idiomas (PT-BR, PT-PT, EN, ES) | ~$0.04–$0.05 / 1k chars | Streaming chunk-by-chunk via WebSocket com `auto_mode: true`; exige chave ElevenLabs no Keychain + opt-in pago. |
| **OpenAI TTS (`gpt-4o-mini-tts` / `tts-1` em PCM) — Opt-In** | **Muito alta (9/10)** | ~350–500 ms em `pcm` 24 kHz | PT-BR muito natural; controla estilo/tom por instrução | `tts-1`: $15/1M chars; `gpt-4o-mini-tts`: $0.60/1M in + $12/1M audio out | Suporta streaming HTTP chunked direto em PCM; observar agenda futura de transição da OpenAI para APIs Realtime. |
| **macOS Nativo `AVSpeechSynthesizer` (Siri Natural `Sandra` / Vozes Aprimoradas)** | **Boa (quando `Siri Natural` / `Enhanced` instalada); Robótica no `eloquence`** | `< 120 ms` local (offline) | Boa no pacote `com.apple.siri.natural.Sandra` (`pt-BR`) | **$0** (100% local, zero envio de dados) | **Teste real neste Mac:** Apenas `Sandra` Natural (`quality=2`, feminina) e vozes compactas femininas estão instaladas. Zero vozes masculinas naturais baixadas localmente; `eloquence` foi rebaixada a último recurso; pitch-shift em áudio de `Sandra` foi descartado por distorcer formantes. O app orienta de forma transparente a baixar vozes *Aprimoradas / Siri* nas Preferências do Sistema caso queira voz masculina gratuita offline ou usar ElevenLabs/OpenAI opt-in. |
| **TTS Local Externo (Piper / Kokoro / CLI local opt-in)** | Boa (depende do modelo) | ~120–300 ms em M2 | Depende do modelo instalado pelo usuário | **$0** (local) | Desligado por padrão para preservar os **8 GB de RAM** deste MacBook M2; ativado apenas se binário/modelo estiver instalado e selecionado pelo usuário. |

---

## 3. Decisão de Estratégia Recomendada (Multi-Tier Padrão WisdAI)

1. **Padrão Seguro Out-of-the-Box ($0 / Zero Surpresa de Cobrança):**
   - **Captura & Áudio Engine Nativo Full-Duplex** + **Apple `SFSpeechRecognizer`** (preferindo `requiresOnDeviceRecognition` quando disponível, com rotação contínua `< 60 s`) + **Streaming do Agente Ativo no WisdAI** (`agy` `--output-format stream-json`, `codex app-server`, etc.) com extração incremental de sentenças/cláusulas + **Apple Natural Voice (`AVSpeechSynthesizer` PCM streaming)** sem pitch-shift destrutivo e sem chamar endpoints não oficiais.
   - Assim que uma API oficial paga (OpenAI / Gemini / ElevenLabs / Deepgram) recebe chave no Keychain **e** o usuário habilita explicitamente "Permitir uso de API de voz paga" + consentimento de áudio externo, o roteador promove automaticamente para o provedor escolhido.
2. **Modo Ultra-Natural Streaming Híbrido (Qualidade ChatGPT para qualquer LLM/Agente do WisdAI):**
   - `Deepgram Nova-3 / Apple On-Device` + `WisdAI Active LLM/CLI Streaming` + `ElevenLabs Flash v2.5 WS` (ou `OpenAI gpt-4o-mini-tts PCM`), entregando naturalidade e prosódia de produto comercial em PT-BR/PT-PT/EN mantendo acesso às ferramentas/projetos do WisdAI.
3. **Modo S2S Nativo Ultra-Baixa Latência:**
   - `OpenAI Realtime` (com `semantic_vad` e `conversation.item.truncate`) ou `Gemini Live` (`BidiGenerateContent` com `sessionResumption`), usando o **Orchestrator Bridge** para delegar tarefas demoradas ao agente do projeto sem bloquear a conversa.
