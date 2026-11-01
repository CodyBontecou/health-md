---
title: "Exportar"
description: "Exporta datos de Apple Health ahora o según una programación. Comprueba que todo esté listo en Archivo, elige un rango en Exportar ahora y define el destino de cada automatización."
---

<p>En el iPhone, Health.md tiene tres pestañas, <strong>Archivo</strong>, <strong>Automatizaciones</strong> y <strong>Ajustes</strong>, además de un botón redondo <strong>Exportar ahora</strong>. En el iPad, las pestañas pasan a una barra lateral.</p>

## Comprueba que todo esté listo en Archivo
<p>El calendario de <strong>Archivo</strong> muestra qué fechas de salud ha cubierto cada automatización. Cuando algo bloquea las exportaciones, la tarjeta <strong>Requiere atención</strong> de arriba lo indica:</p>
<div class="options">
<div class="option"><strong>Apple Health</strong><p>Health.md muestra el estado de configuración de la app, no un acceso de lectura confirmado a cada categoría. HealthKit no revela los permisos de lectura denegados. Revisa las categorías en Apple Health. Un resultado vacío puede significar acceso denegado o que no hay datos. <a href="/es/docs/troubleshooting/">Soluciona datos que faltan</a>.</p></div>
<div class="option"><strong>Carpeta</strong><p>Elige la carpeta, o vuelve a elegirla, en <strong>Ajustes → Carpeta</strong>. Si iOS pierde el acceso tras mover una carpeta, Health.md te pide que la elijas de nuevo; no se borra nada.</p></div>
</div>

## Elige dónde exporta una automatización
<p>Cada automatización tiene su propio destino. Abre <strong>Automatizaciones</strong>, elige la automatización y luego <strong>Salida</strong>:</p>

<div class="options">
<div class="option"><strong>Carpeta local</strong><p>Escribe directamente en la carpeta o bóveda de Obsidian que elegiste en este dispositivo.</p></div>
<div class="option"><strong>Mac conectado</strong><p>Envía los datos diarios capturados y una instantánea exacta de los ajustes a la app de Mac cercana. El iPhone lee HealthKit; el Mac genera los formatos elegidos y escribe los archivos.</p></div>
<div class="option"><strong>Endpoint de API</strong><p>Envía por POST un sobre JSON directamente desde el iPhone a un endpoint HTTP(S) que configures. <a href="/es/docs/api-endpoint/">Consulta Endpoint de API</a>.</p></div>
<div class="option"><strong>Puerta de enlace de Agent Data</strong><p>Sube cada archivo exportado, sin cambios, al endpoint de ingesta de tu puerta de enlace.</p></div>
</div>

## Elige un rango en Exportar ahora
<p>Toca <strong>Exportar ahora</strong>, elige la automatización si tienes varias y luego un rango:</p>

<div class="options">
<div class="option"><strong>Ayer</strong><p>La opción más segura para exportaciones diarias, porque el día ya terminó.</p></div>
<div class="option"><strong>7 días / 30 días</strong><p>La última semana o el último mes, hasta ayer. Con 30 días o más, Health.md te pide confirmación antes.</p></div>
<div class="option"><strong>Personalizado</strong><p>Elige fechas de inicio y fin para un rango concreto.</p></div>
</div>
<p><strong>Se escribirá</strong> muestra el destino y aproximadamente cuántos archivos y días cubre la exportación. <strong>Solo resumen del rango de fechas</strong> escribe un único archivo de resumen en lugar de archivos diarios. Hoy y Todo el historial siguen disponibles en <strong>Automatizaciones → Todos los ajustes de exportación</strong>.</p>

## Vista previa o exportación
<div class="options">
<div class="option"><strong>Vista previa</strong><p>Muestra los archivos y contenidos que se generarán antes de escribir nada.</p></div>
<div class="option"><strong>Exportar</strong><p>Ejecuta la exportación, muestra el progreso sobre la barra de pestañas con un botón Cancelar y registra el resultado en el historial y en el calendario de Archivo.</p></div>
</div>

## Elija el nivel de detalle de datos

<div class="options">
 <div class="option"> <strong> Resumen </strong> <p> Totales diarios compactos y resúmenes para lectura, notas y paneles. </p> </div>
 <div class="option"> <strong> Serie de tiempo detallada </strong> <p> Intervalos y muestras con marca de tiempo seleccionadas. Este nivel está disponible tanto en Apple como en Android cuando la métrica elegida expone los detalles adecuados. </p> </div>
 <div class="option"> <strong> Registros médicos sin pérdidas </strong> <p> El archivo canónico de registros fuente HealthKit . Este nivel es sólo para Apple. Android no convierte los registros Health Connect en un archivo HealthKit . </p> </div>
 </div>

## Qué significa realmente "exportar"
 <ol>
 <li> Para cada día del rango, capture proyecciones resumidas seleccionadas. Agregue muestras compatibles para series temporales detalladas. Y, para registros médicos sin pérdida, agregue registros de origen canónicos y consulte diagnósticos. </li>
 <li> Aplique el formato elegido ( Markdown , Bases, JSON o CSV) y la plantilla. </li>
 <li> Escriba un archivo por día en <code>{vault}/{subfolder}/</code> , transfiera archivos a través del flujo de trabajo de Mac conectado o PUBLICE un sobre JSON versionado en su punto final API. </li>
 <li> Si <em> Seguimiento individual </em> está activado, deriva archivos Markdown seleccionados por entrada del archivo canónico para destinos basados ​​en archivos. </li>
 <li> Si <em> Inyección de notas diarias </em> está activado, combine los campos de resumen seleccionados en sus notas diarias. </li>
 </ol>

<p> JSON y CSV pueden conservar registros canónicos. Markdown y Bases permanecen legibles y exponen diagnósticos de captura compactos en lugar de incrustar el archivo. Consulte la referencia de exportación completa <a href="/es/docs/reference/"> </a> para conocer los esquemas exactos y las reglas de omisión. </p>

## Detener, cancelar y volver a intentar

Detener o cancelar finaliza sólo el intento actual. Los archivos y fechas ya completados permanecen completos, mientras que las fechas no resueltas permanecen disponibles para volver a intentarlo. Cancelar un intento programado no desactiva su programación recurrente.

## Perfiles e historial confiable

Un perfil guardado fija sus ajustes y su destino durante la ejecución. Las filas del historial de exportaciones programadas y de automatización que conocen el perfil conservan el perfil usado, y el historial guarda una etiqueta respetuosa con la privacidad del destino que se usó realmente. Una fila de exportación manual puede omitir el nombre del perfil. Los cambios posteriores de nombre o de destino no reescriben el historial existente. Si falta un perfil al que se hace referencia, la operación falla sin usar otros ajustes. Consulta [Perfiles de exportación](/es/docs/export-profiles/).

<div class="callout">
 <strong> Comportamiento de desbloqueo. </strong>
 <p style="margin-top:6px;"> Las versiones de teléfono iPhone / iPad y Google Play habilitadas para suscripción requieren prueba activa, suscripción, de por vida o acceso permanente preservado para exportaciones y programación. No queda ningún subsidio de libre exportación local. El complemento Mac y la compilación de acceso incluido F-Droid conservan sus excepciones documentadas. <a href="/es/docs/paywall/"> Consulte la página Paywall </a> para obtener detalles de compra de Apple. </p>
 </div>

## Relacionado

<div class="related">
 <a href="/es/docs/export-profiles/"> <span> Configuraciones repetibles </span> Exporte perfiles, guarde configuraciones independientes, destinos, horarios e ID de automatización estables. </a>
 <a href="/es/docs/scheduling/"> <span> Uso diario </span> Programación, automatice esto para que nunca vuelva a tocar Exportar. </a>
 <a href="/es/docs/api-endpoint/"> <span> Integre el punto final API </span> y envíe el JSON seleccionado directamente a su propio servicio. </a>
 <a href="/es/docs/format/"> <span> Personalizar </span> Personalización de formato, cambia el aspecto de cada archivo. </a>
 <a href="/es/docs/shortcuts/"> <span> Enciende </span> Shortcuts , activa exportaciones desde Siri , automatizaciones u otras aplicaciones. </a>
 <a href="/es/docs/reference/"> <span> Referencia </span> Referencia de exportación, esquemas, registros canónicos, diagnósticos y ejemplos generados. </a>
 </div>
