---
title: Funciones por plataforma
description: Qué ofrece Health.md en iPhone, iPad, Mac, Android, Wear OS y la CLI — funciones compartidas y las diferencias honestas entre plataformas.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Panorama de plataformas</p>
  <p>Qué hace Health.md en iPhone, iPad, Mac, Android, Wear OS y la CLI — compartido donde las plataformas lo permiten, honesto donde difieren.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">iPhone y Mac</a>
    <a class="docs-button-secondary" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Android</a>
  </div>
</div>

**Las entradas de Wear OS son funciones previstas, no incluidas en la versión actual de Google Play.**

Leyenda: ✓ disponible · ◐ disponible con diferencias de plataforma indicadas en la fila · △ planificado o en pruebas de calidad · ? no se afirma su disponibilidad · — no disponible en esa plataforma.

La CLI no es una columna aparte de plataforma de datos de salud: las funciones de la CLI aparecen en las filas de automatización y conservan la semántica de su origen en iPhone o Android.

## Configuración y permisos

| Función | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Permisos de datos de salud (elige exactamente qué leer) | ✓ tipos de Apple Health | ◐ lee a través del iPhone emparejado / destino Mac | ✓ categorías de Health Connect | — |
| Elegir destino de exportación | ✓ bóveda de Obsidian, iCloud Drive, Archivos | ✓ carpetas locales | ✓ cualquier proveedor de carpetas de Android (Drive, OneDrive, Syncthing, Obsidian Sync…) | — |
| Configuración inicial con vista previa de ejemplo | ✓ | ✓ | ✓ | — |
| Share My Setup (mover preferencias entre dispositivos) | △ en QA | △ en QA | △ en QA | — |

## Lectura y exportación

| Función | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Exportaciones diarias a Markdown, Obsidian Bases, JSON, CSV | ✓ | ✓ (los archivos llegan desde el iPhone) | ✓ | — |
| 225+ métricas de Apple Health / 106 métricas de Health Connect | ✓ | ✓ | ✓ | — |
| Vista previa antes de escribir | ✓ | ✓ | ✓ | — |
| Perfiles de exportación guardados con ajustes independientes | ✓ se administran en el iPhone; ? administración en iPad no afirmada | ? administración no afirmada | ✓ se administran en Android | — |
| Resúmenes semanales, mensuales y anuales | ✓ | ✓ | △ planificado; requiere un perfil de esquema de Android con revisión separada (las v4/v5 actuales no cambian) | — |
| Historial de exportación y reintento | ✓ | ✓ | ✓ | — |
| Detener o cancelar la ejecución activa sin desactivar su programación | ✓ las fechas completadas se conservan; las fechas sin resolver se pueden reintentar | ✓ | ✓ las fechas completadas se conservan; las fechas sin resolver se pueden reintentar | — |
| Archivo ZIP de una sola ejecución | ✓ | ✓ | — | — |
| Detalle de datos de resumen | ✓ | ✓ | ✓ | — |
| Serie temporal detallada para métricas seleccionadas | ✓ | ✓ | ✓ | — |
| Archivo canónico de registros de origen de Registros de salud sin pérdidas | ✓ `healthmd.healthkit_records` | ✓ | — exclusivo de Apple; consulta las instantáneas de API sin procesar | — |
| Exportación de instantáneas de API sin procesar (JSON/NDJSON inmutable) | — | — | ✓ Health Connect + Fitbit, Oura, WHOOP, Withings | — |

## Datos avanzados

| Función | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Seguimiento de entradas individuales (entrenamientos, fases de sueño, signos vitales) | ✓ | ✓ | ✓ | — |
| Detalles del entrenamiento con gráficas completas y rutas donde se ofrecen | ✓ | ✓ | ✓ | — |
| Exportación de estado de ánimo / State of Mind | ✓ | ✓ | — (sin equivalente en Health Connect) | — |
| Eventos de dosis de medicamentos | ✓ | ✓ | — (sin equivalente en Health Connect) | — |
| Lecturas de presión arterial, glucosa, oxígeno y temperatura | ✓ | ✓ | ✓ | — |
| Datos de proveedores externos | ◐ sección WHOOP en la exportación (beta) | ◐ | ✓ instantáneas sin procesar nativas del proveedor | — |

Algunos datos deliberadamente **no se tratan como equivalentes** entre plataformas: la variabilidad de la frecuencia cardíaca es SDNN en Apple y RMSSD en Android y WHOOP — Health.md las mantiene como métricas distintas en lugar de mezclarlas. La temperatura de muñeca del Apple Watch y la temperatura de la piel de Health Connect también se mantienen separadas.

## Automatizar e integrar

| Función | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Exportaciones recurrentes programadas | ✓ notificaciones + respaldo de APNs | ✓ | ✓ WorkManager (+ alarma exacta opcional), recuperación tras reinicio | — |
| Automatización del sistema | ✓ Atajos / Siri / App Intents | — | ✓ Tasker, adb, intents de difusión explícitos | — |
| Enviar exportaciones a tu propio endpoint de API HTTP(S) | ✓ | — | ✓ con almacenamiento cifrado de encabezados | — |
| Emparejamiento con la CLI independiente (`healthmd`) | ✓ servicio directo en primer plano | ✓ incluida + independiente | ✓ emparejamiento con código de 20 dígitos | — |
| Activación por solicitudes directas de la CLI | ✓ espera limitada + APNs opcional | ✓ iniciador de la CLI | ◐ espera limitada; FCM planificado | — |
| Servidor MCP para agentes de IA | ◐ se incluye a través del Mac; el MCP directo portátil y tipado es exclusivo del iPhone | ✓ incluido como `healthmd-mcp` | — MCP directo tipado no compatible | — |

## Dispositivos y superficies de un vistazo

| Función | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Widgets de pantalla de inicio | ✓ resumen, anillos de actividad, rango cardíaco, sueño | — | ✓ resumen, actividad, rango cardíaco, sueño (los pasos sustituyen a las horas de pie) | — |
| Progreso de exportación en Actividad en vivo | ✓ | — | — | — |
| Superficies del reloj | ✓ app de reloj + 10 complicaciones | — | — | △ previsto para 1.10.0 |
| Mac como destino de exportación (transferencia local cifrada) | ✓ el iPhone envía | ✓ recibe | — | — |

## Compra y privacidad

| Función | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Nivel gratuito | ✓ 10 acciones de exportación manuales o programadas | — | ✓ 10 acciones de exportación manuales | — |
| Desbloqueo | ✓ compra vitalicia única (individual / familiar) | ◐ mismo desbloqueo de Apple | ✓ compra vitalicia única, con programación incluida | — |
| Privacidad con procesamiento local | ✓ sin nube de datos de salud de Health.md | ✓ | ✓ | △ previsto |
| Informe para el médico (un PDF para las citas) | ✓ | — | ✓ | — |

Health.md no opera una nube de datos de salud. Los datos de salud pueden existir en destinos que elijas, en contexto local cifrado y en un estado de transferencia privada acotado. Cada carpeta, Mac, endpoint de API o destino de la CLI se configura de forma explícita. Los perfiles y las programaciones permanecen en el dispositivo donde se crearon. Consulta los [perfiles de exportación](/es/docs/export-profiles/), la [guía de Android](/es/docs/android/) y la [guía de exportación de iPhone](/es/docs/export/) para el flujo de trabajo de cada plataforma.
