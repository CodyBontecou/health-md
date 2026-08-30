---
title: "Health.md CLI"
description: "Elige la aplicación para Mac o el backend directo del teléfono, empareja healthmd con un iPhone o un dispositivo Android, comprueba la disponibilidad, exporta archivos, extrae datos canónicos de Apple Health, ejecuta consultas tipadas y automatiza tareas persistentes."
---

El comando `healthmd` tiene dos modos de funcionamiento. Usa el backend de la aplicación para Mac cuando quieras consultas locales cifradas, herramientas MCP o la carpeta de destino ya seleccionada en Health.md para Mac. Usa el backend directo del teléfono cuando quieras datos sin procesar o archivos generados sin ejecutar la aplicación Mac. El modo directo se empareja con una aplicación Health.md abierta en iPhone (protocolo v1) o Android (protocolo v2).

<div class="callout">
<strong>Los datos de salud permanecen en tu teléfono.</strong>
<p style="margin-top:6px;">Ninguno de los backends CLI lee Apple Health ni Health Connect desde la computadora. Una aplicación Health.md abierta y actual en iPhone o Android realiza cada nueva lectura de salud de la plataforma. La CLI recibe resultados o archivos validados.</p>
</div>

## Elige un backend

| Capacidad | Backend de la aplicación Mac | Backend directo de teléfono |
|---|---|---|
| Predeterminado en el asistente de Mac incluido | Sí | No, seleccione con `--backend direct` |
| Dispositivos de origen | iPhone | iPhone (protocolo v1) o Android (protocolo v2) |
| Necesita abrir Health.md para Mac | Sí | No |
| Necesita la aplicación Health.md del teléfono abierta para datos nuevos | Sí | Sí |
| Destino del archivo | Carpeta seleccionada en la aplicación Mac | `--destination` absoluto existente |
| Exportación estricta de datos sin procesar | Sí | Sí; instantáneas nativas del proveedor Health Connect en Android |
| `healthmd extract` canónico | Sí | Solo iPhone |
| Contexto cifrado, consultas tipadas y evidencia | Sí | Solo iPhone, cliente portátil |
| `healthmd-mcp` | Sí | No |
| Manual IP o Tailscale | Sincronización de Mac o modo directo explícito | Sí |
| Transporte directo Nearby | Solo el asistente Swift incluido | No disponible en el cliente portátil de Rust |

Las opciones de backend y transporte nunca retroceden silenciosamente. Un comando directo no puede cambiar a la aplicación Mac para satisfacer una consulta y una conexión Nearby fallida no puede cambiar a Manual IP.

## Instalar los asistentes incluidos para Mac

<div class="availability available">
<strong>Disponible ahora · Health.md para Mac</strong>
<p>Los asistentes firmados de la CLI y MCP para Swift se envían dentro de la aplicación Mac lanzada.</p>
</div>

Health.md para Mac incluye los asistentes firmados `healthmd` y `healthmd-mcp`. Abre la aplicación para Mac y selecciona **CLI** para ver las rutas de su copia instalada, los comandos de configuración, las indicaciones del agente y el instalador de habilidades del agente opcional.

Las rutas normales del paquete de aplicaciones son:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Usa alias para una sesión de shell:

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

O cree enlaces simbólicos persistentes en un directorio de binarios propiedad del usuario:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

Añade `~/.local/bin` a `PATH` si tu shell aún no lo incluye:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Comprueba la CLI sin iniciar el bucle stdio de MCP:

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` devuelve `healthmd.cli_doctor` JSON con Mac, contexto cifrado y disponibilidad del iPhone. No imprime valores de salud.

## Estado de la CLI portátil

<div class="availability preview">
<strong>Vista previa · aún no empaquetado públicamente</strong>
<p>La CLI de Rust multiplataforma espera el control de calidad del lanzamiento físico del iPhone y su primer paquete calificado.</p>
</div>

Una CLI de Rust independiente está en desarrollo en `0.1.0-alpha.1`. Se ejecuta en macOS, Linux y Windows, utiliza conexiones directas mediante Manual IP o Tailscale de forma predeterminada y no necesita la aplicación para Mac. Se empareja con fuentes iPhone mediante el protocolo v1 y con fuentes Android mediante el protocolo v2, con controles automáticos de compatibilidad Swift↔Rust y Kotlin↔Rust. La compatibilidad de protocolos está implementada, pero el control de calidad del lanzamiento en dispositivos físicos y el empaquetado público aún deben finalizar antes del primer lanzamiento público.

Hasta que exista esa versión, utilice el asistente para Mac incluido. No confíe en Homebrew, crates.io, instalador de GitHub o URL de descarga no publicados.

El cliente portátil admite emparejamiento, estado, exportación sin procesar, destinos de archivos generados, reanudación y cancelación en las tres plataformas de escritorio, tanto para fuentes iPhone como Android. La extracción canónica y las consultas MCP tipadas son capacidades de iPhone; las instantáneas sin procesar de Android conservan su contrato nativo del proveedor Health Connect en lugar de convertirse en datos con forma de HealthKit, y las consultas tipadas de Android no están implementadas. Para la exportación de archivos generados, el teléfono trata el destino como una etiqueta de destino opaca mientras la CLI receptora lo valida y lo vincula de forma persistente al sistema de archivos del host. El protocolo v2 de Android confirma los destinos de archivos en todos los sistemas operativos de la CLI y limita cada tarea generada a 4096 archivos; el protocolo v1 de iOS rechaza los destinos de archivos en Windows.

## Mapa de comando

| Comando | Propósito | Backend |
|---|---|---|
| `healthmd status` | Comprobar la disponibilidad en directo o inspeccionar una tarea local persistente | Ambos |
| `healthmd doctor` | Explicar el estado del Mac, del contexto cifrado y del iPhone | Aplicación para Mac |
| `healthmd metrics list` | Devolver el catálogo canónico de métricas consultables | Aplicación para Mac |
| `healthmd extract` | Adquirir objetos `healthmd.health_data` canónicos seleccionados | Ambos, fuente iPhone |
| `healthmd query` | Adquirir y consultar métricas tipadas seleccionadas | Aplicación para Mac |
| `healthmd sleep sessions` | Devolver sesiones de sueño de primera clase y ventanas fijas | Aplicación para Mac |
| `healthmd training align` | Alinear los entrenamientos con el sueño previo y posterior | Aplicación para Mac |
| `healthmd workouts` | Enumerar entrenamientos tipados con evidencia | Aplicación para Mac |
| `healthmd coverage` | Inspeccionar la cobertura de fechas y métricas o la ausencia de datos | Aplicación para Mac |
| `healthmd compare` | Comparar períodos exactos con la agregación seleccionada por quien realiza la llamada | Aplicación para Mac |
| `healthmd evidence training` | Crear un paquete de evidencia factual sobre el entrenamiento | Aplicación para Mac |
| `healthmd export` | Escribir archivos generados o devolver JSON estricto sin procesar | Ambos |
| `healthmd resume` | Reanudar una tarea de exportación persistente e inmutable | Ambos |
| `healthmd cancel` | Solicitar cancelación explícita | Ambos |
| `healthmd agent ...` | Llamar a la API de bajo nivel para consultas de loopback y tareas | Aplicación para Mac |
| `healthmd direct ...` | Emparejar, enumerar y eliminar la confianza directa del teléfono | Directo |

Los comandos directos se emparejan con fuentes iPhone (protocolo v1) o Android (protocolo v2). La extracción canónica `extract` y todos los comandos de consulta tipada son capacidades de iPhone; el backend directo de Android devuelve instantáneas sin procesar nativas del proveedor Health Connect y archivos generados.

## Primer flujo de trabajo de la aplicación Mac

1. Abre Health.md en el Mac y selecciona una carpeta de destino si tienes previsto escribir archivos.
2. Abre Health.md en el iPhone emparejado y espera a que se conecte con el Mac.
3. Comprueba la disponibilidad.
4. Ejecuta un comando pequeño antes de solicitar un historial grande.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

Las consultas de datos recientes adquieren solo las métricas, fuentes, fechas y detalles resumidos o sin pérdidas proporcionados. No cambian la configuración de exportación guardada del iPhone.

## Exportaciones de archivos y sin procesar

```bash
# Use the Mac app's selected destination
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --all

# Return strict lossless canonical JSON without writing export files
healthmd export --iphone --yesterday --raw --output yesterday.json
healthmd export --iphone --all --raw --output complete-health-corpus.json

# Replace saved metric scope for this one file job
healthmd export --iphone --last 7 --category Sleep --detail summary

# Mirror saved iPhone settings, including roll-ups
healthmd export --iphone --yesterday --use-iphone-settings

# Run a saved export profile by UUID (frozen settings + destination)
healthmd export --iphone --last 7 --profile 11111111-2222-4333-8444-555555555555
```

`--profile PROFILE_ID` resuelve un perfil de exportación guardado en el iPhone por su UUID estable: la ejecución usa la selección de métricas, los formatos y el destino congelados de ese perfil en lugar de los ajustes activos de la app. No se puede combinar con `--use-iphone-settings` ni con selectores de métrica/categoría (el perfil es el dueño del alcance de ajustes), y un UUID desconocido falla con un error tipado `profile_not_found` en lugar de recurrir a los ajustes activos. Consulta el UUID en el selector de perfiles de la pestaña Exportar de la app.

Actualmente no existe un límite de días calendario. `--all` le pide al iPhone que descubra el registro fuente seleccionado más antiguo disponible, fija el rango resuelto y lo procesa a través de particiones acotadas. El almacenamiento disponible y un día inusualmente denso siguen siendo límites prácticos.

`--raw` solicita temporalmente registros fuente canónicos sin pérdidas sin cambiar la preferencia del iPhone. No escribe archivos generados y no incluye datos auxiliares de los proveedores conectados.

## ¿Extracción canónica o consulta derivada?

Usa `extract` cuando necesite datos en forma de fuente:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Usa un comando de consulta cuando necesite una vista tipada y vinculada a evidencia:

```bash
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v7 es el contrato de fuente pública. Los esquemas de consulta, evidencia, tarea y recibo describen vistas de transporte o derivadas. No reemplazan el esquema fuente. La extracción canónica es una capacidad de iPhone; las fuentes directas de Android exponen instantáneas sin procesar nativas del proveedor Health Connect a través de la exportación sin procesar.

## Comportamiento legible por máquina

Los comandos utilizan JSON versionado en la salida estándar o en la ruta `--output` explícita de forma predeterminada. La extracción canónica puede optar por JSONL y las consultas de alto nivel pueden optar por una tabla con pérdidas deliberadamente. El progreso sin salud puede usar stderr. `--help` es texto sin formato. Los errores de argumento antes de que se inicie un comando son texto sin formato en stderr con código de salida 2.

Una salida exitosa del proceso no es suficiente para demostrar datos de salud completos. Controlar:

- el estado externo;
- el estado del alcance solicitado;
- resultados por día y por consulta;
- intervalos ausentes;
- `next_cursor` o el recibo del recorrido;
- esquema fuente y versión;
- limitaciones y advertencias.

Un resultado completamente vacío significa que Health.md representó el alcance solicitado y no encontró observaciones. No es lo mismo que cero, faltante, fallido, omitido o no admitido.

## Automatización segura

Usa el tiempo de espera del proceso de tu host de automatización y mantén la entrada estándar cerrada para los comandos que no deberían aparecer. En sistemas con GNU `timeout`:

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd doctor </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

El tiempo de espera, Ctrl-C, la salida del proceso, la pérdida de red y el agotamiento del tiempo de ejecución en segundo plano de iOS no cancelan una tarea persistente. Inspecciona el ID de la tarea y reanúdala en lugar de iniciar un duplicado.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

La cancelación solo pasa a un estado terminal cuando el iPhone la confirma.

## Reglas de privacidad

La salida sin procesar y sin pérdidas puede contener marcas de tiempo exactas, rutas, registros clínicos, medicamentos, entradas de estado de ánimo, valores de ECG, procedencia y archivos adjuntos. Prefiere un archivo de salida a la salida del terminal. No pegue cargas útiles en informes de problemas, transcripciones de agentes, registros de CI o seguimientos de shell.

La API de consulta local no tiene token de portador, registro, perfil de acceso ni base de datos de concesiones. La accesibilidad del loopback es su límite de acceso completo. Cualquier proceso local puede usarlo mientras la aplicación Mac está abierta, por lo que nunca haga proxy ni exponga el puerto `17645` a otra máquina.

## Próximas guías

<div class="related">
<a href="/es/docs/cli-direct/"><span>Sin aplicación para Mac</span>CLI directa de teléfono: empareja con iPhone o Android, repasa los transportes, las exportaciones sin procesar y de archivos, el comportamiento en segundo plano y la compatibilidad con plataformas.</a>
<a href="/es/docs/cli-extract/"><span>Datos de origen</span>Extracción canónica: selección de métricas, objetos, detalles, punteros JSON, JSONL y recibos.</a>
<a href="/es/docs/cli-jobs/"><span>Automatización</span>Tareas persistentes: tiempos de espera, reanudación, cancelación, resultados parciales y secuencias de comandos seguras.</a>
<a href="/es/docs/agents/"><span>Agentes</span>Flujos de trabajo de agentes locales: contexto cifrado, alcance directo, comandos tipados y evidencia.</a>
<a href="/es/docs/mcp/"><span>MCP</span>Configura el asistente stdio en un entorno aislado y revisa los límites de sus herramientas.</a>
<a href="/es/docs/reference/api-and-cli/"><span>Contrato</span>Referencia de API y CLI: rutas exactas, esquemas, respuestas y fixtures generados.</a>
</div>
