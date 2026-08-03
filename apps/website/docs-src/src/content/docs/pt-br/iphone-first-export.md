---
title: "Primeira exportação no iPhone"
description: "Autorize o Apple Health, escolha um destino no app Arquivos, visualize a saída do Health.md, faça uma pequena primeira exportação no iPhone e verifique os arquivos gravados."
---

Use este guia para produzir uma exportação pequena e verificável antes de alterar métricas, formatação ou automação. O Health.md lê apenas as categorias do Apple Health autorizadas pelo iOS e grava os arquivos gerados na pasta que você escolher.

<div class="availability available">
<strong>Disponível agora · Health.md para iPhone</strong>
<p>A primeira exportação está incluída no limite gratuito. O agendamento e outros recursos pagos podem ser configurados depois.</p>
</div>

## Antes de começar

Você precisa de:

- Health.md instalado em um iPhone que contenha dados do Apple Health;
- permissão para ler pelo menos uma categoria do Apple Health;
- um destino gravável no app Arquivos, como iCloud Drive, No Meu iPhone ou um cofre do Obsidian.

Para agilizar a primeira execução, mantenha as métricas padrão e a saída em Markdown. Comece com **Ontem** ou outro intervalo de um dia, em vez de todo o histórico disponível.

## 1. Conclua a configuração do iPhone

Na primeira inicialização, toque em **Start Setup** (“Iniciar configuração”) e conclua as sete etapas de introdução. Autorize as categorias de saúde desejadas, examine a saída de exemplo, escolha uma pasta no app Arquivos e avance até **Ready** (“Pronto”). Quando aparecer a etapa de desbloqueio, você pode continuar com o limite gratuito.

Se você já concluiu a introdução, abra a aba **Exportar** e confirme que o Apple Health e a pasta local estão prontos. Use o controle de pasta para substituir um destino ausente ou inacessível.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Abrir a captura de tela da introdução em tamanho real">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Tela de boas-vindas da introdução do Health.md na etapa 1 de 7, com o botão Start Setup." />
  </a>
  <figcaption>Start Setup apresenta o arquivo local, as notas agendadas e o modelo de pastas antes de solicitar acesso. A interface desta captura autêntica permanece em inglês.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-setup-required.webp" target="_blank" rel="noopener" aria-label="Abrir a captura de tela de configuração necessária em tamanho real">
    <img src="/docs/assets/docs/iphone-first-export/export-setup-required.webp" width="1206" height="2622" loading="lazy" alt="Aba Export do Health.md com Saúde desconectada, Choose Folder disponível, Local iPhone Folder selecionada e botões de intervalo de datas." />
  </a>
  <figcaption>Os indicadores de prontidão deixam explícita a ausência da configuração de Saúde e da pasta. Esta captura de referência também permanece em inglês e mostra intencionalmente os dois requisitos incompletos.</figcaption>
</figure>
</div>

## 2. Escolha uma exportação pequena

Na aba Exportar:

1. Selecione **Pasta local do iPhone** como destino.
2. Escolha **Ontem** ou um intervalo personalizado de um dia.
3. Mantenha a seleção padrão de métricas na primeira execução.
4. Mantenha **Markdown** selecionado. Você pode adicionar CSV, JSON ou Obsidian Bases depois que o fluxo básico funcionar.

Um intervalo curto facilita a identificação de problemas com permissões, categorias vazias e destino. Também evita interpretar uma primeira solicitação demorada como uma exportação com falha.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/pt-br/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Abrir a captura de tela de seleção de métricas em tamanho real">
    <img src="/docs/assets/docs/pt-br/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Tela atual de Métricas de Saúde com 217 de 219 métricas ativadas, o seletor de métricas padrão ligado, o campo de busca e as categorias Sono, Atividade e Coração." />
  </a>
  <figcaption>Os totais de métricas dependem da versão instalada do app e das permissões. Esta captura localizada mostra 217 de 219 métricas ativadas e as métricas padrão ligadas; não é preciso chegar a esse total para fazer a primeira exportação.</figcaption>
</figure>

## 3. Visualize antes de gravar

Toque em **Pré-visualizar**. A pré-visualização exige acesso ao Apple Health, mas não precisa de uma pasta local gravável. Por isso, ela ajuda a distinguir um problema de permissão de leitura de um problema no app Arquivos.

Confira se a pré-visualização mostra:

- a data solicitada;
- os nomes e as unidades esperados das métricas;
- valores ausentes ou indisponíveis indicados explicitamente, em vez de zeros inventados;
- o formato selecionado e a estrutura do nome do arquivo.

Volte à aba Exportar se precisar ajustar datas, métricas ou formatação.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/pt-br/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Abrir a captura de tela da pré-visualização da exportação em tamanho real">
    <img src="/docs/assets/docs/pt-br/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Pré-visualização da Exportação do Health.md mostrando uma estimativa de exportação Markdown de um dia, períodos de consolidação, destino e nome do arquivo gerado." />
  </a>
  <figcaption>A pré-visualização separa a inspeção da saída da gravação. Esta captura determinística da documentação usa dados de Saúde de exemplo e mostra explicitamente que nenhum cofre está selecionado.</figcaption>
</figure>

## 4. Exporte e verifique

Toque em **Exportar dados**. Se a configuração estiver incompleta, o Health.md identifica o requisito ausente de Saúde ou de pasta, em vez de iniciar silenciosamente uma gravação parcial.

Após a conclusão:

1. Confira no app quais arquivos foram gravados, ignorados ou apresentaram falha.
2. Abra o app Arquivos e navegue até a pasta selecionada.
3. Abra um arquivo gerado e confirme a data, as unidades e o frontmatter.
4. Guarde os detalhes do resultado para solucionar problemas; não presuma que houve sucesso apenas porque o botão voltou ao estado ocioso.

<div class="callout">
<strong>Não há dados para o dia selecionado?</strong>
<p style="margin-top:6px;">Tente um dia que você sabe que contém dados de atividade ou sono. Depois, confira a autorização de Saúde e a seleção de métricas. Um intervalo autorizado vazio é diferente de uma falha de transporte ou gravação.</p>
</div>

## Próximas etapas

<div class="related">
  <a href="/pt-br/docs/metrics/"><span>Escolher dados</span>Pesquise métricas do Apple Health e ajuste categorias ou permissões especiais.</a>
  <a href="/pt-br/docs/format/"><span>Definir a saída</span>Configure formatos, datas, unidades, frontmatter, modelos e nomes de arquivos.</a>
  <a href="/pt-br/docs/scheduling/"><span>Automatizar</span>Agende exportações recorrentes depois de verificar uma execução manual.</a>
  <a href="/pt-br/docs/folder-vault/"><span>Corrigir um destino</span>Entenda provedores do app Arquivos, acesso a pastas e recuperação.</a>
</div>
