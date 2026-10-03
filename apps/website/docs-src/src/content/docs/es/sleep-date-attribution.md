---
title: "Fechas del sueño y notas diarias"
description: "Por qué una sesión nocturna pertenece al día en que comenzó y qué rango exportar por la mañana."
---

Health.md asigna una sesión nocturna a la fecha en que **comenzó**. Dormir del lunes a las 23:45 al martes a las 7:30 pertenece al resumen del lunes. Apple y Android comparten esta convención, aunque Health Connect u otra app puedan mostrar la fecha de despertar.

| Objetivo | Exporta |
|---|---|
| El sueño de anoche el martes | **Ayer** (lunes) |
| La actividad parcial del martes | **Hoy** |
| Ambos | Lunes y martes |

Los resúmenes legibles mantienen la noche unida. Los registros canónicos conservan inicio y fin originales y pertenecen al día de inicio; no se cortan en mitades inventadas. Para software que necesita sesiones, usa `healthmd_sleep_sessions` con fechas, zona horaria, etapas y cobertura.

Daily Note Injection y API Endpoint usan la misma atribución. Si la fuente sincronizó tarde, vuelve a exportar el día de inicio. Health.md no ofrece actualmente un selector para mover resúmenes a la fecha de despertar.

<div class="related"><a href="/es/docs/scheduling/"><span>Automatización</span>Incluye Ayer en la ejecución matinal.</a><a href="/es/docs/troubleshooting/"><span>Ayuda</span>Diagnostica datos vacíos o tardíos.</a></div>
