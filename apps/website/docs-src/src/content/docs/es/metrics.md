---
title: "Métricas de salud"
description: "Elige desde el catálogo actual de métricas de Apple Health de Health.md. Busca, activa categorías completas de una vez o entra en el control por métrica."
---

<div class="callout">
<strong>Nota sobre Android.</strong>
<p style="margin-top:6px;">Esta página documenta el selector de métricas de Apple Health y la referencia generada de datos de HealthKit. La app para Android expone 106 métricas de Health Connect; consulta la <a href="/es/docs/android/">guía de Android</a> para configurar Health Connect y conocer el comportamiento específico de esa plataforma.</p>
</div>

## Diseño
<div class="options">
<div class="option"><strong>Cabecera de recuentos</strong><p>Lectura en vivo de métricas y categorías activadas. Mantén pulsado para copiar al portapapeles el estado exacto de la selección.</p></div>
<div class="option"><strong>Todas las métricas activadas</strong><p>Interruptor principal que activa o desactiva todas las categorías. Resulta útil como punto de partida: activa todo y luego desactiva lo que no te interese.</p></div>
<div class="option"><strong>Búsqueda</strong><p>Filtro en vivo sobre nombres e identificadores de métricas. Prueba con "heart", "sleep", "vo2".</p></div>
</div>

## Categorías
<p>El selector agrupa resúmenes ordinarios y definiciones de registros de origen en categorías como Sueño, Actividad, Corazón, Respiratorio, Signos vitales, Medidas corporales, Movilidad, Ciclismo, Nutrición, Mindfulness, Salud reproductiva, Síntomas, Medicamentos, registros especializados y Entrenamientos. Cada fila muestra el estado activado/desactivado y el recuento en vivo de definiciones activadas dentro de ella. El <a href="/es/docs/reference/generated/core/metric-catalog/">catálogo de métricas</a> generado por producción es el inventario actual autorizado.</p>

<p>Toca una categoría para entrar en sus métricas. Cada métrica tiene su propio interruptor e identificador de HealthKit. El color del punto refleja si HealthKit tiene datos actualmente para esa métrica en este dispositivo.</p>

## Alcance de la selección
<p>Tu selección de métricas controla <em>todo</em>:</p>
<ul>
<li>Exportaciones diarias: solo las métricas activadas aparecen en el archivo</li>
<li>Seguimiento de entradas individuales: solo las métricas activadas generan archivos por entrada</li>
<li>Inserción en notas diarias: solo las métricas activadas se combinan con el frontmatter</li>
<li>Shortcuts: las exportaciones por intervalo de fechas usan la misma selección</li>
</ul>

<div class="callout">
<strong>Consejo práctico.</strong>
<p style="margin-top:6px;">Empieza con poco. Activa Sueño, Actividad y Corazón. Ejecuta una exportación. Mira cómo queda el archivo. Luego añade más categorías. Es más rápido añadir que revisar un archivo de 50 líneas con métricas que no te interesan.</p>
</div>

## Contenido relacionado

<div class="related">
  <a href="/es/docs/reference/"><span>Referencia</span>Referencia de exportación: cada métrica de Apple, clave, unidad, definición de registro de origen y estructura de exportación.</a>
  <a href="/es/docs/android/"><span>Android</span>App para Android: configuración de Health Connect, métricas, destinos y automatización.</a>
  <a href="/es/docs/format/"><span>Cómo</span>Formato: cambia cómo se escriben las métricas que eliges.</a>
  <a href="/es/docs/individual-tracking/"><span>Granular</span>Seguimiento de entradas individuales: también escribe un archivo por entrada con marca de tiempo.</a>
  <a href="/es/docs/daily-notes/"><span>Obsidian</span>Inserción en notas diarias: envía estas métricas a tus notas diarias.</a>
</div>
