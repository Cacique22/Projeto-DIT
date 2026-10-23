# AGENTS.md - Regras de Desenvolvimento para Agentes de IA

Este documento define as regras obrigatórias para qualquer agente de IA ou desenvolvedor trabalhando no repositório **`auto-ingest-station`**.

---

## 1. Regra de Ouro: Execução Obrigatória de Testes a Cada Atualização

> ⚠️ **MANDATÓRIO:** Toda e qualquer alteração de código neste repositório **DEVE ser sucedida pela execução imediata da suíte de testes automatizados**:
> ```powershell
> .\tests\Run-Tests.ps1
> ```
> Se qualquer teste falhar, a alteração é considerada inválida e deve ser corrigida imediatamente antes de qualquer entrega.

---

## 2. Invariantes do Código

1. **Nunca use `Copy-Item` simples sem validação:** Cópia de mídia de missão crítica exige validação de tamanho e hash SHA-256 de ponta a ponta.
2. **Nunca promova arquivos sem Staging:** Arquivos em transferência devem ter a extensão `.staging.tmp` até que o hash seja verificado com sucesso.
3. **Nunca sobrescreva o manifesto:** O manifesto de auditoria (`manifest.jsonl`) é estritamente **append-only**.
4. **Respeite o Hardware do Host:** O sistema deve rodar de forma leve no Windows 11 com 8GB de RAM sem saturar CPU nem vazar conexões ou handles de arquivo.
