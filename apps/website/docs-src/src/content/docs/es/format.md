---
title: "Personalización del formato"
description: "Controla el formato de salida sin cambiar lo que se recopila. Elige un formato de archivo, convenciones de fecha, hora y unidades, personaliza el YAML frontmatter y elige una plantilla de Markdown."
---

## Formatos de salida
<div class="options">
<div class="option"><strong>Markdown (.md)</strong><p>Valor predeterminado. Un archivo por día. YAML frontmatter opcional y secciones con encabezados por categoría.</p></div>
<div class="option"><strong>Obsidian Bases</strong><p>Markdown con frontmatter estructurado optimizado para el plugin <a href="https://help.obsidian.md/Plugins/Bases">Bases</a> de Obsidian. Las propiedades numéricas permanecen numéricas; las fechas permanecen como fechas.</p></div>
<div class="option"><strong>JSON</strong><p>Un archivo JSON por día. Los resúmenes diarios del esquema v7 pueden incrustar el archivo autorizado <code>healthmd.healthkit_records</code> v1 cuando Lossless Health Records está activado.</p></div>
<div class="option"><strong>CSV</strong><p>Un archivo CSV por día con la cabecera <code>Date,Category,Metric,Value,Unit,Timestamp</code>. Las filas de resumen de compatibilidad contienen cinco campos y omiten la columna de marca de tiempo; las filas con marca de tiempo y de registro canónico contienen los seis.</p></div>
</div>

<div class="callout">
<strong>¿Necesitas el contrato exacto?</strong>
<p style="margin-top:6px;">Consulta la <a href="/es/docs/reference/export-formats/">referencia de formatos</a> respaldada por producción, los <a href="/es/docs/reference/generated/core/csv-row-contracts/">contratos de filas CSV</a> y los fixtures completos descargables.</p>
</div>

## Fecha y hora
<p>Selectores para formato de fecha, por ejemplo <code>YYYY-MM-DD</code> o <code>MMM d, yyyy</code>, y formato de hora de 12 o 24 horas. El bloque de vista previa en la parte inferior de la pantalla se actualiza en vivo a medida que cambias los ajustes.</p>

## Sistema de unidades
<p>Alterna entre <em>Métrico</em> e <em>Imperial</em>. Afecta distancia (m/km frente a ft/mi), peso (kg frente a lb), temperatura (°C frente a °F) y algunas otras medidas. HealthKit siempre almacena en unidades canónicas; la conversión ocurre al exportar.</p>

## Campos de frontmatter
<p>Al tocar <em>Campos de frontmatter</em>, se abre un editor dedicado:</p>
<ul>
<li>Activa o desactiva campos integrados individuales (date, weekday, totalSteps, etc.)</li>
<li>Cambia el nombre de un campo; resulta útil si tu configuración de Obsidian espera claves distintas</li>
<li>Añade campos personalizados con valores estáticos, por ejemplo <code>type: health</code></li>
<li>Añade campos con marcadores de posición que se resuelven al exportar, por ejemplo <code>weather: {weather}</code></li>
</ul>

## Plantilla de Markdown
<p>Al tocar <em>Plantilla de Markdown</em>, se abre un editor de plantillas con varios estilos integrados (Compacto, Secciones, Detallado) y un modo totalmente personalizado. El bloque de vista previa muestra el resultado con los datos de hoy.</p>

## Vista previa
<p>En la parte inferior de la pantalla Formato, un bloque de vista previa en vivo renderiza los datos de hoy con tus ajustes actuales. Es la forma más rápida de iterar: cambia una opción, mira la vista previa y repite.</p>

## Contenido relacionado

<div class="related">
  <a href="/es/docs/metrics/"><span>Qué</span>Métricas de salud: elige primero los datos.</a>
  <a href="/es/docs/individual-tracking/"><span>Granular</span>Seguimiento de entradas individuales: una salida completamente distinta, con archivos por entrada.</a>
  <a href="/es/docs/daily-notes/"><span>Obsidian</span>Inserción en notas diarias: usa los mismos campos de frontmatter.</a>
  <a href="/es/docs/reference/export-formats/"><span>Contrato</span>Formatos de exportación: comportamiento exacto de JSON, CSV, Markdown y Bases.</a>
</div>
