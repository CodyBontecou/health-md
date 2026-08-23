import { defaultLocale, publishedLocales } from './locales.mjs';

const text = (en, es, de, fr, ptBr, it, nl, ja, ko, zhHans) => Object.freeze({
  en,
  es,
  de,
  fr,
  'pt-br': ptBr,
  it,
  nl,
  ja,
  ko,
  'zh-hans': zhHans,
});

const item = (labels, slug = '') => Object.freeze({ labels, slug });

export const docsSidebar = Object.freeze([
  Object.freeze({
    labels: text('Get Started', 'Primeros pasos', 'Erste Schritte', 'Bien démarrer', 'Primeiros passos', 'Inizia', 'Aan de slag', 'はじめに', '시작하기', '开始使用'),
    items: Object.freeze([
      item(text('Choose a goal', 'Elige un objetivo', 'Ziel auswählen', 'Choisir un objectif', 'Escolha um objetivo', 'Scegli un obiettivo', 'Kies een doel', '目的を選ぶ', '목표 선택', '选择目标')),
      item(text('First iPhone export', 'Primera exportación desde iPhone', 'Erster iPhone-Export', 'Première exportation depuis l’iPhone', 'Primeira exportação no iPhone', 'Prima esportazione da iPhone', 'Eerste iPhone-export', '最初のiPhoneエクスポート', '첫 iPhone 내보내기', '首次从 iPhone 导出'), 'iphone-first-export'),
      item(text('First Android export', 'Primera exportación desde Android', 'Erster Android-Export', 'Première exportation depuis Android', 'Primeira exportação no Android', 'Prima esportazione da Android', 'Eerste Android-export', '初めてのAndroidエクスポート', '첫 Android 내보내기', '首次从 Android 导出'), 'android'),
      item(text('Connect an agent in 10 minutes', 'Conecta un agente en 10 minutos', 'Agenten in 10 Minuten verbinden', 'Connecter un agent en 10 minutes', 'Conecte um agente em 10 minutos', 'Collega un agente in 10 minuti', 'Koppel een agent in 10 minuten', '10分でエージェントを接続', '10분 안에 에이전트 연결', '10 分钟连接智能体'), 'guides/connect-agent'),
      item(text('Feature overview by platform', 'Funciones por plataforma', 'Funktionen nach Plattform', 'Fonctionnalités par plateforme', 'Recursos por plataforma', 'Funzioni per piattaforma', 'Functies per platform', 'プラットフォーム別の機能', '플랫폼별 기능', '各平台功能概览'), 'guides/platform-features'),
      item(text('Agent configuration reference', 'Referencia de configuración del agente', 'Referenz zur Agentenkonfiguration', 'Référence de configuration de l’agent', 'Referência de configuração do agente', 'Riferimento per la configurazione dell’agente', 'Naslag voor agentconfiguratie', 'エージェント設定リファレンス', '에이전트 구성 참고 자료', '智能体配置参考'), 'configuration'),
      item(text('Mac companion', 'App para Mac', 'Mac-Begleitapp', 'App compagnon pour Mac', 'App complementar para Mac', 'App per Mac', 'macOS-app', 'Macアプリ', 'Mac 앱', 'Mac 配套应用'), 'macos'),
    ]),
  }),
  Object.freeze({
    labels: text('Use an Agent', 'Usar un agente', 'Agenten verwenden', 'Utiliser un agent', 'Usar um agente', 'Usa un agente', 'Een agent gebruiken', 'エージェントを使う', '에이전트 사용', '使用智能体'),
    collapsed: true,
    items: Object.freeze([
      item(text('MCP server & tools', 'Servidor MCP y herramientas', 'MCP-Server & Tools', 'Serveur MCP et outils', 'Servidor MCP e ferramentas', 'Server MCP e strumenti', 'MCP-server en tools', 'MCPサーバーとツール', 'MCP 서버 및 도구', 'MCP 服务器与工具'), 'mcp'),
      item(text('Bundled & portable CLI', 'CLI incluida y portátil', 'Mitgelieferte & portable CLI', 'CLI intégrée et portable', 'CLI incluída e portátil', 'CLI integrata e portatile', 'Gebundelde en platformonafhankelijke CLI', '同梱CLIとポータブルCLI', '번들 및 이식 가능한 CLI', '内置与可移植 CLI'), 'cli'),
      item(text('Query cookbook', 'Recetas de consultas', 'Abfragebeispiele', 'Recettes de requêtes', 'Guia de consultas', 'Ricette per le query', 'Queryrecepten', '型付きクエリ例', '쿼리 활용법', '查询指南'), 'agent-queries'),
      item(text('Agent architecture', 'Arquitectura de agentes', 'Agentenarchitektur', 'Architecture des agents', 'Arquitetura de agentes', 'Architettura degli agenti', 'Agentarchitectuur', 'エージェントアーキテクチャ', '에이전트 아키텍처', '智能体架构'), 'agents'),
      item(text('Direct iPhone CLI · Preview', 'CLI directa para iPhone · Vista previa', 'Direkte iPhone-CLI · Vorschau', 'CLI iPhone directe · Aperçu', 'CLI direta para iPhone · Prévia', 'CLI diretta per iPhone · Anteprima', 'CLI rechtstreeks naar de iPhone · Preview', 'iPhone直接接続CLI・プレビュー', '직접 iPhone CLI · 미리보기', 'iPhone 直连 CLI · 预览'), 'cli-direct'),
      item(text('Canonical extraction', 'Extracción canónica', 'Kanonische Extraktion', 'Extraction canonique', 'Extração canônica', 'Estrazione canonica', 'Canonieke extractie', '正規抽出', '정규 추출', '规范提取'), 'cli-extract'),
      item(text('Durable jobs', 'Tareas persistentes', 'Persistente Aufträge', 'Tâches persistantes', 'Tarefas persistentes', 'Attività persistenti', 'Persistente taken', '永続ジョブ', '영속 작업', '持久作业'), 'cli-jobs'),
    ]),
  }),
  Object.freeze({
    labels: text('Export & Automate', 'Exportar y automatizar', 'Exportieren & automatisieren', 'Exporter et automatiser', 'Exportar e automatizar', 'Esporta e automatizza', 'Exporteren en automatiseren', 'エクスポートと自動化', '내보내기 및 자동화', '导出与自动化'),
    collapsed: true,
    items: Object.freeze([
      item(text('iPhone onboarding', 'Configuración inicial en iPhone', 'iPhone-Einrichtung', 'Prise en main sur iPhone', 'Introdução no iPhone', 'Configurazione iniziale su iPhone', 'iPhone-onboarding', 'iPhoneのオンボーディング', 'iPhone 온보딩', 'iPhone 新手引导'), 'onboarding'),
      item(text('Folders & vaults', 'Carpetas y bóvedas', 'Ordner & Vaults', 'Dossiers et coffres', 'Pastas e cofres', 'Cartelle e vault', 'Mappen en kluizen', 'フォルダとVault', '폴더 및 보관함', '文件夹与知识库'), 'folder-vault'),
      item(text('Export from iPhone', 'Exportar desde iPhone', 'Vom iPhone exportieren', 'Exporter depuis l’iPhone', 'Exportar do iPhone', 'Esporta da iPhone', 'Exporteren vanaf de iPhone', 'iPhoneからエクスポート', 'iPhone에서 내보내기', '从 iPhone 导出'), 'export'),
      item(text('Apple Health metrics', 'Métricas de Apple Health', 'Apple-Health-Metriken', 'Indicateurs Apple Health', 'Métricas do Apple Health', 'Metriche di Apple Health', 'Apple Health-meetwaarden', 'Apple Healthの指標', 'Apple Health 항목', 'Apple Health 指标'), 'metrics'),
      item(text('Export formatting', 'Formato de exportación', 'Exportformatierung', 'Format d’exportation', 'Formato de exportação', 'Formato di esportazione', 'Exportformaat', 'エクスポート形式', '내보내기 형식', '导出格式'), 'format'),
      item(text('Scheduled exports', 'Exportaciones programadas', 'Geplante Exporte', 'Exportations programmées', 'Exportações agendadas', 'Esportazioni pianificate', 'Geplande exports', 'スケジュールエクスポート', '예약된 내보내기', '计划导出'), 'scheduling'),
      item(text('Mac sync', 'Sincronización con Mac', 'Mac-Synchronisierung', 'Synchronisation Mac', 'Sincronização com o Mac', 'Sincronizzazione Mac', 'Mac-synchronisatie', 'Mac同期', 'Mac 동기화', 'Mac 同步'), 'sync'),
      item(text('Shortcuts & App Intents', 'Atajos y App Intents', 'Kurzbefehle & App Intents', 'Raccourcis et App Intents', 'Atalhos e App Intents', 'Comandi rapidi e App Intents', 'Opdrachten en App Intents', 'ショートカットとApp Intents', '단축어 및 App Intents', '快捷指令与 App Intents'), 'shortcuts'),
      item(text('Individual entries', 'Entradas individuales', 'Individuelle Einträge', 'Entrées individuelles', 'Registros individuais', 'Voci singole', 'Individuele vermeldingen', '個別エントリ', '개별 항목', '单条记录'), 'individual-tracking'),
      item(text('Daily notes', 'Notas diarias', 'Tägliche Notizen', 'Notes quotidiennes', 'Notas diárias', 'Note giornaliere', 'Dagelijkse notities', 'デイリーノート', '일일 노트', '每日笔记'), 'daily-notes'),
      item(text('Raw API snapshots', 'Instantáneas de API sin procesar', 'Rohe API-Snapshots', 'Instantanés d’API brutes', 'Snapshots de API brutas', 'Snapshot API non elaborati', 'Ruwe API-snapshots', 'Raw APIスナップショット', '원시 API 스냅샷', '原始 API 快照'), 'guides/raw-snapshots'),
    ]),
  }),
  Object.freeze({
    labels: text('Build an Integration', 'Crear una integración', 'Integration entwickeln', 'Créer une intégration', 'Criar uma integração', 'Crea un’integrazione', 'Een integratie bouwen', '連携を構築', '통합 구축', '构建集成'),
    collapsed: true,
    items: Object.freeze([
      item(text('Contract overview', 'Resumen de contratos', 'Vertragsübersicht', 'Vue d’ensemble des contrats', 'Visão geral dos contratos', 'Panoramica dei contratti', 'Contractoverzicht', 'コントラクト概要', '계약 개요', '契约概览'), 'reference'),
      item(text('API & CLI envelopes', 'Sobres de API y CLI', 'API- und CLI-Envelopes', 'Enveloppes API et CLI', 'Envelopes de API e CLI', 'Envelope API e CLI', 'API- en CLI-enveloppen', 'API・CLIエンベロープ', 'API 및 CLI 엔벨로프', 'API 与 CLI 封装'), 'reference/api-and-cli'),
      item(text('Queries & evidence', 'Consultas y evidencia', 'Abfragen & Nachweise', 'Requêtes et preuves', 'Consultas e evidências', 'Query ed evidenze', 'Query’s en bewijs', 'クエリとエビデンス', '쿼리 및 근거', '查询与证据'), 'reference/evidence-packets'),
      item(text('Loopback API', 'API de loopback', 'Loopback-API', 'API en boucle locale', 'API de loopback', 'API di loopback', 'Loopback-API', 'ループバックAPI', '루프백 API', '环回 API'), 'agent-api'),
      item(text('API endpoint', 'Endpoint de API', 'API-Endpunkt', 'Endpoint d’API', 'Endpoint de API', 'Endpoint API', 'API-eindpunt', 'APIエンドポイント', 'API 엔드포인트', 'API 端点'), 'api-endpoint'),
      item(text('Direct protocol', 'Protocolo directo', 'Direktprotokoll', 'Protocole direct', 'Protocolo direto', 'Protocollo diretto', 'Protocol voor directe verbinding', '直接接続プロトコル', '직접 연결 프로토콜', '直连协议'), 'reference/connected-mac-iphone-protocol'),
      item(text('Integration recipes', 'Recetas de integración', 'Integrationsrezepte', 'Recettes d’intégration', 'Receitas de integração', 'Ricette di integrazione', 'Integratierecepten', '連携レシピ', '통합 레시피', '集成方案'), 'reference/integration-recipes'),
      item(text('Generated artifacts', 'Artefactos generados', 'Generierte Artefakte', 'Artefacts générés', 'Artefatos gerados', 'Artefatti generati', 'Gegenereerde artefacten', '生成物', '생성된 산출물', '生成的构件'), 'reference/generated'),
    ]),
  }),
  Object.freeze({
    labels: text('Data Reference', 'Referencia de datos', 'Datenreferenz', 'Référence des données', 'Referência de dados', 'Riferimento dati', 'Gegevensreferentie', 'データリファレンス', '데이터 참조', '数据参考'),
    collapsed: true,
    items: Object.freeze([
      item(text('Daily records', 'Registros diarios', 'Tägliche Datensätze', 'Enregistrements quotidiens', 'Registros diários', 'Record giornalieri', 'Dagrecords', '日次レコード', '일별 레코드', '每日记录'), 'reference/daily-records'),
      item(text('Canonical Apple Health records', 'Registros canónicos de Apple Health', 'Kanonische Apple-Health-Datensätze', 'Enregistrements Apple Health canoniques', 'Registros canônicos do Apple Health', 'Record canonici di Apple Health', 'Canonieke Apple Health-records', '正規Apple Healthレコード', '정규 Apple Health 레코드', '规范 Apple Health 记录'), 'reference/canonical-healthkit-records'),
      item(text('Export formats', 'Formatos de exportación', 'Exportformate', 'Formats d’exportation', 'Formatos de exportação', 'Formati di esportazione', 'Exportformaten', 'エクスポート形式', '내보내기 형식', '导出格式'), 'reference/export-formats'),
      item(text('Data dictionary & roll-ups', 'Diccionario de datos y agregaciones', 'Datenwörterbuch & Roll-ups', 'Dictionnaire de données et agrégations', 'Dicionário de dados e consolidações', 'Dizionario dati e aggregazioni', 'Gegevenswoordenboek en overzichten', 'データ辞書と集計', '데이터 사전 및 집계', '数据字典与汇总'), 'reference/data-dictionary-and-rollups'),
      item(text('Shared metric registry', 'Registro compartido de métricas', 'Gemeinsames Metrikregister', 'Registre partagé des métriques', 'Registro compartilhado de métricas', 'Registro condiviso delle metriche', 'Gemeenschappelijk meetwaarderegister', '共有指標レジストリ', '공유 측정 항목 레지스트리', '共享指标注册表'), 'shared-metric-registry'),
      item(text('Reference generation', 'Generación de documentación', 'Referenzgenerierung', 'Génération de la documentation', 'Geração da documentação', 'Generazione della documentazione', 'Documentatie genereren', 'リファレンス生成', '문서 생성', '参考文档生成'), 'reference/generation'),
    ]),
  }),
  Object.freeze({
    labels: text('More', 'Más', 'Mehr', 'Plus', 'Mais', 'Altro', 'Meer', 'その他', '더보기', '更多'),
    collapsed: true,
    items: Object.freeze([
      item(text('Visualization catalog', 'Catálogo de visualizaciones', 'Visualisierungskatalog', 'Catalogue de visualisations', 'Catálogo de visualizações', 'Catalogo delle visualizzazioni', 'Visualisatiecatalogus', '可視化カタログ', '시각화 카탈로그', '可视化目录'), 'visualizations-roadmap'),
      item(text('Unlock & plans', 'Desbloqueo y planes', 'Freischaltung & Pläne', 'Déverrouillage et offres', 'Desbloqueio e planos', 'Sblocco e piani', 'Ontgrendelen en opties', 'ロック解除とプラン', '잠금 해제 및 요금제', '解锁与方案'), 'paywall'),
      item(text('Wear OS companion', 'Complemento de Wear OS', 'Wear-OS-Begleiter', 'Compagnon Wear OS', 'Complemento Wear OS', 'Compagno Wear OS', 'Wear OS-compagnon', 'Wear OSコンパニオン', 'Wear OS 컴패니언', 'Wear OS 配套应用'), 'guides/wear-os'),
    ]),
  }),
]);

function starlightLabel(labels) {
  return {
    label: labels[defaultLocale],
    translations: Object.fromEntries(
      publishedLocales('docs')
        .filter(({ code }) => code !== defaultLocale)
        .map(({ code }) => [code, labels[code]]),
    ),
  };
}

export function starlightSidebar() {
  const doc = (slug = '') => ['docs', slug].filter(Boolean).join('/');
  return docsSidebar.map((group) => ({
    ...starlightLabel(group.labels),
    ...(group.collapsed ? { collapsed: true } : {}),
    items: group.items.map((entry) => ({
      ...starlightLabel(entry.labels),
      slug: doc(entry.slug),
    })),
  }));
}
