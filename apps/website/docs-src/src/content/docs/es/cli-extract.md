---
title: "Extracción de datos canónicos de salud"
description: "Usa healthmd extract para adquirir métricas seleccionadas de Apple Health y emitir documentos de esquema canónico v8, registros fuente, proyecciones de puntero JSON o JSONL con recibos explícitos."
---

`healthmd extract` es el comando de datos de origen para scripts y agentes. Le pide al iPhone que adquiera solo las métricas y los detalles seleccionados, valida la transferencia persistente, elimina el contenedor de transporte y emite documentos canónicos `healthmd.health_data` v8 o proyecciones claramente etiquetadas.

La extracción canónica es una capacidad de iPhone respaldada por el backend de la app de Mac y el protocolo directo v1 de iOS. Las fuentes directas de Android devuelven en su lugar instantáneas de Health Connect nativas del proveedor mediante la [exportación sin procesar](/es/docs/cli-direct/).

Usa la extracción cuando necesites datos originales de Health.md. Usa [consultas tipadas](/es/docs/agent-queries/) cuando necesites sesiones, comparaciones, alineación de ejercicios, cobertura o paquetes de evidencia.

## Forma básica

Una extracción necesita:

1. al menos una métrica, categoría, objeto o selector `--all-metrics`;
2. un selector de fecha;
3. opciones opcionales de detalle, objeto, campo, formato, salida, tiempo de espera y resultado parcial.

```bash
healthmd extract \
  (--metric ID | --category NAME | --object NAME | --all-metrics) ... \
  (--from DATE --to DATE | --last N | --yesterday | --all) \
  [--detail summary|lossless] \
  [--source apple_health] \
  [--field /JSON/POINTER] ... \
  [--format json|jsonl] \
  [--timeout 5...900] \
  [--allow-partial] \
  [--output PATH]
```

La fuente de extracción canónica actual es `apple_health`. Los datos auxiliares nativos del proveedor permanecen en sus propios contratos y no se traducen en valores sintéticos de Apple Health.

## Empieza con una solicitud acotada

```bash
# One category, one day, summary detail
healthmd extract --category Sleep --yesterday --output sleep.json

# One metric for the last 30 complete days
healthmd extract --metric resting_heart_rate --last 30 \
  --output resting-heart-rate.json

# Every selected source object for one exact range
healthmd extract --all-metrics \
  --from 2026-07-01 --to 2026-07-07 \
  --detail lossless --output health-week.json
```

Los nombres de métricas y categorías se validan con el catálogo actual antes de que comience la tarea en el iPhone. Repite los selectores para combinarlos.

```bash
healthmd extract \
  --metric sleep_total \
  --metric resting_heart_rate \
  --category Workouts \
  --last 14 --output recovery-context.json
```

## La selección ocurre antes de que HealthKit lea

La extracción no recupera una exportación de todas las métricas guardada y la recorta posteriormente. La CLI resuelve el selector en un `CanonicalHealthDataSelection` inmutable y lo envía al iPhone. Health.md comprueba y lee sólo los tipos de HealthKit normales que respaldan las métricas seleccionadas.

Esta distinción es importante para la privacidad, el rendimiento y la integridad:

- las métricas no seleccionadas no se adquieren;
- las preferencias métricas guardadas del iPhone no cambian;
- las solicitudes de resumen no crean un archivo fuente oculto;
- las solicitudes sin pérdidas recuperan sólo los tipos de fuentes necesarios para la selección;
- la selección pasa a formar parte de la huella digital de la solicitud persistente.

Los selectores de objetos y punteros JSON limitan los datos emitidos después de la captura. Los selectores de métricas, categorías, fuentes y detalles limitan la adquisición del iPhone en sí.

## Resumen y detalle sin pérdidas

El resumen es el valor predeterminado:

```bash
healthmd extract --category Activity --last 7 --detail summary
```

La salida de resumen puede incluir resúmenes diarios tipados, diagnósticos de consultas y `raw_capture_status: not_requested`. Ese estado es honesto: el comando no obtuvo registros fuente canónicos.

Solicita detalles sin pérdidas cuando los objetos de origen, los UUID, las marcas de tiempo exactas, la procedencia o los diagnósticos de archivos sean importantes:

```bash
healthmd extract --metric workouts --last 14 \
  --detail lossless --output workouts-lossless.json
```

Los objetos orientados al archivo como `records` implican detalles sin pérdida incluso si se omite `--detail`.

## Selectores de objetos

Usa `--object` para conservar una parte conocida de cada día seleccionado. Los nombres actuales incluyen:

| Objeto | Contenidos típicos |
|---|---|
| `sleep` | Campos de resumen del sueño diario |
| `activity` | Resúmenes de pasos, energía, distancia, ejercicio y actividades relacionadas |
| `heart` | Frecuencia cardíaca, frecuencia cardíaca en reposo, VFC y resúmenes relacionados |
| `vitals` | Presión arterial, glucosa, temperatura, oxígeno y otros resúmenes vitales |
| `body` | Peso, composición, altura y medidas corporales |
| `nutrition` | Resúmenes de nutrientes e hidratación |
| `mindfulness` | Sesiones de mindfulness y resúmenes de bienestar mental |
| `mobility` | Campos sobre caminar, la marcha y la movilidad |
| `hearing` | Exposición de audio y campos auditivos |
| `reproductive-health` | Campos reproductivos, del embarazo y del ciclo |
| `cycling` | Resúmenes de ciclismo |
| `vitamins` / `minerals` | Resúmenes específicos de nutrientes |
| `symptoms` | Datos de síntomas |
| `medications` | Datos de medicación cuando estén disponibles y autorizados |
| `workouts` | Objetos de resumen de entrenamiento canónicos |
| `archive` | Contenedor de archivo canónico de HealthKit |
| `records` | Registros fuente canónicos; implica detalles sin pérdidas |
| `external-records` | Registros externos ya presentes en el día público |
| `query-results` | Resultados de captura por consulta |
| `warnings` | Advertencias de integridad |

Ejemplos:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --output workout-summaries.json

healthmd extract --metric workouts --last 30 \
  --object records --detail lossless --output workout-records.json

healthmd extract --category Sleep --last 7 \
  --object sleep --object query-results --output sleep-with-status.json
```

## Proyección de puntero JSON

Repita `--field` con punteros JSON RFC 6901 para emitir valores exactos o entradas de estado:

```bash
healthmd extract --category Sleep --last 7 \
  --field /sleep/totalDuration \
  --field /sleep/deepSleep \
  --field /raw_capture_status \
  --output selected-sleep-fields.json
```

Los resultados de los punteros son proyecciones, no documentos diarios completos. Hacen referencia al esquema de origen y al día, pero no incluyen `schema: healthmd.health_data` de una manera que pueda hacer que un subárbol parezca una exportación completa.

Una ruta seleccionada ausente se informa con el estado completo-vacío o incompleto del día. Health.md no convierte la ausencia en cero.

## Salida JSON

La salida JSON predeterminada contiene una de estas colecciones de datos:

- `health_data` para documentos diarios canónicos completos; o
- `projections` para resultados de objetos o punteros.

También contiene `healthmd.extract_receipt`, que registra:

- selección resuelta y rango de fechas;
- fuente y nivel de detalle;
- resultados por día;
- recuentos de elementos retenidos y capturas;
- fechas ausentes;
- diagnóstico parcial o de fallo;
- estado de finalización de la salida.

El recibo son metadatos de protocolo. No reemplaza el esquema fuente.

## Salida JSONL

Usa JSONL para procesar flujos de datos:

```bash
healthmd extract --category Sleep --last 30 \
  --format jsonl --output sleep.jsonl
```

Cada línea es un elemento de datos. El recibo no se mezcla con el flujo de datos de salud:

- con `--output`, se escribe en `OUTPUT.receipt.json`;
- sin `--output`, se escribe en stderr.

Esto hace que las tuberías sean predecibles:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --format jsonl --output workouts.jsonl

jq -c 'select(.workouts != null)' workouts.jsonl
jq '{status, retained_item_count, missing_dates}' workouts.jsonl.receipt.json
```

No canalices stderr hacia el analizador JSONL, porque stderr contiene el recibo y el progreso sin datos de salud.

## Resultados completos, vacíos y parciales

Health.md mantiene estos estados distintos:

| Estado | Significado |
|---|---|
| `success` | Todas las ramas solicitadas se completaron, incluidas las que estaban completamente vacías |
| `complete_empty` | El alcance solicitado estaba representado y no contenía observaciones |
| `partial_success` | Se conservan algunos datos solicitados, pero al menos una rama solicitada está incompleta |
| `failed` | Una rama solicitada produjo un error |
| `unsupported` | La plataforma o HealthKit no admite la rama solicitada |
| `skipped` | Health.md omitió deliberadamente la consulta de esa rama |
| `cancelled` | El iPhone confirmó la cancelación |
| `missing` | Un día o una rama solicitados no estaban representados |

Una extracción parcial no emite datos retenidos de forma predeterminada. Añade `--allow-partial` solo cuando el consumidor pueda aceptar y conservar un alcance incompleto:

```bash
healthmd extract --category Sleep --last 30 \
  --allow-partial --output sleep-partial.json
```

La bandera cambia el comportamiento de emisión y salida. No elimina diagnósticos ni convierte datos parciales en datos completos.

## Aplicación Mac y backends directos

El comando funciona a través de cualquiera de los backends:

```bash
# Bundled helper default: Mac app loopback and connected iPhone
healthmd extract --category Sleep --last 7 --output sleep.json

# Direct-capable helper: bypass the Mac app
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json
```

Ambas rutas utilizan el mismo esquema diario público y una validación estricta. Los registros de transporte, emparejamiento, almacenamiento y tareas son distintos. Ambas rutas requieren una fuente de iPhone; el backend directo de Android no implementa la extracción canónica.

## Historial extenso

`--all` no tiene límite de fecha fija:

```bash
healthmd extract --metric steps --all --output all-steps.json
```

El iPhone resuelve el registro seleccionado más antiguo disponible, fija cada día del calendario de origen hasta el día de hoy y transfiere particiones acotadas. La CLI ensambla y valida en el disco en lugar de crear una respuesta ilimitada en memoria.

Usa JSONL o una selección más acotada cuando un corpus sea grande. El espacio disponible en disco y un día inusualmente denso siguen siendo límites prácticos.

## Lista de verificación de privacidad

- Usa preferentemente `--output` para cualquier resultado que contenga datos de salud.
- Protege los archivos de salida y de recibo con el mismo cuidado que la fuente de Apple Health.
- No actives el seguimiento del shell al ejecutar comandos de salud.
- Mantén las cargas útiles fuera de los registros de CI y de las transcripciones de los agentes.
- Al solucionar problemas, inspecciona únicamente los campos de recibo, recuento, estado, esquema y ausencia de datos.
- Elimina las exportaciones temporales después de que el consumidor previsto las confirme de forma segura.

## Relacionado

<div class="related">
<a href="/es/docs/cli/"><span>CLI</span>Health.md CLI: configuración, selección de backend, mapa de comandos y reglas de salida.</a>
<a href="/es/docs/agent-queries/"><span>Vistas derivadas</span>Libro de recetas de consultas tipadas: series de métricas, sueño, entrenamiento, entrenamientos, comparaciones y evidencia.</a>
<a href="/es/docs/reference/daily-records/"><span>Esquema</span>Registros diarios: el contrato de documento diario completo del esquema-v8.</a>
<a href="/es/docs/reference/canonical-healthkit-records/"><span>Archivo fuente</span>Registros canónicos de Apple Health: identidad, procedencia, relaciones y cargas útiles.</a>
<a href="/es/docs/reference/api-and-cli/"><span>Protocolo</span>Referencia de API y CLI: solicitudes de extracción, recibos, validación estricta y comportamiento de salida.</a>
</div>
