---
title: "Programar exportaciones de Apple Health y resolver ejecuciones omitidas"
description: "Verifica una exportación programada, entiende los días completos y recupera fechas pendientes. La hora de iOS no está garantizada; Reintentar usa los ajustes actuales."
---

Esta página describe la programación en iPhone. Android tiene otros permisos en segundo plano y requisitos de compra; consulta [Automatización en Android](/es/docs/android/).

## Verifica la primera exportación programada

1. Activa el perfil previsto. Revisa métricas, formatos, nivel de detalle, modo de escritura y destino. Exporta manualmente un día completo y comprueba el archivo guardado o el resultado del endpoint antes de automatizar.
2. Abre Programar y Configurar programación o Gestionar programación. Actívala, elige Diaria, Semanal o Personalizada, establece la hora y empieza con un día completo de retrospectiva. Permite las notificaciones si quieres recordatorios locales de recuperación.
3. Comprueba el estado, la próxima ejecución y el último resultado. Tras un intento, revisa el historial y el destino real; una fecha futura o una notificación no demuestra que se hayan escrito datos.
4. Revisa fechas, unidades, cobertura y datos ausentes. Un archivo guardado no demuestra por sí solo una captura completa.

En Apple, una solicitud programada que exporta al menos una fecha comparte las cinco acciones gratuitas con las exportaciones manuales y otras acciones contabilizadas. Full Access elimina ese límite compartido. Consulta [Desbloqueo y compras](/es/docs/paywall/).

## Entiende el intervalo de días completos

Las frecuencias diaria, semanal y personalizada pueden tener un intervalo retrospectivo. La personalizada se repite cada N días, semanas o meses desde la fecha inicial. Cada nueva ejecución vuelve a exportar todo el intervalo de días completos, incluso fechas exportadas antes. Tres días incluyen ayer y los dos días anteriores; si la ejecución se retrasa, el intervalo sigue anclado al día programado.

La actualización de hoy es independiente y no sustituye ese intervalo. Revisa rutas y modo de escritura antes de solapar exportaciones; no sumes instantáneas diarias repetidas como mediciones nuevas.

## Elige la recuperación correcta

- **Recuperación programada pendiente:** desbloquea el iPhone, abre Health.md y revisa el intento pendiente. Conserva las fechas exactas sin resolver, los ajustes guardados y el destino. Los días completados siguen completados; recuperar no amplía el intervalo.
- **Reintentar desde el historial:** inicia otra ejecución para ese intervalo con los ajustes y el destino actuales y crea una nueva fila. Comprueba la configuración activa antes de pulsar Reintentar. No equivale a reanudar un intento pendiente congelado.
- **Destino cambiado o inaccesible:** restablece el acceso o revisa el perfil pendiente. Una recuperación API anterior del iPhone no debe adoptar silenciosamente otro endpoint o credencial. No inicies reintentos nuevos repetidamente mientras el original siga pendiente.

Consulta las reglas de recuperación, identidad y destino en [Perfiles de exportación](/es/docs/export-profiles/).

## Qué garantiza iOS y qué no

La hora elegida es un objetivo, no una hora de finalización garantizada. iOS controla la ejecución en segundo plano y el bloqueo puede impedir leer HealthKit. Las solicitudes y notificaciones silenciosas no evitan esa protección.

Los avisos locales requieren permiso y no garantizan la entrega a la hora objetivo. Si llega uno, desbloquea el dispositivo y ábrelo para intentar recuperar. Si no llega, abre Health.md y revisa pendientes e historial. Comprueba el resultado: una alerta o el tiempo transcurrido no demuestran el éxito.

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
