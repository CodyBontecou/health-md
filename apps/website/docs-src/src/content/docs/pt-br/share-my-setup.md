---
title: "Compartilhar minha configuração"
description: "Revise o fluxo v2 apenas de desenvolvimento para mover perfis sem saúde, credenciais, compras ou confiança do aparelho."
---

<div class="availability preview"><strong>Prévia de desenvolvimento · sem qualificação de lançamento</strong><p>O contrato v2 segue pré-canônico e planejado até concluir interoperabilidade e acessibilidade em aparelhos. Não dependa dele em produção.</p></div>

Share My Setup reúne um ou mais perfis. Transfere métricas, formatos, nomes, organização e intenção de destino. Nunca inclui saúde, tokens, acesso real a pastas, pareamentos, compras, histórico ou trabalhos.

1. Na origem, abra **Ajustes → Share My Setup** e exporte o arquivo v2.
2. Abra no destino e revise cada perfil.
3. Escolha **Adicionar** ou **Substituir**.
4. Vincule localmente pasta, API com credenciais ou Mac.
5. Aplique e teste uma exportação pequena.

A transação é atômica e oferece **Desfazer** uma vez. Perfis ficam bloqueados até o destino ser vinculado; agendas chegam desligadas. O código de desenvolvimento atual escreve somente `healthmd.shared_setup` v2; v1 é recusado.

<div class="related"><a href="/pt-br/docs/export-profiles/"><span>Perfis</span>Ajustes congelados.</a><a href="/pt-br/docs/guides/platform-features/"><span>Status</span>Qualificação.</a></div>
