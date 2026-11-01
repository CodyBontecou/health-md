---
title: "Primera exportación desde el iPhone"
description: "Autoriza Apple Health, elige un destino en Archivos, obtén una vista previa del resultado de Health.md, ejecuta una primera exportación pequeña desde el iPhone y verifica los archivos escritos."
---

Sigue esta guía para producir una exportación pequeña y verificable antes de cambiar las métricas, el formato o la automatización. Health.md solo lee las categorías de Apple Health que autorices en iOS y escribe los archivos generados en la carpeta que elijas.

<div class="availability available">
<strong>Disponible ahora · Health.md para iPhone</strong>
<p>Las exportaciones requieren una prueba activa, una suscripción o acceso Lifetime. Puedes configurar programaciones y otras automatizaciones más adelante.</p>
</div>

## Antes de empezar

Antes de empezar, asegúrate de tener:

- [Health.md en el App Store](https://apps.apple.com/app/health-md/id6757763969), instalado en un iPhone con datos de Apple Health
- permiso para leer al menos una categoría de Apple Health
- una carpeta con permiso de escritura en Archivos: iCloud Drive, En mi iPhone o una bóveda de Obsidian.

Mantén las métricas predeterminadas y el formato Markdown. Selecciona **Ayer** para un rango de un día.

## 1. Termina la configuración del iPhone

Health.md muestra cinco pasos de configuración. Ninguno bloquea el avance: puedes omitir el acceso a Apple Health y la carpeta y resolverlos después.

La primera vez que abras la aplicación, toca **Conectar Apple Health**. Autoriza las categorías de salud que quieras, revisa el resultado de ejemplo, elige una carpeta en Archivos y continúa hasta el último paso.

Tras la configuración, la aplicación se abre en **Archivo**. Si Apple Health o la carpeta necesitan algo, la tarjeta **Requiere atención** de arriba indica qué corregir.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Abrir la captura de la configuración a tamaño completo">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Configuración de Health.md en el paso 1 de 5 con tres pasos y el botón para conectar Apple Health." />
  </a>
  <figcaption>La configuración explica qué lee Health.md y dónde se guardan los archivos antes de pedir acceso. La interfaz de esta captura permanece en inglés.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-now.webp" target="_blank" rel="noopener" aria-label="Abrir la captura de Exportar ahora a tamaño completo">
    <img src="/docs/assets/docs/iphone-first-export/export-now.webp" width="1206" height="2622" loading="lazy" alt="Hoja Exportar ahora de Health.md con Ayer seleccionado, un interruptor de solo resumen del rango, un resumen de un archivo y un día, y un botón de exportar." />
  </a>
  <figcaption>Exportar ahora muestra lo que se escribirá antes de empezar. Esta captura de referencia también conserva la interfaz en inglés.</figcaption>
</figure>
</div>

## 2. Elige una exportación pequeña

Toca el botón redondo **Exportar ahora** junto a la barra de pestañas. Después:

1. Selecciona **Ayer**.
2. Deja desactivado **Solo resumen del rango de fechas**.
3. Comprueba que **Se escribirá** indica tu carpeta y aproximadamente un archivo para un día.

La automatización predeterminada usa la selección de métricas predeterminada y **Markdown**. Para cambiarlas, abre **Automatizaciones**, elige la automatización y luego **Métricas** o **Formatos**. Añade CSV, JSON u Obsidian Bases cuando esta exportación funcione. Un rango corto facilita encontrar problemas de permisos, de datos vacíos y de carpeta.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/es/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Abrir la captura de la selección de métricas a tamaño completo">
    <img src="/docs/assets/docs/es/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Página Métricas de Health.md con el número de métricas activas, los botones Recomendado, Seleccionar todo y Deseleccionar todo, un campo de búsqueda y categorías con recuentos." />
  </a>
  <figcaption>El total de métricas depende de la versión de la app y de los permisos. Esta captura localizada muestra 217 de 219 métricas habilitadas.</figcaption>
</figure>

## 3. Revisa la vista previa antes de escribir

En **Exportar ahora**, toca **Vista previa**. La vista previa necesita acceso a Apple Health, pero no una carpeta con permiso de escritura.

Usa la vista previa para detectar un problema de permisos de Apple Health antes de probar la carpeta.

Comprueba que la vista previa muestre:

- la fecha solicitada
- los nombres de métricas y las unidades esperados
- valores ausentes o no disponibles en lugar de ceros falsos
- el formato elegido y la estructura del nombre de archivo.

Cierra la vista previa y cambia los ajustes de la automatización si necesitas cambiar métricas o formatos.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/es/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Abrir la captura de la vista previa a tamaño completo">
    <img src="/docs/assets/docs/es/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Vista previa de exportación de Health.md con el intervalo de sueño, la estimación de un día en Markdown, el periodo de resumen, la carpeta de destino y el nombre de archivo generado." />
  </a>
  <figcaption>Este ejemplo usa datos de salud de muestra.</figcaption>
</figure>

## 4. Exporta y verifica

Toca **Exportar ayer**. Si la configuración está incompleta, Health.md indica qué falta de Apple Health o de la carpeta.

Cuando termine la exportación:

1. Revisa el resultado para ver los archivos escritos, omitidos o fallidos. El día aparece en el calendario de **Archivo**.
2. Abre la app Archivos y la carpeta elegida.
3. Abre un archivo generado y comprueba que la fecha, las unidades y el frontmatter sean correctos.
4. Conserva los detalles del resultado si necesitas investigar un problema.

Un día cubierto en el calendario es un resumen; toca el día para ver el estado de cada automatización en esa fecha.

<div class="callout">
<strong>¿No hay datos para el día elegido?</strong>
<p style="margin-top:6px;">Elige un día con datos de actividad o sueño. Después revisa la autorización de Apple Health y la selección de métricas. Un rango vacío no es un error de escritura.</p>
</div>

## Siguientes pasos

<div class="related">
  <a href="/es/docs/metrics/"><span>Elegir datos</span>Busca métricas de Apple Health y ajusta las categorías o los permisos especiales.</a>
  <a href="/es/docs/format/"><span>Dar forma al resultado</span>Configura formatos, fechas, unidades, frontmatter, plantillas y nombres de archivo.</a>
  <a href="/es/docs/scheduling/"><span>Automatizar</span>Programa exportaciones periódicas después de verificar una ejecución manual.</a>
  <a href="/es/docs/folder-vault/"><span>Corregir un destino</span>Conoce los proveedores de Archivos, el acceso a carpetas y la recuperación.</a>
</div>
