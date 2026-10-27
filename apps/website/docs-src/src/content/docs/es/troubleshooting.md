---
title: "¿Faltan datos al exportar Apple Health? Solución de problemas"
description: "Resuelve exportaciones vacías de Apple Health o Health Connect, sueño ausente, detalle CSV, errores al guardar y retrasos. Comprueba primero un día."
---

Si faltan datos al exportar Apple Health o Health Connect, distingue un **problema de lectura** de un **problema al guardar archivos**. Un dato ausente no es un cero medido.

## Empieza por un día que puedas comprobar

1. Confirma un valor registrado y su fecha en Apple Health o Health Connect. Espera a que el reloj o la app de origen terminen de sincronizar.
2. En Health.md, revisa el perfil activo, la métrica, las fechas, el formato y el destino. Empieza con una métrica compatible de un día completo.
3. Desbloquea el teléfono, abre Health.md y usa la vista previa si está disponible. Después exporta y comprueba el resultado y el destino reales. La vista previa no demuestra que se haya guardado un archivo.

Consulta [tu primera exportación en iPhone](/es/docs/iphone-first-export/) o la [configuración de Android](/es/docs/android/).

## Hay datos en el origen, pero la exportación está vacía

En iPhone, revisa las categorías permitidas para Health.md en Apple Health. **HealthKit no revela si se denegó el permiso de lectura**. Un resultado vacío no distingue entre acceso restringido y ausencia de registros coincidentes. Una solicitud de permisos correcta tampoco confirma todas las categorías. Consulta la [documentación de autorización de Apple](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

En Android, confirma que la app de origen escribió el registro en Health Connect y que Health.md puede leer ese tipo compatible. Los datos visibles solo en otra app pueden no estar disponibles para exportarlos. Consulta la [lista de comprobación de Google](https://support.google.com/android/answer/13770384).

Tras sincronizar o cambiar permisos, vuelve a revisar métrica y fecha. No sustituyas valores ausentes por ceros.

Si un resultado estructurado indica `complete_empty`, distínguelo de resultados no compatibles, parciales, omitidos o fallidos. No demuestra un cero medido ni revela una decisión sobre el permiso de lectura.

## El sueño de anoche no aparece en Hoy

Health.md asigna el sueño al **día de inicio** en Apple y Android. El martes por la mañana, exporta **Ayer** (lunes), o lunes y martes. Si el origen sincroniza tarde, vuelve a exportar el día de inicio. Consulta [las fechas del sueño](/es/docs/sleep-date-attribution/).

## La vista previa tiene datos, pero la carpeta está vacía

En iPhone, comprueba si el perfil activo escribe en una carpeta local, Connected Mac o API Endpoint. Para archivos, revisa carpeta, subcarpeta, nombre y resultado: escrito, omitido o fallido. Una omisión puede deberse al comportamiento de escritura elegido. Vuelve a seleccionar una carpeta no disponible y comprueba su proveedor antes de reintentar. Consulta [carpetas y vaults](/es/docs/folder-vault/) y [perfiles](/es/docs/export-profiles/).

## El CSV contiene totales, pero no las lecturas esperadas

En iPhone, Summary y Detailed Time-Series ofrecen distinto detalle. Revisa Data Detail y las métricas antes de ampliar las fechas. Los metadatos no son mediciones. Conserva unidades y distingue totales diarios de registros de origen. Lossless Health Records tiene su propio estado de captura; un resumen no demuestra cobertura completa. Consulta la [referencia de formato y cobertura](/es/docs/reference/export-formats/).

## No llega una exportación programada

iOS y Android WorkManager usan horas objetivo, sin garantizar la entrega. Desbloquea el dispositivo, abre Health.md y revisa historial y recuperación pendiente antes de iniciar otra ejecución. Una notificación no demuestra que se haya guardado el archivo. Consulta [programación en iPhone](/es/docs/scheduling/) o [automatización en Android](/es/docs/android/).

## CLI no disponible o timeout

Abre y desbloquea Health.md, verifica Direct CLI Access, IP/Tailscale y deja que termine la ventana de espera. Un timeout no cancela un trabajo aceptado:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Revisa estado exterior, fechas fallidas, cobertura, `next_cursor`, versión y limitaciones antes de afirmar integridad. `--allow-partial` solo cambia la política de salida.

## Pide ayuda sin compartir registros de salud

Indica versión de la app y del sistema, plataforma, formato y si faltan datos, se omite un archivo o falla la escritura. Oculta información privada de capturas y registros. No publiques valores de salud, rutas, documentos clínicos, tokens, códigos de emparejamiento ni rutas privadas.

<div class="related"><a href="/es/docs/cli-jobs/"><span>Trabajos</span>Reanudación y cancelación.</a><a href="/es/docs/release-status/"><span>Versiones</span>Compatibilidad exacta.</a></div>
