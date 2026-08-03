---
title: "Automatización y tareas persistentes de la CLI"
description: "Automatiza healthmd de forma segura con resultados legibles por máquina, esperas acotadas, tareas persistentes durante siete días, estados parciales explícitos, reanudación y cancelación confirmada."
---

Health.md trata las operaciones conectadas de exportación y adquisición de contexto como tareas persistentes. La vida útil de una tarea es independiente del proceso que la inició. Una terminal puede cerrarse o una conexión de red puede fallar sin descartar las particiones completadas.

Esta página se aplica a la exportación de archivos, la exportación estricta de datos sin procesar, la extracción canónica y la adquisición de datos recientes para el contexto cifrado, a menos que un comando documente una regla más estricta.

## La regla central

Un tiempo de espera o desconexión no significa cancelación.

No inicies una tarea duplicada después de un resultado desconocido. Guarda el ID de la tarea devuelto, inspecciona su estado y reanuda la misma tarea.

Las tareas de exportación, de datos sin procesar y de extracción utilizan los comandos del ciclo de vida de nivel superior:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Las tareas de adquisición de contexto cifrado utilizan el ciclo de vida del agente local:

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
```

## Vida útil de siete días

Una tarea persistente tiene un `expires_at` fijo siete días después de su creación. El progreso no amplía ese plazo. Ambos pares conservan la solicitud inmutable y suficiente estado confirmado de la transferencia para reanudarla de forma segura.

Una tarea puede conservar:

- fechas exactas o identificadores resueltos de todo el historial;
- alcance de métricas, categorías, fuentes y detalle;
- enlace de backend y dispositivo emparejado;
- política de configuración;
- selección del perfil de datos sin procesar o de la extracción;
- identidad del destino del archivo;
- huella digital de la solicitud;
- manifiestos de sesión y transferencia;
- cadena de resumen de partición;
- partición comprometida y frontera de bytes;
- acuse de recibo de finalización o cancelación.

La reanudación no puede reinterpretar ninguno de estos campos.

## El estado no solo está en ejecución o terminado

La respuesta de una tarea puede incluir:

| Campo | Significado |
|---|---|
| `durable` | Si la operación tiene un estado de tarea recuperable |
| `state` | Estado actual del ciclo de vida persistente |
| `job_id` | Identificador estable de la tarea |
| `session_id` | Identificador de sesión de transferencia vinculada |
| `paused` | Si la tarea necesita que se vuelva a conectar el mismo iPhone |
| `processed_days` / `total_days` | Progreso lógico del día del propietario |
| `committed_partitions` | Particiones reconocidas de forma persistente por el receptor |
| `committed_bytes` | Bytes de carga útil comprometidos de forma segura |
| `fraction_complete` | Fracción de progreso libre de salud |
| `expires_at` | Marca de tiempo fija de caducidad de la tarea |

Los campos de estado contienen fechas, ID, recuentos, bytes y errores seguros. No deben contener muestras de salud.

## Iniciar una tarea con un plan de salida explícito

Exportación de datos sin procesar:

```bash
healthmd export --iphone --last 30 --raw \
  --output health-month.json
```

Extracción canónica:

```bash
healthmd extract --category Sleep --last 30 \
  --output sleep-month.json
```

Archivos generados directamente:

```bash
healthmd --backend direct export --last 30 \
  --destination "$HOME/Documents/HealthVault"
```

Elige la salida o el destino final antes de que comience la solicitud. Una tarea de datos sin procesar fija su comportamiento de salida. Una tarea directa de archivos vincula la raíz de destino exacta a la solicitud inmutable.

## Reanudar

```bash
healthmd resume JOB_UUID --timeout 300
healthmd resume JOB_UUID --output recovered.json
healthmd resume JOB_UUID --output recovered.json --allow-partial
```

Para el modo directo, seleccione el mismo backend, dispositivo, transporte, puerto y iPhone utilizados en la solicitud original:

```bash
healthmd --backend direct --device DEVICE_UUID \
  --transport manual-ip --port 17647 \
  resume JOB_UUID --timeout 300 --output recovered.json
```

Los bytes pendientes pueden descartarse después de una desconexión. Las particiones confirmadas no se retransmiten ni se reinterpretan. El receptor acepta una partición ya comprometida solo cuando todos los descriptores inmutables coinciden.

Una tarea de archivos no acepta un destino de reemplazo durante la reanudación. Si la raíz original cambió, Health.md produce un error seguro en lugar de escribir en una carpeta diferente.

## Cancelar

Usa el ciclo de vida con el que se creó la tarea:

```bash
# Export, raw, or extraction
healthmd cancel JOB_UUID

# Encrypted-context acquisition
healthmd agent job cancel JOB_UUID
```

La cancelación tiene dos etapas:

1. la CLI registra y envía una solicitud de cancelación persistente;
2. el iPhone reconoce la cancelación y lo convierte en terminal.

Si el iPhone no está disponible, la tarea sigue en estado `cancellation_pending`. Vuelve a abrir el mismo iPhone e intenta cancelar de nuevo. No informes que una tarea está cancelada basándose únicamente en la intención local.

Un proceso que recibe Ctrl-C debería salir sin simular una cancelación terminal. Usa el comando de cancelación explícito cuando quieras cancelar.

## Canales de salida

Health.md separa los resultados del comando del progreso:

| Canal | Contenido |
|---|---|
| salida estándar | Resultado del comando JSON versionado, error o secuencia JSON/JSONL solicitada |
| stderr | Instrucciones de emparejamiento sencillas, progreso sin estado, recibo JSONL durante la transmisión y texto de uso |
| `--output PATH` | JSON o JSONL con datos de salud y escritura atómica |
| `OUTPUT.receipt.json` | Recibo de extracción sin estado para la salida de archivos JSONL |

`--help` es texto sin formato. Los errores de argumento antes de la ejecución utilizan stderr y la salida 2. Una vez que se ejecuta un comando, los errores de tiempo de ejecución utilizan JSON legible por máquina.

No combine stdout y stderr en un analizador de automatización.

## Estado de salida y estado de datos

El estado de salida del proceso es sólo una señal. Analice la respuesta antes de afirmar que fue exitosa.

| Resultado | Comportamiento de salida predeterminado |
|---|---|
| Éxito total | Cero |
| Alcance solicitado completo y vacío | Cero |
| Datos sin procesar estrictos o extracción, validados parcialmente | Distinto de cero |
| Parcial con `--allow-partial` explícito | Cero, pero la respuesta sigue siendo parcial |
| Error de argumento | Salida 2, texto sin formato en stderr |
| Fallo de validación o transporte | Distinto de cero con error de tiempo de ejecución estructurado |

`--allow-partial` es una política de aceptación, no una reparación de datos. Todos los días ausentes, consultas fallidas, tipos no admitidos y advertencias permanecen visibles.

## El recorrido de páginas es independiente de la finalización de la tarea

Las respuestas a las consultas tipadas se paginan. Una tarea de adquisición de datos recientes puede completarse mientras la consulta todavía tiene otra página.

Sin `--all-pages`, inspeccione `next_cursor`. Cuando existe una página siguiente, la CLI de alto nivel informa `partial_success` en lugar de reclamar un recorrido completo.

```bash
healthmd query --category Sleep --last 90 --all-pages
```

`--all-pages` sigue cursores opacos, comprueba si hay repeticiones y aplica un límite máximo de bytes y páginas agregadas. Si se alcanza el límite máximo, limite el alcance o utilice la API de bajo nivel para paginar manualmente. No hay un límite de resultado total oculto, pero cada invocación permanece acotada.

## Datos recientes, en caché y cobertura reutilizada

Los comandos de consulta de alto nivel adquieren datos recientes del iPhone de forma predeterminada:

```bash
healthmd query --metric resting_heart_rate --last 30
```

Usa datos almacenados en caché sólo cuando el contexto obsoleto sea aceptable:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Usa `--reuse-covered` para omitir la adquisición solo después de que Health.md verifique la cobertura resumida completa con reconocimiento de métricas para los días solicitados:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

El atajo de reutilización no se aplica a datos sin pérdida ni a operaciones recién proyectadas de sesiones de sueño. Nunca trata a un proveedor diferente o un blob obsoleto más antiguo como prueba de que esta solicitud se completó recientemente.

## Ejemplo de shell

Este ejemplo mantiene la carga útil de estado en un archivo protegido e imprime solo campos de estado seguro. Se supone que GNU `timeout` está instalado. Otros hosts de automatización deberían aplicar sus propios plazos de proceso.

```bash
#!/usr/bin/env bash
set -euo pipefail

output="${HOME}/Private/healthmd/sleep-week.json"
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"

set +e
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output "$output" \
  </dev/null > /tmp/healthmd-command.json
exit_code=$?
set -e

if [ -s /tmp/healthmd-command.json ]; then
  jq '{status, job_id, error, message}' /tmp/healthmd-command.json
fi

if [ "$exit_code" -ne 0 ]; then
  echo "healthmd did not report complete success" >&2
  exit "$exit_code"
fi
```

No habilite `set -x` alrededor de un comando que pueda transmitir JSON de estado o incluir rutas confidenciales.

## Comportamiento del agente tras un resultado desconocido

Un agente o planificador debe seguir este orden:

1. Lee el error estructurado y el ID de la tarea.
2. Ejecuta `status --job` localmente.
3. Comprueba si la tarea está en pausa, en estado terminal, caducada o a la espera de confirmación.
4. Vuelve a abrir el mismo iPhone cuando se necesiten datos recientes o una confirmación.
5. Reanuda la tarea existente con el mismo backend y dispositivo.
6. Inicia una tarea nueva solo después de conocer el resultado anterior o aceptar explícitamente su caducidad.

Reintentar una mutación a ciegas puede duplicar la tarea de origen incluso cuando las confirmaciones de archivos son idempotentes.

## Errores comunes legibles por máquina

| Código | Significado | Respuesta segura |
|---|---|---|
| `timed_out` | El comando dejó de esperar antes de que finalizara la tarea | Inspeccionar la tarea devuelta y reanudarla |
| `job_not_found` | No existe ningún registro persistente local para ese ID | Confirma el backend y el directorio de estado antes de empezar de nuevo |
| `job_expired` | Venció el plazo fijado de siete días | Registre la brecha y cree una nueva solicitud si corresponde |
| `direct_export_paused` | La tarea directa vuelve a necesitar el iPhone emparejado | Vuelve a abrir el iPhone y reanúdala |
| `direct_cancellation_pending` | La intención de cancelación local carece de reconocimiento del iPhone | Vuelve a abrir el iPhone e intenta cancelar de nuevo |
| `invalid_direct_raw_response` | Falló la validación estricta de los datos sin procesar | No uses la salida |
| `invalid_direct_file_receipt` | El manifiesto de archivo o el recibo de confirmación fallaron en la validación | No repare ni agregue archivos manualmente |
| `partial_canonical_extraction` | La extracción solicitada está incompleta | Inspeccionar el recibo; optar por parcial sólo cuando sea aceptado |
| `unvalidated_response_too_large` | Un resultado no puede exponerse bajo los límites de validación actuales | Restringir el alcance o utilizar un modo de salida apropiado |
| `stale_cursor` | El contexto cifrado cambió después de que se emitió el cursor de la página | Reinicia esa consulta con el corpus actual |

## Progreso sin registro de carga útil

Usa `--progress-json` para fases de consulta de alto nivel y recorrido de página:

```bash
healthmd query --category Sleep --last 30 \
  --all-pages --progress-json --output result.json \
  2> progress.jsonl
```

El progreso en JSONL puede incluir fases, recuento de páginas, recuento de elementos, fechas y diagnósticos seguros. No debe incluir valores de salud. Manténgalo separado del resultado final y aplique una política de retención adecuada de todos modos.

## Relacionado

<div class="related">
<a href="/es/docs/cli/"><span>Configuración</span>Health.md CLI: instale, elija un backend y comprenda la salida del comando.</a>
<a href="/es/docs/cli-direct/"><span>Directo</span> CLI directa de iPhone: emparejamiento, tiempo de fondo finito, destino explícito y reanudación fiable.</a>
<a href="/es/docs/agent-queries/"><span>Paginación</span>Libro de recetas de consultas tipadas: modos de datos recientes y en caché, recorrido de páginas, cobertura y recibos.</a>
<a href="/es/docs/reference/generated/cli/exit-codes/"><span>Contrato generado</span>CLI códigos de salida: estado generado en producción y comportamiento de error.</a>
</div>
