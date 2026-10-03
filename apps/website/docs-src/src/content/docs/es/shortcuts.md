---
title: "Atajos y App Intents"
description: "Usa siete acciones publicadas y dos acciones de contexto Mac del código en desarrollo desde Atajos, Siri y automatizaciones."
---

<div class="availability preview"><strong>Siete acciones publicadas · nueve en el código actual</strong><p>Las dos acciones de contexto Mac requieren versiones compatibles de iPhone y Mac. Confirma las notas de la versión exacta.</p></div>

## Acciones

- exportar ayer, una fecha, un rango o los últimos N días;
- obtener un resumen de salud o el último estado de exportación;
- activar o desactivar la programación;
- **Refresh Mac Health Context** (desarrollo): solicitar una actualización cifrada y duradera ligada a un perfil;
- **Get Mac Context Refresh Status** (desarrollo): consultar su estado y job ID.

Las cuatro acciones de exportación aceptan un **Perfil** opcional. Un nombre inexistente falla de forma segura. Las exportaciones ordinarias de Atajos escriben en la carpeta del iPhone; no cambian silenciosamente a API Endpoint o Connected Mac.

Permitir ejecución con el teléfono bloqueado no desbloquea HealthKit. Si los datos protegidos no están disponibles, Health.md conserva la solicitud y publica **Health Export Needs Attention**.

### Automatización matinal

1. Crea una automatización por hora.
2. Añade **Export Yesterday's Health Data**.
3. Añade **Get Last Export Status** y una notificación.

Ayer incluye el sueño cuya noche empezó ayer. Consulta [Fechas del sueño](/es/docs/sleep-date-attribution/).

<div class="related"><a href="/es/docs/export-profiles/"><span>Perfiles</span>Identidades estables para automatización.</a><a href="/es/docs/release-status/"><span>Compatibilidad</span>Comprueba versiones y calificación.</a></div>
