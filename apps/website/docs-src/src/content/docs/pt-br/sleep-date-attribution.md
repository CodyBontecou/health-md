---
title: "Datas do sono e notas diárias"
description: "Por que o sono noturno pertence à data de início e qual intervalo exportar pela manhã."
---

O Health.md atribui uma sessão à data em que ela **começou**. Dormir de segunda às 23h45 até terça às 7h30 pertence ao resumo de segunda. Apple e Android compartilham essa regra, mesmo que o Health Connect mostre a data do despertar.

| Objetivo | Exporte |
|---|---|
| Sono da noite na terça de manhã | **Ontem** (segunda) |
| Atividade de terça | **Hoje** |
| Ambos | Segunda e terça |

Resumos mantêm a noite inteira. Registros canônicos preservam início e fim e pertencem ao dia inicial; o Health.md não inventa metades. Para semântica de sessão, use `healthmd_sleep_sessions`.

Daily Note Injection e API Endpoint usam a mesma atribuição. Se a fonte sincronizar tarde, reexporte o dia inicial. Hoje não existe opção para mover resumos para a data do despertar.

<div class="related"><a href="/pt-br/docs/scheduling/"><span>Automação</span>Inclua Ontem pela manhã.</a><a href="/pt-br/docs/troubleshooting/"><span>Ajuda</span>Dados vazios ou atrasados.</a></div>
