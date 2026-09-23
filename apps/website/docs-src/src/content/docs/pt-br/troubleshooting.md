---
title: "Solução de problemas do Health.md"
description: "Diagnostique exportações vazias, sono ausente, telefone indisponível, agendas, pastas, resultados parciais e timeouts."
---

Comece com um aparelho, um dia, uma categoria e um destino. Não publique saúde, rotas, documentos clínicos, tokens, códigos de pareamento ou caminhos privados.

## Dados vazios

Confirme o valor no Apple Health ou Health Connect, revise a permissão e exporte uma categoria de um dia. Diferencie `complete_empty`, permissão ausente, não compatível, ignorado, parcial e falho. Ausência não é zero.

## Sono ausente de Hoje

O sono pertence ao dia em que a noite começou. Na terça de manhã, exporte **Ontem** ou segunda e terça. Veja [Datas do sono](/pt-br/docs/sleep-date-attribution/).

## Arquivos e agendas

Confira cofre, acesso à pasta, subpasta, modelo e perfil. O segundo plano do iOS e o WorkManager usam horários-alvo, não garantia universal. Desbloqueie e use a recuperação.

## Timeout da CLI

Timeout não cancela trabalho aceito:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Antes de afirmar completude, confira estado, datas ausentes, cobertura, `next_cursor`, versão e limitações. `--allow-partial` só muda a política de saída.

<div class="related"><a href="/pt-br/docs/cli-jobs/"><span>Trabalhos</span>Retomar e cancelar.</a><a href="/pt-br/docs/release-status/"><span>Versões</span>Compatibilidade.</a></div>
