# Segurança, Privacidade e Isolamento — WisdomUp Voice Intelligence

> Princípio: Processamento local prioritário, menor privilégio em ferramentas/agentes, zero vazamento de credenciais e isolamento estrito entre contas e projetos.

---

## 1. Garantias Obrigatórias Aplicadas

1. **Independência e Não-Exposição de Tokens:**
   - Proibida qualquer leitura de tokens privados em `~/.codex/auth.json` ou reutilização de credenciais de CLIs para endpoints privados não oficiais.
   - Credenciais oficiais opcionais (caso explicitamente habilitadas no futuro pelo utilizador) ficam exclusivamente no **macOS Keychain** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), jamais gravadas em SQLite, JSON de sessão, checkpoints de recuperação ou logs.

2. **Privacidade Acústica e Retenção Zero:**
   - Captura e raciocínio operam localmente no macOS (`SpeechAnalyzer`/`SpeechTranscriber` + `Apple FoundationModels` ANE + `Apple Natural PCM`) por padrão, com **zero transmissão de áudio pela rede**.
   - Áudio bruto de microfone e síntese residem apenas em buffers circulares voláteis de memória e são sobrescritos/liberados imediatamente no `barge-in` e ao encerrar a sessão (**`storeRawAudioRecordings = false` fixo por padrão**).
   - O indicador visual de microfone ativo fica permanentemente visível sempre que a captura estiver aberta, com botão de silenciamento instantâneo.

3. **Defesa Contra Prompt Injection por Voz & Quebra de Sandboxing (`ApprovalTierGuard`):**
   - Toda transcrição recebida por voz é classificada como entrada não-privilegiada do utilizador (`Role.user`).
   - O **WisdAI Voice Intelligence Engine** **nunca** executa comandos de terminal (`shell`), edições de arquivo ou ações destrutivas diretamente a partir de modelos de voz.
   - Qualquer delegação passa obrigatoriamente pelo **`Workspace` / `AgentOrchestrator`** aplicando:
     - O modo de segurança ativo do projeto (`Somente leitura`, `Escrita no projeto`, `Acesso total`);
     - Confirmações explícitas (`pendingApprovals`);
     - Classificação de risco inspirada no `ApprovalStore` do OpenJarvis (`trivial`, `low`, `medium`, `high` onde ações destrutivas sempre exigem confirmação humana);
     - Quarentena de fatos suspeitos na memória (`trust_tier = untrusted` nunca entra como instrução de sistema).

4. **Isolamento Entre Projetos, Contas e Produtos WisdomUp:**
   - Memória persistente local indexa registos isolados por `projectScope` e `accountScope` quando necessário, impedindo que segredos ou código de um projeto vazem para a conversa de outro projeto.
   - Todo log técnico passa por `VoiceLogRedactor` mascarando chaves (`sk-...`, `AIza...`), tokens `Bearer`/`Token`, `xi-api-key`, e-mails e nomes de utilizador em caminhos (`/Users/...` → `~`).
