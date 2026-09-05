---
title: Wear OS 配套应用
description: Health.md for Wear OS 为您的手表添加活动与恢复卡片以及十种健康复杂功能，同时手机仍是 Health Connect 的权威来源。
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · Wear OS</p>
  <p>Health.md 在与手机应用相同的 Google Play 商品条目下提供 Wear OS 配套应用。在手机始终作为唯一 Health Connect 权威的同时，为您的手表添加一目了然的健康界面。</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">前往 Google Play 获取</a>
    <a class="docs-button-secondary" href="/zh-hans/docs/android/">Android 应用指南</a>
  </div>
</div>

## 手表显示的内容

| 界面 | 您获得的内容 |
|---|---|
| 每日活动卡片 | 以表盘卡片形式显示的今日活动摘要 |
| 恢复卡片 | 以表盘卡片形式显示的今日恢复摘要 |
| 复杂功能（10 种） | 活动、恢复、步数、活动量、锻炼、睡眠、静息心率、平均心率、HRV 和血氧，以表盘复杂功能形式显示 |

大多数表盘都可以通过表盘编辑器添加复杂功能，卡片则显示在手表的卡片轮播中。

## 工作原理

- 手表应用通过与手机应用相同的 Play 条目和签名身份分发。
- 健康数据通过 Wear OS 数据层以专用聚合快照的形式从手机流向手表。手表**没有直接的 Health Connect 或 Health Services 传感**；每项指标都以手机为权威。
- 手表界面根据手机应用推送的最新快照刷新——没有账户，没有云端，健康数据绝不会离开您的设备。

## 要求

- 安装了 Health.md 并与 Wear OS 手表配对的 Android 手机。
- 手机上存在您想要查看的指标的 Health Connect 数据。
- 在手表的 Play 商店或配套手机的 Play 商店条目中，在手表上安装 Health.md。

## 设置

1. 在手表上打开 Play 商店（或手机 Play 商店的手表部分），安装 Health.md。
2. 打开一次手机应用，以便同步一个快照。
3. 长按您的表盘 → **自定义** → 添加 Health.md 复杂功能，或滑动到卡片轮播并固定 Health.md 卡片。

## 隐私与验证

配套应用使用纯粹的专用聚合传输契约，因此不会有任何原始记录传输到手表。发布质量以模拟器套件以及物理配对设备的电池和 OEM QA 证据为门槛，达标后才会发布 Wear OS 工件。完整流程请参阅 [Wear OS 实现清单](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/features/wear-os-implementation.md)。
