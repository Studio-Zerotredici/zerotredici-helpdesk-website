# Knowledge Base — Articoli e Collections

Vedi anche: [database.md](./database.md), [widget.md](./widget.md).

## Panoramica

La knowledge base consente di creare articoli di supporto organizzati in collections. Gli articoli sono visibili pubblicamente nel help center e accessibili dal widget tramite search.

## Struttura Route

```
app/(protected)/workspace/[workspaceSlug]/articles/
├── page.tsx                     → Lista collections + articoli
├── [collectionId]/
│   ├── page.tsx                 → Articoli della collection
│   └── [articleId]/
│       └── page.tsx             → Editor articolo

app/(help-center)/
└── [workspaceSlug]/
    ├── page.tsx                 → Home help center pubblico
    ├── collections/[slug]/      → Articoli di una collection
    └── articles/[slug]/         → Singolo articolo pubblico
```

## Componenti principali

In `components/articles/`:

| Componente | Descrizione |
|---|---|
| `ArticleEditor` | Rich text editor per il corpo dell'articolo |
| `ArticleList` | Lista articoli con stato published/draft |
| `CollectionCard` | Card collection con count articoli |
| `ArticleFeedback` | Bottoni "Helpful / Not Helpful" |

## Modelli DB

```prisma
model Collection {
  id          String   @id
  name        String
  slug        String
  description String?
  isPublished Boolean  @default(false)
  icon        String?
  workspaceId String
  articles    Article[]
}

model Article {
  id           String  @id
  title        String
  slug         String
  body         String
  excerpt      String?
  isPublished  Boolean @default(false)
  viewCount    Int     @default(0)
  helpfulCount Int     @default(0)
  authorId     String
  collectionId String
  workspaceId  String
}

model HelpCenterSettings {
  id           String  @id
  title        String?
  subtitle     String?
  primaryColor String?
  logoUrl      String?
  workspaceId  String  @unique
}
```

## Server Actions

```typescript
// Articles
createArticle(workspaceId, collectionId, data)
updateArticle(articleId, data)
publishArticle(articleId, publish: boolean)
deleteArticle(articleId)

// Feedback visitatore
articleFeedback(articleId, helpful: boolean)
// → incrementa helpfulCount o notHelpfulCount

// Collections
createCollection(workspaceId, data)
updateCollection(collectionId, data)
deleteCollection(collectionId)

// Help Center Settings
updateHelpCenterSettings(workspaceId, data)
```

## Widget Search API

Il widget può cercare articoli:

```
GET /api/widget/articles/search?q=testo&workspaceId=xxx
→ Returns: Array<{ id, title, excerpt, slug }>
```

Solo articoli `isPublished: true` vengono restituiti.

## Help Center pubblico

- URL: `{APP_URL}/{workspaceSlug}/articles`
- Non richiede autenticazione
- Personalizzabile via `HelpCenterSettings` (titolo, colore, logo)
- Le collections e gli articoli con `isPublished: false` sono nascosti

## Accesso e permessi

- Solo `OWNER`, `ADMIN`, `AGENT` possono creare/modificare articoli
- `VIEWER` può solo leggere
- Visitatori pubblici accedono al help center senza auth

## Slug generation

Gli slug sono generati dal titolo al momento della creazione. Devono essere unici per workspace. Usati nelle URL pubbliche del help center.

## ContentLayer vs Articles

**Attenzione:** la cartella `content/docs/` usa ContentLayer per la documentazione del prodotto GudDesk (non per i contenuti del cliente). Il sistema knowledge base descritto qui è completamente separato e salvato nel database PostgreSQL.

Vedi [deployment.md](./deployment.md) per la build di ContentLayer.
