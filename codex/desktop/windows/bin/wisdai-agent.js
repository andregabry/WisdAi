#!/usr/bin/env node
/**
 * WisdAI CLI Agent - Autonomous Software Engineering Agent for Windows
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const os = require('os');

const CONFIG_DIR = path.join(os.homedir(), 'AppData', 'Roaming', 'WisdAI');
if (!fs.existsSync(CONFIG_DIR)) {
  fs.mkdirSync(CONFIG_DIR, { recursive: true });
}
const API_KEYS_PATH = path.join(CONFIG_DIR, 'api_keys.json');

function getApiKey(provider) {
  try {
    if (fs.existsSync(API_KEYS_PATH)) {
      const keys = JSON.parse(fs.readFileSync(API_KEYS_PATH, 'utf-8'));
      if (keys[provider]) return keys[provider];
    }
  } catch {}

  const envs = {
    openai: 'OPENAI_API_KEY',
    gemini: 'GEMINI_API_KEY',
    anthropic: 'ANTHROPIC_API_KEY',
    deepseek: 'DEEPSEEK_API_KEY'
  };
  return process.env[envs[provider]] || null;
}

function printBanner() {
  console.log('\x1b[1;36m');
  console.log('╔══════════════════════════════════════════════════════════╗');
  console.log('║           WisdAI Agent - Windows Terminal CLI            ║');
  console.log('║   Agente Autônomo de Engenharia de Software no Windows   ║');
  console.log('╚══════════════════════════════════════════════════════════╝');
  console.log('\x1b[0m');
  console.log(`Workspace: \x1b[33m${process.cwd()}\x1b[0m`);
  console.log(`Comandos: 'help', '$ <comando>', 'exit' ou faça uma pergunta.\n`);
}

async function handleCommand(cmd) {
  console.log(`\x1b[34m> Executando comando no Windows...\x1b[0m`);
  try {
    const isWin = process.platform === 'win32';
    const shell = isWin ? 'powershell.exe' : '/bin/sh';
    const output = execSync(cmd, { shell, encoding: 'utf-8', stdio: 'pipe' });
    console.log(output);
  } catch (err) {
    console.error(`\x1b[31m[Erro na execução]:\x1b[0m ${err.message}`);
    if (err.stdout) console.log(err.stdout);
    if (err.stderr) console.error(err.stderr);
  }
}

async function queryOpenAI(prompt, apiKey, model = 'gpt-4o') {
  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: 'system',
          content: 'Você é o WisdAI CLI Agent no Windows. Auxilie o usuário em programação, análise e automação com clareza e precisão.'
        },
        { role: 'user', content: prompt }
      ]
    })
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return data.choices[0]?.message?.content || 'Sem resposta.';
}

async function repl() {
  printBanner();
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: '\x1b[1;32mwisdai>\x1b[0m '
  });

  rl.prompt();

  rl.on('line', async (line) => {
    const input = line.trim();
    if (!input) {
      rl.prompt();
      return;
    }

    if (input === 'exit' || input === 'sair' || input === 'quit') {
      console.log('\x1b[90mEncerrando WisdAI Agent. Até mais!\x1b[0m');
      process.exit(0);
    }

    if (input === 'help' || input === 'ajuda') {
      console.log(`
Comandos Disponíveis:
  $ <comando>       Executa um comando local diretamente no PowerShell/cmd
  help / ajuda      Mostra este menu
  exit / sair       Encerra a sessão
  <qualquer texto>  Envia a instrução para o raciocínio do agente
`);
      rl.prompt();
      return;
    }

    if (input.startsWith('$ ')) {
      await handleCommand(input.slice(2));
      rl.prompt();
      return;
    }

    const openaiKey = getApiKey('openai');
    const geminiKey = getApiKey('gemini');
    const deepseekKey = getApiKey('deepseek');

    if (openaiKey) {
      try {
        process.stdout.write('\x1b[36mPensando...\x1b[0m\r');
        const reply = await queryOpenAI(input, openaiKey);
        console.log(`\r\x1b[1;34m[WisdAI]:\x1b[0m\n${reply}\n`);
      } catch (err) {
        console.error(`\x1b[31m[Erro API]:\x1b[0m ${err.message}`);
      }
    } else {
      console.log(`\x1b[33m[Modo Local]:\x1b[0m Solicitação recebida: "${input}"`);
      console.log(`Nenhuma chave de API configurada no momento.`);
      console.log(`Para ativar raciocínio completo com IA, defina a variável OPENAI_API_KEY, GEMINI_API_KEY ou DEEPSEEK_API_KEY.`);
      console.log(`Você pode executar comandos diretamente usando o prefixo '$ ' (ex: '$ dir').\n`);
    }

    rl.prompt();
  });
}

function main() {
  const args = process.argv.slice(2);
  if (args.length > 0) {
    const prompt = args.join(' ');
    const openaiKey = getApiKey('openai');
    if (openaiKey) {
      queryOpenAI(prompt, openaiKey)
        .then(res => console.log(res))
        .catch(err => {
          console.error(`Erro: ${err.message}`);
          process.exit(1);
        });
    } else {
      console.log(`[WisdAI Agent]: ${prompt}`);
    }
  } else {
    repl();
  }
}

main();
