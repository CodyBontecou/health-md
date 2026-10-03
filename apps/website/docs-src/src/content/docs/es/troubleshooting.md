---
title: "Solución de problemas de Health.md"
description: "Diagnostica exportaciones vacías, sueño ausente, teléfonos no disponibles, horarios, carpetas, resultados parciales y timeouts."
---

Empieza con un dispositivo, un día, una categoría y un destino. No publiques datos de salud, rutas, documentos clínicos, tokens, códigos de emparejamiento ni rutas privadas.

## Datos vacíos

Confirma el valor en Apple Health o Health Connect, revisa permisos y exporta una categoría de un día. Distingue `complete_empty`, permiso ausente, no compatible, omitido, parcial y fallido. Ausencia no equivale a cero.

## Sueño ausente de Hoy

El sueño pertenece al día en que empezó la noche. El martes por la mañana, exporta **Ayer** o lunes y martes. Consulta [Fechas del sueño](/es/docs/sleep-date-attribution/).

## Archivos o programación

Comprueba que la carpeta esté dentro del vault correcto, vuelve a conceder acceso si se movió y revisa subcarpeta, plantilla y perfil. Los horarios de iOS y WorkManager son objetivos; desbloquea el teléfono y usa la recuperación pendiente.

## CLI no disponible o timeout

Abre y desbloquea Health.md, verifica Direct CLI Access, IP/Tailscale y deja que termine la ventana de espera. Un timeout no cancela un trabajo aceptado:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Revisa estado exterior, fechas fallidas, cobertura, `next_cursor`, versión y limitaciones antes de afirmar integridad. `--allow-partial` solo cambia la política de salida.

<div class="related"><a href="/es/docs/cli-jobs/"><span>Trabajos</span>Reanudación y cancelación.</a><a href="/es/docs/release-status/"><span>Versiones</span>Compatibilidad exacta.</a></div>
