#!/usr/bin/env bun
import { execute } from '@nzyme/cli-core/execute.js';
import { defineGmailCommands } from '@nzyme/gmail-cli/defineGmailCommands.js';
import { createContainer } from '@nzyme/ioc/Container.js';
import { defineSecretsCommands } from '@nzyme/secrets/commands/defineSecretsCommands.js';
import { loadSecretsConfig } from '@nzyme/secrets/loadSecretsConfig.js';

import { GMAIL_TOKENS } from './secrets.js';
import { UmbraGoogleClients } from './UmbraGoogleClients.js';
import { UmbraSecrets, UmbraSecretStore } from './UmbraSecrets.js';

const container = createContainer();
await loadSecretsConfig(container, container.resolve(UmbraSecrets).stores);

await execute({
    name: 'umbra',
    container,
    commands: [
        ...defineSecretsCommands({ provider: UmbraSecrets }),
        ...defineGmailCommands({
            auth: {
                store: UmbraSecretStore,
                tokens: GMAIL_TOKENS,
                client: UmbraGoogleClients,
                accounts: ['kedrzu@gmail.com', 'kedrzu@sigma.clinic'],
            },
            labels: {
                groups: {
                    status: ['AI/Done', 'AI/Triage'],
                    priority: ['P/0', 'P/1', 'P/2', 'P/3'],
                },
                // Every processed thread stays filterable by importance.
                require: [{ when: 'AI/Done', group: 'priority' }],
                // Nieaktualne = stale, kept for reference; Śmieci = junk, a marker only.
                archiveMarkers: ['Nieaktualne', 'Śmieci'],
                views: {
                    unprocessed: '-label:AI/Done -label:AI/Triage',
                    triage: 'label:AI/Triage',
                    pending: '-label:AI/Done',
                    done: 'label:AI/Done',
                },
            },
            reply: { locale: 'pl', timeZone: 'Europe/Warsaw' },
        }),
    ],
});
