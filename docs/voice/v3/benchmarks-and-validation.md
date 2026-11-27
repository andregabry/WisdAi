# Benchmarks, Cenários Obrigatórios e Validação Comparativa V2 vs V3

**Data:** 2026-11-27  
**Hardware:** Apple M2, 8.0 GB RAM unificada, macOS 27.0.1 (`26A434`)  
**Stack Ativa:** `Qwen3-1.7B-Q4_K_M` (`llama.cpp Metal b12809`), `Kokoro-82M INT8` (`pf_dora` e `pm_alex`), `SpeechAnalyzer` (`pt-BR`), CoreAudio `Alto-falantes (MacBook Pro)`.

---

## 1. Suítes de Regressão Executadas Após Últimas Edições

- `./codex/desktop/macos/tests/run-voice-smoke.sh` → **`VOICE_SMOKE_ALL_PASS`** (inclui `PASS: V3 Behavior Engine, Acoustic F0, Cache (Kokoro hit=0.002ms) & Priority Audio`)
- `./codex/desktop/macos/tests/run-state-smoke.sh` → **`PASS`**
- `./codex/desktop/macos/tests/run-recovery-smoke.sh` → **`PASS`**

---

## 2. Resultados dos 6 Cenários Obrigatórios (Seção 16)

Todos executados ponta a ponta em `scratch/voice_v3_eval_bench.swift` com saída `BENCH_V3_ALL_SCENARIOS_PASS`:

1. **Escuta Prolongada (30 segundos com pausas naturais):**
   - Emitidos **2 feedbacks contextuais** no tempo exato de micro-pausas (`10.0s: "Entendi…"` entregue ao hardware CoreAudio em **17.3 ms**; `21.5s: "Ah, sim!"` entregue em **21.0 ms**).
   - Zero interrupções prematuras, FSM permaneceu em `.userSpeaking`, memória de sessão `VoiceMemoryStore` manteve `0` contaminações.
2. **Reflexão (problema técnico complexo):**
   - `ConversationalBehaviorPlanner` planejou `intent=reflection`, `behavior=think_then_speak`, `expression=thoughtful`, acionando o clipe em cache `"Boa pergunta."` em **0.115 ms** (lookup em memória) enquanto o `Qwen3-1.7B-Q4_K_M` iniciou a resposta sem vazar JSON nem tags comportamentais.
   - Turno subsequente consecutivo suprimiu nova interjeição automática (anti-repetição verificada).
3. **Interrupção (Barge-In sobre resposta principal + canal auxiliar):**
   - Interrupção durante fala ativa no `outputJitterBuffer` + `auxiliaryVocalizationBuffer` concluiu flush de ambos os canais em **0.008 ms** (`bothChannelsCleared=true`).
4. **Silêncio Prolongado (15 segundos):**
   - `spontaneousVocalizations=0`, zero ativações espúrias.
5. **Conversação Técnica Multi-Turno Coerente:**
   - Múltiplos turnos arquiteturais em 8 GB RAM mantiveram contexto integral e adaptação prosódica estável (`0` erros/fallbacks).
6. **Agentes em Segundo Plano (`agy --mode plan --sandbox`):**
   - Consulta somente leitura paralela concluiu (`agyLen=79`, `workspaceUnchanged=true`) mantendo `persona=aurora` e `kokoroPreset=pf_dora` inalterados.

---

## 3. Comparação Empírica: V2 vs V3 com Behavior Engine + Cache vs Apple Natural

| Configuração Avaliada | Tempo Síntese Frase Teste | Latência de Reação Vocal (Cache) | Memória Adicional da Cache | Características Observadas |
| :--- | :---: | :---: | :---: | :--- |
| **Voice Intelligence V2 (Baseline Kokoro `pf_dora`)** | **9003 ms** (`654 KB` WAV) | — *(sem cache)* | 0 MB | Lê integralmente aberturas formais (`"Certamente! Aqui está..."`), números de lista e fechamentos genéricos (`"Se precisar de mais..."`). |
| **Voice Intelligence V3 (Kokoro `pf_dora` + Behavior + Cache)** | **5510 ms** (`391 KB` WAV · **-38.8%**) | **0.002–0.115 ms** lookup · **17.3–21.0 ms** render + DAC | **0.71 MB** (`11` clipes) | Remove artificialismos, suaviza fluxo oral preservando termos técnicos, aplica `silence_scale` contextual (`0.30` em reflexão `pm_alex`, `5579 ms`), reage em `<25 ms` na escuta ativa. |
| **Apple Voz Natural PCM + Composição V3 (`pt-BR`)** | **1443 ms** (`405 KB` WAV) | Compartilha infra cache quando selecionada | Compatível | Síntese mais rápida e suporte a `pt-PT` (`Joana`), porém prosódia mais mecânica comparada ao timbre neural do `Kokoro-82M`. |

### Pegada Total de Recursos em Execução Simultânea (M2 8 GB)
- **App + Kokoro-82M + Vocalization Cache (11 clipes):** `418.8 MB` (cache isolada = `0.71 MB`)
- **`llama-server` Metal (`Qwen3-1.7B-Q4_K_M`):** `316.3 MB`
- **Total da Pilha de Voz:** **`735.1 MB`** dentro dos 8.0 GB unificados.

---

## 4. Limitações Honestas & Amostras para Avaliação Auditiva Humana

- **Comparação com ChatGPT Voice:** Não declaramos paridade integral com o modo de voz proprietário do ChatGPT; embora a V3 reduza drasticamente o tempo de reação da escuta ativa (<25 ms), remova formalismos e introduza contorno F0 + prosódia contextual, modelos S2S end-to-end como Moshi/MiniCPM-o exigem mais memória unificada (16–32+ GB) para entoação neural totalmente livre em tempo real.
- **Avaliação auditiva humana pendente com você:** Foram geradas 5 amostras `.wav` comparáveis no diretório de artefatos (`voice_samples_v3/`) além dos controles interativos na aba **Comportamento V3** do aplicativo instalado (`/Applications/WisdAI.app`) para aprovação humana direta da naturalidade entre `V2`, `V3 (pf_dora / pm_alex)` e `Apple Natural`.
