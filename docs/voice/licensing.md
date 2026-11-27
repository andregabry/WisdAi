# Matriz de Licenciamento Comercial e Conformidade Jurídica

> Objetivo: Garantir que o **WisdAI** e futuros produtos **WisdomUp** (`WisdMeet`, `WisdFin`, `WisdInvest`) possam distribuir o **WisdomUp Voice Intelligence Engine** comercialmente sem riscos de contaminação copyleft ou violação de termos de modelos.

---

## 1. Auditoria de Licenças dos Componentes e Candidatos

| Componente / Modelo | Licença Verificada | Uso Comercial Permitido? | Risco Copyleft? | Obrigações & Restrições | Decisão WisdAI |
|---|---|---|---|---|---|
| **Apple CoreAudio / AVFoundation / Speech / FoundationModels** | Apple Developer SDK License | **Sim** (em hardware Apple) | Não | Restrito a sistemas Apple (`macOS`/`iOS`) | **Adotado no adaptador macOS** |
| **OpenJarvis (Arquitetura/Padrões)** | **Apache-2.0** (`Copyright 2025 The OpenJarvis Authors`) | **Sim** | Não | Manter aviso de atribuição quando trechos/derivados forem adaptados; patente grant incluso | **Padrões adaptados com atribuição** |
| **Kokoro-82M** | **Apache-2.0** | **Sim** | Não | Preservar licença Apache-2.0 e créditos originais | **Candidato Principal TTS Expressivo Open-Source** |
| **CosyVoice** | **Apache-2.0** | **Sim** | Não | Verificar versão exata (v1/v2) e licenças dos pesos | **Candidato Alternativo para `>= 16 GB RAM`** |
| **Sesame CSM-1B** | **Apache-2.0** (com termo de acesso HF) | Sim (verificar termos HF específicos) | Não | Fraco em PT-BR/PT-PT | **Descartado p/ PT-BR** |
| **Whisper.cpp / MLX-Whisper / Faster-Whisper** | **MIT** | **Sim** | Não | Preservar copyright MIT | **Aprovados para plugins STT offline** |
| **Silero VAD** | **MIT** | **Sim** | Não | Preservar copyright MIT | **Aprovado** |
| **WebRTC VAD / RNNoise** | **BSD-3-Clause** | **Sim** | Não | Preservar aviso BSD-3 | **Aprovados** |
| **Smart Turn (Pipecat)** | **BSD-2-Clause** | **Sim** | Não | Preservar aviso BSD-2 | **Aprovado para evolução Turn-Taking** |
| **llama.cpp (Engine) / ONNX Runtime** | **MIT** | **Sim** | Não | Separar licença do motor da licença dos pesos GGUF | **Aprovados** |
| **Moshi (Kyutai)** | Código **MIT/Apache-2.0**; Pesos **CC-BY-4.0** | Sim c/ atribuição obrigatória | Não | Atribuição explícita CC-BY-4.0 obrigatória | Inviável em 8 GB RAM |
| **PersonaPlex (NVIDIA)** | Código **MIT**; **NVIDIA Open Model License** | Sim (rever cláusulas NVIDIA OML) | Não | Termos proprietários abertos NVIDIA nos pesos | Inviável em 8 GB RAM |
| **MiniCPM-o** | Apache-2.0 + **MiniCPM CLA** | Condicional (exige registro acima de limites de uso comercial) | Não | Restrição contratual de escala | Inviável em 8 GB RAM |
| **Piper TTS (`espeak-ng` + wrapper)** | **GPL-3.0-or-later** | Apenas compatível c/ GPL se linkado | **SIM (Copyleft forte)** | Exigiria abertura do código conectado ou isolamento estrito em processo separado sob GPL | **Excluído como padrão embutido no app proprietário** |
| **F5-TTS** | Código MIT; **Pesos/dados com cláusulas não-comerciais em checkpoints comuns** | **Risco em distribuição comercial** | Não | Restrições de uso comercial nos dados/pesos pré-treinados | **Rejeitado para distribuição comercial padrão** |

---

## 2. Política Estrita de Vozes e Clonagem (Seção 8)
- **Proibição absoluta de clonagem não autorizada:** Nenhuma voz humana real de terceiros nem vozes proprietárias comerciais (ChatGPT, Gemini, ElevenLabs) são clonadas ou amostradas.
- **Identidade original:** A identidade vocal WisdAI usa exclusivamente síntese autorizada do sistema operacional (`Apple Siri Natural / Enhanced`) ou pesos Apache-2.0 / MIT devidamente licenciados (`Kokoro-82M`).
