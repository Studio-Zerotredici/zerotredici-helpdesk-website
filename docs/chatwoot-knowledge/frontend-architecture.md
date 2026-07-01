# Chatwoot Frontend Architecture

Chatwoot's frontend (`vendor/chatwoot/app/javascript/`) is not one Vue app but **seven independent Vue application bundles** sharing common code via aliases (`shared/`, `dashboard/`, `v3/`, `widget/`, etc. — see `vendor/chatwoot/vite.shared.ts:3-14`). Each bundle has its own entrypoint file under `entrypoints/`, is built as a separate Vite output, and is mounted into a different Rails ERB view via `vite_javascript_tag '<pack_name>'`. The two most important for a branding pass are `dashboard/` (the agent-facing admin app, Vuex + migrating to Pinia) and `widget/` (the customer-facing embeddable chat widget, its own Vuex store, its own router, and its own i18n set — genuinely separate from the dashboard, not a mode-switch of the same app). Vue 3.5 + Vite 6 + vue-router 4 are used throughout; state management is mid-migration from Vuex 4 (legacy, still primary in `dashboard/store/` and `widget/store/`) to Pinia 3 (newer, used in `dashboard/stores/` (plural) and all of `v3/`).

## Key directories

| Path (under `app/javascript/`) | What it is |
|---|---|
| `dashboard/` | The agent/admin dashboard SPA — by far the largest app (routes, components, store, i18n, settings pages, conversation UI, etc.) |
| `dashboard/components-next/` | Newer component set actively replacing `dashboard/components/`; per `vendor/chatwoot/CLAUDE.md`, message bubbles specifically should use `components-next/` — the rest of `components/` is being deprecated |
| `widget/` | The embeddable customer-facing chat widget SPA — own `App.vue`, `router.js`, `store/`, `i18n/`, `views/`, `components/` |
| `sdk/` (`vendor/chatwoot/app/javascript/sdk/`) | The tiny public JS SDK (`sdk.js`, `IFrameHelper.js`, `bubbleHelpers.js`, etc.) that customer sites embed; it creates/controls the iframe that loads the `widget` bundle — not a Vue app itself |
| `v3/` | A newer, Pinia-based mini-app used specifically for auth/login/onboarding flows (`v3app` entrypoint, mounted when request path includes `/auth` or `/login`, see `vendor/chatwoot/app/controllers/dashboard_controller.rb:101-106`) |
| `portal/` | The public Help Center ("portal") app — notably NOT a Vue SPA entrypoint the same way; `entrypoints/portal.js` just boots Rails UJS + Turbo (`vendor/chatwoot/app/javascript/entrypoints/portal.js:1-9`), with `portal/components` used as Turbo-enhanced partials, not a client-side-routed app |
| `survey/` | Small standalone Vue app for CSAT survey response pages (own `App.vue`, `store/`, `i18n/`, `views/`) |
| `superadmin_pages/` | Small Vue app for parts of the Rails-admin ("Super Admin") UI (`views/`, `components/`, no dedicated store seen) |
| `shared/` | Cross-app shared code: `components/`, `composables/`, `constants/`, `helpers/`, `mixins/`, `store/` — imported via the `shared` Vite alias by dashboard, widget, survey, etc. |
| `design-system/` | Histoire (component-story/dev-tool) assets and styles (`histoire.scss`, `images/`) — this plus each app's `assets/` directory (e.g. `dashboard/assets/`, `widget/assets/`) is the top-level place a branding/theming pass would need to inspect for logo/color assets. Exact injection points are out of scope here (being researched separately). |
| `entrypoints/` | The 8 Vite entry files, one per bundle: `dashboard.js`, `widget.js`, `sdk.js`, `portal.js`, `survey.js`, `superadmin.js`, `superadmin_pages.js`, `v3app.js` |

## Build tooling

- **Vue**: `^3.5.12` (`vendor/chatwoot/package.json` dependencies block, `vue` entry)
- **Router**: `vue-router ~4.4.5`
- **Build tool**: **Vite `6.4.2`**, via `vite-plugin-ruby` (Rails integration) — see `vendor/chatwoot/vite.config.ts:1-17`. Note there is no webpack anywhere in this version; Chatwoot fully migrated to Vite (comments like `// [VITE] Disabled this...` in `entrypoints/dashboard.js:52` and `entrypoints/v3app.js:16-18` are leftover migration markers).
- Config split across three files:
  - `vendor/chatwoot/vite.config.ts` — main config (plugins: `ruby()`, `vue()`, `yaml()`; SCSS via `modern-compiler` API)
  - `vendor/chatwoot/vite.shared.ts` — shared path aliases (`components`, `next`, `v3`, `dashboard`, `helpers`, `shared`, `survey`, `widget`, `assets`) and Vue compiler options (treats `ninja-keys` as a custom element)
  - `vendor/chatwoot/vite.lib.config.ts` — separate config used only for `pnpm build:sdk` (`vite build --config vite.lib.config.ts`, `vendor/chatwoot/package.json:15`), producing the small public SDK bundle (size-limited to 40KB per `package.json` `size-limit` block) distinct from the ~300KB widget bundle
- `vendor/chatwoot/config/vite.json` configures dev-server behavior (port 3036 dev / 3037 test, `sourceCodeDir: app/javascript`).
- Rails views pull in each bundle via `vite_client_tag` + `vite_javascript_tag '<pack>'`, e.g.:
  - `app/views/layouts/vueapp.html.erb:74-75` → dynamic `@application_pack` (`dashboard` or `v3app`)
  - `app/views/widgets/show.html.erb:36-37` → `'widget'`
  - `app/views/layouts/_portal_head.html.erb:6-7` → `'portal'`
  - `app/views/survey/responses/show.html.erb:10-11` → `'survey'`
  - `app/views/layouts/super_admin/application.html.erb:25-26` and `app/views/super_admin/devise/sessions/new.html.erb:5-6` → `'superadmin'`
  - `app/views/super_admin/application/_navigation.html.erb:10-11` → `'superadmin_pages'`

## Dashboard app structure

- Entry: `vendor/chatwoot/app/javascript/entrypoints/dashboard.js` — creates the Vue app, wires `vue-i18n`, Vuex `store`, Pinia, `vue-router`, Sentry, FormKit, FloatingVue, highlight.js plugin, and a custom `WootUiKit` component library (`dashboard/components`) plus `WootWizard`.
- `dashboard/App.vue` — root component.
- `dashboard/routes/index.js` — creates the router (`createWebHistory`), assembles routes from `dashboard/routes/dashboard/dashboard.routes.js`, and (in `initalizeRouter()`) runs an auth/onboarding guard before each navigation (`vendor/chatwoot/app/javascript/dashboard/routes/index.js:57-69`).
- `dashboard/routes/dashboard/` contains one subdirectory per feature area, each presumably exporting its own route module: `campaigns/`, `captain/`, `commands/`, `companies/`, `contacts/`, `conversation/`, `customviews/`, `helpcenter/`, `inbox/`, `noAccounts/`, `notifications/`, `onboarding/`, `settings/`, `suspended/`, `upgrade/`.
- `dashboard/components/` — legacy/current component library; `dashboard/components-next/` is the newer set actively replacing it (message bubbles specifically, per `vendor/chatwoot/CLAUDE.md`).
- Other top-level dashboard dirs: `api/` (API clients), `assets/` (images/branding-relevant static assets), `composables/`, `constants/`, `helper/`, `i18n/`, `mixins/`, `modules/`, `services/`, `store/` (Vuex), `stores/` (Pinia, newer — see State Management below).
- The `v3/` app (separate bundle, `v3app.js` entry) is used specifically for `/auth` and `/login` paths per `vendor/chatwoot/app/controllers/dashboard_controller.rb:101-106`; it reuses `dashboard/i18n` messages but has its own `App.vue`, `store/`, `views/` router, and is Pinia-only (no Vuex import in its entrypoint).

## Widget app structure

- Entry: `vendor/chatwoot/app/javascript/entrypoints/widget.js` — a materially simpler bootstrap than the dashboard: creates the Vue app, wires `vue-i18n`, its own Vuex `store` (`widget/store`), its own `router` (`widget/router.js`), FormKit, DOMPurify, and an `ActionCableConnector` for realtime messaging (`vendor/chatwoot/app/javascript/entrypoints/widget.js:49-53`). No Pinia, no Sentry, no FloatingVue/highlight.js — confirming it's a lighter, purpose-built bundle rather than the dashboard app in a different mode.
- Top-level dirs: `App.vue`, `api/`, `assets/`, `components/`, `composables/`, `constants/`, `helpers/`, `i18n/`, `mixins/`, `router.js`, `store/`, `views/`.
- Mounted by Rails at `app/views/widgets/show.html.erb:36-37` (the iframe target page), separately from any dashboard view.
- The public embed script (`sdk/sdk.js` and friends, `entrypoints/sdk.js`) is a distinct, much smaller, framework-agnostic bundle (`build:sdk` script, size-capped at 40KB in `package.json`) that customer websites load directly; its job is to create/manage the iframe that loads the widget bundle and pass messages via `IFrameHelper.js` — it is not itself a Vue app.

## State management

Two systems coexist, reflecting an in-progress migration:

- **Vuex 4** (`~4.1.0`, `vendor/chatwoot/package.json`) — the legacy/primary pattern. Present in:
  - `dashboard/store/` — `index.js` (root store setup), `modules/` (per-feature Vuex modules), `storeFactory.js`, `mutation-types.js`, `constants.js`, `utils/`. Wired into the dashboard app via `sync(store, router)` from `vuex-router-sync` (`entrypoints/dashboard.js:17,42`).
  - `widget/store/` — `index.js`, `modules/`, `types.js`.
  - `survey/store/` and `shared/store/` also exist (shared store utilities used across apps).
- **Pinia 3** (`^3.0.4`) — the newer pattern, added alongside Vuex rather than replacing it wholesale yet:
  - `dashboard/stores/` (note: plural, distinct directory from `dashboard/store/`) — e.g. `calls.js`, `companies.js`, both using `defineStore(...)` (confirmed in `vendor/chatwoot/app/javascript/dashboard/stores/calls.js:5,15`).
  - `v3/store/index.js` — the `v3` app's only store, Pinia-based (its entrypoint never imports Vuex).
  - Both Pinia and Vuex are instantiated together in the dashboard entrypoint (`entrypoints/dashboard.js:44,48-49`: `createPinia()` alongside the Vuex `store`), so new dashboard features can adopt Pinia incrementally while older modules stay on Vuex.

## Routing

- **Dashboard**: `vue-router` `createWebHistory()` router assembled in `dashboard/routes/index.js`, routes sourced from `dashboard/routes/dashboard/dashboard.routes.js` plus per-feature route files under `dashboard/routes/dashboard/<feature>/`. Global navigation guard (`initalizeRouter()`, `dashboard/routes/index.js:57-69`) handles auth/account/onboarding redirects (`validateAuthenticateRoutePermission`, same file lines 15-55) before letting a navigation through.
- **v3 (auth/login/onboarding)**: separate router from `v3/views/index.js` (imported in `entrypoints/v3app.js:11` as `router, { initalizeRouter }`), same general pattern (guarded, initialized on boot) but an entirely separate router instance from the dashboard's.
- **Widget**: its own router at `widget/router.js`, imported directly into `entrypoints/widget.js:9`.
- **Survey**: has its own `views/` directory (`survey/views/`) but no dedicated router.js was found at the top level — routing setup for this small app was not further traced (out of scope for this pass; low-signal for branding work).
- **Portal**: not a `vue-router` SPA at all — driven by Rails routing + Hotwire Turbo (`entrypoints/portal.js:1-9` just calls `Rails.start()` and `Turbo.start()`), with `portal/components` acting as progressively-enhanced partials rather than router-driven views.

## i18n / locale handling

Locale files live under a consistent `<app>/i18n/locale/` convention per app, each app maintaining its own message set (not shared globally):

- `dashboard/i18n/locale/` (also used, via reimport, by the `v3` app's entrypoint — `entrypoints/v3app.js:4` imports `dashboard/i18n`)
- `widget/i18n/locale/`
- `survey/i18n/locale/`

Contents were not inspected (per instructions — low-signal, directory location only). No locale directory was found for `portal/`, `superadmin_pages/`, or `sdk/` at the same depth; not further investigated.
