# WisdAI V5 — Migração de Configurações, Cache & Publicação

---

## 1. Migração Automática de `UserDefaults` (`UnifiedVoiceConfig.loadMigrated`)

Na primeira inicialização após atualização para V5:
- A chave unificada `wisdai.voice.unifiedConfig.v5` é gerada automaticamente caso ainda não exista.
- Se houver conflito entre chaves herdadas (`wisdcode.voice.gender == "male"` coexistindo com `wisdai.voice.kokoroPreset == "pf_dora"` ou ausência de `wisdai.voice.identity.v1`):
  - Promove automaticamente a identidade para **`JARVIS` (`.jarvis`, `.male`)** com speaker masculino válido (`pm_alex` no Kokoro-82M ou `supertonic:m2` no Supertonic-3), eliminando o bug P0 de voz feminina travada.
- Qualquer alteração posterior em qualquer tela grava `wisdai.voice.unifiedConfig.v5` e espelha coerentemente `wisdcode.voice.*` + `wisdai.voice.*`.

---

## 2. Isolamento de Cache V5

- Diretórios antigos de `~/Library/Application Support/WisdAI/Voice/VocalizationCache/` que não comecem com `v5_` são removidos automaticamente uma única vez (`wisdai.voice.v5.cachePurgedLegacy`).
- Todos os clips novos são isolados por assinatura SHA-256 contendo motor, modelo, versão, identidade, speaker, preferência, idioma, cadência e configuração de prosódia.

---

## 3. Instalação de Modelo Local & Publicação

- O modelo neural `sherpa-onnx-supertonic-3-tts-int8-2026-05-11` (`122.8 MB`, SHA-256 `82fa96f91c4ef8abaae3a14a3f4153facf88bed821d1f7331cec2700f432c427`) também pode ser baixado sob consentimento explícito diretamente pelo Catálogo de Modelos no Laboratório de Voz reutilizando o runtime `sherpa-onnx-v1.13.8-arm64` já existente.
- Branch dedicada: **`feature/voice-identity-jarvis-v5`** (sem merge automático na `main` até revisão e aprovação final da identidade vocal pelo utilizador).
