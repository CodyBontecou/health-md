---
title: "Atajos y App Intents"
description: "Usa siete acciones de Health.md desde Atajos y Siri. Las acciones de actualización del contexto Mac son propuestas, no están disponibles."
---

<div class="availability preview"><strong>Siete acciones registradas en el código</strong><p>Refresh Mac Health Context y Get Mac Context Refresh Status son propuestas, no están implementadas ni disponibles en desarrollo. Sigue la <a href="https://github.com/CodyBontecou/health-md/issues/173">incidencia #173</a>; su disponibilidad requiere implementación, calificación y notas de una versión Apple exacta.</p></div>

## Acciones

- exportar ayer, una fecha, un rango o los últimos N días;
- obtener un resumen de salud o el último estado de exportación;
- activar o desactivar la programación.

### Acciones de contexto Mac propuestas (no disponibles)

La acción solicitada **Refresh Mac Health Context** usaría un alcance explícito de perfil y fechas, dispositivos compatibles autenticados y adquisición duradera de contexto sin archivos de exportación ni consumo de la cuota de exportación de archivos. **Get Mac Context Refresh Status** informaría del estado pendiente/completado/fallido con una identidad de trabajo recuperable. Son requisitos, no nombres de acciones, parámetros o resultados admitidos en la aplicación actual.

La actualización mediante MCP desde el ordenador no satisface una automatización personal de iOS. No uses Atajos de exportación ordinarios como sustituto: conservan la semántica de carpeta del iPhone. Ninguna automatización puede prometer despertar un Mac en reposo ni eludir los datos protegidos de HealthKit. Antes de calificar esta función aún se requiere verificar la automatización en un iPhone físico tras despertar.

Las cuatro acciones de exportación aceptan un **Perfil** opcional. Un nombre inexistente falla de forma segura. Las exportaciones ordinarias de Atajos escriben en la carpeta del iPhone; no cambian silenciosamente a API Endpoint o Connected Mac.

Permitir ejecución con el teléfono bloqueado no desbloquea HealthKit. Si los datos protegidos no están disponibles, Health.md conserva la solicitud y publica **Health Export Needs Attention**.

### Automatización matinal

1. Crea una automatización por hora.
2. Añade **Export Yesterday's Health Data**.
3. Añade **Get Last Export Status** y una notificación.

Ayer incluye el sueño cuya noche empezó ayer. Consulta [Fechas del sueño](/es/docs/sleep-date-attribution/).

<div class="related"><a href="/es/docs/export-profiles/"><span>Perfiles</span>Identidades estables para automatización.</a><a href="/es/docs/release-status/"><span>Compatibilidad</span>Comprueba versiones y calificación.</a></div>
