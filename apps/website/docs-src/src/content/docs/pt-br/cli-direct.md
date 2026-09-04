---
title: "CLI direta para telefone"
description: "Emparelhe o healthmd com um iPhone ou um telefone Android por IP manual ou Tailscale e exporte sem executar o Health.md para Mac."
---

O backend direto conecta o `healthmd` a um app Health.md aberto no iPhone ou no Android, sem encaminhar o comando pelo Health.md para Mac. O telefone lê o repositório de saúde da sua plataforma — o HealthKit no iPhone e o Health Connect no Android —, prepara o resultado em armazenamento protegido e transfere partições validadas para a CLI.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone or Android -> HealthKit / Health Connect -> protected bounded spool
  -> raw snapshots, production-generated files, or (iPhone) canonical and typed query data
```

<div class="availability preview">
<strong>Prévia · CLI direta portátil</strong>
<p>O backend direto Swift integrado está disponível no macOS e emparelha com o iPhone. O Android com protocolo de aplicação v2 faz parte da prévia publicamente empacotada do cliente Rust multiplataforma. As versões atuais de iOS e Android usam o mesmo seletor 3 e o mesmo QR universal em novos emparelhamentos portáteis. A conectividade física básica foi confirmada nas duas plataformas móveis, mas a matriz completa de lançamento com builds exatos continua pendente; portanto, este ainda é um fluxo de trabalho explicitamente não qualificado.</p>
</div>

## Compatibilidade móvel para 0.1.0-alpha.6

Esta tabela independente é a matriz aplicável para a prévia explicitamente não qualificada. A conectividade básica com iPhone e Android foi confirmada fisicamente; nenhum par público de CLI e dispositivo móvel concluiu e reteve ainda toda a matriz de qualificação.

| Fonte móvel | Protocolo | Correspondente tag-SHA exato / piso não qualificado | Operações Rust portáteis | Status público |
|---|---|---|---|---|
| iPhone com exportação | seletor 3 atual (1 antigo) / aplicação v1 | iOS 3.3.0 (build 202609032317) / iOS 3.0.3 | Status, dados brutos, extração, arquivos, retomada, cancelamento | Conectividade confirmada; qualificação completa pendente |
| iPhone com consultas | seletor 3 atual (1 antigo) / aplicação v1 + consulta v3 | iOS 3.3.0 (build 202609032317) / iOS 3.0.3 | V1 mais MCP/consulta local com 19 ferramentas | Conectividade confirmada; qualificação completa pendente |
| Android | seletor 3 atual (2 antigo) / aplicação v2 | Android 1.8.2 (`versionCode 31`) / Android 1.5.4 (`versionCode 25`) | Status, dados nativos, arquivos, retomada, cancelamento | Conectividade confirmada; qualificação completa pendente |
| Consulta MCP tipada no Android | Não disponível | Não implementada | As ferramentas exigem iPhone v3 | Sem suporte |

## O que o modo direto oferece

- emparelhamento único pelo seletor compartilhado 3 e reconexão confiável com fontes iPhone (protocolo de aplicação v1) ou Android (protocolo de aplicação v2);
- inspeção local de dispositivos confiáveis e desemparelhamento;
- prontidão do telefone em tempo real;
- exportação bruta estrita — `healthmd.health_data` no schema v8 no iPhone e snapshots nativos do Health Connect no Android;
- extração canônica selecionada (somente iPhone);
- exportação de arquivos gerados em produção em ambas as plataformas de telefone;
- status local persistente de tarefas e retomada;
- cancelamento explícito;
- o servidor stdio `healthmd mcp serve` no mesmo executável, com consultas tipadas diretas, catálogo de métricas, evidências, interface do MCP Apps e alternativa em PNG (somente iPhone).

O backend direto do comando `healthmd` não emula as rotas HTTP de contexto criptografado do app para Mac. Portanto, os subcomandos `doctor` orientados ao Mac, assim como os de consulta, evidências e atualização, continuam retornando `backend_unsupported` em vez de trocar de backend. Use `healthmd mcp serve` para análises tipadas recentes diretamente do iPhone ou execute `healthmd setup codex` para configurar e emparelhar o Codex automaticamente. `healthmd mcp schema [TOOL]` imprime localmente o schema exato e aninhado da entrada MCP, além de exemplos; use `healthmd_sleep_sessions` diretamente para sono, em vez de tratar a saída canônica de `extract` como a API de consulta tipada.

## Requisitos

- Um binário `healthmd` com suporte ao modo direto e uma versão correspondente do Health.md: iPhone (protocolo de aplicação v1) ou Android (protocolo de aplicação v2). O emparelhamento com Android exige o cliente Rust portátil; o auxiliar integrado do macOS emparelha somente com o iPhone.
- O Health.md aberto em primeiro plano no telefone para emparelhamento e novos comandos.
- **Ajustes > Sincronização com Mac > Acesso ao Direct CLI** ativado no iPhone, ou **Ajustes → Direct CLI** no Android.
- Permissão de saúde da plataforma (HealthKit ou Health Connect), dados protegidos, permissão de rede local e cota de exportação disponíveis.
- Um endereço de computador acessível e a porta TCP `17647` para IP manual. Um endereço do Tailscale funciona.
- Um destino absoluto existente para o modo de arquivos gerados.

A CLI atua como listener. O telefone se conecta ao endereço do computador informado no Acesso ao Direct CLI.

## Suporte a transportes

| Transporte | Auxiliar Swift integrado no macOS | Cliente Rust portátil |
|---|---:|---:|
| IP manual em uma LAN | Sim | macOS, Linux, Windows |
| Endereço do Tailscale | Sim | macOS, Linux, Windows |
| Proximidade / MultipeerConnectivity | Sim | Não |

A conexão por proximidade usa a sessão Multipeer criptografada da Apple, além da mesma autenticação e criptografia do aplicativo Health.md usadas pelo IP manual. O cliente portátil retorna `transport_unsupported` para conexões por proximidade.

## Emparelhe uma vez por IP manual

Inicie o listener no computador:

```bash
healthmd direct pair --transport manual-ip
```

O cliente Rust portátil mostra um QR universal para iOS e Android e grava em stderr o código compartilhado de 20 dígitos, possíveis endereços do computador, a porta do listener e um código alternativo de seis dígitos para versões antigas do iOS. O auxiliar integrado do macOS continua mostrando apenas o código antigo de seis dígitos do iPhone. O stdout permanece reservado para o resultado JSON final.

No iPhone:

1. Abra **Health.md > Ajustes > Sincronização com Mac > Acesso ao Direct CLI** e ative o acesso.
2. Toque em **Escanear QR de emparelhamento** e escaneie o QR universal; o emparelhamento começa imediatamente após essa leitura explícita.
3. Se a leitura não estiver disponível, selecione **IP manual** e digite endereço, porta e o código compartilhado de 20 dígitos. Uma CLI antiga ainda pode usar o código de seis dígitos.
4. Mantenha o app aberto até que ambos os lados informem sucesso.

## Emparelhe um telefone Android

1. Abra **Health.md > Ajustes → Direct CLI** no telefone Android.
2. Toque em **Escanear QR de emparelhamento** e escaneie o QR universal; o emparelhamento começa imediatamente após essa leitura explícita.
3. Sem câmera ou permissão, digite manualmente endereço, porta e o mesmo código compartilhado de 20 dígitos.
4. Mantenha o app aberto; o Android executa um serviço de primeiro plano visível de sincronização de dados, iniciado pelo usuário, para uma sessão direta ativa.

Os códigos de uso único nunca são enviados pela rede nem mantidos de forma persistente. Após o emparelhamento, o Keychain ou o Android Keystore protege a confiança de reconexão.

Use outra porta quando necessário:

```bash
healthmd --port 18000 direct pair --transport manual-ip
healthmd --backend direct --port 18000 status
```

Continue usando a mesma porta explícita nos comandos posteriores de status, exportação, retomada e cancelamento.

## Emparelhe por proximidade

A conexão por proximidade está disponível apenas no auxiliar Swift integrado:

```bash
healthmd direct pair --transport nearby
```

Selecione Proximidade no Acesso ao Direct CLI no iPhone, digite o código exibido e mantenha os dois dispositivos abertos até a conclusão do emparelhamento. Nenhuma operação por proximidade que falhar mudará para IP manual.

## Dispositivos confiáveis

O emparelhamento estabelece uma relação de confiança separada da relação de sincronização do app Health.md para Mac.

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

Esses comandos leem ou alteram a confiança local e não entram em contato com o telefone. No iPhone, use **Esquecer CLI emparelhada** para remover a outra parte; no Android, remova o emparelhamento em **Ajustes → Direct CLI**.

Quando houver mais de um telefone confiável, selecione explicitamente a instalação desejada:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Use `healthmd direct reset-trust --confirm` somente quando a confiança local estiver corrompida ou pertencer a uma instalação substituída. Esse comando remove todos os emparelhamentos diretos locais. Esqueça esses emparelhamentos no telefone antes de recomeçar.

## Verifique a prontidão em tempo real

```bash
healthmd --backend direct --transport manual-ip status
```

Uma resposta de status direto informa o estado da conexão e da segurança sem valores de saúde. O cliente portátil informa a fonte em `source` com um `platform` de valor `ios` ou `android`; o auxiliar integrado expõe os campos `iphone` abaixo. Verifique estes campos antes de iniciar uma tarefa (fonte iPhone exibida):

| Campo | Estado pronto |
|---|---|
| `backend` | `direct` |
| `mac_app` | `bypassed` |
| `direct_cli.paired` | `true` |
| `iphone.connected` | `true` |
| `iphone.app_active` | `true` para novas tarefas |
| `iphone.protected_data_available` | `true` |
| `iphone.can_trigger_raw_exports` | `true` para dados brutos e extração |
| `iphone.can_trigger_exports` | `true` para arquivos gerados |

O destino no status direto permanece não selecionado. O modo de arquivos usa apenas o `--destination` explícito fornecido ao comando.

Uma fonte Android informa `platform: "android"` com `app_active`, `protected_data_available`, `export_in_progress` e seus produtos brutos disponíveis, em vez dos sinalizadores de disparo do iPhone.

## Exportação bruta estrita (iPhone)

Escolha um seletor de intervalo:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Omita `--output` para transmitir o JSON validado por stdout. Um arquivo de saída é mais seguro para respostas confidenciais ou grandes.

A exportação bruta estrita do iPhone retorna `healthmd.raw_result` v1 contendo dias comuns de `healthmd.health_data` no schema v8 e seus arquivos canônicos de origem. Ela solicita temporariamente detalhes sem perdas sem alterar os ajustes salvos no iPhone. A CLI valida as datas exatas, o perfil, o schema, o arquivo, os manifestos, a cadeia de resumos, o resumo final do corpo e o estado de conclusão antes de disponibilizar o resultado.

Um dia completo sem dados é considerado bem-sucedido. Dados solicitados ausentes, parciais, com falha, cancelados, incompatíveis ou ignorados produzem `partial_success` e um código de saída diferente de zero, a menos que `--allow-partial` seja especificado explicitamente.

## Exportação bruta nativa do provedor (Android)

O cliente Rust portátil é direto por padrão, então os comandos brutos do Android omitem o sinalizador `--backend`:

```bash
healthmd export --last 7 --raw --provider health_connect \
  --raw-format ndjson --output health-connect.ndjson
```

`--provider` indica um único provedor explícito e usa `health_connect` como padrão. `--raw-format` usa NDJSON como padrão, o formato recomendado para snapshots grandes; a validação de JSON em memória é limitada a 64 MiB. A seleção de métricas aceita `--metric` e `--all-metrics`, mas não os seletores canônicos nem os de arquivos gerados — esses permanecem como recursos do iPhone.

Os snapshots brutos do Android mantêm seu contrato nativo do provedor Health Connect. Eles nunca são convertidos em dias `healthmd.health_data` no formato do HealthKit, e estatísticas relacionadas, porém diferentes, mantêm identidades próprias.

## Extração canônica

A extração direta usa o mesmo transporte bruto persistente, mas retorna dados selecionados no formato da origem, em vez do envelope de transporte. É um recurso do iPhone:

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

A seleção de métrica, categoria, origem e nível de detalhe chega ao iPhone antes das leituras do HealthKit. Consulte [Extração canônica](/pt-br/docs/cli-extract/) para conhecer seletores de objetos, JSON Pointers, JSONL e recibos.

Enquanto o app permanece em primeiro plano, uma sessão direta confiável pode se reconectar automaticamente após uma interrupção temporária, com tentativas e esperas limitadas. Isso não desperta nem promete acesso a um app em segundo plano; reabra o Health.md antes de retomar.

## Arquivos gerados em produção

O modo direto de arquivos solicita que o telefone execute os exportadores de produção do Health.md e transfere os arquivos resultantes para um destino explícito no computador.

```bash
mkdir -p "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --last 7 \
  --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

O destino deve existir, ser absoluto e não ser resolvido por meio de um link simbólico. O modo direto nunca pressupõe nem usa um bookmark do app para Mac. `--output` serve para a saída bruta ou de extração; `--destination` serve para arquivos gerados.

Por padrão, uma solicitação preserva os formatos salvos, a subpasta Health, os nomes de arquivos, os modelos, o modo de gravação, a Injeção em Nota Diária e a opção Somente Notas Diárias. Ela suprime consolidações e o modo somente resumo para essa tarefa. As opções repetíveis `--metric` ou `--category`, junto com `--detail`, substituem apenas o escopo de métricas e detalhes da tarefa. `--use-iphone-settings` replica todos os ajustes salvos e não pode ser combinado com seletores.

O iPhone pode preparar JSON, CSV, Markdown, ZIP, dicionários de dados, consolidações, registros individuais, notas diárias e arquivos complementares de provedores. Antes de confirmar, a CLI valida cada caminho relativo, contagem de bytes, resumo, manifesto de arquivos, identidade do destino e impressão digital da solicitação. Ela rejeita travessia de diretórios, ancestrais que sejam links simbólicos, alteração da raiz, colisões de caminhos e mudanças de resumo. A substituição é atômica. A anexação e a mesclagem de Markdown usam planos persistentes para que uma repetição não duplique conteúdo.

Os destinos de arquivos gerados funcionam com o protocolo v1 do iPhone e o protocolo v2 do Android em todos os sistemas operacionais da CLI — macOS, Linux e Windows. O Android limita cada tarefa a 4.096 arquivos.

As tarefas de arquivos do protocolo v2 do Android recebem suas configurações de saída das seleções salvas no dispositivo ou de `--profile PROFILE_ID`; os seletores de métrica, categoria e nível de detalhe da CLI são rejeitados. Nas duas plataformas de telefone, `--profile` resolve configurações de saída congeladas, enquanto o `--destination` obrigatório continua definindo a pasta explícita no computador.
Para IDs estáveis e falhas seguras, consulte [Perfis de exportação](/pt-br/docs/export-profiles/).

## Comportamento em primeiro e segundo plano

O emparelhamento e as novas tarefas exigem que o app do telefone esteja em primeiro plano. O Acesso ao Direct CLI não transforma o telefone em um servidor de exportação sem interface e não pode ativar o app sob demanda.

No iPhone, se uma exportação já estiver conectada quando o app passar para segundo plano, o Health.md solicitará um período finito de execução em segundo plano no iOS. A exportação poderá ser concluída durante esse período. Se o iOS encerrar esse período, a conexão será fechada e a tarefa persistente será pausada. Reabra o Health.md e retome a mesma tarefa.

No Android, uma sessão direta ativa executa um serviço de primeiro plano visível de sincronização de dados, iniciado pelo usuário. Mantenha o app em primeiro plano para o emparelhamento e as novas tarefas.

No iPhone, um banner de atividade global durante tarefas diretas inclui a fase de captura e transferência, os dias concluídos, o progresso em bytes e o status pausado ou concluído, sem exibir valores de saúde.

Enquanto o app do telefone permanecer em primeiro plano, uma sessão direta confiável poderá se reconectar automaticamente após uma interrupção temporária. As tentativas usam atrasos progressivos limitados a um máximo curto. Isso não desperta nem garante acesso a um app em segundo plano; reabra o Health.md antes de retomar se ele não estiver mais em primeiro plano.

A janela de espera limitada de 120 segundos mantém a mesma solicitação aberta enquanto a pessoa desbloqueia o telefone e abre o Health.md. Ajuste com `--wake-timeout SECONDS`; `0` desativa. O MCP usa `HEALTHMD_WAKE_TIMEOUT`. Os binários alpha.6 publicados apenas aguardam. Nas builds oficiais posteriores, um iPhone inscrito também recebe uma única notificação APNs de melhor esforço pelo serviço de ativação exclusivo para notificações do Health.md; Android e iPhones não inscritos continuam apenas aguardando. A notificação pode restabelecer a presença da pessoa, mas nunca autoriza uma leitura do HealthKit nem envia o escopo de saúde pelo Worker.

## Retomada e cancelamento persistentes

As tarefas diretas expiram sete dias após a criação. Timeout, Ctrl-C, encerramento do processo, desconexão e expiração da execução em segundo plano não as cancelam.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

A retomada preserva as datas, os ajustes, o destino, a impressão digital da solicitação, o dispositivo e a fronteira das partições originais. Você não pode direcionar uma tarefa de arquivos a outro destino durante a retomada.

O cancelamento registra uma solicitação persistente, mas só se torna terminal após a confirmação pelo telefone emparelhado. Se o telefone estiver indisponível, o status permanecerá `cancellation_pending`. Reabra o mesmo telefone e tente cancelar novamente.

## Modelo de segurança

- Os emparelhamentos portáteis atuais usam troca efêmera de chaves e provas de transcrição do seletor 3 vinculadas a um código compartilhado de alta entropia com 20 dígitos (~66 bits) para iOS e Android. Os fluxos antigos do seletor 1 da Apple e do seletor 2 do Android permanecem compatíveis byte a byte.
- As transferências por QR são aceitas apenas por scanners explícitos dentro do app para endereços privados LAN/Tailscale canônicos; abrir uma URL personalizada externa não pode autorizar o emparelhamento.
- A reconexão comprova um segredo aleatório armazenado e as identidades de ambas as instalações.
- Cada conexão deriva novas chaves e nonces.
- Mensagens e quadros binários usam ChaCha20-Poly1305 com verificações de sequência monotônica.
- As partições usam manifestos SHA-256 e uma fronteira encadeada de resumos.
- A relação de confiança do iPhone é armazenada no Keychain; a confiança de reconexão do Android é protegida pelo Keystore.
- A relação de confiança portátil usa Keychain, Secret Service ou Windows Credential Manager e nunca recorre a texto simples.
- Spools e diários usam armazenamento privado do aplicativo e são excluídos de backups quando a plataforma oferece suporte a isso.

O IP manual permanece criptografado em uma rede local ou no Tailscale. O Tailscale também protege o caminho de rede, mas não substitui a autenticação do aplicativo Health.md.

## Erros comuns

| Erro | Ação |
|---|---|
| `direct_not_paired` | Emparelhe esta instalação da CLI com a fonte móvel desejada. |
| `direct_device_selection_required` | Informe o `--device` confiável desejado. |
| `direct_trust_invalid` | Preserve os diagnósticos. Redefina a confiança somente quando a recuperação for impossível. |
| `direct_iphone_unavailable` | Verifique o estado do app em primeiro plano, a opção de acesso, o endereço, a porta, a permissão e a acessibilidade pela LAN ou pelo Tailscale. |
| `direct_export_paused` | Inspecione a tarefa, reabra o telefone emparelhado e retome-a. |
| `direct_cancellation_pending` | Reabra o telefone emparelhado e tente cancelar novamente. |
| `transport_unsupported` | Use IP manual ou Tailscale no cliente portátil. |
| `backend_unsupported` | Use o backend do app para Mac para consultas, evidências, diagnóstico, métricas ou MCP. |
| `invalid_direct_raw_response` | Não consuma a saída. Preserve os diagnósticos de validação. |
| `invalid_direct_file_receipt` | Não repare os arquivos manualmente. Inspecione e retome a tarefa. |
| `job_expired` | O período de sete dias do estado terminou. Confirme antes de iniciar uma nova tarefa. |

## Conteúdo relacionado

<div class="related">
  <a href="/pt-br/docs/cli/"><span>Visão geral</span>CLI do Health.md: instale os auxiliares integrados e escolha o backend adequado.</a>
  <a href="/pt-br/docs/android/"><span>Android</span>Health.md para Android: fontes do Health Connect, destinos em pastas e automação no dispositivo.</a>
  <a href="/pt-br/docs/cli-extract/"><span>Dados</span>Extração canônica: selecione e emita dados do Health.md no formato da origem (iPhone).</a>
  <a href="/pt-br/docs/cli-jobs/"><span>Confiabilidade</span>Tarefas persistentes e automação: retomada, cancelamento, resultados parciais e scripts.</a>
  <a href="/pt-br/docs/reference/connected-mac-iphone-protocol/"><span>Protocolo</span>Referência da conexão entre Mac e iPhone: recursos, transferência limitada e estados dos resultados.</a>
</div>
