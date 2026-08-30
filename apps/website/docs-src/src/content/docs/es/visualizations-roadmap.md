---
title: Visualizaciones y hoja de ruta
description: Cobertura actual de visualizaciones de Health.md para Obsidian y gráficos planificados, organizados por tipo de dato exportado.
---

Health.md exporta un conjunto de datos local con un esquema versionado para Markdown, Obsidian Bases, JSON y CSV. La hoja de ruta de visualizaciones de abajo conecta esa superficie de datos con el plugin complementario de visualizaciones para Obsidian: qué existe ya, qué pueden soportar después los datos exportados y qué categorías necesitan gráficos genéricos compatibles con el esquema.

<div class="callout">
<strong>Fuente de datos.</strong>
<p style="margin-top:6px;">Esta página está organizada a partir del esquema de exportación y el diccionario de datos de Health.md: actividad, sueño, corazón, signos vitales, cuerpo, nutrición, mindfulness, medicamentos, entrenamientos, salud reproductiva, síntomas, audición y métricas de estilo de vida y entorno.</p>
</div>

## Anulaciones de unidades por visualización

Añade `units` dentro de un bloque `health-viz` individual cuando un gráfico deba usar un sistema de visualización distinto de la preferencia global del plugin:

```health-viz
type: workout-trends
metric: distance
units: imperial
```

Usa `auto` para seguir el sistema de unidades declarado por la exportación, `metric` para mostrar kilómetros, kilogramos, metros y Celsius, o `imperial` para mostrar millas, libras, pies y Fahrenheit. La anulación solo se aplica a esa visualización y tiene prioridad sobre el ajuste global Units. Solo cambia los valores mostrados; los archivos Health.md exportados no se modifican. Las métricas no convertibles, como pasos, BPM, porcentajes y calorías, no cambian.

## Cobertura actual de visualizaciones

<div class="reference-stats">
<div><strong>43</strong><span>renderizadores actuales del plugin</span></div>
<div><strong>18</strong><span>categorías de datos de exportación</span></div>
<div><strong>220+</strong><span>claves canónicas de exportación</span></div>
<div><strong>1</strong><span>capa genérica de métricas aún necesaria</span></div>
</div>

## Compatibilidad de plataforma por exportador

La compatibilidad de visualizaciones depende de si los datos de origen existen tanto en Apple HealthKit como en Android Health Connect, o únicamente en el contrato de exportación de Apple HealthKit.

### iOS y Android

Estas visualizaciones se asignan a campos de exportación compartidos de HealthKit / Health Connect:

| Categoría | Tipos de visualización |
| --- | --- |
| Resumen | `intro-stats`, `summary-card`, `trend-tile` |
| Actividad | `activity-rings`, `vitals-rings`, `bar-chart`, `activity-heatmap`, `step-spiral`, `weekday-average` |
| Corazón | `heart-terrain`, `heart-range`, `hrv-trend` |
| Respiratorio y signos vitales | `oxygen-river`, `oxygen-range`, `breathing-wave` |
| Sueño | `sleep-schedule`, `sleep-quality-bars`, `sleep-architecture`, `sleep-polar` |
| Movilidad | `walking-symmetry`* |
| Entrenamientos | `workout-log`, `workout-heart-rate`, `workout-zones`, `workout-trends`, `workout-intervals`, `workout-map` |

Notas:

- `walking-symmetry` es parcial en Android: Android incluye la velocidad al caminar, pero no asimetría exclusiva de Apple ni detalles de doble apoyo.
- `activity-rings` es parcial en Android para Stand: el plugin recurre a un valor aproximado de Stand derivado de los pasos cuando falta `standHours`.
- Los gráficos de rutas y muestras de entrenamientos requieren datos granulares de entrenamiento y permiso o consentimiento de ruta.

### Solo iOS

Visualizaciones de State of Mind / ánimo de HealthKit:

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

Visualizaciones de catálogo de medicamentos / eventos de dosis:

- `medication-overview` / `medications` / `medication-adherence`
- `medication-inventory`
- `medication-adherence-summary`
- `medication-dose-status` / `per-medication-dose-status`
- `medication-adherence-trend` / `medication-daily-adherence-trend`
- `medication-recent-dose-events` / `medication-dose-events`

Android Health Connect no expone registros equivalentes a State of Mind de HealthKit ni registros de catálogo de medicamentos / eventos de dosis al estilo HealthKit.

### Solo Android

Ninguno en el registro actual de visualizaciones del plugin para Obsidian. Android sí exporta datos nativos de Android, como recursos PHR/FHIR, entrenamientos planificados e intensidad de actividad, pero ningún tipo de visualización actual apunta todavía a esos campos.

<span id="visualization-screenshot-gallery"></span>

## Catálogo de visualizaciones

Cada elemento enlaza a su variación pública correspondiente en la [galería de visualizaciones de Health.md](/visualizations/). Estos enlaces usan la variación `theme-colors` para que la documentación permanezca rápida y estable en lugar de incrustar cada renderizador en esta página.

### Resumen y vista general

- [Estadísticas de introducción](/visualizations/overview-trends/intro-stats/theme-colors/) — `intro-stats`
- [Tarjeta de resumen](/visualizations/overview-trends/summary-card/theme-colors/) — `summary-card`
- [Bloque de tendencia](/visualizations/overview-trends/trend-tile/theme-colors/) — `trend-tile`

### Actividad

- [Anillos de actividad](/visualizations/activity-fitness/activity-rings/theme-colors/) — `activity-rings`
- [Gráfico de barras](/visualizations/activity-fitness/bar-chart/theme-colors/) — `bar-chart`
- [Mapa de calor de actividad](/visualizations/activity-fitness/activity-heatmap/theme-colors/) — `activity-heatmap`
- [Espiral de pasos](/visualizations/activity-fitness/step-spiral/theme-colors/) — `step-spiral`
- [Promedio por día de la semana](/visualizations/activity-fitness/weekday-average/theme-colors/) — `weekday-average`

### Corazón

- [Terreno cardíaco](/visualizations/heart-health/heart-terrain/theme-colors/) — `heart-terrain`
- [Rango cardíaco](/visualizations/heart-health/heart-range/theme-colors/) — `heart-range`
- [Tendencia de HRV](/visualizations/heart-health/hrv-trend/theme-colors/) — `hrv-trend`

### Respiratorio, oxígeno y signos vitales

- [Río de oxígeno](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/) — `oxygen-river`
- [Rango de oxígeno](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/) — `oxygen-range`
- [Onda respiratoria](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/) — `breathing-wave`
- [Anillos de signos vitales](/visualizations/activity-fitness/vitals-rings/theme-colors/) — `vitals-rings`

### Sueño

- [Horario de sueño](/visualizations/sleep-analysis/sleep-schedule/theme-colors/) — `sleep-schedule`
- [Barras de calidad del sueño](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/) — `sleep-quality-bars`
- [Arquitectura del sueño](/visualizations/sleep-analysis/sleep-architecture/theme-colors/) — `sleep-architecture`
- [Polar del sueño](/visualizations/sleep-analysis/sleep-polar/theme-colors/) — `sleep-polar`

### Mindfulness y ánimo

- [Tendencia de ánimo](/visualizations/mindfulness-mood/mood-trend/theme-colors/) — `mood-trend`
- [Mapa de calor de ánimo en calendario](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/) — `mood-calendar-heatmap`
- [Dispersión ánimo × sueño](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/) — `mood-sleep-scatter`
- [Línea de tiempo diaria de ánimo](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/) — `mood-day-timeline`
- [Ánimo por asociación](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/) — `mood-association-breakdown`
- [Nube de etiquetas de ánimo](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/) — `mood-label-cloud`
- [Volatilidad del ánimo](/visualizations/mindfulness-mood/mood-volatility/theme-colors/) — `mood-volatility`
- [Ánimo diario frente a momentáneo](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/) — `mood-kind-split`
- [Reloj circadiano del ánimo](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/) — `mood-circadian-clock`
- [Bloque de recuperación y mentalidad](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/) — `mood-recovery-tile`
- [Matriz de asociaciones de ánimo](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/) — `mood-association-matrix`

### Medicamentos

- [Resumen de medicamentos](/visualizations/medication-adherence/medication-overview/theme-colors/) — `medication-overview`
- [Inventario de medicamentos](/visualizations/medication-adherence/medication-inventory/theme-colors/) — `medication-inventory`
- [Resumen de adherencia a medicamentos](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/) — `medication-adherence-summary`
- [Estado de dosis de medicamentos](/visualizations/medication-adherence/medication-dose-status/theme-colors/) — `medication-dose-status`
- [Tendencia de adherencia a medicamentos](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/) — `medication-adherence-trend`
- [Eventos recientes de dosis de medicamentos](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/) — `medication-recent-dose-events`

### Movilidad, marcha y técnica de carrera

- [Simetría al caminar](/visualizations/mobility-gait/walking-symmetry/theme-colors/) — `walking-symmetry`

### Entrenamientos

- [Registro de entrenamientos](/visualizations/workout-analytics/workout-log/theme-colors/) — `workout-log`
- [Frecuencia cardíaca de entrenamiento](/visualizations/workout-analytics/workout-heart-rate/theme-colors/) — `workout-heart-rate`
- [Zonas de entrenamiento](/visualizations/workout-analytics/workout-zones/theme-colors/) — `workout-zones`
- [Tendencias de entrenamiento](/visualizations/workout-analytics/workout-trends/theme-colors/) — `workout-trends`
- [Intervalos de entrenamiento](/visualizations/workout-analytics/workout-intervals/theme-colors/) — `workout-intervals`
- [Mapa de entrenamiento](/visualizations/workout-analytics/workout-map/theme-colors/) — `workout-map`

## Hoja de ruta de la infraestructura básica

La brecha más grande del producto no es un gráfico faltante. Es una capa genérica de métricas compatible con el esquema que permita graficar cualquier campo exportado por Health.md sin escribir un analizador y renderizador personalizado para cada métrica.

### Construido

- Detección de compatibilidad de esquema para exportaciones diarias, archivos heredados, acumulados y archivos de diccionario de datos.
- Carga de JSON, CSV, Markdown y Obsidian Bases.
- Reconocimiento de datos acumulados para que los resúmenes semanales, mensuales y anuales no contaminen los gráficos diarios.
- Navegación desde puntos del gráfico hasta el archivo de Health.md que contribuye.

### Planificado

- **Acceso genérico a métricas compatible con el esquema**: leer `_healthmd_data_dictionary.json` para etiquetas, unidades, categorías, reglas de agregación y alias.
- **Tendencia genérica de métrica**: gráfico de línea/área para cualquier clave numérica exportada.
- **Barras genéricas de métrica**: barras generalizadas diarias, semanales o mensuales con líneas de objetivo y umbral.
- **Mapa de calor genérico de calendario**: cualquier métrica numérica diaria como cuadrícula de calendario.
- **Informe de cobertura de visualizaciones**: mostrar campos presentes en una bóveda frente a campos cubiertos por renderizadores dedicados.

---

## Resumen y vista general

### Construido

- [`intro-stats`](/visualizations/overview-trends/intro-stats/theme-colors/) — resumen del conjunto de datos con totales, promedios, sueño y signos vitales.
- [`summary-card`](/visualizations/overview-trends/summary-card/theme-colors/) — tarjeta KPI estilo Apple con minigráfico y comparación con el período anterior.
- [`trend-tile`](/visualizations/overview-trends/trend-tile/theme-colors/) — comparación en tarjeta de tendencias entre ventanas actual y anterior.

### Planificado

- Panel generado automáticamente según los campos presentes en la carpeta Health.md seleccionada.
- Panel de cobertura de esquema por categoría de datos.
- Tarjetas de resumen de correlación, como sueño frente a ánimo, HRV frente a entrenamientos, síntomas frente a medicamentos o alcohol frente a sueño.

---

## Actividad

Health.md exporta pasos, energía activa, energía basal, tiempo de ejercicio, tiempo de pie, pisos subidos, distancia caminando/corriendo, ciclismo, natación, actividad en silla de ruedas, distancia de esquí alpino, tiempo de movimiento, esfuerzo físico y VO₂ máx.

### Construido

- [`activity-rings`](/visualizations/activity-fitness/activity-rings/theme-colors/)
- [`vitals-rings`](/visualizations/activity-fitness/vitals-rings/theme-colors/)
- [`bar-chart`](/visualizations/activity-fitness/bar-chart/theme-colors/)
- [`activity-heatmap`](/visualizations/activity-fitness/activity-heatmap/theme-colors/)
- [`step-spiral`](/visualizations/activity-fitness/step-spiral/theme-colors/)
- [`weekday-average`](/visualizations/activity-fitness/weekday-average/theme-colors/)

### Planificado

- Panel de carga de actividad para pasos, calorías, ejercicio, horas de pie y esfuerzo físico.
- Tendencia de VO₂ máx.
- Gráfico de constancia de movimiento, ejercicio y horas de pie.
- Gráfico de mezcla de distancias entre caminar/correr, ciclismo, natación, silla de ruedas y deportes de nieve.
- Gráfico de distancia de natación + brazadas.
- Gráfico de distancia en silla de ruedas + impulsos.

---

## Sueño

Health.md exporta sueño total, hora de acostarse, hora de despertar, duraciones de sueño profundo/REM/core/despierto/en cama e intervalos granulares de fases de sueño.

### Construido

- [`sleep-schedule`](/visualizations/sleep-analysis/sleep-schedule/theme-colors/)
- [`sleep-quality-bars`](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/)
- [`sleep-architecture`](/visualizations/sleep-analysis/sleep-architecture/theme-colors/)
- [`sleep-polar`](/visualizations/sleep-analysis/sleep-polar/theme-colors/)

### Planificado

- Deuda de sueño y puntuación de constancia.
- Tendencia de proporción de fases de sueño.
- Mapa de calor de regularidad de hora de acostarse/despertar.
- Panel de recuperación con sueño + HRV + frecuencia cardíaca en reposo.

---

## Corazón

Health.md exporta frecuencia cardíaca en reposo, frecuencia cardíaca al caminar, frecuencia cardíaca media/mínima/máxima, HRV, muestras de frecuencia cardíaca, muestras de HRV, recuperación de frecuencia cardíaca y carga de AFib.

### Construido

- [`heart-terrain`](/visualizations/heart-health/heart-terrain/theme-colors/)
- [`heart-range`](/visualizations/heart-health/heart-range/theme-colors/)
- [`hrv-trend`](/visualizations/heart-health/hrv-trend/theme-colors/)

### Planificado

- Tendencia de frecuencia cardíaca en reposo.
- Tendencia de frecuencia cardíaca al caminar.
- Tendencia de recuperación de frecuencia cardíaca.
- Gráfico de carga de AFib.
- Bloque de recuperación con HRV + frecuencia cardíaca en reposo.
- Perfil circadiano de frecuencia cardíaca por hora del día.

---

## Respiratorio y oxígeno

Health.md exporta oxígeno en sangre medio/mínimo/máximo, muestras de oxígeno en sangre, frecuencia respiratoria media/mínima/máxima y muestras de frecuencia respiratoria.

### Construido

- [`oxygen-river`](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/)
- [`oxygen-range`](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/)
- [`breathing-wave`](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/)

### Planificado

- Gráfico dedicado de rango respiratorio.
- Gráfico de eventos de desaturación de oxígeno.
- Panel respiratorio nocturno que combina fases de sueño, oxígeno y frecuencia respiratoria.

---

## Signos vitales

Health.md exporta temperatura corporal, presión arterial, glucosa en sangre, temperatura corporal basal, temperatura de muñeca, actividad electrodérmica, capacidad vital forzada, FEV1, flujo espiratorio máximo y uso de inhalador.

### Construido

- Cobertura parcial mediante tarjetas de resumen y gráficos diarios genéricos.

### Planificado

- Gráfico de rango sistólico/diastólico de presión arterial con bandas de umbral.
- Gráfico de rango de glucosa en sangre.
- Tendencia de temperatura corporal, basal y de muñeca.
- Bloque de recuperación / enfermedad por temperatura de muñeca.
- Panel de función respiratoria para FVC, FEV1, flujo máximo y uso de inhalador.
- Tendencia de actividad electrodérmica / estrés.

---

## Medidas corporales

Health.md exporta peso, altura, IMC, porcentaje de grasa corporal, masa corporal magra y circunferencia de cintura.

### Construido

- Todavía no hay un renderizador dedicado de composición corporal.

### Planificado

- Panel de composición corporal.
- Tendencia de peso con promedio móvil y línea de objetivo.
- Tendencia de IMC con bandas de categoría.
- Gráfico de grasa corporal frente a masa magra.
- Tendencia de circunferencia de cintura.

---

## Movilidad, marcha y técnica de carrera

Health.md exporta velocidad al caminar, longitud de paso, doble apoyo, asimetría al caminar, velocidad de ascenso/descenso de escaleras, caminata de seis minutos, estabilidad al caminar, velocidad al correr, longitud de zancada al correr, tiempo de contacto con el suelo, oscilación vertical y potencia de carrera.

### Construido

- [`walking-symmetry`](/visualizations/mobility-gait/walking-symmetry/theme-colors/)

### Planificado

- Panel de marcha.
- Indicador de estabilidad al caminar.
- Tendencia de caminata de seis minutos.
- Gráfico de velocidad de ascenso/descenso de escaleras.
- Panel de técnica de carrera para velocidad, zancada, contacto con el suelo, oscilación vertical y potencia.

---

## Entrenamientos

Health.md exporta recuentos de entrenamientos, minutos, calorías, distancia, tipos de entrenamiento, estadísticas de frecuencia cardíaca, métricas de forma al correr/ciclismo, potencia, elevación, vueltas, parciales, puntos de ruta, zonas de frecuencia cardíaca y muestras de series temporales de entrenamientos.

### Construido

- [`workout-log`](/visualizations/workout-analytics/workout-log/theme-colors/)
- [`workout-heart-rate`](/visualizations/workout-analytics/workout-heart-rate/theme-colors/)
- [`workout-zones`](/visualizations/workout-analytics/workout-zones/theme-colors/)
- [`workout-trends`](/visualizations/workout-analytics/workout-trends/theme-colors/)
- [`workout-intervals`](/visualizations/workout-analytics/workout-intervals/theme-colors/)
- [`workout-map`](/visualizations/workout-analytics/workout-map/theme-colors/)

### Planificado

- Mapa de calor de calendario de entrenamientos.
- Gráfico de carga de entrenamiento a partir de duración e intensidad.
- Distribución semanal de entrenamientos por tipo.
- Tendencia de ritmo y velocidad por tipo de entrenamiento.
- Tendencia de ganancia/pérdida de elevación.
- Múltiplos pequeños para comparación de rutas.
- Curva de potencia / mejores esfuerzos.
- Paneles de técnica de carrera y rendimiento en ciclismo.

---

## Mindfulness y ánimo

Health.md exporta minutos de mindfulness, sesiones de mindfulness, entradas de State of Mind, valencia media, ánimo diario, emociones momentáneas, etiquetas y asociaciones.

### Construido

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

### Planificado

- Tendencia de minutos de mindfulness.
- Racha/calendario de sesiones de mindfulness.
- Ánimo frente a adherencia a medicamentos.
- Ánimo frente a nutrición, alcohol y cafeína.
- Línea de tiempo de etiquetas de ánimo.

---

## Medicamentos

Health.md exporta inventario de medicamentos, recuentos activos/archivados, recuentos de eventos de dosis, recuentos de tomados/omitidos, detalles de medicamentos, metadatos de RxNorm/codificación, cantidades de dosis, tipo de programación, fechas programadas/de inicio/de fin, estados y metadatos.

### Construido

- [`medication-overview`](/visualizations/medication-adherence/medication-overview/theme-colors/)
- [`medication-inventory`](/visualizations/medication-adherence/medication-inventory/theme-colors/)
- [`medication-adherence-summary`](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/)
- [`medication-dose-status`](/visualizations/medication-adherence/medication-dose-status/theme-colors/)
- [`medication-adherence-trend`](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/)
- [`medication-recent-dose-events`](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/)

### Planificado

- Línea de tiempo de programación de medicamentos.
- Mapa de calor de calendario de adherencia a medicamentos.
- Gráfico de retraso de medicación que compara la hora programada con la hora tomada.
- Tendencia de cantidad de dosis.
- Vistas de correlación entre medicamentos y síntomas/ánimo.
- Panel de detalle de RxNorm / codificación.

---

## Nutrición

Health.md exporta calorías dietarias, proteína, carbohidratos, grasa, grasa saturada, grasa monoinsaturada, grasa poliinsaturada, fibra, azúcar, sodio, colesterol, agua y cafeína.

### Construido

- Todavía no hay un renderizador dedicado de nutrición.

### Planificado

- Panel de nutrición.
- Gráfico de distribución de macros.
- Gráfico de calorías ingeridas frente a calorías activas.
- Tendencia de hidratación.
- Gráfico de cantidad diaria / horario de cafeína.
- Gráficos de umbral de azúcar y sodio.
- Progreso de objetivos de fibra y proteína.

---

## Vitaminas y minerales

Health.md exporta vitaminas A, B6, B12, C, D, E, K, tiamina, riboflavina, niacina, folato, biotina, ácido pantoténico, calcio, hierro, potasio, magnesio, fósforo, zinc, selenio, cobre, manganeso, cromo, molibdeno, cloruro y yodo.

### Construido

- Todavía no hay un renderizador dedicado de micronutrientes.

### Planificado

- Mapa de calor de micronutrientes.
- Cuadrícula de progreso de valor diario recomendado.
- Panel de tendencias de vitaminas.
- Panel de tendencias de minerales.
- Panel de señales de deficiencia/exceso.
- Puntuación de integridad nutricional.

---

## Audición

Health.md exporta nivel de audio de auriculares y nivel de sonido ambiental.

### Construido

- Solo cobertura parcial a nivel de resumen.

### Planificado

- Tendencia de exposición auditiva.
- Calendario de días ruidosos.
- Bandas de umbral de exposición segura.
- Resumen semanal de exposición.

---

## Salud reproductiva y seguimiento del ciclo

Health.md exporta flujo menstrual, actividad sexual, resultado de prueba de ovulación, calidad del moco cervical y sangrado intermenstrual.

### Construido

- Todavía no hay un renderizador dedicado de salud reproductiva.

### Planificado

- Calendario de ciclo.
- Mapa de calor de flujo menstrual.
- Línea de tiempo de señales de fertilidad.
- Superposición de síntomas del ciclo que combina salud reproductiva, síntomas, ánimo y sueño.
- Línea de tiempo de manchado / sangrado intermenstrual.

---

## Síntomas

Health.md exporta recuentos diarios de síntomas de dolor de cabeza, fatiga, náuseas, mareo, cambios de ánimo, cambios de sueño, cambios de apetito, sofocos, escalofríos, fiebre, dolor lumbar, hinchazón, estreñimiento, diarrea, acidez, tos, dolor de garganta, secreción nasal, dificultad para respirar, dolor torácico, latido omitido, latido rápido, acné, piel seca, caída del cabello, lapsos de memoria, sudores nocturnos, vómitos, cólicos abdominales, dolor de pecho, dolor pélvico, dolor corporal, desmayo, pérdida de olfato, pérdida de gusto, sibilancias, congestión sinusal, incontinencia urinaria y sequedad vaginal.

### Construido

- Todavía no hay un renderizador dedicado de síntomas.

### Planificado

- Mapa de calor de calendario de síntomas.
- Tabla de clasificación de frecuencia de síntomas.
- Matriz de coocurrencia de síntomas.
- Línea de tiempo de brotes.
- Explorador de correlación de síntomas.
- Panel de síntomas agrupados por sistema corporal.

---

## Otra salud, estilo de vida y entorno

Health.md exporta exposición UV, tiempo con luz natural, caídas, alcohol en sangre, bebidas alcohólicas, administración de insulina, cepillado dental, lavado de manos, temperatura del agua y profundidad bajo el agua.

### Construido

- Todavía no hay un renderizador dedicado de estilo de vida/entorno.

### Planificado

- Calendario de luz natural / UV.
- Línea de tiempo de caídas.
- Gráfico de alcohol frente a sueño / HRV.
- Tendencia de administración de insulina.
- Rachas de cepillado dental y lavado de manos.
- Gráfico de temperatura del agua / profundidad bajo el agua.

---

## Orden de prioridad

1. Infraestructura genérica de métricas compatible con el esquema.
2. Renderizadores genéricos de tendencia, barras y mapa de calor de calendario.
3. Conjunto de signos vitales: presión arterial, glucosa, temperatura y función respiratoria.
4. Panel de composición corporal.
5. Panel de nutrición.
6. Mapa de calor de síntomas, tabla de clasificación y vistas de correlación.
7. Calendario de ciclo / salud reproductiva.
8. Mapa de calor de micronutrientes y cuadrícula RDA.
9. Panel ampliado de movilidad y forma al correr.
10. Gráficos de audición y estilo de vida/entorno.

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Última actualización: 2026-06-25</p>
