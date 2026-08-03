---
title: "Sincronização com o Mac"
description: "Use o app complementar para macOS como destino local. O iPhone captura dados do HealthKit e configurações; o Mac renderiza e grava os arquivos solicitados."
---

## O que é
<p>A Sincronização com o Mac permite que o Mac produza exportações sem se tornar leitor do HealthKit. O iPhone continua sendo a fonte da verdade dos dados do Apple Health: captura os dados diários selecionados e uma cópia exata das configurações e transfere a tarefa ao Mac. O Mac usa os exportadores compartilhados para planejar caminhos, renderizar formatos e gravar os arquivos na pasta escolhida.</p>

<div class="doc-diagram"><div class="flow-steps" aria-label="Fluxo de exportação da Sincronização com o Mac"><span><strong>iPhone</strong>Captura dados do HealthKit e as configurações efetivas.</span><span><strong>Rede local</strong>Transfere a tarefa versionada ao app no Mac próximo.</span><span><strong>Mac</strong>Renderiza os formatos e grava na pasta escolhida.</span><span><strong>Cofre</strong>Obsidian, iCloud Drive ou qualquer pasta local recebe a exportação final.</span></div></div>

## Como ativar
<ol><li>Instale e abra o app para macOS.</li><li>No Mac, escolha uma pasta de destino.</li><li>No iPhone, abra a aba Sincronizar e ative a conectividade com o Mac.</li><li>Volte à aba Exportar, escolha <em>Mac conectado</em>, configure e toque em Exportar.</li></ol>

## O que é transferido
<ul><li>Uma solicitação versionada com intervalo e configurações efetivas</li><li>Mensagens de progresso e recursos durante a captura</li><li>Quadros limitados e validados por checksum com dados diários e a cópia exata das configurações</li><li>Um resultado estruturado de conclusão, conclusão parcial, falha, rejeição ou indisponibilidade</li></ul>
<p>Não é necessária conta nem nuvem remota de dados de saúde. A sincronização próxima usa Multipeer Connectivity criptografada; IP manual/Tailscale usa transporte Network.framework emparelhado e criptografado. Os dispositivos precisam se comunicar, e o iPhone continua sendo o leitor do HealthKit.</p>

## Quando usar
<div class="options"><div class="option"><strong>Cofres somente no computador</strong><p>Se o cofre do Obsidian existe apenas no Mac, este é o caminho direto entre o HealthKit do iPhone e os arquivos.</p></div><div class="option"><strong>Grandes preenchimentos retroativos</strong><p>Mantenha os arquivos finais no disco do computador enquanto o iPhone lê o HealthKit.</p></div><div class="option"><strong>Arquivos locais</strong><p>Grave em pastas com backup, versionamento ou indexação no macOS.</p></div></div>

<div class="callout"><strong>Rede local obrigatória.</strong><p style="margin-top:6px;">Os dispositivos devem estar próximos e autorizados a usar a rede local. Um iPhone somente na rede celular não descobre o Mac. Se a prontidão indicar que o Mac exige atenção, reabra o app e selecione novamente a pasta.</p></div>

## A Sincronização com o Mac e o Acesso ao Direct CLI são separados
<p>A Sincronização emparelha o iPhone com o app Health.md para Mac para exportações e contexto criptografado do agente. O Acesso ao Direct CLI cria outro domínio de confiança com uma instalação de linha de comando. O modo direto exporta dados brutos ou arquivos gerados sem o app para Mac, mas não usa o índice criptografado nem o MCP do Mac.</p>
<p>Consulte [CLI direta para iPhone](/pt-br/docs/cli-direct/) antes de ativar esse ajuste separado.</p>

## Relacionados
<div class="related"><a href="/pt-br/docs/macos/"><span>Computador</span>App para macOS — Exportar, Agendar e Histórico.</a><a href="/pt-br/docs/scheduling/"><span>Fluxo</span>Agendamento — automatize exportações.</a><a href="/pt-br/docs/cli-direct/"><span>Confiança separada</span>CLI direta para iPhone.</a><a href="/pt-br/docs/reference/connected-mac-iphone-protocol/"><span>Protocolo</span>Referência da conexão Mac–iPhone.</a></div>
