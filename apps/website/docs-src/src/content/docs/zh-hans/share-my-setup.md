---
title: "共享我的设置"
description: "了解仅供开发的 v2 配置转移流程，其中不包含健康数据、凭据、购买或设备信任。"
---

<div class="availability preview"><strong>开发预览 · 尚未获得发布资格</strong><p>v2 合约在完成实机互操作与无障碍验证前仍为 pre-canonical 和 planned。请勿在生产环境依赖它。</p></div>

Share My Setup 可打包一个或多个配置文件。它传递指标、格式、命名、组织方式和目标意图。绝不包含健康数据、令牌、实际文件夹权限、配对、购买、历史或任务。

1. 在源设备打开**设置 → Share My Setup**并导出 v2 文件。
2. 在目标设备打开并检查每个配置文件。
3. 选择**添加**或**替换**。
4. 在本机重新绑定文件夹、带凭据的 API 或 Mac。
5. 应用后先测试小范围导出。

事务是原子的，并提供一次**撤销**。绑定目标前配置文件会被阻止，导入的计划任务默认关闭。当前开发源码只写出 `healthmd.shared_setup` v2，拒绝 v1。

<div class="related"><a href="/zh-hans/docs/export-profiles/"><span>配置文件</span>冻结设置。</a><a href="/zh-hans/docs/guides/platform-features/"><span>状态</span>平台 QA。</a></div>
