---
title: "Atalhos e App Intents"
description: "Oito App Intents permitem acionar exportações, obter resumos e alternar o agendamento pela Siri, pelo app Atalhos, por filtros de Foco, automações e qualquer host compatível com AppIntent."
---

## Intents disponíveis
<div class="options">
<div class="option"><strong>Exportar dados de saúde de ontem</strong><p>Atalho sem parâmetros. O caminho rápido para exportar os dados de ontem. Usa o mesmo mecanismo da exportação manual.</p></div>
<div class="option"><strong>Exportar dados de saúde de uma data</strong><p>Um parâmetro <em>Data</em>. A hora é ignorada. Útil em automações baseadas no calendário.</p></div>
<div class="option"><strong>Exportar dados de saúde de um intervalo</strong><p>Parâmetros <em>Data inicial</em> e <em>Data final</em>, ambas inclusivas. Use para preenchimentos retroativos.</p></div>
<div class="option"><strong>Exportar os últimos N dias de dados de saúde</strong><p>Parâmetro <em>Número de dias</em> (1–366). Termina ontem. Padrão: 7. Bom para automações semanais.</p></div>
<div class="option"><strong>Obter resumo de saúde de uma data</strong><p>Retorna uma captura estruturada — passos, calorias ativas, sono e frequência cardíaca — sem gravar no cofre.</p></div>
<div class="option"><strong>Obter status da última exportação</strong><p>Retorna data e hora, sucesso, número de dias e motivo de falha da exportação registrada mais recente. Uma solicitação com o dispositivo bloqueado permanece pendente até ser repetida e não aparece como status atual.</p></div>
<div class="option"><strong>Ativar ou desativar exportação agendada</strong><p>Parâmetro booleano. Suspenda o agendamento, por exemplo durante o Foco Férias, e retome depois.</p></div>
<div class="option"><strong>Exportar dados de saúde</strong><p>Exportação genérica que usa o último intervalo do modal Exportar no app. As variantes com intervalo costumam ser mais claras.</p></div>
</div>

## Onde encontrá-los
<p>Abra o app Atalhos no iOS ou macOS. Toque em <em>+</em>, crie um atalho e busque "Health.md" ou um dos títulos acima. Eles ficam na categoria <em>Saúde</em>.</p>
<p>A maioria usa <code>openAppWhenRun = false</code> e é executada sem interface. Funciona em automações, filtros de Foco, transferência do Hey Siri e Botão de Ação.</p>

<div class="callout"><strong>Executar com o aparelho bloqueado não desbloqueia o HealthKit.</strong><p style="margin-top:6px;">A Apple protege os dados enquanto o iPhone está bloqueado e <a href="https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web">remove o acesso dos apps cerca de dez minutos após o bloqueio</a>. <em>Permitir execução quando bloqueado</em> permite iniciar a ação, mas não substitui a proteção do HealthKit. A permissão de conteúdo do Health.md nos Atalhos também não.</p><p>Se o HealthKit estiver indisponível, o Health.md preserva as datas como pendentes e envia uma notificação <em>A exportação de saúde precisa de atenção</em>. Desbloqueie o iPhone e toque nela ou abra o Health.md. Não é possível garantir uma exportação totalmente autônoma enquanto o telefone permanecer bloqueado.</p></div>

<a id="recipe-nightly-export-with-confirmation"></a>
## Receita: exportação diária com confirmação
<ol><li><strong>Automação pessoal</strong> → <em>Hora do dia</em> → escolha um horário em que o iPhone costuma estar desbloqueado, como 8:00 AM.</li><li>Intent <em>Exportar dados de saúde de ontem</em>.</li><li>Intent <em>Obter status da última exportação</em>.</li><li><em>Mostrar notificação</em> com o resultado.</li></ol>
<p><strong>Observação sobre status pendente:</strong> o status lê a entrada mais recente do histórico. Se o HealthKit estava bloqueado, pode mostrar a exportação anterior até a nova tentativa. A notificação de recuperação do Health.md é o sinal oficial.</p>

## Receita: preenchimento retroativo avulso
<ol><li>Crie um atalho.</li><li><em>Exportar dados de saúde de um intervalo</em> com início = 2024-01-01 e fim = 2024-12-31.</li><li>Execute nos Atalhos. O app percorre o ano e grava um arquivo por dia. Anos completos podem levar alguns minutos.</li></ol>

## Receita: pausar durante as férias
<ol><li><strong>Filtro de Foco</strong>: quando o Foco <em>Férias</em> ativar, execute <em>Ativar ou desativar exportação agendada</em> com Enabled = false.</li><li>Quando o Foco desativar, execute novamente com Enabled = true.</li></ol>

<div class="callout"><strong>Autorização obrigatória.</strong><p style="margin-top:6px;">Os intents herdam a permissão do HealthKit e a seleção do cofre no app. Eles falham com um erro claro se o app não tiver sido aberto e configurado pelo menos uma vez no dispositivo.</p></div>

## Relacionados
<div class="related"><a href="/pt-br/docs/scheduling/"><span>Origem</span>Agendamento — equivalente no app ao intent de alternância.</a><a href="/pt-br/docs/export/"><span>Origem</span>Exportação — equivalente no app aos intents de intervalo.</a></div>
