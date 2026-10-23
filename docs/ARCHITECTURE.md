# Arquitetura de Missão Crítica: Estação Autônoma de Ingestão e Backup Fotográfico (DIT)

> Projeto isolado: `auto-ingest-station`
> Objetivo: Ingestão de alta velocidade, incremental, com verificação de integridade criptográfica SHA-256, staging atômico e interface web local.

---

## 1. Princípios de Engenharia

Este projeto adota o padrão de **alta confiabilidade para dados de risco jurídico**. Toda e qualquer alteração neste repositório deve preservar as 7 invariantes abaixo:

### Invariantes Inegociáveis
1. **Somente-Leitura no Cartão de Origem (`Read-Only`):** O leitor de cartões é acessado sem nenhuma operação de escrita, modificação ou exclusão.
2. **Integridade Criptográfica Obrigatória (`SHA-256`):** Todo arquivo copiado deve ter seu hash verificado byte a byte antes de ser considerado concluído:
   $$\text{SHA256}(\text{Destino}) \equiv \text{SHA256}(\text{Origem})$$
3. **Escrita Atômica em Duas Etapas (`Staging & Commit`):** A cópia é gravada com extensão `.staging.tmp`. Se o cartão for desconectado durante a transferência, o arquivo incompleto é purgado e nunca promovido ao nome final.
4. **Ledger de Auditoria Append-Only (`manifest.jsonl` / `manifest.db`):** Toda foto gera um registro imutável com timestamp, serial do cartão, hash e status de validação.
5. **Idempotência Determinística:** Re-inserções do mesmo cartão ignoram fotos já salvas em milissegundos sem reprocessamento ou duplicação.
6. **Sinalização Auditiva e Visual Rígida:**
   - Sucesso total = Acorde sonoro Dó-Mi-Sol (ascendente) + Notificação Verde.
   - Falha ou corrupção = Alarme grave contínuo (Buzzer) + Notificação Vermelha Bloqueante.
7. **Pre-Flight Check de Armazenamento:** Bloqueio preventivo se o drive de destino não possuir espaço suficiente para as fotos novas + margem de 10%.

---

## 2. Estrutura do Repositório

```
auto-ingest-station/
├── docs/
│   ├── ARCHITECTURE.md       # Este documento
│   └── AGENTS.md             # Regras estritas para agentes de IA
├── src/
│   ├── IngestEngine.ps1      # Motor de cópia, hash, staging e ledger
│   ├── WebServer.ps1         # Servidor HTTP nativo com API REST
│   └── public/
│       └── index.html        # Dashboard visual moderno e reativo
├── tests/
│   ├── Run-Tests.ps1         # Suíte completa de testes automatizados
│   └── mock_data/            # Dados simulados para testes de estresse
└── README.md                 # Guia de uso e comandos
```
