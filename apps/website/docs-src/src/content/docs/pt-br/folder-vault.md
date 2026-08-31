---
title: "Pasta e cofre"
description: "Escolha onde ficam seus arquivos Markdown e nomeie a subpasta em que as exportações serão gravadas. O cofre é apenas uma pasta do iOS — Obsidian, Arquivos, iCloud Drive e provedores de arquivos de terceiros funcionam."
---

## O que significa "cofre" aqui
<p>O app usa <em>cofre</em> como nome genérico da pasta escolhida, mesmo que você não use o Obsidian. Se usar, selecione a raiz do cofre do Obsidian. Caso contrário, escolha qualquer pasta — <code>Documents/Health</code> no iCloud Drive, uma pasta em No Meu iPhone etc.</p>

## Como funciona o seletor
<p>Ao tocar na linha do cofre, abre-se o seletor de documentos padrão do iOS (<code>UIDocumentPickerViewController</code>). Quando você escolhe uma pasta, o iOS retorna uma <em>URL com escopo de segurança</em> — uma referência duradoura que permite ao app continuar acessando a pasta entre inicializações sem pedir novamente. O app a armazena como marcador em <code>UserDefaults</code>.</p>

## Nome da subpasta
<p>Depois de escolher o cofre, você deve nomear a subpasta das exportações. O padrão é <code>Health</code>. O nome escolhido se torna o prefixo do caminho de todos os arquivos exportados:</p>

<div class="doc-diagram folder-tree" aria-label="Exemplo de árvore de pastas de exportação do Health.md">
<span>{vault}/</span>
<span>└─ <span class="accent">{subfolder}/</span> <span class="dim">← o nome definido no Health.md</span></span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-28-tuesday.md</span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-27-monday.json</span>
<span>&nbsp;&nbsp;&nbsp;└─ _healthmd_data_dictionary.json</span>
</div>

<p>Você pode alterar a subpasta depois em <em>Ajustes → Cofre do Obsidian</em>. Os arquivos existentes não são movidos.</p>

## Comportamento entre apps
<div class="options">
<div class="option"><strong>Obsidian</strong><p>Escolha a raiz do cofre do Obsidian. Defina a subpasta como, por exemplo, <code>Health</code>, para que as exportações apareçam como pasta na árvore do cofre.</p></div>
<div class="option"><strong>iCloud Drive</strong><p>Escolha uma pasta no iCloud Drive. Os arquivos são sincronizados automaticamente com todos os seus dispositivos Apple.</p></div>
<div class="option"><strong>No Meu iPhone</strong><p>Escolha uma pasta criada em Arquivos → No Meu iPhone. Somente local, sem sincronização.</p></div>
<div class="option"><strong>Provedores de terceiros</strong><p>Dropbox, Google Drive, Working Copy etc. — qualquer provedor disponível no app Arquivos funciona da mesma maneira.</p></div>
</div>

<div class="callout">
<strong>Uma peculiaridade do iOS.</strong>
<p style="margin-top:6px;">Se o iOS revogar o marcador com escopo de segurança — algo raro, geralmente restrito à exclusão ou movimentação da pasta original — as exportações começarão a falhar. Para corrigir, selecione novamente o cofre em <em>Ajustes</em>.</p>
</div>

## Substituir ou mover uma pasta com segurança

Quando um marcador salvo é resolvido em outro caminho, o Health.md vincula a pasta novamente de forma automática se a identidade persistente confirmar que é a mesma pasta. O app também pode aceitar um marcador com escopo de segurança resolvido com sucesso quando nem a pasta salva nem a resolvida expõe uma identidade persistente, o que é comum em provedores de nuvem. Um caminho parecido, por si só, nunca serve como prova. O histórico continua mostrando o rótulo de destino que preserva a privacidade usado por cada execução.

Selecione a pasta novamente se ela foi excluída, o acesso foi revogado, as identidades persistentes entram em conflito ou apenas um dos lados fornece identidade e a mudança não pode ser verificada. O Health.md não grava em um destino ambíguo. Como cada [perfil de exportação](/pt-br/docs/export-profiles/) possui seu destino, verifique ou selecione novamente a pasta afetada em cada perfil.

## Relacionados
<div class="related">
  <a href="/pt-br/docs/export-profiles/"><span>Perfis</span>Gerencie acesso a pastas e destinos por perfil.</a>
  <a href="/pt-br/docs/onboarding/"><span>Anterior</span>Introdução — onde você escolhe o cofre pela primeira vez.</a>
  <a href="/pt-br/docs/export/"><span>Próximo</span>Faça uma exportação para o novo cofre.</a>
  <a href="/pt-br/docs/format/"><span>Personalizar</span>Personalização do formato — como os arquivos da subpasta são gravados.</a>
</div>
