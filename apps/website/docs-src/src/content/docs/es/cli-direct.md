---
title: "CLI directa de teléfono"
description: "Empareja healthmd con un iPhone o un teléfono Android mediante Manual IP o Tailscale y exporta sin ejecutar Health.md para Mac."
---

El backend directo conecta `healthmd` a una aplicación Health.md abierta en iPhone o Android sin enrutar el comando a través de Health.md para Mac. El teléfono lee su almacén de salud de la plataforma — HealthKit en iPhone, Health Connect en Android —, prepara el resultado en un almacenamiento protegido y transfiere particiones validadas a la CLI.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone or Android -> HealthKit / Health Connect -> protected bounded spool
  -> raw snapshots, production-generated files, or (iPhone) canonical and typed query data
```

<div class="availability preview">
<strong>Vista previa · CLI directa y portátil</strong>
<p>El backend directo Swift incluido está disponible en macOS y se empareja con iPhone. Android con protocolo de aplicación v2 forma parte de la vista previa públicamente empaquetada del cliente Rust multiplataforma. Las versiones actuales de iOS y Android usan el mismo selector 3 y el mismo QR universal para nuevos emparejamientos portátiles. Las pruebas de lanzamiento en iPhone y Android físicos siguen pendientes; los comandos de Linux y Windows describen un flujo de trabajo explícitamente no cualificado.</p>
</div>

## Compatibilidad móvil para 0.1.0-alpha.3

Esta tabla independiente es la matriz aplicable para la vista previa explícitamente no cualificada. Todavía no hay ninguna pareja pública CLI/móvil cualificada.

| Fuente móvil | Protocolo | Contraparte tag-SHA exacta / compatibilidad mínima no cualificada | Operaciones Rust portátiles | Estado público |
|---|---|---|---|---|
| iPhone con exportación | selector 3 actual (1 antiguo) / aplicación v1 | iOS 3.2.1 (compilación 202608300209) / iOS 3.0.3 | Estado, datos sin procesar, extracción, archivos, reanudación, cancelación | Pendiente de cualificación física |
| iPhone con consultas | selector 3 actual (1 antiguo) / aplicación v1 + consulta v3 | iOS 3.2.1 (compilación 202608300209) / iOS 3.0.3 | V1 más MCP/consulta local de 19 herramientas | Pendiente de cualificación física |
| Android | selector 3 actual (2 antiguo) / aplicación v2 | Android 1.8.1 (`versionCode 30`) / Android 1.5.4 (`versionCode 25`) | Estado, datos nativos, archivos, reanudación, cancelación | Pendiente de cualificación física |
| Consulta MCP tipada en Android | No disponible | No implementada | Las herramientas requieren iPhone v3 | No compatible |

## ¿Qué admite el modo directo?

- emparejamiento único mediante el selector compartido 3 y reconexión confiable con fuentes iPhone (protocolo de aplicación v1) o Android (protocolo de aplicación v2);
- inspección y desemparejamiento de dispositivos locales de confianza;
- comprobación en directo de la disponibilidad del teléfono;
- exportación estricta sin procesar — `healthmd.health_data` de esquema v8 en iPhone, instantáneas nativas del proveedor Health Connect en Android;
- extracción canónica seleccionada (solo iPhone);
- exportación de archivos generados en producción en ambas plataformas de teléfono;
- estado y reanudación de tareas locales persistentes;
- cancelación explícita;
- el mismo servidor stdio `healthmd mcp serve` ejecutable con consultas tipadas directas, catálogo de métricas, evidencia, interfaz de usuario de aplicaciones MCP y respaldo PNG (solo iPhone).

El backend directo del comando `healthmd` no emula las rutas HTTP de contexto cifrado de la aplicación Mac, por lo que los subcomandos `doctor`, de consulta, evidencia y actualización orientados a Mac aún devuelven `backend_unsupported` en lugar de cambiar de backend. Usa `healthmd mcp serve` para análisis tipados directos y recientes del iPhone, o ejecuta `healthmd setup codex` para configurar y emparejar Codex automáticamente. `healthmd mcp schema [TOOL]` imprime localmente el esquema de entrada MCP anidado exacto y ejemplos; usa `healthmd_sleep_sessions` directamente para el sueño en lugar de tratar la salida canónica de `extract` como la API de consulta tipada.

## Requisitos

- Un binario `healthmd` con capacidad directa y una compilación coincidente de Health.md: iPhone (protocolo de aplicación v1) o Android (protocolo de aplicación v2). El emparejamiento con Android requiere el cliente Rust portátil; el asistente incluido de macOS se empareja solo con iPhone.
- Health.md abierto en primer plano en el teléfono para el emparejamiento y los nuevos comandos.
- **Configuración > Sincronización de Mac > Acceso directo a CLI** habilitado en iPhone, o **Configuración → Direct CLI** en Android.
- Permiso de salud de la plataforma (HealthKit o Health Connect), datos protegidos, permiso de red local y cuota de exportación disponibles.
- Una dirección de computadora accesible y un puerto TCP `17647` para Manual IP. Una dirección de Tailscale funciona.
- Un destino absoluto existente para el modo de archivos generados.

La CLI mantiene el servicio de escucha. El teléfono se conecta a la dirección de la computadora ingresada en Direct CLI Access.

## Soporte de transporte

| Transporte | Asistente Swift incluido en macOS | Cliente Rust portátil |
|---|---:|---:|
| Manual IP en una LAN | Sí | macOS, Linux, Windows |
| Dirección de Tailscale | Sí | macOS, Linux, Windows |
| Cercano / Conectividad multipar | Sí | No |

Nearby utiliza la sesión Multipeer cifrada de Apple más la misma autenticación y cifrado de la aplicación Health.md que utiliza Manual IP. El cliente portátil devuelve `transport_unsupported` para Nearby.

## Emparejar una vez con Manual IP

Inicia el servicio de escucha en la computadora:

```bash
healthmd direct pair --transport manual-ip
```

El cliente Rust portátil muestra un QR universal para iOS y Android y escribe en stderr su código compartido de 20 dígitos, las direcciones candidatas de la computadora, el puerto de escucha y un código de respaldo de seis dígitos para iOS antiguo. El asistente incluido de macOS sigue mostrando solo su código antiguo de seis dígitos para iPhone. stdout permanece reservado para el resultado JSON final.

En iPhone:

1. Abre **Health.md > Configuración > Sincronización de Mac > Acceso directo a CLI** y habilita el acceso.
2. Toca **Escanear QR de emparejamiento** y escanea el QR universal; el emparejamiento comienza inmediatamente tras ese escaneo explícito.
3. Si no puedes escanear, selecciona **Manual IP** e introduce la dirección, el puerto y el código compartido de 20 dígitos. Una CLI antigua aún puede usar el código de seis dígitos.
4. Mantén la aplicación abierta hasta que ambas partes indiquen éxito.

## Emparejar un teléfono Android

1. Abre **Health.md > Configuración → Direct CLI** en el teléfono Android.
2. Toca **Escanear QR de emparejamiento** y escanea el QR universal; el emparejamiento comienza inmediatamente tras ese escaneo explícito.
3. Sin cámara o permiso, introduce manualmente la dirección, el puerto y el mismo código compartido de 20 dígitos.
4. Mantén la aplicación abierta; Android ejecuta un servicio en primer plano de sincronización de datos, visible e iniciado por el usuario, para una sesión directa activa.

Los códigos de un solo uso nunca se envían por la red ni se guardan de forma persistente. Tras el emparejamiento, Keychain o Android Keystore protegen la confianza de reconexión.

Usa un puerto diferente cuando sea necesario:

```bash
healthmd --port 18000 direct pair --transport manual-ip
healthmd --backend direct --port 18000 status
```

Sigue usando el mismo puerto explícito para los comandos posteriores de estado, exportación, reanudación y cancelación.

## Emparejar con Nearby

Cercano está disponible solo en el asistente Swift incluido:

```bash
healthmd direct pair --transport nearby
```

Selecciona Nearby en Acceso directo a CLI en el iPhone, introduce el código mostrado y mantén ambos dispositivos abiertos hasta que finalice el emparejamiento. Ninguna operación Nearby fallida cambia a Manual IP.

## Dispositivos confiables

El emparejamiento crea una confianza independiente de la relación de sincronización de la aplicación Health.md para Mac.

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

Estos comandos leen o modifican la confianza local y no contactan al teléfono. En iPhone, usa **Olvidar CLI emparejado** para quitar el otro lado; en Android, elimina el emparejamiento desde **Configuración → Direct CLI**.

Cuando se confíe en más de un teléfono, selecciona explícitamente la instalación deseada:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Usa `healthmd direct reset-trust --confirm` solo cuando la confianza local esté dañada o pertenezca a una instalación reemplazada. Elimina todos los emparejamientos directos locales. Olvida esos emparejamientos en el teléfono antes de empezar de nuevo.

## Comprobar la disponibilidad en directo

```bash
healthmd --backend direct --transport manual-ip status
```

Una respuesta de estado directa informa del estado de conexión y de seguridad sin valores de salud. El cliente portátil informa la fuente bajo `source` con una `platform` de `ios` o `android`; el asistente incluido expone los campos `iphone` siguientes. Comprueba estos campos antes de comenzar a trabajar (se muestra la fuente iPhone):

| Campo | Estado listo |
|---|---|
| `backend` | `direct` |
| `mac_app` | `bypassed` |
| `direct_cli.paired` | `true` |
| `iphone.connected` | `true` |
| `iphone.app_active` | `true` para tareas nuevas |
| `iphone.protected_data_available` | `true` |
| `iphone.can_trigger_raw_exports` | `true` para exportaciones sin procesar y extracciones |
| `iphone.can_trigger_exports` | `true` para archivos generados |

El destino del estado directo permanece sin seleccionar. El modo de archivo usa solo el `--destination` explícito proporcionado al comando.

Una fuente Android informa `platform: "android"` con `app_active`, `protected_data_available`, `export_in_progress` y sus productos sin procesar disponibles, en lugar de los indicadores de activación del iPhone.

## Exportación estricta sin procesar (iPhone)

Elige un selector de intervalo:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Omite `--output` para transmitir JSON validado a la salida estándar. Un archivo de salida es más seguro para respuestas confidenciales o grandes.

La exportación estricta sin procesar de iPhone devuelve `healthmd.raw_result` v1 que contiene días `healthmd.health_data` de esquema v8 ordinario y sus archivos fuente canónicos. Solicita temporalmente detalles sin pérdida sin cambiar la configuración guardada del iPhone. La CLI valida las fechas exactas, el perfil, el esquema, el archivo, los manifiestos, la cadena de resúmenes, el resumen final del cuerpo y el estado de finalización antes de exponer el resultado.

Un día completamente vacío es un éxito. Los datos solicitados faltantes, parciales, fallidos, cancelados, no admitidos u omitidos producen `partial_success` y una salida distinta de cero a menos que `--allow-partial` sea explícito.

## Exportación sin procesar nativa del proveedor (Android)

El cliente Rust portátil es directo de forma predeterminada, por lo que los comandos sin procesar de Android omiten la opción `--backend`:

```bash
healthmd export --last 7 --raw --provider health_connect \
  --raw-format ndjson --output health-connect.ndjson
```

`--provider` nombra un único proveedor explícito y su valor predeterminado es `health_connect`. `--raw-format` tiene como valor predeterminado NDJSON, la forma recomendada para instantáneas grandes; la validación de JSON en memoria está limitada a 64 MiB. La selección de métricas admite `--metric` y `--all-metrics`, pero no selectores canónicos ni de archivos generados; esas siguen siendo capacidades de iPhone.

Las instantáneas sin procesar de Android conservan su contrato nativo del proveedor Health Connect. Nunca se convierten en días `healthmd.health_data` con forma de HealthKit, y las estadísticas relacionadas pero distintas mantienen sus propias identidades.

## Extracción canónica

La extracción directa usa el mismo transporte persistente de datos sin procesar, pero devuelve datos seleccionados en forma de fuente en lugar del contenedor de transporte. Es una capacidad de iPhone:

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

La selección de métricas, categorías, fuentes y detalles llega al iPhone antes de que HealthKit lea. Consulta [Extracción canónica](/es/docs/cli-extract/) para selectores de objetos, punteros JSON, JSONL y recibos.

Mientras la aplicación permanezca en primer plano, una sesión directa de confianza puede reconectarse automáticamente tras una interrupción temporal, con intentos y esperas limitados. Esto no despierta ni promete acceso a una aplicación en segundo plano; vuelve a abrir Health.md antes de reanudar.

## Archivos generados en producción

El modo de archivo directo solicita al teléfono que ejecute los exportadores de producción de Health.md y luego transfiere los archivos resultantes a un destino informático explícito.

```bash
mkdir -p "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --last 7 \
  --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

El destino ya debe existir, ser absoluto y no resolverse mediante un enlace simbólico. El modo directo nunca adivina ni usa un marcador de la aplicación de Mac. `--output` es para la salida sin procesar o de extracción; `--destination` es para archivos generados.

De forma predeterminada, una solicitud conserva los formatos guardados, la subcarpeta Health, los nombres de archivos, las plantillas, el modo de escritura, la inyección de notas diarias y solo notas diarias. Suprime los datos agregados y el modo de solo resumen para esa tarea. Las opciones repetibles `--metric` o `--category` junto con `--detail` reemplazan solo el alcance de métrica y detalle de la tarea. `--use-iphone-settings` refleja todas las configuraciones guardadas y no se puede combinar con selectores.

El iPhone puede almacenar archivos JSON, CSV, Markdown, ZIP, diccionarios de datos, datos agregados, registros individuales, notas diarias y datos auxiliares de proveedores. La CLI valida cada ruta relativa, recuento de bytes, resumen, manifiesto de archivo, identidad de destino y huella digital de solicitud antes de confirmar. Rechaza el recorrido, los ancestros de enlaces simbólicos, la mutación de raíz, las colisiones de rutas y los cambios de resumen. La sobrescritura es atómica. La combinación Append y Markdown usa planes persistentes para que un reintento no duplique el contenido.

Los destinos de archivos generados funcionan con el protocolo v1 de iPhone y el protocolo v2 de Android en todos los sistemas operativos de la CLI — macOS, Linux y Windows. Android limita cada tarea generada a 4096 archivos.

Las tareas de archivos del protocolo v2 de Android toman sus ajustes de salida de las selecciones guardadas en el dispositivo o de `--profile PROFILE_ID`; los selectores CLI de métrica, categoría y detalle se rechazan. En ambas plataformas de teléfono, `--profile` resuelve ajustes de salida congelados, mientras que el `--destination` obligatorio sigue indicando la carpeta explícita del ordenador.
Para identificadores estables y fallos seguros, consulta [Perfiles de exportación](/es/docs/export-profiles/).

## Comportamiento en primer plano y en segundo plano

El emparejamiento y las tareas nuevas requieren la aplicación del teléfono en primer plano. Direct CLI Access no convierte el teléfono en un servidor de exportación sin cabeza y no puede activar la aplicación a pedido.

En iPhone, si ya hay una exportación conectada cuando la aplicación pasa a segundo plano, Health.md solicita un tiempo finito de ejecución en segundo plano de iOS. La exportación puede finalizar durante ese intervalo. Si iOS agota el tiempo asignado, la conexión se cierra y la tarea persistente se pausa. Vuelve a abrir Health.md y reanuda la misma tarea.

En Android, una sesión directa activa ejecuta un servicio en primer plano de sincronización de datos, visible e iniciado por el usuario. Mantén la aplicación en primer plano para el emparejamiento y las tareas nuevas.

En iPhone, un banner de actividad global durante la tarea directa incluye la fase de captura y transferencia, los días completados, el progreso de bytes y el estado de pausa o finalización sin mostrar valores de salud.

Mientras la aplicación del teléfono permanezca en primer plano, una sesión directa de confianza puede volver a conectarse automáticamente tras una desconexión transitoria. Los reintentos usan demoras crecientes con un máximo breve. Esto no activa ni garantiza acceso a una aplicación en segundo plano; vuelve a abrir Health.md antes de reanudar si ya no está en primer plano.

La ventana de espera limitada de 120 segundos mantiene abierta la misma solicitud mientras la persona desbloquea el teléfono y abre Health.md. Se ajusta con `--wake-timeout SECONDS`; `0` la desactiva. MCP usa `HEALTHMD_WAKE_TIMEOUT`. Esta primera fase todavía no envía notificaciones push ni evita el desbloqueo o los permisos.

## Reanudación y cancelación persistentes

Las tareas directas caducan siete días después de su creación. El tiempo de espera, Ctrl-C, la muerte del proceso, la desconexión y el vencimiento en segundo plano no las cancelan.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

La reanudación mantiene las fechas originales, la configuración, el destino, la huella digital de la solicitud, el dispositivo y la frontera de la partición. No se puede dirigir una tarea de archivos a un destino diferente durante la reanudación.

La cancelación registra una solicitud persistente, pero solo se vuelve terminal después de que el teléfono emparejado la confirma. Si el teléfono no está disponible, el estado sigue siendo `cancellation_pending`. Vuelve a abrir el mismo teléfono e intenta cancelar de nuevo.

## Modelo de seguridad

- Los emparejamientos portátiles actuales usan un acuerdo de claves efímero y pruebas de transcripción del selector 3 vinculadas a un código compartido de alta entropía de 20 dígitos (~66 bits) para iOS y Android. Los flujos antiguos de Apple selector 1 y Android selector 2 siguen siendo compatibles byte por byte.
- Las entregas por QR solo se aceptan mediante escáneres explícitos dentro de la aplicación para direcciones privadas LAN/Tailscale canónicas; abrir una URL personalizada externa no puede autorizar el emparejamiento.
- La reconexión demuestra un secreto almacenado aleatorio y ambas identidades de instalación.
- Cada conexión deriva claves y nonces nuevos.
- Los mensajes y los marcos binarios usan ChaCha20-Poly1305 con comprobaciones de secuencia monótona.
- Las particiones usan manifiestos SHA-256 y una frontera de resumen encadenada.
- La confianza del iPhone se almacena en Keychain; la confianza de reconexión de Android está respaldada por Keystore.
- La confianza portátil usa Keychain, Secret Service o Windows Credential Manager y nunca recurre al texto sin formato.
- Los spools y los diarios usan almacenamiento de aplicaciones privado y excluyen las copias de seguridad cuando la plataforma lo admite.

Manual IP permanece cifrado en una red local o Tailscale. Tailscale también protege la ruta de red, pero no reemplaza la autenticación de la aplicación Health.md.

## Errores comunes

| Error | Acción |
|---|---|
| `direct_not_paired` | Empareja esta instalación CLI con la fuente móvil prevista. |
| `direct_device_selection_required` | Proporciona el `--device` de confianza previsto. |
| `direct_trust_invalid` | Conserva el diagnóstico. Restablece la confianza solo cuando no sea posible recuperarla. |
| `direct_iphone_unavailable` | Comprueba el estado de primer plano de la aplicación, la alternancia de acceso, la dirección, el puerto, el permiso y la accesibilidad de LAN o Tailscale. |
| `direct_export_paused` | Inspecciona la tarea, vuelve a abrir el teléfono emparejado y reanúdala. |
| `direct_cancellation_pending` | Vuelve a abrir el teléfono emparejado e intenta cancelar de nuevo. |
| `transport_unsupported` | Usa Manual IP o Tailscale en el cliente portátil. |
| `backend_unsupported` | Usa el backend de la aplicación para Mac para consultas, evidencia, diagnóstico, métricas o MCP. |
| `invalid_direct_raw_response` | No uses la salida. Conserva los diagnósticos de validación. |
| `invalid_direct_file_receipt` | No repares archivos manualmente. Inspecciona y reanuda la tarea. |
| `job_expired` | El período de conservación del estado, de siete días, ha terminado. Confírmalo antes de iniciar una tarea nueva. |

## Relacionado

<div class="related">
<a href="/es/docs/cli/"><span>Resumen</span>Health.md CLI: instala los asistentes incluidos y elige el backend correcto.</a>
<a href="/es/docs/android/"><span>Android</span>Health.md para Android: fuentes de Health Connect, destinos de carpeta y automatización en el dispositivo.</a>
<a href="/es/docs/cli-extract/"><span>Datos</span>Extracción canónica: selecciona y emite datos Health.md en forma de fuente (iPhone).</a>
<a href="/es/docs/cli-jobs/"><span>Fiabilidad</span>Tareas persistentes y automatización: reanudación, cancelación, resultados parciales y scripting.</a>
<a href="/es/docs/reference/connected-mac-iphone-protocol/"><span>Protocolo</span>Referencia de Mac y iPhone conectados: capacidades, transferencia acotada y estados de resultados.</a>
</div>
