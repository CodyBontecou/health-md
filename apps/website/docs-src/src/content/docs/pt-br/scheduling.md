---
title: "Agende exportações Apple Health e solucione problemas de execuções perdidas"
description: "Verifique uma exportação agendada, entenda a retrospectiva dos dias concluídos e recupere datas pendentes. iPhone o tempo de fundo é o melhor esforço; histórico Tentar novamente usa as configurações atuais."
---

Esta página descreve o agendamento iPhone . O Android tem diferentes permissões de segundo plano e requisitos de compra; veja [Automação Android](/pt-br/docs/android/).

## Verifique a primeira exportação agendada

1. Ative o perfil pretendido. Verifique suas métricas, formatos, detalhes de dados, comportamento de gravação e destino. Execute um dia concluído manualmente e inspecione o arquivo salvo ou o resultado do endpoint antes de ativar a automação.
2. Abra Agenda e depois Configurar Agenda ou Gerenciar Agenda. Ative a programação, escolha Diário, Semanal ou Personalizado, defina o horário e comece com uma retrospectiva de um dia completo. Permita notificações se desejar lembretes de recuperação local.
3. Verifica se o agendamento está habilitado, a próxima ocorrência e o último resultado. Após uma tentativa, inspecione os detalhes do histórico e o destino real; um rótulo ou notificação de próxima execução não é prova de que os dados foram gravados.
4. Verifique as datas exportadas, unidades, cobertura e dados faltantes. Um arquivo salvo por si só não prova a captura completa da fonte.

Na versão do telefone com assinatura habilitada, as exportações programadas e manuais exigem uma avaliação ativa, assinatura, compra vitalícia ou acesso permanente preservado. Não há permissão de livre exportação local. O acesso expirado deve ser restaurado antes que o trabalho pendente possa ser retomado. Consulte [desbloqueio e acesso pago](/pt-br/docs/paywall/).

## Entenda a janela do dia concluído

As programações diárias, semanais e personalizadas podem ter uma retrospectiva. A cadência personalizada se repete a cada N dias, semanas ou meses a partir da data de início. Cada nova ocorrência reexporta toda a janela configurada de dias concluídos, incluindo as datas exportadas anteriormente. Uma retrospectiva de três dias cobre ontem e os dois dias anteriores; a execução atrasada mantém a janela ancorada no dia do incêndio programado.

A atualização de hoje é um trabalho separado do dia atual e não um substituto para a janela do dia concluído. Inspecione caminhos e comportamento de gravação antes de exportar sobreposições; não adicione instantâneos diários repetidos como novas medições.

## Escolha o caminho de recuperação correto

- **Recuperação agendada pendente:** desbloqueie iPhone , abra Health.md e inspecione a tentativa pendente. Ele mantém suas datas exatas não resolvidas, configurações salvas e destino. As datas concluídas permanecem concluídas; a recuperação não se expande para uma nova retrospectiva.
- **Repetir a partir do histórico:** isso inicia uma nova execução para esse intervalo usando as configurações e o destino atualmente configurados e registra uma nova linha do histórico. Verifique a configuração ativa antes de pressionar Repetir. Não é o mesmo que retomar uma tentativa pendente congelada.
- **Destino alterado ou indisponível:** restaure o acesso ou inspecione o perfil pendente antes de tentar novamente. Uma recuperação de API iPhone antiga não deve adotar silenciosamente um endpoint ou credencial alterado. Não inicie novas tentativas repetidamente enquanto a tentativa original não for resolvida.

Revise a recuperação pendente, a identidade do perfil e as regras de destino em [Exportar perfis](/pt-br/docs/export-profiles/).

## O que o iOS faz e não garante

O tempo selecionado é uma meta, não um tempo de conclusão garantido. O iOS controla o tempo de execução em segundo plano e a proteção de dispositivos bloqueados pode impedir leituras HealthKit . Solicitações em segundo plano e notificações de ativação silenciosa não ignoram essa proteção.

As notificações de recuperação local exigem permissão de notificação e não são uma garantia de entrega no horário previsto. Se você receber um, desbloqueie o dispositivo e abra-o para permitir que Health.md tente a recuperação. Se nenhuma notificação chegar, abra Health.md e verifique o trabalho pendente e o histórico. Verifique o resultado em vez de presumir que um alerta ou tempo decorrido significa sucesso.

## Controle programático
 <p> Você pode ativar/desativar a programação de Shortcuts usando a intenção <em> Ativar ou desativar exportação agendada </em> . <a href="/pt-br/docs/shortcuts/"> Veja Shortcuts </a> para exemplos. </p>

## Agendamentos e cancelamento de perfil

- Cada perfil pode manter sua própria programação, incluindo uma cadência personalizada. A troca do perfil ativo não redireciona a programação de outro perfil.
- Um aviso de colisão aparece quando os perfis podem gravar os mesmos caminhos renderizados no mesmo destino. Revise-o antes de ativar programações concorrentes. Health.md não altera silenciosamente nenhum dos perfis.
- Parar ou Cancelar encerra apenas a tentativa atual. As datas concluídas permanecem concluídas, as datas não resolvidas permanecem passíveis de nova tentativa e o agendamento permanece ativado.
- Cada linha do histórico permanece fixada no perfil de tempo de execução e no rótulo de destino seguro para privacidade realmente usado.

Gerencie as configurações congeladas e o destino por perfil em [Exportar perfis](/pt-br/docs/export-profiles/).

## Relacionado

<div class="related">
 <a href="/pt-br/docs/export-profiles/"> <span> Vários fluxos de trabalho </span> Exporte perfis, dê a cada configuração salva seu próprio destino e cadência. </a>
 <a href="/pt-br/docs/export/"> <span> Manual </span> Exportação, para intervalos de datas únicos. </a>
 <a href="/pt-br/docs/shortcuts/"> <span> Automatize </span> Shortcuts , alterne a programação das automações. </a>
 <a href="/pt-br/docs/sync/"> <span> Entre dispositivos </span> Mac Sync, agende também no Mac. </a>
 </div>
