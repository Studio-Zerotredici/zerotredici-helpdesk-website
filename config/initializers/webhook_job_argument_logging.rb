# WebhookJob arguments can include the outbound signing secret. ActiveJob's
# default job logger prints arguments, and Rails parameter filtering does not
# cover this log path. Keep the change scoped to this job class.
Rails.application.config.to_prepare do
  WebhookJob.log_arguments = false
end
