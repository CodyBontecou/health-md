---
title: "Shortcuts y App Intents"
description: "Ocho App Intents te permiten iniciar exportaciones, obtener resúmenes y alternar la programación desde Siri, la app Shortcuts, filtros de Concentración, automatizaciones y cualquier otro host compatible con AppIntent."
---

## Intents disponibles
<div class="options">
<div class="option"><strong>Exportar los datos de salud de ayer</strong><p>Atajo sin parámetros. La ruta rápida para "exportar los datos de ayer y no molestar más". Usa el mismo motor que la exportación manual. Parámetro opcional <em>Perfil</em> (véase <a href="#profiles">Perfiles de exportación</a>).</p></div>
<div class="option"><strong>Exportar datos de salud para una fecha</strong><p>Un único parámetro de <em>Fecha</em>. La hora del día se ignora. Resulta útil en automatizaciones basadas en calendario. Parámetro opcional <em>Perfil</em>.</p></div>
<div class="option"><strong>Exportar datos de salud para un intervalo de fechas</strong><p>Parámetros de <em>Fecha inicial</em> y <em>Fecha final</em>, inclusivos en ambos extremos. Úsalo para cargas históricas. Parámetro opcional <em>Perfil</em>.</p></div>
<div class="option"><strong>Exportar los últimos N días de datos de salud</strong><p>Parámetro <em>Número de días</em> (1–366). Termina ayer. Valor predeterminado: 7. Bueno para automatizaciones como "cada domingo, exportar los últimos 7 días". Parámetro opcional <em>Perfil</em>.</p></div>
<div class="option"><strong>Obtener resumen de salud para una fecha</strong><p>Devuelve una instantánea estructurada: pasos, calorías activas, sueño y frecuencia cardíaca, sin escribir nada en la bóveda. Úsalo en Shortcuts para pasar valores a otras apps.</p></div>
<div class="option"><strong>Obtener estado de la última exportación</strong><p>Devuelve la marca de tiempo, el estado de éxito, el recuento de días y cualquier motivo de fallo de la exportación registrada más reciente. Una solicitud con el dispositivo bloqueado queda pendiente hasta que se reintente, por lo que no se devuelve como estado actual mientras está pendiente.</p></div>
<div class="option"><strong>Activar o desactivar exportación programada</strong><p>Parámetro booleano. Úsalo para suspender la programación, por ejemplo durante una Concentración de vacaciones, y reanudarla más tarde.</p></div>
<div class="option"><strong>Exportar datos de salud</strong><p>Exportación genérica: usa el intervalo de fechas del último estado del modal Exportar dentro de la app. Es menos común; las variantes con intervalo de fechas suelen ser más claras. Parámetro opcional <em>Perfil</em>.</p></div>
</div>

<a id="profiles"></a>
## Perfiles de exportación
<p>Los cinco intents de exportación aceptan un parámetro opcional <em>Perfil</em>. Déjalo vacío para ejecutar con tus ajustes de exportación actuales de la app; pasa el nombre de un perfil guardado para ejecutar la configuración congelada de ese perfil —su selección de métricas, formatos y destino— sin importar lo que la app muestre en ese momento.</p>
<div class="callout">
<strong>Atención para los atajos existentes sin parámetro.</strong>
<p style="margin-top:6px;">Una vez que crees tu primer perfil de exportación en la app, un atajo sin <em>Perfil</em> definido exporta usando los ajustes guardados del perfil <em>activo</em> en lugar de los ajustes en vivo de la app. Si dependes del comportamiento anterior, fija el atajo a un perfil concreto (o mantén cero perfiles) para seguir siendo explícito. Un nombre de perfil que ya no existe falla con un error claro en lugar de exportar lo incorrecto.</p>
</div>
## Dónde encontrarlos
<p>Abre la app Shortcuts en iOS o macOS. Toca el botón <em>+</em> para crear un nuevo atajo y busca &quot;Health.md&quot; o cualquiera de los títulos de intent anteriores. Están en la categoría <em>Salud</em>.</p>
<p>La mayoría de los intents tienen <code>openAppWhenRun = false</code>, así que se ejecutan sin abrir la app: sin lanzamiento visible ni parpadeo de interfaz. Funcionan desde automatizaciones, filtros de Concentración, el traspaso de Hey Siri y el Action Button.</p>

<div class="callout">
<strong>Ejecutar mientras está bloqueado no desbloquea HealthKit.</strong>
<p style="margin-top:6px;">Apple protege los datos de HealthKit mientras el iPhone está bloqueado y <a href="https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web">retira el acceso de las apps unos diez minutos después del bloqueo</a>. <em>Permitir ejecución al estar bloqueado</em> deja que Shortcuts inicie la acción, pero no anula la protección de datos de HealthKit. El permiso de contenido de la app Health.md en Shortcuts tampoco la anula.</p>
<p>Si HealthKit no está disponible, Health.md conserva las fechas solicitadas como pendientes y publica una notificación <em>La exportación de salud necesita atención</em>. Desbloquea el iPhone y luego toca la notificación o abre Health.md para reintentar. No se puede garantizar una exportación totalmente desatendida mientras el teléfono permanezca bloqueado.</p>
</div>

<a id="recipe-nightly-export-with-confirmation"></a>
## Receta: exportación diaria con confirmación
<ol>
<li><strong>Automatización personal</strong> → <em>Hora del día</em> → elige una hora en la que normalmente uses el iPhone desbloqueado, como 8:00 AM.</li>
<li>Intent <em>Exportar los datos de salud de ayer</em>.</li>
<li>Intent <em>Obtener estado de la última exportación</em>.</li>
<li><em>Mostrar notificación</em> con el resultado.</li>
</ol>
<p><strong>Nota sobre estado pendiente:</strong> <em>Obtener estado de la última exportación</em> lee la entrada registrada más reciente del historial de exportaciones. Si esta ejecución encontró datos de HealthKit bloqueados, es posible que todavía muestre la exportación anterior hasta que reintentes la solicitud pendiente. La notificación de recuperación propia de Health.md es la señal autorizada para trabajo pendiente.</p>

## Receta: carga histórica puntual
<ol>
<li>Crea un atajo.</li>
<li><em>Exportar datos de salud para un intervalo de fechas</em> con start = 2024-01-01, end = 2024-12-31.</li>
<li>Ejecútalo desde Shortcuts. Recorre el año y escribe un archivo por día. Puede tardar unos minutos en años completos.</li>
</ol>

## Receta: pausar la programación durante vacaciones
<ol>
<li><strong>Filtro de Concentración</strong>: cuando se active la Concentración <em>Vacaciones</em>, ejecuta <em>Activar o desactivar exportación programada</em> con Enabled = false.</li>
<li>Cuando se desactive la Concentración, vuelve a ejecutarlo con Enabled = true.</li>
</ol>

<div class="callout">
<strong>Se requiere autorización.</strong>
<p style="margin-top:6px;">Los intents heredan tu permiso de HealthKit dentro de la app y la selección de bóveda. Fallarán con un error claro si la app no se ha abierto y configurado al menos una vez en este dispositivo.</p>
</div>

## Contenido relacionado

<div class="related">
  <a href="/es/docs/scheduling/"><span>Origen</span>Programación: el equivalente dentro de la app del intent de alternancia.</a>
  <a href="/es/docs/export/"><span>Origen</span>Exportar: el equivalente dentro de la app de los intents por intervalo de fechas.</a>
</div>
