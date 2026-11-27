# Paridade visual com a referência ChatGPT

## Critério de entrega

Em 22 de novembro de 2026, o utilizador pediu a reprodução fiel do front do ChatGPT aberto e autenticado no Chrome, incluindo telas, menus, configurações e comportamento visual. Em seguida, condicionou a geração do instalador à verificação completa dessas áreas. A entrega completa permanece pendente.

A pasta do projeto agora resolve para `/Users/andregabry/Project/WisdAI`. `/Users/andregabry/Project/WisdCode` é um link para essa pasta. O cliente em desenvolvimento continua em `codex/desktop/macos`.

## Referência observada

A inspeção pela interface do Chrome identificou a barra lateral estreita, Início, Espaço, Agendado, Plugins, Explorar e Sites. O início mostra projetos fixados, projetos, chats recentes, Chat/Work, chat temporário, entrada central, anexos, potência, microfone e voz. O menu Explorar contém Projetos, Imagens, Sites, Mapas, GPTs, Figma e Codex.

Foram lidas a página de Plugins com categorias e itens instalados, a galeria de sugestões de tarefas e as categorias das configurações. Aparência expõe modo, personalização de tema, cores e opções avançadas. Essa tela contém mais controles do que a primeira implementação local.

O utilizador concluiu a entrada no Espaço e confirmou que estava pronto. A inspeção seguinte leu a biblioteca autenticada: navegação Tudo, Seus itens, Compartilhados com você, Espaços, Recentes e Lixeira; abas Sugestões, Páginas, Slides, Planilhas, Imagens e Sites; pesquisa, criação, grade/lista, seleção e ações por arquivo. A captura de Sites mostrou o estado vazio e o botão de criação. Os nomes e conteúdos privados dessa conta não foram copiados para o aplicativo. Algumas capturas do Chrome mostraram uma tela anterior à árvore de acessibilidade; o menu Criar não abriu de forma verificável pela automação. A comparação pixel a pixel de todas as páginas ainda precisa de capturas estáveis.

## Situação de cada área

| Área | Situação local | Validação e diferença pendente |
| --- | --- | --- |
| Início | Layout nativo reformulado, barra de ícones, sidebar e entrada central | App compilado aberto e inspecionado. Tipografia, ícones próprios de projetos e medidas em todas as larguras ainda precisam de comparação completa. |
| Projetos | Criar/editar nome, pastas, ícone/emoji, fixar, menus visíveis e remoção local confirmada | Criação, emoji, edição, cancelamento e remoção passaram na interface isolada. Teste de estado confirmou preservação dos arquivos. Ordem/seções e equivalência completa à referência permanecem pendentes. |
| Recentes e pesquisa | Histórico real e pesquisa em modal | Pesquisa por `multi-agent` retornou a conversa correspondente. |
| Chats | Menus visíveis, renomear, arquivar/restaurar e excluir permanentemente com confirmação | O motor real passou no ciclo completo em CODEX_HOME e Git descartáveis, sem inferência. Nenhuma conversa privada foi excluída. Confirmação visual de exclusão de chat ainda precisa de teste com fixture na UI. |
| Chat/Work | Alterna a apresentação do compositor e os controles do projeto | O motor de execução continua sendo Codex nos dois modos. Paridade com os modos do serviço ChatGPT permanece pendente. |
| Chat temporário | Usa `ephemeral` em `thread/start` | O servidor aceitou um thread temporário somente leitura num Git descartável. Nenhum turno de inferência foi submetido nesse teste. |
| Modelos e potência | Lista retornada pelo servidor em popover | Menu aberto no app. Corrigidos botões com bordas nativas e textos de potência truncados. A troca automática entre modelos reais passou no mesmo chat com limite injetado e tarefa descartável; persistência de todas as opções ainda precisa de teste completo. |
| Anexos | Menu, seleção e entradas existentes preservados | Menu aberto. Anexar e enviar imagem/áudio/texto ainda precisa de regressão pela nova interface. |
| Voz | Painel de áudio por turnos e leitura de resposta | Abertura e fechamento passaram. A sessão de voz ao vivo do ChatGPT continua sem integração. |
| Agendado | Editor local, pausa, execução e 32 sugestões | Abertura de sugestão e cancelamento passaram. Execução continua local e depende do app aberto. Agendamento na nuvem permanece pendente. |
| Espaço | Nova navegação, abas por tipo, pesquisa, grade/lista, seleção, favoritos, espaços locais e lixeira recuperável | A biblioteca anterior passou em importação, favorito, filtro, lista e remoção. A nova tela abriu no app, exibiu menu Criar e validou formulário de espaço vazio/preenchido/cancelado. Importação, favoritos, pesquisa, lista, lixeira e restauração passaram com um TXT descartável; o conteúdo original permaneceu intacto. Persistência da nova lixeira entre reinícios ainda precisa de teste conjunto. Páginas colaborativas, modelos de documentos e compartilhamento remoto permanecem pendentes. |
| Imagens | Filtro da biblioteca local | Galeria, geração, edição e estados próprios da referência ainda precisam de implementação ou validação. |
| Plugins | Catálogo real, categorias, logos e detalhes | Leitura do catálogo real retornou 100 itens na prévia. Categorias, logos e detalhes foram acrescentados depois da primeira inspeção. Instalação, autorização e comportamento final ainda precisam de teste. |
| Habilidades | Listagem e ativação pelo motor | Navegação visual implementada. Ativação e desativação ainda precisam de teste. |
| Sites | Aba dentro do Espaço com pastas locais, preparação de pedido no chat e prévia de index.html | Referência acessível com estado vazio conferido. Publicação e compartilhamento equivalentes à referência permanecem pendentes. |
| Mapas e GPTs | Entradas e estados de integração pendente | As interfaces completas permanecem pendentes. |
| Figma | Acesso ao catálogo filtrado | A interface e o fluxo completos permanecem pendentes. |
| Conta e perfil | Modal agrupada por provedor; múltiplos perfis; sessões OpenAI reais; catálogos por conta; APIs com Keychain | Uma sessão real e quatro modelos do motor foram exibidos. Múltiplos perfis e isolamento passaram nos testes locais. Retomada automática entre modelos passou com inferência real e limite injetado. Troca entre contas passou em fixtures; duas sessões reais, APIs com chave e execução externa ainda não foram validadas. |
| Uso e faturamento | Dados do motor e fluxo existente de redefinição | Consulta de limites passou. Histórico completo, compra, recarga e demais comportamentos da referência permanecem pendentes. |
| Aparência | Escuro, claro e sistema | Alternância claro/escuro conferida visualmente no app e restaurada para escuro. Cores livres, fontes e controles avançados permanecem pendentes. |
| Configurações restantes | Navegação agrupada e algumas páginas locais | Notificações, controles parentais, mascotes, senhas, nuvem e outros estados completos ainda precisam de implementação e teste. |
| Responsividade e teclado | Layouts nativos com largura mínima de 820 pontos | Pesquisa e fechamento de popover por Escape foram exercitados. Matriz de larguras, foco e atalhos completa permanece pendente. |

## Artefatos e testes

- Os arquivos Swift da primeira prévia passaram na verificação de tipos para macOS arm64 e na compilação otimizada da prévia.
- A prévia abriu com o motor incluído e a assinatura ad hoc foi verificada. A validação de execução real identificou que o fallback sem Code Mode não produzia os arquivos solicitados. A prévia 0.7.1 exige `codex-code-mode-host` compatível ao lado do motor; o empacotador e a inicialização recusam a dependência ausente. O helper oficial instalado foi validado com o fork no teste descartável.
- O teste de protocolo com o mesmo motor passou em inicialização, modelos, chats arquivados, conta, limites e criação de thread temporário somente leitura. Esse teste terminou o subprocesso e utilizou um repositório descartável.
- O DMG criado antes da instrução de aguardar está identificado como `dist/preview-0.7.0/PROTOTYPE-NOT-VALIDATED-0.7.0.dmg`. Ele corresponde à primeira prévia, anterior às últimas correções, e não representa uma entrega aprovada. Os testes posteriores usam somente a cópia local do app nessa pasta.

## Continuação

A entrada no Espaço foi concluída. Continuar a inspeção dos menus, modelos de documentos e edição de artefatos sem alterar os arquivos privados da referência. Completar as páginas e interações ainda pendentes na tabela, repetir os testes onde houver alteração e registrar evidências de comparação por tela e largura. A geração do instalador final aguarda o cumprimento do critério definido pelo utilizador.

## Validação de 23 de novembro de 2026

Consulte a seção de gestão de projetos, chats e contas em `PROGRESS.md`. A prévia isolada está em `dist/validation-2026-11-23/WisdAI.app` e não é um instalador nem uma entrega de paridade completa. A consulta de modelos não equivale à verificação de cota ou autorização de inferência. Os perfis externos sem adaptador ficam identificados como configuração pendente.
