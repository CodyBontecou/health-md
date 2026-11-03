---
title: "Fechas del sueño y notas diarias"
description: "Elige la fecha de exportación del sueño: ventana de mediodía a mediodía, acostarse después de medianoche, siestas y resultados vacíos."
---

Para el sueño de anoche el martes por la mañana, exporta **lunes**, normalmente **Ayer**. El resumen diario de sueño de Health.md usa una ventana local de **12:00 a 12:00**: del mediodía del lunes al del martes, en lugar del límite de medianoche de la actividad.

<div id="sleep-journal-window"></div>

## Por qué el sueño aparece en la nota de ayer

La ventana mantiene unida una noche habitual incluso si te acuestas después de medianoche. Incluye el mediodía inicial y excluye el siguiente. El sueño que cruza el mediodía puede contribuir a resúmenes de días contiguos. Las marcas de tiempo originales no se cambian para coincidir con la nota.

Apple y Android comparten esta ventana en los resúmenes de compatibilidad; métricas, etapas, registros y agregación pueden diferir. No hay un ajuste para mover el resumen a la fecha de despertar.

<div id="sleep-date-examples"></div>

## Qué fecha exportar

Ejemplos ficticios en hora local, no registros de salud:

| Sueño o actividad | Fecha de exportación |
| --- | --- |
| Lunes 23:45 a martes 07:30 | **Lunes** |
| Martes 01:00 a martes 07:30 | **Lunes**, no martes |
| Siesta del martes, 14:00 a 14:30 | **Martes** |
| Pasos y actividad del martes | **Martes** |
| Sueño del lunes y actividad del martes | **Lunes y martes** |

Usa la zona horaria local de la exportación. La fecha de despertar de otra app o la modificación del archivo no determina la fecha del diario.

<div id="sleep-empty-checks"></div>

## Si la nota esperada está vacía

1. Comprueba la fecha del diario y las métricas de sueño seleccionadas.
2. Deja que el reloj o la app sincronicen con Apple Health o Health Connect; previsualiza y vuelve a exportar ese día.
3. Revisa los permisos. En iPhone, un resultado vacío de HealthKit no revela si se denegó la lectura. En Android, confirma que la fuente escribió el registro compatible en Health Connect.
4. Comprueba el destino y el resultado escrito, omitido o fallido. Una vista previa no prueba que se guardara un archivo. Un dato ausente no es cero.

Daily Note Injection y los resúmenes de API Endpoint usan la misma ventana. Si la fuente llega tarde, repite el día o revisa la ventana retrospectiva del horario. La ejecución en segundo plano no garantiza una escritura correcta a una hora exacta.

<div id="sleep-records-and-queries"></div>

## Resúmenes, registros y consultas de sesiones

Los registros originales o canónicos tienen sus propias reglas de pertenencia y conservan las marcas de tiempo. No reconstruyas sesiones a partir de un total diario ni sumes los intervalos de origen como sueño adicional.

En Apple, el archivo original asigna los registros al día local de medianoche a medianoche según su hora de inicio. En cambio, el resumen de sueño recorta los intervalos a la ventana de mediodía a mediodía. Una consulta correcta de Sleep Analysis puede contener registros matutinos aunque el resumen de esa fecha esté vacío. Exporta el día anterior y comprueba `time_context.calendar_timezone`. Por ejemplo, los registros del 22 de septiembre de 04:03 a 11:52 UTC pertenecen al resumen del 21 en UTC; en Europe/Lisbon, los últimos 52 minutos quedan después del mediodía local y contribuyen al día 22.

Las etapas de sueño no necesitan un registro explícito `inBed`: si falta, Apple usa la unión de las etapas de sueño disponibles, sin inventar una duración en cama. Una consulta fallida debe aparecer en `diagnostics.partial_failures`; una consulta correcta sin intervalos válidos es una ausencia válida. La frecuencia cardíaca en reposo usa otra consulta por día natural y requiere una medición real; las etapas de sueño o el permiso de lectura no la proporcionan.

`healthmd_sleep_sessions` requiere una configuración CLI/MCP compatible con **Apple Health**. Las consultas MCP tipadas de Android no están disponibles actualmente. Consulta [capacidades por plataforma](/es/docs/guides/platform-features/) y [MCP](/es/docs/mcp/).

Sigue las guías de [programación](/es/docs/scheduling/), [resolución de problemas](/es/docs/troubleshooting/) y [formatos](/es/docs/format/) para revisar sincronización tardía, lecturas vacías, escrituras y cobertura.
