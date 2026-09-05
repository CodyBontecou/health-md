---
title: Complemento de Wear OS
description: Health.md para Wear OS añade a tu reloj mosaicos de actividad y recuperación más diez complicaciones de salud, mientras el teléfono sigue siendo la autoridad de Health Connect.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · Wear OS</p>
  <p>Health.md incluye un complemento de Wear OS en la misma ficha de Google Play que la app del teléfono. Añade superficies de salud de un vistazo a tu reloj mientras tu teléfono sigue siendo la única autoridad de Health Connect.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Descargar en Google Play</a>
    <a class="docs-button-secondary" href="/es/docs/android/">Guía de la app para Android</a>
  </div>
</div>

## Qué muestra el reloj

| Superficie | Qué obtienes |
|---|---|
| Mosaico de actividad diaria | El resumen de actividad de hoy como mosaico de esfera |
| Mosaico de recuperación | El resumen de recuperación de hoy como mosaico de esfera |
| Complicaciones (10) | Actividad, Recuperación, Pasos, Movimiento, Ejercicio, Sueño, Frecuencia cardíaca en reposo, Frecuencia cardíaca media, VFC y Oxígeno en sangre como complicaciones de esfera |

Las complicaciones pueden añadirse a la mayoría de las esferas desde el editor de esferas, y los mosaicos aparecen en el carrusel de mosaicos del reloj.

## Cómo funciona

- La app del reloj se distribuye con la misma ficha de Play y la misma identidad de firma que la app del teléfono.
- Los datos de salud fluyen del teléfono al reloj por la capa de datos de Wear OS como una instantánea agregada privada. El reloj **no tiene detección directa de Health Connect ni de Health Services**; el teléfono sigue siendo la autoridad para cada métrica.
- Las superficies del reloj se actualizan con la última instantánea enviada por la app del teléfono: sin cuentas, sin nube y sin que los datos de salud salgan de tus dispositivos.

## Requisitos

- Un teléfono Android con Health.md instalado y emparejado con un reloj Wear OS.
- Datos de Health Connect en el teléfono para las métricas que quieras ver.
- Instala Health.md en el reloj desde la Play Store del reloj, o desde la ficha de la Play Store del teléfono complementario.

## Configuración

1. Abre la Play Store en tu reloj (o en la sección de relojes de la Play Store del teléfono) e instala Health.md.
2. Abre la app del teléfono una vez para que se sincronice una instantánea.
3. Mantén pulsada tu esfera → **Personalizar** → añade una complicación de Health.md, o desliza hasta el carrusel de mosaicos y fija un mosaico de Health.md.

## Privacidad y validación

El complemento usa un contrato de transporte privado puramente agregado, por lo que no se transmiten registros sin procesar al reloj. La calidad de cada versión se valida con suites de emulador y con evidencia de batería y QA de OEM en dispositivos físicos emparejados antes de publicar los artefactos de Wear OS. Consulta la [lista de comprobación de implementación de Wear OS](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/features/wear-os-implementation.md) para el manual completo.
