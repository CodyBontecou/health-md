---
title: "Health.md CLI"
description: "Instala la CLI independiente healthmd en macOS, Linux o Windows, empárela directamente con un iPhone o un dispositivo Android, comprueba la disponibilidad, exporta datos, ejecuta consultas y gestiona tareas persistentes. No requiere la aplicación para Mac."
---

La CLI independiente `healthmd` funciona en macOS, Linux y Windows y se empareja directamente con una aplicación Health.md abierta en iPhone (protocolo v1) o Android (protocolo v2). Nunca requiere la aplicación Health.md para Mac, no tiene selección de backend y nunca lee Apple Health ni Health Connect desde la computadora.

<div class="callout">
<strong>Los datos de salud permanecen en tu teléfono.</strong>
<p style="margin-top:6px;">La CLI nunca lee Apple Health ni Health Connect desde la computadora. Una aplicación Health.md abierta y actual en iPhone o Android realiza cada nueva lectura de salud de la plataforma. La CLI recibe resultados o archivos validados.</p>
</div>

## Instalar la CLI independiente

<div class="availability preview">
<strong>Vista previa pública · aún sin versión estable calificada</strong>
<p>La CLI multiplataforma de Rust está empaquetada públicamente, pero su matriz móvil exacta aún espera la calificación física de lanzamiento.</p>
</div>

En macOS o Linux, instala la vista previa con <code>brew install CodyBontecou/tap/healthmd</code>. Usa la compilación móvil exacta indicada por la evidencia de lanzamiento; la publicación del paquete no demuestra compatibilidad móvil.

La CLI independiente de Rust funciona en macOS, Linux y Windows, usa conexiones directas Manual IP o Tailscale y no necesita la aplicación para Mac. Se empareja con fuentes iPhone mediante el protocolo v1 y con fuentes Android mediante el protocolo v2, con verificaciones automatizadas de compatibilidad Swift↔Rust y Kotlin↔Rust. La compatibilidad de protocolo está implementada; la QA de lanzamiento en dispositivos físicos debe completarse antes de la primera versión estable calificada. Archivos con suma de verificación, un instalador de PowerShell y `cargo install healthmd-cli --locked` acompañan cada lanzamiento.

El cliente portátil admite emparejamiento, estado, exportación sin procesar, destinos de archivos generados, reanudación y cancelación en las tres plataformas de escritorio para iPhone y Android. La extracción canónica y las consultas MCP tipadas son capacidades de iPhone. Las instantáneas sin procesar de Android conservan su contrato nativo del proveedor Health Connect en lugar de convertirse en datos con formato HealthKit. Las consultas tipadas de Android no están implementadas. Para la exportación de archivos generados, el teléfono trata el destino como una etiqueta opaca. La CLI receptora lo valida y lo vincula duraderamente al sistema de archivos del host. El protocolo Android v2 confirma destinos de archivos en todos los sistemas operativos de la CLI y limita cada trabajo generado a 4.096 archivos.

## Mapa de comando

| Comando | Propósito |
|---|---|
| `healthmd status` | Inspeccionar disponibilidad en vivo o una tarea local persistente |
| `healthmd export` | Escribir archivos generados o devolver JSON sin procesar estricto |
| `healthmd extract` | Adquirir objetos canónicos `healthmd.health_data` seleccionados (iPhone) |
| `healthmd query` | Ejecutar operaciones de consulta tipadas fijas (iPhone) |
| `healthmd resume` | Reanudar una tarea de exportación persistente inmutable |
| `healthmd cancel` | Solicitar cancelación explícita |
| `healthmd direct ...` | Emparejar, listar y eliminar confianza directa del teléfono |
| `healthmd mcp ...` | Servir o inspeccionar la superficie fija de herramientas MCP |
| `healthmd setup codex` | Configurar Codex y emparejar un iPhone en un solo flujo |

Los comandos directos se emparejan con fuentes iPhone (protocolo v1) o Android (protocolo v2). El `extract` canónico y cada comando de consulta tipada son capacidades de iPhone; las fuentes directas de Android devuelven instantáneas sin procesar nativas del proveedor Health Connect y archivos generados.

```bash
# Disponibilidad y confianza local
healthmd status
healthmd direct devices

# Exportación sin procesar nativa de la plataforma; omite --output para transmitir JSON/NDJSON validado a stdout
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json

# Consulta tipada a través del mismo registro de operaciones que MCP (iPhone)
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'

# Extracción canónica con alcance (iPhone)
healthmd extract --category Sleep --last 7 --output sleep.json

# Archivos generados por producción en todos los sistemas operativos de la CLI
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"

# Operaciones persistentes
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --output resumed.json
healthmd cancel JOB_UUID
```

### Exportación portátil de archivos basada en perfiles

La CLI directa independiente puede resolver un perfil guardado en cualquiera de las dos plataformas telefónicas compatibles mediante su ID estable. El perfil aporta sus ajustes de salida congelados. El destino de la computadora sigue siendo explícito:

```bash
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --last 7 \
  --profile 11111111-2222-4333-8444-555555555555 \
  --destination "$HOME/Documents/HealthVault"
```

`--profile PROFILE_ID` no puede combinarse con `--use-device-settings` ni con selectores de métrica/categoría, y un ID desconocido falla de forma segura en lugar de usar ajustes activos. Copia el ID desde **Ajustes → Perfiles de exportación → ID de perfil** en iPhone o Android. Consulta [Perfiles de exportación](/es/docs/export-profiles/) para automatización y comportamiento del destino.

El cliente directo portátil puede invocar cualquier operación tipada de iPhone admitida sin envoltorio MCP:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

## Asistente de Mac incluido

Health.md para Mac incluye sus propios asistentes Swift firmados `healthmd` y `healthmd-mcp` dentro de la aplicación. Ese asistente es una función de la aplicación para Mac, no un backend de la CLI independiente: de forma predeterminada se comunica con el servidor loopback de la aplicación Mac en ejecución para consultas locales cifradas, herramientas MCP y la carpeta de destino ya seleccionada en Health.md para Mac, y además ofrece un modo directo de iPhone compatible seleccionado con `--backend direct`. Los dos clientes nunca cambian de modo silenciosamente.

<div class="availability available">
<strong>Disponible ahora · Health.md para Mac</strong>
<p>Los asistentes Swift firmados de CLI y MCP se incluyen en la aplicación para Mac publicada.</p>
</div>

Abre la aplicación para Mac y selecciona **CLI** para ver las rutas de tu copia instalada, los comandos de configuración, los prompts de agentes y el instalador opcional de habilidades de agente.

Las rutas normales del paquete de la aplicación son:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Usa alias para una sesión de shell:

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

O crea enlaces simbólicos persistentes en un directorio bin propiedad del usuario:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

Añade `~/.local/bin` a `PATH` si tu shell aún no lo incluye:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verifica el asistente sin iniciar el bucle stdio de MCP:

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` devuelve JSON `healthmd.cli_doctor` con la disponibilidad de Mac, contexto cifrado e iPhone. No imprime valores de salud.

### Comandos del asistente incluido

| Comando | Propósito |
|---|---|
| `healthmd export --iphone ...` | Escribir archivos generados o devolver JSON sin procesar estricto a través de la aplicación Mac |
| `healthmd status` | Inspeccionar disponibilidad de Mac/iPhone o una tarea persistente |
| `healthmd doctor` | Explicar la disponibilidad de Mac, contexto cifrado e iPhone |
| `healthmd metrics list` | Devolver el catálogo canónico de métricas consultables |
| `healthmd query` | Adquirir y consultar métricas tipadas seleccionadas |
| `healthmd sleep sessions` | Devolver sesiones de sueño de primera clase y ventanas fijas |
| `healthmd training align` | Alinear entrenamientos con el sueño previo y posterior |
| `healthmd workouts` | Listar entrenamientos tipados con evidencia |
| `healthmd coverage` | Inspeccionar cobertura de fechas y métricas o datos faltantes |
| `healthmd compare` | Comparar períodos exactos con agregación elegida por el llamador |
| `healthmd evidence training` | Construir un paquete de evidencia de entrenamiento fáctico |
| `healthmd resume` / `healthmd cancel` | Gestionar tareas persistentes |
| `healthmd agent ...` | Llamar a la API loopback de bajo nivel de consultas y tareas |
| `healthmd --backend direct ...` | El modo directo de iPhone compatible del asistente |

En el modo directo del asistente, los subcomandos de consulta, evidencia, doctor, métricas y actualización de contexto Mac devuelven `backend_unsupported` en lugar de cambiar a la aplicación Mac.

### Primer flujo de trabajo de la aplicación Mac

1. Abre Health.md en Mac y selecciona una carpeta de destino si planeas escribir archivos.
2. Abre Health.md en el iPhone emparejado y espera la conectividad con Mac.
3. Comprueba la disponibilidad.
4. Ejecuta un comando pequeño antes de solicitar un historial grande.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

Las consultas nuevas adquieren solo las métricas, fuentes, fechas y detalle de resumen o sin pérdidas suministrados. No cambian los ajustes de exportación guardados del iPhone.

### Exportaciones de archivos y sin procesar del asistente incluido

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
```

Actualmente no hay límite de días de calendario. `--all` pide al iPhone descubrir el registro seleccionado disponible más antiguo, fija el rango resuelto y lo procesa en particiones acotadas. El almacenamiento disponible y un día inusualmente denso siguen siendo límites prácticos.

`--raw` solicita temporalmente registros canónicos sin pérdidas sin cambiar la preferencia del iPhone. No escribe archivos generados ni incluye sidecars de proveedores conectados.

## ¿Extracción canónica o consulta derivada?

Usa `extract` cuando necesitas datos con la forma del origen:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Usa un comando de consulta cuando necesitas una vista tipada vinculada a evidencia. La CLI independiente expone operaciones tipadas fijas; el asistente de Mac incluido ofrece además los comandos de alto nivel siguientes:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}'
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v8 es el contrato público de origen de Apple. Los esquemas de consulta, evidencia, tarea y recibo describen vistas de transporte o derivadas. No reemplazan el esquema de origen. La extracción canónica es una capacidad de iPhone; las fuentes directas de Android exponen instantáneas nativas del proveedor Health Connect mediante exportación sin procesar.

## Comportamiento legible por máquina

Los comandos usan JSON versionado en stdout o en la ruta `--output` explícita de forma predeterminada. La extracción canónica puede emitir JSONL y las consultas de alto nivel pueden optar por una tabla deliberadamente con pérdidas. El progreso sin datos de salud puede usar stderr. `--help` es texto plano. Los errores de argumentos antes de iniciar un comando son texto plano en stderr con código de salida 2.

Una salida de proceso exitosa no basta para demostrar datos de salud completos. Comprueba:

- el estado exterior;
- el estado del alcance solicitado;
- los resultados por día y por consulta;
- los intervalos faltantes;
- `next_cursor` o el recibo de recorrido;
- el esquema y la versión del origen;
- las limitaciones y advertencias.

Un resultado completamente vacío significa que Health.md representó el alcance solicitado y no encontró observaciones. No es lo mismo que cero, faltante, fallido, omitido o no admitido.

## Automatización segura

Usa el tiempo de espera de proceso de tu host de automatización y mantén stdin cerrado para comandos que no deben solicitar entrada. En sistemas con `timeout` de GNU:

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

El tiempo de espera, Ctrl-C, la salida del proceso, la pérdida de red y el tiempo de fondo de iOS agotado no cancelan una tarea persistente. Inspecciona el ID de la tarea y reanúdala en lugar de iniciar un duplicado.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

Solo el reconocimiento del iPhone hace terminal la cancelación.

## Reglas de privacidad

La salida sin procesar y sin pérdidas puede contener marcas de tiempo exactas, rutas, registros clínicos, medicamentos, entradas de ánimo, valores de ECG, procedencia y adjuntos. Prefiere un archivo de salida a la salida de terminal. No pegues cargas útiles en informes de problemas, transcripciones de agentes, registros de CI ni trazas de shell.

La API de consulta local del asistente de Mac incluido no tiene token de portador, registro, perfil de acceso ni base de datos de concesiones. La alcance de loopback es su límite de acceso completo. Cualquier proceso local puede usarla mientras la aplicación Mac está abierta; nunca hagas proxy ni expongas el puerto `17645` a otra máquina.

## Próximas guías

<div class="related">
  <a href="/es/docs/cli-direct/"><span>Sin aplicación Mac</span>CLI directa de teléfono: empareja con iPhone o Android, revisa transportes, exportaciones sin procesar y de archivos, comportamiento en segundo plano y soporte de plataformas.</a>
  <a href="/es/docs/cli-extract/"><span>Datos de origen</span>Extracción canónica: selecciona métricas, objetos, detalle, punteros JSON, JSONL y recibos.</a>
  <a href="/es/docs/cli-jobs/"><span>Automatización</span>Tareas persistentes: tiempos de espera, reanudación, cancelación, resultados parciales y scripting seguro.</a>
  <a href="/es/docs/agents/"><span>Agentes</span>Flujos de agentes locales: contexto cifrado, alcance directo, comandos tipados y evidencia.</a>
  <a href="/es/docs/mcp/"><span>MCP</span>Configura el asistente stdio aislado y revisa su límite de herramientas.</a>
  <a href="/es/docs/reference/api-and-cli/"><span>Contrato</span>Referencia de API y CLI: rutas exactas, esquemas, respuestas y fixtures generados.</a>
</div>
