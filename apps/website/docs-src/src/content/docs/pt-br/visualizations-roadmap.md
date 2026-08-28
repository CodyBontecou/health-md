---
title: Visualizações e roadmap
description: Cobertura atual das visualizações do Health.md no Obsidian e gráficos planejados, organizados por tipo de dado exportado.
---

O Health.md exporta um conjunto de dados local com esquema versionado para Markdown, Obsidian Bases, JSON e CSV. O roadmap de visualizações abaixo conecta essa superfície de dados ao plugin complementar de visualizações do Obsidian: o que já existe, o que os dados exportados podem viabilizar em seguida e quais categorias precisam de gráficos genéricos com reconhecimento de esquema.

<div class="callout">
<strong>Fonte dos dados.</strong>
<p style="margin-top:6px;">Esta página é organizada a partir do esquema de exportação e do dicionário de dados do Health.md: atividade, sono, coração, sinais vitais, corpo, nutrição, atenção plena, medicamentos, exercícios, saúde reprodutiva, sintomas, audição e métricas de estilo de vida/ambiente.</p>
</div>

## Substituições de unidades por visualização

Adicione `units` a um bloco `health-viz` individual quando um gráfico precisar usar um sistema de exibição diferente da preferência global do plugin:

```health-viz
type: workout-trends
metric: distance
units: imperial
```

Use `auto` para seguir o sistema de unidades declarado pela exportação, `metric` para exibir quilômetros, quilogramas, metros e Celsius, ou `imperial` para exibir milhas, libras, pés e Fahrenheit. A substituição se aplica somente a essa visualização e tem prioridade sobre a configuração global Units. Ela altera apenas os valores exibidos; os arquivos Health.md exportados permanecem inalterados. Métricas não conversíveis, como passos, BPM, porcentagens e calorias, não são alteradas.

## Cobertura atual de visualizações

<div class="reference-stats">
<div><strong>43</strong><span>renderizadores do plugin hoje</span></div>
<div><strong>18</strong><span>categorias de dados exportados</span></div>
<div><strong>220+</strong><span>chaves canônicas de exportação</span></div>
<div><strong>1</strong><span>camada genérica de métricas ainda necessária</span></div>
</div>

## Suporte de plataforma por exportador

O suporte a visualizações depende de os dados de origem existirem tanto no Apple HealthKit quanto no Android Health Connect, ou apenas no contrato de exportação do Apple HealthKit.

### iOS e Android

Estas visualizações são mapeadas para campos de exportação compartilhados do HealthKit / Health Connect:

| Categoria | Tipos de visualização |
| --- | --- |
| Visão geral | `intro-stats`, `summary-card`, `trend-tile` |
| Atividade | `activity-rings`, `vitals-rings`, `bar-chart`, `activity-heatmap`, `step-spiral`, `weekday-average` |
| Coração | `heart-terrain`, `heart-range`, `hrv-trend` |
| Respiratório e sinais vitais | `oxygen-river`, `oxygen-range`, `breathing-wave` |
| Sono | `sleep-schedule`, `sleep-quality-bars`, `sleep-architecture`, `sleep-polar` |
| Mobilidade | `walking-symmetry`* |
| Exercícios | `workout-log`, `workout-heart-rate`, `workout-zones`, `workout-trends`, `workout-intervals`, `workout-map` |

Observações:

- `walking-symmetry` é parcial no Android: o Android tem velocidade de caminhada, mas não os detalhes exclusivos da Apple de assimetria ou apoio duplo.
- `activity-rings` é parcial no Android para Stand: o plugin usa uma aproximação de Stand derivada de passos quando `standHours` está ausente.
- Gráficos de rotas e amostras de exercícios exigem dados granulares de exercícios, além de permissão e consentimento para as rotas.

### Somente iOS

Visualizações de State of Mind / humor do HealthKit:

- `mood-trend` / `state-of-mind`
- `mood-calendar-heatmap`
- `mood-sleep-scatter`
- `mood-day-timeline`
- `mood-association-breakdown`
- `mood-label-cloud`
- `mood-volatility`
- `mood-kind-split`
- `mood-circadian-clock`
- `mood-recovery-tile`
- `mood-association-matrix`

Visualizações de catálogo de medicamentos / eventos de dose:

- `medication-overview` / `medications` / `medication-adherence`
- `medication-inventory`
- `medication-adherence-summary`
- `medication-dose-status` / `per-medication-dose-status`
- `medication-adherence-trend` / `medication-daily-adherence-trend`
- `medication-recent-dose-events` / `medication-dose-events`

O Android Health Connect não expõe registros equivalentes de State of Mind do HealthKit nem registros de catálogo de medicamentos / eventos de dose no estilo HealthKit.

### Somente Android

Nenhuma no registro atual de visualizações do plugin do Obsidian. O Android exporta dados nativos do Android, como recursos PHR/FHIR, exercícios planejados e intensidade de atividade, mas nenhum tipo de visualização atual aborda esses campos ainda.

<span id="visualization-screenshot-gallery"></span>

## Catálogo de visualizações

Cada item leva à variação pública correspondente na [galeria de visualizações do Health.md](/visualizations/). Esses links usam a variação `theme-colors` para que a documentação permaneça rápida e estável em vez de incorporar todos os renderizadores nesta página.

### Resumo e visão geral

- [Estatísticas introdutórias](/visualizations/overview-trends/intro-stats/theme-colors/) — `intro-stats`
- [Cartão de resumo](/visualizations/overview-trends/summary-card/theme-colors/) — `summary-card`
- [Bloco de tendência](/visualizations/overview-trends/trend-tile/theme-colors/) — `trend-tile`

### Atividade

- [Anéis de atividade](/visualizations/activity-fitness/activity-rings/theme-colors/) — `activity-rings`
- [Gráfico de barras](/visualizations/activity-fitness/bar-chart/theme-colors/) — `bar-chart`
- [Mapa de calor de atividade](/visualizations/activity-fitness/activity-heatmap/theme-colors/) — `activity-heatmap`
- [Espiral de passos](/visualizations/activity-fitness/step-spiral/theme-colors/) — `step-spiral`
- [Média por dia da semana](/visualizations/activity-fitness/weekday-average/theme-colors/) — `weekday-average`

### Coração

- [Terreno cardíaco](/visualizations/heart-health/heart-terrain/theme-colors/) — `heart-terrain`
- [Faixa cardíaca](/visualizations/heart-health/heart-range/theme-colors/) — `heart-range`
- [Tendência de HRV](/visualizations/heart-health/hrv-trend/theme-colors/) — `hrv-trend`

### Respiratório, oxigênio e sinais vitais

- [Rio de oxigênio](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/) — `oxygen-river`
- [Faixa de oxigênio](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/) — `oxygen-range`
- [Onda respiratória](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/) — `breathing-wave`
- [Anéis de sinais vitais](/visualizations/activity-fitness/vitals-rings/theme-colors/) — `vitals-rings`

### Sono

- [Horário de sono](/visualizations/sleep-analysis/sleep-schedule/theme-colors/) — `sleep-schedule`
- [Barras de qualidade do sono](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/) — `sleep-quality-bars`
- [Arquitetura do sono](/visualizations/sleep-analysis/sleep-architecture/theme-colors/) — `sleep-architecture`
- [Polar do sono](/visualizations/sleep-analysis/sleep-polar/theme-colors/) — `sleep-polar`

### Atenção plena e humor

- [Tendência de humor](/visualizations/mindfulness-mood/mood-trend/theme-colors/) — `mood-trend`
- [Mapa de calor do calendário de humor](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/) — `mood-calendar-heatmap`
- [Dispersão de humor × sono](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/) — `mood-sleep-scatter`
- [Linha do tempo diária de humor](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/) — `mood-day-timeline`
- [Humor por associação](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/) — `mood-association-breakdown`
- [Nuvem de rótulos de humor](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/) — `mood-label-cloud`
- [Volatilidade do humor](/visualizations/mindfulness-mood/mood-volatility/theme-colors/) — `mood-volatility`
- [Humor diário vs momentâneo](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/) — `mood-kind-split`
- [Relógio circadiano do humor](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/) — `mood-circadian-clock`
- [Bloco de recuperação + estado mental](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/) — `mood-recovery-tile`
- [Matriz de associações de humor](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/) — `mood-association-matrix`

### Medicamentos

- [Visão geral de medicamentos](/visualizations/medication-adherence/medication-overview/theme-colors/) — `medication-overview`
- [Inventário de medicamentos](/visualizations/medication-adherence/medication-inventory/theme-colors/) — `medication-inventory`
- [Resumo de adesão a medicamentos](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/) — `medication-adherence-summary`
- [Status de doses de medicamentos](/visualizations/medication-adherence/medication-dose-status/theme-colors/) — `medication-dose-status`
- [Tendência de adesão a medicamentos](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/) — `medication-adherence-trend`
- [Eventos recentes de doses de medicamentos](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/) — `medication-recent-dose-events`

### Mobilidade, marcha e forma de corrida

- [Simetria da caminhada](/visualizations/mobility-gait/walking-symmetry/theme-colors/) — `walking-symmetry`

### Exercícios

- [Registro de exercícios](/visualizations/workout-analytics/workout-log/theme-colors/) — `workout-log`
- [Frequência cardíaca no exercício](/visualizations/workout-analytics/workout-heart-rate/theme-colors/) — `workout-heart-rate`
- [Zonas de exercício](/visualizations/workout-analytics/workout-zones/theme-colors/) — `workout-zones`
- [Tendências de exercícios](/visualizations/workout-analytics/workout-trends/theme-colors/) — `workout-trends`
- [Intervalos de exercícios](/visualizations/workout-analytics/workout-intervals/theme-colors/) — `workout-intervals`
- [Mapa de exercícios](/visualizations/workout-analytics/workout-map/theme-colors/) — `workout-map`

## Roadmap de base

A maior lacuna do produto não é um gráfico ausente. É uma camada genérica de métricas compatível com o esquema que permita representar qualquer campo exportado pelo Health.md sem escrever um parser e um renderizador personalizados para cada métrica.

### Implementado

- Detecção de compatibilidade com o esquema em exportações diárias, arquivos legados, consolidações e arquivos de dicionário de dados.
- Carregamento de JSON, CSV, Markdown e Obsidian Bases.
- Reconhecimento de consolidações para que resumos semanais/mensais/anuais não poluam gráficos diários.
- Navegação dos pontos do gráfico de volta ao arquivo Health.md de origem que contribuiu para eles.

### Planejado

- **Acesso genérico a métricas compatível com o esquema** — lê `_healthmd_data_dictionary.json` para rótulos, unidades, categorias, regras de agregação e aliases.
- **Tendência genérica de métricas** — gráfico de linha/área para qualquer chave numérica exportada.
- **Barras genéricas de métricas** — barras diárias/semanais/mensais generalizadas com linhas de meta e limiar.
- **Mapa de calor de calendário genérico** — qualquer métrica numérica diária como grade de calendário.
- **Relatório de cobertura de visualizações** — mostra os campos presentes em um cofre em comparação com os campos cobertos por renderizadores dedicados.

---

## Resumo e visão geral

### Implementado

- [`intro-stats`](/visualizations/overview-trends/intro-stats/theme-colors/) — resumo do conjunto de dados com totais, médias, sono e sinais vitais.
- [`summary-card`](/visualizations/overview-trends/summary-card/theme-colors/) — cartão de KPI ao estilo Apple com sparkline e comparação com período anterior.
- [`trend-tile`](/visualizations/overview-trends/trend-tile/theme-colors/) — comparação em cartão de tendências entre janelas atual e anterior.

### Planejado

- Painel gerado automaticamente com base nos campos presentes na pasta Health.md selecionada.
- Painel da cobertura do esquema por categoria de dados.
- Cartões de resumo de correlação, como sono vs humor, HRV vs exercícios, sintomas vs medicamentos ou álcool vs sono.

---

## Atividade

O Health.md exporta passos, energia ativa, energia basal, tempo de exercício, tempo em pé, lances de escada subidos, distância de caminhada/corrida, ciclismo, natação, atividade em cadeira de rodas, distância de neve em descida, tempo de movimento, esforço físico e VO₂ max.

### Implementado

- [`activity-rings`](/visualizations/activity-fitness/activity-rings/theme-colors/)
- [`vitals-rings`](/visualizations/activity-fitness/vitals-rings/theme-colors/)
- [`bar-chart`](/visualizations/activity-fitness/bar-chart/theme-colors/)
- [`activity-heatmap`](/visualizations/activity-fitness/activity-heatmap/theme-colors/)
- [`step-spiral`](/visualizations/activity-fitness/step-spiral/theme-colors/)
- [`weekday-average`](/visualizations/activity-fitness/weekday-average/theme-colors/)

### Planejado

- Painel de carga de atividade para passos, calorias, exercício, horas em pé e esforço físico.
- Tendência de VO₂ max.
- Gráfico de consistência de movimento / exercício / tempo em pé.
- Gráfico de composição de distância em caminhada/corrida, ciclismo, natação, cadeira de rodas e esportes na neve.
- Gráfico de distância de natação e braçadas.
- Gráfico de distância em cadeira de rodas e impulsos.

---

## Sono

O Health.md exporta sono total, hora de dormir, hora de acordar, durações de sono profundo/REM/core/acordado/na cama e intervalos granulares de estágios do sono.

### Implementado

- [`sleep-schedule`](/visualizations/sleep-analysis/sleep-schedule/theme-colors/)
- [`sleep-quality-bars`](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/)
- [`sleep-architecture`](/visualizations/sleep-analysis/sleep-architecture/theme-colors/)
- [`sleep-polar`](/visualizations/sleep-analysis/sleep-polar/theme-colors/)

### Planejado

- Dívida de sono e pontuação de consistência.
- Tendência de proporção dos estágios do sono.
- Mapa de calor de regularidade de hora de dormir/acordar.
- Painel de recuperação com sono, HRV e frequência cardíaca em repouso.

---

## Coração

O Health.md exporta frequência cardíaca em repouso, frequência cardíaca caminhando, frequência cardíaca média/mínima/máxima, HRV, amostras de frequência cardíaca, amostras de HRV, recuperação de frequência cardíaca e carga de AFib.

### Implementado

- [`heart-terrain`](/visualizations/heart-health/heart-terrain/theme-colors/)
- [`heart-range`](/visualizations/heart-health/heart-range/theme-colors/)
- [`hrv-trend`](/visualizations/heart-health/hrv-trend/theme-colors/)

### Planejado

- Tendência de frequência cardíaca em repouso.
- Tendência de frequência cardíaca caminhando.
- Tendência de recuperação de frequência cardíaca.
- Gráfico de carga de AFib.
- Bloco de recuperação com HRV e frequência cardíaca em repouso.
- Perfil circadiano de frequência cardíaca por horário do dia.

---

## Respiratório e oxigênio

O Health.md exporta média/mínima/máxima de oxigênio no sangue, amostras de oxigênio no sangue, média/mínima/máxima de frequência respiratória e amostras de frequência respiratória.

### Implementado

- [`oxygen-river`](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/)
- [`oxygen-range`](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/)
- [`breathing-wave`](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/)

### Planejado

- Gráfico dedicado de faixa respiratória.
- Gráfico de eventos de dessaturação de oxigênio.
- Painel respiratório noturno que combina estágios do sono, oxigênio e frequência respiratória.

---

## Sinais vitais

O Health.md exporta temperatura corporal, pressão arterial, glicemia, temperatura corporal basal, temperatura do pulso, atividade eletrodérmica, capacidade vital forçada, FEV1, pico de fluxo expiratório e uso de inalador.

### Implementado

- Cobertura parcial por cartões de resumo e gráficos diários genéricos.

### Planejado

- Gráfico de faixa sistólica/diastólica de pressão arterial com faixas de limiar.
- Gráfico de faixa de glicemia.
- Tendência de temperatura corporal, basal e do pulso.
- Bloco de recuperação / doença com temperatura do pulso.
- Painel de função respiratória para FVC, FEV1, pico de fluxo e uso de inalador.
- Tendência de atividade eletrodérmica / estresse.

---

## Medidas corporais

O Health.md exporta peso, altura, BMI, percentual de gordura corporal, massa magra e circunferência da cintura.

### Implementado

- Ainda não há renderizador dedicado de composição corporal.

### Planejado

- Painel de composição corporal.
- Tendência de peso com média móvel e linha de meta.
- Tendência de BMI com faixas de categoria.
- Gráfico de gordura corporal vs massa magra.
- Tendência de circunferência da cintura.

---

## Mobilidade, marcha e forma de corrida

O Health.md exporta velocidade de caminhada, comprimento do passo, apoio duplo, assimetria da caminhada, velocidade de subida/descida de escadas, caminhada de seis minutos, estabilidade da caminhada, velocidade de corrida, comprimento da passada de corrida, tempo de contato com o solo, oscilação vertical e potência de corrida.

### Implementado

- [`walking-symmetry`](/visualizations/mobility-gait/walking-symmetry/theme-colors/)

### Planejado

- Painel de marcha.
- Medidor de estabilidade da caminhada.
- Tendência de caminhada de seis minutos.
- Gráfico de velocidade de subida/descida de escadas.
- Painel de forma de corrida para velocidade, passada, contato com o solo, oscilação vertical e potência.

---

## Exercícios

O Health.md exporta contagens de exercícios, minutos, calorias, distância, tipos de exercício, estatísticas de frequência cardíaca, métricas de forma de corrida/ciclismo, potência, elevação, voltas, parciais, pontos de rota, zonas de frequência cardíaca e amostras de séries temporais de exercícios.

### Implementado

- [`workout-log`](/visualizations/workout-analytics/workout-log/theme-colors/)
- [`workout-heart-rate`](/visualizations/workout-analytics/workout-heart-rate/theme-colors/)
- [`workout-zones`](/visualizations/workout-analytics/workout-zones/theme-colors/)
- [`workout-trends`](/visualizations/workout-analytics/workout-trends/theme-colors/)
- [`workout-intervals`](/visualizations/workout-analytics/workout-intervals/theme-colors/)
- [`workout-map`](/visualizations/workout-analytics/workout-map/theme-colors/)

### Planejado

- Mapa de calor de calendário de exercícios.
- Gráfico de carga de treino a partir de duração e intensidade.
- Distribuição semanal de exercícios por tipo.
- Tendência de ritmo e velocidade por tipo de exercício.
- Tendência de ganho/perda de elevação.
- Pequenos múltiplos de comparação de rotas.
- Curva de potência / melhores esforços.
- Painéis de forma de corrida e desempenho no ciclismo.

---

## Atenção plena e humor

O Health.md exporta minutos de atenção plena, sessões de atenção plena, entradas de State of Mind, valência média, humor diário, emoções momentâneas, rótulos e associações.

### Implementado

- [`mood-trend`](/visualizations/mindfulness-mood/mood-trend/theme-colors/)
- [`mood-calendar-heatmap`](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/)
- [`mood-sleep-scatter`](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/)
- [`mood-day-timeline`](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/)
- [`mood-association-breakdown`](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/)
- [`mood-label-cloud`](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/)
- [`mood-volatility`](/visualizations/mindfulness-mood/mood-volatility/theme-colors/)
- [`mood-kind-split`](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/)
- [`mood-circadian-clock`](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/)
- [`mood-recovery-tile`](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/)
- [`mood-association-matrix`](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/)

### Planejado

- Tendência de minutos de atenção plena.
- Sequência/calendário de sessões de atenção plena.
- Humor vs adesão a medicamentos.
- Humor vs nutrição, álcool e cafeína.
- Linha do tempo de rótulos de humor.

---

## Medicamentos

O Health.md exporta inventário de medicamentos, contagens de ativos/arquivados, contagens de eventos de dose, contagens de doses tomadas/puladas, detalhes de medicamentos, metadados de RxNorm/codificação, quantidades de dose, tipo de cronograma, datas programadas/de início/de término, status e metadados.

### Implementado

- [`medication-overview`](/visualizations/medication-adherence/medication-overview/theme-colors/)
- [`medication-inventory`](/visualizations/medication-adherence/medication-inventory/theme-colors/)
- [`medication-adherence-summary`](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/)
- [`medication-dose-status`](/visualizations/medication-adherence/medication-dose-status/theme-colors/)
- [`medication-adherence-trend`](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/)
- [`medication-recent-dose-events`](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/)

### Planejado

- Linha do tempo da agenda de medicamentos.
- Mapa de calor de calendário de adesão a medicamentos.
- Gráfico de atraso de medicamentos comparando o horário programado ao horário de tomada.
- Tendência de quantidade de dose.
- Visualizações de correlação de medicamento vs sintoma/humor.
- Painel de detalhes de RxNorm / codificação.

---

## Nutrição

O Health.md exporta calorias alimentares, proteína, carboidratos, gordura, gordura saturada, gordura monoinsaturada, gordura poli-insaturada, fibra, açúcar, sódio, colesterol, água e cafeína.

### Implementado

- Ainda não há renderizador dedicado de nutrição.

### Planejado

- Painel de nutrição.
- Gráfico de divisão de macros.
- Gráfico de calorias ingeridas vs calorias ativas.
- Tendência de hidratação.
- Gráfico de quantidade diária / horário de cafeína.
- Gráficos de limiar de açúcar e sódio.
- Progresso de metas de fibra e proteína.

---

## Vitaminas e minerais

O Health.md exporta vitaminas A, B6, B12, C, D, E, K, tiamina, riboflavina, niacina, folato, biotina, ácido pantotênico, cálcio, ferro, potássio, magnésio, fósforo, zinco, selênio, cobre, manganês, cromo, molibdênio, cloreto e iodo.

### Implementado

- Ainda não há renderizador dedicado de micronutrientes.

### Planejado

- Mapa de calor de micronutrientes.
- Grade de progresso de valores diários recomendados.
- Painel de tendência de vitaminas.
- Painel de tendência de minerais.
- Painel de sinalizações de deficiência/excesso.
- Pontuação de completude nutricional.

---

## Audição

O Health.md exporta nível de áudio dos fones de ouvido e nível de som ambiental.

### Implementado

- Apenas cobertura parcial em nível de resumo.

### Planejado

- Tendência de exposição auditiva.
- Calendário de dias ruidosos.
- Faixas de limiar de exposição segura.
- Resumo semanal de exposição.

---

## Saúde reprodutiva e monitoramento do ciclo

O Health.md exporta fluxo menstrual, atividade sexual, resultado de teste de ovulação, qualidade do muco cervical e sangramento intermenstrual.

### Implementado

- Ainda não há renderizador dedicado de saúde reprodutiva.

### Planejado

- Calendário do ciclo.
- Mapa de calor de fluxo menstrual.
- Linha do tempo de sinais de fertilidade.
- Sobreposição de sintomas do ciclo combinando saúde reprodutiva, sintomas, humor e sono.
- Linha do tempo de sangramento de escape e sangramento intermenstrual.

---

## Sintomas

O Health.md exporta contagens diárias de sintomas de dor de cabeça, fadiga, náusea, tontura, alterações de humor, alterações do sono, alterações de apetite, ondas de calor, calafrios, febre, dor lombar, inchaço abdominal, constipação, diarreia, azia, tosse, dor de garganta, coriza, falta de ar, dor no peito, batimento cardíaco pulado, batimento cardíaco acelerado, acne, pele seca, queda de cabelo, lapsos de memória, suores noturnos, vômito, cólicas abdominais, dor nas mamas, dor pélvica, dor no corpo, desmaio, perda de olfato, perda de paladar, chiado no peito, congestão sinusal, incontinência urinária e secura vaginal.

### Implementado

- Ainda não há renderizador dedicado de sintomas.

### Planejado

- Mapa de calor de calendário de sintomas.
- Ranking de frequência de sintomas.
- Matriz de coocorrência de sintomas.
- Linha do tempo de crises.
- Explorador de correlação de sintomas.
- Painel de sintomas agrupados por sistema corporal.

---

## Outros dados de saúde, estilo de vida e ambiente

O Health.md exporta exposição UV, tempo à luz do dia, quedas, álcool no sangue, bebidas alcoólicas, administração de insulina, escovação dos dentes, lavagem das mãos, temperatura da água e profundidade subaquática.

### Implementado

- Ainda não há renderizador dedicado de estilo de vida/ambiente.

### Planejado

- Calendário de luz do dia / UV.
- Linha do tempo de quedas.
- Gráfico de álcool vs sono / HRV.
- Tendência de administração de insulina.
- Sequências de escovação dos dentes e lavagem das mãos.
- Gráfico de temperatura da água / profundidade subaquática.

---

## Ordem de prioridade

1. Infraestrutura genérica de métricas compatível com o esquema.
2. Renderizadores genéricos de tendência, barras e mapa de calor de calendário.
3. Conjunto de sinais vitais: pressão arterial, glicose, temperatura, função respiratória.
4. Painel de composição corporal.
5. Painel de nutrição.
6. Visualizações de mapa de calor, ranking e correlação de sintomas.
7. Calendário de ciclo / saúde reprodutiva.
8. Mapa de calor de micronutrientes e grade de valores diários recomendados.
9. Painel expandido de mobilidade e forma de corrida.
10. Gráficos de audição e estilo de vida/ambiente.

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Atualizado em 2026-06-25</p>
