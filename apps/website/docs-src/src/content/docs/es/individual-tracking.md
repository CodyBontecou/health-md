---
title: "Seguimiento de entradas individuales"
description: "Opcionalmente escribe un archivo por cada entrada con marca de tiempo: cada entrenamiento, cada lectura de presión arterial y cada registro de ánimo obtiene su propio archivo Markdown con la marca de tiempo incluida en el nombre."
---

## Cuándo usarlo
<p>Las exportaciones diarias te dan un archivo por día con resúmenes. El <em>seguimiento individual</em> sirve cuando quieres <em>citar un evento concreto</em>: enlazar un entrenamiento específico desde una nota de diario o crear un backlink de una entrada de ánimo hacia una revisión semanal.</p>

<p>Esto se suma a la exportación diaria, no la reemplaza. Con ambas opciones activadas, obtienes ambos tipos de archivos.</p>

## Configuración en dos pasos
<p>La interfaz de ajustes está diseñada intencionalmente como un flujo de dos pasos:</p>
<ol>
<li><strong>Interruptor principal.</strong> Activa la función globalmente.</li>
<li><strong>Selección por métrica.</strong> Elige <em>qué</em> métricas obtienen archivos individuales. La mayoría de las personas no quiere un archivo por cada lectura de frecuencia cardíaca (10.000 al día), pero sí quiere uno por entrenamiento (aprox. 1 al día).</li>
</ol>

## Acciones rápidas
<div class="options">
<div class="option"><strong>Activar métricas sugeridas</strong><p>Valores predeterminados razonables: ánimo, síntomas, entrenamientos, presión arterial y glucosa en sangre. Son las métricas donde un archivo por entrada tiene sentido.</p></div>
<div class="option"><strong>Activar todas las métricas</strong><p>Todo. Ten cuidado: esto puede producir miles de archivos por día.</p></div>
<div class="option"><strong>Desactivar todas las métricas</strong><p>Borra la selección por métrica sin cambiar el interruptor principal.</p></div>
</div>

## Estructura de carpetas
<div class="options">
<div class="option"><strong>Carpeta de entradas</strong><p>Ruta relativa a la bóveda donde se guardan los archivos individuales. Valor predeterminado: <code>entries</code>.</p></div>
<div class="option"><strong>Organizar por categoría</strong><p>Si está activado, las entradas se anidan en subcarpetas por categoría (<code>entries/workouts/</code>, <code>entries/symptoms/</code>). Si está desactivado, todas las entradas quedan en una sola carpeta plana.</p></div>
</div>

## Plantilla de nombre de archivo
<p>Valor predeterminado: <code>{date}_{time}_{metric}</code>. Marcadores de posición disponibles: <code>{date}</code>, <code>{time}</code>, <code>{metric}</code>, <code>{category}</code>. Ejemplo de salida:</p>

<div class="doc-diagram folder-tree" aria-label="Árbol de archivos de ejemplo para entradas individuales">
<span>{vault}/entries/</span>
<span>├─ workouts/2026_07_14_0920_workouts_workouts_71000000-0000-0000-0000-000000000008.md</span>
<span>├─ symptoms/2026_07_14_0916_symptom_headache_symptom_headache_71000000-0000-0000-0000-000000000002.md</span>
<span>└─ vitals/2026_07_14_0918_blood_pressure_blood_pressure_71000000-0000-0000-0000-000000000004.md</span>
</div>

<p>Las entradas respaldadas por una fuente canónica añaden la métrica seleccionada y el UUID de HealthKit en minúsculas después del nombre de archivo configurado. Esto mantiene estable el mismo registro de origen entre repeticiones y evita colisiones dentro del mismo minuto. Las entradas de compatibilidad sin UUID conservan el comportamiento heredado de nombre de archivo más corto.</p>

<div class="callout">
<strong>Aviso.</strong>
<p style="margin-top:6px;">Aquí solo aparecen las categorías donde activaste al menos una métrica en <em>Métricas de salud</em>. Activa primero una métrica allí y vuelve luego para elegir si tendrá seguimiento por entrada. Consulta el <a href="/es/docs/reference/individual-entry-tracking/">contrato de identidad de registros de origen</a> y la <a href="/es/docs/reference/generated/individual/filename-path-matrix/">matriz de nombres de archivo</a> generada antes de construir automatizaciones alrededor de rutas.</p>
</div>

## Contenido relacionado

<div class="related">
  <a href="/es/docs/metrics/"><span>Requisito</span>Métricas de salud: activa métricas primero.</a>
  <a href="/es/docs/format/"><span>Salida</span>Formato: también se aplica a los archivos de entrada.</a>
  <a href="/es/docs/daily-notes/"><span>Alternativa</span>Inserción en notas diarias: otra forma de adjuntar métricas a notas.</a>
  <a href="/es/docs/reference/individual-entry-tracking/"><span>Contrato</span>Referencia de entradas individuales: identidad UUID, frontmatter, entradas especializadas y respaldos de compatibilidad.</a>
</div>
