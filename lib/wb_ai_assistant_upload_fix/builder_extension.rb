# frozen_string_literal: true

module ::WbAiAssistantUploadFix
  # Discourse AI складывает в сообщение истории вложения того поста, из которого оно собрано. Если
  # файл привязан к посту БОТА — а это случается, когда бот ставит в своём ответе ссылку
  # `upload://…` на присланный клиентом файл, — файл уезжает в сообщении с ролью assistant.
  # Responses API разрешает там только `output_text` и `refusal`, поэтому отвергает запрос целиком:
  # «Invalid value: 'input_file'. Supported values are: 'output_text' and 'refusal'» (HTTP 400).
  # Пост остаётся в истории, значит ломаются и все следующие ответы — диалог умирает насовсем.
  #
  # Убираем вложения из сообщений модели. Клиентские вложения остаются на месте, в своих
  # пользовательских сообщениях, а в тексте ответа бот файл и так называет словами. Побочная польза:
  # один и тот же файл больше не уезжает в запрос дважды.
  module BuilderExtension
    def push(**kwargs)
      return super(**kwargs) if !SiteSetting.wb_ai_assistant_upload_fix_enabled
      return super(**kwargs) if kwargs[:type] != :model

      dropped = Array(kwargs[:upload_ids]).size
      kwargs = kwargs.except(:upload_ids)

      if kwargs[:content].is_a?(Array)
        kept = kwargs[:content].reject { |part| WbAiAssistantUploadFix.upload_part?(part) }
        dropped += kwargs[:content].size - kept.size
        kwargs = kwargs.merge(content: collapse(kept))
      end

      if dropped > 0
        Rails.logger.info(
          "[#{WbAiAssistantUploadFix::PLUGIN_NAME}] вложений убрано из хода ассистента: #{dropped}",
        )
      end

      super(**kwargs)
    end

    private

    # без вложений остаётся обычный текст; пустое сообщение модели оставляем пустой строкой,
    # чтобы дальше по пути не появился ни массив из одного элемента, ни nil
    def collapse(parts)
      return "" if parts.empty?
      return parts.first if parts.size == 1 && parts.first.is_a?(String)

      parts
    end
  end
end
