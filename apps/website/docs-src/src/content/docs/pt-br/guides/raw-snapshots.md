---
title: Snapshots de API brutas
description: Exporte snapshots JSON ou NDJSON imutáveis e versionados de registros do Health Connect e de respostas dos provedores Fitbit, Oura, WHOOP e Withings, com manifestos por tipo e somas de verificação.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · exportação para arquivamento</p>
  <p>O Raw API Snapshot é um produto de exportação separado do Health.md para Android, voltado a fluxos de migração e arquivamento: um artefato JSON ou NDJSON imutável e versionado por intervalo selecionado, preservando os registros nativos.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Baixar no Google Play</a>
    <a class="docs-button-secondary" href="/pt-br/docs/android/">Guia do app para Android</a>
  </div>
</div>

## O que é um snapshot bruto

As exportações de compatibilidade convertem registros do Health Connect em resumos diários legíveis de `HealthData`. Um snapshot bruto ignora completamente essa conversão:

- **Snapshots do Health Connect** preservam todos os campos expostos pela API AndroidX fixada, incluindo identidade e metadados nativos, carimbos de tempo em nanossegundos, deslocamentos de origem anuláveis, valores de enum brutos, amostras aninhadas, estágios, rotas e estruturas de treinos planejados.
- **Snapshots de Fitbit, Oura, WHOOP e Withings** preservam os bytes exatos das respostas bem-sucedidas do provedor e divulgam a paginação do endpoint e a agregação no servidor. Provedores sem suporte são relatados em vez de normalizados ou substituídos silenciosamente por dados do Health Connect.
- Cada artefato termina com um **manifesto** com status, problemas, contagens e somas de verificação por tipo. Exportações para pasta também recebem um arquivo complementar `.sha256`.

Um snapshot bruto é completo em relação à API de provedor fixada do app; não é um backup transacional do banco de dados do provedor. Ele não pode recuperar registros inacessíveis, unidades originais que a API não expõe, registros excluídos ou campos desconhecidos do SDK instalado.

## Prévia antes do destino

Snapshots brutos podem ser visualizados em prévia sem um destino configurado. A prévia faz a leitura nativa completa do provedor em armazenamento privado sem backup, mantém na memória apenas texto de início e fim limitado e exclui o artefato temporário sem enviar nada.

## Regras de entrega

Os uploads de API bruta são deliberadamente mais rígidos que as exportações de API de compatibilidade:

| Regra | Motivo |
|---|---|
| Somente HTTPS | O artefato transmitido nunca trafega em texto simples |
| Redirecionamentos rejeitados | O artefato e as credenciais nunca podem ser reproduzidos em outra origem |
| Cabeçalhos de esquema, exportação e soma de verificação | O endpoint receptor pode verificar o que aceitou |
| Artefato privado temporário excluído após a tentativa | Nenhuma cópia permanece no dispositivo |

## Arquivos incrementais

O backend `healthmd.raw-changes`, com versão independente, usa tokens de mudança e marcadores de exclusão do Health Connect para futuros fluxos de arquivamento incremental, de modo que um snapshot completo não precise ser a única estratégia de arquivamento.

## Requisitos

- Health.md para Android com o produto Raw API Snapshot.
- Permissões do Health Connect para os tipos de registro selecionados, ou uma conta Fitbit, Oura, WHOOP ou Withings conectada para snapshots de provedores.
- Um endpoint HTTPS se você enviar snapshots; a exportação para pasta local não tem requisitos de transporte.

## Onde saber mais

- [Contrato de snapshot bruto v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-snapshot-v1.md)
- [Contrato de registro bruto v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-record-v1.md)
- [Contrato de mudanças brutas v1](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-changes-v1.md)
