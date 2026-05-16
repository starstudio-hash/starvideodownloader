"use strict";

const GUMROAD_PRODUCT_ID = "vdHfyiPVIE20rc3y7Rfc8g==";
const GUMROAD_VERIFY_URL = "https://api.gumroad.com/v2/licenses/verify";
const BUY_PRO_URL = "https://firaskam.gumroad.com/l/xxmkcc";

const FREE_DAILY_DOWNLOAD_LIMIT = 5;
const FREE_MAX_CONCURRENT_DOWNLOADS = 1;
const PRO_MAX_CONCURRENT_DOWNLOADS = 99;

const RELEASE_DOWNLOADS = {
  mac: "https://github.com/starstudio-hash/starvideodownloader/releases/latest/download/Star.Video.Downloader.zip",
  windows: "https://starvideoapp.com/exp/Star.Video.Downloader.Windows.zip"
};

module.exports = {
  BUY_PRO_URL,
  FREE_DAILY_DOWNLOAD_LIMIT,
  FREE_MAX_CONCURRENT_DOWNLOADS,
  GUMROAD_PRODUCT_ID,
  GUMROAD_VERIFY_URL,
  PRO_MAX_CONCURRENT_DOWNLOADS,
  RELEASE_DOWNLOADS
};
