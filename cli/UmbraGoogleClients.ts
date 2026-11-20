import type { GoogleClientProvider } from '@nzyme/google-auth/GoogleClientProvider.js';
import { defineService } from '@nzyme/ioc/Service.js';

import { GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET } from './secrets.js';

/** One OAuth client for every account. */
export const UmbraGoogleClients = defineService({
    name: 'UmbraGoogleClients',
    deps: { clientId: GOOGLE_CLIENT_ID, clientSecret: GOOGLE_CLIENT_SECRET },
    setup: ({ clientId, clientSecret }): GoogleClientProvider => ({
        async getClient() {
            return { clientId, clientSecret };
        },
    }),
});
