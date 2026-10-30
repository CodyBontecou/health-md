---
title: "Exportar"
description: "Use a guia Exportar para verificar HealthKit e conexões do vault. Selecione um destino e exporte um intervalo de datas."
---

<p> A guia Exportar é organizada em três pequenas decisões: confirmar a disponibilidade, escolher um destino e, em seguida, escolher o intervalo de datas antes de visualizar ou exportar. </p>

## Leia os crachás de status
 <div class="options">
 <div class="option"> <strong> Crachá de saúde </strong> <p>Verde indica o estado de configuração Conectado do app, não confirma acesso de leitura a todas as categorias. O HealthKit não revela permissões de leitura negadas. Toque no indicador para solicitar acesso. O iOS pode mostrar um diálogo para tipos que precisam de uma decisão; se as escolhas já estiverem registradas, o Health.md mostra as orientações de permissão. Confira as categorias no Apple Health. Um resultado vazio pode significar acesso negado ou ausência de dados correspondentes. <a href="/pt-br/docs/troubleshooting/">Resolver dados ausentes</a>.</p> </div>
 <div class="option"> <strong> Crachá do Vault </strong> <p> Ponto verde = uma pasta do Vault está selecionada. Toque para selecionar novamente ou alterar o cofre. O rótulo mostra o nome da pasta. </p> </div>
 </div>
 <p> A ação <em> Exportar </em> permanece desativada até que HealthKit , o formato de saída e o destino selecionado estejam prontos. Isso evita o modo de falha mais comum: tentar exportar sem destino. </p>

## Escolha um destino de exportação
 <p> O cartão Destino de exportação decide para onde vão os dados: </p>

<div class="options">
 <div class="option"> <strong> Local iPhone Pasta </strong> <p> Grava diretamente na pasta ou cofre Obsidian que você escolheu neste dispositivo. </p> </div>
 <div class="option"> <strong> Mac conectado </strong> <p> Envia dados diários capturados e um instantâneo exato das configurações para o aplicativo Mac próximo. O iPhone lê HealthKit . O Mac renderiza os formatos selecionados e grava os arquivos. </p> </div>
 <div class="option"> <strong> API Endpoint </strong> <p> POSTA um envelope JSON diretamente de iPhone para um endpoint HTTP(S) configurado pelo usuário. <a href="/pt-br/docs/api-endpoint/"> Consulte Ponto final da API </a> . </p> </div>
 </div>

## Escolha um intervalo de datas
 <p> As predefinições de data cobrem os caminhos comuns: </p>

<div class="options">
 <div class="option"> <strong> Hoje </strong> <p> Exporta o dia atual. Útil para testar a formatação de saída. </p> </div>
 <div class="option"> <strong> Ontem </strong> <p> A escolha de exportação diária mais segura porque o dia está completo. </p> </div>
 <div class="option"> <strong> Todo o tempo </strong> <p> Preencha a partir dos primeiros dados HealthKit Health.md puder encontrar. </p> </div>
 <div class="option"> <strong> Personalizado </strong> <p> Escolha datas de início e término para um intervalo específico. </p> </div>
 </div>

## Pré-visualizar ou Exportar
 <div class="options">
 <div class="option"> <strong> Pré-visualizar </strong> <p> Mostra os arquivos e conteúdos que serão gerados antes de qualquer coisa ser escrita. </p> </div>
 <div class="option"> <strong> Exportar </strong> <p> Executa a exportação, mostra o progresso na tela principal e registra o resultado no histórico. </p> </div>
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

Um perfil salvo congela suas configurações e destino da execução. As linhas do histórico de automação e programado com reconhecimento de perfil mantêm o perfil de tempo de execução, enquanto o histórico mantém um rótulo de segurança de privacidade para o destino realmente usado. Uma linha da guia Exportação manual pode omitir o nome do perfil. Renomeações posteriores e alterações de destino não reescrevem o histórico existente. Se o perfil referenciado estiver ausente, a operação falha sem usar outras configurações. Consulte [Exportar perfis](/pt-br/docs/export-profiles/).

## Barra de guias

<p> As quatro guias na parte inferior da tela, Exportar, Agendar, Sincronizar, Configurações, cobrem toda a área de superfície do aplicativo. Todo o resto reside em uma ou duas camadas nas configurações. </p>

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
