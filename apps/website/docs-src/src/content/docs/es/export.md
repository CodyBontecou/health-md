---
title: "Exportar"
description: "Utilice la pestaña Exportar para verificar HealthKit y las conexiones de la bóveda. Seleccione un destino y exporte un rango de fechas."
---

<p> La pestaña Exportar está organizada en tres pequeñas decisiones: confirmar la preparación, elegir un destino y luego elegir el rango de fechas antes de obtener una vista previa o exportar. </p>

## Leer las insignias de estado
 <div class="options">
 <div class="option"> <strong> Insignia de salud </strong> <p> Un punto verde significa que HealthKit está autorizado. Un punto rojo significa que no se concede el acceso. Toque para volver a intentar la hoja de permisos de iOS. La hoja aparece sólo una vez por instalación. Después de eso, abra Configuración → Privacidad y privacidad. Seguridad → Salud. </p> </div>
 <div class="option"> <strong> Insignia de bóveda </strong> <p> Punto verde = se selecciona una carpeta de bóveda. Toque para volver a seleccionar o cambiar la bóveda. La etiqueta muestra el nombre de la carpeta. </p> </div>
 </div>
 <p> La acción <em> Exportar </em> permanece deshabilitada hasta que HealthKit , el formato de salida y el destino seleccionado estén listos. Esto evita el modo de error más común: intentar exportar sin destino. </p>

## Elija un destino de exportación
 <p> La tarjeta Destino de exportación decide dónde van los datos: </p>

<div class="options">
 <div class="option"> <strong> Local iPhone Carpeta </strong> <p> Escribe directamente en la carpeta o Obsidian bóveda que eligió en este dispositivo. </p> </div>
 <div class="option"> <strong> Mac conectado </strong> <p> Envía datos diarios capturados y una instantánea de la configuración exacta a la aplicación Mac cercana. El iPhone lee HealthKit . La Mac procesa los formatos seleccionados y escribe los archivos. </p> </div>
 <div class="option"> <strong> Punto final API </strong> <p> Publica un sobre JSON directamente desde iPhone a un punto final HTTP(S) configurado por el usuario. <a href="/es/docs/api-endpoint/"> Consulte el punto final API </a> . </p> </div>
 </div>

## Elija un rango de fechas
 <p> Los ajustes preestablecidos de fecha cubren las rutas comunes: </p>

<div class="options">
 <div class="option"> <strong> Hoy </strong> <p> Exporta el día actual. Útil para probar el formato de salida. </p> </div>
 <div class="option"> <strong> Ayer </strong> <p> La opción de exportación diaria más segura porque el día está completo. </p> </div>
 <div class="option"> <strong> Todos los tiempos </strong> <p> Rellene desde los primeros HealthKit datos Health.md pueda encontrar. </p> </div>
 <div class="option"> <strong> Personalizado </strong> <p> Elija fechas de inicio y finalización para un rango específico. </p> </div>
 </div>

## Vista previa o exportación
 <div class="options">
 <div class="option"> <strong> Vista previa </strong> <p> Muestra los archivos y contenidos que se generarán antes de escribir algo. </p> </div>
 <div class="option"> <strong> Exportar </strong> <p> Ejecuta la exportación, muestra el progreso en la pantalla principal y registra el resultado en el historial. </p> </div>
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

Un perfil guardado congela su configuración y destino de la ejecución. Las filas del historial de automatización y programación que tienen en cuenta el perfil mantienen el perfil en tiempo de ejecución, mientras que el historial conserva una etiqueta de seguridad de privacidad para el destino realmente utilizado. Una fila de la pestaña Exportar manual puede omitir el nombre del perfil. Los cambios de nombre y destino posteriores no reescriben el historial existente. Las referencias de perfil que faltan fallan al cerrarse en lugar de retroceder. Consulte [Exportar perfiles](/es/docs/export-profiles/).

## Barra de pestañas

<p> Las cuatro pestañas en la parte inferior de la pantalla, Exportar, Programar, Sincronizar y Configuración, cubren toda la superficie de la aplicación. Todo lo demás vive una o dos capas en el interior de Configuración. </p>

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
