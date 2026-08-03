---
title: "API de consulta de loopback"
description: "Accede a las rutas locales versionadas de Health.md para consultas, evidencia, actualización, preparación, métricas y tareas persistentes mediante HTTP o el comando de agente de bajo nivel de healthmd."
---

Health.md para Mac expone una API local versionada bajo `/v1/agent/`. Ofrece consultas sobre el contexto cifrado, paquetes de evidencia, adquisición desde el iPhone acotada a la solicitud, información de disponibilidad y tareas de adquisición persistentes.

La API escucha en la interfaz de loopback del puerto `17645`. Solo acepta conexiones validadas de pares de loopback IPv4 o IPv6.

<div class="callout">
<strong>No expongas este puerto.</strong>
<p style="margin-top:6px;">No hay token de portador, registro de clientes, perfil de acceso ni base de datos de permisos. El acceso mediante loopback constituye todo el límite de autorización. Cualquier proceso local puede enviar solicitudes mientras Health.md esté abierto.</p>
</div>

## Rutas

| Método | Ruta | Propósito |
|---|---|---|
| `GET` | `/v1/agent/capabilities` | Listar esquemas versionados, soporte de alcance y límites de página |
| `GET` | `/v1/agent/metrics` | Devolver ID, categorías, unidades y requisitos de métricas canónicas consultables |
| `GET` | `/v1/agent/readiness` | Devolver la disponibilidad del contexto cifrado y de datos recientes del iPhone, con los siguientes pasos |
| `POST` | `/v1/agent/query` | Ejecutar una página acotada de una consulta tipada |
| `POST` | `/v1/agent/evidence` | Derivar una página acotada de un paquete de evidencia factual |
| `POST` | `/v1/agent/refresh` | Adquirir un alcance explícito desde iPhone en contexto Mac cifrado |
| `GET` | `/v1/agent/jobs/{id}` | Inspeccionar una tarea local persistente de adquisición |
| `POST` | `/v1/agent/jobs/{id}/resume` | Reanudar la solicitud de adquisición inmutable |
| `POST` | `/v1/agent/jobs/{id}/cancel` | Solicitar cancelación explícita |

Las rutas anteriores `/v1/agent/profiles` y `/v1/agent/activity/query` devuelven `410 removed_endpoint`.

El backend directo del iPhone no aloja estas rutas HTTP. El comando independiente `healthmd` lo utiliza para la extracción y exportación canónicas, mientras que `healthmd mcp serve` implementa herramientas de consulta tipada de datos recientes, evidencia, catálogo de métricas, disponibilidad, visualización y exportación persistente directamente mediante el protocolo de consulta del iPhone v3. El emparejamiento y MCP utilizan la misma identidad del ejecutable; la actualización y el contexto cifrado del Mac siguen siendo específicos de esta API HTTP.

## Usa preferentemente el adaptador de la CLI

La CLI de bajo nivel conserva exactamente los cuerpos de las solicitudes y gestiona los errores de transporte de loopback:

```bash
healthmd agent capabilities
healthmd agent query --input query-body.json
healthmd agent query --input - < query-body.json
healthmd agent evidence --input evidence-body.json
healthmd agent refresh --input refresh-body.json
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

Usa `--json JSON` en lugar de `--input` para un cuerpo pequeño. La CLI no amplía ni reduce silenciosamente el JSON proporcionado a estos comandos.

Usa comandos de alto nivel como `healthmd query`, `healthmd sleep sessions` o `healthmd compare` para flujos de trabajo normales. Estos comandos validan los selectores y construyen la operación tipada.

## Cuerpo de la consulta

`POST /v1/agent/query` acepta solo `request` y `detail_level` opcional en el nivel superior:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

Se rechazan los campos desconocidos del contenedor. El contrato de solicitud de consulta define métricas, fuentes, fechas, operación y controles de página. `detail_level` es `summary` o `lossless`.

La respuesta es `healthmd.query_response` v1. Contiene elementos tipados, cobertura, evidencia, descriptores de fuentes, limitaciones y `next_cursor` opcional.

Consulta una respuesta sintética completa en [`agent-query-response.json`](/docs/reference/generated/automation/agent-query-response.json).

## Continuar un cursor

Para solicitar la página siguiente, envíe la misma solicitud semántica y coloque el cursor devuelto en `page.cursor`:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144,
      "cursor": "OPAQUE_CURSOR_FROM_PRIOR_RESPONSE"
    }
  },
  "detail_level": "summary"
}
```

Siga `next_cursor` hasta que desaparezca. Los cursores están autenticados y vinculados a la solicitud y a la revisión del corpus cifrado. Health.md rechaza cursores modificados, no coincidentes y obsoletos.

Los límites de página protegen cada solicitud sin imponer un historial total o un límite de resultados.

## Cuerpo de evidencia

`POST /v1/agent/evidence` usa el mismo contenedor. La operación es `derive_packet` con un tipo de paquete y detalles seleccionados explícitamente.

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps", "resting_heart_rate"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "derive_packet",
      "kind": "doctor_visit",
      "detail_ids": []
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

La respuesta sigue siendo una respuesta de consulta paginada y contiene un fragmento `healthmd.evidence_packet` v1. Los hechos incluyen valores tipados y evidencia. El paquete incluye la limitación de únicamente observaciones fácticas.

Consulta [`agent-evidence-response.json`](/docs/reference/generated/automation/agent-evidence-response.json) para obtener una respuesta sintética completa.

## Cuerpo de actualización

La actualización solo adquiere un alcance explícito. El cuerpo acepta fechas, métricas, fuentes, nivel de detalle y un tiempo de espera finito:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-07"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["sleep_total"]
  },
  "sources": {
    "type": "explicit",
    "source_ids": ["apple_health"],
    "provider_ids": []
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

El Mac valida el alcance con los catálogos actuales y lo convierte en una selección canónica inmutable. El iPhone solo lee los tipos de HealthKit ordinarios seleccionados. La configuración del alcance de la solicitud no cambia las preferencias de exportación guardadas del iPhone.

La actualización utiliza un modo de transferencia `encrypted_context` dedicado:

- no escribe archivos de exportación;
- no consume cuota de exportación de archivos;
- transfiere particiones reanudables acotadas;
- el Mac confirma cada día de propietario compacto y determinista antes de enviar el acuse de recibo;
- la solicitud exacta se conserva con la tarea persistente.

Un alcance limitado al proveedor no requiere leer Apple Health. El historial nativo del proveedor sigue siendo evidencia nativa del proveedor y no se convierte en métricas sintéticas de Apple Health.

## Selección de todos los datos disponibles

Los selectores de métricas y fechas pueden usar `all_available`:

```json
{
  "dates": {"type": "all_available"},
  "metrics": {"type": "all_available"},
  "sources": {"type": "all_available"},
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

El iPhone resuelve el registro de Apple Health seleccionado más antiguo disponible y todos los días del calendario fuente hasta hoy. La adquisición de proveedores sigue los cursores del historial nativo del proveedor. Los identificadores resueltos se fijan antes de la transferencia, por lo que la reanudación no puede cambiar la solicitud.

No hay fecha fija ni límite de resultados. Las particiones, las páginas, el descifrado de un día, el espacio en disco y las esperas finitas proporcionan límites de recursos.

## Tareas persistentes de adquisición

La espera de una actualización puede agotar el tiempo mientras la tarea continúa. La respuesta incluye un ID de tarea e información de progreso que se puede mostrar con seguridad.

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

La tarea caduca siete días después de su creación. La reanudación reutiliza la misma solicitud, el mismo Mac, el mismo iPhone, el mismo alcance de fuentes y la misma frontera confirmada.

La cancelación es terminal solo después del reconocimiento del iPhone. Un iPhone no disponible puede dejar la tarea en estado de cancelación pendiente.

## Llamadas HTTP directas

Se prefiere la CLI, pero el software local puede llamar a HTTP directamente:

```bash
curl --fail-with-body --max-time 5 \
  http://127.0.0.1:17645/v1/agent/readiness

curl --fail-with-body --max-time 30 \
  -H 'Content-Type: application/json' \
  --data @query-body.json \
  http://127.0.0.1:17645/v1/agent/query
```

El servicio limita las cabeceras y los cuerpos JSON, exige un método y un tipo de contenido explícitos, impone plazos de recepción y garantiza que las solicitudes finalicen.

Mantén los clientes HTTP directos en la misma Mac. No añadas un enlace a la LAN, un proxy, un túnel o un contenedor HTTP MCP remoto.

## Valores tipados y ausencia de datos

Los resultados de la consulta conservan el tipo y la unidad. Los valores pueden ser cantidades, duraciones, recuentos, cadenas, categorías, valores booleanos, marcas de tiempo, fechas de calendario, matrices anidadas o valores tipados futuros desconocidos.

Los estados de ausencia incluyen vacío completo, parcial, fallido, no compatible, omitido, cancelado, no solicitado, no disponible en datos heredados, censurado y no sincronizado. Los consumidores no deben convertirlos en cero.

La cobertura incluye los intervalos solicitados y disponibles, los días considerados, los días con valores y los intervalos de ausencia comprimidos que conservan su estado.

## Manejo de errores

Los errores utilizan `healthmd.query_error` v1 con un código estable, mensaje, información sobre si se puede reintentar y detalles tipados. Los errores distintos cubren:

- controles de página no válidos;
- cursores mal formados o manipulados;
- cursor y consulta no coinciden;
- revisión del corpus obsoleto;
- intervalo de fechas no válido;
- validación de métricas o fuentes;
- discrepancia entre unidades o agregaciones;
- operación no compatible;
- violación del alcance de la evidencia;
- disponibilidad del iPhone o del almacén cifrado;
- estado de la tarea persistente.

No vuelva a intentar una actualización a ciegas después de un resultado desconocido. Primero inspecciona el estado de la tarea.

## Relacionado

<div class="related">
<a href="/es/docs/agents/"><span>Descripción general</span>Agentes locales y contexto de salud: configuración, almacenamiento cifrado, alcance y reglas de generación de informes.</a>
<a href="/es/docs/agent-queries/"><span>Nivel alto</span>Libro de recetas de consultas tipadas: comandos validados para preguntas comunes sobre métricas, sueño, entrenamiento y evidencia.</a>
<a href="/es/docs/mcp/"><span>Herramientas</span>Servidor MCP local: configuración estándar, herramientas tipadas, paginación y límites de sandbox.</a>
<a href="/es/docs/reference/api-and-cli/"><span>Referencia</span>Contrato API y CLI: exportación, extracción, consulta, backend directo y límites operativos.</a>
<a href="/es/docs/reference/evidence-packets/"><span>Contratos de datos</span>Consultas compactas y paquetes de evidencia: tipos, cursores, operaciones e ID de paquetes deterministas.</a>
</div>
