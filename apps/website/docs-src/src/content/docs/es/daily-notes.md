---
title: "Inserción en notas diarias"
description: "Combina métricas de salud seleccionadas con el YAML frontmatter, y opcionalmente con el cuerpo, de tus notas diarias existentes: las que escribes en Obsidian o en cualquier otra app de Markdown."
---

## Qué hace
<p>Si llevas notas diarias, por ejemplo <code>Daily/2026-04-28.md</code>, activa esta opción y la app <em>combinará</em> las métricas seleccionadas con el YAML frontmatter de esas notas en cada exportación, sin tocar el resto del contenido de la nota.</p>

<div class="doc-diagram merge-preview" aria-label="Frontmatter de nota diaria antes y después de la combinación de Health.md">
<div class="merge-card">
<strong>Antes</strong>
<pre><code>---
title: Tuesday note
mood: focused
---

Wrote launch notes...</code></pre>
</div>
<div class="merge-card">
<strong>Después de exportar</strong>
<pre><code>---
title: Tuesday note
mood: focused
steps: 12642
sleep_total_hours: 7.31
workout_count: 1
---

Wrote launch notes...</code></pre>
</div>
</div>

<p>Opcionalmente, la app también puede insertar secciones de Markdown (Sueño, Actividad, Corazón, etc.) en el cuerpo de la nota. Esas secciones están <em>gestionadas por la app</em>: se reemplazan limpiamente en cada exportación. Los encabezados que escribes tú no se modifican.</p>

## Ubicación
<div class="options">
<div class="option"><strong>Carpeta</strong><p>Ruta relativa a la bóveda de la carpeta de notas diarias. Valor predeterminado: <code>Daily</code>. Déjala vacía para usar la raíz de la bóveda. Ejemplos: <code>Daily</code>, <code>Journal/Daily</code>.</p></div>
<div class="option"><strong>Nombre de archivo</strong><p>Patrón para el nombre de la nota sin extensión. El valor predeterminado <code>{date}</code> se resuelve como <code>2026-04-28</code>.</p></div>
</div>

## Marcadores de posición para nombres de archivo
<p>Combínalos como quieras:</p>
<ul>
<li><code>{date}</code>: fecha ISO completa (<code>2026-04-28</code>)</li>
<li><code>{year}</code>, <code>{month}</code>, <code>{day}</code></li>
<li><code>{weekday}</code>: nombre corto (<code>Tue</code>)</li>
<li><code>{monthName}</code>: nombre largo (<code>April</code>)</li>
<li><code>{quarter}</code>: Q1 / Q2 / Q3 / Q4</li>
</ul>
<p>Ejemplo: <code>{year}/{monthName}/{date}-{weekday}</code> → <code>2026/April/2026-04-28-Tue.md</code>. La línea de vista previa bajo el campo muestra la ruta resuelta en vivo.</p>

## Opciones
<div class="options">
<div class="option"><strong>Crear nota si falta</strong><p>Si no existe la nota diaria para una fecha determinada, crea una nueva. Déjalo desactivado si creas tus propias notas diarias con Obsidian Templater o un plugin similar.</p></div>
<div class="option"><strong>Insertar secciones de métricas</strong><p>También escribe encabezados de Sueño, Actividad, Corazón, etc. en el cuerpo de la nota. Están gestionados por la app y se reemplazan limpiamente en cada exportación. Desactivado de forma predeterminada.</p></div>
</div>

## Qué métricas se insertan
<p>Las que hayas seleccionado en <em>Métricas de salud</em>. Aquí no hay un selector independiente. Cambia allí la selección de métricas, y la inserción en notas diarias la seguirá.</p>

## Vista previa del frontmatter
<p>La parte inferior de la pantalla Inserción en notas diarias tiene una vista previa en vivo del frontmatter que se combinará. Se actualiza cuando cambias la selección de métricas o los campos de frontmatter en la personalización del formato.</p>

<div class="callout">
<strong>Cómo funciona la combinación.</strong>
<p style="margin-top:6px;">Si tu nota diaria existente ya tiene frontmatter, la app conserva tus claves y solo añade o actualiza las claves que le pertenecen. Las secciones del cuerpo gestionadas por la app están envueltas en comentarios HTML, por lo que las repeticiones son idempotentes.</p>
</div>

## Contenido relacionado

<div class="related">
  <a href="/es/docs/metrics/"><span>Requisito</span>Métricas de salud: elige qué se insertará.</a>
  <a href="/es/docs/format/"><span>Formato</span>Editor de campos de frontmatter: cambia nombres de claves y añade campos personalizados.</a>
  <a href="/es/docs/individual-tracking/"><span>Granular</span>Seguimiento de entradas individuales: alternativa para el seguimiento por evento.</a>
</div>
