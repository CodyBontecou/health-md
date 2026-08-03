---
title: "Exportação"
description: "A aba Exportar é a tela principal. Ela mostra se o HealthKit e seu cofre estão conectados, permite escolher um destino e executa exportações avulsas para o intervalo selecionado."
---

<p>A aba Exportar organiza o processo em três decisões simples: confirme a prontidão, escolha um destino e selecione o intervalo antes de visualizar ou exportar.</p>

## Leia os indicadores de status
<div class="options"><div class="option"><strong>Indicador de Saúde</strong><p>Ponto verde = HealthKit autorizado. Vermelho = acesso não concedido. Toque para tentar novamente a folha de permissões do iOS. Isso só funciona na primeira vez por instalação; depois, o iOS não faz nada e você precisa corrigir em Ajustes → Privacidade e Segurança → Saúde.</p></div><div class="option"><strong>Indicador do cofre</strong><p>Ponto verde = uma pasta de cofre está selecionada. Toque para escolher novamente ou mudar o cofre. O rótulo mostra o nome da pasta.</p></div></div>
<p>A ação <em>Exportar</em> fica desativada até que HealthKit, formato de saída e destino estejam prontos. Isso evita a falha mais comum: tentar exportar sem destino.</p>

## Escolha um destino de exportação
<p>O cartão Destino da exportação define para onde os dados vão:</p>
<div class="options"><div class="option"><strong>Pasta local do iPhone</strong><p>Grava diretamente na pasta ou no cofre do Obsidian escolhido neste dispositivo.</p></div><div class="option"><strong>Mac conectado</strong><p>Envia os dados diários capturados e uma cópia exata das configurações ao app próximo no Mac. O iPhone lê o HealthKit; o Mac renderiza os formatos e grava os arquivos.</p></div><div class="option"><strong>Endpoint da API</strong><p>Envia por POST um envelope JSON diretamente do iPhone para um endpoint HTTP(S) configurado pelo usuário. <a href="/pt-br/docs/api-endpoint/">Veja Endpoint da API</a>.</p></div></div>

## Escolha um intervalo
<div class="options"><div class="option"><strong>Hoje</strong><p>Exporta o dia atual. Útil para testar a formatação.</p></div><div class="option"><strong>Ontem</strong><p>A opção mais segura para exportações diárias, pois o dia está completo.</p></div><div class="option"><strong>Todo o período</strong><p>Preenche desde os dados mais antigos que o Health.md encontrar no HealthKit.</p></div><div class="option"><strong>Personalizado</strong><p>Escolha datas inicial e final.</p></div></div>

## Prévia ou Exportar
<div class="options"><div class="option"><strong>Prévia</strong><p>Mostra os arquivos e o conteúdo que serão gerados antes de qualquer gravação.</p></div><div class="option"><strong>Exportar</strong><p>Executa a exportação, mostra o progresso e registra o resultado no histórico.</p></div></div>

## O que "exportar" realmente faz
<ol><li>Para cada dia, captura as projeções de resumo selecionadas e, quando Registros de Saúde sem Perdas está ativado, os registros canônicos de origem e diagnósticos de consulta.</li><li>Aplica o formato escolhido (Markdown, Bases, JSON ou CSV) e o modelo.</li><li>Grava um arquivo por dia em <code>{vault}/{subfolder}/</code>, transfere arquivos pelo fluxo do Mac conectado ou envia por POST um envelope JSON versionado ao endpoint.</li><li>Se <em>Rastreamento individual</em> estiver ativo, deriva arquivos Markdown por registro do arquivo canônico para destinos baseados em arquivos.</li><li>Se <em>Injeção em notas diárias</em> estiver ativa, mescla campos de resumo nas notas.</li></ol>
<p>JSON e CSV podem preservar registros canônicos. Markdown e Bases continuam legíveis e exibem diagnósticos compactos, sem incorporar o arquivo. Consulte a <a href="/pt-br/docs/reference/">referência completa de exportação</a> para schemas e regras de omissão.</p>

## Barra de abas
<p>As quatro abas — Exportar, Agendar, Sincronizar e Ajustes — abrangem todo o app. O restante fica um ou dois níveis abaixo de Ajustes.</p>
<div class="callout"><strong>Comportamento do desbloqueio.</strong><p style="margin-top:6px;">Full Access libera exportações ilimitadas, exportações agendadas, destinos no Mac e Atalhos. <a href="/pt-br/docs/paywall/">Veja a página do paywall</a>.</p></div>

## Relacionados
<div class="related"><a href="/pt-br/docs/scheduling/"><span>Uso diário</span>Agendamento — automatize para não precisar tocar em Exportar.</a><a href="/pt-br/docs/api-endpoint/"><span>Integrar</span>Endpoint da API — envie JSON selecionado ao seu serviço.</a><a href="/pt-br/docs/format/"><span>Personalizar</span>Formato — altere a aparência dos arquivos.</a><a href="/pt-br/docs/shortcuts/"><span>Avançado</span>Atalhos — acione exportações com Siri, automações ou outros apps.</a><a href="/pt-br/docs/reference/"><span>Referência</span>Referência de exportação — schemas, registros e exemplos.</a></div>
