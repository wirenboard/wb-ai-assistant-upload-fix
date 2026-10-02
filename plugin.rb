# frozen_string_literal: true

# name: wb-ai-assistant-upload-fix
# about: Не отдаёт вложения постов бота моделью как часть сообщения ассистента — иначе Responses API отвергает весь запрос и диалог ломается навсегда
# version: 1.0.0
# authors: Wiren Board
# url: https://github.com/wirenboard/wb-ai-assistant-upload-fix
# required_version: 2026.7.0

enabled_site_setting :wb_ai_assistant_upload_fix_enabled

module ::WbAiAssistantUploadFix
  PLUGIN_NAME = "wb-ai-assistant-upload-fix"

  def self.upload_part?(part)
    part.is_a?(Hash) && (part.key?(:upload_id) || part.key?("upload_id"))
  end
end

after_initialize do
  next unless defined?(DiscourseAi::Completions::PromptMessagesBuilder)

  require_relative "lib/wb_ai_assistant_upload_fix/builder_extension"

  DiscourseAi::Completions::PromptMessagesBuilder.prepend(WbAiAssistantUploadFix::BuilderExtension)
end
