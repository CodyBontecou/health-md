---
title: "Agentes locais e contexto de saúde"
description: "Conecte agentes locais ao Health.md por meio de comandos limitados da CLI ou MCP direto para iPhone e preserve evidências, cobertura e ausência de dados."
---

O Health.md oferece aos agentes locais de programação e automação duas formas de trabalhar com dados do Apple Health:

- a CLI `healthmd` para comandos explícitos no terminal e extração canônica;
- `healthmd mcp serve` e seu MCP App para ferramentas tipadas, visualizações nativas e exportações aprovadas de arquivos gerados.

O servidor MCP portátil se comunica diretamente com o iPhone em primeiro plano e não exige o Health.md para Mac. A CLI pode usar o mesmo canal direto para exportações brutas/canônicas ou a API de loopback do app para Mac em fluxos de trabalho com índice no Mac. As leituras do HealthKit sempre ocorrem no iPhone, e `healthmd.health_data` v8 continua sendo o contrato público de origem.

```text
local agent -> healthmd mcp serve -> authenticated encrypted port 17647 -> foreground iPhone
local agent -> healthmd CLI -> direct iPhone or optional Mac loopback workflow
```

## O que um agente pode fazer

- verificar o emparelhamento direto e a prontidão do iPhone em primeiro plano sem ler valores de saúde;
- listar IDs de métricas e categorias canônicas;
- adquirir do iPhone um escopo exato de métrica, fonte, data e nível de detalhe;
- extrair documentos diários canônicos ou registros de origem;
- consultar séries de métricas tipadas com evidências e cobertura;
- criar sessões de sono estáveis e janelas de sono fixas;
- alinhar treinos ao sono anterior e posterior;
- listar treinos e inspecionar a cobertura;
- comparar períodos exatos com agregação explícita;
- criar pacotes factuais de evidências de treino;
- percorrer um corpus lógico ilimitado por meio de solicitações limitadas;
- renderizar visualizações de métricas, sono, treinos, comparações, cobertura e evidências dentro de MCP Apps;
- executar exportações aprovadas de arquivos gerados para um destino explícito e existente na mesa;
- inspecionar, retomar ou cancelar tarefas persistentes de exportação.

O Health.md não diagnostica, recomenda tratamento, infere causalidade nem classifica um resultado como saudável, nocivo, melhor ou pior.

## Configure os auxiliares locais

<div class="availability preview">
<strong>Prévia pública · ainda não é uma versão estável qualificada</strong>
<p>O pacote multiplataforma é publicado como uma prévia explicitamente não qualificada. Use a compilação móvel exata indicada pela evidência da versão; o auxiliar assinado para Mac continua disponível em <a href="/pt-br/docs/configuration/">Configure seu agente</a>.</p>
</div>

1. No macOS ou Linux, execute `brew install CodyBontecou/tap/healthmd` e depois verifique `healthmd --version`.
2. Execute `healthmd setup codex`; ele configura o Codex e inicia o emparelhamento quando ainda não há um iPhone confiável.
3. Conclua o emparelhamento em Acesso ao Direct CLI no Health.md para iPhone e mantenha o app em primeiro plano.
4. Para o Claude ou uma configuração manual do host, configure o caminho absoluto de `healthmd` com os argumentos `mcp serve` usando [Servidor e App MCP do Health.md](/pt-br/docs/mcp/).
5. Reinicie o host quando a configuração indicar uma alteração e, em seguida, chame `healthmd_doctor`.

O app Health.md para Mac continua sendo uma opção de instalação e distribuição de skills para usuários de Mac, não uma dependência portátil do MCP.

O instalador de skills do app cria `healthmd-cli/SKILL.md` no diretório que você aprovar. Ele substitui apenas a pasta de skills do próprio Health.md. A skill ensina comandos limitados, tratamento de resultados estruturados, regras de privacidade e recuperação segura após resultados desconhecidos.

Use o prompt de configuração no app para Mac se quiser que um agente crie os links simbólicos. O próprio Health.md não modifica silenciosamente arquivos de inicialização do shell nem `/usr/local/bin`.

## Primeiro, verifique a prontidão

Para clientes MCP portáteis, chame `healthmd_doctor`. Ele verifica a confiança direta local e o iPhone conectado em primeiro plano sem ler valores de saúde e retorna erros acionáveis sem dados de saúde. Cada consulta MCP tipada é então uma solicitação nova e explícita para esse iPhone: ela captura apenas o escopo solicitado, avalia a consulta tipada no dispositivo e retorna páginas limitadas.

Usuários da CLI com loopback no Mac ainda podem executar `healthmd doctor` para verificar a prontidão de `healthmd.cli_doctor` v1, a cobertura do contexto criptografado e as próximas ações.

## Cada solicitação inclui seu próprio escopo

O Health.md não usa perfis de acesso salvos, registros de chamadores, registros de concessões nem credenciais da CLI. Cada solicitação fornece todo o escopo de dados necessário:

- IDs de métricas ou categorias;
- seletores de fonte do Apple Health e, opcionalmente, de provedores;
- datas exatas ou todas as datas disponíveis;
- nível de detalhe resumido ou sem perdas;
- operação de consulta;
- controles de paginação limitados.

A aquisição de dados recentes valida o escopo com base nos catálogos atuais, persiste-o com a tarefa persistente e o aplica no iPhone sem alterar as preferências de exportação salvas.

Uma solicitação sem seleção explícita de aquisição é rejeitada, em vez de herdar as configurações normais de exportação do usuário.

## Limites de autorização

O MCP portátil usa o protocolo direto emparelhado: armazenamento nativo de credenciais, autenticação mútua da transcrição, pacotes criptografados, proteção contra repetição e uma conexão do iPhone em primeiro plano com o endereço explícito do computador. A API opcional de consulta no Mac, por sua vez, atende apenas no loopback IPv4 e IPv6 e valida que o par seja de loopback.

No modo opcional de loopback do Mac, qualquer processo local que consiga acessar a porta `17645` enquanto o Health.md estiver aberto poderá emitir as mesmas solicitações de consulta. Trate o acesso à máquina local como autoridade para consultas:

- não vincule nem encaminhe a porta para uma interface de LAN;
- não crie um túnel para outra máquina;
- não coloque um proxy reverso HTTP à frente dela;
- não configure o MCP com uma URL que não seja de loopback;
- analise quais agentes locais podem executar o auxiliar.

As antigas rotas de perfil e atividade retornam `410 removed_endpoint` por compatibilidade.

## Dados canônicos e visualizações derivadas

Use `healthmd extract` quando o agente precisar de dados no formato da fonte ou de um corpo bruto/canônico grande e validado:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Use comandos de consulta ou ferramentas MCP para visualizações derivadas e visualizações no host:

```bash
healthmd query --metric resting_heart_rate --last 30 --all-pages
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd training align --last 14 --workout running --sleep-window first:4h
```

A distinção é intencional:

| Interface | Função do contrato |
|---|---|
| `healthmd.health_data` v8 | Documento público diário de origem |
| `healthmd.healthkit_records` v1 | Arquivo canônico de registros de origem dentro de documentos diários sem perdas |
| `healthmd.extract_receipt` | Metadados de escopo e conclusão da extração |
| `healthmd.query_context_day` v1 | Registro descartável do índice criptografado |
| `healthmd.query_response` v1 | Resultado derivado tipado e paginado |
| `healthmd.evidence_packet` v1 | Pacote factual vinculado às evidências de origem |
| Comprovantes de tarefas e percurso | Metadados de transporte, persistência e conclusão |

Uma projeção ou um resultado tipado nunca se apresenta como um documento diário de origem completo.

## Aquisição de dados recentes

Por padrão, consultas de alto nível adquirem dados recentes:

```bash
healthmd query --category Sleep --last 14
```

O Health.md cria uma solicitação dedicada de contexto criptografado. Ele não grava arquivos de exportação nem consome a cota de exportação de arquivos. O iPhone lê o escopo explícito, cria dias compactos e determinísticos do proprietário e envia partições limitadas e retomáveis. O Mac confirma cada dia criptografado antes de acusar seu recebimento.

A conclusão da atualização verifica cada métrica, fonte ou provedor e dia do proprietário solicitados em relação aos blobs substituídos após o início dessa atualização. Valores mais antigos em cache e dados de outro provedor não podem ocultar uma falha na aquisição.

Solicitações exclusivas de provedores podem ignorar o HealthKit. O percurso do histórico do provedor segue cursores nativos do provedor, em vez de impor um limite fixo ao total de resultados.

## Contexto criptografado no Mac

O Mac armazena uma geração criptografada de forma independente por dia do proprietário. Uma chave aleatória de 256 bits fica nas Chaves como um item exclusivo deste dispositivo e disponível quando desbloqueado.

- os blobs diários e o manifesto usam AES-256-GCM;
- os nomes de arquivo são UUIDs aleatórios, não datas nem nomes de métricas;
- as datas do proprietário e as entradas do índice são criptografadas;
- os arquivos têm permissões exclusivas do proprietário e são excluídos do backup;
- as confirmações gravam uma nova geração imutável antes de substituir o manifesto criptografado;
- as leituras falham de forma segura em caso de chaves ausentes, falha de autenticação, datas malformadas ou incompatibilidade do manifesto.

O armazenamento não tem um limite total configurado de métricas, dias, histórico ou resultados. Os comandos permanecem limitados porque descriptografam um dia por vez e paginam os resultados.

O índice é descartável. As exportações canônicas continuam sendo a fonte da verdade.

## Retenção e exclusão

O Health.md não exclui o contexto de consulta segundo um cronograma de retenção implícito. No Mac, os Ajustes mostram a quantidade de dias do proprietário armazenados e o intervalo de datas.

Use:

- **Excluir contexto mais antigo** para remover datas do proprietário estritamente anteriores a um limite selecionado;
- **Excluir todo o contexto criptografado** para remover todas as gerações criptografadas e a chave dedicada das Chaves.

A exclusão completa continua disponível mesmo se a chave ou o texto cifrado estiver danificado. Remover a chave proporciona o apagamento criptográfico de quaisquer resquícios de texto cifrado não excluídos.

Excluir o contexto de consulta não exclui arquivos de exportação, credenciais de provedores conectados nem dados do Apple Health.

## Valores tipados e ausência de dados

Os valores de consulta são identificados por tipo. Um resultado pode conter uma quantidade e unidade canônica, duração, contagem com sinal, string, categoria, Booleano, timestamp UTC, data de calendário, array aninhado ou uma carga tipada futura desconhecida.

A ausência de dados permanece explícita:

- `complete_empty` significa que o escopo representado não tinha observações correspondentes;
- `partial` significa que apenas parte do escopo solicitado foi concluída;
- `failed`, `unsupported`, `skipped` e `cancelled` mantêm seus significados;
- `not_requested`, `legacy_unavailable`, `redacted` e `not_synchronized` permanecem distintos.

O Health.md nunca converte um valor ausente em zero numérico. Um zero real é codificado como um valor tipado disponível.

## Evidências e linguagem neutra

Os resultados vinculam fatos a evidências de origem, como:

- chaves de resumo diário;
- UUIDs canônicos do HealthKit;
- identidades externas;
- resultados do manifesto de consultas;
- avisos de integridade;
- falhas parciais.

A resolução de evidências verifica em conjunto o ID da evidência, o localizador, o schema de origem, a versão da origem e o digest da origem.

A direção da comparação entre períodos se limita a `increased`, `decreased`, `unchanged` ou `not_comparable`. O alinhamento de treinos informa timestamps e intervalos, não efeitos causais. Os pacotes de evidências informam observações e cobertura armazenadas, não conclusões médicas.

Um agente deve preservar esses limites na própria resposta. Deve informar quando houver dados ausentes, evitar transformar correlação em causalidade e encaminhar dúvidas médicas a um profissional de saúde qualificado.

## Páginas limitadas, acesso lógico completo

As páginas de consulta usam `max_items`, `max_bytes` e um `next_cursor` opaco. Não há limite contratual para o total de dias, treinos, métricas ou itens de resultados armazenados.

Um cursor tem proteção de integridade e está vinculado à consulta semântica e à revisão do corpus criptografado. O Health.md rejeita:

- um cursor modificado;
- um cursor usado com outra consulta;
- um cursor emitido antes de o corpus ser alterado;
- um cursor repetido durante o percurso automático.

Use `--all-pages` ou `all_pages: true` no MCP para um percurso automático limitado. Restrinja o escopo ou percorra as páginas manualmente se uma invocação atingir o limite agregado de segurança.

## Checklist de relatórios do agente

Ao resumir um resultado, informe:

- o comando ou a ferramenta usados;
- as datas, métricas, fonte e nível de detalhe exatos solicitados;
- o modo de dados recentes, em cache ou de reutilização da cobertura;
- o status do escopo solicitado e o status do corpus separadamente;
- a conclusão da página ou do percurso;
- as unidades e as evidências de origem de qualquer valor informado;
- intervalos ausentes, limitações e omissões não relacionadas;
- o ID da tarefa quando o trabalho estiver pausado ou puder ser retomado.

Não inclua registros brutos, rotas, texto clínico, detalhes de medicamentos, registros de humor nem anexos, a menos que o usuário solicite explicitamente esses valores e compreenda a divulgação.

## Escolha uma integração

<div class="related">
  <a href="/pt-br/docs/agent-queries/"><span>Guia da CLI</span>Consultas tipadas de agentes: métricas, sessões de sono, alinhamento de treinos, treinos, cobertura, comparação e evidências.</a>
  <a href="/pt-br/docs/mcp/"><span>Protocolo de ferramentas</span>Configuração do Codex e Claude, 21 ferramentas Mac publicadas, 19 ferramentas portáteis em prévia, gráficos em MCP App, exportações, paginação e limites do sandbox.</a>
  <a href="/pt-br/docs/agent-api/"><span>Baixo nível</span>API de consulta de loopback: rotas, JSON de solicitação direta, cursores e tarefas persistentes de aquisição.</a>
  <a href="/pt-br/docs/cli-extract/"><span>Objetos de origem</span>Extração canônica: documentos selecionados do schema v8, registros, projeções e comprovantes.</a>
  <a href="/pt-br/docs/reference/evidence-packets/"><span>Contratos</span>Consultas compactas e pacotes de evidências: valores tipados, cobertura, operações e IDs determinísticos.</a>
</div>
