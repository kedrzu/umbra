import { defineSecret } from '@nzyme/secrets/defineSecret.js';

// Every secret lives in the macOS keychain (UmbraSecrets), so none needs `meta.store` routing.

export const GOOGLE_CLIENT_ID = defineSecret('GOOGLE_CLIENT_ID', {
    description: 'Google OAuth client id (Desktop app), from the client JSON',
});

export const GOOGLE_CLIENT_SECRET = defineSecret('GOOGLE_CLIENT_SECRET', {
    description: 'Google OAuth client secret, from the client JSON',
});

export const GMAIL_TOKENS = defineSecret('GMAIL_TOKENS', {
    description: 'Gmail refresh tokens by account, written by `umbra gmail auth`',
});
