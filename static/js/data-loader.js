// Parse response as JSON or JSONL depending on file extension.
async function _parseDataResponse(filename, res) {
  const text = await res.text();
  if (filename.endsWith('.jsonl')) {
    return text.trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
  }
  return JSON.parse(text);
}

// Fetch a JSON/JSONL file directly from GitHub via jsDelivr CDN (explicit — no fallback).
// Uses jsDelivr instead of raw.githubusercontent.com because GitHub's CDN omits Origin
// from its Vary header, causing browsers to receive cached responses without CORS headers.
async function loadFromGitHub(filename) {
  const { githubDataRepo } = window.DATA_CONFIG || {};
  if (!githubDataRepo) throw new Error('DATA_CONFIG.githubDataRepo is not set');
  const url = `https://cdn.jsdelivr.net/gh/${githubDataRepo}@main/${filename}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`GitHub fetch failed for ${filename}: HTTP ${res.status}`);
  return _parseDataResponse(filename, res);
}

// Fetch a JSON/JSONL file directly from GCS (explicit — no fallback).
async function loadFromGCS(filename) {
  const { gcsBucket } = window.DATA_CONFIG || {};
  if (!gcsBucket) throw new Error('DATA_CONFIG.gcsBucket is not set');
  const url = `https://storage.googleapis.com/${gcsBucket}/${filename}?t=${Date.now()}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`GCS fetch failed for ${filename}: HTTP ${res.status}`);
  return _parseDataResponse(filename, res);
}

// Fetches a JSON file: tries GitHub raw first, falls back to GCS.
// Requires window.DATA_CONFIG = { gcsBucket, githubDataRepo }
async function loadJsonData(filename) {
  const { gcsBucket, githubDataRepo } = window.DATA_CONFIG || {};

  console.debug(`[data-loader] loading ${filename} | githubDataRepo=${githubDataRepo} | gcsBucket=${gcsBucket}`);

  // --- Try GitHub (via jsDelivr CDN — guarantees CORS) ---
  if (githubDataRepo) {
    const githubUrl = `https://cdn.jsdelivr.net/gh/${githubDataRepo}@main/${filename}`;
    console.debug(`[data-loader] trying GitHub: ${githubUrl}`);
    try {
      const res = await fetch(githubUrl);
      console.debug(`[data-loader] GitHub response: ${res.status} for ${filename}`);
      if (res.ok) return await _parseDataResponse(filename, res);
      console.warn(`[data-loader] GitHub returned ${res.status} for ${filename}, falling back to GCS`);
    } catch (e) {
      console.warn(`[data-loader] GitHub fetch threw for ${filename}:`, e);
    }
  } else {
    console.warn(`[data-loader] githubDataRepo not set, skipping GitHub`);
  }

  // --- Fall back to GCS ---
  if (!gcsBucket) throw new Error('DATA_CONFIG.gcsBucket is not set');
  const gcsUrl = `https://storage.googleapis.com/${gcsBucket}/${filename}?t=${Date.now()}`;
  console.debug(`[data-loader] trying GCS: ${gcsUrl}`);
  try {
    const gcsRes = await fetch(gcsUrl);
    console.debug(`[data-loader] GCS response: ${gcsRes.status} for ${filename}`);
    if (!gcsRes.ok) throw new Error(`GCS fetch failed for ${filename}: ${gcsRes.status}`);
    return await gcsRes.json();
  } catch (e) {
    console.error(`[data-loader] GCS fetch threw for ${filename}:`, e);
    throw e;
  }
}
