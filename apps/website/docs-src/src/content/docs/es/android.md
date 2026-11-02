---
title: "Aplicación de Android"
description: "Configure Health.md para Android. Exporte datos Health Connect , seleccione carpetas de Storage Access Framework, programe exportaciones y automatice con Tasker o adb."
---

<div class="docs-hero">
 <p class="docs-eyebrow"> Health Connect a archivos privados </p>
 <p> Health.md para Android lee Health Connect en el dispositivo y escribe Markdown , Obsidian Bases, JSON o CSV en las carpetas que elijas. Este flujo de trabajo de exportación de carpetas no requiere una cuenta Health.md . Las opciones de acceso Google Play y el acceso incluido F-Droid se describen a continuación. </p>
 <div class="docs-actions">
 <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener"> Continúe Google Play </a>
 <a class="docs-button-secondary" href="#distribution-status"> F-Droid estado de publicación </a>
 <a class="docs-button-secondary" href="/es/docs/export/"> Leer documentos de exportación </a>
 </div>
 <p id="distribution-status"> F-Droid está pendiente de publicación del catálogo. Obtenga la versión actual de Android en Google Play . </p>
 </div>

<div class="reference-stats">
 <div> <strong> 106 </strong> Health Connect <span> métricas seleccionables </span> </div>
 <div> <strong> 4 </strong> <span> formatos de exportación </span> </div>
 <div> <strong> 2 </strong> <span> Canales de distribución de Android </span> </div>
 <div> <strong> 0 </strong> <span> Health.md se requieren cuentas en la nube </span> </div>
 </div>

## Qué hace la aplicación de Android

Health.md para Android convierte Health Connect en una revista de salud local. Elija las métricas que necesita y obtenga una vista previa del resultado. Luego, exporte archivos a una carpeta local, una bóveda Obsidian , una carpeta de proveedor sincronizada o un proveedor de documentos de Android grabable.

<div class="options">
 <div class="option"> <strong> Health Connect fuente </strong> <p> Lee actividad, sueño, corazón, signos vitales, medidas corporales, nutrición, entrenamientos y otras categorías a través de las API Health Connect del dispositivo Android. </p> </div>
 <div class="option"> <strong> Obsidian -salida nativa </strong> <p> Escribe notas diarias, YAML/frontmatter, Obsidian notas amigables con Bases, entradas individuales y JSON compatible con el complemento Health.md Obsidian . </p> </div>
 <div class="option"> <strong> Almacenamiento nativo de Android </strong> <p> Utiliza Storage Access Framework para que pueda elegir carpetas expuestas por el almacenamiento local, Obsidian , Google Drive, OneDrive, Syncthing u otro proveedor. </p> </div>
 </div>

## Requisitos

- Android 9/API 28 o posterior.
- Un dispositivo o emulador compatible con Health Connect .
- Health Connect datos de aplicaciones, dispositivos portátiles o servicios de Android que escriben en Health Connect .
- Una carpeta o proveedor de documentos que permite acceso de escritura para exportaciones.

## Primera exportación

1. Instale la versión actual Health.md de Google Play .
2. Abra la configuración ** Health Connect ** y otorgue solo las categorías que desea que Health.md exporte.
3. Elija el destino de exportación a través del selector de carpetas de Android.
4. Elija formatos: Markdown , Obsidian Bases, JSON, CSV o cualquier combinación.
5. Seleccione métricas y rango de fechas.
6. Vista previa de la salida.
7. Toque exportar y verifique los archivos generados en su carpeta o bóveda.

La versión del teléfono Google Play habilitada para suscripción requiere prueba activa, suscripción, de por vida o acceso permanente preservado para exportaciones manuales. Las suscripciones elegibles incluyen una prueba de 7 días; La vida no tiene juicio. La compilación F-Droid incluye acceso ilimitado sin flujo de compra ni restauración.

## Destinos en Android

Android no utiliza el destino de red local iPhone → Mac. En cambio, se basa en el marco de acceso al almacenamiento de Android.

| Destino | estado de Android |
| --- | --- |
| Carpeta del dispositivo local | Compatible con el selector de carpetas |
| Obsidian bóveda | Compatible cuando la carpeta del almacén está expuesta al selector de Android |
| Google Drive, OneDrive, Syncthing, Obsidian Sync y proveedores similares | Compatible cuando el proveedor expone carpetas grabables |
| iPhone /Destino de red local Mac | Específico de la plataforma Apple; no utilizado por Android |

Si un proveedor no expone carpetas grabables a través del selector de Android, Health.md no puede escribir allí directamente de forma segura. Elija una carpeta de proveedor que otorgue acceso de escritura persistente o exporte localmente y sincronice con su herramienta preferida.

## Formatos

La aplicación de Android comparte los mismos objetivos de archivo sin formato que la aplicación de Apple:

| Formato | Úselo para |
| --- | --- |
| Markdown | Resúmenes, plantillas y notas de salud diarios legibles |
| Obsidian Bases | Primeras notas de Frontmatter que se pueden consultar en las vistas de la base de datos Obsidian |
| JSON | Cargas útiles diarias estructuradas para scripts, paneles, cuadernos y el complemento Health.md Obsidian |
| CSV | Flujos de trabajo de análisis y hojas de cálculo |

Las exportaciones JSON de Android están diseñadas para ser compatibles con las visualizaciones Health.md de Obsidian . Las exportaciones de Markdown y Bases utilizan el mismo flujo de trabajo centrado en el tema principal documentado en la [guía de formato](/es/docs/format/).

## Programación y automatización

En la versión del teléfono Google Play con suscripción habilitada, las exportaciones programadas requieren prueba activa, suscripción, de por vida o acceso permanente preservado; están incluidos en la compilación F-Droid . Usan una alarma exacta de un solo disparo cuando otorgas acceso a las alarmas y recordatorios de Android, con un trabajo duradero WorkManager como respaldo. Sin acceso exacto a la alarma, WorkManager se convierte en el programador principal, por lo que el tiempo seleccionado es un objetivo en lugar de una garantía estricta. Health.md registra el historial de exportación, puede recuperar fechas programadas perdidas y le permite volver a intentar ejecuciones fallidas.

Para Tasker, adb u otras herramientas de automatización, Health.md expone intenciones de transmisión solo explícitas. Las personas que llaman externamente deben dirigirse directamente al componente receptor:

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

Ejemplos:

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

La automatización utiliza el perfil activo de forma predeterminada, incluido su destino congelado, formatos, métricas, contabilidad e historial. Un `PROFILE` extra suministrado puede seleccionar un ID o nombre de perfil estable. Una referencia desconocida no se cierra en lugar de utilizar la configuración actual. Las carreras programadas también permanecen vinculadas a su perfil. Consulte [Exportar perfiles](/es/docs/export-profiles/).

### Preparación en segundo plano y cancelación programada

- Permitir lecturas Health Connect en segundo plano para exportaciones desatendidas. De lo contrario, abra Health.md para completar la lectura de datos de salud.
- Mantenga las notificaciones habilitadas para que Android pueda mostrar el trabajo activo, el estado del servicio en primer plano, los resultados y las acciones de recuperación.
- Otorgue alarmas y recordatorios solo cuando desee una programación de alarmas exacta. Sin él, el trabajo WorkManager duradero sigue estando disponible, pero el tiempo elegido es aproximado.
- La cancelación de una ejecución programada detiene solo ese intento. Las fechas completadas permanecen completas, las fechas no resueltas se pueden volver a intentar y la programación recurrente permanece habilitada.

## Fuentes de salud

Health Connect es la ruta de exportación local en ambos canales. La compilación Google Play también incluye un área de configuración de fuentes de salud para ecosistemas como Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar y WHOOP. Cuando esos ecosistemas escriben en Health Connect , cualquiera de las compilaciones puede exportar los registros Health Connect resultantes. Las importaciones directas de proveedores de nube y las devoluciones de llamadas de OAuth son solo para reproducción. El catálogo de proveedores F-Droid contiene únicamente Health Connect .

Google Fit está excluido intencionalmente de la superficie de proveedores compatibles porque Health Connect es la capa de datos de salud preferida de Android.

### Pasos exactos del día local

Los totales de pasos diarios utilizan límites exactos del día local por zonas. Antes de la agregación, Health.md recorta y divide intervalos superpuestos de Health Connect a la medianoche local. Por lo tanto, los cambios en los viajes y el horario de verano no desplazan pasos hacia el día equivocado.

## Distribución, precios y conmutación

- ** Google Play :** la versión del teléfono con suscripción habilitada ofrece suscripciones semanales/anuales individuales y de por vida. Los suscriptores elegibles por primera vez reciben una prueba de 7 días y luego se renuevan automáticamente al precio mostrado hasta que se cancelen a través de Google Play . Lifetime se cobra una vez inmediatamente sin prueba. No queda ningún subsidio de libre exportación local. Se conserva el acceso permanente existente. Restaurar Compra utiliza la cuenta de Google de compras; Eliminar la aplicación o comprar Lifetime no cancela una suscripción. Las versiones publicadas más antiguas pueden mostrar la asignación anterior. La versión actual es solo para teléfono. El complemento Wear OS se pospone a un ciclo de calificación posterior.
- ** F-Droid :** se incluye acceso ilimitado. No hay contador gratuito, dependencia de facturación, muro de pago, acción de compra o restauración.
- ** F-Droid alcance:** Health Connect únicamente, sin integración de Wear OS, OAuth directo del proveedor de la nube, revisión de Play, atribución o telemetría de incorporación Health.md .
- **Resultado compartido:** ambos canales utilizan la misma captura Health Connect , exportadores, esquemas, acciones de automatización y protocolo de dispositivo directo.
- **Cambio:** Google Play y F-Droid usan claves de firma diferentes, por lo que cambiar de canal requiere desinstalar la aplicación primero.

Un cambio de canal no migra compras, configuraciones, historial, credenciales ni estado de transferencia privada. Los archivos exportados permanecen en el destino que eligió.

Si Google Play Billing se desconecta transitoriamente, la compilación de Play se vuelve a conectar y actualiza el estado del derecho automáticamente. Una pérdida temporal del servicio no elimina Premium de forma permanente. Utilice Restaurar compra solo si la cuenta sigue sin resolverse después de que se restablezca la conectividad.

## Modelo de privacidad

Health.md para Android es local primero:

- Los registros -  Health Connect se leen en su dispositivo Android.
- Las exportaciones se escriben directamente en las carpetas que elija.
- Las exportaciones de carpetas principales y las consultas directas al dispositivo no crean una copia del servidor Health.md de forma predeterminada.
- La configuración y el historial de exportación permanecen en el dispositivo.
- La facturación la maneja Google Play en la compilación Play. F-Droid incluye acceso ilimitado sin facturación y no contiene ningún código de telemetría Health.md ni identidad/estado de telemetría.
- Las carpetas respaldadas por el proveedor se sincronizan según los propios términos de ese proveedor.

Si desea la configuración local más estricta, ejecute exportaciones manuales a una carpeta de dispositivo local y deje deshabilitadas las exportaciones programadas y la sincronización respaldada por el proveedor.

El piloto separado y opcional de Health.md Cloud es para un único propietario y conserva solo las exportaciones de API enviadas intencionalmente. No hay registro público ni sincronización automática de dispositivos; este flujo de carpetas no sube datos al piloto. Consulta la [política de privacidad](/privacy-policy.html) sobre conservación, eliminación, cuota y riesgos de pérdida sin copias de seguridad.

## Documentos relacionados

<div class="related">
 <a href="/es/docs/export-profiles/"> <span> Perfiles </span> Guarde destinos independientes, configuraciones de salida, horarios e ID de automatización estables. </a>
 <a href="/es/docs/export/"> <span> Exportar </span> Flujo de exportación manual, rangos de fechas, vistas previas, historial y salida de archivos. </a>
 <a href="/es/docs/metrics/"> <span> Métricas </span> Cómo funcionan la selección de métricas y las categorías en Health.md . </a>
 <a href="/es/docs/format/"> <span> Formatos </span> Markdown , bases, JSON, CSV, unidades, nombres de archivos y frontmatter. </a>
 <a href="/es/docs/visualizations-roadmap/"> <span> Obsidian </span> Cómo JSON exportado y Markdown potencian las visualizaciones Health.md . </a>
 </div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;"> Última actualización 2026-10-04 </p>
