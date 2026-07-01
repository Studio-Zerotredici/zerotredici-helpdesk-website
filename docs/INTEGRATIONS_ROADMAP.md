# Chatwoot Integrations & Knowledge Graph — Roadmap (planning only)

Status: **planning only**, same as `BRANDING_FORK_PLAN.md`. Nothing here has
been built. This captures everything discussed beyond branding: knowledge
graph, MCP/AI integration, Freshdesk import, email channel, agent signatures,
Teams, and GitHub visibility. Each item below is graded by how much is
already native to Chatwoot vs. how much needs custom work, based on directly
checked sources — not assumption.

## 1. Knowledge graph of the Chatwoot codebase

**Done — 2026-07-01.** Decided against `gbrain` (Christian's shared remote brain):
its ingestion mechanism can't read this Mac's local filesystem directly (the worker
runs on a separate Hetzner VPS), so it would've meant hand-writing curated pages one
by one over MCP anyway rather than a bulk import — no real advantage over a local
doc, plus it would've mixed project-specific technical detail into a cross-project
shared system. Went local instead: `docs/chatwoot-knowledge/` (start at
[00-overview.md](../docs/chatwoot-knowledge/00-overview.md)), six code-grounded
reference docs (data model, channels/inboxes, frontend architecture, branding
injection points, background jobs, API/integrations/enterprise boundary), every
claim cited to `vendor/chatwoot/path:LINE`. Directly answers the structural
questions this section originally listed (conversation/contact/inbox modeling,
Teams + email-channel logic, branding strings/asset paths) and meaningfully
de-scopes `BRANDING_FORK_PLAN.md` (native DB-backed branding config exists for
name/logo/attribution — only color tokens + favicon need a real file overlay).
Tied to the pinned tag `v4.15.1`; re-run on major version bumps, not continuously.

## 2. AI integration via MCP

Two distinct directions here — checked both, they're at very different maturity levels:

**Chatwoot → external MCP tools (Captain AI using MCP servers as tools).** Not built by Chatwoot yet — open feature request [chatwoot#14382](https://github.com/chatwoot/chatwoot/issues/14382) (opened May 2026): "Support MCP servers integration in Captain AI Agents." Also note Captain AI itself is a **paid feature** (not in Community Edition — see the pricing page checked earlier), so this direction requires both an unshipped feature and a paid plan. Not viable today.

**External MCP clients (Claude, Claude Code, Cowork) → Chatwoot as a tool.** This direction already works today via third-party MCP servers reading Chatwoot's REST API — e.g. [hugoblanc/chatwoot-mcp](https://github.com/hugoblanc/chatwoot-mcp) (MIT licensed, TypeScript, npm-installable). It exposes conversations/messages as MCP tools (list conversations, get conversation, list/send messages) authenticated with a normal Chatwoot agent API access token — no code changes to Chatwoot itself required. This is the realistic near-term path if what's wanted is "let Claude/agents read and act on helpdesk conversations."

Recommendation: this second direction is genuinely buildable now and low-risk (read a third-party open-source MCP server, or write a small one ourselves against Chatwoot's documented API — either way it runs *outside* Chatwoot, doesn't touch `vendor/chatwoot/` or the custom image at all). Worth a dedicated small project once the base deployment is live, separate from the branding fork.

## 3. Importing data from Freshdesk

Chatwoot has **no native Freshdesk connector** — the official migration guide ([chatwoot.com/hc/.../how-to-migrate-from-freshdesk-to-chatwoot](https://www.chatwoot.com/hc/user-guide/articles/1696159781-how-to-migrate-from-freshdesk-to-chatwoot)) is a manual process:

1. Export contacts from Freshdesk as CSV → import via Chatwoot's Contacts → Import.
2. Historical conversations have **no bulk import tool at all** — the official guidance is literally "use the [Conversations API](https://www.chatwoot.com/developers/api/#tag/Conversations/operation/newConversation)," i.e. write a script that reads Freshdesk tickets via Freshdesk's API and creates matching conversations in Chatwoot one by one. Nothing off-the-shelf does this mapping (statuses, tags, custom fields, attachments, private notes all need explicit field mapping — the official docs call this out as the hard part, not the export itself).

**Decided (2026-07-01): one-time historical migration.** Freshdesk stops being the support ticketing system once this runs — Chatwoot is seeded with past history and becomes the system of record going forward. This is a bounded, one-shot script, not a continuously-running bridge (contrast with the existing `freshdesk-wethod-bridge`, which stays live for timesheets — that one is unaffected by this decision).

Scope once this is picked up:
1. Contacts: Freshdesk CSV export → Chatwoot Contacts → Import (official path, no code).
2. Conversations: custom one-shot script — read tickets via Freshdesk's API (the existing `freshdesk-tickets` skill already knows how to authenticate/query, reusable for the "read" half), write them into Chatwoot via the [Conversations API](https://www.chatwoot.com/developers/api/#tag/Conversations/operation/newConversation) (the "write" half). Needs explicit field mapping decided before writing the script: statuses, tags, custom fields, attachments, private notes — the official docs flag this mapping as the actual hard part, not the export/import mechanics.
3. Run this **after** the base Chatwoot deployment is live and validated, not before — no reason to migrate history into an unproven instance.
4. Not started. No script exists yet.

## 4. Email channel — supporto@zerotredici.com

Fully native Chatwoot feature, no customization needed. Settings → Inboxes →
Add Inbox → Email, then choose one of:
- Google OAuth (if the mailbox is Google Workspace)
- Microsoft OAuth (if Microsoft 365)
- **Generic IMAP/SMTP** — the applicable path here, since Studio Zerotredici runs its own mail infrastructure (Stalwart/Postfix per existing conventions), not Google or Microsoft.

Needs: IMAP host/port/credentials and SMTP host/port/credentials for the
`supporto@zerotredici.com` mailbox. Standard setup once those exist — no
open questions, just needs the actual mailbox provisioned first.

## 5. Agent email signatures (at least 2 agents)

Fully native. Each agent sets their own signature under Profile Settings →
Personal Settings → Personal message signature — no admin/global config
needed, each agent does their own.

One real limitation to know about: since Chatwoot 3.x, a signature is
**global across all of that agent's channels** (email, website widget, API,
etc.) — there's no built-in per-inbox or per-channel signature yet (open
feature requests: [#4953](https://github.com/chatwoot/chatwoot/issues/4953), [#8247](https://github.com/chatwoot/chatwoot/issues/8247)). Fine for "2 agents,
2 signatures" as stated; would need custom work if different signatures per
channel per agent are wanted later.

Needs: the two agents' names/emails and desired signature text/HTML —
not yet specified.

## 6. Teams (future org structure: Studio 013 IT, Marketing, WEB, etc.)

Fully native, zero customization. Settings → Teams → Create new team,
3-step wizard: name/description/auto-assign toggle, then add member agents.
Conversations route to a Team (group-level) and can also carry an individual
assignee at the same time (dual assignment) — e.g. a ticket lands on "WEB"
team and gets individually assigned to one agent on it.

This is pure configuration once agents exist — no blockers, no code. Purely
a matter of deciding team names/membership when there are enough agents to
split.

## 7. GitHub Issues/PRs visibility for the WEB team

Re-confirms what's in `DEPLOYMENT_GUIDE.md`: Chatwoot's native GitHub
integration isn't shipped (their own roadmap says Q4 2026). Two flavors of
"GitHub integration" are actually different asks, worth distinguishing:

- **Outbound** (create/link a GitHub issue from a Chatwoot conversation) — the n8n bridge already sketched in `DEPLOYMENT_GUIDE.md`.
- **Inbound visibility** (WEB team sees GitHub issue/PR activity without leaving Chatwoot) — not previously covered. One clean option: use Chatwoot's generic **API Channel** (a channel type built for piping arbitrary external events in as conversations) fed by a GitHub webhook via n8n — new issues/PRs/merges land as conversation updates in a dedicated "GitHub Activity" inbox that the WEB team is a member of. Same n8n dependency as the outbound direction, so if both are wanted eventually, they're one workflow, not two.

Neither direction has been built. Both are workarounds for the same upstream
gap, worth building together if/when this becomes a priority.

## Summary table

| Item | Native to Chatwoot CE? | Blocked on |
|---|---|---|
| Knowledge graph | Done — `docs/chatwoot-knowledge/` | Nothing |
| MCP: Chatwoot as a tool for Claude | Yes (via 3rd-party MCP server) | Nothing — buildable now |
| MCP: Captain using external tools | No — unshipped + paid feature | Chatwoot roadmap + a paid plan |
| Freshdesk import | Partial (CSV contacts only) | One-time migration script — write after base deploy is live |
| Email channel (supporto@) | Yes | Mailbox credentials |
| Agent signatures | Yes | Agent names/emails/text |
| Teams | Yes | Team names/membership once agents exist |
| GitHub outbound (create issues) | No | n8n workflow (planned, not built) |
| GitHub inbound (visibility) | No | n8n + API channel (planned, not built) |
