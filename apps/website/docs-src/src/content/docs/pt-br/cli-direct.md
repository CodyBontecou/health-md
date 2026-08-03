---
title: "CLI direta para iPhone"
description: "Emparelhe o healthmd com um iPhone por IP manual, Tailscale ou um transporte por proximidade compatível e exporte sem executar o Health.md para Mac."
---

O backend direto conecta o `healthmd` a um app Health.md aberto no iPhone sem encaminhar o comando pelo Health.md para Mac. O iPhone lê o HealthKit, prepara o resultado em armazenamento protegido e transfere partições validadas para a CLI.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone -> HealthKit -> protected bounded spool / typed query evaluator
  -> canonical JSON, production-generated files, or bounded MCP query pages
```

<div class="availability preview">
<strong>Prévia · CLI direta portátil</strong>
<p>O backend direto Swift integrado está disponível no macOS. O cliente Rust multiplataforma é uma versão alfa que aguarda a validação de lançamento em iPhones físicos e seu primeiro pacote público; os comandos para Linux e Windows descrevem o fluxo de trabalho planejado.</p>
</div>

## O que o modo direto oferece

- emparelhamento único e reconexão confiável;
- inspeção local de dispositivos confiáveis e desemparelhamento;
- prontidão do iPhone em tempo real;
- exportação bruta estrita no schema v7;
- extração canônica selecionada;
- exportação de arquivos gerados em produção;
- status local persistente de tarefas e retomada;
- cancelamento explícito;
- o servidor stdio `healthmd mcp serve` no mesmo executável, com consultas tipadas diretas, catálogo de métricas, evidências, interface do MCP Apps e alternativa em PNG.

O backend direto do comando `healthmd` não emula as rotas HTTP de contexto criptografado do app para Mac. Portanto, os subcomandos `doctor` orientados ao Mac, assim como os de consulta, evidências e atualização, continuam retornando `backend_unsupported` em vez de trocar de backend. Use `healthmd mcp serve` para análises tipadas recentes diretamente do iPhone ou execute `healthmd setup codex` para configurar e emparelhar o Codex automaticamente. `healthmd mcp schema [TOOL]` imprime localmente o schema exato e aninhado da entrada MCP, além de exemplos; use `healthmd_sleep_sessions` diretamente para sono, em vez de tratar a saída canônica de `extract` como a API de consulta tipada.

## Requisitos

- Um binário `healthmd` com suporte ao modo direto e uma versão correspondente do Health.md para iPhone.
- O Health.md aberto em primeiro plano no iPhone para emparelhamento e novos comandos.
- **Ajustes > Sincronização com Mac > Acesso ao Direct CLI** ativado no iPhone.
- Permissão do HealthKit, dados protegidos, permissão de rede local e cota de exportação disponíveis.
- Um endereço de computador acessível e a porta TCP `17647` para IP manual. Um endereço do Tailscale funciona.
- Um destino absoluto existente para o modo de arquivos gerados.

A CLI atua como listener. O iPhone se conecta ao endereço do computador informado no Acesso ao Direct CLI.

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

O comando grava um código de seis dígitos, possíveis endereços do computador e a porta do listener em stderr, mantendo stdout reservado para o resultado JSON final.

No iPhone:

1. Abra **Health.md > Ajustes > Sincronização com Mac > Acesso ao Direct CLI**.
2. Ative o Acesso ao Direct CLI.
3. Selecione **IP manual**.
4. Digite o endereço LAN ou Tailscale do computador.
5. Digite a porta `17647`, a menos que a CLI use outra opção global `--port`.
6. Digite o código de emparelhamento e toque em Emparelhar.
7. Mantenha o app aberto até que ambos os lados informem sucesso.

Os códigos de emparelhamento expiram após 10 minutos. Eles nunca são enviados pela rede nem mantidos de forma persistente.

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

Esses comandos leem ou alteram a confiança local e não entram em contato com o iPhone. No iPhone, use **Esquecer CLI emparelhada** para remover a outra parte.

Quando houver mais de um iPhone confiável, selecione explicitamente a instalação desejada:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Use `healthmd direct reset-trust --confirm` somente quando a confiança local estiver corrompida ou pertencer a uma instalação substituída. Esse comando remove todos os emparelhamentos diretos locais. Esqueça esses emparelhamentos no iPhone antes de recomeçar.

## Verifique a prontidão em tempo real

```bash
healthmd --backend direct --transport manual-ip status
```

Uma resposta de status direto informa o estado da conexão e da segurança sem valores de saúde. Verifique estes campos antes de iniciar uma tarefa:

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

## Exportação bruta estrita

Escolha um seletor de intervalo:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Omita `--output` para transmitir o JSON validado por stdout. Um arquivo de saída é mais seguro para respostas confidenciais ou grandes.

A exportação bruta estrita retorna `healthmd.raw_result` v1 contendo dias comuns de `healthmd.health_data` no schema v7 e seus arquivos canônicos de origem. Ela solicita temporariamente detalhes sem perdas sem alterar os ajustes salvos no iPhone. A CLI valida as datas exatas, o perfil, o schema, o arquivo, os manifestos, a cadeia de resumos, o resumo final do corpo e o estado de conclusão antes de disponibilizar o resultado.

Um dia completo sem dados é considerado bem-sucedido. Dados solicitados ausentes, parciais, com falha, cancelados, incompatíveis ou ignorados produzem `partial_success` e um código de saída diferente de zero, a menos que `--allow-partial` seja especificado explicitamente.

## Extração canônica

A extração direta usa o mesmo transporte bruto persistente, mas retorna dados selecionados no formato da origem, em vez do envelope de transporte:

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

A seleção de métrica, categoria, origem e nível de detalhe chega ao iPhone antes das leituras do HealthKit. Consulte [Extração canônica](/pt-br/docs/cli-extract/) para conhecer seletores de objetos, JSON Pointers, JSONL e recibos.

## Arquivos gerados em produção

O modo direto de arquivos solicita que o iPhone execute os exportadores de produção do Health.md e transfira os arquivos resultantes para um destino explícito no computador.

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

Os destinos de arquivos gerados funcionam no macOS e no Linux. O protocolo v1 os rejeita no Windows. Usuários do modo direto no Windows podem usar a exportação bruta e a extração.

## Comportamento em primeiro e segundo plano

O emparelhamento e as novas tarefas exigem que o app do iPhone esteja em primeiro plano. O Acesso ao Direct CLI não transforma o iOS em um servidor de exportação sem interface e não pode ativar o app sob demanda.

Se uma exportação já estiver conectada quando o app passar para segundo plano, o Health.md solicitará um período finito de execução em segundo plano no iOS. A exportação poderá ser concluída durante esse período. Se o iOS encerrar esse período, a conexão será fechada e a tarefa persistente será pausada. Reabra o Health.md e retome a mesma tarefa.

O iPhone exibe um banner de atividade global durante tarefas diretas. Ele inclui a fase de captura e transferência, os dias concluídos, o progresso em bytes e o status pausado ou concluído, sem exibir valores de saúde.

## Retomada e cancelamento persistentes

As tarefas diretas expiram sete dias após a criação. Timeout, Ctrl-C, encerramento do processo, desconexão e expiração da execução em segundo plano não as cancelam.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

A retomada preserva as datas, os ajustes, o destino, a impressão digital da solicitação, o dispositivo e a fronteira das partições originais. Você não pode direcionar uma tarefa de arquivos a outro destino durante a retomada.

O cancelamento registra uma solicitação persistente, mas só se torna terminal após a confirmação pelo iPhone. Se o iPhone estiver indisponível, o status permanecerá `cancellation_pending`. Reabra o mesmo iPhone e tente cancelar novamente.

## Modelo de segurança

- O emparelhamento usa uma troca efêmera de chaves Curve25519 e provas de transcrição vinculadas ao código de seis dígitos.
- A reconexão comprova um segredo aleatório armazenado e as identidades de ambas as instalações.
- Cada conexão deriva novas chaves e nonces.
- Mensagens e quadros binários usam ChaCha20-Poly1305 com verificações de sequência monotônica.
- As partições usam manifestos SHA-256 e uma fronteira encadeada de resumos.
- A relação de confiança do iPhone é armazenada no Keychain.
- A relação de confiança portátil usa Keychain, Secret Service ou Windows Credential Manager e nunca recorre a texto simples.
- Spools e diários usam armazenamento privado do aplicativo e são excluídos de backups quando a plataforma oferece suporte a isso.

O IP manual permanece criptografado em uma rede local ou no Tailscale. O Tailscale também protege o caminho de rede, mas não substitui a autenticação do aplicativo Health.md.

## Erros comuns

| Erro | Ação |
|---|---|
| `direct_not_paired` | Emparelhe esta instalação da CLI com o iPhone. |
| `direct_device_selection_required` | Informe o `--device` confiável desejado. |
| `direct_trust_invalid` | Preserve os diagnósticos. Redefina a confiança somente quando a recuperação for impossível. |
| `direct_iphone_unavailable` | Verifique o estado do app em primeiro plano, a opção de acesso, o endereço, a porta, a permissão e a acessibilidade pela LAN ou pelo Tailscale. |
| `direct_export_paused` | Inspecione a tarefa, reabra o iPhone e retome-a. |
| `direct_cancellation_pending` | Reabra o iPhone emparelhado e tente cancelar novamente. |
| `transport_unsupported` | Use IP manual ou Tailscale no cliente portátil. |
| `backend_unsupported` | Use o backend do app para Mac para consultas, evidências, diagnóstico, métricas ou MCP. |
| `invalid_direct_raw_response` | Não consuma a saída. Preserve os diagnósticos de validação. |
| `invalid_direct_file_receipt` | Não repare os arquivos manualmente. Inspecione e retome a tarefa. |
| `job_expired` | O período de sete dias do estado terminou. Confirme antes de iniciar uma nova tarefa. |

## Conteúdo relacionado

<div class="related">
  <a href="/pt-br/docs/cli/"><span>Visão geral</span>CLI do Health.md: instale os auxiliares integrados e escolha o backend adequado.</a>
  <a href="/pt-br/docs/cli-extract/"><span>Dados</span>Extração canônica: selecione e emita dados do Health.md no formato da origem.</a>
  <a href="/pt-br/docs/cli-jobs/"><span>Confiabilidade</span>Tarefas persistentes e automação: retomada, cancelamento, resultados parciais e scripts.</a>
  <a href="/pt-br/docs/reference/connected-mac-iphone-protocol/"><span>Protocolo</span>Referência da conexão entre Mac e iPhone: recursos, transferência limitada e estados dos resultados.</a>
</div>
