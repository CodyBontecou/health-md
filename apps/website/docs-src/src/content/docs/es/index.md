---
title: Empieza a usar Health.md.
description: Exporta datos de Apple Health o Health Connect, conecta la herramienta auxiliar firmada para Mac a un agente local y desarrolla con los contratos versionados de Health.md.
---

<div class="docs-hero" data-strand-stage>
  <canvas class="docs-dna" data-three-strand aria-hidden="true"></canvas>
  <div class="docs-hero-copy">
    <p class="docs-eyebrow">Ya disponible · herramienta auxiliar firmada para Mac</p>
    <p>Exporta los datos de salud de tu teléfono, conecta un agente local mediante las herramientas auxiliares firmadas para Mac o desarrolla con contratos versionados. Las lecturas de HealthKit permanecen en el iPhone y las de Health Connect, en Android.</p>
    <div class="docs-command" aria-label="Comando incluido para comprobar si Health.md está listo"><span aria-hidden="true">$</span> "/Applications/Health.md.app/Contents/Helpers/healthmd" doctor</div>
    <p class="docs-command-note">¿Lo instalaste en otra ubicación? Copia la ruta de la herramienta auxiliar incluida desde <strong>Health.md for Mac → CLI</strong>.</p>
    <div class="docs-actions">
      <a class="docs-button" href="/es/docs/iphone-first-export/">Primera exportación desde el iPhone</a>
      <a class="docs-button-secondary" href="/es/docs/configuration/">Conectar un agente</a>
      <a class="docs-button-secondary" href="/es/docs/reference/">Explorar los contratos (en inglés)</a>
    </div>
  </div>
</div>

<div class="agent-path" aria-label="Elige qué quieres hacer con Health.md">
  <a href="/es/docs/iphone-first-export/"><span>01 · Exportar</span><strong>Empieza en el iPhone</strong>Autoriza Apple Health, elige una carpeta, obtén una vista previa del resultado y ejecuta tu primera exportación.</a>
  <a href="/es/docs/configuration/"><span>02 · Consultar</span><strong>Conecta un agente local</strong>Usa la herramienta auxiliar MCP firmada para Mac con Codex, Claude u otro cliente stdio.</a>
  <a href="/es/docs/reference/"><span>03 · Desarrollar</span><strong>Usa contratos estables</strong>Integra esquemas, registros, evidencias, fixtures generados y estructuras exactas de solicitud y respuesta (documentación en inglés).</a>
</div>

<div class="reference-stats">
<div><strong>21</strong><span>herramientas MCP incluidas para Mac</span></div>
<div><strong>4</strong><span>formatos de exportación</span></div>
<div><strong>v8</strong><span>esquema público de exportación de Apple</span></div>
<div><strong>0</strong><span>transferencias obligatorias a través de la nube de Health.md</span></div>
</div>

<p class="docs-section-kicker">Ya disponible · macOS</p>

## Inicio rápido con un agente local en cinco minutos

Abre Health.md en el Mac y, después, Health.md en el iPhone emparejado; espera a que se establezca la conexión. La herramienta auxiliar incluida comprueba que todo esté listo sin devolver valores de salud, enumera las métricas de sueño y ejecuta una consulta de un día:

```bash
HMD="/Applications/Health.md.app/Contents/Helpers/healthmd"
"$HMD" doctor
"$HMD" metrics list --category Sleep
"$HMD" query --category Sleep --yesterday
```

Cuando todo está listo, el resultado de `doctor` usa el esquema `healthmd.cli_doctor` e incluye los siguientes pasos si la configuración está incompleta. Para Codex o Claude, continúa con [Configura tu agente](/es/docs/configuration/) y dirige el cliente a la herramienta auxiliar firmada independiente `healthmd-mcp`, incluida en la aplicación.

<p class="docs-section-kicker">Elige según tu objetivo</p>

## Configurar y conectar

<div class="related">
  <a href="/es/docs/configuration/"><span>Ya disponible · Mac</span>Configuración: conecta Codex, Claude u otro cliente stdio a la herramienta auxiliar MCP firmada.</a>
  <a href="/es/docs/mcp/"><span>Ya disponible · Mac</span>Servidor MCP y App: descubre las 21 herramientas incluidas, genera visualizaciones privadas y conoce la vista previa portátil.</a>
  <a href="/es/docs/cli/"><span>Ya disponible · Mac</span>Health.md CLI: instala la herramienta auxiliar incluida, comprueba la disponibilidad, consulta datos y distingue la vista previa portátil.</a>
  <a href="/es/docs/agents/"><span>Arquitectura</span>Contexto del agente: conoce el alcance de las solicitudes, la confianza local, el contexto cifrado, la evidencia, la retención y la privacidad.</a>
</div>

<p class="docs-section-kicker">Operaciones habituales</p>

## Consultar, extraer y automatizar

<div class="related">
  <a href="/es/docs/agent-queries/"><span>Consultas tipadas</span>Consulta métricas, sesiones de sueño, entrenamientos, comparaciones, cobertura y evidencia factual.</a>
  <a href="/es/docs/cli-direct/"><span>Vista previa · CLI portátil</span>Acceso directo al teléfono: revisa el emparejamiento mediante IP manual o Tailscale y la matriz actual de compatibilidad no cualificada de iPhone y Android.</a>
  <a href="/es/docs/cli-extract/"><span>Datos de origen</span>Extracción canónica: obtén días seleccionados con el esquema v8, registros de origen, proyecciones o JSONL.</a>
  <a href="/es/docs/cli-jobs/"><span>Ejecuciones fiables</span>Tareas persistentes: gestiona de forma segura los tiempos de espera, los resultados inciertos, la reanudación, la cancelación y los resultados parciales.</a>
  <a href="/es/docs/agent-api/"><span>Bajo nivel</span>API de loopback: usa las rutas exactas de consulta, evidencia, cursor, actualización y tareas persistentes.</a>
  <a href="/es/docs/reference/integration-recipes/"><span>Patrones</span>Recetas de integración: analiza y valida los resultados de Health.md sin debilitar sus contratos (en inglés).</a>
</div>

<p class="docs-section-kicker">Interfaces estables</p>

## Contratos y estructuras de datos

<div class="related">
  <a href="/es/docs/reference/"><span>Mapa de contratos</span>Referencia de exportación: consulta esquemas, métricas, formatos, registros y fixtures de interoperabilidad (en inglés).</a>
  <a href="/es/docs/reference/api-and-cli/"><span>Automatización</span>Contratos de API y CLI: consulta estructuras de solicitud y respuesta, rutas, comportamiento de salida y ejemplos generados (en inglés).</a>
  <a href="/es/docs/reference/evidence-packets/"><span>Resultados del agente</span>Consultas y evidencia: valores tipados, cobertura, datos ausentes, operaciones e identidades deterministas (en inglés).</a>
  <a href="/es/docs/reference/daily-records/"><span>Esquema v8</span>Registros diarios: conoce el documento público de origen y sus reglas de propiedad (en inglés).</a>
  <a href="/es/docs/shared-metric-registry/"><span>Vocabulario</span>Registro de métricas: usa identificadores, categorías, unidades y metadatos de perfil estables entre plataformas.</a>
  <a href="/es/docs/reference/generated/"><span>Legible por máquina</span>Artefactos generados: consulta campos canónicos, fixtures, inventarios de mensajes y contratos de la CLI (en inglés).</a>
</div>

<p class="docs-section-kicker">Flujos de trabajo del producto</p>

## Aplicaciones y exportaciones

### Exportaciones fiables basadas en perfiles

- Elige Resumen o Serie temporal detallada compartida; el archivo canónico Registros de salud sin pérdidas es exclusivo de Apple.
- Guarda ajustes, destinos y programaciones independientes como perfiles locales en iPhone o Android.
- Detener o cancelar solo afecta al intento activo: las fechas terminadas se conservan, las pendientes pueden reintentarse y la programación sigue activa.

Empieza con [Perfiles de exportación](/es/docs/export-profiles/) para conocer identificadores estables, automatización, historial de destinos y fallos seguros.

<div class="related">
  <a href="/es/docs/export-profiles/"><span>Flujos reutilizables</span>Perfiles de exportación: fija el destino, los formatos, las métricas, la programación y el identificador de automatización.</a>
  <a href="/es/docs/iphone-first-export/"><span>Empieza aquí · iPhone</span>Primera exportación: autoriza Apple Health, elige una carpeta, obtén una vista previa y verifica los archivos escritos.</a>
  <a href="/es/docs/android/"><span>Android</span>Health Connect: elige una carpeta de un proveedor de documentos y configura la automatización de la plataforma.</a>
  <a href="/es/docs/export/"><span>Archivos</span>Exportación: ejecuta intervalos de fechas explícitos en Markdown, CSV, JSON u Obsidian Bases.</a>
  <a href="/es/docs/format/"><span>Estructura</span>Personalización del formato: controla las unidades, las fechas, el frontmatter, los nombres de archivo y el comportamiento de escritura.</a>
  <a href="/es/docs/scheduling/"><span>Segundo plano</span>Programación: conoce las cadencias recurrentes, la recuperación y los límites de tiempo de cada plataforma.</a>
  <a href="/es/docs/shortcuts/"><span>Automatización</span>Shortcuts y App Intents: inicia exportaciones, resúmenes y comprobaciones de estado desde flujos de trabajo de Apple.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:12px; font-family:var(--sl-font-mono);">Estructura de la documentación actualizada el 2026-08-31</p>
