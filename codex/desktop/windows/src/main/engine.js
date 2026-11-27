const { spawn, exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

class EngineManager {
  constructor(appDataDir, sendToRenderer) {
    this.appDataDir = appDataDir;
    this.sendToRenderer = sendToRenderer;
    this.process = null;
    this.activeTurnProcess = null;
    this.requestId = 1;
    this.pendingRequests = new Map();
    this.buffer = '';
    this.ready = false;
    this.models = [];
    this.account = { label: 'Conectando ao motor...', type: 'none' };

    // Persistent storage paths
    this.storageDir = path.join(this.appDataDir, 'WisdAI');
    if (!fs.existsSync(this.storageDir)) {
      fs.mkdirSync(this.storageDir, { recursive: true });
    }
    this.conversationsPath = path.join(this.storageDir, 'conversations.json');
    this.accountsPath = path.join(this.storageDir, 'accounts.json');
    this.apiKeysPath = path.join(this.storageDir, 'api_keys.json');
    this.spacePath = path.join(this.storageDir, 'space.json');

    this.initStorage();
  }

  initStorage() {
    if (!fs.existsSync(this.conversationsPath)) {
      fs.writeFileSync(this.conversationsPath, JSON.stringify([
        {
          id: 'conv-1',
          title: 'Boas-vindas ao WisdAI',
          cwd: this.storageDir,
          createdAt: Date.now(),
          messages: [
            {
              id: 'm1',
              author: 'assistant',
              text: 'Olá! Sou o **WisdAI**, seu assistente avançado de inteligência artificial e agente autônomo de engenharia de software para Windows.\n\nPosso executar comandos de terminal, inspecionar e editar código, conectar a múltiplos provedores (OpenAI, Gemini, Claude, DeepSeek) e gerenciar projetos.\n\nComo posso ajudar você hoje?'
            }
          ]
        }
      ], null, 2));
    }

    if (!fs.existsSync(this.accountsPath)) {
      fs.writeFileSync(this.accountsPath, JSON.stringify({
        activeId: 'acc-codex-1',
        accounts: [
          { id: 'acc-codex-1', label: 'Codex Engine (Oficial)', provider: 'codex', email: 'default@wisdai.local', active: true },
          { id: 'acc-gemini-1', label: 'Google Gemini (AGY CLI)', provider: 'gemini', email: 'gemini@wisdai.local', active: false },
          { id: 'acc-claude-1', label: 'Claude Code CLI', provider: 'claude', email: 'claude@wisdai.local', active: false },
          { id: 'acc-deepseek-1', label: 'DeepSeek AI', provider: 'deepseek', email: 'deepseek@wisdai.local', active: false }
        ]
      ], null, 2));
    }

    if (!fs.existsSync(this.apiKeysPath)) {
      fs.writeFileSync(this.apiKeysPath, JSON.stringify({}, null, 2));
    }

    if (!fs.existsSync(this.spacePath)) {
      fs.writeFileSync(this.spacePath, JSON.stringify([
        { id: 'item-1', name: 'Documento Inicial.txt', type: 'page', space: 'default', date: 'Hoje', size: '1.2 KB' },
        { id: 'item-2', name: 'Arquitetura WisdAI.md', type: 'page', space: 'default', date: 'Hoje', size: '4.8 KB' }
      ], null, 2));
    }
  }

  findEngineBinary() {
    const isWin = process.platform === 'win32';
    const binaryName = isWin ? 'codex.exe' : 'codex';
    const hostName = isWin ? 'codex-code-mode-host.exe' : 'codex-code-mode-host';

    const candidates = [
      // 1. Packaged resource directory
      path.join(process.resourcesPath || '', 'bin', binaryName),
      // 2. Local app directory
      path.join(__dirname, '..', '..', 'bin', binaryName),
      // 3. User local paths
      isWin 
        ? path.join(os.homedir(), 'AppData', 'Local', 'Programs', 'WisdAI', 'bin', binaryName)
        : path.join(os.homedir(), '.local', 'bin', binaryName),
      isWin
        ? path.join(os.homedir(), '.cargo', 'bin', binaryName)
        : '/usr/local/bin/codex'
    ];

    for (const candidate of candidates) {
      if (candidate && fs.existsSync(candidate)) {
        return {
          binary: candidate,
          hostBinary: path.join(path.dirname(candidate), hostName)
        };
      }
    }

    return null;
  }

  async start() {
    const paths = this.findEngineBinary();
    if (!paths) {
      console.log('Motor nativo local não detectado. Ativando modo Multi-Provedor nativo (Direct API & System Tools).');
      this.ready = true;
      this.populateDefaultModels();
      this.sendToRenderer('engine:status', {
        ready: true,
        mode: 'multi-provider',
        message: 'WisdAI Engine pronto (Multi-Provedor e Ferramentas do Windows Ativas)'
      });
      return;
    }

    try {
      console.log(`Iniciando codex app-server a partir de: ${paths.binary}`);
      this.process = spawn(paths.binary, ['app-server'], {
        env: { ...process.env, CODEX_HOME: this.storageDir }
      });

      this.process.stdout.on('data', (chunk) => this.handleData(chunk));
      this.process.stderr.on('data', (data) => console.error(`[Engine STDERR]: ${data.toString()}`));
      this.process.on('close', (code) => {
        console.log(`Engine process closed with code ${code}`);
        this.ready = false;
        this.sendToRenderer('engine:status', { ready: false, message: 'Motor desconectado.' });
      });

      this.sendRequest('initialize', {
        clientInfo: { name: 'wisdai-desktop-windows', version: '0.7.1' },
        capabilities: { experimentalApi: true }
      }).then(() => {
        this.ready = true;
        this.populateDefaultModels();
        this.sendToRenderer('engine:status', { ready: true, mode: 'native', message: 'Conectado ao motor nativo WisdAI' });
      }).catch((err) => {
        console.error('Falha no handshake inicial:', err);
        this.ready = true;
        this.populateDefaultModels();
      });

    } catch (e) {
      console.error('Erro ao instanciar processo do motor:', e);
      this.ready = true;
      this.populateDefaultModels();
    }
  }

  handleData(chunk) {
    this.buffer += chunk.toString();
    let newlineIndex;
    while ((newlineIndex = this.buffer.indexOf('\n')) !== -1) {
      const line = this.buffer.slice(0, newlineIndex).trim();
      this.buffer = this.buffer.slice(newlineIndex + 1);
      if (line) {
        this.parseMessage(line);
      }
    }
  }

  parseMessage(line) {
    try {
      const msg = JSON.parse(line);
      if (msg.id && this.pendingRequests.has(msg.id)) {
        const { resolve, reject } = this.pendingRequests.get(msg.id);
        this.pendingRequests.delete(msg.id);
        if (msg.error) {
          reject(msg.error);
        } else {
          resolve(msg.result);
        }
      } else if (msg.method === 'turn/stream' || msg.method === 'turn/delta') {
        const delta = msg.params?.delta?.text || msg.params?.text || '';
        this.sendToRenderer('engine:streamChunk', { text: delta });
      }
    } catch (err) {
      console.error('Erro ao parsear mensagem JSON-RPC:', err);
    }
  }

  sendRequest(method, params = {}) {
    return new Promise((resolve, reject) => {
      if (!this.process || !this.process.stdin.writable) {
        return reject(new Error('Processo do motor não está disponível'));
      }
      const id = this.requestId++;
      this.pendingRequests.set(id, { resolve, reject });
      const payload = JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n';
      this.process.stdin.write(payload);
    });
  }

  populateDefaultModels() {
    this.models = [
      { id: 'gpt-4o', name: 'GPT-4o (Codex Engine)', provider: 'openai', isDefault: true, efforts: ['auto', 'low', 'medium', 'high'] },
      { id: 'o3-mini', name: 'o3-mini (Raciocínio Rápido)', provider: 'openai', isDefault: false, efforts: ['low', 'medium', 'high'] },
      { id: 'gemini-2.5-flash', name: 'Gemini 2.5 Flash (Google AI)', provider: 'gemini', isDefault: false, efforts: ['auto', 'high'] },
      { id: 'claude-3-7-sonnet', name: 'Claude 3.7 Sonnet (Anthropic)', provider: 'anthropic', isDefault: false, efforts: ['standard', 'thinking'] },
      { id: 'deepseek-chat', name: 'DeepSeek V3 (DeepSeek AI)', provider: 'deepseek', isDefault: false, efforts: ['auto'] },
      { id: 'deepseek-reasoner', name: 'DeepSeek R1 (Raciocínio Puro)', provider: 'deepseek', isDefault: false, efforts: ['high'] }
    ];
  }

  getConversations() {
    try {
      const data = fs.readFileSync(this.conversationsPath, 'utf-8');
      return JSON.parse(data);
    } catch {
      return [];
    }
  }

  saveConversations(convs) {
    fs.writeFileSync(this.conversationsPath, JSON.stringify(convs, null, 2));
  }

  getApiKey(provider) {
    try {
      const keys = JSON.parse(fs.readFileSync(this.apiKeysPath, 'utf-8'));
      if (keys[provider]) return keys[provider];
    } catch {}

    const envMap = {
      openai: ['OPENAI_API_KEY'],
      codex: ['OPENAI_API_KEY'],
      gemini: ['GEMINI_API_KEY', 'GOOGLE_API_KEY'],
      anthropic: ['ANTHROPIC_API_KEY'],
      claude: ['ANTHROPIC_API_KEY'],
      deepseek: ['DEEPSEEK_API_KEY']
    };

    const envNames = envMap[provider] || [];
    for (const envName of envNames) {
      if (process.env[envName]) return process.env[envName];
    }
    return null;
  }

  async executeSystemCommand(cmd, cwd) {
    return new Promise((resolve) => {
      const isWin = process.platform === 'win32';
      const shell = isWin ? 'powershell.exe' : '/bin/sh';
      exec(cmd, { cwd: cwd || this.storageDir, shell, timeout: 30000 }, (err, stdout, stderr) => {
        resolve({
          success: !err,
          code: err ? err.code || 1 : 0,
          stdout: stdout || '',
          stderr: stderr || (err ? err.message : '')
        });
      });
    });
  }

  async sendTurn({ conversationId, message, model, attachments }) {
    const convs = this.getConversations();
    let conv = convs.find(c => c.id === conversationId);
    if (!conv) {
      conv = {
        id: conversationId,
        title: message.slice(0, 30) + '...',
        cwd: this.storageDir,
        createdAt: Date.now(),
        messages: []
      };
      convs.unshift(conv);
    }

    conv.messages.push({
      id: `u-${Date.now()}`,
      author: 'user',
      text: message,
      attachments: attachments || []
    });
    this.saveConversations(convs);

    const assistantMsgId = `a-${Date.now()}`;
    conv.messages.push({
      id: assistantMsgId,
      author: 'assistant',
      text: '',
      model: model || 'gpt-4o'
    });
    this.saveConversations(convs);

    // 1. Direct native codex process dispatch
    if (this.process && this.ready && (!model || model.startsWith('gpt') || model.startsWith('o3'))) {
      try {
        await this.sendRequest('turn/start', {
          threadId: conversationId,
          model: model || 'gpt-4o',
          input: [{ type: 'text', text: message }]
        });
        return { success: true };
      } catch (e) {
        console.warn('Erro ao despachar via codex app-server nativo, usando engine multi-provedor:', e);
      }
    }

    // 2. Direct command execution prefix ($ command or exec: command)
    const trimmed = message.trim();
    if (trimmed.startsWith('$ ') || trimmed.startsWith('exec: ')) {
      const command = trimmed.startsWith('$ ') ? trimmed.slice(2) : trimmed.slice(6);
      return this.handleCommandExecutionTurn(conv, assistantMsgId, command);
    }

    // 3. Multi-Provider LLM Integration
    return this.handleAgentTurn(conv, assistantMsgId, message, model);
  }

  async handleCommandExecutionTurn(conv, messageId, command) {
    this.sendToRenderer('engine:streamChunk', {
      text: `> Executando no terminal Windows: \`${command}\`...\n\n`,
      messageId
    });

    const result = await this.executeSystemCommand(command, conv.cwd);
    let output = '';
    if (result.stdout) {
      output += '```\n' + result.stdout + '\n```\n';
    }
    if (result.stderr) {
      output += '**Avisos/Erros:**\n```\n' + result.stderr + '\n```\n';
    }
    if (!result.stdout && !result.stderr) {
      output += '*(Comando concluído sem saída)*\n';
    }

    const fullText = `### Execução de Comando\n**Comando:** \`${command}\`\n**Status:** ${result.success ? '✅ Sucesso' : '❌ Falha (código ' + result.code + ')'}\n\n${output}`;
    this.sendToRenderer('engine:streamChunk', { text: fullText, messageId });
    this.sendToRenderer('engine:streamEnd', { messageId, text: fullText });

    const msg = conv.messages.find(m => m.id === messageId);
    if (msg) {
      msg.text = fullText;
      this.saveConversations(this.getConversations());
    }
    return { success: true, text: fullText };
  }

  async handleAgentTurn(conv, messageId, prompt, model) {
    const selectedModel = model || 'gpt-4o';
    let provider = 'openai';
    if (selectedModel.includes('gemini')) provider = 'gemini';
    else if (selectedModel.includes('claude')) provider = 'anthropic';
    else if (selectedModel.includes('deepseek')) provider = 'deepseek';

    const apiKey = this.getApiKey(provider);

    // If API Key is present, execute via real LLM API
    if (apiKey) {
      try {
        return await this.callCloudProvider({ conv, messageId, prompt, model: selectedModel, provider, apiKey });
      } catch (err) {
        console.error('Falha na chamada da API do provedor:', err);
        const errMsg = `\n\n⚠️ **Erro na chamada à API (${provider}):** ${err.message}\nVerifique sua chave de API ou conexão de rede.`;
        this.sendToRenderer('engine:streamChunk', { text: errMsg, messageId });
        this.sendToRenderer('engine:streamEnd', { messageId, text: errMsg });
        return { success: false, error: err.message };
      }
    }

    // Fallback: Agent Local Assistant Mode
    return this.streamLocalAgentResponse(conv, messageId, prompt, selectedModel, provider);
  }

  async callCloudProvider({ conv, messageId, prompt, model, provider, apiKey }) {
    let fullText = '';

    const systemPrompt = `Você é o WisdAI, um agente autônomo de inteligência artificial de elite e engenheiro de software para Windows.
Seu workspace atual é: "${conv.cwd || this.storageDir}".
Responda com precisão, clareza e código de alta qualidade em português (a menos que solicitado outro idioma).
Você pode orientar a execução de comandos no Windows (PowerShell/cmd) e auxiliar em tarefas completas de desenvolvimento.`;

    if (provider === 'openai' || provider === 'deepseek') {
      const baseUrl = provider === 'deepseek' ? 'https://api.deepseek.com/v1/chat/completions' : 'https://api.openai.com/v1/chat/completions';
      const actualModel = provider === 'deepseek'
        ? (model.includes('reasoner') ? 'deepseek-reasoner' : 'deepseek-chat')
        : (model.includes('o3') ? 'o3-mini' : 'gpt-4o');

      const response = await fetch(baseUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`
        },
        body: JSON.stringify({
          model: actualModel,
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: prompt }
          ],
          stream: true
        })
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`HTTP ${response.status}: ${errorText}`);
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder('utf-8');
      let partialData = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        partialData += decoder.decode(value, { stream: true });
        const lines = partialData.split('\n');
        partialData = lines.pop() || '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (trimmed.startsWith('data: ') && trimmed !== 'data: [DONE]') {
            try {
              const parsed = JSON.parse(trimmed.slice(6));
              const delta = parsed.choices?.[0]?.delta?.content || '';
              if (delta) {
                fullText += delta;
                this.sendToRenderer('engine:streamChunk', { text: delta, messageId });
              }
            } catch {}
          }
        }
      }
    } else if (provider === 'gemini') {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?key=${apiKey}`;
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts: [{ text: `${systemPrompt}\n\nUsuário: ${prompt}` }] }]
        })
      });

      if (!response.ok) {
        const errText = await response.text();
        throw new Error(`HTTP ${response.status}: ${errText}`);
      }

      const data = await response.json();
      const candidateText = data?.[0]?.candidates?.[0]?.content?.parts?.[0]?.text || 'Resposta processada.';
      fullText = candidateText;
      this.sendToRenderer('engine:streamChunk', { text: fullText, messageId });
    }

    const msg = conv.messages.find(m => m.id === messageId);
    if (msg) {
      msg.text = fullText;
      this.saveConversations(this.getConversations());
    }
    this.sendToRenderer('engine:streamEnd', { messageId, text: fullText });
    return { success: true, text: fullText };
  }

  async streamLocalAgentResponse(conv, messageId, prompt, modelName, provider) {
    const isWindows = process.platform === 'win32';
    const osInfo = isWindows ? `Windows x64 (NT ${os.release()})` : `${os.type()} ${os.arch()}`;

    const chunks = [
      `### ⚡ WisdAI Agent (${modelName})\n\n`,
      `Entendi a sua solicitação:\n> "${prompt}"\n\n`,
      `**Ambiente de Execução:**\n`,
      `- **Sistema:** ${osInfo}\n`,
      `- **Workspace:** \`${conv.cwd || this.storageDir}\`\n`,
      `- **Provedor Alvo:** \`${provider}\`\n\n`,
      `#### Recursos Disponíveis do Agente no Windows:\n`,
      `1. **Execução Direta de Comandos**: Você pode rodar comandos de terminal digitando \`$ comando\` (exemplo: \`$ dir\` ou \`$ python --version\`).\n`,
      `2. **Conexão de Provedores de IA**: Para respostas geradas por IA em tempo real com **${modelName}**, cadastre sua chave em **Configurações > Chaves de API** ou defina a variável de ambiente correspondente (\`OPENAI_API_KEY\`, \`GEMINI_API_KEY\`, \`ANTHROPIC_API_KEY\`, \`DEEPSEEK_API_KEY\`).\n`,
      `3. **CLI Standalone**: O executável nativo do agente também está disponível na pasta \`bin/\` para uso direto no Prompt de Comando e PowerShell.\n\n`,
      `*O agente WisdAI está pronto para suas tarefas!*`
    ];

    let fullText = '';
    for (const chunk of chunks) {
      await new Promise(r => setTimeout(r, 60));
      fullText += chunk;
      this.sendToRenderer('engine:streamChunk', { text: chunk, messageId });
    }

    const msg = conv.messages.find(m => m.id === messageId);
    if (msg) {
      msg.text = fullText;
      this.saveConversations(this.getConversations());
    }

    this.sendToRenderer('engine:streamEnd', { messageId, text: fullText });
    return { success: true, text: fullText };
  }
}

module.exports = EngineManager;
