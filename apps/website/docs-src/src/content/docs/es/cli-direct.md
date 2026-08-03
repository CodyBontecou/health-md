---
title: "CLI directa de iPhone"
description: "Empareja healthmd con un iPhone mediante Manual IP, Tailscale o un transporte Nearby compatible y exporta sin ejecutar Health.md para Mac."
---

El backend directo conecta `healthmd` a una aplicación de iPhone Health.md abierta sin enrutar el comando a través de Health.md para Mac. El iPhone lee HealthKit, prepara el resultado en un almacenamiento protegido y transfiere particiones validadas a la CLI.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone -> HealthKit -> protected bounded spool / typed query evaluator
  -> canonical JSON, production-generated files, or bounded MCP query pages
```

<div class="availability preview">
<strong>Vista previa · CLI directa y portátil</strong>
<p>El backend directo Swift incluido está disponible en macOS. El cliente Rust multiplataforma es una versión alfa en espera de control de calidad del lanzamiento físico del iPhone y su primer paquete público; los comandos de Linux y Windows describen el flujo de trabajo por etapas.</p>
</div>

## ¿Qué admite el modo directo?

- emparejamiento único y reconexión confiable;
- inspección y desemparejamiento de dispositivos locales de confianza;
- comprobación en directo de la disponibilidad del iPhone;
- exportación estricta sin procesar con el esquema v7;
- extracción canónica seleccionada;
- exportación de archivos generados en producción;
- estado y reanudación de tareas locales persistentes;
- cancelación explícita;
- el mismo servidor stdio `healthmd mcp serve` ejecutable con consultas tipadas directamente, catálogo de métricas, evidencia, interfaz de usuario de aplicaciones MCP y respaldo PNG.

El backend directo del comando `healthmd` no emula las rutas HTTP de contexto cifrado de la aplicación Mac, por lo que los subcomandos `doctor`, consulta, evidencia y actualización orientados a Mac aún devuelven `backend_unsupported` en lugar de cambiar de backend. Usa `healthmd mcp serve` para realizar análisis tipados de datos recientes directamente en el iPhone o ejecute `healthmd setup codex` para configurar y emparejar Codex automáticamente. `healthmd mcp schema [TOOL]` imprime el esquema de entrada MCP anidado exacto y ejemplos localmente; usa `healthmd_sleep_sessions` directamente para consultar el sueño en lugar de tratar la salida canónica de `extract` como la API de consulta tipada.

## Requisitos

- Un binario `healthmd` con capacidad directa y una compilación de iPhone Health.md coincidente.
- Health.md se abre en primer plano en un iPhone para emparejamiento y nuevos comandos.
- **Configuración > Sincronización de Mac > Acceso directo a CLI** habilitado en iPhone.
- Permiso de HealthKit, datos protegidos, permiso de red local y cuota de exportación disponibles.
- Una dirección de computadora accesible y un puerto TCP `17647` para Manual IP. Una dirección Tailscale funciona.
- Un destino absoluto existente para el modo de archivo generado.

La CLI mantiene el servicio de escucha. El iPhone se conecta a la dirección de la computadora ingresada en Direct CLI Access.

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

El comando escribe un código de seis dígitos, las posibles direcciones del ordenador y el puerto de escucha en stderr mientras mantiene stdout reservado para el resultado JSON final.

En iPhone:

1. Abre **Health.md > Configuración > Sincronización de Mac > Acceso directo a CLI**.
2. Habilita el acceso directo a la CLI.
3. Selecciona **Manual IP**.
4. Introduce la dirección LAN o Tailscale del ordenador.
5. Introduce el puerto `17647`, salvo que la CLI utilice otro `--port` global.
6. Introduce el código de emparejamiento y toca Emparejar.
7. Mantén la aplicación abierta hasta que ambas partes indiquen que la operación se ha completado correctamente.

Los códigos de emparejamiento caducan después de 10 minutos. Nunca se envían a través de la red ni persisten.

Usa un puerto diferente cuando sea necesario:

```bash
healthmd --port 18000 direct pair --transport manual-ip
healthmd --backend direct --port 18000 status
```

Siga usando el mismo puerto explícito para comandos de estado, exportación, reanudación y cancelación posteriores.

## Emparejar con Nearby

Cercano está disponible solo en el asistente Swift incluido:

```bash
healthmd direct pair --transport nearby
```

Selecciona Nearby en Acceso directo CLI en el iPhone, introduce el código que se muestra y mantén ambos dispositivos abiertos hasta que finalice el emparejamiento. Ninguna operación Nearby fallida cambia a Manual IP.

## Dispositivos confiables

El emparejamiento crea una confianza independiente de la relación de sincronización de la aplicación Health.md para Mac.

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

Estos comandos leen o modifican la confianza local y no contactan al iPhone. En iPhone, use **Olvidar CLI emparejado** para quitar el otro lado.

Cuando se confíe en más de un iPhone, seleccione explícitamente la instalación deseada:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

Usa `healthmd direct reset-trust --confirm` solo cuando la confianza local esté dañada o pertenezca a una instalación reemplazada. Elimina todos los emparejamientos directos locales. Olvida esos emparejamientos en el iPhone antes de empezar de nuevo.

## Comprobar la disponibilidad en directo

```bash
healthmd --backend direct --transport manual-ip status
```

Una respuesta de estado directa informa el estado de conexión y seguridad sin valores de salud. Comprueba estos campos antes de comenzar a trabajar:

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

El destino del estado directo permanece sin seleccionar. El modo de archivo utiliza solo el `--destination` explícito proporcionado al comando.

## Exportación estricta sin procesar

Elige un selector de intervalo:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

Omita `--output` para transmitir JSON validado a la salida estándar. Un archivo de salida es más seguro para respuestas confidenciales o grandes.

La exportación estricta sin procesar devuelve un resultado `healthmd.raw_result` v1 que contiene días `healthmd.health_data` de esquema ordinario v7 y sus archivos fuente canónicos. Solicita temporalmente detalles sin pérdida sin cambiar la configuración guardada del iPhone. La CLI valida las fechas exactas, el perfil, el esquema, el archivo, los manifiestos, la cadena de resúmenes, el resumen final del cuerpo y el estado de finalización antes de exponer el resultado.

Un día completamente vacío es un éxito. Los datos solicitados faltantes, parciales, fallidos, cancelados, no admitidos u omitidos producen `partial_success` y una salida distinta de cero a menos que `--allow-partial` sea explícito.

## Extracción canónica

La extracción directa utiliza el mismo transporte persistente de datos sin procesar, pero devuelve datos seleccionados en forma de fuente en lugar del contenedor de transporte:

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

La selección de métricas, categorías, fuentes y detalles llega al iPhone antes de que HealthKit lea. Consulta [Extracción canónica](/es/docs/cli-extract/) para selectores de objetos, punteros JSON, JSONL y recibos.

## Archivos generados en producción

El modo de archivo directo solicita al iPhone que ejecute los exportadores de producción de Health.md y luego transfiere los archivos resultantes a un destino informático explícito.

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

El destino ya debe existir, ser absoluto y no resolverse mediante un enlace simbólico. El modo directo nunca adivina ni utiliza un marcador de aplicación de Mac. `--output` es para salida sin procesar o de extracción; `--destination` es para archivos generados.

De forma predeterminada, una solicitud conserva los formatos guardados, la subcarpeta Health, los nombres de archivos, las plantillas, el modo de escritura, la inyección de notas diarias y solo notas diarias. Desactiva los datos agregados y el modo de solo resumen para esa tarea. Las opciones repetibles `--metric` o `--category` más `--detail` reemplazan solo la métrica y el alcance de métricas y detalle de la tarea. `--use-iphone-settings` refleja todas las configuraciones guardadas y no se puede combinar con selectores.

El iPhone puede almacenar archivos JSON, CSV, Markdown, ZIP, diccionarios de datos, resúmenes, registros individuales, notas diarias y datos auxiliares de proveedores. La CLI valida cada ruta relativa, recuento de bytes, resumen, manifiesto de archivo, identidad de destino y huella digital de solicitud antes de confirmar. Rechaza el recorrido, los ancestros de enlaces simbólicos, la mutación de raíz, las colisiones de rutas y los cambios de resumen. La sobrescritura es atómica. La combinación Append y Markdown utiliza planes persistentes para que un reintento no duplique el contenido.

Los destinos de archivos generados funcionan en macOS y Linux. El protocolo v1 los rechaza en Windows. Los usuarios directos de Windows pueden utilizar la exportación y extracción de datos sin procesar.

## Comportamiento en primer plano y en segundo plano

El emparejamiento y las tareas nuevas requieren la aplicación de iPhone en primer plano. Direct CLI Access no convierte iOS en un servidor de exportación sin cabeza y no puede activar la aplicación a pedido.

Si ya hay una exportación conectada cuando la aplicación pasa a segundo plano, Health.md solicita un tiempo finito de ejecución en segundo plano de iOS. La exportación puede finalizar durante ese intervalo. Si iOS agota el tiempo asignado, la conexión se cierra y la tarea persistente se pausa. Vuelve a abrir Health.md y reanuda la misma tarea.

El iPhone muestra un banner de actividad global durante la tarea directa. Incluye fase de captura y transferencia, días completados, progreso de bytes y estado de pausa o finalización sin mostrar valores de salud.

## Reanudación y cancelación persistentes

Las tareas directas caducan siete días después de su creación. El tiempo de espera, Ctrl-C, muerte del proceso, desconexión y vencimiento en segundo plano no los cancelan.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

La reanudación mantiene las fechas originales, la configuración, el destino, la huella digital de la solicitud, el dispositivo y la frontera de la partición. No se puede asignar a una tarea de archivos a un destino diferente durante la reanudación.

La cancelación registra una solicitud persistente, pero solo pasa a un estado terminal después de que el iPhone la confirma. Si el iPhone no está disponible, el estado sigue siendo `cancellation_pending`. Vuelve a abrir el mismo iPhone e intenta cancelar de nuevo.

## Modelo de seguridad

- El emparejamiento utiliza el acuerdo de clave efímero Curve25519 y pruebas de transcripción vinculadas al código de seis dígitos.
- La reconexión demuestra un secreto almacenado aleatoriamente y ambas identidades de instalación.
- Cada conexión deriva claves y nonces nuevos.
- Los mensajes y marcos binarios utilizan ChaCha20-Poly1305 con comprobaciones de secuencia monótona.
- Las particiones utilizan manifiestos SHA-256 y una frontera de resumen encadenada.
- La confianza del iPhone se almacena en Keychain.
- La confianza portátil utiliza Keychain, Secret Service o Windows Credential Manager y nunca recurre al texto sin formato.
- Los spools y los diarios utilizan almacenamiento de aplicaciones privado y excluyen las copias de seguridad cuando la plataforma lo admite.

Manual IP permanece cifrado en una red local o Tailscale. Tailscale también protege la ruta de la red, pero no reemplaza la autenticación de la aplicación Health.md.

## Errores comunes

| Error | Acción |
|---|---|
| `direct_not_paired` | Empareje esta instalación CLI con el iPhone. |
| `direct_device_selection_required` | Proporciona el `--device` de confianza previsto. |
| `direct_trust_invalid` | Conserva el diagnóstico. Restablece la confianza solo cuando no sea posible recuperarla. |
| `direct_iphone_unavailable` | Comprueba el estado de primer plano de la aplicación, la alternancia de acceso, la dirección, el puerto, el permiso y la accesibilidad de LAN o Tailscale. |
| `direct_export_paused` | Inspecciona la tarea, vuelve a abrir el iPhone y reanúdala. |
| `direct_cancellation_pending` | Vuelve a abrir el iPhone emparejado e intenta cancelar de nuevo. |
| `transport_unsupported` | Usa Manual IP o Tailscale en el cliente portátil. |
| `backend_unsupported` | Usa el backend de la aplicación para Mac para consultas, evidencia, diagnóstico, métricas o MCP. |
| `invalid_direct_raw_response` | No uses la salida. Conserva los diagnósticos de validación. |
| `invalid_direct_file_receipt` | No repares archivos manualmente. Inspecciona y reanuda la tarea. |
| `job_expired` | El período de conservación del estado, de siete días, ha terminado. Confírmalo antes de iniciar una tarea nueva. |

## Relacionado

<div class="related">
<a href="/es/docs/cli/"><span>Resumen</span>Health.md CLI: instale los asistentes incluidos y elija el backend correcto.</a>
<a href="/es/docs/cli-extract/"><span>Datos</span>Extracción canónica: seleccione y emita datos Health.md en forma de fuente.</a>
<a href="/es/docs/cli-jobs/"><span>Fiabilidad</span>Tareas persistentes y automatización: reanudar, cancelar, resultados parciales y scripting.</a>
<a href="/es/docs/reference/connected-mac-iphone-protocol/"><span>Protocolo</span>Referencia de Mac y iPhone conectados: capacidades, transferencia acotada y estados de resultados.</a>
</div>
