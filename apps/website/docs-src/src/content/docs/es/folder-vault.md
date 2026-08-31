---
title: "Carpeta y bóveda"
description: "Elige dónde viven tus archivos Markdown y nombra la subcarpeta donde se escribirán las exportaciones. La bóveda es cualquier carpeta de iOS: Obsidian, Archivos, iCloud Drive y los proveedores de archivos de terceros funcionan."
---

## Qué significa "bóveda" aquí
<p>La app usa <em>bóveda</em> como nombre genérico para la carpeta que elegiste, independientemente de si usas Obsidian. Si usas Obsidian, apunta a la raíz de tu bóveda de Obsidian. Si no, elige cualquier carpeta: <code>Documents/Health</code> de iCloud Drive, una carpeta de En mi iPhone, etc.</p>

## Cómo funciona el selector
<p>Al tocar la fila de la bóveda, se abre el selector de documentos estándar de iOS (<code>UIDocumentPickerViewController</code>). Cuando eliges una carpeta, iOS devuelve una <em>URL con alcance de seguridad</em>: un identificador de larga duración que permite que la app siga accediendo a la carpeta entre ejecuciones sin volver a pedir permiso. La app lo guarda como marcador en <code>UserDefaults</code>.</p>

## Nombre de subcarpeta
<p>Después de elegir la bóveda, se te pide que nombres la subcarpeta donde irán las exportaciones. El valor predeterminado es <code>Health</code>. Lo que elijas se convierte en el prefijo de la ruta de cada archivo exportado:</p>

<div class="doc-diagram folder-tree" aria-label="Árbol de carpetas de ejemplo para exportaciones de Health.md">
<span>{vault}/</span>
<span>└─ <span class="accent">{subfolder}/</span> <span class="dim">← lo que nombras en Health.md</span></span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-28-tuesday.md</span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-27-monday.json</span>
<span>&nbsp;&nbsp;&nbsp;└─ _healthmd_data_dictionary.json</span>
</div>

<p>Puedes cambiar la subcarpeta más adelante desde <em>Ajustes → Bóveda de Obsidian</em>. Los archivos existentes no se mueven.</p>

## Comportamiento entre apps
<div class="options">
<div class="option"><strong>Obsidian</strong><p>Elige la raíz de la bóveda de Obsidian. Configura la subcarpeta, por ejemplo <code>Health</code>, para que las exportaciones aparezcan como una carpeta en el árbol de tu bóveda.</p></div>
<div class="option"><strong>iCloud Drive</strong><p>Elige una carpeta dentro de iCloud Drive. Los archivos se sincronizan automáticamente con todos tus dispositivos Apple.</p></div>
<div class="option"><strong>En mi iPhone</strong><p>Elige una carpeta que hayas creado en Archivos → En mi iPhone. Solo local, sin sincronización.</p></div>
<div class="option"><strong>Proveedores de terceros</strong><p>Dropbox, Google Drive, Working Copy, etc.: cualquier proveedor que exponga una integración con la app Archivos funciona del mismo modo.</p></div>
</div>

<div class="callout">
<strong>Particularidad de iOS.</strong>
<p style="margin-top:6px;">Si iOS revoca el marcador con alcance de seguridad, algo poco común que suele ocurrir solo si la carpeta subyacente se elimina o se mueve, las exportaciones empezarán a fallar. La solución es volver a elegir la bóveda desde <em>Ajustes</em>.</p>
</div>

## Reemplazar o mover una carpeta seleccionada con seguridad

Cuando un marcador guardado se resuelve en otra ruta, Health.md vuelve a vincular la carpeta automáticamente si la identidad persistente confirma que es la misma. También puede aceptar un marcador con ámbito de seguridad que se resuelva correctamente cuando ni la carpeta guardada ni la resuelta exponen una identidad persistente, algo habitual en proveedores en la nube. Una ruta parecida nunca basta como prueba. El historial sigue mostrando la etiqueta de destino respetuosa con la privacidad que usó cada ejecución.

Vuelve a seleccionar la carpeta si fue eliminada, se revocó el acceso, las identidades persistentes entran en conflicto o solo uno de los lados aporta identidad y el movimiento no puede verificarse. Health.md no escribe en un destino ambiguo. Como cada [perfil de exportación](/es/docs/export-profiles/) posee su destino, verifica o vuelve a seleccionar la carpeta afectada para cada perfil.

## Contenido relacionado

<div class="related">
  <a href="/es/docs/export-profiles/"><span>Perfiles</span>Administra el acceso a carpetas y los destinos por perfil.</a>
  <a href="/es/docs/onboarding/"><span>Anterior</span>Introducción: donde eliges la bóveda por primera vez.</a>
  <a href="/es/docs/export/"><span>Siguiente</span>Ejecuta una exportación en tu nueva bóveda.</a>
  <a href="/es/docs/format/"><span>Personalizar</span>Personalización del formato: cómo se escriben los archivos dentro de la subcarpeta.</a>
</div>
