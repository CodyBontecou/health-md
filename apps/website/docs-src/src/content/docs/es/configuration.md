---
title: Configura tu agente
description: Elige la interfaz MCP o CLI de Health.md, configura Codex, Claude u otro cliente local y conecta un iPhone emparejado sin enviar HealthKit a través de un servicio en la nube.
---

La aplicación publicada para Mac incluye dos herramientas auxiliares locales firmadas: `healthmd-mcp` para las herramientas tipadas del agente y `healthmd` para flujos de trabajo explícitos de la CLI. También existe una CLI multiplataforma independiente con MCP directo para iPhone, documentada como vista previa hasta que su primer paquete público complete las pruebas de lanzamiento con dispositivos físicos.

<div class="callout">
<strong>HealthKit permanece en el iPhone.</strong>
<p style="margin-top:6px;">La configuración permite que un cliente local acceda a las interfaces limitadas de Health.md. No concede al dispositivo local ni al agente acceso directo a HealthKit, ni sube tus datos de salud originales a una nube de Health.md.</p>
</div>

## Elige una interfaz

| Objetivo | Empieza con | Continúa con |
|---|---|---|
| Permitir que Codex o Claude consulten y representen gráficamente datos de salud en el Mac | `healthmd-mcp` incluido mediante stdio | [Servidor MCP y herramientas (en inglés)](/docs/mcp/) |
| Exportar JSON canónico o archivos generados desde un script en el Mac | CLI `healthmd` incluida | [CLI (en inglés)](/docs/cli/) |
| Conectarse directamente a un iPhone abierto sin la aplicación para Mac | CLI directa y portátil (**vista previa**) | [Acceso directo al iPhone (en inglés)](/docs/cli-direct/) |
| Desarrollar con las estructuras exactas de solicitud y respuesta | API de loopback o contratos públicos | [API de loopback (en inglés)](/docs/agent-api/) |
| Analizar esquemas, registros, evidencias o fixtures generados | Referencia versionada | [Contratos de datos (en inglés)](/docs/reference/) |

Las opciones de backend y transporte son explícitas; Health.md no cambia de forma silenciosa del acceso directo al iPhone a la aplicación para Mac.

## Codex con la aplicación para Mac

<div class="availability available">
<strong>Ya disponible · herramienta auxiliar firmada para Mac</strong>
<p>Instala Health.md for Mac, abre su pantalla <strong>CLI</strong> y, si la aplicación no está en <code>/Applications</code>, copia la ruta que se muestra para el servidor MCP incluido.</p>
</div>

Añade la herramienta auxiliar firmada `healthmd-mcp`, incluida en la aplicación, a `~/.codex/config.toml`:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

Reinicia Codex, llama a `healthmd_doctor` y, después, a `healthmd_metrics` y a una herramienta tipada sencilla, como `healthmd_metric_chart`. El servidor incluido ofrece 21 herramientas, entre ellas la comprobación de la aplicación para Mac, los trabajos de actualización del contexto cifrado, la evidencia y las visualizaciones.

## Claude Desktop o Claude Code en el Mac

Añade la herramienta auxiliar incluida a la configuración MCP de Claude Desktop o a un archivo `.mcp.json` de confianza para Claude Code:

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

Reinicia el cliente después de modificar la configuración. Las configuraciones limitadas al proyecto también exigen confiar en el espacio de trabajo y aprobar el servidor de forma explícita. Mantén abiertas las aplicaciones del Mac y del iPhone cuando una herramienta necesite datos recientes de HealthKit.

## Cualquier cliente MCP stdio en el Mac

Configura un único proceso local:

```text
command: /Applications/Health.md.app/Contents/Helpers/healthmd-mcp
arguments: none
transport: stdio
```

El host controla stdin y el ciclo de vida del proceso. No inicies la herramienta auxiliar como si fuera un comando interactivo normal ni lo envuelvas en un shell que modifique la salida JSON-RPC. Usa `tools/list` de MCP para descubrir los esquemas exactos que ofrece la aplicación instalada.

## Configuración directa y portátil

<div class="availability preview">
<strong>Vista previa · aún no disponible como paquete público</strong>
<p>La CLI multiplataforma en Rust, <code>healthmd setup codex</code>, el servidor <code>healthmd mcp serve</code> incluido en el mismo binario y el emparejamiento directo en Linux/Windows ya están implementados, pero aún esperan su primer lanzamiento público aprobado.</p>
</div>

Después de la publicación, `healthmd setup codex` configurará Codex de manera idempotente e iniciará el emparejamiento directo con el iPhone. Hasta entonces, no dependas de URLs de Homebrew, crates.io, instaladores o lanzamientos de GitHub que todavía no se hayan publicado. La página [CLI directa para iPhone (en inglés)](/docs/cli-direct/) documenta el comportamiento previsto del transporte y del protocolo.

## Flujos de trabajo explícitos de la CLI

Para realizar una extracción canónica o una automatización orientada a archivos, ejecuta `healthmd` directamente en lugar de pedirle a un host MCP que transporte un cuerpo de datos de origen grande:

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

La disponibilidad y la gramática no son iguales en la herramienta auxiliar incluida para Mac y en la CLI multiplataforma independiente. Consulta [Health.md CLI (en inglés)](/docs/cli/) antes de copiar comandos en una automatización desatendida.

## Enlace portátil y comprobación de preparación

<div class="availability preview">
<strong>Vista previa · flujos de trabajo directos y portátiles</strong>
<p>Estos pasos describen el próximo paquete multiplataforma. La ruta MCP incluida y ya disponible para Mac usa en su lugar la conexión existente entre la aplicación para Mac y el iPhone.</p>
</div>

Los flujos de trabajo directos de MCP y la CLI requieren emparejar una sola vez un dispositivo de confianza con Health.md en el iPhone. El emparejamiento usa un canal cifrado y autenticado, además del almacenamiento nativo de credenciales en macOS, Linux o Windows.

1. Activa **Acceso directo por CLI** en Health.md en el iPhone.
2. Inicia el emparejamiento desde `healthmd setup codex` o `healthmd direct pair`.
3. Aprueba en el iPhone la solicitud de emparejamiento de alcance limitado.
4. Mantén Health.md en primer plano al iniciar una consulta o exportación.
5. Llama a `healthmd_doctor` en MCP o a `healthmd status` en la CLI portátil antes de ejecutar tareas más grandes.

Consulta [Acceso directo al iPhone (en inglés)](/docs/cli-direct/) para conocer Manual IP, Tailscale, el puerto, los dispositivos de confianza, el uso en primer plano y las opciones de recuperación.

## Límites de la configuración

La configuración de un agente local **no** concede:

- lecturas o escrituras arbitrarias en HealthKit;
- acceso arbitrario al sistema de archivos;
- URLs, comandos de shell, prompts, raíces o muestreos arbitrarios mediante MCP;
- permiso para ocultar datos ausentes, cobertura, unidades, evidencia o limitaciones;
- permiso para reanudar, cancelar o sobrescribir archivos generados sin la aprobación correspondiente.

Para obtener un resultado completo, revisa el alcance solicitado, la cobertura, el recorrido, las limitaciones y el esquema de origen, no solo si el proceso terminó correctamente.

## Continúa

<div class="related">
  <a href="/docs/mcp/"><span>Interfaz de herramientas</span>Consulta las 21 herramientas disponibles para Mac, la vista previa portátil con 17 herramientas, MCP Apps, los esquemas, la paginación, las exportaciones y los límites del sandbox (en inglés).</a>
  <a href="/docs/agent-queries/"><span>Primeras preguntas</span>Ejecuta flujos de trabajo tipados para métricas, sueño, entrenamientos, comparaciones, cobertura y evidencia (en inglés).</a>
  <a href="/docs/cli-extract/"><span>Datos canónicos</span>Extrae documentos seleccionados del esquema v7 y registros de origen sin colocar cuerpos de datos grandes en el chat (en inglés).</a>
  <a href="/docs/reference/"><span>Contratos</span>Consulta estructuras de datos versionadas, inventarios de campos, fixtures generados y recetas de integración (en inglés).</a>
</div>
