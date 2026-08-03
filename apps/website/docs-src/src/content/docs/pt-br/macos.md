---
title: "App para macOS"
description: "Use Health.md para Mac como destino de exportação do iPhone, host local da CLI e do MCP, armazenamento criptografado de contexto de saúde, visualizador de histórico e autoridade de acesso a pastas."
---

O Health.md para Mac tem duas funções locais:

1. recebe tarefas de exportação do iPhone e grava arquivos em uma pasta que você escolher;
2. hospeda a CLI de loopback, a API de consultas, o contexto de saúde criptografado e o adaptador MCP usados por agentes locais.

Apple Health permanece no iPhone. O app para Mac não lê HealthKit diretamente.

## Áreas principais

<div class="options">
<div class="option"><strong>Sincronização</strong><p>Mostra se o Mac está detectável e pronto para tarefas de exportação do iPhone.</p></div>
<div class="option"><strong>Pasta de destino</strong><p>Armazena um marcador com escopo de segurança para saídas Markdown, JSON, CSV, Bases, consolidações, ZIP e notas diárias.</p></div>
<div class="option"><strong>Agendamento</strong><p>Mantém visíveis o agendamento e a prontidão no lado do Mac. O iPhone ainda fornece os dados do HealthKit.</p></div>
<div class="option"><strong>Histórico</strong><p>Acompanha resultados de exportação, progresso de tarefas persistentes, erros e contexto de nova tentativa para arquivos gravados pelo desktop.</p></div>
<div class="option"><strong>Ajustes</strong><p>Mostra a integridade do destino, controles de retenção do contexto criptografado e configuração local da CLI.</p></div>
<div class="option"><strong>Barra de menus</strong><p>Fornece acesso rápido ao status, aos ajustes e ao app enquanto Health.md permanece disponível localmente.</p></div>
<div class="option"><strong>CLI</strong><p>Instala os auxiliares incluídos <code>healthmd</code> e <code>healthmd-mcp</code>, copia prompts de configuração, instala a skill opcional de agente e mostra comandos testados.</p></div>
</div>

## Configure um destino no Mac

1. Instale e abra Health.md no Mac.
2. Escolha uma pasta de destino no disco local, no iCloud Drive ou dentro de um cofre do Obsidian.
3. No iPhone, ative a conectividade com o Mac na aba Sincronização.
4. No iPhone, escolha Mac conectado como destino de exportação.
5. Configure a exportação e toque em Exportar.

O iPhone captura dados do HealthKit e o instantâneo das configurações efetivas. Os pares atuais transferem partições de tamanho limitado, validadas por soma de verificação. O Mac usa os exportadores de produção e grava os arquivos solicitados.

<div class="callout">
<strong>Limitação do HealthKit.</strong>
<p style="margin-top:6px;">O Mac não consegue consultar Apple Health por conta própria. Novas exportações e contexto de agente exigem que o app conectado do iPhone esteja aberto. Consultas criptografadas em cache podem ser executadas sem uma nova conexão com o iPhone quando a cobertura armazenada for suficiente.</p>
</div>

## Configuração da CLI e de agentes

Abra a área **CLI** do app para Mac para:

- ver os caminhos exatos dos auxiliares assinados neste pacote do app;
- copiar aliases ou comandos de link simbólico para `~/.local/bin`;
- copiar um prompt de configuração assistida por agente;
- instalar a skill opcional `healthmd-cli` em um diretório que você escolher;
- ver os comandos atuais de status, doctor, extração, consulta, sono, alinhamento de treinos, treinos, cobertura e exportação;
- revisar erros comuns de prontidão.

O app nunca edita arquivos de inicialização do shell nem instala em um diretório do sistema sem uma ação sua.

Comece com:

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --category Sleep --yesterday
```

Consulte [CLI do Health.md](/pt-br/docs/cli/) para seleção de backend e [Agentes locais](/pt-br/docs/agents/) para a arquitetura de consultas.

## Contexto de saúde criptografado

Novas solicitações de consulta e evidência usam um modo dedicado de aquisição de contexto. O iPhone lê a métrica, a fonte, a data e o escopo de detalhe exatamente solicitados. Ele não cria arquivos de exportação nem altera preferências de exportação salvas.

O Mac armazena cada dia compacto do proprietário em um blob AES-256-GCM autenticado de forma independente. Um item do Keychain exclusivo deste dispositivo e disponível quando desbloqueado contém a chave de criptografia aleatória. Os nomes de arquivo são aleatórios e não revelam datas nem nomes de métricas.

Ajustes informa a contagem de dias do proprietário criptografados e o intervalo de datas. Duas ações independentes controlam a retenção:

- **Excluir Contexto Antigo** remove dias do proprietário estritamente anteriores ao limite escolhido;
- **Excluir Todo o Contexto Criptografado** remove todos os arquivos de contexto e a chave dedicada do Keychain.

A retenção de contexto nunca exclui dados do Apple Health, arquivos de exportação, marcadores de destino do Mac nem credenciais de provedores conectados.

## Limite da API de loopback

O app para Mac escuta em `127.0.0.1` e `::1`, na porta `17645`, para rotas locais de status, exportação, consulta, evidência, atualização e tarefas persistentes.

Não há token bearer nem registro de agente. Qualquer processo local pode chamar a API enquanto o app estiver aberto. Nunca exponha, faça proxy nem crie túnel da porta para outra máquina.

O auxiliar `healthmd-mcp` em sandbox aceita apenas endpoints HTTP canônicos de loopback e oferece ferramentas sem shell, arquivos arbitrários, SQL, busca de URL, resources, prompts, roots ou sampling.

## Direct CLI Access é separado

O ajuste **Direct CLI Access** do iPhone cria uma relação de confiança separada entre uma CLI compatível com acesso direto e o iPhone. Ele pode contornar o app para Mac para exportação bruta, extração canônica, arquivos gerados, status, retomada e cancelamento.

O modo direto não usa o contexto de consulta criptografado do app para Mac. Em vez disso, `healthmd mcp serve` portátil executa consultas tipadas recentes diretamente no iPhone em primeiro plano, usando a mesma identidade executável usada no emparelhamento. Consulte [Direct iPhone CLI](/pt-br/docs/cli-direct/) para emparelhamento e compatibilidade de plataforma.

## Relacionados

<div class="related">
  <a href="/pt-br/docs/sync/"><span>Destino</span>Sincronização com o Mac: emparelhe iPhone e Mac para exportações locais de arquivos.</a>
  <a href="/pt-br/docs/cli/"><span>Terminal</span>CLI do Health.md: instale auxiliares, selecione um backend e execute comandos.</a>
  <a href="/pt-br/docs/agents/"><span>Contexto local</span>Agentes: aquisição com escopo, armazenamento criptografado, evidência e retenção.</a>
  <a href="/pt-br/docs/mcp/"><span>Ferramentas</span>Servidor MCP local: configuração, catálogo de ferramentas e limites do sandbox.</a>
  <a href="/pt-br/docs/scheduling/"><span>Fluxo de trabalho</span>Agendamento: automatize exportações recorrentes.</a>
</div>
