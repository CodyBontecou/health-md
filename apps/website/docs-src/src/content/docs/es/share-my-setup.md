---
title: "Compartir mi configuración"
description: "Revisa el flujo v2 solo de desarrollo para mover perfiles sin salud, credenciales, compras ni confianza de dispositivos."
---

<div class="availability preview"><strong>Vista previa de desarrollo · sin calificación de lanzamiento</strong><p>El contrato v2 sigue precanónico y planificado hasta completar interoperabilidad y accesibilidad en dispositivos. No dependas de él en producción.</p></div>

Share My Setup empaqueta uno o varios perfiles. Transfiere métricas, formatos, nombres, organización y la intención del destino. Nunca incluye datos de salud, tokens, acceso real a carpetas, emparejamientos, compras, historial ni trabajos.

1. En el origen, abre **Ajustes → Share My Setup** y exporta el archivo v2.
2. Ábrelo en el destino y revisa cada perfil.
3. Elige **Añadir** o **Reemplazar**.
4. Vincula localmente carpeta, URL/API con credenciales o Mac.
5. Aplica y prueba una exportación pequeña.

La operación es atómica y ofrece un **Deshacer** de una sola vez. Los perfiles importados quedan bloqueados hasta vincular su destino; las programaciones llegan desactivadas. El código de desarrollo actual solo emite `healthmd.shared_setup` v2; v1 se rechaza.

<div class="related"><a href="/es/docs/export-profiles/"><span>Perfiles</span>Ajustes congelados e identidades estables.</a><a href="/es/docs/guides/platform-features/"><span>Estado</span>Calificación por plataforma.</a></div>
