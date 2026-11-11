---
title: "Exportar"
description: "Exporte dados do Apple Health agora ou por agendamento. Confira se está tudo pronto em Arquivo, escolha um intervalo em Exportar agora e defina o destino de cada automação."
---

<p>No iPhone, o Health.md tem três abas, <strong>Arquivo</strong>, <strong>Automações</strong> e <strong>Configurações</strong>, além de um botão redondo <strong>Exportar agora</strong>. No iPad, as abas ficam em uma barra lateral.</p>

## Confira se está tudo pronto em Arquivo
<p>O calendário de <strong>Arquivo</strong> mostra quais datas de saúde cada automação cobriu. Quando algo bloqueia as exportações, o cartão <strong>Requer atenção</strong> no topo indica o motivo:</p>
<div class="options">
<div class="option"><strong>Apple Health</strong><p>O Health.md mostra o estado de configuração do app, não um acesso de leitura confirmado a cada categoria. O HealthKit não revela permissões de leitura negadas. Revise as categorias no Apple Health. Resultados vazios podem significar acesso negado ou ausência de dados. <a href="/pt-br/docs/troubleshooting/">Resolva dados ausentes</a>.</p></div>
<div class="option"><strong>Pasta</strong><p>Escolha ou escolha de novo a pasta em <strong>Configurações → Pasta</strong>. Se o iOS perder o acesso depois que uma pasta for movida, o Health.md pede que você a escolha novamente; nada é apagado.</p></div>
</div>

## Escolha para onde uma automação exporta
<p>Cada automação tem seu próprio destino. Abra <strong>Automações</strong>, escolha a automação e depois <strong>Saída</strong>:</p>

<div class="options">
<div class="option"><strong>Pasta local</strong><p>Grava diretamente na pasta ou no cofre do Obsidian escolhido neste dispositivo.</p></div>
<div class="option"><strong>Mac conectado</strong><p>Envia os dados diários capturados e um instantâneo exato dos ajustes para o app do Mac próximo. O iPhone lê o HealthKit; o Mac gera os formatos escolhidos e grava os arquivos.</p></div>
<div class="option"><strong>Endpoint da API</strong><p>Envia por POST um envelope JSON direto do iPhone para um endpoint HTTP(S) que você configura. <a href="/pt-br/docs/api-endpoint/">Veja Endpoint da API</a>.</p></div>
<div class="option"><strong>Gateway do Agent Data</strong><p>Envia cada arquivo exportado, sem alterações, para o endpoint de ingestão do seu gateway.</p></div>
</div>

## Escolha um intervalo em Exportar agora
<p>Toque em <strong>Exportar agora</strong>, escolha a automação se tiver mais de uma e depois um intervalo:</p>

<div class="options">
<div class="option"><strong>Ontem</strong><p>A escolha mais segura para exportações diárias, porque o dia já terminou.</p></div>
<div class="option"><strong>7 dias / 30 dias</strong><p>A última semana ou o último mês, até ontem. A partir de 30 dias, o Health.md pede confirmação antes.</p></div>
<div class="option"><strong>Personalizado</strong><p>Escolha as datas de início e fim de um intervalo específico.</p></div>
</div>
<p><strong>Será gravado</strong> mostra o destino e, aproximadamente, quantos arquivos e dias a exportação cobre. <strong>Somente resumo do intervalo de datas</strong> grava um único arquivo de resumo em vez de arquivos diários. Hoje e Todo o histórico continuam disponíveis em <strong>Automações → Todos os ajustes de exportação</strong>.</p>

## Pré-visualização ou exportação
<div class="options">
<div class="option"><strong>Pré-visualização</strong><p>Mostra os arquivos e o conteúdo que serão gerados antes de gravar qualquer coisa.</p></div>
<div class="option"><strong>Exportar</strong><p>Executa a exportação, mostra o progresso acima da barra de abas com um botão Cancelar e registra o resultado no histórico e no calendário de Arquivo.</p></div>
</div>

## Escolha o nível de detalhe dos dados

<div class="options">
 <div class="option"> <strong> Resumo </strong> <p> Compacte totais diários e roll-ups para leitura, notas e painéis. </p> </div>
 <div class="option"> <strong> Série temporal detalhada </strong> <p> Amostras e intervalos selecionados com carimbo de data/hora. Este nível está disponível tanto no Apple quanto no Android quando a métrica escolhida expõe detalhes adequados. </p> </div>
 <div class="option"> <strong> Registros de saúde sem perdas </strong> <p> O arquivo canônico de registros de origem HealthKit . Este nível é exclusivo da Apple. O Android não transforma registros Health Connect em um arquivo HealthKit . </p> </div>
 </div>

## O que a "exportação" realmente faz
 <ol>
 <li> Para cada dia no intervalo, capture as projeções resumidas selecionadas. Adicione amostras compatíveis para séries temporais detalhadas. E, para registros de saúde sem perdas, adicione registros de origem canônica e diagnósticos de consulta. </li>
 <li> Aplique o formato escolhido ( Markdown , Bases, JSON ou CSV) e modelo. </li>
 <li> Grave um arquivo por dia em <code>{vault}/{subfolder}/</code> , transfira arquivos por meio do fluxo de trabalho do Mac conectado ou POST um envelope JSON com versão para seu endpoint de API. </li>
 <li> Se <em> Rastreamento individual </em> estiver ativado, derive os arquivos Markdown por entrada selecionados do arquivo canônico para destinos baseados em arquivo. </li>
 <li> Se <em> Injeção de notas diárias </em> estiver ativado, mescle os campos de resumo selecionados em suas notas diárias. </li>
 </ol>

<p> JSON e CSV podem preservar registros canônicos. Markdown e Bases permanecem legíveis e expõem diagnósticos de captura compacta em vez de incorporar o arquivo. Consulte a referência de exportação completa <a href="/pt-br/docs/reference/"> </a> para esquemas exatos e regras de omissão. </p>

## Pare, cancele e tente novamente

Interromper ou cancelar encerra apenas a tentativa atual. Os arquivos e as datas já concluídas permanecem concluídos, enquanto as datas não resolvidas permanecem disponíveis para novas tentativas. Cancelar uma tentativa agendada não desativa sua programação recorrente.

## Perfis e histórico confiável

Um perfil salvo congela seus ajustes e seu destino durante a execução. As linhas do histórico de exportações agendadas e de automações que conhecem o perfil mantêm o perfil usado, enquanto o histórico guarda um rótulo que preserva a privacidade para o destino realmente usado. Uma linha de exportação manual pode omitir o nome do perfil. Renomeações e mudanças de destino posteriores não reescrevem o histórico existente. Se um perfil referenciado não existir, a operação falha sem usar outros ajustes. Veja [Perfis de exportação](/pt-br/docs/export-profiles/).

<div class="callout">
 <strong> Comportamento de desbloqueio. </strong>
 <p style="margin-top:6px;"> As versões de telefone iPhone / iPad e Google Play habilitadas para assinatura exigem avaliação ativa, assinatura, vitalício ou acesso permanente preservado para exportações e agendamento. Não resta nenhuma permissão local de livre exportação. O complemento para Mac e a compilação de acesso incluído F-Droid mantêm suas exceções documentadas. <a href="/pt-br/docs/paywall/"> Consulte a página Paywall </a> para obter detalhes de compra da Apple. </p>
 </div>

## Relacionado

<div class="related">
 <a href="/pt-br/docs/export-profiles/"> <span> Configurações repetíveis </span> Exporte perfis, salve configurações independentes, destinos, programações e IDs de automação estáveis. </a>
 <a href="/pt-br/docs/scheduling/"> <span> Uso diário </span> Agendamento, automatize isso para nunca mais tocar em Exportar. </a>
 <a href="/pt-br/docs/api-endpoint/"> <span> Integre </span> API Endpoint, envie o JSON selecionado diretamente para seu próprio serviço. </a>
 <a href="/pt-br/docs/format/"> <span> Personalizar </span> Personalização de formato, altere a aparência de cada arquivo. </a>
 <a href="/pt-br/docs/shortcuts/"> <span> Power </span> Shortcuts , acione exportações de Siri , automações ou outros aplicativos. </a>
 <a href="/pt-br/docs/reference/"> <span> Referência </span> Exportar referência, esquemas, registros canônicos, diagnósticos e exemplos gerados. </a>
 </div>
