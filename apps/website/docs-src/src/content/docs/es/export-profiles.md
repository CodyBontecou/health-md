---
title: "Perfiles de exportación"
description: "Guarda juntos los ajustes de exportación y un destino para ejecutar o programar esa configuración desde iPhone, Android, Atajos, la CLI, Tasker o adb."
---

Los perfiles de exportación mantienen unida una configuración repetible. Adminístralos en Health.md para iPhone o Android. En las plataformas Apple, el flujo de administración actual solo está documentado y probado en iPhone; no se afirma que exista una pantalla de administración en iPad o Mac.

## Administrar y editar perfiles

Abre **Ajustes → Perfiles de exportación**. La lista marca el perfil activo y permite crear, renombrar, duplicar, eliminar, activar o inspeccionar perfiles. Abre la vista de detalles para copiar su identificador estable. El último perfil no se puede eliminar.

La pestaña Exportar modifica el perfil activo. Activa otro antes de cambiar los ajustes si no deseas actualizar el actual.

Cada perfil congela las opciones necesarias para repetir una ejecución:

- métricas seleccionadas, detalle de datos, formatos, plantillas, nombres de archivo, unidades y forma de escritura;
- su propia carpeta de destino y subcarpeta, un endpoint de API o un Mac conectado cuando la plataforma lo admite;
- notas diarias, entradas individuales, resúmenes acumulados y otras opciones de salida compatibles con la plataforma.

La programación se vincula por separado a la identidad estable del perfil. Cambiar el perfil activo no redirige esa programación. Una ejecución usa la instantánea guardada en vez de tomar ajustes modificados de otro perfil.

## Ejecutar y programar con seguridad

- Cada perfil puede tener su propia programación recurrente, incluida la cadencia personalizada que ofrece la aplicación.
- Se siguen aplicando los derechos de cada plataforma: la asignación gratuita de Apple puede incluir acciones programadas, mientras que la programación en Android exige la compra vitalicia.
- Health.md avisa cuando varios perfiles podrían escribir las mismas rutas generadas en el mismo destino. El aviso no modifica en silencio ningún perfil ni programación.
- Detener o cancelar solo afecta al intento actual. Las fechas terminadas se conservan, las pendientes pueden reintentarse y la programación recurrente sigue activada.
- Si falta el perfil indicado, Health.md rechaza la ejecución de forma segura. Nunca usa como alternativa el perfil activo ni otro destino.

## Nombres, identificadores estables y automatización

El nombre visible es para las personas y puede cambiar. El identificador estable permite automatizaciones resistentes a cambios de nombre. Cópialo en **Ajustes → Perfiles de exportación → ID del perfil**.

- La app Atajos de Apple selecciona el perfil por su nombre visible; un parámetro de perfil vacío usa el perfil activo.
- Los broadcasts de Tasker y adb en Android pueden enviar el extra `PROFILE` con un identificador estable o un nombre. Usa el identificador si el flujo debe sobrevivir a un cambio de nombre.
- La CLI directa acepta `--profile PROFILE_ID` en tareas compatibles de archivos generados. El perfil aporta sus ajustes de salida congelados; el `--destination` obligatorio sigue seleccionando la carpeta existente en el ordenador.

Consulta la guía de automatización de cada plataforma antes de activar un flujo desatendido.

## Historial, recuperación y privacidad

Las filas de historial de ejecuciones programadas y automatizadas que usan perfiles registran el perfil utilizado. El historial también conserva una etiqueta respetuosa con la privacidad del destino real. Una ejecución manual desde la pestaña Exportar puede no adjuntar el nombre del perfil aunque use los ajustes del perfil activo. Renombrar un perfil, cambiar su destino o seleccionar otro después no reescribe el historial existente.

Un reintento iniciado desde el historial de exportaciones usa los ajustes y el destino configurados actualmente y crea una fila nueva con lo que realmente utilizó. No atribuye el reintento al perfil original. En cambio, recuperar o reanudar un intento programado pendiente conserva sus fechas, ajustes y destino exactos.

Los perfiles y sus programaciones son ajustes locales del dispositivo. No se sincronizan entre iPhone, iPad, Mac y Android. Vuelve a crear la configuración deseada en cada dispositivo y verifica el destino antes de activar la automatización.

## Relacionado

<div class="related">
  <a href="/es/docs/export/"><span>Exportar</span>Elige el detalle de datos, previsualiza la salida y exporta un intervalo.</a>
  <a href="/es/docs/scheduling/"><span>Programación</span>Comprende cadencias, recuperación y límites de tiempo de cada plataforma.</a>
  <a href="/es/docs/shortcuts/"><span>Atajos</span>Selecciona un perfil guardado en automatizaciones de Apple.</a>
  <a href="/es/docs/android/"><span>Automatización en Android</span>Usa acciones de Tasker y adb compatibles con perfiles.</a>
  <a href="/es/docs/cli-direct/"><span>CLI directa</span>Ejecuta los ajustes guardados del perfil en una carpeta explícita del ordenador.</a>
</div>
