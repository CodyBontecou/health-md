import { buildAppStoreUrl, starterCampaignLinks } from "../campaign-links.mjs";

const baseUrl = process.env.CAMPAIGN_BASE_URL || "https://healthmd.app";
const rows = starterCampaignLinks(baseUrl).map((link) => ({
  shortlink: link.shortlink,
  campaign_token: link.campaignToken,
  platform: link.platformLabel,
  angle: link.angleLabel,
  app_store_url: buildAppStoreUrl(link, process.env),
}));

const headers = ["shortlink", "campaign_token", "platform", "angle", "app_store_url"];
console.log(headers.join(","));
for (const row of rows) {
  console.log(headers.map((header) => csvCell(row[header])).join(","));
}

function csvCell(value) {
  const text = String(value ?? "");
  if (!/[",\n]/.test(text)) return text;
  return `"${text.replaceAll('"', '""')}"`;
}
