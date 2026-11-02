---
title: "Programe exportaciones Apple Health y solucione problemas de ejecuciones perdidas"
description: "Verifique una exportación programada, comprenda la retrospectiva del día completado y recupere las fechas pendientes. iPhone la sincronización en segundo plano es el mejor esfuerzo; El historial de reintento utiliza la configuración actual."
---

Esta página describe la programación de iPhone . Android tiene diferentes permisos en segundo plano y requisitos de compra; consulte [automatización de Android](/es/docs/android/).

## Verificar la primera exportación programada

1. Activa el perfil deseado. Consulta sus métricas, formatos, detalle de datos, comportamiento de escritura y destino. Ejecute un día completo manualmente e inspeccione el archivo guardado o el resultado del punto final antes de habilitar la automatización.
2. Abra Horario, luego Configurar Horario o Administrar Horario. Habilite el cronograma, elija Diario, Semanal o Personalizado, establezca la hora y comience con una vista retrospectiva del día completo. Permita notificaciones si desea recordatorios de recuperación locales.
3. Verifique si la programación está habilitada, la siguiente ocurrencia y el último resultado. Después de un intento, inspecciona los detalles de su historial y el destino real; una etiqueta o notificación de la siguiente ejecución no es prueba de que se escribieron datos.
4. Verifique las fechas exportadas, unidades, cobertura y datos faltantes. Un archivo guardado no demuestra por sí solo una captura completa del código fuente.

En la versión de teléfono con suscripción habilitada, las exportaciones programadas y manuales requieren una prueba activa, una suscripción, una compra de por vida o un acceso permanente preservado. No existe ningún subsidio de libre exportación local. El acceso caducado debe restablecerse antes de que se pueda reanudar el trabajo pendiente. Consulte [desbloqueo y muro de pago](/es/docs/paywall/).

## Comprender la ventana del día completado

Los horarios diarios, semanales y personalizados pueden tener una retrospectiva. La cadencia personalizada se repite cada N días, semanas o meses desde su fecha de inicio. Cada nueva ocurrencia reexporta toda la ventana configurada del día completo, incluidas las fechas exportadas anteriormente. Una mirada retrospectiva de tres días cubre ayer y los dos días anteriores; La ejecución retrasada mantiene la ventana anclada al día programado del incendio.

La actualización de hoy es un trabajo independiente del día actual, no un reemplazo de la ventana del día completo. Inspeccionar rutas y escribir comportamiento antes de superponer exportaciones; No agregue instantáneas diarias repetidas como nuevas mediciones.

## Elija la ruta de recuperación correcta

- **Recuperación programada pendiente:** desbloquee iPhone , abra Health.md e inspeccione el intento pendiente. Conserva sus fechas exactas no resueltas, configuraciones guardadas y destino. Las fechas completadas permanecen completas; la recuperación no se expande hacia una nueva mirada retrospectiva.
- **Reintentar desde el historial:** esto inicia una nueva ejecución para ese rango utilizando la configuración y el destino configurados actualmente y registra una nueva fila del historial. Verifique la configuración activa antes de presionar Reintentar. No es lo mismo que reanudar un intento pendiente congelado.
- **Destino cambiado o no disponible:** restaurar el acceso o inspeccionar el perfil pendiente antes de volver a intentarlo. Una recuperación de API iPhone antigua no debe adoptar silenciosamente un punto final o una credencial modificados. No inicie nuevos intentos repetidamente mientras el intento original no se haya resuelto.

Revise la recuperación pendiente, la identidad del perfil y las reglas de destino en [Exportar perfiles](/es/docs/export-profiles/).

## Lo que iOS garantiza y lo que no garantiza

El tiempo seleccionado es un objetivo, no un tiempo de finalización garantizado. iOS controla el tiempo de ejecución en segundo plano y la protección del dispositivo bloqueado puede evitar las lecturas de HealthKit . Las solicitudes en segundo plano y las notificaciones de activación silenciosa no eluden esa protección.

Las notificaciones de recuperación local requieren permiso de notificación y no son garantía de entrega en el momento objetivo. Si recibe uno, desbloquee el dispositivo y ábralo para permitir que Health.md intente la recuperación. Si no llega ninguna notificación, abra Health.md y verifique el historial y el trabajo pendiente. Verifique el resultado en lugar de asumir que una alerta o el tiempo transcurrido significa éxito.

## Control programático
 <p> Puede activar o desactivar la programación desde Shortcuts usando la intención <em> Activar o desactivar la exportación programada </em> . <a href="/es/docs/shortcuts/"> Consulte Shortcuts </a> para ver ejemplos. </p>

## Horarios y cancelación del perfil

- Cada perfil puede mantener su propio horario, incluida una cadencia personalizada. Cambiar el perfil activo no reorienta la programación de otro perfil.
- Aparece una advertencia de colisión cuando los perfiles pueden escribir las mismas rutas renderizadas en el mismo destino. Revíselo antes de habilitar horarios competitivos. Health.md no cambia silenciosamente ninguno de los perfiles.
- Detener o Cancelar finaliza solo el intento actual. Las fechas completadas permanecen completadas, las fechas no resueltas siguen siendo reintentables y la programación permanece habilitada.
- Cada fila del historial permanece anclada al perfil de tiempo de ejecución y a la etiqueta de destino seguro para la privacidad realmente utilizada.

Administre la configuración congelada y el destino por perfil en [Exportar perfiles](/es/docs/export-profiles/).

## Relacionado

<div class="related">
 <a href="/es/docs/export-profiles/"> <span> Múltiples flujos de trabajo </span> Exporta perfiles, otorga a cada configuración guardada su propio destino y cadencia. </a>
 <a href="/es/docs/export/"> <span> Manual </span> Exportación, para rangos de fechas únicos. </a>
 <a href="/es/docs/shortcuts/"> <span> Automatizar </span> Shortcuts , alternar el horario de automatizaciones. </a>
 <a href="/es/docs/sync/"> <span> Multidispositivo </span> Mac Sync, programe también en Mac. </a>
 </div>
