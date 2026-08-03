---
title: Aplicación para Android
description: Configura Health.md for Android, exporta datos de Health Connect a Markdown, Obsidian Bases, JSON y CSV, elige carpetas mediante Storage Access Framework, programa exportaciones y automatiza con Tasker o adb.
---

<div class="docs-hero">
  <p class="docs-eyebrow">De Health Connect a archivos privados</p>
  <p>Health.md for Android lee Health Connect en el dispositivo y escribe Markdown, Obsidian Bases, JSON o CSV en las carpetas que elijas. No necesitas una cuenta de Health.md, una nube para tus datos de salud ni una suscripción.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Descargar en Google Play</a>
    <a class="docs-button-secondary" href="/es/docs/export/">Consultar la documentación sobre exportación</a>
  </div>
</div>

<div class="reference-stats">
<div><strong>106</strong><span>métricas seleccionables de Health Connect</span></div>
<div><strong>4</strong><span>formatos de exportación</span></div>
<div><strong>10</strong><span>acciones gratuitas de exportación manual</span></div>
<div><strong>0</strong><span>cuentas obligatorias en la nube de Health.md</span></div>
</div>

## Qué hace la aplicación para Android

Health.md for Android convierte Health Connect en un diario de salud basado en el almacenamiento local. Elige las métricas que te interesen, obtén una vista previa del resultado y exporta archivos ordenados a una carpeta local, una bóveda de Obsidian, una carpeta sincronizada o cualquier proveedor de documentos de Android que conceda permiso de escritura.

<div class="options">
  <div class="option"><strong>Health Connect como fuente</strong><p>Lee actividad, sueño, frecuencia cardíaca, signos vitales, medidas corporales, nutrición, entrenamientos y otras categorías mediante las API de Health Connect integradas en Android.</p></div>
  <div class="option"><strong>Resultado nativo para Obsidian</strong><p>Escribe notas diarias, YAML/frontmatter, notas compatibles con Obsidian Bases, entradas individuales y JSON compatible con el Health.md Obsidian plugin.</p></div>
  <div class="option"><strong>Almacenamiento nativo de Android</strong><p>Usa Storage Access Framework para que puedas elegir carpetas disponibles en el almacenamiento local, Obsidian, Google Drive, OneDrive, Syncthing u otro proveedor.</p></div>
</div>

## Requisitos

- Android 9 / API 28 o una versión posterior.
- Un dispositivo o emulador compatible con Health Connect.
- Datos de Health Connect procedentes de aplicaciones de Android, dispositivos vestibles o servicios que escriban en Health Connect.
- Una carpeta o un proveedor de documentos que permita escribir las exportaciones.

## Primera exportación

1. Instala Health.md desde Google Play.
2. Abre la configuración de **Health Connect** y concede acceso únicamente a las categorías que quieras que Health.md exporte.
3. Elige el destino de exportación con el selector de carpetas de Android.
4. Elige los formatos: Markdown, Obsidian Bases, JSON, CSV o cualquier combinación de ellos.
5. Selecciona las métricas y el intervalo de fechas.
6. Obtén una vista previa del resultado.
7. Toca el botón de exportación y verifica los archivos generados en tu carpeta o bóveda.

El plan gratuito incluye 10 acciones de exportación manual para que puedas probar los permisos, el acceso a la carpeta, los formatos y tu flujo de trabajo con Obsidian antes de desbloquear las exportaciones ilimitadas.

## Destinos en Android

Android no utiliza el destino de red local iPhone → Mac. En su lugar, usa Storage Access Framework de Android.

| Destino | Compatibilidad con Android |
|---|---|
| Carpeta local del dispositivo | Compatible mediante el selector de carpetas |
| Bóveda de Obsidian | Compatible cuando la carpeta de la bóveda está disponible en el selector de Android |
| Google Drive, OneDrive, Syncthing, Obsidian Sync y proveedores similares | Compatible cuando el proveedor ofrece carpetas con permiso de escritura |
| Destino de red local iPhone/Mac | Específico de las plataformas de Apple; Android no lo utiliza |

Si un proveedor no ofrece carpetas con permiso de escritura mediante el selector de Android, Health.md no puede escribir directamente en ellas de forma segura. Elige una carpeta de un proveedor que conceda acceso de escritura persistente, o exporta de forma local y sincroniza los archivos con la herramienta que prefieras.

## Formatos

La aplicación para Android tiene los mismos objetivos de archivos sencillos que la aplicación para Apple:

| Formato | Úsalo para |
|---|---|
| Markdown | Resúmenes diarios de salud legibles, plantillas y notas |
| Obsidian Bases | Notas centradas en el frontmatter que se pueden consultar en las vistas de base de datos de Obsidian |
| JSON | Cargas útiles diarias estructuradas para scripts, paneles, notebooks y el Health.md Obsidian plugin |
| CSV | Flujos de trabajo con hojas de cálculo y análisis |

Las exportaciones JSON de Android están diseñadas para ser compatibles con las visualizaciones de Health.md en Obsidian. Las exportaciones Markdown y Bases siguen el mismo flujo de trabajo centrado en el frontmatter que se explica en la [guía de formatos](/es/docs/format/).

## Programación y automatización

Las exportaciones programadas usan una alarma exacta de una sola ejecución cuando concedes acceso a Alarmas y recordatorios de Android, con una tarea persistente de WorkManager como respaldo. Sin ese acceso, WorkManager se convierte en el programador principal, por lo que la hora seleccionada es un objetivo y no una garantía estricta. Health.md registra el historial de exportaciones, puede recuperar las fechas programadas que no se ejecutaron y permite reintentar las ejecuciones fallidas.

Para Tasker, adb u otras herramientas de automatización, Health.md ofrece intents de difusión exclusivamente explícitos. Los clientes externos deben dirigirse directamente al componente receptor:

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

Ejemplos:

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

La automatización usa tus ajustes de exportación actuales, la carpeta y los formatos seleccionados, la selección de métricas, el cómputo de exportaciones gratuitas y el historial.

## Fuentes de salud

Health Connect es la ruta predeterminada para las exportaciones locales. La aplicación para Android también incluye un área de configuración de fuentes de salud para ecosistemas como Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar y WHOOP. Cuando estos ecosistemas escriben datos en Health Connect, Health.md puede exportar los registros resultantes de Health Connect. Las importaciones directas desde proveedores en la nube requieren la autorización del proveedor y pueden tener requisitos adicionales de configuración o disponibilidad.

Google Fit se excluye de forma intencional de los proveedores compatibles porque Health Connect es la capa de datos de salud preferida de Android.

## Precio y restauración

- La aplicación para Android incluye 10 acciones gratuitas de exportación manual.
- Las exportaciones ilimitadas y la automatización programada se desbloquean con una única compra vitalicia mediante Google Play Billing.
- No hay suscripción ni cargos recurrentes.
- Google Play muestra el precio local vigente antes de la compra.
- **Restaurar Compra** usa la cuenta de Google con la que compraste **Premium**.

## Modelo de privacidad

Health.md for Android prioriza el almacenamiento local:

- Los registros de Health Connect se leen en tu dispositivo Android.
- Las exportaciones se escriben directamente en las carpetas que elijas.
- Health.md no ofrece un servicio en la nube para datos de salud.
- Los ajustes y el historial de exportaciones permanecen en el dispositivo.
- Google Play gestiona la facturación.
- Las carpetas asociadas a un proveedor se sincronizan según las condiciones de ese proveedor.

Si quieres la configuración local más estricta, ejecuta exportaciones manuales a una carpeta local del dispositivo y deja desactivadas las exportaciones programadas y la sincronización con proveedores.

## Documentación relacionada

<div class="related">
  <a href="/es/docs/export/"><span>Exportación</span>Flujo de exportación manual, intervalos de fechas, vistas previas, historial y archivos de salida.</a>
  <a href="/es/docs/metrics/"><span>Métricas</span>Cómo funcionan la selección de métricas y las categorías en Health.md.</a>
  <a href="/es/docs/format/"><span>Formatos</span>Markdown, Bases, JSON, CSV, unidades, nombres de archivo y frontmatter.</a>
  <a href="/es/docs/visualizations-roadmap/"><span>Obsidian</span>Cómo el JSON y el Markdown exportados alimentan las visualizaciones de Health.md.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Última actualización: 2026-08-03</p>
