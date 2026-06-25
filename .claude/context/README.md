# Contesto AI — GudDesk Helpdesk

Questa cartella contiene la documentazione strutturata del progetto per assistere gli Agenti AI in future modifiche, integrazioni e analisi della codebase.

## Come usare questi file

Ogni file copre una sezione specifica dell'app. Prima di modificare o aggiungere funzionalità, leggi il file relativo alla sezione coinvolta. I file si cross-referenziano tra loro con link `[file.md](./file.md)`.

## Indice dei file

| File | Contenuto |
|---|---|
| [overview.md](./overview.md) | Stack, struttura cartelle, flusso dati, convenzioni globali |
| [auth.md](./auth.md) | NextAuth, providers, sessioni JWT, RBAC, guards |
| [database.md](./database.md) | Schema Prisma completo, tutti i modelli ed enum |
| [inbox.md](./inbox.md) | Conversazioni, messaggi, tipi, componenti UI |
| [knowledge-base.md](./knowledge-base.md) | Articoli, collections, help center pubblico |
| [automations.md](./automations.md) | Regole automazione, trigger, azioni, condizioni |
| [widget.md](./widget.md) | Widget Preact embeddabile, build, API, visitor auth |
| [ai.md](./ai.md) | Claude AI, client wrapper, prompts, usage logging |
| [real-time.md](./real-time.md) | Pusher, canali, eventi, autenticazione |
| [integrations.md](./integrations.md) | Slack, email (Resend), Google OAuth, analytics |
| [deployment.md](./deployment.md) | Docker, docker-compose, variabili d'ambiente, build |
| [api-routes.md](./api-routes.md) | Tutte le API REST con metodi, params, response |
| [server-actions.md](./server-actions.md) | Tutte le server actions con signatures e pattern |

## Aggiornamento di questa documentazione

Quando si aggiunge una nuova sezione all'app o si modifica significativamente una esistente:

1. Aggiorna il file `.claude/context/` relativo alla sezione modificata
2. Se si aggiunge una sezione completamente nuova, crea un nuovo file con lo stesso formato
3. Aggiorna i cross-reference nei file correlati
4. Aggiorna questo README con il nuovo file

## Note per gli agenti AI

- Queste sezioni si riferiscono alla codebase **nel momento in cui è stata scritta** — verificare sempre lo stato attuale dei file prima di fare assunzioni
- I modelli Prisma in `database.md` devono corrispondere a `prisma/schema.prisma` (fonte di verità)
- Le firme delle server actions in `server-actions.md` possono cambiare — verificare il file in `actions/`
- I nomi dei componenti in `inbox.md` e `knowledge-base.md` corrispondono ai file in `components/`
