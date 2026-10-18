// Which deployment this build is (set at build time in vite.config.js from Vercel's
// system variables). Production is the `main` branch, staging is the `staging` branch,
// anything else is a per-branch preview or local development.
/* global __APP_ENV__ */
const raw = typeof __APP_ENV__ === 'object' ? __APP_ENV__ : { vercelEnv: 'development', branch: '', commit: '' };

function resolve({ vercelEnv, branch }) {
  if (vercelEnv === 'production') return 'production';
  if (branch === 'staging') return 'staging';
  if (vercelEnv === 'preview') return 'preview';
  return 'development';
}

export const ENV = resolve(raw);
export const ENV_LABEL = { production: 'Production', staging: 'Staging', preview: 'Preview', development: 'Development' }[ENV];
export const BRANCH = raw.branch;
export const COMMIT = (raw.commit || '').slice(0, 7);
export const IS_PRODUCTION = ENV === 'production';
