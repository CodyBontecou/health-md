---
title: "Primera exportación desde el iPhone"
description: "Autoriza Apple Health, elige un destino en Archivos, obtén una vista previa del resultado de Health.md, ejecuta una primera exportación pequeña desde el iPhone y verifica los archivos escritos."
---

Sigue esta guía para producir una exportación pequeña y verificable antes de cambiar las métricas, el formato o la automatización. Health.md solo lee las categorías de Apple Health que autorices en iOS y escribe los archivos generados en la carpeta que elijas.

<div class="availability available">
<strong>Ya disponible · Health.md for iPhone</strong>
<p>La primera exportación está incluida en el límite gratuito. Puedes configurar más adelante la programación y las demás funciones de pago.</p>
</div>

## Antes de empezar

Necesitas:

- Health.md instalado en un iPhone que contenga datos de Apple Health;
- permiso para leer al menos una categoría de Apple Health;
- un destino de Archivos con permiso de escritura, como iCloud Drive, En mi iPhone o una bóveda de Obsidian.

Para que la primera ejecución sea lo más breve posible, conserva las métricas predeterminadas y el formato Markdown. Empieza con **Ayer** u otro intervalo de un solo día en lugar de exportar todo el historial disponible.

## 1. Completa la configuración del iPhone

La primera vez que abras la aplicación, toca **Start Setup** y completa los siete pasos de la introducción. Autoriza las categorías de salud que quieras, revisa el resultado de ejemplo, elige una carpeta en Archivos y continúa hasta **Ready**. Cuando aparezca el paso de desbloqueo, puedes seguir usando el límite gratuito.

Si ya completaste la introducción, abre la pestaña **Exportar** y confirma que Apple Health y la carpeta local estén listos. Usa el control de carpeta para sustituir un destino que ya no exista o al que no se pueda acceder.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Abrir a tamaño completo la captura de la pantalla de introducción">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Pantalla de bienvenida de la introducción de Health.md, en el paso 1 de 7, con el botón Start Setup." />
  </a>
  <figcaption>Start Setup presenta el archivo local, las notas programadas y el modelo de carpetas antes de solicitar acceso. La interfaz de esta captura auténtica permanece en inglés.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-setup-required.webp" target="_blank" rel="noopener" aria-label="Abrir a tamaño completo la captura que muestra la configuración pendiente">
    <img src="/docs/assets/docs/iphone-first-export/export-setup-required.webp" width="1206" height="2622" loading="lazy" alt="Pestaña Export de Health.md con Health desconectado, Choose Folder disponible, Local iPhone Folder seleccionado y botones para elegir el intervalo de fechas." />
  </a>
  <figcaption>Los indicadores de preparación muestran claramente si falta configurar Health o la carpeta. Esta captura de referencia también conserva la interfaz en inglés y muestra de forma intencional que ambos requisitos están incompletos.</figcaption>
</figure>
</div>

## 2. Elige una exportación pequeña

En la pestaña **Exportar**:

1. Selecciona **Carpeta local del iPhone** como destino.
2. Elige **Ayer** o un intervalo personalizado de un solo día.
3. Conserva la selección predeterminada de métricas para la primera ejecución.
4. Mantén seleccionado **Markdown**. Podrás añadir CSV, JSON u Obsidian Bases cuando hayas comprobado que el flujo básico funciona.

Un intervalo corto facilita la identificación de problemas con los permisos, las categorías vacías o el destino. También evita confundir una primera solicitud de larga duración con una exportación fallida.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/es/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Abrir a tamaño completo la captura de selección de métricas">
    <img src="/docs/assets/docs/es/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Pantalla actual de Métricas de salud con 217 de 219 métricas habilitadas, el interruptor de métricas estándar activado, el campo de búsqueda y las categorías desplegables Sueño, Actividad y Corazón." />
  </a>
  <figcaption>El total de métricas depende de la versión instalada de la aplicación y de los permisos. Esta captura localizada muestra 217 de 219 métricas habilitadas y las métricas estándar activadas; no necesitas alcanzar ese total para realizar la primera exportación.</figcaption>
</figure>

## 3. Obtén una vista previa antes de escribir

Toca **Vista previa**. La vista previa necesita acceso a Apple Health, pero no una carpeta local con permiso de escritura. Por eso resulta útil para distinguir un problema de permisos de lectura de un problema con Archivos.

Comprueba que la vista previa muestre:

- la fecha solicitada;
- los nombres y las unidades esperados de las métricas;
- los valores ausentes o no disponibles de forma explícita, en lugar de ceros inventados;
- el formato y la estructura de nombres de archivo seleccionados.

Vuelve a la pestaña **Exportar** si necesitas ajustar las fechas, las métricas o el formato.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/es/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Abrir a tamaño completo la captura de la vista previa de exportación">
    <img src="/docs/assets/docs/es/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Vista previa de exportación de Health.md con la estimación de una exportación Markdown de un día, períodos acumulados, el destino y el nombre de archivo generado." />
  </a>
  <figcaption>La vista previa permite revisar el resultado sin escribirlo. Esta captura determinista de la documentación usa datos de muestra de Health e indica explícitamente que no hay ninguna bóveda seleccionada.</figcaption>
</figure>

## 4. Exporta y verifica

Toca **Exportar datos**. Si la configuración está incompleta, Health.md indica qué requisito de Apple Health o de la carpeta falta, en lugar de iniciar de forma silenciosa una escritura parcial.

Al terminar:

1. Revisa en la aplicación qué archivos se escribieron, se omitieron o produjeron errores.
2. Abre la aplicación Archivos y ve a la carpeta que elegiste.
3. Abre uno de los archivos generados y comprueba la fecha, las unidades y el frontmatter.
4. Conserva los detalles del resultado para diagnosticar problemas; no des por hecho que la operación terminó correctamente solo porque el botón volvió al estado inactivo.

<div class="callout">
<strong>¿No hay datos para el día seleccionado?</strong>
<p style="margin-top:6px;">Prueba con un día que sepas que contiene datos de actividad o sueño. Después, revisa la autorización de Health y la selección de métricas. Un intervalo autorizado pero vacío no es lo mismo que un error de transporte o escritura.</p>
</div>

## Siguientes pasos

<div class="related">
  <a href="/es/docs/metrics/"><span>Elegir datos</span>Busca métricas de Apple Health y ajusta las categorías o los permisos especiales.</a>
  <a href="/es/docs/format/"><span>Dar forma al resultado</span>Configura formatos, fechas, unidades, frontmatter, plantillas y nombres de archivo.</a>
  <a href="/es/docs/scheduling/"><span>Automatizar</span>Programa exportaciones periódicas después de verificar una ejecución manual.</a>
  <a href="/es/docs/folder-vault/"><span>Corregir un destino</span>Conoce los proveedores de Archivos, el acceso a carpetas y la recuperación.</a>
</div>
