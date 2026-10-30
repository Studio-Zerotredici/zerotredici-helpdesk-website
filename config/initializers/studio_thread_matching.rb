require 'json'
# Scoped Chatwoot v4.17.1 email-thread fallback. Copy-tested only; not installed.
# Mount as a Rails initializer for both rails and sidekiq only after approval.
module StudioThreadMatching
  PREFIX = /\A\s*(?:(?:re|r|i|fwd|fw|aw)\s*:\s*|\[?not scanned!\]?\s*:?\s*)/i
  GENERIC = %w[info richiesta preventivo assistenza supporto problema urgente segnalazione fattura documenti domanda ciao].freeze
  OWN_DOMAINS = %w[zerotredici.com zerotredici.app].freeze
  MAX_CANDIDATES = 200
  MAX_MESSAGES = 500

  def self.event(name, **ids)
    Rails.logger.info('studio_thread_matching ' + JSON.generate(event: name, **ids))
  rescue StandardError
    nil
  end

  def self.normalized_subject(value)
    subject = value.to_s.strip
    8.times do
      stripped = subject.sub(PREFIX, '').strip
      break if stripped == subject

      subject = stripped
    end
    subject = subject.downcase.gsub(/\s+/, ' ').strip
    return nil if subject.length < 10 || subject.split.length < 2 ||
                  GENERIC.include?(subject) || ['nessun oggetto', 'no subject'].include?(subject)

    subject
  end

  def self.addresses(value)
    Array.wrap(value).filter_map do |raw|
      address = Mail::Address.new(raw.to_s).address&.downcase
      address if address&.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
    rescue Mail::Field::ParseError, Mail::Field::IncompleteParseError
      nil
    end.uniq
  end

  def self.message_ids(mail)
    (Array.wrap(mail.in_reply_to) + Array.wrap(mail.references)).map(&:to_s).uniq.first(50)
  end

  # Written only by the authenticated outbound sender as private User notes.
  # The note lives in the target conversation, so account/inbox scope is native.
  def self.outbound_match(mail, inbox)
    return nil unless inbox

    ids = message_ids(mail).map { |id| id.strip.delete_prefix('<').delete_suffix('>') }
    return nil if ids.empty?

    notes = inbox.messages.where(private: true, sender_type: 'User', source_id: ids)
                 .includes(:conversation).limit(51).to_a
    return nil if notes.length > 50

    matches = notes.filter_map do |note|
      binding = note.content_attributes['studio_outbound_v1']
      next unless binding.is_a?(Hash) && binding['message_id'] == note.source_id && binding['version'] == 1 && binding['inbox_id'] == inbox.id &&
                  binding['ticket_id'] == note.conversation.display_id

      redirect(note.conversation)
    end.uniq(&:id)
    if matches.one?
      event('outbound_match', inbox_id: inbox.id, conversation_id: matches.first.id)
      matches.first
    end
  rescue StandardError => error
    log_failure('outbound_match', error)
    nil
  end

  def self.token_match(mail, inbox)
    return nil unless inbox&.channel_type == 'Channel::Email'

    tokens = mail.subject.to_s.scan(/\[#([1-9][0-9]*)\]/).flatten.uniq
    return nil unless tokens.one?

    target = inbox.conversations.find_by(display_id: tokens.first.to_i)
    return nil unless target

    notes = target.messages.where(private: true, sender_type: 'User').limit(MAX_MESSAGES + 1).to_a
    bindings = notes.filter_map do |note|
      binding = note.content_attributes['studio_outbound_v1']
      binding if binding.is_a?(Hash) && binding['version'] == 1 &&
                 binding['message_id'] == note.source_id && binding['inbox_id'] == inbox.id &&
                 binding['ticket_id'] == target.display_id
    end
    senders = addresses(mail.from)
    prior = addresses(target.contact.email)
    prior.concat(target.conversation_participants.includes(:user).flat_map { |participant| addresses(participant.user.email) })
    prior.concat(bindings.flat_map { |binding| addresses(binding['recipients']) })
    # Native inbound senders are external participants; ignore text and quoted headers.
    messages = target.messages.where(message_type: :incoming).limit(MAX_MESSAGES + 1).to_a
    prior.concat(messages.flat_map { |message| addresses(message.sender.email) if message.sender.respond_to?(:email) }.compact)
    eligible = notes.length <= MAX_MESSAGES && messages.length <= MAX_MESSAGES &&
               bindings.any? && senders.one? && prior.include?(senders.first)
    match = redirect(target)
    if eligible && ENV['STUDIO_THREAD_TOKEN_MODE'] == 'join'
      event('token_match', inbox_id: inbox.id, conversation_id: match.id)
      match
    else
      event('token_would_join', inbox_id: inbox.id, conversation_id: match.id, eligible: eligible)
      nil
    end
  rescue StandardError => error
    log_failure('token_match', error)
    nil
  end

  def self.unbound_candidate_ids(mail)
    return [] unless mail

    message_ids(mail).select { |id| id.match?(/\A<?(?:companion-|mattia-portfolio-|customer-)[^<>\s]+@zerotredici\.com>?\z/) }
  end

  def self.source_match(mail, inbox)
    return nil unless inbox

    message_ids(mail).each do |source_id|
      message = inbox.messages.find_by(source_id: source_id)
      if message&.conversation
        match = redirect(message.conversation)
        event('source_match', inbox_id: inbox.id, conversation_id: match.id)
        return match
      end
    end
    nil
  rescue StandardError => error
    log_failure('source_match', error)
    nil
  end

  def self.log_failure(operation, error)
    Rails.logger.warn("studio_thread_matching #{operation} fallback #{error.class.name}")
  rescue StandardError
    nil
  end

  def self.own_addresses(inbox)
    inbox.account.inboxes.where(channel_type: 'Channel::Email').includes(:channel).flat_map do |item|
      [item.channel.email, item.channel.forward_to_email]
    end.flat_map { |value| addresses(value) }.uniq
  end

  def self.external_addresses(values, own)
    values.uniq.reject do |address|
      own.include?(address) || OWN_DOMAINS.include?(address.split('@').last)
    end
  end

  def self.subject_mode
    ENV['STUDIO_THREAD_SUBJECT_MODE'] == 'join' ? 'join' : 'observe'
  end

  def self.subject_route(mail, inbox)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    candidate_count = 0
    return nil if unbound_candidate_ids(mail).any?
    return nil if mail&.subject.to_s.match?(/\[#([1-9][0-9]*)\]/)

    match = subject_match(mail, inbox) { |count| candidate_count = count }
    if match && subject_mode == 'observe'
      Rails.logger.info("studio_thread_matching would join conversation #{match.id} (candidates #{candidate_count})")
      nil
    else
      match
    end
  rescue StandardError => error
    log_failure('subject_route', error)
    nil
  ensure
    if started && subject_mode == 'observe'
      begin
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        Rails.logger.info("studio_thread_matching subject_scan_ms=#{elapsed_ms} candidates=#{candidate_count}")
      rescue StandardError
        nil
      end
    end
  end

  def self.redirect(conversation)
    return nil unless conversation

    target_id = conversation.additional_attributes['studio_merged_into']
    return conversation unless target_id

    target = Conversation.find_by(id: target_id, account_id: conversation.account_id,
                                  inbox_id: conversation.inbox_id)
    unless target && target.id != conversation.id &&
           target.additional_attributes['studio_merged_into'].blank?
      Rails.logger.warn('studio_thread_matching invalid redirect; native conversation retained')
      return conversation
    end

    event('redirect', from_id: conversation.id, to_id: target.id)
    target
  rescue StandardError => error
    log_failure('redirect', error)
    conversation
  end

  def self.subject_match(mail, inbox)
    return nil unless inbox&.channel_type == 'Channel::Email'

    subject = normalized_subject(mail.subject)
    return nil unless subject

    own = own_addresses(inbox)
    participants = external_addresses(addresses(mail.from) + addresses(mail.to) + addresses(mail.cc), own)
    return nil if participants.empty?

    suffix = ActiveRecord::Base.sanitize_sql_like(subject)
    candidates = inbox.conversations.where(status: %w[open pending resolved])
                     .where('last_activity_at >= ?', 14.days.ago)
                     .where("lower(coalesce(additional_attributes->>'mail_subject', '')) LIKE ?", "%#{suffix}")
                     .order(last_activity_at: :desc)
                     .limit(MAX_CANDIDATES + 1).to_a
    yield candidates.length if block_given?
    return nil if candidates.length > MAX_CANDIDATES

    matches = candidates.select do |conversation|
      next false if conversation.additional_attributes['studio_merged_into'].present?
      next false unless normalized_subject(conversation.additional_attributes['mail_subject']) == subject

      messages = conversation.messages.where.not(message_type: Message.message_types.fetch('activity'))
                             .limit(MAX_MESSAGES + 1).to_a
      next false if messages.length > MAX_MESSAGES

      prior = [conversation.contact.email.to_s.downcase]
      messages.each do |message|
        prior << message.sender.email.to_s.downcase if message.sender.respond_to?(:email)
        email = message.content_attributes&.dig('email') || {}
        prior.concat(addresses(email['from']) + addresses(email['to']) + addresses(email['cc']))
      end
      (participants & external_addresses(prior, own)).any?
    end
    matches.one? ? matches.first : nil
  rescue StandardError => error
    log_failure('subject_match', error)
    nil
  end

  module FinderRedirect
    def find
      StudioThreadMatching.redirect(super)
    end
  end

  module ImapConversationPatch
    def process(mail, channel)
      @studio_existing_conversation = nil
      result = super
      begin
        unless @studio_existing_conversation.nil?
          saved = @inbox.messages.find_by(source_id: @processed_mail.message_id)
          StudioThreadMatching.event('incoming_saved', inbox_id: @inbox.id,
            message_id: saved.id, conversation_id: saved.conversation_id,
            joined_existing: @studio_existing_conversation) if saved
        end
      rescue StandardError => error
        StudioThreadMatching.log_failure('incoming_saved_telemetry', error)
      end
      result
    end

    private

    def find_or_create_conversation
      match = begin
        existing = find_conversation_by_in_reply_to || find_conversation_by_reference_ids
        StudioThreadMatching.redirect(existing) ||
          StudioThreadMatching.outbound_match(@inbound_mail, @inbox) ||
          StudioThreadMatching.source_match(@inbound_mail, @inbox) ||
          StudioThreadMatching.token_match(@inbound_mail, @inbox) ||
          StudioThreadMatching.subject_route(@inbound_mail, @inbox)
      rescue StandardError => error
        StudioThreadMatching.log_failure('imap_conversation', error)
        nil
      end
      @studio_existing_conversation = match.present?
      @conversation = match if match
      result = match || super
      if !match && (ids = StudioThreadMatching.unbound_candidate_ids(@inbound_mail)).any?
        begin
          ActiveRecord::Base.transaction(requires_new: true) do
            @conversation.update!(additional_attributes: @conversation.additional_attributes.merge(
              'studio_thread_candidate' => { 'reason' => 'unbound_outbound_reply', 'message_ids' => ids }
            ))
          end
        rescue StandardError => error
          StudioThreadMatching.log_failure('unbound_candidate', error)
        end
      end
      result
    end
  end

  module SenderPatch
    private

    def sanitized_message_attributes(source_id)
      attrs = super
      begin
        inbound = defined?(@inbound_mail) && @inbound_mail ? @inbound_mail : mail
        return attrs if is_a?(Imap::ImapMailbox) && !@studio_existing_conversation
        return attrs if @conversation.new_record?
        real_from = StudioThreadMatching.addresses(inbound.from)
        return attrs unless real_from.one?

        address = real_from.first
        reply_to = StudioThreadMatching.addresses(inbound.reply_to)
        return attrs if reply_to.any? && reply_to != real_from
        inbox = @conversation.inbox
        return attrs if @conversation.contact.email.to_s.casecmp?(address)
        contact = inbox.account.contacts.from_email(address)
        unless contact
          contact = ActiveRecord::Base.transaction(requires_new: true) do
            ContactInboxWithContactBuilder.new(
              inbox: inbox, source_id: address,
              contact_attributes: { name: address.split('@').first, email: address }
            ).perform.contact
          end
        end
        if contact
          attrs[:sender] = contact
          StudioThreadMatching.event('sender_corrected', conversation_id: @conversation.id, sender_id: contact.id)
        end
      rescue StandardError => error
        StudioThreadMatching.log_failure('sender', error)
      end
      attrs
    end
  end

  def self.install!
    begin
      finder = Mailbox::ConversationFinder
      namespace = Mailbox::ConversationFinderStrategies
      strategies = finder.const_get(:DEFAULT_STRATEGIES, false)
      expected = namespace::NewConversationStrategy
      base_strategy = namespace::BaseStrategy
      in_reply_to_strategy = namespace::InReplyToStrategy
      references_strategy = namespace::ReferencesStrategy
      imap_mailbox = Imap::ImapMailbox
      reply_mailbox = ReplyMailbox
      _email_channel_finder = EmailChannelFinder
      subject_strategy = const_get(:SubjectStrategy, false) if const_defined?(:SubjectStrategy, false)
    rescue NameError => error
      Rails.logger.warn("studio_thread_matching not installed: #{error.class.name}")
      return
    end
    return if subject_strategy && strategies.include?(subject_strategy)

    unless strategies.last == expected
      Rails.logger.warn('studio_thread_matching not installed: finder chain changed')
      return
    end

    unless subject_strategy
      strategy = Class.new(base_strategy) do
        def find
          channel = EmailChannelFinder.new(mail).perform
          StudioThreadMatching.outbound_match(mail, channel&.inbox) ||
            StudioThreadMatching.source_match(mail, channel&.inbox) ||
            StudioThreadMatching.token_match(mail, channel&.inbox) ||
            StudioThreadMatching.subject_route(mail, channel&.inbox)
        rescue StandardError => error
          StudioThreadMatching.log_failure('subject_strategy', error)
          nil
        end
      end
      const_set(:SubjectStrategy, strategy)
      subject_strategy = strategy
    end

    finder.send(:remove_const, :DEFAULT_STRATEGIES)
    finder.const_set(:DEFAULT_STRATEGIES,
                     (strategies[0...-1] + [subject_strategy, expected]).freeze)
    finder.prepend(FinderRedirect)
    imap_mailbox.prepend(ImapConversationPatch)
    imap_mailbox.prepend(SenderPatch)
    reply_mailbox.prepend(SenderPatch)
    Rails.logger.info('studio_thread_matching installed native_first=1 redirect=1 sender=1 subject_mode=' + subject_mode +
                      ' token_mode=' + (ENV['STUDIO_THREAD_TOKEN_MODE'] == 'join' ? 'join' : 'observe'))
  end
end

Rails.application.config.to_prepare { StudioThreadMatching.install! }
