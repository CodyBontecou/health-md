---
title: Complemento Wear OS
description: O Health.md para Wear OS adiciona ao seu relógio blocos de atividade e recuperação e dez complicações de saúde, com o telefone permanecendo a autoridade do Health Connect.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · Wear OS</p>
  <p>O Health.md oferece um complemento de Wear OS na mesma listagem do Google Play que o app do telefone. Adicione superfícies de saúde de relance ao seu relógio enquanto o telefone continua sendo a única autoridade do Health Connect.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Baixar no Google Play</a>
    <a class="docs-button-secondary" href="/pt-br/docs/android/">Guia do app para Android</a>
  </div>
</div>

## O que o relógio mostra

| Superfície | O que você recebe |
|---|---|
| Bloco de atividade diária | O resumo de atividades de hoje como um bloco de mostrador |
| Bloco de recuperação | O resumo de recuperação de hoje como um bloco de mostrador |
| Complicações (10) | Atividade, Recuperação, Passos, Movimento, Exercício, Sono, Frequência cardíaca em repouso, Frequência cardíaca média, VFC e Oxigênio no sangue como complicações de mostrador |

As complicações podem ser adicionadas à maioria dos mostradores pelo editor de mostrador, e os blocos aparecem no carrossel de blocos do relógio.

## Como funciona

- O app do relógio é distribuído com a mesma listagem e identidade de assinatura da Play do app do telefone.
- Os dados de saúde fluem do telefone para o relógio pela camada de dados do Wear OS como um snapshot agregado privado. O relógio **não tem detecção direta do Health Connect nem do Health Services**; o telefone permanece a autoridade para cada métrica.
- As superfícies do relógio são atualizadas a partir do snapshot mais recente enviado pelo app do telefone — sem contas, sem nuvem e sem que dados de saúde saiam dos seus dispositivos.

## Requisitos

- Um telefone Android com o Health.md instalado e pareado com um relógio Wear OS.
- Dados do Health Connect no telefone para as métricas que você quer ver.
- Instale o Health.md no relógio pela Play Store do relógio ou pela listagem da Play Store do telefone.

## Configuração

1. Abra a Play Store no seu relógio (ou na seção de relógios da Play Store do telefone) e instale o Health.md.
2. Abra o app do telefone uma vez para que um snapshot seja sincronizado.
3. Toque e segure o mostrador do relógio → **Personalizar** → adicione uma complicação do Health.md, ou deslize até o carrossel de blocos e fixe um bloco do Health.md.

## Privacidade e validação

O complemento usa um contrato de transporte puramente privado e agregado, portanto nenhum registro bruto é transmitido ao relógio. A qualidade do lançamento é controlada por suítes de emulador e por evidências de bateria e QA de OEM em dispositivos físicos pareados antes que artefatos do Wear OS sejam publicados. Veja a [lista de verificação de implementação do Wear OS](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/features/wear-os-implementation.md) para o runbook completo.
