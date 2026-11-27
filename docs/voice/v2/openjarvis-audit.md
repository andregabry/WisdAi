# Auditoria Honesta de Referência — OpenJarvis (`HEAD 0cdafabb`)

**Repositório inspecionado:** `stanford-scaling-intelligence/OpenJarvis`  
**Commit HEAD verificado na sessão:** `0cdafabb320a3b29219fc9be81d3285269f5436d` (`2026-11-27T06:11:38Z`, `958` arquivos sob `src/openjarvis/`)

---

## 1. O Que Foi Realmente Inspecionado vs Adaptado no WisdAI

1. **`kokoro_tts.py` (Mapeamento Kokoro PT-BR):**
   - **Verificado no OpenJarvis:** mapeia explicitamente o código `"p"` no frontend Kokoro para Português Brasileiro (`pt-BR`) e não para Português Europeu.
   - **Aplicação honesta no WisdAI:** como o runtime C/C++ nativo embarcado no `sherpa-onnx v1.13.8` (`piper-phonemize` / `espeak-ng`) utiliza identificação de voz `"pt-br"` (`espeak-ng-data/lang/roa/pt-BR`) em vez da abreviação `"p"` do wrapper Python `kokoro` (`misaki`), o código C++ do WisdAI passa `"pt-br"` e mantém honestamente bloqueado `pt-PT` no Kokoro (encaminhando `pt-PT` para `Apple Voz Natural`).
2. **`complexity.py` (Roteamento por Complexidade e Ação):**
   - **Inspiração conceitual:** separação entre consultas locais diretas e consultas complexas/delegação sem depender somente de contagem bruta de palavras.
   - **Implementação Swift nativa (`LocalIntelligenceEngine.swift`):** `computeSemanticComplexityScore` combina pontuação sintática, conectores causais/técnicos e separação explícita entre perguntas conceituais e comandos de workspace (`VoiceDelegationDispatchResult`).
3. **`hybrid.py` (Reciprocal Rank Fusion — RRF) e `energy_apple.py` (`zeus_apple_silicon` IOReport):**
   - **Avaliados e NÃO copiados diretamente:** o núcleo de memória local do WisdAI utiliza SQLite FTS5 (`VoiceSQLiteKnowledgeStore`) com quarentena `.untrusted` em Swift puro, e a telemetria de recursos utiliza `ProcessResourceProbe` (`TASK_VM_INFO`, `task_threads`, GPU Metal recomendada via `MTLCreateSystemDefaultDevice`), evitando dependências Python privilegiadas (`zeus_apple_silicon` / `IOReport`) no app desktop macOS.

---

## 2. Transparência de Atribuição

- Nenhum código Python do `OpenJarvis` foi copiado ou embutido no app WisdAI.
- Todo o código em `codex/desktop/macos/` é Swift nativo + chamada C ABI `dlopen` para `sherpa-onnx` (`Apache-2.0`) e HTTP loopback local para `llama-server` (`MIT`), respeitando integralmente as licenças de cada projeto.
