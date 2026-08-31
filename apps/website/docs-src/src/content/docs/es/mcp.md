---
title: "Servidor y aplicación Health.md MCP"
description: "Usa Codex o Claude para ejecutar análisis acotados de Apple Health, generar gráficos nativos e iniciar exportaciones persistentes de Health.md mediante una aplicación MCP local en un entorno aislado."
---

Health.md para Mac incluye un asistente stdio firmado `healthmd-mcp`. Permite a Codex, Claude y otros hosts de MCP consultar datos reales de Apple Health, generar visualizaciones, actualizar el contexto local cifrado y ejecutar exportaciones persistentes aprobadas a través de la aplicación abierta para Mac.

```text
Codex / Claude / another local MCP host
  <-> MCP JSON-RPC over stdio
  <-> signed healthmd-mcp helper
  <-> Health.md Mac loopback API on 127.0.0.1:17645
  <-> connected iPhone for fresh HealthKit reads and exports
```

<div class="availability available">
<strong>Disponible ahora · Health.md para Mac</strong>
<p>El servidor incluido expone 21 herramientas fijas. Por sí mismo, no lee HealthKit ni exporta carpetas, marcadores con alcance de seguridad o archivos arbitrarios.</p>
</div>

<div class="availability preview">
<strong>Vista previa · MCP directo y portátil</strong>
<p>La topología independiente <code>healthmd mcp serve</code> de 19 herramientas para macOS, Linux y Windows está empaquetada públicamente como vista previa explícitamente no cualificada. Su entrada <code>serve-read-only</code> sin nube expone solo las 13 herramientas de disponibilidad y consulta después del emparejamiento local. Instala en macOS o Linux con <code>brew install CodyBontecou/tap/healthmd</code>.</p>
</div>

## Requisitos de la versión incluida para Mac

- Health.md para Mac instalado y abierto.
- Health.md abierto en el iPhone conectado cuando la herramienta de actualización o una exportación inicia una nueva lectura de HealthKit.
- Un host MCP local con soporte stdio.
- La ruta del asistente firmado que se muestra en **Health.md para Mac → CLI**.

La ruta habitual del asistente es `/Applications/Health.md.app/Contents/Helpers/healthmd-mcp`. Las versiones principales del protocolo MCP admitidas son `2024-11-05`, `2025-03-26`, `2025-06-18` y `2025-11-25`. No inicies `healthmd-mcp` como un comando interactivo normal; el host MCP posee la entrada estándar y el ciclo de vida del proceso.

## Requisitos del modo directo portátil

- Instala la vista previa independiente en macOS, Linux o Windows; no requiere la aplicación para Mac ni su servicio de loopback.
- Empareja una vez un iPhone con consultas y mantén Health.md en primer plano para cada petición tipada nueva. Android no admite MCP tipado.
- Usa Manual IP o Tailscale y el almacén nativo de credenciales; Linux requiere un proveedor Secret Service desbloqueado.
- Configura el iniciador de compatibilidad instalado o el servidor stdio del mismo binario. Ambos usan el backend directo emparejado.

## Configuración de Codex

Añade el asistente incluido a `~/.codex/config.toml`:

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

Reinicia Codex, llama a `healthmd_doctor`, resuelve los ID con `healthmd_metrics`, adquiere explícitamente un alcance pequeño y exacto con la herramienta de actualización y luego consulta ese alcance con `healthmd_metric_chart`. Los hosts sin aplicaciones MCP interactivas aún reciben JSON exacto más un gráfico PNG estándar.

## Configuración de Claude

Usa esta entrada stdio local en la configuración MCP de Claude Desktop o un Claude Code `.mcp.json` confiable:

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

Reinicia Claude Desktop después de editar su configuración. Las configuraciones del proyecto Claude requieren confianza en el espacio de trabajo y aprobación explícita del servidor.

Las versiones de Claude Desktop que anuncian la extensión estable de MCP Apps muestran la vista interactiva de Health.md en línea. Claude Code y otros clientes de texto conservan los respaldos de imágenes y JSON.

## Vista previa portátil de MCP directo

En la vista previa pública independiente, `healthmd setup codex` empareja un iPhone en primer plano y crea de forma segura una entrada `healthmd mcp serve` del mismo binario. Esa topología utiliza Manual IP cifrada autenticada o transporte Tailscale en el puerto `17647`, almacenamiento de credenciales nativo y lecturas explícitas de iPhone por solicitud. Linux también requiere un proveedor de Secret Service desbloqueado; Windows utiliza el Windows Credential Manager.

Usa la versión preliminar exacta `healthmd-cli/v<version>` en lugar del puntero a la versión más reciente de todo el repositorio. Consulta [CLI directa para iPhone](/es/docs/cli-direct/) para conocer el contrato de transporte y emparejamiento explícitamente no cualificado.

## Visualizaciones de la aplicación MCP nativa

Health.md implementa una negociación `io.modelcontextprotocol/ui` estable con `text/html;profile=mcp-app`.

Después de que un host anuncia ese tipo MIME, el servidor expone:

- `ui://healthmd/query-visualization-v1`;
- métodos estándar `resources/list` y `resources/read`;
- `_meta.ui.resourceUri` sobre herramientas de análisis y recibos de exportación;
- `structuredContent` validado junto con texto JSON exacto.

La vista es un recurso HTML5 autónomo sin red, scripts remotos, fuentes remotas, almacenamiento ni marcos anidados. Su CSP declarado contiene listas vacías de dominios de conexión, recursos, marcos y URI base. Sigue el ciclo de vida estándar de inicialización, resultado de herramienta, tema, cambio de tamaño, cancelación y desmontaje.

Puede representar:

- gráficos de líneas métricas con unidades y huecos explícitos por datos ausentes;
- comparaciones de períodos con agregación seleccionada por la persona que llama;
- sesiones de sueño y resúmenes de duración de las etapas;
- entrenamientos y horarios reales de entrenamiento/sueño;
- cobertura, intervalos ausentes, evidencia y limitaciones;
- recibos del recorrido de todas las páginas;
- progreso persistente de las exportaciones, destinos y recibos de tareas.

Si el host no admite aplicaciones MCP, las herramientas aún funcionan. `healthmd_metric_chart` agrega contenido `image/png` para hosts con capacidad de imagen y al mismo tiempo conserva JSON completo como texto.

## Herramientas disponibles

El servidor Mac incluido expone 21 herramientas fijas: 13 de disponibilidad y consulta, cuatro de tareas de archivos generados y cuatro de tareas de actualización del contexto cifrado. La vista previa portátil de 19 herramientas conserva las 13 herramientas de disponibilidad y consulta y las cuatro de exportación, sustituye las tareas de actualización de Mac por dos herramientas de emparejamiento directo y ejecuta las consultas tipadas directamente en el iPhone en primer plano.

### Disponibilidad y descubrimiento

| Herramienta | Propósito |
|---|---|
| `healthmd_status` | Comprobar la disponibilidad de la aplicación para Mac, el contexto, el iPhone y la exportación |
| `healthmd_doctor` | Diagnosticar el asistente incluido y la topología de loopback de Mac |
| `healthmd_capabilities` | Enumerar capacidades de consulta directa, evidencia, exportación, esquema y paginación |
| `healthmd_metrics` | Enumerar ID de métricas canónicas, categorías, unidades y requisitos |

### Análisis y visualización

| Herramienta | Propósito |
|---|---|
| `healthmd_metric_chart` | Consulta series de métricas y genera gráficos nativos con cobertura y unidades |
| `healthmd_sleep_sessions` | Enumerar y visualizar sesiones de sueño estables y cobertura de fisiología |
| `healthmd_training_alignment` | Mostrar el tiempo real de entrenamiento frente al sueño anterior o posterior |
| `healthmd_workouts` | Listar y visualizar entrenamientos |
| `healthmd_coverage` | Inspeccionar la cobertura y la ausencia de datos por métrica y fecha |
| `healthmd_compare_periods` | Comparar períodos exactos con semántica de agregación explícita |
| `healthmd_training_evidence` | Crear un paquete de evidencia factual sobre el entrenamiento |
| `healthmd_query` | Enviar un `healthmd.query_request` exacto y, opcionalmente, atraviese páginas |
| `healthmd_evidence_packet` | Enviar una solicitud de evidencia exacta y, opcionalmente, recorra páginas |

### Exportaciones de archivos generados

| Herramienta | Propósito |
|---|---|
| `healthmd_export_files` | Ejecutar una exportación persistente de archivos; el Mac integrado usa su carpeta seleccionada y el MCP directo portátil exige un destino explícito del ordenador |
| `healthmd_export_job_status` | Inspeccionar el progreso de la exportación y el recibo de destino |
| `healthmd_export_job_resume` | Reanudar la tarea de exportación exacta, inmutable y persistente |
| `healthmd_export_job_cancel` | Cancelar explícitamente la tarea de exportación |

Las herramientas de exportación, reanudación y cancelación están marcadas como escrituras potencialmente destructivas y requieren interacción explícita en los hosts Claude actuales, porque los modos de exportación configurados pueden actualizar o sobrescribir los archivos generados. La configuración del Codex anterior solicita esas herramientas como protección adicional.

### Tareas de adquisición de contexto cifrado · solo en la versión incluida para Mac

| Herramienta | Propósito |
|---|---|
| `healthmd_refresh` | Adquirir un alcance aprobado desde iPhone en un contexto de Mac cifrado desechable |
| `healthmd_job_status` | Inspeccionar el progreso de la actualización sin leer los valores de salud |
| `healthmd_job_resume` | Reanudar la tarea de actualización exacta y aceptada |
| `healthmd_job_cancel` | Cancelar explícitamente una tarea de actualización aceptada |

### Descubre la estructura completa de las consultas

MCP `tools/list` incluye un esquema JSON anidado completo para fechas, métricas, fuentes, paginación,
intervalos de períodos, agregaciones y la estructura avanzada `healthmd.query_request`. Las herramientas tipadas también incluyen
ejemplos concretos. Un agente debe llamar directamente a la herramienta tipada correspondiente en lugar de consultar la ayuda
genérica del shell. En particular, las preguntas sobre el sueño usan `healthmd_sleep_sessions`; `healthmd extract` produce una
proyección diferente de los datos de origen canónicos.

La vista previa portátil permite inspeccionar el mismo esquema localmente sin abrir un servicio de escucha de red ni contactar al iPhone. Para el asistente Mac publicado, usa tools/list de MCP.

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # complete fixed catalog
```

Una llamada de sueño mínima tiene esta forma (resuelva las fechas inclusivas para la solicitud real):

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-22",
      "end_date": "2026-07-28"
    }
  },
  "all_pages": true
}
```

Las métricas canónicas del sueño y el detalle sin pérdidas de la sesión se proporcionan automáticamente mediante
`healthmd_sleep_sessions`.

## Analizar y representar datos gráficamente

Llama primero a `healthmd_doctor` y obtén los ID de métricas con `healthmd_metrics`. En la topología Mac publicada, las herramientas de consulta tipada leen el contexto cifrado del Mac; no contactan implícitamente al iPhone. Para obtener datos actuales, llama a la herramienta de actualización con fechas, métricas y fuentes explícitas, espera a que termine su tarea persistente y luego representa el mismo alcance:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps", "resting_heart_rate"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

Pasa ese objeto a `healthmd_metric_chart`. La vista interactiva utiliza pequeños múltiplos que mantienen separadas las unidades. Un punto faltante o parcial rompe la línea en lugar de convertirse en cero.

Las herramientas tipadas publicadas para Mac evalúan el contexto local cifrado y devuelven páginas acotadas con cobertura, datos ausentes, evidencia y limitaciones. Solo una actualización explícita contacta al iPhone conectado en primer plano y reemplaza el alcance solicitado del contexto. La vista previa portátil evalúa cada solicitud tipada directamente en su iPhone emparejado en primer plano.

## Ejecutar una exportación de archivo generado

Primero selecciona y conserva una carpeta de destino con permisos de escritura en Health.md para Mac. Después de que el host muestre los argumentos completos y el usuario los apruebe, llama a `healthmd_export_files`:

```json
{
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-07-01",
    "end": "2026-07-07"
  },
  "settings_policy": "requested_dates_only",
  "categories": ["Sleep"],
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Usa `date_selection: "all_available"` sin `date_range` para obtener un historial completo. Los campos opcionales `metric_ids`, `categories` o `all_metrics` acotan la adquisición del iPhone sin cambiar la configuración guardada. `detail_level` se aplica solo cuando una de esas selecciones está presente. `all_metrics` no se puede combinar con listas explícitas de métricas/categorías.

Para ejecutar en su lugar un perfil guardado, establece `settings_policy` en `"profile"` y pasa `profile_reference` con su UUID estable. En el protocolo público, el `name` opcional aporta contexto de visualización y error. Las implementaciones actuales del teléfono pueden consultarlo si falla la búsqueda del ID, pero ese comportamiento no resiste cambios de nombre; la automatización debe tratar el UUID como identidad estable:

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" }
}
```

El perfil es el dueño del alcance de ajustes: `profile_reference` no se puede combinar con `metric_ids`, `categories`, `all_metrics` ni con la política de ajustes guardados, y una referencia que no se puede resolver falla con un error tipado en lugar de recurrir a los ajustes activos.

Los ejemplos anteriores usan el destino del Mac integrado. Con el MCP directo portátil, cada solicitud de archivos también exige una carpeta absoluta y existente del ordenador en `destination`; el perfil del teléfono aporta los ajustes de salida, no esa ruta del host:

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" },
  "destination": "/absolute/existing/HealthVault",
  "wait_timeout_seconds": 300
}
```

El modo directo portátil rechaza un destino ausente, relativo, inexistente o que sea un enlace simbólico antes de iniciar la tarea del teléfono.

Inspeccionar:

- `status` y el `state` persistente;
- `job_id`;
- días procesados/total y progreso;
- archivos o notas diarias escritas;
- destino de escritorio validado;
- particiones y bytes comprometidos;
- motivo de pausa/fallo y caducidad.

Un tiempo de espera o el cierre de un cliente MCP que esperaba el resultado no cancelan la tarea persistente. Comprueba `healthmd_export_job_status` antes de reanudarla tras un resultado desconocido. Solo una cancelación explícita finaliza la tarea.

El transporte de datos de origen sin procesar y canónicos puede contener gigabytes de rutas, texto clínico, archivos adjuntos y registros de fuentes. Health.md deliberadamente no incluye esos cuerpos de datos en una conversación MCP. Usa la CLI de transmisión validada para obtener resultados en forma de fuente:

```bash
healthmd extract --metric workouts --last 30 --detail lossless --output workouts.json
healthmd export --iphone --all --raw --output health-corpus.json
```

El análisis del MCP sigue siendo una vista factual derivada; las exportaciones de archivos generados continúan utilizando el contrato público `healthmd.health_data` a través de los exportadores de producción.

## Paginación e integridad

Las herramientas de consulta/evidencia exponen `all_pages: true` cuando sea compatible. El asistente sigue cursores opacos con detección de ciclos y límites máximos de bytes/páginas agregados, preservando cada respuesta versionada bajo `healthmd.mcp_query_pages` v1. Si se alcanza un límite de recorrido automático, el contenedor parcial exitoso establece `receipt.traversal_complete` en `false` y devuelve el `receipt.next_cursor` exacto para una continuación sin pérdidas. El iPhone conserva una instantánea compacta y paginada durante diez minutos de inactividad en primer plano y la elimina al finalizar el recorrido o al pasar a segundo plano. Cada solicitud tiene un límite de seguridad de 366.000 días para el contexto compacto codificado y 64 MiB; `query_scope_too_large` significa que hay que repartir las fechas o los ID de métricas entre varias llamadas, no que el historial lógico no esté disponible. Las páginas acotan las listas de intervalos ausentes y descriptores de origen con limitaciones y campos explícitos de recuento/truncamiento.

El éxito del transporte no es la integridad. Inspecciona siempre:

- alcance solicitado y estado del corpus;
- cobertura e intervalos ausentes;
- limitaciones y evidencia;
- `next_cursor` o el recibo del recorrido;
- omisiones no relacionadas;
- esquema fuente y versión.

La aplicación MCP muestra estos campos en lugar de ocultarlos. Si el recorrido automático alcanza su límite de seguridad, reduce el alcance o continúa manualmente.

## Límites de seguridad y privacidad

El asistente no tiene mensajes, raíces, muestreo, shell, SQL, lecturas de archivos arbitrarias, recuperaciones de URL arbitrarias, escrituras de HealthKit, servicio HTTP de loopback ni punto final MCP remoto. Su único recurso MCP es el documento de la aplicación incluido. Las escrituras de archivos generados son una operación fija sujeta a aprobación. El asistente Mac publicado usa la carpeta seleccionada en Health.md para Mac; la vista previa portátil requiere un destino existente explícito que valida y vincula de forma persistente antes de la transferencia.

La confianza directa se almacena en Keychain, Secret Service o Windows Credential Manager. El emparejamiento utiliza el protocolo cifrado autenticado existente; el iPhone debe estar en primer plano y conectado explícitamente a la dirección LAN o Tailscale de la computadora. Las páginas de consulta están limitadas a los límites de bytes/elementos negociados, y la agregación automática de todas las páginas tiene límites de bytes/páginas adicionales. Los cuerpos de datos sin procesar y sin límite permanecen en la ruta CLI de transmisión validada.

Health.md informa observaciones fácticas con unidades, procedencia, cobertura y ausencia de datos. No diagnostica, recomienda tratamiento, infiere la causalidad ni indica una dirección mejor o peor.

## Solución de problemas

| Síntoma | Acción |
|---|---|
| El host no puede iniciar el asistente | Usa la ruta `healthmd` o `.exe` instalada absoluta con los argumentos `mcp serve` |
| El asistente espera cuando se ejecuta en la Terminal | Esperado; un host MCP debe enviar JSON-RPC en stdin |
| `healthmd_not_paired` | Ejecuta `healthmd direct pair` y completa el emparejamiento en el iPhone |
| `healthmd_unavailable` | Desbloquea Health.md en el iPhone y ponlo en primer plano, habilita el acceso directo de la CLI y conéctate a la computadora |
| `query_scope_too_large` | Fechas de partición o ID de métricas entre llamadas; el corpus lógico permanece disponible en todas las solicitudes |
| Sin gráfico interactivo | Actualizar el host; el servidor aún devuelve JSON exacto y un gráfico alternativo de métricas PNG |
| Destino de exportación no disponible | Mac: vuelve a seleccionar la carpeta guardada en Health.md. Vista previa portátil: crea y proporciona un directorio de escritorio absoluto existente sin enlace simbólico. |
| Se agota el tiempo de espera de la exportación | Inspeccionar la tarea persistente de exportación por ID antes de reanudarlo |
| El resultado tiene `next_cursor` | Configura `all_pages: true` o continúa con el cursor manualmente |

## Relacionado

<div class="related">
<a href="/es/docs/agents/"><span>Arquitectura</span>Agentes locales, contexto cifrado, alcance de la solicitud y evidencia.</a>
<a href="/es/docs/agent-queries/"><span>Análisis</span>Libro de recetas de consultas tipadas para métricas, sueño, entrenamientos, comparación y cobertura.</a>
<a href="/es/docs/cli-extract/"><span>Datos de origen</span>Extracción canónica validada para resultados de gran tamaño en forma de origen.</a>
<a href="/es/docs/reference/evidence-packets/"><span>Contratos</span>Valores tipados, ausencia de datos, evidencia e identidades de paquetes.</a>
</div>
