---
title: "Endpoint de API"
description: "Envía el JSON de Apple Health seleccionado directamente desde el iPhone a tu propio punto final HTTP(S)."
---

<p>API Endpoint es un destino de exportación para quienes quieran enviar los datos de Health.md a su propio servidor, webhook, base de datos, panel o automatización. El iPhone sigue leyendo Apple Health; en lugar de escribir archivos, envía mediante POST datos JSON al endpoint que configures.</p>

<div class="callout">
<strong>Recordatorio de privacidad.</strong>
<p style="margin-top:6px;">Este destino envía deliberadamente los datos de salud seleccionados a la URL que introduzcas. Usa un endpoint que controles o en el que confíes, opta por HTTPS y limita las métricas a las que tu servicio necesite realmente.</p>
</div>

## Configurar el destino

<ol>
<li>Abre Health.md en el iPhone.</li>
<li>Ve a <strong>Exportar</strong>.</li>
<li>En <strong>Destino de exportación</strong>, elige <strong>API Endpoint</strong>.</li>
<li>Introduce una URL como <code>https://api.example.com/healthmd/ingest</code>.</li>
<li>Opcional: introduce un token de portador. Health.md lo almacena en Keychain.</li>
<li>Toca <strong>Done</strong>, elige el intervalo de fechas y las métricas y, después, toca <strong>Export</strong>.</li>
</ol>

<p>Si introduces un token sin prefijo, Health.md lo envía como <code>Authorization: Bearer &lt;token&gt;</code>. Si el valor ya comienza con <code>Bearer </code> o <code>Basic </code>, Health.md lo envía tal como lo introdujiste.</p>

## Estructura de la carga útil

<p>Health.md envía una solicitud POST por cada acción de exportación. El cuerpo es un contenedor <code>healthmd.api_export</code> con una versión independiente que contiene registros diarios <code>healthmd.health_data</code> de esquema público v8. El contenedor de API v1 incluye los registros diarios; v2 también puede incluir datos auxiliares del proveedor sin cambiar el esquema de registro diario.</p>

<div class="options">
<div class="option"><strong><code>records</code></strong><p>Objetos completos del esquema diario v8 retenidos para el rango solicitado, incluidos los registros completamente vacíos cuyo manifiesto de consulta sirve de evidencia.</p></div>
<div class="option"><strong><code>failed_date_details</code></strong><p>Fechas que fallaron antes de que se pudiera conservar un documento diario.</p></div>
<div class="option"><strong><code>daily_record_schema_version</code></strong><p>La versión del esquema diario dentro de <code>records</code>. Avanza independientemente de la versión del sobre API.</p></div>
<div class="option"><strong>Datos auxiliares del proveedor</strong><p>Registros externos condicionales de v2, con su propio esquema y sus propias reglas de identidad, cuando hay un proveedor conectado habilitado.</p></div>
</div>

<p>Consulta el <a href="/docs/reference/generated/automation/api-export-v1.json">contenedor de API v1</a> completo y el <a href="/docs/reference/generated/automation/api-export-v2-provider-sidecar.json">contenedor de API v2 con datos auxiliares del proveedor</a>, ambos generados en producción. El contrato de <a href="/es/docs/reference/api-and-cli/">API y CLI</a> documenta cada campo, límite entre versiones y regla de aceptación.</p>

## Requisitos del endpoint

<div class="options">
<div class="option"><strong>Método</strong><p>Aceptar <code>POST</code>.</p></div>
<div class="option"><strong>Tipo de contenido</strong><p>Aceptar <code>application/json</code>.</p></div>
<div class="option"><strong>Éxito</strong><p>Devuelve cualquier estado <code>2xx</code> después de aceptar la carga útil de forma segura.</p></div>
<div class="option"><strong>Errores</strong><p>Devuelve <code>4xx</code> o <code>5xx</code> para las solicitudes rechazadas. Health.md muestra una breve vista previa de la respuesta cuando esté disponible.</p></div>
</div>

<p>Para lograr una ingesta fiable, configura el endpoint para que sea idempotente por fecha. Un usuario puede repetir el mismo rango de exportación después de cambiar las métricas o corregir un error del servidor.</p>

## Consejos

<ul>
<li>Haz una prueba con un solo día antes de cargar un período histórico largo.</li>
<li>Mantén habilitados los registros de salud sin pérdidas cuando sea importante conservar íntegramente la fuente; reduce el intervalo de fechas para rutas densas, documentos clínicos, ECG o archivos adjuntos.</li>
<li>Valida el token en el servidor antes de almacenar cualquier carga útil.</li>
<li>Usa <code>records[].date</code> como clave principal de cada día.</li>
<li>Devuelve un cuerpo de error conciso; Health.md solo muestra una breve vista previa.</li>
</ul>

## Solución de problemas

| Problema | Suele significar | Solución |
|---|---|---|
| El objetivo de API no está listo | La URL está vacía o no es válida | Vuelve a abrir la configuración de API Endpoint e ingrese una URL HTTP(S) válida. |
| HTTP 401 o 403 | Falta el token o se ha rechazado | Actualiza las reglas de autenticación del token o del servidor. |
| HTTP 404 | La ruta de la URL es incorrecta | Comprueba la ruta en su servidor. |
| HTTP 413 | La carga útil es demasiado grande | Exporta menos días; usa una salida solo de resumen únicamente cuando el receptor no necesite registros de origen canónicos. |
| Faltan algunas fechas | No hay datos de HealthKit habilitados para esas fechas | Comprueba <code>failed_date_details</code> y su selección de métricas. |

## Relacionado

<div class="related">
<a href="/es/docs/export/"><span>Fuente</span>Exportar: elija objetivos, rangos de fechas y ejecute exportaciones manuales.</a>
<a href="/es/docs/reference/api-and-cli/"><span>Esquema</span>Referencia de API y CLI: sobres exactos, versiones, comportamiento de falla y ejemplos generados.</a>
<a href="/es/docs/format/"><span>Salida</span>Personalización de formato: JSON, CSV, Markdown, unidades y campos.</a>
</div>
