---
title: "Exportar"
description: "La pestaña Exportar es el espacio de trabajo principal. Muestra si HealthKit y tu bóveda están conectados, permite elegir un destino y ejecuta exportaciones puntuales para el intervalo de fechas que elijas."
---

<p>La pestaña Exportar organiza el proceso en tres pequeñas decisiones: confirmar que todo esté listo, elegir un destino y seleccionar el intervalo de fechas antes de obtener una vista previa o exportar.</p>

## Lee los indicadores de estado
<div class="options">
<div class="option"><strong>Indicador de Health</strong><p>Punto verde = HealthKit autorizado. Rojo = permiso no concedido. Tócalo para volver a abrir la hoja de permisos de iOS (solo funciona la primera vez por instalación; después, iOS no hace nada y debes corregirlo en Ajustes → Privacidad y seguridad → Salud).</p></div>
<div class="option"><strong>Indicador de la bóveda</strong><p>Punto verde = hay una carpeta de bóveda seleccionada. Tócalo para volver a elegirla o cambiarla. La etiqueta muestra el nombre de la carpeta.</p></div>
</div>
<p>La acción <em>Exportar</em> permanece desactivada hasta que HealthKit, el formato de salida y el destino seleccionado estén listos. Esto evita el error más habitual: intentar exportar sin un destino.</p>

## Elige un destino de exportación
<p>La tarjeta Destino de exportación determina adónde van los datos:</p>

<div class="options">
<div class="option"><strong>Carpeta local del iPhone</strong><p>Escribe directamente en la carpeta o bóveda de Obsidian que elegiste en este dispositivo.</p></div>
<div class="option"><strong>Mac conectado</strong><p>Envía los datos diarios capturados y una instantánea exacta de los ajustes a la aplicación cercana del Mac. El iPhone lee HealthKit; el Mac genera los formatos seleccionados y escribe los archivos.</p></div>
<div class="option"><strong>Endpoint de API</strong><p>Envía mediante POST un contenedor JSON directamente desde el iPhone a un endpoint HTTP(S) configurado por el usuario. <a href="/es/docs/api-endpoint/">Consulta Endpoint de API</a>.</p></div>
</div>

## Elige un intervalo de fechas
<p>Los intervalos predefinidos cubren los casos más habituales:</p>

<div class="options">
<div class="option"><strong>Hoy</strong><p>Exporta el día actual. Resulta útil para probar el formato de salida.</p></div>
<div class="option"><strong>Ayer</strong><p>La opción más segura para una exportación diaria porque el día ya ha terminado.</p></div>
<div class="option"><strong>Todo el período</strong><p>Completa el historial desde los primeros datos de HealthKit que Health.md pueda encontrar.</p></div>
<div class="option"><strong>Personalizado</strong><p>Elige las fechas inicial y final de un intervalo concreto.</p></div>
</div>

## Vista previa o Exportar
<div class="options">
<div class="option"><strong>Vista previa</strong><p>Muestra los archivos y el contenido que se generarán antes de escribir nada.</p></div>
<div class="option"><strong>Exportar</strong><p>Ejecuta la exportación, muestra el progreso en la pantalla principal y registra el resultado en el historial.</p></div>
</div>

## Qué hace realmente la «exportación»
<ol>
<li>Para cada día del intervalo, captura las proyecciones de resumen seleccionadas y, cuando está activado Lossless Health Records, sus registros de origen canónicos y los diagnósticos de consulta.</li>
<li>Aplica el formato elegido (Markdown, Bases, JSON o CSV) y la plantilla.</li>
<li>Escribe un archivo por día en <code>{vault}/{subfolder}/</code>, transfiere los archivos mediante el flujo del Mac conectado o envía mediante POST un contenedor JSON versionado a tu endpoint de API.</li>
<li>Si está activado <em>Individual Tracking</em>, genera para los destinos basados en archivos los archivos Markdown por entrada seleccionados a partir del archivo canónico.</li>
<li>Si está activado <em>Daily Note Injection</em>, combina los campos de resumen seleccionados con tus notas diarias.</li>
</ol>

<p>JSON y CSV pueden conservar los registros canónicos. Markdown y Bases mantienen la legibilidad y muestran diagnósticos de captura compactos en lugar de incrustar el archivo. Consulta la <a href="/es/docs/reference/">referencia completa de exportación</a> para conocer los esquemas exactos y las reglas de omisión.</p>

## Barra de pestañas

<p>Las cuatro pestañas de la parte inferior de la pantalla —Exportar, Programar, Sincronizar y Ajustes— abarcan toda la aplicación. Todo lo demás se encuentra uno o dos niveles dentro de Ajustes.</p>

<div class="callout">
<strong>Comportamiento del desbloqueo.</strong>
<p style="margin-top:6px;">Full Access desbloquea las exportaciones ilimitadas, las exportaciones programadas, los destinos del Mac y Shortcuts. <a href="/es/docs/paywall/">Consulta la página sobre el muro de pago</a> para obtener más información.</p>
</div>

## Contenido relacionado

<div class="related">
  <a href="/es/docs/scheduling/"><span>Uso diario</span>Programación: automatiza el proceso para no tener que volver a tocar Exportar.</a>
  <a href="/es/docs/api-endpoint/"><span>Integración</span>Endpoint de API: envía el JSON seleccionado directamente a tu propio servicio.</a>
  <a href="/es/docs/format/"><span>Personalización</span>Personalización del formato: cambia el aspecto de cada archivo.</a>
  <a href="/es/docs/shortcuts/"><span>Más opciones</span>Shortcuts: inicia exportaciones desde Siri, automatizaciones u otras aplicaciones.</a>
  <a href="/es/docs/reference/"><span>Referencia</span>Referencia de exportación: esquemas, registros canónicos, diagnósticos y ejemplos generados.</a>
</div>
