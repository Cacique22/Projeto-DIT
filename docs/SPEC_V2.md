# ESPECIFICAÇÃO ARQUITETURAL E FUNCIONAL - PROJETO DIT v2
> **Versão:** 2.0.0-PROD-SPEC  
> **Status:** Aprovado para Desenvolvimento  
> **Público-alvo:** Desenvolvedores, Engenheiros de Software e Agentes Autônomos de IA  
> **Plataformas-Alvo:** Windows 10/11 (x64), macOS 12+ (Universal Apple Silicon arm64 / Intel x86_64), Linux (x64)

---

## 1. Visão Geral e Missão do Produto
O **Projeto DIT v2** é uma estação autônoma e profissional de ingestão, backup e verificação criptográfica para fotografia e vídeo de eventos de alta responsabilidade jurídica e operacional.

### Invariantes Inegociáveis (Core Rules):
1. **Zero Perda de Dados:** Nenhum arquivo é considerado entregue sem validação determinística de integridade.
2. **Imutabilidade da Origem (Safe Read):** O cartão é lido estritamente em modo de leitura, exceto pela gravação de um arquivo de identificação leve `.dit_card_id.json` durante o registro inicial.
3. **Escrita Atômica (Staging):** Gravações ocorrem com extensão temporária `.staging.tmp`. Arquivos incompletos por queda de energia ou remoção de cabo são purgados imediatamente.
4. **Idempotência em Milissegundos:** Se um cartão for reinserido no mesmo evento, fotos já transferidas são ignoradas instantaneamente.
5. **Auditoria Permanente:** Todos os eventos, cartões, arquivos, hashes e erros são gravados em banco de dados local imutável (`station.db`).

---

## 2. Stack Tecnológica
* **Backend Core:** **Rust** (gerenciamento direto de I/O, threads de cópia em paralelo, instruções SIMD de hardware para SHA-256, comunicação com APIs nativas de hardware).
* **Interface Gráfica (GUI):** **Tauri v2** + Webview nativo (UI reativa em Dark Mode, responsiva, aceleração gráfica 60fps, consumo ~40MB de RAM).
* **Banco de Dados Local:** **SQLite** embutido via Rust (`rusqlite` / `sqlx`), persistido no diretório de dados do sistema operacional.
* **Módulos Nativos de Ejeção de Hardware:**
  * **Windows:** Win32 APIs (`IOCTL_STORAGE_EJECT_MEDIA` via `DeviceIoControl`).
  * **macOS:** Framework `DiskArbitration` / chamada de sistema `diskutil`.
  * **Linux:** D-Bus via `udisks2` ou utilitário `udisksctl`.

---

## 3. Assistente de Abertura de Evento (Setup Wizard)
Ao iniciar um novo trabalho, a estação apresenta uma tela de configuração simples:
1. **Nome do Evento:** (Ex: `Casamento_Ana_e_Pedro`, `Formatura_Medicina_2026`).
2. **Topologia de Armazenamento:**
   * **Destino Principal (Obrigatório):** Disco/pasta onde as fotos de trabalho ficarão.
   * **Destino Espelho / Redundância (Opcional):** Segundo disco para cópia simultânea de segurança (Regra 3-2-1).
3. **Modo de Operação:**
   * **Modo A (Operador Dedicado / DIT):** Interface rica com controle total, permitindo ao operador renomear, pausar ou auditar cartões individualmente.
   * **Modo B (Totem Autônomo / Self-Service):** Interface à prova de erros, com botões gigantes e bloqueio de menus sensíveis. O fotógrafo chega, espeta o cartão e a estação conduz todo o fluxo com mínima interação.
4. **Política de Ejeção:**
   * `[x]` **Ejetar Imediatamente:** Assim que o hash é verificado com sucesso, ejeta o cartão e toca o acorde sonoro de sucesso.
   * `[ ]` **Ejeção Manual por Botão:** Mantém o cartão montado com status verde até o usuário clicar em `[Liberar Cartão]`.
5. **Lista de Fotógrafos da Equipe:** Cadastro dos nomes (e fotos opcionais) dos fotógrafos escalados para o evento.

---

## 4. Gerenciamento de Armazenamento e Redundância

### Pré-Flight Check (Antes de Iniciar o Backup):
1. O sistema calcula a capacidade livre em cada disco de destino vs o tamanho total das fotos novas.
2. É exigida uma margem de segurança de **10% de folga** no disco.
3. **Alerta Preventivo de Espaço:**
   * Se um dos discos (ex: Destino Espelho) não possuir espaço suficiente, o sistema alerta o usuário na tela:
     > *"O Disco de Backup [E:\] não possui espaço suficiente (Necessário: 64 GB | Livre: 20 GB). Deseja continuar gravando apenas no Disco Principal [D:\] ou cancelar?"*

### Tolerância a Falhas em Tempo Real (Overflow em Execução):
* Se durante a transferência um dos discos atingir capacidade máxima ou for desconectado:
  1. A estação alerta visualmente qual unidade falhou.
  2. **Em paralelo, continua a gravação ininterrupta no disco restante que ainda possui espaço**, evitando perda do tempo de cópia já realizado.

---

## 5. Concorrência e Detecção de Cartões

### Limite de Concorrência:
* O sistema suporta até **3 cartões simultâneos** gravando em paralelo com total isolamento de memória e threads independentes.
* Cada cartão ativo possui seu próprio card visual com:
  * Nome do fotógrafo e ID do cartão.
  * Barra de progresso individual (porcentagem e contagem de arquivos).
  * Velocidade real de transferência (MB/s).
  * Tempo restante estimado (ETA).

### Identificação Inteligente do Cartão:
1. **Cartão Novo (Primeira Inserção):**
   * No Modo Autônomo, surge uma tela simples e limpa: *"De quem é este cartão?"* com os nomes dos fotógrafos cadastrados.
   * Ao selecionar o nome, a estação cria automaticamente um ID único (ex: `Cartao_01`, `Cartao_02`) e grava na raiz do cartão o arquivo oculto `.dit_card_id.json`:
     ```json
     {
       "event": "Casamento_Ana_e_Pedro",
       "photographer": "Lucas Silva",
       "card_id": "Cartao_01",
       "registered_at": "2026-10-24T00:00:00Z"
     }
     ```
2. **Cartão Já Cadastrado (Re-inserção):**
   * A estação lê o arquivo `.dit_card_id.json` em menos de 10 milissegundos e inicia o processo instantaneamente sem nenhuma pergunta.

---

## 6. Motor de Cópia e Integridade Criptográfica (In-Flight Stream)

### Estratégia de Streaming:
* O leitor lê blocos do cartão para a memória RAM.
* **Em um único ciclo de leitura:**
  * O bloco é enviado ao buffer do Destino 1 (SSD).
  * O bloco é enviado ao buffer do Destino 2 (HD/Espelho, se ativo).
  * O bloco é processado pelo algoritmo SHA-256 utilizando aceleração por hardware da CPU.
* **Vantagem:** O cartão é lido apenas 1 vez (menor aquecimento físico, maior vida útil do cartão e velocidade máxima no set).

---

## 7. Estrutura de Diretórios no Destino

O sistema consolida apenas as pastas que realmente contêm mídias (ex: `100CANON`, `101CANON`, `100MSDCF`), ignorando diretórios vazios ou pastas de sistema da câmera (`MISC`, etc.):

```
[Destino_Selecionado]/
└── [Nome_Do_Evento]/
    └── [Nome_Do_Fotografo]/
        └── [Cartao_01]/
            ├── 100CANON/
            │   ├── _MG_0001.CR3
            │   ├── _MG_0001.JPG
            │   └── _MG_0002.CR3
            └── 101CANON/
                └── _MG_5001.CR3
```
* **Mídias Mistas:** Fotos RAW, JPG e vídeos (MP4, MOV) mantêm rigorosamente os nomes e formatos originais gravados pela câmera.

---

## 8. Tratamento de Exceções e Resiliência de Campo

### A. Arquivo Danificado no Cartão (Erro Físico de Leitura):
* Se uma foto estiver corrompida por queda de bateria da câmera:
  1. O motor tenta ler o bloco até 3 vezes.
  2. Persistindo o erro de I/O, **o sistema NÃO TRAVA o descarregamento**.
  3. O arquivo problemático é registrado no log de incidentes.
  4. O sistema continua copiando todos os demais arquivos íntegros do cartão.
  5. Ao final, sinaliza em alerta amarelo: *"Descarregamento concluído: X arquivos copiados com sucesso, 1 arquivo ilegível no cartão"*.

### B. Remoção Abrupta de Cabo (Tropeço no leitor USB):
* O arquivo incompleto que estava com extensão `.staging.tmp` é purgado do destino.
* A interface exibe aviso em vermelho no slot correspondente: *"Cartão desconectado abruptamente. Reconecte para continuar"*.
* Ao reconectar, a estação retoma exatamente de onde parou sem duplicar fotos.

### C. Cartão Sem Novas Fotos (Idempotência Total):
* Se o fotógrafo colocar um cartão onde 100% dos arquivos já foram salvos anteriormente:
  * A tela avisa: *"Nenhuma foto nova encontrada. Cartão já sincronizado."*
  * O cartão é liberado/ejetado imediatamente para desocupar o leitor.

---

## 9. Ciclo de Vida do Evento e Segurança Contra Erro Humano

### Encerramento do Evento:
* O operador clica no botão `[Finalizar Evento Atual]`.
* A estação exibe um resumo estatístico:
  * Total de fotos e vídeos descarregados.
  * Volume total em Gigabytes transferidos.
  * Número de cartões processados por fotógrafo.
* A sessão é trancada e a estação retorna à tela inicial de [Novo Evento], evitando que o trabalho seguinte caia acidentalmente na pasta do evento anterior.

### Histórico Persistente e Retomada Segura:
* Todos os dados, logs e registros de eventos passados continuam gravados permanentemente no banco de dados local para conferência e auditoria futura.
* **Trava de Segurança para Reabertura:**
  * Se o evento foi encerrado por engano enquanto ainda havia fotógrafos trabalhando, o usuário pode reabri-lo.
  * Para destravar, a interface exige a digitação exata de uma frase de confirmação:
    > **Digite: `Retomar evento fechado`**
  * Essa barreira física elimina qualquer risco de clique acidental misturar fotos de clientes diferentes.
