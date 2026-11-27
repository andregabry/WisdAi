// WisdAI Desktop Renderer Application Logic

document.addEventListener('DOMContentLoaded', async () => {
  // DOM Elements
  const winMinBtn = document.getElementById('winMinBtn');
  const winMaxBtn = document.getElementById('winMaxBtn');
  const winCloseBtn = document.getElementById('winCloseBtn');
  const engineBadge = document.getElementById('engineBadge');

  const navItems = document.querySelectorAll('.nav-item[data-view]');
  const viewPanels = document.querySelectorAll('.view-panel');
  const newChatBtn = document.getElementById('newChatBtn');
  const conversationList = document.getElementById('conversationList');
  const chatHistory = document.getElementById('chatHistory');
  const welcomeContainer = document.getElementById('welcomeContainer');
  const promptInput = document.getElementById('promptInput');
  const sendBtn = document.getElementById('sendBtn');
  const modelSelect = document.getElementById('modelSelect');
  const effortSelect = document.getElementById('effortSelect');
  const promptCards = document.querySelectorAll('.prompt-card');
  const spaceGrid = document.getElementById('spaceGrid');

  // Settings DOM
  const openSettingsBtn = document.getElementById('openSettingsBtn');
  const settingsModal = document.getElementById('settingsModal');
  const closeSettingsModalBtn = document.getElementById('closeSettingsModalBtn');
  const settingsNavItems = document.querySelectorAll('.settings-nav-item');
  const settingsTabPanels = document.querySelectorAll('.settings-tab-panel');
  const settingsTabTitle = document.getElementById('settingsTabTitle');
  const themeCards = document.querySelectorAll('.theme-card');

  // State
  let activeConversationId = null;
  let conversations = [];
  let isStreaming = false;

  // Window Controls
  winMinBtn?.addEventListener('click', () => window.wisdAI?.minimizeWindow());
  winMaxBtn?.addEventListener('click', () => window.wisdAI?.maximizeWindow());
  winCloseBtn?.addEventListener('click', () => window.wisdAI?.closeWindow());

  // Listen to engine status
  window.wisdAI?.onEngineStatus((status) => {
    if (status.ready) {
      engineBadge.textContent = status.mode === 'native' ? 'Nativo Windows' : 'Multi-Provedor';
      engineBadge.style.color = '#10a37f';
      engineBadge.style.borderColor = 'rgba(16, 163, 127, 0.4)';
    } else {
      engineBadge.textContent = 'Desconectado';
      engineBadge.style.color = '#ef4444';
      engineBadge.style.borderColor = 'rgba(239, 68, 68, 0.4)';
    }
  });

  // Navigation switching
  navItems.forEach(item => {
    item.addEventListener('click', () => {
      const view = item.getAttribute('data-view');
      navItems.forEach(i => i.classList.remove('active'));
      item.classList.add('active');

      viewPanels.forEach(p => p.classList.remove('active'));
      const targetPanel = document.getElementById(`${view}View`);
      if (targetPanel) targetPanel.classList.add('active');
    });
  });

  // Settings modal
  openSettingsBtn?.addEventListener('click', () => {
    settingsModal.classList.add('active');
    loadSettingsData();
  });

  closeSettingsModalBtn?.addEventListener('click', () => {
    settingsModal.classList.remove('active');
  });

  settingsModal?.addEventListener('click', (e) => {
    if (e.target === settingsModal) {
      settingsModal.classList.remove('active');
    }
  });

  settingsNavItems.forEach(item => {
    item.addEventListener('click', () => {
      const tab = item.getAttribute('data-tab');
      settingsNavItems.forEach(i => i.classList.remove('active'));
      item.classList.add('active');

      settingsTabPanels.forEach(p => p.classList.remove('active'));
      const activePanel = document.getElementById(`tab-${tab}`);
      if (activePanel) activePanel.classList.add('active');
      if (settingsTabTitle) settingsTabTitle.textContent = item.textContent;
    });
  });

  // Theme Switching
  themeCards.forEach(card => {
    card.addEventListener('click', () => {
      themeCards.forEach(c => c.classList.remove('active'));
      card.classList.add('active');
      const theme = card.getAttribute('data-theme');
      if (theme === 'light') {
        document.body.classList.remove('theme-dark');
        document.body.classList.add('theme-light');
      } else {
        document.body.classList.remove('theme-light');
        document.body.classList.add('theme-dark');
      }
    });
  });

  // API Key Saving
  document.querySelectorAll('.btn-save[data-provider]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const provider = btn.getAttribute('data-provider');
      const input = document.getElementById(`key-${provider}`);
      if (input && input.value) {
        await window.wisdAI?.saveApiKey(provider, input.value.trim());
        btn.textContent = 'Salvo!';
        const status = document.getElementById(`status-${provider}`);
        if (status) {
          status.textContent = 'Configurada';
          status.classList.add('configured');
        }
        setTimeout(() => { btn.textContent = 'Salvar'; }, 2000);
      }
    });
  });

  // Load Initial Settings Data
  async function loadSettingsData() {
    if (!window.wisdAI) return;
    const keys = await window.wisdAI.getApiKeys();
    ['openai', 'gemini', 'anthropic', 'deepseek'].forEach(p => {
      const status = document.getElementById(`status-${p}`);
      if (status && keys[p]) {
        status.textContent = 'Configurada';
        status.classList.add('configured');
      }
    });

    const accounts = await window.wisdAI.listAccounts();
    const accountsList = document.getElementById('settingsAccountsList');
    if (accountsList) {
      accountsList.innerHTML = accounts.map(acc => `
        <div class="api-key-item">
          <div class="api-key-header">
            <span>${acc.label} (${acc.email})</span>
            <span class="api-status ${acc.active ? 'configured' : ''}">${acc.active ? 'Ativa' : 'Inativa'}</span>
          </div>
        </div>
      `).join('');
    }
  }

  // Load Conversations
  async function loadConversations() {
    if (!window.wisdAI) return;
    conversations = await window.wisdAI.listConversations();
    renderConversationList();

    if (conversations.length > 0 && !activeConversationId) {
      selectConversation(conversations[0].id);
    }
  }

  function renderConversationList() {
    if (!conversationList) return;
    conversationList.innerHTML = conversations.map(c => `
      <div class="conversation-item ${c.id === activeConversationId ? 'active' : ''}" data-id="${c.id}">
        <span class="conv-title">${escapeHTML(c.title || 'Nova conversa')}</span>
        <button class="conv-delete-btn" title="Excluir conversa">✕</button>
      </div>
    `).join('');

    conversationList.querySelectorAll('.conversation-item').forEach(item => {
      const id = item.getAttribute('data-id');
      item.addEventListener('click', (e) => {
        if (!e.target.classList.contains('conv-delete-btn')) {
          selectConversation(id);
        }
      });

      const delBtn = item.querySelector('.conv-delete-btn');
      delBtn?.addEventListener('click', async (e) => {
        e.stopPropagation();
        if (confirm('Tem certeza que deseja excluir esta conversa?')) {
          await window.wisdAI?.deleteConversation(id);
          conversations = conversations.filter(c => c.id !== id);
          if (activeConversationId === id) {
            activeConversationId = conversations[0]?.id || null;
          }
          renderConversationList();
          if (activeConversationId) selectConversation(activeConversationId);
          else renderMessages([]);
        }
      });
    });
  }

  function selectConversation(id) {
    activeConversationId = id;
    renderConversationList();
    const conv = conversations.find(c => c.id === id);
    if (conv) {
      renderMessages(conv.messages || []);
    }
  }

  // New Chat
  newChatBtn?.addEventListener('click', async () => {
    if (!window.wisdAI) return;
    const newConv = await window.wisdAI.startConversation({ title: 'Nova conversa' });
    conversations.unshift(newConv);
    selectConversation(newConv.id);
  });

  // Prompt suggestions
  promptCards.forEach(card => {
    card.addEventListener('click', () => {
      const text = card.getAttribute('data-prompt');
      if (promptInput) {
        promptInput.value = text;
        promptInput.focus();
        handleSend();
      }
    });
  });

  // Auto-resize prompt input
  promptInput?.addEventListener('input', () => {
    promptInput.style.height = 'auto';
    promptInput.style.height = `${Math.min(promptInput.scrollHeight, 200)}px`;
  });

  promptInput?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  });

  sendBtn?.addEventListener('click', handleSend);

  async function handleSend() {
    if (!promptInput || isStreaming) return;
    const text = promptInput.value.trim();
    if (!text) return;

    if (!activeConversationId) {
      const newConv = await window.wisdAI.startConversation({ title: text.slice(0, 30) });
      conversations.unshift(newConv);
      activeConversationId = newConv.id;
    }

    promptInput.value = '';
    promptInput.style.height = 'auto';

    // Append user message to DOM
    if (welcomeContainer) welcomeContainer.style.display = 'none';
    appendMessageDOM('user', text);

    // Prepare assistant message bubble for streaming
    const assistantBody = appendMessageDOM('assistant', '');
    isStreaming = true;

    // Stream handler
    const removeChunkListener = window.wisdAI.onStreamChunk((chunk) => {
      if (assistantBody) {
        assistantBody.innerHTML = formatMarkdown(assistantBody.getAttribute('data-raw-text') + chunk.text);
        assistantBody.setAttribute('data-raw-text', assistantBody.getAttribute('data-raw-text') + chunk.text);
        chatHistory.scrollTop = chatHistory.scrollHeight;
      }
    });

    assistantBody.setAttribute('data-raw-text', '');

    try {
      await window.wisdAI.sendTurn({
        conversationId: activeConversationId,
        message: text,
        model: modelSelect?.value || 'gpt-4o'
      });
    } catch (err) {
      if (assistantBody) {
        assistantBody.innerHTML += `<div style="color: #ef4444; margin-top: 8px;">Erro: ${escapeHTML(err.message)}</div>`;
      }
    } finally {
      isStreaming = false;
      removeChunkListener();
      loadConversations();
    }
  }

  function appendMessageDOM(author, text) {
    const row = document.createElement('div');
    row.className = `message-row ${author}`;

    const avatar = document.createElement('div');
    avatar.className = 'message-avatar';
    avatar.textContent = author === 'user' ? 'U' : 'W';

    const body = document.createElement('div');
    body.className = 'message-body';
    body.innerHTML = formatMarkdown(text);

    row.appendChild(avatar);
    row.appendChild(body);
    chatHistory.appendChild(row);
    chatHistory.scrollTop = chatHistory.scrollHeight;
    return body;
  }

  function renderMessages(messages) {
    chatHistory.innerHTML = '';
    if (!messages || messages.length === 0) {
      if (welcomeContainer) {
        welcomeContainer.style.display = 'flex';
        chatHistory.appendChild(welcomeContainer);
      }
      return;
    }

    messages.forEach(m => {
      appendMessageDOM(m.author, m.text);
    });
  }

  // Space items
  async function loadSpaceItems() {
    if (!window.wisdAI || !spaceGrid) return;
    const items = await window.wisdAI.listSpaceItems();
    spaceGrid.innerHTML = items.map(item => `
      <div class="space-card">
        <div style="font-size: 24px;">📄</div>
        <div style="font-weight: 500; font-size: 14px;">${escapeHTML(item.name)}</div>
        <div style="font-size: 12px; color: var(--text-muted);">${item.date} · ${item.size}</div>
      </div>
    `).join('');
  }

  // Markdown formatter helper
  function formatMarkdown(text) {
    if (!text) return '';
    let html = escapeHTML(text);
    // Bold
    html = html.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
    // Code inline
    html = html.replace(/`(.*?)`/g, '<code>$1</code>');
    // Code block
    html = html.replace(/```([\s\S]*?)```/g, '<pre><code>$1</code></pre>');
    // Newlines
    html = html.replace(/\n/g, '<br>');
    return html;
  }

  function escapeHTML(str) {
    return (str || '').replace(/[&<>'"]/g, 
      tag => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[tag] || tag)
    );
  }

  // Initialize
  await loadConversations();
  await loadSpaceItems();
});
