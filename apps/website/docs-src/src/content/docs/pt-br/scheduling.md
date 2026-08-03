---
title: "Agendamento"
description: "Execute exportações automaticamente — todos os dias ou toda semana, no horário que escolher. Usa tarefas em segundo plano do iOS e uma notificação local agendada como alternativa quando o dispositivo está bloqueado."
---

## A aba Agendar
<p>É uma tela de status, não um painel de ajustes. Ela informa rapidamente:</p>
<ul><li>Se o agendamento está ativado ou desativado</li><li>A próxima execução agendada, se houver</li><li>O resultado da última execução</li></ul>
<p>Um botão — <em>Configurar agendamento</em> ou <em>Gerenciar agendamento</em> — abre a tela de detalhes.</p>

## Configurações do agendamento
<div class="options">
<div class="option"><strong>Ativar exportações agendadas</strong><p>Controle mestre no topo. Quando desativado, não há execuções em segundo plano nem notificações.</p></div>
<div class="option"><strong>Frequência</strong><p>Diária, semanal ou mensal. A exportação diária cobre ontem; a semanal, os 7 dias anteriores; a mensal, os 30 anteriores.</p></div>
<div class="option"><strong>Horário</strong><p>Hora e minuto. O iOS trata isso como uma indicação, não como garantia — veja as limitações abaixo.</p></div>
</div>

## Histórico de exportações
<p>A lista no fim da tela Agendar registra cada execução agendada e seu resultado. Toque em uma linha para ver detalhes. Execuções com falha incluem um botão <em>Tentar novamente</em>, que repete o intervalo específico.</p>

## Como o agendamento do iOS realmente funciona
<div class="doc-diagram"><div class="flow-steps" aria-label="Fluxo alternativo da exportação agendada">
<span><strong>1. Horário previsto</strong>O Health.md pede ao iOS que desperte o app perto do horário escolhido.</span>
<span><strong>2. Tentativa em segundo plano</strong>Se o dispositivo estiver disponível, o iOS executa uma tarefa de atualização.</span>
<span><strong>3. Alternativa com bloqueio</strong>Se o HealthKit estiver indisponível, o Health.md envia uma notificação.</span>
<span><strong>4. Toque para concluir</strong>Ao abrir a notificação, o app pode ler o HealthKit e exportar.</span>
</div></div>

<div class="callout"><strong>Limitações do iOS que você deve conhecer.</strong><p style="margin-top:6px;">Os dados do HealthKit não podem ser lidos enquanto o dispositivo está bloqueado. As exportações agendadas usam <code>BGAppRefreshTask</code>, que o iOS agenda de forma oportunista conforme os padrões de uso — o horário definido é uma meta, não um contrato. Como alternativa, o app envia uma notificação local no horário agendado se o dispositivo estiver bloqueado; toque nela para executar a exportação.</p></div>
<ul><li>O horário é aproximado. O iOS pode executar antes ou depois, ou ignorar a tarefa se o aparelho estiver desligado ou desconectado.</li><li>As exportações funcionam melhor quando o telefone costuma estar conectado à energia e desbloqueado aproximadamente no mesmo horário.</li><li>Se a exportação falhar porque o dispositivo estava bloqueado, toque na notificação para executá-la com acesso ao HealthKit.</li></ul>

## Controle programático
<p>Você pode ativar ou desativar o agendamento nos Atalhos com o intent <em>Ativar ou desativar exportação agendada</em>. <a href="/pt-br/docs/shortcuts/">Veja exemplos em Atalhos</a>.</p>

## Relacionados
<div class="related"><a href="/pt-br/docs/export/"><span>Manual</span>Exportação — para intervalos avulsos.</a><a href="/pt-br/docs/shortcuts/"><span>Automatizar</span>Atalhos — alterne o agendamento com automações.</a><a href="/pt-br/docs/sync/"><span>Entre dispositivos</span>Sincronização com o Mac — agende também no Mac.</a></div>
