const APP_STORE_ID = "6757763969";
const PLAY_STORE_PACKAGE = "com.healthmd.android";
export const DEFAULT_APP_STORE_URL = `https://apps.apple.com/us/app/health-md/id${APP_STORE_ID}`;
export const DEFAULT_PLAY_STORE_URL = `https://play.google.com/store/apps/details?id=${PLAY_STORE_PACKAGE}`;
export const DEFAULT_DOWNLOAD_URL = "https://healthmd.app/";

export const platformLabels = {
  tt: "TikTok",
  ig: "Instagram Reels",
  yt: "YouTube Shorts",
  x: "X/Twitter",
  th: "Threads",
  web: "Website",
};

export const angleConfig = {
  obsidian: {
    label: "Obsidian Daily Notes",
    ppidEnv: "CPP_OBSIDIAN_PPID",
  },
  privacy: {
    label: "Private / No Cloud",
    ppidEnv: "CPP_PRIVACY_PPID",
  },
  csv: {
    label: "CSV + Data Export",
    ppidEnv: "CPP_CSV_PPID",
  },
  homepage: {
    label: "Homepage CTA",
    ppidEnv: "CPP_HOMEPAGE_PPID",
  },
};

export const starterSlugs = [
  "tt-obsidian-001",
  "tt-obsidian-002",
  "ig-obsidian-001",
  "yt-obsidian-001",
  "tt-privacy-001",
  "tt-privacy-002",
  "ig-privacy-001",
  "yt-privacy-001",
  "tt-csv-001",
  "tt-csv-002",
  "ig-csv-001",
  "yt-csv-001",
];

export const explicitLinks = {
  "web-home": {
    slug: "web-home",
    platform: "web",
    platformLabel: platformLabels.web,
    angle: "homepage",
    angleLabel: angleConfig.homepage.label,
    sequence: "001",
    campaignToken: "web_home_001",
    ppidEnv: angleConfig.homepage.ppidEnv,
  },
};

function cleanSlug(slug) {
  return String(slug || "")
    .trim()
    .toLowerCase()
    .replace(/^\/+|\/+$/g, "");
}

export function parseCampaignSlug(rawSlug) {
  const slug = cleanSlug(rawSlug);
  if (!slug) return null;
  if (explicitLinks[slug]) return explicitLinks[slug];

  const match = slug.match(/^([a-z]{1,4})-([a-z0-9]+)-([0-9]{3})$/);
  if (!match) return null;

  const [, platform, angle, sequence] = match;
  const platformLabel = platformLabels[platform];
  const angleDetails = angleConfig[angle];
  if (!platformLabel || !angleDetails) return null;

  return {
    slug,
    platform,
    platformLabel,
    angle,
    angleLabel: angleDetails.label,
    sequence,
    campaignToken: `${platform}_${angle}_${sequence}`,
    ppidEnv: angleDetails.ppidEnv,
  };
}

export function buildAppStoreUrl(link, env = {}) {
  const target = new URL(env.APP_STORE_BASE_URL || DEFAULT_APP_STORE_URL);
  const providerToken = env.APPLE_PROVIDER_TOKEN;
  const productPageId = link.ppidEnv ? env[link.ppidEnv] : undefined;

  if (productPageId) {
    target.searchParams.set("ppid", productPageId);
  }
  if (providerToken) {
    target.searchParams.set("pt", providerToken);
  }

  target.searchParams.set("ct", link.campaignToken);
  target.searchParams.set("mt", "8");
  return target.toString();
}

export function buildPlayStoreUrl(link, env = {}) {
  const target = new URL(env.PLAY_STORE_BASE_URL || DEFAULT_PLAY_STORE_URL);
  const installReferrer = new URLSearchParams({
    utm_source: link.platform,
    utm_medium: "campaign_shortlink",
    utm_campaign: link.campaignToken,
    utm_content: link.angle,
  });

  target.searchParams.set("referrer", installReferrer.toString());
  return target.toString();
}

export function buildDownloadUrl(link, env = {}) {
  const target = new URL(env.DOWNLOAD_PAGE_URL || DEFAULT_DOWNLOAD_URL);
  target.searchParams.set("utm_source", link.platform);
  target.searchParams.set("utm_medium", "campaign_shortlink");
  target.searchParams.set("utm_campaign", link.campaignToken);
  target.searchParams.set("utm_content", link.angle);
  return target.toString();
}

export function starterCampaignLinks(baseUrl = "https://healthmd.app") {
  return starterSlugs
    .map((slug) => parseCampaignSlug(slug))
    .filter(Boolean)
    .map((link) => ({
      ...link,
      shortlink: `${baseUrl.replace(/\/+$/g, "")}/v/${link.slug}`,
    }));
}
