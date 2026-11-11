---
title: "Primeira exportação no iPhone"
description: "Autorize o Apple Health, escolha um destino no app Arquivos, visualize a saída do Health.md, faça uma pequena primeira exportação no iPhone e verifique os arquivos gravados."
---

Use este guia para produzir uma exportação pequena e verificável antes de alterar métricas, formatação ou automação. O Health.md lê apenas as categorias do Apple Health autorizadas pelo iOS e grava os arquivos gerados na pasta que você escolher.

<div class="availability available">
<strong>Disponível agora · Health.md para iPhone</strong>
<p>As exportações exigem um teste ativo, uma assinatura ou acesso Lifetime. Você pode configurar agendamentos e outras automações depois.</p>
</div>

## Antes de começar

Antes de começar, verifique se você tem:

- [Health.md na App Store](https://apps.apple.com/app/health-md/id6757763969), instalado em um iPhone com dados do Apple Health
- permissão para ler pelo menos uma categoria do Apple Health
- uma pasta gravável no app Arquivos: iCloud Drive, No Meu iPhone ou um cofre do Obsidian.

Mantenha as métricas padrão e o formato Markdown. Selecione **Ontem** para um intervalo de um dia.

## 1. Conclua a configuração do iPhone

O Health.md mostra cinco etapas de configuração. Nenhuma impede o avanço: o acesso ao Apple Health e a pasta podem ser pulados e resolvidos depois.

Na primeira inicialização, toque em **Conectar Apple Health**. Autorize as categorias de saúde desejadas, revise a saída de exemplo, escolha uma pasta no Arquivos e continue até a última etapa.

Depois da configuração, o app abre em **Arquivo**. Se o Apple Health ou a pasta precisarem de algo, o cartão **Requer atenção** no topo indica o que corrigir.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Abrir a captura da configuração em tamanho real">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Configuração do Health.md na etapa 1 de 5 com três etapas listadas e o botão para conectar o Apple Health." />
  </a>
  <figcaption>A configuração explica o que o Health.md lê e para onde vão os arquivos antes de pedir acesso. A interface desta captura permanece em inglês.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-now.webp" target="_blank" rel="noopener" aria-label="Abrir a captura de Exportar agora em tamanho real">
    <img src="/docs/assets/docs/iphone-first-export/export-now.webp" width="1206" height="2622" loading="lazy" alt="Painel Exportar agora do Health.md com Ontem selecionado, um botão de somente resumo do intervalo, um resumo de um arquivo para um dia e um botão de exportar." />
  </a>
  <figcaption>Exportar agora mostra o que será gravado antes de começar. Esta captura de referência também mantém a interface em inglês.</figcaption>
</figure>
</div>

## 2. Escolha uma exportação pequena

Toque no botão redondo **Exportar agora** ao lado da barra de abas. Em seguida:

1. Selecione **Ontem**.
2. Deixe **Somente resumo do intervalo de datas** desativado.
3. Confira se **Será gravado** mostra sua pasta e cerca de um arquivo para um dia.

A automação padrão usa a seleção de métricas padrão e **Markdown**. Para alterá-las, abra **Automações**, escolha a automação e depois **Métricas** ou **Formatos**. Adicione CSV, JSON ou Obsidian Bases depois que esta exportação funcionar. Um intervalo curto facilita encontrar problemas de permissão, de dados vazios e de pasta.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/pt-br/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Abrir a captura da seleção de métricas em tamanho real">
    <img src="/docs/assets/docs/pt-br/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Página Métricas do Health.md com a quantidade de métricas ativas, os botões Recomendado, Selecionar Tudo e Desmarcar Tudo, um campo de busca e categorias com contagens." />
  </a>
  <figcaption>O total de métricas depende da versão do app e das permissões. Esta captura localizada mostra 217 de 219 métricas ativadas.</figcaption>
</figure>

## 3. Confira a pré-visualização antes de gravar

Em **Exportar agora**, toque em **Pré-visualização**. A pré-visualização precisa de acesso ao Apple Health, mas não de uma pasta gravável.

Use a pré-visualização para identificar um problema de permissão do Apple Health antes de testar a pasta.

Verifique se a pré-visualização mostra:

- a data solicitada
- os nomes de métricas e as unidades esperados
- valores ausentes ou indisponíveis em vez de zeros falsos
- o formato escolhido e a estrutura do nome do arquivo.

Feche a pré-visualização e altere os ajustes da automação se precisar mudar métricas ou formatos.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/pt-br/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Abrir a captura da pré-visualização em tamanho real">
    <img src="/docs/assets/docs/pt-br/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Pré-visualização da exportação do Health.md com a janela de sono, a estimativa de um dia em Markdown, o período de resumo, a pasta de destino e o nome de arquivo gerado." />
  </a>
  <figcaption>Este exemplo usa dados de saúde de amostra.</figcaption>
</figure>

## 4. Exporte e verifique

Toque em **Exportar ontem**. Se a configuração estiver incompleta, o Health.md indica o que falta no Apple Health ou na pasta.

Quando a exportação terminar:

1. Confira no resultado os arquivos gravados, ignorados ou com falha. O dia aparece no calendário de **Arquivo**.
2. Abra o app Arquivos e a pasta escolhida.
3. Abra um arquivo gerado e confira se a data, as unidades e o frontmatter estão corretos.
4. Guarde os detalhes do resultado se precisar investigar um problema.

Um dia coberto no calendário é um resumo; toque no dia para ver o status de cada automação nessa data.

<div class="callout">
<strong>Sem dados para o dia escolhido?</strong>
<p style="margin-top:6px;">Escolha um dia com dados de atividade ou sono. Depois verifique a autorização do Apple Health e a seleção de métricas. Um intervalo vazio não é uma falha de gravação.</p>
</div>

## Próximas etapas

<div class="related">
  <a href="/pt-br/docs/metrics/"><span>Escolher dados</span>Pesquise métricas do Apple Health e ajuste categorias ou permissões especiais.</a>
  <a href="/pt-br/docs/format/"><span>Definir a saída</span>Configure formatos, datas, unidades, frontmatter, modelos e nomes de arquivos.</a>
  <a href="/pt-br/docs/scheduling/"><span>Automatizar</span>Agende exportações recorrentes depois de verificar uma execução manual.</a>
  <a href="/pt-br/docs/folder-vault/"><span>Corrigir um destino</span>Entenda provedores do app Arquivos, acesso a pastas e recuperação.</a>
</div>
