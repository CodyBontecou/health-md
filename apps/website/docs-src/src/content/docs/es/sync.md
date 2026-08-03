---
title: "Sincronización con Mac"
description: "Usa la app complementaria para macOS como destino local. Tu iPhone captura datos y ajustes de HealthKit; luego el Mac renderiza y escribe los archivos solicitados."
---

## Qué es
<p>La sincronización con Mac permite que tu Mac produzca exportaciones sin convertirse en lector de HealthKit. El iPhone sigue siendo la fuente de referencia para los datos de Apple Health: captura los datos diarios seleccionados y una instantánea exacta de los ajustes, y luego transfiere ese trabajo al Mac. El Mac usa los exportadores compartidos para planificar rutas, renderizar los formatos solicitados y escribir los archivos resultantes en la carpeta de destino que elegiste.</p>

<div class="doc-diagram">
  <div class="flow-steps" aria-label="Flujo de exportación con sincronización de Mac">
    <span><strong>iPhone</strong>Captura datos de HealthKit y toma una instantánea de los ajustes efectivos.</span>
    <span><strong>Red local</strong>Transfiere el trabajo versionado a la app cercana del Mac.</span>
    <span><strong>Mac</strong>Renderiza los formatos seleccionados y los escribe en la carpeta elegida.</span>
    <span><strong>Bóveda</strong>Obsidian, iCloud Drive o cualquier carpeta local recibe la exportación final.</span>
  </div>
</div>

## Cómo activarla
<ol>
<li>Instala y abre la app de macOS.</li>
<li>En el Mac, elige una carpeta de destino para que Health.md tenga acceso de escritura.</li>
<li>En el iPhone, abre la pestaña Sincronizar y activa la conectividad con Mac.</li>
<li>Vuelve a la pestaña Exportar del iPhone, elige <em>Mac conectado</em>, configura la exportación y toca Exportar.</li>
</ol>

## Qué se transfiere
<ul>
<li>Una solicitud de exportación versionada que describe el intervalo de fechas y los ajustes efectivos</li>
<li>Mensajes de progreso y capacidades mientras el iPhone captura datos de HealthKit</li>
<li>Tramas acotadas y validadas con suma de comprobación que transportan los datos diarios capturados y la instantánea exacta de ajustes para trabajos de escritura de archivos</li>
<li>Un resultado estructurado de finalización, parcial, error, rechazo o no disponibilidad</li>
</ul>
<p>No se requiere una cuenta ni una nube remota de datos de salud. La sincronización cercana usa Multipeer Connectivity cifrado; Manual IP/Tailscale usa un transporte cifrado emparejado de Network.framework. Ambos dispositivos deben poder comunicarse, y el iPhone sigue siendo el lector de HealthKit.</p>

## Cuándo usarla
<div class="options">
<div class="option"><strong>Bóvedas solo de escritorio</strong><p>Si tu bóveda de Obsidian vive solo en el Mac, este es el camino limpio desde HealthKit en el iPhone hasta archivos en el Mac.</p></div>
<div class="option"><strong>Cargas históricas grandes</strong><p>Mantén los archivos finales en un disco de escritorio mientras el iPhone gestiona la lectura de HealthKit y la configuración de exportación.</p></div>
<div class="option"><strong>Flujos de archivo local</strong><p>Escribe directamente en carpetas respaldadas, versionadas o indexadas en macOS.</p></div>
</div>

<div class="callout">
<strong>Se requiere red local.</strong>
<p style="margin-top:6px;">Ambos dispositivos deben estar cerca y tener permiso para usar redes locales. Los iPhone que solo usan datos móviles no pueden descubrir un destino Mac. Si el estado de preparación dice que el Mac necesita atención, vuelve a abrir la app del Mac y selecciona de nuevo la carpeta de destino.</p>
</div>

## La sincronización con Mac y Direct CLI Access son independientes

La sincronización con Mac empareja el iPhone con la app Health.md para Mac para exportaciones de destino y contexto cifrado de agente. Direct CLI Access empareja el iPhone con una instalación de línea de comandos mediante un dominio de confianza separado. El modo directo puede exportar datos sin procesar o archivos generados sin la app para Mac, pero no puede usar el índice de consulta cifrado del Mac ni MCP.

Consulta [Direct iPhone CLI](/es/docs/cli-direct/) antes de activar el ajuste independiente del iPhone.

## Contenido relacionado

<div class="related">
  <a href="/es/docs/macos/"><span>Escritorio</span>App para macOS: Exportar, Programar e Historial en el Mac.</a>
  <a href="/es/docs/scheduling/"><span>Flujo</span>Programación: automatiza exportaciones recurrentes.</a>
  <a href="/es/docs/cli-direct/"><span>Confianza separada</span>Direct iPhone CLI: empareja una CLI sin enrutar el trabajo por la app del Mac.</a>
  <a href="/es/docs/reference/connected-mac-iphone-protocol/"><span>Protocolo</span>Referencia de Mac-iPhone conectado: capacidades, solicitudes, transferencia acotada y resultados.</a>
</div>
