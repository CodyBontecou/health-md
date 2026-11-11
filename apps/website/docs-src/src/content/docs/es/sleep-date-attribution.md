---
title: "Fechas del sueño y notas diarias"
description: "Elige la fecha de exportación del sueño: ventana de mediodía a mediodía, acostarse después de medianoche, siestas y resultados vacíos."
---

**Inicio de la noche** es la opción predeterminada en iPhone y Android. Para el sueño de anoche el martes por la mañana, exporta **lunes**, normalmente **Ayer**. El resumen diario de sueño de Health.md usa una ventana local de **12:00 a 12:00**: del mediodía del lunes al del martes, en lugar del límite de medianoche de la actividad.

Elige **Fin por la mañana** en los ajustes de exportación para asignar cada sesión de sueño completa a la fecha en que termina, en la zona horaria de la exportación y sin recortarla al mediodía. Para la noche del lunes que termina el martes, exporta **martes (Hoy)**; las siestas del martes también pertenecen al martes. El cambio se aplica a operaciones nuevas; las guardadas conservan su atribución aceptada.

<div id="sleep-journal-window"></div>

## Por qué el sueño aparece en la nota de ayer

La ventana mantiene unida una noche habitual incluso si te acuestas después de medianoche. Incluye el mediodía inicial y excluye el siguiente. El sueño que cruza el mediodía puede contribuir a resúmenes de días contiguos. Las marcas de tiempo originales no se cambian para coincidir con la nota.

Ambos modos de atribución del sueño están disponibles en Apple y Android. Las métricas, etapas, registros de origen y agregaciones pueden seguir siendo diferentes según la plataforma.

<div id="sleep-date-examples"></div>

## Qué fecha exportar

**Inicio de la noche:** Ejemplos ficticios en hora local, no registros de salud:

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

Los resúmenes de Daily Note Injection y API Endpoint usan la atribución del sueño elegida para la operación. Si la fuente se actualiza tarde, vuelve a exportar la fecha correspondiente a ese modo o revisa el periodo retrospectivo de la programación. La hora en segundo plano es un objetivo, no una escritura garantizada.

<div id="sleep-records-and-queries"></div>

## Resúmenes, registros y consultas de sesiones

Los registros originales o canónicos tienen sus propias reglas de pertenencia y conservan las marcas de tiempo. No reconstruyas sesiones a partir de un total diario ni sumes los intervalos de origen como sueño adicional.

**Inicio de la noche:** En Apple, el archivo de datos originales asigna los registros según su hora de inicio de origen dentro del día local, de medianoche a medianoche. El resumen de sueño, en cambio, recorta los intervalos a la ventana del diario, de mediodía a mediodía. Por eso, una consulta correcta de registros originales de Sleep Analysis puede contener registros matutinos mientras el resumen de sueño de esa fecha está vacío. Exporta la fecha anterior del diario y comprueba `time_context.calendar_timezone` antes de investigar un resumen ausente. Por ejemplo, los registros del 22 de septiembre de 04:03–11:52 UTC pertenecen por completo al resumen del 21 de septiembre en UTC; en Europe/Lisbon, los últimos 52 minutos quedan después del mediodía local y contribuyen al 22 de septiembre.

El sueño por fases no requiere un registro explícito `inBed`: cuando falta, los resúmenes de Apple usan la unión de los intervalos disponibles de las fases de sueño. La ausencia de datos de tiempo en cama no crea una duración en cama. Una consulta de resumen fallida debe aparecer en `diagnostics.partial_failures`; una consulta correcta sin intervalos válidos representa una ausencia de datos válida. La frecuencia cardiaca en reposo usa una consulta independiente por día natural y requiere una medición real de frecuencia cardiaca en reposo; las fases de sueño o el permiso de lectura por sí solos no la proporcionan.

`healthmd_sleep_sessions` requiere una configuración CLI/MCP compatible con **Apple Health**. Las consultas MCP tipadas de Android no están disponibles actualmente. Consulta [capacidades por plataforma](/es/docs/guides/platform-features/) y [MCP](/es/docs/mcp/).

Sigue las guías de [programación](/es/docs/scheduling/), [resolución de problemas](/es/docs/troubleshooting/) y [formatos](/es/docs/format/) para revisar sincronización tardía, lecturas vacías, escrituras y cobertura.
