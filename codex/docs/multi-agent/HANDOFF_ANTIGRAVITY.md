# Retomada do WisdCode no Antigravity

## Atualização de 22 de novembro de 2026

Antes de seguir as etapas históricas abaixo, leia `FRONTEND_PARITY.md` e a seção atual de `PROGRESS.md`. O pedido vigente é reproduzir o front e as interações do ChatGPT de referência. O utilizador condicionou a geração do instalador à validação completa. As etapas antigas de empacotamento abaixo ficam sujeitas a essa instrução mais recente. A prévia interna 0.7.0 tem lacunas registradas na matriz. `/Users/andregabry/Project/WisdCode` agora é um link para `/Users/andregabry/Project/WisdAI`.

## Onde continuar

- Repositório local em `/Users/andregabry/Project/WisdCode/codex`, branch `main`. Na preparação deste resumo, o último commit era `c122d13` (`Add desktop attachments, voice turns and account controls`).
- Há trabalho local a preservar em `README.md`, `desktop/macos/Info.plist`, `desktop/macos/WisdCode.swift`, `desktop/macos/build-dmg.sh` e `docs/multi-agent/PROGRESS.md`. `desktop/macos/DesktopPanels.swift` também faz parte do trabalho e ainda não está rastreado. Rode `git status --short --branch` e leia o diff antes de editar.
- A última entrega é o aplicativo nativo de macOS 0.6.0. O DMG está em `/Users/andregabry/Project/WisdCode/dist/WisdCode-Desktop-0.6.0-macos-arm64.dmg`.
- Leia `PROGRESS.md`, `ARCHITECTURE.md`, `COMPATIBILITY.md` e `IMPLEMENTATION_PLAN.md` neste diretório. O histórico de progresso inclui decisões de segurança e limitações de cada integração.

## Implementação e testes já realizados

- A interface SwiftUI tem chat, anexos, gravação e leitura de respostas por turnos e seleção de contas ChatGPT. A versão 0.6.0 acrescenta tarefas locais, biblioteca, catálogo de plugins e habilidades, Sites locais, revisão do Git e uso da conta. As tarefas agendadas são somente leitura e dependem de uma janela do app aberta.
- O DMG 0.6.0 foi compilado e verificado, e uma cópia instalada abriu com o servidor Codex incluído. O servidor respondeu às consultas de conta, uso, limites, plugins e habilidades.
- A execução de uma tarefa agendada, a revisão de código e a instalação de plugins pela interface ainda precisam de testes funcionais. O resgate de créditos envolve alteração real na conta. Use uma resposta simulada para validar o fluxo da interface.
- O handoff por checkpoint existe no terminal para uma cópia de trabalho isolada. A troca automática por cota, a aplicação das alterações ao projeto original e a seleção de contas externas no desktop continuam pendentes de implementação ou validação. O desktop 0.6.0 ainda tem lacunas em relação às capturas, incluindo agendamento na nuvem, Sites publicados e compartilhados e autorização de conectores.

## Próxima entrega

1. Use um repositório descartável para verificar os fluxos locais do desktop 0.6.0, começando por agendamento e revisão de alterações. Confirme o resultado da tarefa e o histórico exibido. Corrija falhas reproduzíveis na interface ou na comunicação com o servidor.
2. Para retomar a integração entre agentes, revise o checkpoint e a execução isolada existentes antes de alterar o seletor do desktop. Preserve as aprovações e o sandbox do Codex. Continue a partir de arquivos e decisões registradas e valide a retomada sem repetir etapas concluídas. Mantenha a troca autônoma desativada enquanto os limites de execução e escrita estiverem sem validação.
3. Registre em `PROGRESS.md` o que foi testado, o resultado e o que ficou pendente. Ao entregar mudanças no desktop, gere e valide um novo DMG nativo para Apple Silicon.

O EGM 0.1.1 está habilitado na CLI do Antigravity. Para uma revisão separada do plano de integração, use `/egm:egm-review docs/multi-agent/IMPLEMENTATION_PLAN.md` a partir da raiz do repositório.
