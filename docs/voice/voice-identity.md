# WisdAI Voice Identity — Identidade Vocal Proprietária e Invariante

> Princípio: A voz pertence exclusivamente ao **WisdAI / WisdomUp**. Trocar de conta, provedor ou agente (`Codex`, `Antigravity`, `Claude Code`) **nunca** altera a voz, personalidade ou ritmo do assistente.

---

## 1. Arquétipo da Identidade Vocal WisdAI

1. **Perfis Vocais Originais WisdAI (`WisdVoicePersona`):**
   - **Aurora (WisdAI — Voz Padrão Natural):** Timbre claro, acolhedor, sereno e ágil; foco em conversa colaborativa em PT-BR/PT-PT/EN/ES.
   - **Atlas (WisdAI — Masculina Estruturada):** Timbre firme, calmo e objetivo para discussões técnicas/executivas.
   - **Aria (WisdAI — Dinâmica):** Ritmo ligeiramente mais ágil para brainstorming.
   - **Invariância Garantida:** O perfil selecionado em `VoiceIdentityProfile` permanece fixo independentemente do agente especialista consultado nos bastidores.

2. **Parâmetros Prosódicos e Estilísticos (Não Dependentes de Agentes):**
   - **Cadência natural:** Pontuação prosódica adaptativa sem pausas artificiais nem leitura mecânica de símbolos Markdown, backticks ou URLs.
   - **Respeito linguístico contínuo:** Adapta automaticamente `PT-BR`, `PT-PT`, `EN` e `ES` ao idioma ativo da fala do utilizador (ou escolha fixa no HUD).
   - **Vocabulário técnico WisdomUp:** Pronúncia consistente de termos técnicos (`WisdAI`, `WisdPlay`, `WisdFin`, `WisdMeet`, `API`, `CLI`, `WebRTC`, `SQLite`, `macOS`, `PR`).

---

## 2. Estratégia Técnica de Síntese Vocal (`Voice Identity Layer`)

| Camada | Mecanismo | Estado Atual / Requisitos | Consistência Cross-Agent & Cross-Product |
|---|---|---|---|
| **Camada Nativa Zero-Download (Ativa por Padrão)** | `AppleNaturalPCMStreamingTTSProvider` (`AVSpeechSynthesisVoice` Siri Natural / Enhanced + aquecimento assíncrono `~158 ms`) | Imediata e gratuita no macOS sem baixar pesos externos. *Observação:* voz `Atlas` masculina nativa requer que o utilizador baixe voz Aprimorada/Siri masculina nos Ajustes do macOS, senão `Aurora` (`Sandra`) natural responde com máxima naturalidade sem pitch-shift destrutivo. | Mantém exatamente a mesma voz independentemente de `Codex`, `Antigravity`, `Claude` ou conta selecionada. |
| **Camada Neural Portável Opcional (`Kokoro-82M` Apache-2.0)** | Vetores de estilo (`pf_dora` / `pm_santa` / mistura proprietária de estilo `VoiceEmbeddingDescriptor`) via CoreML / ONNX sidecar | Arquitetura preparada com `KokoroStyleVectorSpec` e verificador de espaço livre + autorização antes de baixar (~320 MB). | Permite idêntica assinatura acústica futura em **WisdAI**, **WisdMeet**, **WisdFin** e **WisdInvest**. |

3. **Proibição Absoluta:** Nunca amostrar, copiar ou clonar vozes proprietárias do ChatGPT, Gemini, ElevenLabs ou terceiros sem licença explícita.
