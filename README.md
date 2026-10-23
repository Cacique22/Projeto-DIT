# Estação de Ingestão e Backup DIT (Digital Imaging Technician)
### Sistema de Descarregamento Automático, Incremental e Verificado para Fotografia de Eventos

> **Missão Crítica:** Eliminação total de risco de perda de arquivos e responsabilidade jurídica em eventos fotográficos através de integridade criptográfica SHA-256 byte-a-byte, idempotência em milissegundos e operação 100% autônoma.

---

## 📸 O Que o Sistema Faz

1. **Detecção Automática:** Ao plugar um cartão SD, CFexpress ou leitor USB, a estação reconhece o dispositivo imediatamente.
2. **Identificação do Fotógrafo:** Lê etiquetas de volume ou arquivo `fotografo.txt` na raiz do cartão para separar os arquivos por autor.
3. **Idempotência Inteligente (Pula Duplicados em Milissegundos):** Fotógrafos entregam o mesmo cartão várias vezes ao longo do evento. O sistema identifica em milissegundos o que já foi salvo anteriormente e **só copia os arquivos novos**.
4. **Verificação Criptográfica SHA-256:** Cada arquivo copiado é validado byte-a-byte contra corrupção antes de ser confirmado.
5. **Cópia Atômica com Staging (`.staging.tmp`):** Nenhum arquivo incompleto ou corrompido é gravado no destino.
6. **Imutabilidade Total do Cartão:** Acesso estritamente somente leitura. O cartão original nunca é apagado ou modificado.
7. **Pre-Flight Disk Check:** Rejeita preventivamente a operação se o armazenamento de destino não tiver espaço suficiente (com 10% de margem de segurança).
8. **Feedback Visual e Sonoro:** Bips no início e fim de cada descarga e painel web em tempo real.
9. **Interface Web Moderna:** Acesse de qualquer navegador na mesma rede (`http://[IP-DA-MAQUINA]:8080`) ou localmente para escolher onde salvar, definir o nome do evento e ver o histórico.

---

## 🚀 Como Iniciar

### Modo Rápido (Interface Gráfica)
Dê um duplo clique no arquivo:
```cmd
Iniciar_Estacao.bat
```
O navegador abrirá automaticamente com o painel de controle em: `http://localhost:8080/`.

---

## ⚙️ Configuração via Painel Web

No painel, você pode:
- **Escolher a Unidade de Backup:** Clique diretamente no cartão do disco detectado (ex: `D:\` com SSD dedicado, `C:\`, etc.).
- **Nome do Evento:** Digite o nome (ex: `Casamento_Ana_e_Pedro`). Os arquivos serão organizados em:
  `[Destino]\[Nome_Do_Evento]\[Fotografo]\...`
- **Histórico e Auditoria:** Consulte o manifesto de auditoria (`manifest.jsonl`) com hashes SHA-256 e timestamps de cada foto.

---

## 🧪 Testes Automatizados Periódicos

Conforme a regra de ouro de confiabilidade, **nenhuma alteração deve quebrar o sistema existente**. Para validar todas as invariantes a qualquer momento:

Dê um duplo clique em:
```cmd
Executar_Testes.bat
```
Ou execute via PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```
A suíte executa 38 testes cobrindo:
- Criptografia determinística SHA-256
- Identificação de múltiplos fotógrafos
- Pre-flight de espaço livre em disco
- Cópia atômica em 2 fases (`.staging.tmp` -> commit final)
- Idempotência em re-inserção de cartões
- Imutabilidade do cartão de origem
- Persistência e sanitização de configurações
- API REST e entrega do painel web

---

## 📁 Estrutura do Repositório

```
auto-ingest-station/
├── docs/
│   ├── ARCHITECTURE.md     # Manifesto DIT de Missão Crítica
│   └── AGENTS.md           # Regras para agentes e desenvolvedores
├── src/
│   ├── IngestEngine.ps1    # Motor de ingestão, hashing e staging
│   ├── ConfigManager.ps1   # Gerenciador de armazenamento e configurações
│   ├── WebServer.ps1       # Servidor HTTP nativo e API REST
│   ├── Watch-UsbCards.ps1  # Daemon de monitoramento de cartões USB
│   ├── Start-Station.ps1   # Orquestrador da estação
│   └── public/
│       └── index.html      # Painel web moderno e responsivo
├── tests/
│   └── Run-Tests.ps1       # Suíte de testes automatizados completa
├── Iniciar_Estacao.bat     # Atalho para inicialização da estação
├── Executar_Testes.bat     # Atalho para execução dos testes
└── config.json             # Configuração da estação (gerada automaticamente)
```
