---
title: "Libro de recetas de consultas tipadas"
description: "Ejecuta consultas de Health.md sobre métricas, sueño, entrenamiento, ejercicios, cobertura, comparación de períodos y evidencia, con datos recientes o en caché, paginación explícita y representación de datos ausentes."
---

Los comandos de alto nivel de la CLI convierten preguntas habituales sobre datos de salud en operaciones de consulta fijas y tipadas. De forma predeterminada, adquieren del iPhone los datos solicitados, consultan el contexto cifrado del Mac y devuelven JSON versionado con evidencia y cobertura.

Usa [extracción canónica](/es/docs/cli-extract/) en su lugar cuando necesites días `healthmd.health_data` completos o registros de origen.

## Comprueba la disponibilidad y descubre métricas

```bash
healthmd doctor
healthmd metrics list
healthmd metrics list --category Sleep
```

El catálogo de métricas devuelve ID canónicos, nombres para mostrar, categorías, unidades y requisitos de disponibilidad. No afirma que se haya concedido la autorización de HealthKit para una métrica.

Copia los ID del catálogo en lugar de intentar adivinarlos.

## Consultar serie de métricas

```bash
healthmd query \
  --metric sleep_total \
  --metric sleep_deep \
  --from 2026-07-01 --to 2026-07-14 \
  --all-pages
```

Las categorías se amplían a través del catálogo actual:

```bash
healthmd query --category Sleep --yesterday
healthmd query --category Heart --last 30 --all-pages
```

Se combinan varias opciones de métricas y categorías. La adquisición de datos recientes envía la selección ampliada al iPhone sin cambiar la configuración de exportación guardada.

La respuesta utiliza un sobre `healthmd.cli_metric_query` v1. Mantiene los diagnósticos de adquisición junto con la respuesta de consulta tipada anidada.

## Datos recientes, en caché y reutilización de la cobertura

El modo de datos recientes es el predeterminado:

```bash
healthmd query --metric resting_heart_rate --last 30
```

Esto solicita el alcance exacto del iPhone conectado, confirma los días de propietario cifrados y actualizados y luego los consulta.

El modo en caché no contacta con el iPhone:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Usa el modo en caché para el análisis fuera de línea solo cuando el tiempo de captura almacenado y la cobertura sean aceptables.

`--reuse-covered` comprueba primero la cobertura del resumen cifrado:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

Health.md omite la adquisición solo cuando cada métrica y día solicitados tienen una cobertura resumida compatible completa. Las solicitudes sin pérdidas y las operaciones recién proyectadas de sesiones de sueño no utilizan este atajo.

## Comprender los campos de finalización

Las respuestas a consultas de datos recientes distinguen tres conceptos:

| Campo | Pregunta respondida |
|---|---|
| `requested_scope_status` | ¿Se completaron todos los días de métrica, fuente, proveedor y propietario solicitados para esta adquisición? |
| `corpus_status` | ¿Otras ramas del corpus capturado informaron advertencias, omisiones o fallas? |
| `unrelated_skips` | ¿Qué ramas omitidas o no admitidas estaban fuera del alcance solicitado? |

Un alcance solicitado completo puede coexistir con omisiones no relacionadas en el corpus. Health.md conserva ambos datos en lugar de degradar falsamente el resultado solicitado u ocultar los diagnósticos del corpus.

Para las operaciones con datos recientes, solo cuentan como completados los blobs reemplazados después de iniciarse la actualización. Los valores almacenados en caché obsoletos no pueden satisfacer una solicitud fallida.

## Paginar los resultados

Sin `--all-pages`, el comando devuelve una página acotada. Comprueba `next_cursor`:

```bash
healthmd query --category Activity --last 365 --output activity-page-1.json
jq '.query.next_cursor' activity-page-1.json
```

Un cursor no nulo significa que existen más resultados. El estado externo de alto nivel permanece `partial_success` hasta que se completa el recorrido.

El recorrido automático sigue cursores opacos y comprueba que no se repitan:

```bash
healthmd query --category Activity --last 365 \
  --all-pages --output activity-all-pages.json
```

La respuesta mantiene el primer `healthmd.query_response` en `query`, las respuestas con versiones posteriores en `pages` y un `healthmd.cli_query_receipt` v1 que contiene recuentos de páginas, elementos, hechos y evidencias, además del estado final del recorrido.

El recorrido automático tiene un límite máximo de bytes y páginas agregadas. Si se alcanza, limite la fecha o la selección de métricas o use el [API](/es/docs/agent-api/) de bajo nivel para buscar manualmente.

## Progreso y salida en forma de tabla

Escribe en stderr, como JSONL, el progreso de las fases que no contienen datos de salud y de las páginas:

```bash
healthmd query --category Sleep --last 90 \
  --all-pages --progress-json --output sleep.json \
  2> sleep-progress.jsonl
```

JSON es el resultado completo. El modo de tabla es una vista TSV con pérdida opcional para una persona en una terminal:

```bash
healthmd query --metric resting_heart_rate --last 30 --format table
```

El pie de página de la tabla conserva la cobertura, la fuente, la limitación, la finalización y las notas de omisión no relacionadas. No utilices la salida en forma de tabla cuando un script necesite evidencia o valores tipados exactos.

## Sesiones de sueño

Las etapas del sueño de Apple Health cruzan la medianoche y pueden superponerse según la fuente. El comando de sueño crea sesiones estables en lugar de tratar cada día del propietario como un total numérico.

```bash
healthmd sleep sessions --last-nights 14
healthmd sleep sessions --last-nights 14 --include-naps
healthmd sleep sessions --last-nights 14 \
  --window first:4h --physiology-metric heart_rate
```

Las fechas exactas y la selección de todo el historial también están disponibles:

```bash
healthmd sleep sessions \
  --from 2026-07-01 --to 2026-07-14 \
  --window first:3h --all-pages

healthmd sleep sessions --all --all-pages
```

Cada sesión puede informar:

- identidad de sesión estable;
- fecha del propietario y zona horaria local;
- marcas de tiempo exactas de inicio y finalización locales y UTC;
- clasificación como sueño nocturno o siesta;
- totales de etapas seleccionadas;
- duración observada y sin seguimiento;
- integridad y exclusiones;
- ventana fija relativa a la sesión;
- cobertura de fisiología del día adyacente;
- fuente de evidencia.

La adquisición de sesiones solicita intervalos canónicos y sin pérdidas de etapas del sueño y el conjunto completo de métricas de etapas canónicas. Health.md lee como máximo un día técnico de propietario adyacente para los límites y luego excluye las fechas no relacionadas del resultado.

Las fuentes de etapas que se solapan se deduplican para calcular la duración total del sueño. El contexto almacenado en caché de solo agregado tiene la etiqueta `aggregated`; no reclama cobertura de observación de intervalo. Una ventana `first:4h` fija nunca distribuye un agregado diario en cuatro horas.

## Alineación del entrenamiento y el sueño

```bash
healthmd training align --last 14
healthmd training align --last 14 --workout running
healthmd training align --last 14 --workout running \
  --sleep-window first:4h \
  --physiology-metric heart_rate \
  --all-pages
```

Para cada entrenamiento seleccionado, Health.md encuentra las sesiones de sueño anteriores y posteriores elegibles más cercanas dentro de las 36 horas. Informa:

- ID de sesión y entrenamiento estables;
- intervalos de tiempo exactos;
- ventanas para dormir solicitadas;
- recuentos de muestras de fisiología;
- cobertura de etapas y de la sesión;
- evidencia y exclusiones.

La operación es de alineación temporal determinista. No afirma que un entrenamiento haya causado un resultado de sueño o que el sueño haya causado un rendimiento en el entrenamiento. No lee más de dos días técnicos de propietario adyacentes y no devuelve datos no relacionados.

## Lista de entrenamientos

```bash
healthmd workouts --yesterday
healthmd workouts --last 14 --all-pages
healthmd workouts \
  --from 2026-07-01 --to 2026-07-31 \
  --format table
```

La lista de entrenamientos conserva la identidad estable, las marcas de tiempo exactas, los detalles tipados, la evidencia y la representación de datos ausentes. Los resultados se ordenan por marca de tiempo de inicio e identidad estable del entrenamiento. No hay un límite total fijo de entrenamientos; los controles de página acotan cada respuesta.

## Cobertura

Usa la cobertura cuando la pregunta sea "¿Qué tengo?" en lugar de "¿Cuál es el valor?"

```bash
healthmd coverage --category Sleep --last 30
healthmd coverage \
  --metric steps --metric resting_heart_rate \
  --from 2026-01-01 --to 2026-06-30 \
  --all-pages
```

La cobertura devuelve rangos solicitados y disponibles, días considerados, días con valores e intervalos de ausencia con su estado. Los intervalos adyacentes con el mismo estado y motivo se pueden comprimir sin perder significado.

Un día sin observaciones coincidentes puede ser `complete_empty`. Un día que nunca se sincronizó tiene un estado diferente. Ninguno de los dos se vuelve cero.

## Comparar períodos exactos

La CLI nunca adivina si una métrica se debe sumar, promediar, minimizar, maximizar, contar o seleccionar según el último valor. Coloque la agregación al lado de cada ID de métrica:

```bash
healthmd compare \
  --metric steps:sum \
  --metric resting_heart_rate:average \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

Las agregaciones admitidas son:

- `sum`
- `average`
- `minimum`
- `maximum`
- `latest`
- `count`
- `duration_sum`

Las discrepancias entre unidades o tipos producen un error en lugar de combinarse de forma silenciosa. Un período faltante no tiene valor agregado. Una línea base cero en el primer período tiene un cambio absoluto pero ningún cambio porcentual e incluye `zero_baseline` como limitación.

La dirección es objetiva: `increased`, `decreased`, `unchanged` o `not_comparable`. Nunca significa mejor o peor.

## Paquetes de evidencia de entrenamiento

```bash
healthmd evidence training \
  --category Sleep \
  --metric resting_heart_rate \
  --last 14 \
  --all-pages
```

Solicita detalles de entrenamiento específicos solo cuando sea necesario:

```bash
healthmd evidence training \
  --category Sleep \
  --workout-detail distance \
  --workout-detail duration \
  --last 14 --all-pages
```

Al seleccionar los detalles del entrenamiento se solicita el alcance sin pérdidas requerido para esa solicitud. El paquete contiene valores fácticos, cobertura, descriptores de fuentes, localizadores de evidencia y limitaciones.

Los ID de los paquetes son resúmenes SHA-256 deterministas del contenido semántico. Si se vuelve a generar el mismo paquete en otro momento, se conserva el ID semántico aunque los metadatos de generación puedan cambiar.

Los tipos de paquetes de evidencia en el contrato v1 incluyen `daily_wellness`, `training` y `doctor_visit`. El comando de conveniencia de alto nivel actualmente expone el paquete de entrenamiento. Usa la API de bajo nivel para cuerpos de solicitud exactos.

## Fecha de propiedad y zona horaria

Las fechas de consulta son valores `owner_date` de contexto compacto. Cada día también conserva el intervalo UTC semiabierto exacto y la zona horaria capturada del calendario de la IANA utilizada para formarlo.

Las sesiones de sueño mantienen marcas de tiempo locales y fechas pasadas la medianoche. Existen lecturas técnicas adyacentes para que una sesión pueda cruzar el límite del día del propietario sin mover datos según la zona horaria actual de la Mac.

Cuando le haga a un agente una pregunta sobre fechas sensibles, incluya las fechas del propietario previsto e inspeccione la zona horaria devuelta en lugar de asumir la zona horaria de la computadora.

## No ocultes los datos ausentes en la respuesta de un agente

Un resumen seguro debe contener:

- ID de métrica y unidad canónica;
- rango de fechas y zona horaria;
- modo de datos recientes, en caché o con reutilización de la cobertura;
- alcance solicitado y estado del corpus;
- finalización del recorrido de la página;
- referencias de evidencia o resumen de fuentes;
- intervalos completamente vacíos y ausentes;
- advertencias, limitaciones y omisiones no relacionadas.

No promedies los días fallidos, no trates la ausencia como cero ni describas la alineación temporal como una causa.

## Relacionado

<div class="related">
<a href="/es/docs/agents/"><span>Arquitectura</span>Agentes locales y contexto de salud: configuración, cifrado, alcance de la solicitud, evidencia y retención.</a>
<a href="/es/docs/mcp/"><span>MCP</span>El asistente de MCP local: equivalentes tipados para consulta, sueño, alineación, entrenamientos, cobertura, comparación y evidencia.</a>
<a href="/es/docs/agent-api/"><span>Contratos sin procesar</span>La API de consulta de loopback: solicitudes exactas, respuestas de una página, actualización y rutas de trabajo.</a>
<a href="/es/docs/reference/evidence-packets/"><span>Referencia</span>Consultas compactas y paquetes de evidencia: valores tipados, cursores, operaciones, cobertura e ID.</a>
</div>
