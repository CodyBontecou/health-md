---
title: "Agentes locales y contexto de salud"
description: "Conecta agentes locales a Health.md mediante comandos acotados de la CLI o MCP directo con el iPhone, y conserva la evidencia, la cobertura y la representación de datos ausentes."
---

Health.md ofrece a los agentes locales de codificación y automatización dos formas de trabajar con los datos de Apple Health:

- la CLI `healthmd` para comandos de terminal explícitos y extracción canónica;
- `healthmd mcp serve` y su aplicación para MCP para herramientas tipadas, visualizaciones nativas y exportaciones aprobadas de archivos generados.

El servidor MCP portátil se comunica directamente con el iPhone en primer plano y no requiere Health.md para Mac. La CLI puede usar el mismo canal directo para exportaciones sin procesar o canónicas, o la API de loopback de la aplicación Mac para flujos de trabajo de índice Mac. Las lecturas de HealthKit siempre se realizan en iPhone y `healthmd.health_data` v8 sigue siendo el contrato de fuente pública.

```text
local agent -> healthmd mcp serve -> authenticated encrypted port 17647 -> foreground iPhone
local agent -> healthmd CLI -> direct iPhone or optional Mac loopback workflow
```

## Qué puede hacer un agente

- comprobar el emparejamiento directo y la disponibilidad del iPhone en primer plano sin leer los valores de salud;
- enumerar categorías e ID de métricas canónicas;
- adquirir una métrica exacta, fuente, fecha y alcance detallado del iPhone;
- extraer documentos diarios canónicos o registros fuente;
- consultar series de métricas tipadas con evidencia y cobertura;
- crear sesiones de sueño estables y ventanas de sueño fijas;
- alinear los entrenamientos con el sueño previo y posterior;
- enumerar entrenamientos e inspeccionar la cobertura;
- comparar períodos exactos con agregación explícita;
- crear paquetes de evidencia factual sobre el entrenamiento;
- recorrer mediante paginación un corpus lógico ilimitado con solicitudes acotadas;
- renderizar vistas de métricas, sueño, entrenamiento, comparación, cobertura y evidencia dentro de las aplicaciones MCP;
- ejecutar exportaciones de archivos generados aprobadas en un destino de escritorio existente explícito;
- inspeccionar, reanudar o cancelar tareas persistentes de exportación.

Health.md no diagnostica, recomienda tratamientos, infiere la causalidad ni etiqueta un resultado como saludable, dañino, mejor o peor.

## Configurar los asistentes locales

<div class="availability preview">
<strong>Vista previa pública · aún no es una versión estable cualificada</strong>
<p>El paquete multiplataforma se publica como una vista previa explícitamente no cualificada. Usa la compilación móvil exacta indicada por la evidencia de la versión; el asistente firmado para Mac sigue disponible en <a href="/es/docs/configuration/">Configurar el agente</a>.</p>
</div>

1. En macOS o Linux, ejecuta `brew install CodyBontecou/tap/healthmd` y después verifica `healthmd --version`.
2. Ejecuta `healthmd setup codex`; el comando configura Codex y abre el emparejamiento cuando aún no se confía en un iPhone.
3. Completa el emparejamiento en Acceso directo de la CLI, dentro de Health.md en el iPhone, y mantén la aplicación en primer plano.
4. Para Claude o la configuración manual del host, configura la ruta absoluta `healthmd` con los argumentos `mcp serve` usando [Servidor y aplicación MCP de Health.md](/es/docs/mcp/).
5. Reinicia el host cuando la instalación informe un cambio en la configuración, luego llame a `healthmd_doctor`.

## Instalar una habilidad para agentes

La aplicación Health.md para Mac sigue siendo una ruta de instalación y distribución de habilidades opcional para los usuarios de Mac, no una dependencia de MCP portátil.

La mayoría de los usuarios debe instalar únicamente la [habilidad Health.md CLI para consumidores en skills.sh](https://skills.sh/CodyBontecou/health-md/healthmd-cli):

```bash
npx skills add CodyBontecou/health-md@healthmd-cli
```

El repositorio público ofrece cuatro habilidades específicas para cada tarea:

| Habilidad | Uso previsto |
|---|---|
| `healthmd-cli` | Consultas y exportaciones limitadas y autorizadas por el usuario mediante la CLI y MCP |
| `healthmd-cli-operator` | Operaciones directas con el iPhone y recuperación de tareas persistentes |
| `healthmd-cli-development` | Desarrollo de la CLI, MCP, el protocolo y el servicio del iPhone |
| `healthmd-cli-qa` | Validación automatizada y con dispositivos físicos |

Para instalar una habilidad de colaborador, sustituye el nombre después de `@`; no instales instrucciones de desarrollo o QA para solicitudes normales de datos de salud. Usa `npx skills add CodyBontecou/health-md --list` para inspeccionar el repositorio sin instalar una habilidad y `npx skills update healthmd-cli --project --yes` para actualizar la habilidad de consumidor del proyecto. La [guía de instalación del repositorio](https://github.com/CodyBontecou/health-md/blob/main/docs/agents/skills.md) documenta todos los comandos y el contrato de publicación.

Una habilidad es un conjunto de instrucciones. No instala `healthmd` ni `healthmd-mcp`, no configura MCP, no empareja un teléfono, no concede acceso a datos de salud ni se mantiene actualizada automáticamente. Revisa su código fuente antes de instalarla.

El instalador de habilidades de la aplicación para Mac crea `healthmd-cli/SKILL.md` en el directorio que apruebes. Reemplaza únicamente la carpeta de habilidades propia de Health.md. La habilidad enseña comandos limitados, manejo estructurado de resultados, reglas de privacidad, límites de divulgación del proveedor del modelo y recuperación segura después de resultados desconocidos.

Usa el mensaje de configuración en la aplicación Mac si quieres que un agente cree los enlaces simbólicos. Health.md en sí no modifica los archivos de inicio del shell o `/usr/local/bin` de forma silenciosa.

## Comprobar primero la disponibilidad

En clientes MCP portátiles, llama a `healthmd_doctor`. Comprueba la confianza directa local y que el iPhone conectado esté en primer plano sin leer valores de salud, y devuelve errores sin datos de salud que indican cómo actuar. A partir de ahí, cada consulta MCP tipada constituye una solicitud explícita de datos recientes a ese iPhone: captura solo el alcance solicitado, evalúa la consulta tipada en el dispositivo y devuelve páginas acotadas.

Los usuarios de Mac-loopback CLI aún pueden ejecutar `healthmd doctor` para comprobar la disponibilidad de `healthmd.cli_doctor` v1, cobertura de contexto cifrado y próximas acciones.

## Cada solicitud lleva su propio alcance

Health.md no utiliza perfiles de acceso guardados, registros de llamadas, registros de concesiones ni credenciales CLI. Cada solicitud proporciona el alcance de datos completo que necesita:

- ID de métricas o categorías;
- Apple Health y selectores de fuentes de proveedores opcionales;
- fechas exactas o todas las fechas disponibles;
- resumen o detalle sin pérdidas;
- operación de consulta;
- controles de página acotados.

La adquisición de datos recientes valida el alcance con los catálogos actuales, lo conserva con la tarea persistente y lo aplica en el iPhone sin cambiar las preferencias de exportación guardadas.

Una solicitud sin selección de adquisición explícita se rechaza en lugar de heredar la configuración de exportación normal del usuario.

## Límites de autorización

Portable MCP utiliza el protocolo directo emparejado: almacenamiento de credenciales nativo, autenticación de transcripción mutua, paquetes cifrados, protección de reproducción y una conexión de iPhone en primer plano a la dirección explícita de la computadora. En cambio, la API de consulta de Mac opcional escucha solo en loopback IPv4 e IPv6 y valida que el par pertenezca a loopback.

Para el modo de loopback de Mac opcional, cualquier proceso local que pueda alcanzar el puerto `17645` mientras Health.md está abierto puede emitir las mismas solicitudes de consulta. Trata el acceso a la máquina local como autoridad de consulta:

- no vincule ni haga proxy del puerto a una interfaz LAN;
- no crees un túnel hacia otra máquina;
- no coloque un proxy inverso HTTP delante;
- no configure MCP con una URL sin loopback;
- revisa qué agentes locales pueden ejecutar el asistente.

Las rutas de actividad y perfiles anteriores devuelven `410 removed_endpoint` por compatibilidad.

## Datos canónicos y vistas derivadas

Usa `healthmd extract` cuando el agente necesite datos en forma de fuente o un cuerpo canónico/sin procesar validado de gran tamaño:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Usa comandos de consulta o herramientas MCP para vistas derivadas y visualizaciones en el host:

```bash
healthmd query --metric resting_heart_rate --last 30 --all-pages
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd training align --last 14 --workout running --sleep-window first:4h
```

La distinción es deliberada:

| Superficie | Rol del contrato |
|---|---|
| `healthmd.health_data` v8 | Documento fuente diario público |
| `healthmd.healthkit_records` v1 | Archivo canónico de registros fuente dentro de documentos diarios sin pérdidas |
| `healthmd.extract_receipt` | Alcance de extracción y metadatos de finalización |
| `healthmd.query_context_day` v1 | Registro de índice cifrado desechable |
| `healthmd.query_response` v1 | Resultado derivado, tipado y paginado |
| `healthmd.evidence_packet` v1 | Paquete factual vinculado a la evidencia de origen |
| Recibos de tareas y recorridos | Metadatos de transporte, persistencia y finalización |

Una proyección o un resultado tipado nunca se presenta como un documento fuente diario completo.

## Adquisición de datos recientes

Las consultas de alto nivel adquieren datos recientes de forma predeterminada:

```bash
healthmd query --category Sleep --last 14
```

Health.md crea una solicitud de contexto cifrado dedicada. No escribe archivos de exportación ni consume cuota de exportación de archivos. El iPhone lee el alcance explícito, crea días de propietario compactos deterministas y envía particiones reanudables acotadas. El Mac confirma cada día cifrado antes de reconocerlo.

La finalización de la adquisición de datos recientes verifica cada métrica, fuente o proveedor y día del propietario solicitados con los blobs reemplazados después de que comenzó la actualización. Los valores y datos almacenados en caché más antiguos de otro proveedor no pueden ocultar una adquisición fallida.

Las solicitudes exclusivas del proveedor pueden omitir HealthKit. El recorrido del historial del proveedor sigue los cursores nativos del proveedor en lugar de imponer un límite fijo de resultado total.

## Contexto de Mac cifrado

El Mac almacena una generación cifrada de forma independiente por día de propietario. Una clave aleatoria de 256 bits se encuentra en Keychain como un elemento exclusivo de este dispositivo cuando se desbloquea.

- los blobs diarios y el manifiesto utilizan AES-256-GCM;
- los nombres de archivos son UUID aleatorios, no fechas ni nombres de métricas;
- las fechas del propietario y las entradas del índice están cifradas;
- los archivos tienen permisos de propietario exclusivo y exclusión de copias de seguridad;
- las confirmaciones escriben una nueva generación inmutable antes de reemplazar el manifiesto cifrado;
- las lecturas producen un error seguro si faltan claves, falla la autenticación, las fechas tienen un formato incorrecto o el manifiesto no coincide.

El almacén no tiene configurado ningún límite total de métricas, días, historial ni resultados. Los comandos permanecen acotados porque descifran un día a la vez y paginan los resultados.

El índice es desechable. Las exportaciones canónicas siguen siendo la fuente de la verdad.

## Retención y eliminación

Health.md no elimina el contexto de la consulta en un programa de retención implícito. En Mac, Configuración muestra el recuento de días del propietario almacenado y el rango de fechas.

Usar:

- **Eliminar contexto anterior** para eliminar las fechas del propietario estrictamente antes de un límite seleccionado;
- **Eliminar todo el contexto cifrado** para eliminar cada generación cifrada y la clave de llavero dedicada.

La eliminación completa permanece disponible incluso si la clave o el texto cifrado están dañados. Quitar la clave proporciona un borrado criptográfico de cualquier resto de texto cifrado no eliminado.

Eliminar el contexto de la consulta no elimina los archivos de exportación, las credenciales del proveedor conectado ni los datos de Apple Health.

## Valores tipados y ausencia de datos

Los valores de consulta están etiquetados. Un resultado puede contener una cantidad y una unidad canónica, una duración, un recuento con signo, una cadena, una categoría, un valor booleano, una marca de tiempo UTC, una fecha de calendario, una matriz anidada o una carga útil tipada futura desconocida.

Los datos faltantes siguen siendo explícitos:

- `complete_empty` significa que el alcance representado no tuvo observaciones coincidentes;
- `partial` significa que solo se ha completado una parte del alcance solicitado;
- `failed`, `unsupported`, `skipped` y `cancelled` conservan sus significados;
- `not_requested`, `legacy_unavailable`, `redacted` y `not_synchronized` siguen siendo distintos.

Health.md nunca convierte un valor ausente en cero numérico. Un cero real se codifica como un valor tipado disponible.

## Evidencia y lenguaje neutral

Los resultados vinculan los hechos con la fuente de evidencia, como por ejemplo:

- claves de resumen diario;
- UUID canónicos de HealthKit;
- identidades externas;
- resultados del manifiesto de consulta;
- advertencias de integridad;
- fallos parciales.

La resolución de evidencia verifica el ID de la evidencia, el localizador, el esquema de origen, la versión de origen y el resumen de origen en conjunto.

La dirección de comparación de períodos se limita a `increased`, `decreased`, `unchanged` o `not_comparable`. La alineación del entrenamiento informa marcas de tiempo e intervalos, no efectos causales. Los paquetes de evidencia informan observaciones y cobertura almacenadas, no conclusiones médicas.

Un agente debe preservar esos límites en su propia respuesta. Debería indicar cuándo faltan datos, evitar convertir la correlación en causa y dirigir las preguntas médicas a un médico calificado.

## Páginas acotadas, acceso lógico completo

Las páginas de consulta utilizan `max_items`, `max_bytes` y un `next_cursor` opaco. No hay límite a nivel de contrato en el total de días almacenados, entrenamientos, métricas o elementos de resultados.

Un cursor está protegido por su integridad y está vinculado a la consulta semántica y a la revisión del corpus cifrado. Health.md rechaza:

- un cursor modificado;
- un cursor utilizado con otra consulta;
- un cursor emitido antes de que cambiara el corpus;
- un cursor repetido durante el recorrido automático.

Usa `--all-pages` o MCP `all_pages: true` para un recorrido automático limitado. Acota manualmente el alcance o la página si una invocación alcanza su límite de seguridad agregado.

## Lista de verificación de informes del agente

Al resumir un resultado, informe:

- comando o herramienta utilizada;
- fechas, métricas, fuente y detalles exactos solicitados;
- modo de datos recientes, en caché o con cobertura reutilizada;
- estado del alcance solicitado y estado del corpus por separado;
- finalización de página o recorrido;
- unidades y fuentes de evidencia para cualquier valor declarado;
- intervalos ausentes, limitaciones y omisiones no relacionadas;
- ID del ID de la tarea cuando esta está en pausa o se reanuda.

No incluya registros sin procesar, rutas, textos clínicos, detalles de medicamentos, entradas de estado de ánimo ni archivos adjuntos a menos que el usuario solicite explícitamente esos valores y comprenda la divulgación.

## Elige una integración

<div class="related">
<a href="/es/docs/agent-queries/"><span>Recetario de la CLI</span>Consultas tipadas para agentes: métricas, sesiones de sueño, alineación del entrenamiento, entrenamientos, cobertura, comparación y evidencia.</a>
<a href="/es/docs/mcp/"><span>Protocolo de herramientas</span>Configuración de Codex y Claude, 21 herramientas Mac publicadas, 19 herramientas portátiles en vista previa, gráficos de aplicaciones MCP, exportaciones, paginación y límites de sandbox.</a>
<a href="/es/docs/agent-api/"><span>Nivel bajo</span>La API de consulta de loopback: rutas, JSON de solicitud directa, cursores y tareas persistentes de adquisición.</a>
<a href="/es/docs/cli-extract/"><span>Objetos de origen</span>Extracción canónica: documentos, registros, proyecciones y recibos seleccionados del esquema v8.</a>
<a href="/es/docs/reference/evidence-packets/"><span>Contratos</span>Consultas compactas y paquetes de evidencia: valores tipados, cobertura, operaciones e ID deterministas.</a>
</div>
