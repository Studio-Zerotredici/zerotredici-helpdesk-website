# Chatwoot Data Model (v4.15.1-ce)

Chatwoot's core Rails data model is a fairly conventional multi-tenant
helpdesk schema: everything hangs off `Account` (the tenant), and the
central entity is `Conversation`, which threads together a `Contact`
(the customer), an `Inbox` (the channel it came in on), a list of
`Message`s, and an optional assignment to a `User` (agent) or `Team`.
Contacts don't belong to a single inbox — the join table `ContactInbox`
lets one contact be reachable across multiple channels while keeping a
per-channel external identity (`source_id`). Agents relate to accounts
through `AccountUser` (which carries the account-scoped role), and to
teams/inboxes through their own many-to-many join tables
(`TeamMember`, `InboxMember`). This structure is exactly what a future
Freshdesk import script needs to reproduce: create/match `Contact` →
resolve/create `Inbox` (likely one inbox per imported channel, or a
single "Freshdesk Import" API inbox) → create `ContactInbox` linking
them → create `Conversation` → create `Message`s in order. Schema
grounded against `vendor/chatwoot/db/schema.rb`
(`ActiveRecord::Schema[7.1].define(version: 2026_06_11_184600)`), which
matches the annotated schema comments in each model file.

This doc covers the data model only. For confirmed native-feature
status of email channel, Teams, and other integration items, see
`docs/INTEGRATIONS_ROADMAP.md` — not re-derived here.

## Key files

| File | What it is |
|---|---|
| `vendor/chatwoot/app/models/account.rb` | Tenant root. Owns nearly every other resource via `has_many`. |
| `vendor/chatwoot/app/models/conversation.rb` | Core support-ticket entity; status/priority state, links contact+inbox+account+assignee+team. |
| `vendor/chatwoot/app/models/contact.rb` | A customer/end-user record, scoped to an account. |
| `vendor/chatwoot/app/models/contact_inbox.rb` | Join model: one contact's identity within one specific inbox/channel (`source_id`). |
| `vendor/chatwoot/app/models/inbox.rb` | A channel instance (email, web widget, WhatsApp, API, etc.) via polymorphic `channel`. |
| `vendor/chatwoot/app/models/message.rb` | A single chat/email message inside a conversation; polymorphic sender. |
| `vendor/chatwoot/app/models/user.rb` | An agent/admin login identity (Devise-based), can belong to multiple accounts. |
| `vendor/chatwoot/app/models/account_user.rb` | Join model: a `User`'s role (`agent`/`administrator`) within one `Account`. |
| `vendor/chatwoot/app/models/team.rb` | A named group of agents within an account (e.g. "WEB", "IT"), assignable to conversations. |
| `vendor/chatwoot/app/models/team_member.rb` | Join model: `User` ↔ `Team`. |
| `vendor/chatwoot/app/models/inbox_member.rb` | Join model: `User` ↔ `Inbox` (which agents can see/handle an inbox). |
| `vendor/chatwoot/app/models/label.rb` | Account-scoped tag definition, applied to conversations via `acts_as_taggable_on`. |
| `vendor/chatwoot/app/models/custom_attribute_definition.rb` | Schema definition for custom fields on conversations/contacts/companies. |
| `vendor/chatwoot/app/models/agent_bot.rb` | A webhook-driven bot identity that can be a message sender or conversation assignee. |
| `vendor/chatwoot/db/schema.rb` | Ground-truth DB schema (Rails 7.1, version `2026_06_11_184600`), cross-checked against every model above. |

## Account

`vendor/chatwoot/app/models/account.rb:1-19` (schema annotation), class body `:25-224`.

- Represents a tenant/workspace. Columns: `name`, `domain` (inbound email domain, not a website domain — comment explicitly warns against repurposing it, `account.rb:41-43`), `support_email`, `locale`, `status` enum (`active: 0, suspended: 1`, `account.rb:106`), `settings`/`custom_attributes`/`internal_attributes`/`limits` (all `jsonb`), `feature_flags` (bitmask via `FlagShihTzu`, `account.rb:27`).
- `has_many` nearly every other resource in the app (`conversations`, `contacts`, `inboxes`, `users` through `account_users`, `teams`, `labels`, `messages`, `custom_attribute_definitions`, all `Channel::*` types, `webhooks`, `automation_rules`, `macros`, etc.) — `account.rb:60-101`. This is the tenant boundary; almost every other table carries an `account_id`.
- `agents` / `administrators` helper methods filter `users` by `account_users.role` (`account.rb:115-121`).
- A DB trigger creates a per-account Postgres sequence `conv_dpid_seq_<id>` on insert (`account.rb:187-189`), used to generate the human-facing `display_id` on conversations (see Conversation below) — this is why `display_id` is unique per account, not globally.

## Conversation

`vendor/chatwoot/app/models/conversation.rb:1-32` (schema annotation), class body `:54-390`.

- Central entity. Required associations enforced by validation: `account_id`, `inbox_id`, `contact_id` all `presence: true` (`conversation.rb:65-67`); `contact_inbox` and `team` are `belongs_to ... optional: true` for team (`conversation.rb:109`) but `contact_inbox` itself is a hard `belongs_to` (`:108`).
- Key associations (`conversation.rb:103-118`): `belongs_to :account`, `:inbox`, `:contact`, `:contact_inbox`; `belongs_to :assignee, class_name: 'User', optional: true`; `belongs_to :assignee_agent_bot, class_name: 'AgentBot', optional: true`; `belongs_to :team, optional: true`; `belongs_to :campaign, optional: true`; `has_many :messages`, `:mentions`, `:conversation_participants`, `:attachments` (through messages), `:reporting_events`; `has_one :csat_survey_response`.
- **Status enum**: `open: 0, resolved: 1, pending: 2, snoozed: 3` (`conversation.rb:75`). **Priority enum**: `low: 0, medium: 1, high: 2, urgent: 3` (`conversation.rb:76`).
- Dual assignment model confirmed in code: a conversation can carry both a `team_id` and an individual `assignee_id` simultaneously (`conversation.rb:31` schema column, plus `belongs_to :team` alongside `belongs_to :assignee` at `:105-109`) — matches what `INTEGRATIONS_ROADMAP.md` describes for Teams.
- `assignee_type` virtual method (`conversation.rb:197-202`) resolves to `'AgentBot'`, `'User'`, or `nil` — assignee is polymorphic in practice today even though it's modeled as two separate FK columns (`assignee_id` for `User`, `assignee_agent_bot_id` for `AgentBot`), not a single polymorphic column; a comment at `:196` calls this out as a "virtual attribute till we switch completely to polymorphic assignee."
- `display_id` (per-account sequential ticket number) is populated by a DB trigger, not Rails (`conversation.rb:383-385`, trigger `NEW.display_id := nextval('conv_dpid_seq_' || NEW.account_id)`), and re-fetched after insert in `load_attributes_created_by_db_triggers` (`:322-329`) since Rails can't know the DB-generated value at INSERT time.
- `identifier` column (schema line `conversation.rb:13`) exists for external-system correlation but no model-level validation/usage was found in this file — worth using for a Freshdesk ticket ID if importing.
- State-changing helpers: `toggle_status` (`:154-159`, cycles open ↔ resolved, forces `pending`/`snoozed` back to `open`), `toggle_priority` (`:161-164`), `bot_handoff!` (`:166-170`).
- `waiting_since` / `first_reply_created_at` / `last_activity_at` drive SLA/unattended-conversation logic (`unattended` scope, `:84`; `resolvable_not_waiting`/`resolvable_all` scopes for auto-resolve, `:85-94`).
- `determine_conversation_status` (private, `:280-287`) sets initial status to `resolved` if the contact is blocked, or `pending` if the inbox has an active bot — otherwise defaults to the `open: 0` enum default from the schema.

## Contact

`vendor/chatwoot/app/models/contact.rb:1-40` (schema annotation), class body `:44-255`.

- Columns: `name`, `email`, `phone_number`, `identifier` (external ID), `country_code`, `additional_attributes`/`custom_attributes` (jsonb), `blocked` (boolean), `contact_type` enum, `company_id`.
- **contact_type enum**: `visitor: 0, lead: 1, customer: 2` (`contact.rb:71`).
- Uniqueness constraints are all scoped to `account_id`, confirming contacts are per-tenant, not global: `email` (`:51`, case-insensitive), `identifier` (`:53`), `phone_number` (`:54-56`, must match E.164 `\+[1-9]\d{1,14}`). DB backs this with `uniq_email_per_account_contact` and `uniq_identifier_per_account_contact` unique indexes (schema annotation `:38-39`).
- Associations (`contact.rb:58-64`): `belongs_to :account`; `has_many :conversations`; `has_many :contact_inboxes`; `has_many :inboxes, through: :contact_inboxes`; `has_many :messages, as: :sender` (contacts are a valid polymorphic sender on `Message`); `has_many :notes`.
- `identifier` field (schema `:14`) is the natural place to store a Freshdesk contact ID during migration, since it's already `uniqueness: { scope: :account_id }` and freeform.
- `self.from_email(email)` class method (`:194-196`) is a simple lookup — will be directly reusable for de-duplication logic in a Freshdesk import script.
- `stale_without_conversations` scope (`:134-144`) — contacts with no email/phone/identifier and no conversations, used for cleanup; not relevant to import but worth knowing exists.

## Inbox

`vendor/chatwoot/app/models/inbox.rb:1-40` (schema annotation), class body `:42-271`.

- Represents one configured channel (a specific email address, WhatsApp number, website widget, API endpoint, etc.). The actual channel-specific config/credentials live on a separate polymorphic `channel` association, not on `Inbox` itself: `belongs_to :channel, polymorphic: true, dependent: :destroy` (`inbox.rb:60`), backed by `channel_id`/`channel_type` columns (schema `:11,27-28`). Concrete channel classes live under `vendor/chatwoot/app/models/channel/` (e.g. `Channel::Email`, `Channel::WebWidget`, `Channel::Api`, `Channel::Whatsapp` — confirmed via `Account`'s `has_many` list, `account.rb:63,78-100`).
- Type-check helper methods (`inbox.rb:117-163`) — `email?`, `api?`, `web_widget?`, `whatsapp?`, `telegram?`, etc. — all just compare `channel_type` to a literal string, e.g. `channel_type == 'Channel::Email'` (`:145-147`). Confirms the roadmap doc's claim that email is a first-class native channel type requiring no code changes — it's just another `channel_type` string.
- Associations (`inbox.rb:57-76`): `belongs_to :account`; `belongs_to :portal, optional: true` (Help Center linkage); `has_many :contact_inboxes`; `has_many :contacts, through: :contact_inboxes`; `has_many :inbox_members` / `has_many :members, through: :inbox_members, source: :user`; `has_many :conversations`; `has_many :messages`; `has_one :agent_bot_inbox` / `has_one :agent_bot, through:`.
- `assignable_agents` (`:169-171`) = inbox members plus all account administrators (admins can always be assigned regardless of explicit membership).
- `active_bot?` (`:173-176`) checks either an active `AgentBotInbox` or an enabled Dialogflow hook — this is what flips a new conversation's initial status to `pending` (see `Conversation#determine_conversation_status` above).
- No enum on `channel_type` — it's a plain string column matching a Rails STI-like polymorphic class name, not a Rails `enum`.

## Message

`vendor/chatwoot/app/models/message.rb:1-24` (schema annotation), class body `:41-457`.

- Columns: `content` (text), `content_type` enum, `content_attributes` (json, used as a flexible key-value store via `store`), `message_type` enum, `private` (boolean — internal notes vs. customer-visible), `status` enum, `sender_type`/`sender_id` (polymorphic), `source_id` (external ID from the origin channel).
- **message_type enum**: `incoming: 0, outgoing: 1, activity: 2, template: 3` (`message.rb:87`). **content_type enum** (`:88-102`) covers `text`, various bot input types, `article`, `incoming_email`, `input_csat`, `sticker`, `voice_call`, etc. **status enum**: `sent: 0, delivered: 1, read: 2, failed: 3` (`:103`).
- Associations (`message.rb:128-135`): `belongs_to :account`, `:inbox`, `:conversation`; `belongs_to :sender, polymorphic: true, optional: true` — sender can be a `Contact`, `User`, `AgentBot`, or (per `merge_sender_attributes`, `:167-171`) `Captain::Assistant`; `has_many :attachments`; `has_one :csat_survey_response`.
- `private` flag (`:12` schema, used throughout e.g. `:118,211,225`) is how internal agent notes are distinguished from customer-visible replies within the same `messages` table — there is no separate "Note" table for conversation-level private messages (there is a separate top-level `note.rb` model, but that's for CRM-style contact/account notes per `Account`/`User` `has_many :notes`, not conversation replies).
- `source_id` (schema `:23`, text) is the external-system message identifier — directly relevant for a Freshdesk import script to preserve traceability back to the original ticket note/reply ID.
- Business logic of note: `human_response?` (`:362-371`) and `bot_response?` (`:373-376`) distinguish real agent replies from automation/bot/campaign-triggered ones, used to compute `first_reply_created_at` SLA timing (`valid_first_reply?`, `:224-233`, and `dispatch_create_events`, `:378-387`). A conversation only gets its very first "first reply" timestamp set once, from the first qualifying human outgoing message.
- `reopen_conversation` (`:403-410`) — an incoming message on a snoozed or resolved (non-muted) conversation automatically reopens it, with channel-specific handling for bot inboxes vs. API inboxes vs. everything else (`reopen_resolved_conversation`, `:424-434`).

## User

`vendor/chatwoot/app/models/user.rb:1-46` (schema annotation), class body `:48-231`.

- Represents a login identity (agent/admin/super-admin), not account-scoped itself — a single `User` row can belong to multiple `Account`s via `account_users` (`user.rb:87-89`). This is the standard Chatwoot multi-account-per-login pattern.
- Devise-based (`database_authenticatable`, `registerable`, `recoverable`, `trackable`, `confirmable`, `two_factor_authenticatable`, `omniauthable` with `google_oauth2`/`saml`, `user.rb:59-68`) — directly relevant to the planned Phase 2 MFA rollout mentioned in `docs/DEPLOYMENT_GUIDE.md`; MFA fields (`otp_secret`, `otp_backup_codes`, `otp_required_for_login`) are encrypted at rest (`encrypts :otp_secret, deterministic: true` / `encrypts :otp_backup_codes`, `:83-85`).
- `availability` enum (`online: 0, offline: 1, busy: 2`, `:72`) is marked in a comment as legacy/to-be-removed in favor of per-account availability on `AccountUser` (`:70-71`) — note this if building anything that reads presence status; `AccountUser` also carries its own `availability` enum (see below) which is likely the more current source of truth.
- `message_signature` (text column, `:19`) is exactly the field backing the "agent email signatures" feature confirmed native in `INTEGRATIONS_ROADMAP.md` §5 — and the model confirms the roadmap's caveat: there's a single `message_signature` column on `User`, not one per inbox/channel, so it is indeed global per agent, not per-channel (`user.rb:19`, no per-inbox signature association exists anywhere in this file).
- Key associations (`user.rb:87-118`): `has_many :account_users` / `:accounts, through:`; `has_many :assigned_conversations` (aliased to `:conversations`, foreign key `assignee_id`, `:91-92`); `has_many :inbox_members` / `:inboxes, through:`; `has_many :team_members` / `:teams, through:`; `has_many :messages, as: :sender`; `has_many :macros` (foreign_key `created_by_id`).

## Team

`vendor/chatwoot/app/models/team.rb:1-17` (schema annotation), class body `:18-70`.

- Simple account-scoped group: `name` (unique per account, downcased before save, `:26-32`), `description`, `allow_auto_assign` (boolean).
- Associations (`:21-24`): `belongs_to :account`; `has_many :team_members`; `has_many :members, through: :team_members, source: :user`; `has_many :conversations, dependent: :nullify` — deleting a team nullifies `conversations.team_id` rather than deleting conversations, confirming teams are a soft grouping, not an ownership boundary.
- `add_members`/`remove_members` (`:37-52`) are the only mutation entry points besides direct `TeamMember` CRUD — this is what the "3-step wizard" in the Chatwoot UI (per `INTEGRATIONS_ROADMAP.md` §6) calls under the hood.
- No enum/state machine — teams have no internal status.

## Label

`vendor/chatwoot/app/models/label.rb:1-18` (schema annotation), class body `:19-56`.

- Account-scoped tag definition (`title`, unique per account and downcased before save, `:25-28,33-35`; `color`; `description`; `show_on_sidebar`).
- Not directly associated to `Conversation` via a Rails association — instead implemented through `acts_as_taggable_on` (confirmed by `Account#all_conversation_tags` in `account.rb:123-131`, which queries `ActsAsTaggableOn::Tagging` directly with `taggable_type: 'Conversation'`, and by `Label#conversations` here using `account.conversations.tagged_with(title)`, `label.rb:37-39`). So the actual DB-level join is the `acts-as-taggable-on` gem's polymorphic `taggings` table, not a Chatwoot-owned join table — there is no `label_conversations` table in the schema.
- `conversation.rb:9` confirms the denormalized cache: `Conversation` has a `cached_label_list` text column plus `cached_label_list_array` helper (`conversation.rb:184-186`) to avoid re-querying tags on every read.

## CustomAttributeDefinition

`vendor/chatwoot/app/models/custom_attribute_definition.rb:1-23` (schema annotation), class body `:24-77`.

- Defines the *schema* for custom fields — actual values are stored in the `custom_attributes` jsonb column on the target model (`Conversation`, `Contact`, or a `Company` — company model not read in this pass, flagged as unclear/not directly reviewed).
- **attribute_model enum**: `conversation_attribute: 0, contact_attribute: 1, company_attribute: 2` (`:45`). **attribute_display_type enum**: `text, number, currency, percent, link, date, list, checkbox` (`:46`).
- `STANDARD_ATTRIBUTES` constant (`:25-30`) lists the built-in (non-custom) field names per model — e.g. for `conversation`: `status, priority, assignee_id, inbox_id, team_id, display_id, campaign_id, labels, browser_language, country_code, referer, created_at, last_activity_at`; for `contact`: `name, email, phone_number, identifier, country_code, city, company_name, created_at, last_activity_at, referer, blocked`. A validation (`attribute_must_not_conflict`, `:67-74`) prevents defining a custom attribute with a key that collides with these.
- Directly relevant to Freshdesk migration: any Freshdesk custom ticket/contact field without a Chatwoot equivalent should become a `CustomAttributeDefinition` (with matching `attribute_model`) before writing values into the corresponding record's `custom_attributes` jsonb column.

## ContactInbox

`vendor/chatwoot/app/models/contact_inbox.rb:1-21` (schema annotation), class body `:23-79`.

- The join model that lets one `Contact` have a distinct external identity (`source_id`, e.g. an email address, a WhatsApp phone-id, or a website-widget-generated visitor ID) per `Inbox`/channel. `belongs_to :contact`, `belongs_to :inbox`, `has_many :conversations` (`:31-34`).
- Unique index `index_contact_inboxes_on_inbox_id_and_source_id` (schema annotation `:18`) — a `source_id` is only unique within a given inbox, not globally, which makes sense since different channels generate IDs independently.
- Channel-specific `source_id` format validation for Twilio/WhatsApp (`:60-73`) — not relevant to a generic API-based import inbox.
- `current_conversation` (`:54-56`) just returns the most recent conversation for that contact+inbox pairing — Chatwoot has a `lock_to_single_conversation` inbox-level flag (`inbox.rb:19` schema) for channels that should only ever have one active conversation per contact.

## AgentBot

`vendor/chatwoot/app/models/agent_bot.rb:1-19` (schema annotation), class body `:21-69`.

- A bot identity (`bot_type` enum currently only `webhook: 0`, `:41`) that can be attached to inboxes via `agent_bot_inboxes` and act as a message `sender` or conversation `assignee_agent_bot`.
- `account_id` is **optional** (`belongs_to :account, optional: true`, `:40`) — a bot with `account_id: nil` is a "system bot" available across all accounts (`system_bot?`, `:66-68`; `accessible_to` scope, `:27-30`, explicitly includes `account_id: [nil, account_id]`). Relevant context if Studio Zerotredici later evaluates Captain AI or any bot-based automation — bots are a first-class entity separate from `User`/human agents, not a role on `User`.
- `has_many :assigned_conversations, foreign_key: :assignee_agent_bot_id` (`:36-39`) confirms the earlier note on `Conversation`: bot assignment and human assignment are two separate FK columns, reconciled at the app layer via `Conversation#assignee_type`/`#assigned_entity`.

## AccountUser, TeamMember, InboxMember (join models)

- `AccountUser` (`account_user.rb:1-25` schema, `:27-86` class) — the account-scoped membership record for a `User`. Carries **role enum** `agent: 0, administrator: 1` (`:34`) and its own **availability enum** `online/offline/busy` (`:35`, likely the actual current-generation presence field, per the note on `User#availability` above). Also tracks `inviter_id` (self-referential to `User`) and (per schema-only columns not covered by a dedicated model in this pass) `agent_capacity_policy_id`/`custom_role_id`, suggesting Enterprise-only capacity/role features layer on top of this same table — not explored further here, flagged as unclear/EE-only.
- `TeamMember` (`team_member.rb:1-24`) — pure join: `belongs_to :user`, `belongs_to :team`, uniqueness scoped to team.
- `InboxMember` (`inbox_member.rb:1-39`) — pure join: `belongs_to :user`, `belongs_to :inbox`, uniqueness scoped to inbox; also hooks into round-robin auto-assignment queue management on create/destroy (`:25-36`), not a data-model concern but worth knowing it's not side-effect-free.

## Core relationships

```
Account (tenant)
 ├─ has_many Users            (through AccountUser: role = agent|administrator)
 ├─ has_many Inboxes          (each wraps one polymorphic Channel::* config)
 ├─ has_many Contacts
 ├─ has_many Teams            (through TeamMember: Team ↔ User)
 ├─ has_many Labels           (via acts-as-taggable-on, not a Chatwoot join table)
 ├─ has_many CustomAttributeDefinitions (schema for jsonb custom_attributes)
 └─ has_many Conversations, Messages (denormalized account_id on every child row)

Contact --< ContactInbox >-- Inbox        (per-channel external identity: source_id)
                 |
                 └──< Conversation         (contact_inbox_id FK; a conversation always
                                            belongs to exactly one contact_inbox)

Conversation
 ├─ belongs_to Account, Inbox, Contact, ContactInbox   (all required)
 ├─ belongs_to Team            (optional — group-level routing)
 ├─ belongs_to assignee (User) OR assignee_agent_bot (AgentBot)   (optional, mutually
 │                                                                exclusive in practice —
 │                                                                see reset_agent_bot_when_assignee_present,
 │                                                                conversation.rb:274-278)
 ├─ has_many Messages          (ordered by created_at; sender is polymorphic:
 │                              Contact | User | AgentBot | Captain::Assistant)
 └─ tagged_with Labels         (cached_label_list column caches the tag names)
```

Practical implication for a Freshdesk import script (per `docs/INTEGRATIONS_ROADMAP.md` §3):
a conversation cannot be created in isolation — it requires an existing `Account`,
`Inbox` (so decide up front whether imported history goes into a dedicated
"Freshdesk Import" `Channel::Api` inbox, or is split across per-channel inboxes),
`Contact`, and a `ContactInbox` row linking that contact to that inbox with some
`source_id` (the Freshdesk contact/requester ID is a reasonable choice). Only then
can `Message` rows be created against the conversation, in original chronological
order, since `display_id` and activity timestamps are derived at creation time.
`Contact#identifier` and `Message#source_id` are the two fields best suited to
carry over original Freshdesk IDs for traceability and idempotent re-runs.

## Explicitly unclear / not verified in this pass

- The `Company` model (referenced by `Contact#company_id` and by
  `CustomAttributeDefinition`'s `company_attribute` enum value) was not read in
  this pass — `vendor/chatwoot/app/models/` listing did not show a top-level
  `company.rb`; it may live under a different path or be an Enterprise-only
  model. Don't assume its schema without checking directly.
- `AccountUser.agent_capacity_policy_id` and `.custom_role_id` (visible in the
  schema annotation, `account_user.rb:13-14`) point at `AssignmentPolicy` and a
  custom-roles feature respectively — `assignment_policy.rb` exists in the
  models directory but was not read in this pass; likely Enterprise/paid-tier
  functionality given the "custom role" naming, not confirmed.
- No `add_foreign_key` constraints were found for `conversations`' FK-like
  columns in `schema.rb` — Chatwoot enforces referential integrity at the
  Rails/model layer (`belongs_to` + validations), not via Postgres foreign
  keys, for at least this table. Not exhaustively checked across all tables.
