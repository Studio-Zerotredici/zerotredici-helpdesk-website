# Chatwoot v4.17.1 customer-template policy; install on rails and sidekiq together.
module StudioEmailAcknowledgement
  OWN_DOMAINS = %w[zerotredici.com zerotredici.app].freeze

  def self.addresses(values)
    Array.wrap(values).filter_map do |value|
      Mail::Address.new(value.to_s).address&.downcase
    rescue Mail::Field::ParseError, Mail::Field::IncompleteParseError
      nil
    end.uniq
  end

  def self.internal_sender?(message)
    sender = message.sender
    return false unless sender.respond_to?(:email)

    actual = addresses(sender.email)
    return false if actual.empty?
    return true if actual.any? { |address| OWN_DOMAINS.include?(address.split('@').last) }

    account = message.conversation.account
    own = addresses(account.users.pluck(:email))
    account.inboxes.where(channel_type: 'Channel::Email').includes(:channel).each do |inbox|
      own.concat(addresses([inbox.channel.email, inbox.channel.forward_to_email]))
    end
    (actual & own).any?
  end

  def self.existing_thread?(message)
    # A private outbound-binding note counts; automatic creation activities do not.
    # IDs order stored messages even when the timestamps are equal.
    message.conversation.messages.where('id < ?', message.id)
           .where.not(message_type: :activity).exists?
  end

  module TemplatePolicy
    private

    def should_send_greeting?
      if inbox.channel_type == 'Channel::Email'
        return false if StudioEmailAcknowledgement.internal_sender?(message)
        return false if StudioEmailAcknowledgement.existing_thread?(message)
      end
      super
    end

    def should_send_out_of_office_message?
      if inbox.channel_type == 'Channel::Email'
        return false if StudioEmailAcknowledgement.internal_sender?(message)
      end
      super
    end
  end

  def self.install!
    service = MessageTemplates::HookExecutionService
    required = %i[should_send_greeting? should_send_out_of_office_message?]
    unless required.all? { |name| service.private_method_defined?(name) }
      raise 'studio_email_ack incompatible Chatwoot template service'
    end
    return if service.ancestors.include?(TemplatePolicy)

    service.prepend(TemplatePolicy)
    Rails.logger.info('studio_email_ack installed internal_templates=0 existing_thread_greeting=0')
  end
end

Rails.application.config.to_prepare { StudioEmailAcknowledgement.install! }
