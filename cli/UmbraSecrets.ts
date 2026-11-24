import { defineService } from '@nzyme/ioc/Service.js';
import { secretsProvider } from '@nzyme/secrets/commands/secretsProvider.js';
import { getSecretDefinitions } from '@nzyme/secrets/getSecretDefinitions.js';
import { keychainStore } from '@nzyme/secrets/keychainStore.js';
import type { SecretStore } from '@nzyme/secrets/SecretStore.js';

import * as secrets from './secrets.js';

/**
 * umbra's one store: the OS keychain of the current user, scope `umbra`. It is personal, so the Gmail
 * refresh tokens, which act as their owner, are read and written here too.
 */
export const UmbraSecretStore = defineService({
    name: 'UmbraSecretStore',
    setup: (): SecretStore => keychainStore({ scope: 'umbra' }),
});

/** umbra's secrets, all in {@link UmbraSecretStore}. */
export const UmbraSecrets = defineService({
    name: 'UmbraSecrets',
    deps: { store: UmbraSecretStore },
    setup: ({ store }) =>
        secretsProvider({
            secrets: getSecretDefinitions(secrets),
            store,
        }),
});
