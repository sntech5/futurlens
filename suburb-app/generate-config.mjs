import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const envPath = resolve(process.cwd(), '.env');
const outputPath = resolve(process.cwd(), 'config.js');

function parseEnv(raw) {
  const map = {};
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim();
    map[key] = value;
  }
  return map;
}

const envFromFile = existsSync(envPath) ? parseEnv(readFileSync(envPath, 'utf8')) : {};
const env = { ...envFromFile, ...process.env };

const required = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'USER_PROFILE_ID'];
const missing = required.filter((key) => !env[key]);
if (missing.length) {
  throw new Error(`Missing required environment keys: ${missing.join(', ')}`);
}

const configJs = `window.APP_CONFIG = {
  supabaseUrl: ${JSON.stringify(env.SUPABASE_URL)},
  supabaseKey: ${JSON.stringify(env.SUPABASE_ANON_KEY)},
  supabaseFunctionJwt: ${JSON.stringify(env.SUPABASE_FUNCTION_JWT || env.SUPABASE_LEGACY_ANON_KEY || env.SUPABASE_ANON_JWT || '')},
  userProfileId: ${JSON.stringify(env.USER_PROFILE_ID)},
  googleMapsEmbedApiKey: ${JSON.stringify(env.GOOGLE_MAPS_EMBED_API_KEY || '')}
};
`;

writeFileSync(outputPath, configJs, 'utf8');
console.log(`Generated ${outputPath}`);
