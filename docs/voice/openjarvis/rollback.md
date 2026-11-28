# Guia de Rollback Seguro

A integração nativa OpenJarvis foi desenvolvida exclusivamente na branch `feature/openjarvis-native-integration`, criada a partir da branch/commit estável anterior `feature/voice-identity-jarvis-v5` (`5e33caf10577b4425bfa1afd29ec32c65cc7b8af`), **sem tocar em `main`**.

## 1. Quando acionar o rollback

Acione apenas se for necessário restaurar integralmente o binário/subsistema V5–V6 anterior sem o runtime OpenJarvis.

## 2. Procedimento para restaurar o código-fonte anterior

1. Verificar ausência de alterações não salvas na branch atual:
   ```bash
   git -C /Users/andregabry/Project/WisdAI status
   ```
2. Retornar para a branch base preservada ou restaurar a partir do commit base `5e33caf10577b4425bfa1afd29ec32c65cc7b8af`:
   ```bash
   git -C /Users/andregabry/Project/WisdAI checkout feature/voice-identity-jarvis-v5
   # ou criar uma branch de restauração explícita sem alterar o histórico da feature:
   git -C /Users/andregabry/Project/WisdAI checkout -b recovery/voice-v5 5e33caf10577b4425bfa1afd29ec32c65cc7b8af
   ```
3. Recompilar e reinstalar `/Applications/WisdAI.app` usando os binários `codex` e `codex-code-mode-host` de suporte:
   ```bash
   /Users/andregabry/Project/WisdAI/codex/desktop/macos/build-dmg.sh <codex> <WisdAI.dmg> <codex-code-mode-host>
   ```
4. Validar novamente as suítes V5–V6 (`run-state-smoke.sh`, `run-recovery-smoke.sh`, `run-voice-smoke.sh`, `run-agentic-voice-e2e.sh`).

## 3. Limpeza opcional de artefatos do OpenJarvis em disco

O runtime OpenJarvis fica estritamente isolado em um único diretório de usuário e **não altera** bancos de conversas (`Chats/`), projetos (`Projects/`), chaveiros nem dados do `WisdMeet`:

```bash
rm -rf "$HOME/Library/Application Support/WisdAI/OpenJarvis"
```

## 4. Reversão seletiva via Git (preservando demais evoluções)

Se quiser apenas desativar o OpenJarvis em builds locais mantendo a estrutura na árvore:
- No checkout atual, todos os novos arquivos residem isolados em `codex/desktop/macos/OpenJarvisBridge.swift`, `codex/desktop/macos/OpenJarvisWorkspaceAdapter.swift`, `codex/desktop/macos/OpenJarvisRuntime/` e `docs/voice/openjarvis/`.
- Um `git revert <commit-integracao>` desfaz toda a substituição de forma atômica.
