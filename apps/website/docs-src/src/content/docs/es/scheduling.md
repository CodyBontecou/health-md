---
title: "Programación"
description: "Ejecuta exportaciones automáticamente con cadencias diarias, semanales o de calendario personalizadas. iOS usa tareas en segundo plano y una notificación local de recuperación cuando los datos protegidos no están disponibles."
---

## La pestaña Programar
<p>Es una pantalla de estado, no un panel de ajustes. Te muestra de un vistazo:</p>
<ul>
<li>Si la programación está activada o desactivada</li>
<li>La próxima ejecución programada, si existe</li>
<li>El resultado de la última ejecución</li>
</ul>
<p>Un botón, <em>Configurar programación</em> o <em>Gestionar programación</em>, abre la vista de detalles.</p>

## Ajustes de programación
<div class="options">
<div class="option"><strong>Activar exportaciones programadas</strong><p>Interruptor principal en la parte superior. Cuando está desactivado, no hay ejecuciones en segundo plano ni notificaciones.</p></div>
<div class="option"><strong>Frecuencia</strong><p>Diaria, semanal o personalizada. Las programaciones personalizadas se repiten cada N días, semanas o meses desde una fecha inicial. El intervalo retrospectivo determina cuántos días completos incluye cada ejecución.</p></div>
<div class="option"><strong>Hora</strong><p>Hora y minuto. iOS lo trata como una indicación, no como una garantía; consulta el aviso de limitaciones más abajo.</p></div>
</div>

## Historial de exportaciones
<p>La lista en la parte inferior de la pantalla Programar registra cada ejecución programada con su resultado. Toca una fila para ver los detalles. Las ejecuciones fallidas incluyen un botón <em>Reintentar</em> que vuelve a ejecutar ese intervalo con los ajustes y el destino configurados actualmente, y luego registra una nueva fila del historial.</p>

## Cómo funciona realmente la programación en iOS
<div class="doc-diagram">
  <div class="flow-steps" aria-label="Flujo de respaldo de exportación programada">
    <span><strong>1. Hora objetivo</strong>Health.md pide a iOS que active la app cerca de la hora que elegiste.</span>
    <span><strong>2. Intento en segundo plano</strong>Si el dispositivo está disponible, iOS ejecuta una tarea de actualización en segundo plano.</span>
    <span><strong>3. Respaldo si está bloqueado</strong>Si HealthKit no está disponible, Health.md publica una notificación.</span>
    <span><strong>4. Toca para terminar</strong>Al abrir la notificación, la app puede leer HealthKit y exportar.</span>
  </div>
</div>

<div class="callout">
<strong>Limitaciones de iOS que conviene conocer.</strong>
<p style="margin-top:6px;">Los datos de HealthKit no se pueden leer mientras el dispositivo está bloqueado. Las exportaciones programadas se ejecutan mediante <code>BGAppRefreshTask</code>, que iOS programa de forma oportunista según los patrones de uso: la hora configurada es un objetivo, no un contrato. Como respaldo, la app publica una notificación local a la hora programada si el dispositivo está bloqueado; tócala para ejecutar la exportación.</p>
</div>
<ul>
<li>La hora programada es aproximada. iOS puede ejecutar la tarea antes, después u omitirla si el dispositivo está sin batería o desconectado.</li>
<li>Las exportaciones programadas funcionan mejor cuando el teléfono suele estar conectado y desbloqueado aproximadamente a la misma hora cada día.</li>
<li>Si la exportación falla porque el dispositivo estaba bloqueado, toca la notificación; eso ejecuta la exportación con acceso a HealthKit.</li>
</ul>

## Control programático
<p>Puedes activar o desactivar la programación desde Shortcuts con el intent <em>Turn Scheduled Export On or Off</em>. <a href="/es/docs/shortcuts/">Consulta Shortcuts</a> para ver ejemplos.</p>

## Programaciones por perfil y cancelación

- Cada perfil conserva su propia programación, incluida una cadencia personalizada; cambiar el perfil activo no redirige la programación de otro.
- Aparece un aviso de colisión cuando varios perfiles podrían escribir las mismas rutas generadas en el mismo destino. Revísalo antes de activar programaciones que compitan; Health.md no cambia ningún perfil en silencio.
- Detener o Cancelar solo finaliza el intento actual. Las fechas terminadas se conservan, las pendientes pueden reintentarse y la programación sigue activada.
- Cada fila del historial permanece vinculada al perfil de la ejecución y a la etiqueta respetuosa con la privacidad del destino real.

Administra los ajustes congelados y el destino de cada perfil en [Perfiles de exportación](/es/docs/export-profiles/).

## Contenido relacionado

<div class="related">
  <a href="/es/docs/export-profiles/"><span>Perfiles</span>Administra programaciones y destinos independientes.</a>
  <a href="/es/docs/export/"><span>Manual</span>Exportar: para intervalos de fechas puntuales.</a>
  <a href="/es/docs/shortcuts/"><span>Automatizar</span>Shortcuts: alterna la programación desde automatizaciones.</a>
  <a href="/es/docs/sync/"><span>Entre dispositivos</span>Sincronización con Mac: programa también en el Mac.</a>
</div>
