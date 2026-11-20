import { defineService } from '@nzyme/ioc/Service.js';
import { secretsProvider } from '@nzyme/secrets/commands/secretsProvider.js';
import { getSecretDefinitions } from '@nzyme/secrets/getSecretDefinitions.js';
import { keychainStore } from '@nzyme/secrets/keychainStore.js';

import * as secrets from './secrets.js';

/** umbra's secrets: the OS keychain of the current user, scope `umbra`. */
export const UmbraSecrets = defineService({
    name: 'UmbraSecrets',
    setup: () =>
        secretsProvider({
            secrets: getSecretDefinitions(secrets),
            store: keychainStore({ scope: 'umbra' }),
        }),
});
