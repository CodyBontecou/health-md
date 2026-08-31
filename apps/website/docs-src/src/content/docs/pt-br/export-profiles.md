---
title: "Perfis de exportação"
description: "Salve juntos as configurações de exportação e um destino para executar ou agendar essa configuração no iPhone, Android, Atalhos, CLI, Tasker ou adb."
---

Os perfis de exportação reúnem uma configuração reproduzível. Gerencie-os no Health.md para iPhone ou Android. Nas plataformas Apple, o fluxo de gerenciamento atual é documentado e testado apenas no iPhone; não há afirmação de uma tela de gerenciamento no iPad ou Mac.

## Gerenciar e editar perfis

Abra **Ajustes → Perfis de exportação**. A lista marca o perfil ativo e permite criar, renomear, duplicar, excluir, ativar ou inspecionar perfis. Abra os detalhes para copiar o ID estável. O último perfil não pode ser excluído.

A aba Exportar edita o perfil ativo. Ative outro perfil antes de alterar as configurações se não quiser atualizar o atual.

Cada perfil congela as opções necessárias para reproduzir uma execução:

- métricas selecionadas, detalhes dos dados, formatos, modelos, nomes de arquivo, unidades e comportamento de gravação;
- sua própria pasta de destino e subpasta, um endpoint de API ou um Mac conectado quando houver suporte na plataforma;
- notas diárias, entradas individuais, consolidações e outras opções de saída compatíveis com a plataforma.

O agendamento é vinculado separadamente à identidade estável do perfil. Trocar o perfil ativo não redireciona esse agendamento. Uma execução usa o instantâneo salvo em vez de aproveitar configurações alteradas de outro perfil.

## Executar e agendar com segurança

- Um perfil pode ter seu próprio agendamento recorrente, inclusive a cadência personalizada oferecida pelo app.
- Os direitos de cada plataforma continuam valendo: a cota gratuita da Apple pode incluir ações agendadas, enquanto o agendamento no Android exige a compra vitalícia.
- O Health.md avisa quando perfis podem gravar os mesmos caminhos gerados no mesmo destino. O aviso não altera silenciosamente nenhum perfil nem agendamento.
- Parar ou cancelar afeta somente a tentativa atual. As datas concluídas permanecem concluídas, as pendentes podem ser tentadas novamente e o agendamento continua ativado.
- Se o perfil indicado não existir, o Health.md falha de forma segura. Ele nunca usa o perfil ativo nem outro destino como alternativa.

## Nomes, IDs estáveis e automação

O nome de exibição é para pessoas e pode mudar. O ID estável permite automações resistentes a renomeações. Copie-o em **Ajustes → Perfis de exportação → ID do perfil**.

- Os Atalhos da Apple selecionam o perfil pelo nome de exibição; um parâmetro de perfil vazio usa o perfil ativo.
- As transmissões do Tasker e do adb no Android podem fornecer o extra `PROFILE` com um ID estável ou nome. Prefira o ID em fluxos que precisam sobreviver a renomeações.
- A CLI direta aceita `--profile PROFILE_ID` em tarefas compatíveis de arquivos gerados. O perfil fornece as configurações de saída congeladas; o `--destination` obrigatório ainda seleciona a pasta existente no computador.

Consulte o guia de automação da plataforma antes de ativar um fluxo sem supervisão.

## Histórico, recuperação e privacidade

As linhas do histórico de execuções agendadas e automatizadas associadas a perfis registram o perfil usado. O histórico também preserva um rótulo privado do destino real. Uma execução manual pela aba Exportar pode não anexar o nome do perfil, mesmo usando as configurações do perfil ativo. Renomear o perfil, mudar o destino ou selecionar outro depois não reescreve o histórico existente.

Uma nova tentativa iniciada no histórico de exportações usa as configurações e o destino atuais e cria uma nova linha com o que realmente foi usado. Ela não atribui a tentativa ao perfil original. Já a recuperação ou retomada de uma tentativa agendada pendente mantém suas datas, configurações e destino exatos.

Perfis e agendamentos são configurações locais do dispositivo. Eles não são sincronizados entre iPhone, iPad, Mac e Android. Recrie a configuração desejada em cada dispositivo e verifique o destino antes de ativar a automação.

## Relacionados

<div class="related">
  <a href="/pt-br/docs/export/"><span>Exportar</span>Escolha os detalhes, visualize a saída e exporte um intervalo de datas.</a>
  <a href="/pt-br/docs/scheduling/"><span>Agendamento</span>Entenda cadências, recuperação e limites de horário da plataforma.</a>
  <a href="/pt-br/docs/shortcuts/"><span>Atalhos</span>Selecione um perfil salvo nas automações da Apple.</a>
  <a href="/pt-br/docs/android/"><span>Automação no Android</span>Use ações do Tasker e adb compatíveis com perfis.</a>
  <a href="/pt-br/docs/cli-direct/"><span>CLI direta</span>Execute as configurações salvas do perfil em uma pasta explícita do computador.</a>
</div>
