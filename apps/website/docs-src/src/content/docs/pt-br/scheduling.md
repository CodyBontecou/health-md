---
title: "Agendar exportações do Apple Health e resolver execuções perdidas"
description: "Verifique exportações agendadas, a janela de dias completos e a recuperação. O iOS não garante o horário; Repetir no histórico usa as configurações atuais."
---

Esta página descreve o agendamento no iPhone. O Android tem outras permissões em segundo plano e requisitos de compra; consulte [Automação no Android](/pt-br/docs/android/).

## Verifique a primeira exportação agendada

1. Ative o perfil desejado. Confira métricas, formatos, nível de detalhe, modo de gravação e destino. Exporte manualmente um dia completo e verifique o arquivo ou resultado do endpoint antes de automatizar.
2. Abra Agendar e Configurar ou Gerenciar agendamento. Ative-o, escolha Diário, Semanal ou Personalizado, ajuste o horário e comece com um dia completo de retrospectiva. Permita notificações se quiser lembretes locais de recuperação.
3. Confira o estado, a próxima ocorrência e o último resultado. Após uma tentativa, examine o histórico e o destino real; uma data futura ou notificação não comprova a gravação.
4. Verifique datas, unidades, cobertura e dados ausentes. Um arquivo salvo, sozinho, não comprova captura completa.

Na Apple, uma solicitação agendada que exporta pelo menos uma data compartilha as cinco ações gratuitas com exportações manuais e outras ações contabilizadas. Full Access remove esse limite compartilhado. Consulte [Desbloqueio e compras](/pt-br/docs/paywall/).

## Entenda a janela de dias completos

Agendamentos diários, semanais e personalizados podem ter retrospectiva. O personalizado repete a cada N dias, semanas ou meses desde a data inicial. Cada nova ocorrência reexporta toda a janela configurada, incluindo datas anteriores já exportadas. Três dias cobrem ontem e os dois dias anteriores; atrasos mantêm a janela ancorada no dia previsto.

A atualização de hoje é independente e não substitui essa janela. Confira caminhos e modo de gravação antes de sobrepor exportações; instantâneos repetidos do mesmo dia não são novas medições.

## Escolha a recuperação correta

- **Recuperação agendada pendente:** desbloqueie o iPhone, abra Health.md e examine a tentativa. Ela mantém as datas exatas não resolvidas, configurações salvas e destino. Datas concluídas permanecem concluídas; a recuperação não amplia a retrospectiva.
- **Repetir pelo histórico:** inicia outra execução para o intervalo com as configurações e o destino atuais e cria uma nova linha. Confira a configuração ativa antes de repetir. Isso não retoma a tentativa pendente congelada.
- **Destino alterado ou inacessível:** restaure o acesso ou examine o perfil pendente. Uma recuperação API antiga do iPhone não deve adotar silenciosamente outro endpoint ou credencial. Não inicie novas tentativas repetidamente enquanto a original estiver sem resolução.

Consulte [Perfis de exportação](/pt-br/docs/export-profiles/) para regras de recuperação, identidade e destino.

## O que o iOS garante ou não

O horário é um objetivo, não uma conclusão garantida. O iOS controla a execução em segundo plano, e o bloqueio pode impedir leituras do HealthKit. Solicitações e notificações silenciosas não contornam essa proteção.

Lembretes locais exigem permissão e não garantem entrega no horário escolhido. Se um chegar, desbloqueie o aparelho e abra-o para tentar recuperar. Se não chegar, abra Health.md e verifique pendências e histórico. Confira o resultado em vez de presumir sucesso por um alerta ou pelo tempo decorrido.

## Controle programático
<p>Você pode ativar ou desativar o agendamento nos Atalhos com o intent <em>Ativar ou desativar exportação agendada</em>. <a href="/pt-br/docs/shortcuts/">Veja exemplos em Atalhos</a>.</p>

## Agendamentos por perfil e cancelamento

- Cada perfil mantém seu próprio agendamento, inclusive uma cadência personalizada; trocar o perfil ativo não redireciona outro agendamento.
- Um aviso de colisão aparece quando perfis podem gravar os mesmos caminhos gerados no mesmo destino. Revise-o antes de ativar agendamentos concorrentes; o Health.md não altera nenhum perfil silenciosamente.
- Parar ou Cancelar encerra somente a tentativa atual. Datas concluídas permanecem assim, as pendentes podem ser repetidas e o agendamento continua ativo.
- Cada item do histórico permanece ligado ao perfil da execução e ao rótulo privado do destino realmente usado.

Gerencie configurações congeladas e destino em [Perfis de exportação](/pt-br/docs/export-profiles/).

## Relacionados
<div class="related"><a href="/pt-br/docs/export-profiles/"><span>Perfis</span>Gerencie agendamentos e destinos independentes.</a><a href="/pt-br/docs/export/"><span>Manual</span>Exportação — para intervalos avulsos.</a><a href="/pt-br/docs/shortcuts/"><span>Automatizar</span>Atalhos — alterne o agendamento com automações.</a><a href="/pt-br/docs/sync/"><span>Entre dispositivos</span>Sincronização com o Mac — agende também no Mac.</a></div>
