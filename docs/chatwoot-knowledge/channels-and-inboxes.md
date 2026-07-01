# Channels and Inboxes — Chatwoot Internals

Every communication surface in Chatwoot (email, website widget, WhatsApp, API, social) is a
separate `Channel::*` ActiveRecord model, and an `Inbox` is a thin wrapper that points at exactly
one channel row via a polymorphic `belongs_to`. Inbound email specifically is ingested through
**Rails ActionMailbox**, but Chatwoot layers a second, custom path on top of it for IMAP polling
(since ActionMailbox alone only handles inbound routes/webhooks, not periodic mailbox fetching) —
both paths converge on the same `Imap::ImapMailbox`/`ReplyMailbox` processing code that creates
`Contact` → `Conversation` → `Message` records. Routing/assignment is two independent axes on
`Conversation`: an individual `assignee_id` (auto-assigned via one of two round-robin mechanisms)
and an optional `team_id` (never auto-assigned by inbox activity — only set explicitly via
Automation Rules, macros, or manual UI action), confirming the roadmap's "dual assignment" claim
at the code level.

## Key files

| File | What it is |
|---|---|
| `vendor/chatwoot/app/models/inbox.rb` | `Inbox` model — polymorphic `belongs_to :channel`, per-type predicate methods (`email?`, `web_widget?`, etc.), auto-assignment config |
| `vendor/chatwoot/app/models/concerns/channelable.rb` | Shared concern every `Channel::*` model includes — defines the inverse `has_one :inbox, as: :channel` |
| `vendor/chatwoot/app/models/channel/email.rb` | `Channel::Email` — IMAP/SMTP credentials, OAuth provider flags, `forward_to_email` generation |
| `vendor/chatwoot/app/models/channel/api.rb` | `Channel::Api` — generic webhook-fed channel (used for the "GitHub Activity" inbox idea in the roadmap) |
| `vendor/chatwoot/app/models/channel/web_widget.rb` | `Channel::WebWidget` — website widget config, pre-chat form, widget script generator |
| `vendor/chatwoot/app/mailboxes/application_mailbox.rb` | ActionMailbox router — decides `:reply` vs `:default` mailbox per inbound mail |
| `vendor/chatwoot/app/mailboxes/reply_mailbox.rb` | ActionMailbox mailbox — handles mail routed via SMTP/webhook ingress (e.g. Postmark/SES-style inbound) |
| `vendor/chatwoot/app/mailboxes/imap/imap_mailbox.rb` | Plain Ruby class (NOT an ActionMailbox subclass) — shared processing logic for IMAP-polled mail |
| `vendor/chatwoot/app/jobs/inboxes/fetch_imap_emails_job.rb` | Sidekiq job — polls a `Channel::Email`'s IMAP mailbox on an interval |
| `vendor/chatwoot/app/services/imap/fetch_email_service.rb` | Generic IMAP fetch (the path relevant for Studio Zerotredici's self-hosted Stalwart/Postfix mailbox) |
| `vendor/chatwoot/app/finders/email_channel_finder.rb` | Resolves which `Channel::Email` an inbound mail belongs to, by matching To/Cc/BCC/X-Original-To against `email` or `forward_to_email` |
| `vendor/chatwoot/app/models/concerns/auto_assignment_handler.rb` | `after_save` hook on `Conversation` that triggers agent auto-assignment |
| `vendor/chatwoot/app/services/auto_assignment/agent_assignment_service.rb` | Legacy round-robin assignment (per-conversation) |
| `vendor/chatwoot/app/services/auto_assignment/inbox_round_robin_service.rb` | Redis-backed round-robin queue per inbox |
| `vendor/chatwoot/app/jobs/auto_assignment/assignment_job.rb` | "Assignment V2" — batch/capacity-aware assignment job (feature-flagged) |
| `vendor/chatwoot/app/models/team.rb` | `Team` model — members, `allow_auto_assign` flag |
| `vendor/chatwoot/app/services/action_service.rb` | Executes Automation Rule / macro actions, including `assign_team` and `assign_agent` |
| `vendor/chatwoot/app/models/conversation.rb` | `Conversation` — holds both `assignee_id` and `team_id` as independent, nullable foreign keys |

## Channel architecture

`Inbox` does not store any channel-specific fields itself. Instead it has a **polymorphic
association**:

```ruby
belongs_to :channel, polymorphic: true, dependent: :destroy   # inbox.rb:60
```

The `inboxes` table carries `channel_id` and `channel_type` columns (`vendor/chatwoot/app/models/inbox.rb:11,28`,
schema comment lines 11/28/34), and `channel_type` is a string like `'Channel::Email'`,
`'Channel::WebWidget'`, `'Channel::Api'`, `'Channel::Whatsapp'`, etc. Each concrete channel
(`Channel::Email`, `Channel::Api`, `Channel::WebWidget`, `Channel::Whatsapp`, `Channel::Sms`,
`Channel::FacebookPage`, `Channel::Instagram`, `Channel::Telegram`, `Channel::Line`,
`Channel::Tiktok`, `Channel::TwilioSms`, `Channel::TwitterProfile` — full list at
`vendor/chatwoot/app/models/channel/`) includes the shared `Channelable` concern, which supplies
the inverse side:

```ruby
has_one :inbox, as: :channel, dependent: :destroy_async, touch: true   # concerns/channelable.rb:6
```

So the relationship is: one `Channel::Email` row (or `Channel::WebWidget`, etc.) has exactly one
`Inbox` row pointing back at it via `(channel_id, channel_type)`. This is the standard Rails
"single-table-per-type via polymorphism" pattern — it lets `Inbox` (and everything that queries
inboxes: conversations, contact_inboxes, reporting) stay channel-agnostic, while each channel table
only carries the columns that type actually needs (IMAP/SMTP creds for email, `website_token` for
the widget, `webhook_url`/`hmac_token` for the generic API channel). `Inbox` exposes convenience
predicates (`email?`, `web_widget?`, `api?`, `whatsapp?`, …) that just compare `channel_type`
(`inbox.rb:117-167`), used throughout the app instead of type-checking the polymorphic association
directly.

One channel model matters for the roadmap's "GitHub inbound visibility" idea:
**`Channel::Api`** (`vendor/chatwoot/app/models/channel/api.rb`) is a generic webhook-driven
channel with no built-in transport of its own — it just exposes an `identifier`/`hmac_token` pair
so an external system (e.g. an n8n workflow relaying GitHub webhooks) can POST conversation/message
data into Chatwoot's public API. This confirms the roadmap's suggestion is architecturally sound:
no new channel type would need to be built, only an n8n workflow feeding this existing channel
type.

## Email channel — inbound processing

Chatwoot uses **Rails ActionMailbox** (`ApplicationMailbox < ActionMailbox::Base`,
`vendor/chatwoot/app/mailboxes/application_mailbox.rb:1`) as its inbound-email framework, but only
one of *two* inbound paths actually goes through it:

**Path 1 — ActionMailbox ingress (SMTP relay/webhook style, e.g. Postmark/Mandrill/SES adapters or
direct SMTP-to-Rails ingestion).** `ApplicationMailbox` routes every inbound mail based on a
lambda:

```ruby
routing(
  lambda { |inbound_mail|
    valid_to_address?(inbound_mail) &&
    (reply_uuid_mail?(inbound_mail) || EmailChannelFinder.new(inbound_mail.mail).perform.present?)
  } => :reply
)
routing(all: :default)   # application_mailbox.rb:10-18
```

- `reply_uuid_mail?` recognizes reply-tracking addresses of the form
  `reply+<conversation-uuid>@domain` (`application_mailbox.rb:6,22-27`).
- Otherwise it asks `EmailChannelFinder` (`vendor/chatwoot/app/finders/email_channel_finder.rb`) to
  match the mail's To/Cc/`X-Original-To` headers (falling back to Bcc, gated by a
  `SKIP_INCOMING_BCC_PROCESSING` global config, `email_channel_finder.rb:23-34,49-57`) against any
  `Channel::Email.email` or `Channel::Email.forward_to_email` value
  (`email_channel_finder.rb:44-47`). `forward_to_email` is an auto-generated
  `<random-hex>@<account.inbound_email_domain>` address created on channel creation
  (`vendor/chatwoot/app/models/channel/email.rb:78-80`) — this is the address you'd point real
  mailbox forwarding rules at if using the ActionMailbox ingress path instead of/alongside IMAP.
- Matches go to **`ReplyMailbox`** (`vendor/chatwoot/app/mailboxes/reply_mailbox.rb`), which uses
  `Mailbox::ConversationFinder` to locate or build a `Conversation`, then creates the `Message`
  and attachments inside a transaction (`reply_mailbox.rb:6-19`). Everything else falls through to
  `DefaultMailbox`, which is a no-op (`vendor/chatwoot/app/mailboxes/default_mailbox.rb:2`) — mail
  that matches neither a reply UUID nor a known channel address is silently dropped.

**Path 2 — IMAP polling (the path relevant to this deployment, since Studio Zerotredici will use
generic IMAP/SMTP against its own Stalwart/Postfix mailbox rather than an inbound-webhook
provider).** This path does **not** go through `ActionMailbox::Base` routing at all — it's a
custom Sidekiq scheduled job:

- `Inboxes::FetchImapEmailsJob` (`vendor/chatwoot/app/jobs/inboxes/fetch_imap_emails_job.rb:3`) is
  enqueued periodically per inbox (fan-out job is
  `vendor/chatwoot/app/jobs/inboxes/fetch_imap_email_inboxes_job.rb:8`). It takes a Redis mutex per
  inbox (`Redis::Alfred::EMAIL_MESSAGE_MUTEX`, `fetch_imap_emails_job.rb:9-13`) to avoid concurrent
  fetches, then dispatches to one of three IMAP fetch services based on provider
  (`fetch_imap_emails_job.rb:32-38`): `Imap::GoogleFetchEmailService`,
  `Imap::MicrosoftFetchEmailService`, or the generic `Imap::FetchEmailService`
  (`vendor/chatwoot/app/services/imap/fetch_email_service.rb`) — the one used for plain
  IMAP/SMTP credentials, which is what Studio Zerotredici's setup requires per
  `docs/INTEGRATIONS_ROADMAP.md` section 4.
- Each fetched `Mail::Message` is then handed to **`Imap::ImapMailbox#process`**
  (`vendor/chatwoot/app/mailboxes/imap/imap_mailbox.rb:8`) — note this is a **plain Ruby class**,
  not an `ActionMailbox::Base` subclass, despite living under `app/mailboxes/`. It wraps the mail
  in a `MailPresenter` (`imap_mailbox.rb:39`), then in a single transaction:
  finds/creates the `Contact` by sender email (`imap_mailbox.rb:109-116`, via
  `inbox.contacts.from_email`), finds or creates the `Conversation` by matching
  `In-Reply-To`/`References` headers against existing `Message.source_id` values
  (`imap_mailbox.rb:42-107`, with a UUID-in-References fallback for agent-initiated threads at
  `FALLBACK_CONVERSATION_PATTERN`, line 6), creates the `Message`, and attaches any files
  (`imap_mailbox.rb:20-25`).
- Failure handling: per-message retry suppression after 3 failures within 6 hours via Rails cache
  (`fetch_imap_emails_job.rb:48-56`), a configurable per-email processing timeout
  (`GlobalConfigService.load('EMAIL_PROCESSING_TIMEOUT_SECONDS', 60)`, line 80), and IMAP-specific
  exception classes are caught and logged rather than raised (lines 14-22).

**Practical implication for this deployment:** since generic IMAP/SMTP is the configured method
(not Google/Microsoft OAuth), inbound mail delivery to Chatwoot happens exclusively via **Path 2**
polling `Inboxes::FetchImapEmailsJob` → `Imap::FetchEmailService` → `Imap::ImapMailbox`, not via
ActionMailbox's webhook routing. The ActionMailbox `application_mailbox.rb` routing table and
`forward_to_email` address only become relevant if a webhook-based inbound provider is configured
instead of/in addition to IMAP — worth remembering when debugging "email not arriving": check the
IMAP job/Sidekiq schedule and credentials first, not ActionMailbox ingress config.

I could not find, within the time available, the exact Sidekiq-cron/`sidekiq_schedule.yml` entry
that fires `Inboxes::FetchImapEmailsJob` on an interval — only the fan-out job that calls
`.perform_later` per inbox (`fetch_imap_email_inboxes_job.rb:8`). Worth confirming the actual
polling interval directly against `vendor/chatwoot/config/schedule.yml` (or equivalent) before
relying on a specific cadence assumption.

## Routing and assignment (Teams + agents)

`Conversation` carries two independent, nullable foreign keys — confirmed directly in the schema
comment and associations:

```ruby
belongs_to :assignee, class_name: 'User', optional: true, inverse_of: :assigned_conversations  # conversation.rb:105
belongs_to :assignee_agent_bot, class_name: 'AgentBot', optional: true                          # conversation.rb:106
belongs_to :team, optional: true                                                                # conversation.rb:109
```

These are set through **completely different mechanisms**:

**Individual agent assignment (`assignee_id`) is automatic**, driven by the `AutoAssignmentHandler`
concern included into `Conversation` (`conversation.rb:58`,
`vendor/chatwoot/app/models/concerns/auto_assignment_handler.rb`). An `after_save` callback
(`auto_assignment_handler.rb:6`) runs on every conversation save, but only actually assigns when
the conversation just transitioned to `open` (or, under "Assignment V2", to resolved/snoozed too —
`auto_assignment_handler.rb:14,30-32`) and `inbox.enable_auto_assignment?` is true and the current
assignee is blank or no longer has inbox access (`auto_assignment_handler.rb:40-48`). Two
assignment engines exist side by side, selected per-account by a feature flag:
- **Legacy** (`inbox.auto_assignment_v2_enabled?` false): `AutoAssignment::AgentAssignmentService`
  (`vendor/chatwoot/app/services/auto_assignment/agent_assignment_service.rb`) picks from a Redis
  list-backed round-robin queue per inbox
  (`vendor/chatwoot/app/services/auto_assignment/inbox_round_robin_service.rb`), restricted to
  *online* agents (`agent_assignment_service.rb:18-21`) who are also allowed for this conversation.
  If the conversation already has a `team_id`, the allowed pool is narrowed to that team's members
  who also have inbox capacity (`auto_assignment_handler.rb:25,34-38`, gated by
  `team.allow_auto_assign` — schema default `TRUE`, `team.rb:6`); otherwise the pool is all inbox
  members with assignment capacity (`inbox.rb:169-171,202-204`).
- **V2** (`assignment_v2` account feature flag, `inbox.rb:206-208`): work is delegated to
  `AutoAssignment::AssignmentJob` (`vendor/chatwoot/app/jobs/auto_assignment/assignment_job.rb`),
  enqueued per-inbox and coalesced (`auto_assignment_handler.rb:17-21`) — a capacity-aware batch
  assignment pass rather than a single-conversation round-robin pick. I did not trace V2's internal
  selection algorithm in this pass (only confirmed the enqueue trigger and its coexistence with the
  legacy path); worth a follow-up read of `assignment_job.rb` and
  `vendor/chatwoot/app/services/auto_assignment/round_robin_selector.rb` /
  `vendor/chatwoot/app/services/auto_assignment/assignment_service.rb` before relying on V2 behavior
  specifics.

**Team assignment (`team_id`) is never automatic on inbound mail** — nothing in the email
ingestion path (`Imap::ImapMailbox`, `ReplyMailbox`) sets `team_id`. It is only ever set through
explicit rule/action execution:

```ruby
def assign_team(team_ids = [])
  should_unassign = team_ids.blank? || %w[nil 0].include?(team_ids[0].to_s)
  return @conversation.update!(team_id: nil) if should_unassign
  return unless !team_ids[0].nil? && team_belongs_to_account?(team_ids)
  @conversation.update!(team_id: team_ids[0])   # action_service.rb:62-72
end
```

`ActionService` (`vendor/chatwoot/app/services/action_service.rb`) is the shared action executor
for both **Automation Rules** and **macros** — it also has `assign_agent`
(`action_service.rb:43-53`) for explicitly assigning an individual agent by rule/macro, independent
of the round-robin path above. This confirms the roadmap's model precisely: getting a new
conversation onto, say, the "WEB" team requires an Automation Rule (e.g. "inbox is X → assign team
WEB") or a manual/macro action — there is no native "auto-assign to team based on inbox" toggle
comparable to the individual-agent auto-assignment toggle on `Inbox`. Once a `team_id` is set
(by whatever means), individual round-robin assignment (legacy path) then narrows itself to that
team's members (`auto_assignment_handler.rb:25,34-38`) — this is the mechanical basis for "dual
assignment": a conversation can simultaneously sit on a `Team` (coarse routing, set by rule) and
carry an individual `assignee` (fine-grained, set by round-robin or rule), with the team narrowing
the round-robin candidate pool when both are configured for auto-assignment.
