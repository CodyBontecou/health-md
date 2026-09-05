---
title: "Conecta un agente en 10 minutos"
description: "Conecta el asistente MCP de Mac de Health.md publicado con Codex o Claude, adquiere un alcance explícito del iPhone, ejecuta una consulta acotada y verifica la completitud con seguridad."
---

<div class="availability available">
<strong>Disponible ahora · Health.md para Mac</strong>
<p>Este camino usa el asistente <code>healthmd-mcp</code> firmado que se incluye con la app de Mac publicada. No usa la vista previa portátil de la CLI, el acceso directo de la CLI, un código QR de emparejamiento ni el puerto 17647.</p>
</div>

Vas a conectar un host MCP local, verificar la disponibilidad sin leer valores de salud, actualizar explícitamente un alcance pequeño desde el iPhone y consultar ese contexto cifrado del Mac. Calcula unos diez minutos cuando ambas apps ya están instaladas y en la misma red local.

## 1. Instala y abre Health.md

[Descarga Health.md del App Store](https://apps.apple.com/us/app/health-md/id6757763969) en el Mac y en el iPhone. Abre ambas apps.

HealthKit se queda en el iPhone. La app de Mac aloja el asistente MCP firmado y un contexto de consulta cifrado y desechable; no lee HealthKit directamente.

## 2. Conecta el iPhone y el Mac

1. En el Mac, deja Health.md abierto.
2. En el iPhone, abre **Health.md → Sincronizar** y activa la conectividad con el Mac.
3. Mantén ambos dispositivos en la misma red local accesible y mantiene Health.md en primer plano en el iPhone mientras empieza trabajo nuevo.
4. Confirma que la app del Mac muestra la conexión del iPhone prevista. Si no es así, vuelve a abrir ambas apps y revisa la [disponibilidad de la sincronización con el Mac](/es/docs/sync/).

Esta es la conexión publicada del Mac. No ejecutes `healthmd direct pair`; ese comando pertenece a la vista previa portátil independiente.

## 3. Copia la ruta del asistente firmado

Abre **Health.md para Mac → CLI** y copia la ruta del asistente MCP que se muestra. Una instalación normal en `/Applications` usa:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Usa la ruta mostrada si la app está instalada en otro lugar. Configura el asistente directamente: no lo envuelvas en un shell ni lo inicies como comando interactivo.

## 4. Configura Codex o Claude

### Codex

Añade esto a `~/.codex/config.toml`, sustituyendo la ruta del asistente cuando sea necesario:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_files]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_resume]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_cancel]
approval_mode = "prompt"
```

Reinicia Codex después de guardar el archivo.

### Claude Desktop o Claude Code

Añade esta entrada stdio local a la configuración MCP de Claude Desktop o a un `.mcp.json` de confianza de Claude Code:

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

Reinicia Claude Desktop, o confía en el espacio de trabajo de Claude Code y aprueba el servidor. Mantén activados los avisos de aprobación para las operaciones de actualización, exportación, reanudación y cancelación.

## 5. Comprueba la disponibilidad

Llama a `healthmd_doctor`. Solo lee la disponibilidad, sin valores de salud.

Un resultado listo contiene estos campos:

```json
{
  "schema": "healthmd.local_readiness",
  "schema_version": 1,
  "status": "ready"
}
```

El resultado completo también incluye comprobaciones y acciones siguientes. Resuelve cada comprobación bloqueante antes de continuar. Un asistente conectado **no** demuestra que el contexto cifrado esté actualizado.

Después, llama a `healthmd_metrics` y confirma el ID de métrica canónico y la unidad que piensas solicitar. Este recorrido usa `steps` solo como ejemplo.

## 6. Actualiza explícitamente un alcance pequeño

Resuelve las fechas que realmente quieres y llama a `healthmd_refresh` con un rango exacto e inclusivo. El ejemplo solicita un día de datos resumidos:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Revisa los argumentos, aprueba la adquisición y mantén ambas apps abiertas. La actualización no escribe archivos de exportación ni cambia los ajustes de exportación guardados del iPhone. Conserva el `job_id` devuelto hasta que la tarea alcance un estado terminal.

## 7. Ejecuta la primera consulta acotada

Cuando termine la actualización, llama a `healthmd_metric_chart` con las mismas fechas, métrica, selección de fuentes y nivel de detalle:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

`all_pages: true` recorre cursores opacos únicamente dentro de los techos agregados de páginas y bytes del asistente. Para el sueño, llama a `healthmd_sleep_sessions` en lugar de sustituir la extracción canónica.

## 8. Verifica la completitud antes de responder

No trates el éxito de una herramienta como prueba de cobertura sanitaria completa. Comprueba todo lo siguiente:

- la actualización alcanzó un estado terminal correcto para las mismas fechas exactas, métricas, fuentes y nivel de detalle;
- el esquema y la versión de la respuesta se reconocen;
- el rango solicitado y la zona horaria coinciden con la pregunta;
- cada valor indicado conserva su ID de métrica canónico y su unidad;
- se informan el estado de cobertura, los días considerados, los días con valores y cada intervalo ausente;
- `complete_empty`, `partial`, `failed`, `unsupported`, `skipped` y `cancelled` no se convierten en cero;
- el recorrido se completó, o se declara cualquier cursor o techo agregado pendiente;
- los descriptores de evidencia y de origen y las limitaciones siguen adjuntos a la respuesta;
- la dirección factual no se convierte en diagnóstico, consejo de tratamiento, causalidad ni un lenguaje de «mejor/peor».

### Lee resultados parciales sin descartar datos útiles

Una consulta tipada puede devolver un `healthmd.query_response` válido aunque solo se completara parte del alcance solicitado. El [fixture generado de respuesta parcial](/docs/reference/generated/automation/agent-query-response-partial.json) conserva un elemento de pasos disponible e informa del día fallido por separado:

```json
{
  "schema": "healthmd.query_response",
  "schema_version": 1,
  "coverage": {
    "status": "partial",
    "days_considered": 2,
    "days_with_values": 1,
    "missing": [
      {
        "status": "failed",
        "range": {
          "start_date": "2026-03-16",
          "end_date": "2026-03-16"
        }
      }
    ]
  },
  "items": ["one retained typed item"],
  "limitations": ["one or more requested days did not complete"]
}
```

Las cadenas dentro de `items` y `limitations` son abreviaturas explicativas; usa el fixture generado descargable para los campos y la evidencia exactos. Conserva juntos el elemento retenido, el intervalo fallido, los recuentos de cobertura y la limitación.

No añadas `status: "partial_success"` a `healthmd.query_response`. Ese estado pertenece a los sobres de la CLI y de exportación de nivel superior cuando la adquisición, el recorrido o la generación de archivos quedan incompletos. Un tiempo de espera es otra cosa: es un resultado desconocido de una tarea persistente que debe inspeccionarse por ID de tarea.

Los fallos estructurados usan `healthmd.query_error` v1 en lugar de una respuesta parcial. Consulta [agent-query-error.json](/docs/reference/generated/automation/agent-query-error.json) para la forma de producción generada, con código estable, mensaje, reintento y detalles tipados.

## 9. Recupérate de un tiempo de espera con seguridad

Un tiempo de espera, un host cerrado o una espera de MCP cancelada no cancela una actualización aceptada.

1. Conserva el `job_id` devuelto.
2. Llama a `healthmd_job_status` con ese ID.
3. Si la tarea inmutable se puede reanudar, revisa y aprueba `healthmd_job_resume` con el mismo ID y un tiempo de espera finito.
4. Inicia una actualización nueva solo después de que el estado demuestre que ninguna tarea aceptada puede completarse todavía.
5. Usa `healthmd_job_cancel` solo cuando quieras terminar la tarea; la cancelación es terminal únicamente tras el reconocimiento del iPhone.

Nunca reintentes a ciegas tras un resultado desconocido. Las tareas persistentes de actualización conservan el alcance aceptado y la frontera confirmada.

## Estás conectado

El primer flujo de solo lectura termina cuando el doctor está listo, la actualización explícita es terminal, la consulta acotada tiene el recorrido completo y has inspeccionado la cobertura, la evidencia, las unidades y las limitaciones.

Las exportaciones de archivos generados son un flujo aparte que requiere aprobación. La herramienta publicada del Mac escribe en la carpeta ya seleccionada en Health.md para Mac; no acepta un argumento de destino arbitrario.

<div class="related">
  <a href="/es/docs/mcp/"><span>Catálogo de herramientas</span>Repasa todas las herramientas publicadas del Mac, los esquemas exactos, MCP Apps, la paginación y los límites de seguridad.</a>
  <a href="/es/docs/configuration/"><span>Otros clientes</span>Elige entre la integración publicada del Mac y la vista previa portátil claramente marcada.</a>
  <a href="/es/docs/agent-queries/"><span>Siguientes preguntas</span>Ejecuta flujos tipados de métricas, sueño, entrenamientos, comparaciones, cobertura y evidencia.</a>
  <a href="/es/docs/agents/"><span>Modelo de confianza</span>Entiende el contexto cifrado, el alcance de las solicitudes, la retención, la evidencia y las reglas de informes.</a>
</div>
