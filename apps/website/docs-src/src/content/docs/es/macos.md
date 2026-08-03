---
title: "Aplicación para macOS"
description: "Usa Health.md for Mac como destino de exportación del iPhone, host local para CLI y MCP, almacén cifrado de contexto de salud, visor de historial y autoridad de carpeta."
---

Health.md for Mac tiene dos funciones locales:

1. recibe tareas de exportación del iPhone y escribe archivos en una carpeta que eliges;
2. aloja la CLI de loopback, la API de consultas, el contexto de salud cifrado y el adaptador MCP que usan los agentes locales.

Apple Health permanece en el iPhone. La app del Mac no lee HealthKit directamente.

## Áreas principales

<div class="options">
<div class="option"><strong>Sincronización</strong><p>Muestra si el Mac es visible y está listo para tareas de exportación del iPhone.</p></div>
<div class="option"><strong>Carpeta de destino</strong><p>Guarda un marcador con alcance de seguridad para salidas Markdown, JSON, CSV, Bases, acumuladas, ZIP y notas diarias.</p></div>
<div class="option"><strong>Programación</strong><p>Mantiene visibles la programación y el estado de preparación del lado del Mac. El iPhone sigue proporcionando los datos de HealthKit.</p></div>
<div class="option"><strong>Historial</strong><p>Registra resultados de exportación, progreso persistente, errores y contexto de reintento para archivos escritos desde el escritorio.</p></div>
<div class="option"><strong>Ajustes</strong><p>Muestra el estado del destino, controles de retención del contexto cifrado y configuración local de la CLI.</p></div>
<div class="option"><strong>Barra de menús</strong><p>Ofrece acceso rápido a estado, ajustes y app mientras Health.md permanece disponible localmente.</p></div>
<div class="option"><strong>CLI</strong><p>Instala las herramientas auxiliares incluidas <code>healthmd</code> y <code>healthmd-mcp</code>, copia prompts de configuración, instala la habilidad opcional de agente y muestra comandos probados.</p></div>
</div>

## Configurar un destino Mac

1. Instala y abre Health.md en el Mac.
2. Elige una carpeta de destino en el disco local, iCloud Drive o dentro de una bóveda de Obsidian.
3. En el iPhone, activa la conectividad con Mac desde la pestaña Sincronizar.
4. En el iPhone, elige Mac conectado como destino de exportación.
5. Configura la exportación y toca Exportar.

El iPhone captura los datos de HealthKit y la instantánea de ajustes efectivos. Los pares actuales transfieren particiones acotadas y validadas con suma de comprobación. El Mac usa los exportadores de producción y escribe los archivos solicitados.

<div class="callout">
<strong>Limitación de HealthKit.</strong>
<p style="margin-top:6px;">El Mac no puede consultar Apple Health por sí solo. Las exportaciones nuevas y el contexto de agente requieren que la app conectada del iPhone esté abierta. Las consultas cifradas en caché pueden ejecutarse sin una conexión nueva con el iPhone cuando la cobertura almacenada es suficiente.</p>
</div>

## Configuración de CLI y agente

Abre el área **CLI** de la app del Mac para:

- ver las rutas exactas de las herramientas auxiliares firmadas en este paquete de app;
- copiar alias o comandos de enlace simbólico para `~/.local/bin`;
- copiar un prompt de configuración asistida por agente;
- instalar la habilidad opcional `healthmd-cli` en un directorio que elijas;
- ver comandos actuales de estado, doctor, extracción, consulta, sueño, entrenamiento, workout, cobertura y exportación;
- revisar errores habituales de disponibilidad.

La app nunca edita archivos de inicio del shell ni instala en un directorio del sistema sin tu acción.

Empieza con:

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --category Sleep --yesterday
```

Consulta [Health.md CLI](/es/docs/cli/) para la selección de backend y [Agentes locales](/es/docs/agents/) para la arquitectura de consultas.

## Contexto de salud cifrado

Las solicitudes de consulta y evidencia con datos recientes usan un modo dedicado de adquisición de contexto. El iPhone lee la métrica, fuente, fecha y alcance de detalle exactos solicitados. No crea archivos de exportación ni cambia las preferencias de exportación guardadas.

El Mac guarda cada día de propietario compacto en un blob AES-256-GCM autenticado de forma independiente. Un elemento de Keychain exclusivo de este dispositivo y disponible cuando está desbloqueado contiene la clave de cifrado aleatoria. Los nombres de archivo son aleatorios y no revelan fechas ni nombres de métricas.

Ajustes informa el recuento de días de propietario cifrados y el intervalo de fechas. Dos acciones independientes controlan la retención:

- **Eliminar contexto anterior** elimina los días de propietario estrictamente anteriores al límite elegido;
- **Eliminar todo el contexto cifrado** elimina todos los archivos de contexto y la clave dedicada de Keychain.

La retención del contexto nunca elimina datos de Apple Health, archivos de exportación, marcadores de destino del Mac ni credenciales de proveedores conectados.

## Límite de la API de loopback

La app del Mac escucha en `127.0.0.1` y `::1` en el puerto `17645` para rutas locales de estado, exportación, consulta, evidencia, actualización y tareas persistentes.

No hay token bearer ni registro de agente. Cualquier proceso local puede llamar a la API mientras la app está abierta. Nunca expongas, proxifiques ni tunelices el puerto hacia otra máquina.

La herramienta auxiliar en sandbox `healthmd-mcp` solo acepta endpoints HTTP de loopback canónicos y ofrece herramientas sin shell, archivos arbitrarios, SQL, recuperación de URLs, recursos, prompts, raíces ni muestreo.

## Direct CLI Access es independiente

El ajuste **Direct CLI Access** del iPhone crea una relación de confianza separada entre una CLI con capacidad directa y el iPhone. Puede omitir la app del Mac para exportación sin procesar, extracción canónica, archivos generados, estado, reanudación y cancelación.

El modo directo no usa el contexto de consulta cifrado de la app del Mac. En su lugar, `healthmd mcp serve` portátil ejecuta consultas tipadas de datos recientes directamente en el iPhone en primer plano, usando la misma identidad ejecutable que el emparejamiento. Consulta [Direct iPhone CLI](/es/docs/cli-direct/) para emparejamiento y compatibilidad de plataformas.

## Contenido relacionado

<div class="related">
  <a href="/es/docs/sync/"><span>Destino</span>Sincronización con Mac: empareja iPhone y Mac para exportaciones locales de archivos.</a>
  <a href="/es/docs/cli/"><span>Terminal</span>Health.md CLI: instala herramientas auxiliares, selecciona un backend y opera comandos.</a>
  <a href="/es/docs/agents/"><span>Contexto local</span>Agentes: adquisición acotada, almacenamiento cifrado, evidencia y retención.</a>
  <a href="/es/docs/mcp/"><span>Herramientas</span>Servidor MCP local: configuración, catálogo de herramientas y límites del sandbox.</a>
  <a href="/es/docs/scheduling/"><span>Flujo</span>Programación: automatiza exportaciones recurrentes.</a>
</div>
