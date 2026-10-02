# frozen_string_literal: true

RSpec.describe WbAiAssistantUploadFix::BuilderExtension do
  let(:builder) { DiscourseAi::Completions::PromptMessagesBuilder.new }

  before { enable_current_plugin }

  def messages(&blk)
    blk.call(builder)
    builder.to_a
  end

  it "keeps uploads of the client's message" do
    result =
      messages { |b| b.push(type: :user, content: "вопрос", id: "client", upload_ids: [1, 2]) }
    expect(result.first[:content]).to eq(["вопрос", { upload_id: 1 }, { upload_id: 2 }])
  end

  it "drops uploads attached to the bot's own message" do
    result =
      messages do |b|
        b.push(type: :user, content: "вопрос", id: "client", upload_ids: [1])
        b.push(type: :model, content: "ответ", upload_ids: [1])
      end
    expect(result.first[:content]).to eq(["вопрос", { upload_id: 1 }])
    expect(result.last[:content]).to eq("ответ")
  end

  it "cleans upload parts passed inside the content array" do
    result =
      messages do |b|
        b.push(type: :user, content: "вопрос", id: "client")
        b.push(type: :model, content: ["ответ", { upload_id: 7 }])
      end
    expect(result.last[:content]).to eq("ответ")
  end

  it "leaves an empty text when the bot's message had nothing but uploads" do
    result =
      messages do |b|
        b.push(type: :user, content: "вопрос", id: "client")
        b.push(type: :model, content: [{ upload_id: 7 }])
      end
    expect(result.last[:content]).to eq("")
  end

  it "changes nothing when the plugin is disabled" do
    SiteSetting.wb_ai_assistant_upload_fix_enabled = false
    result =
      messages do |b|
        b.push(type: :user, content: "вопрос", id: "client")
        b.push(type: :model, content: "ответ", upload_ids: [5])
      end
    expect(result.last[:content]).to eq(["ответ", { upload_id: 5 }])
  end

  describe "сквозь настоящую переписку" do
    fab!(:llm_model) { Fabricate(:llm_model, vision_enabled: true) }
    fab!(:user)
    fab!(:bot_user, :user)
    fab!(:pm) do
      Fabricate(
        :private_message_topic,
        user: user,
        topic_allowed_users: [
          Fabricate.build(:topic_allowed_user, user: user),
          Fabricate.build(:topic_allowed_user, user: bot_user),
        ],
      )
    end
    fab!(:question) do
      Fabricate(:post, topic: pm, user: user, post_number: 1, raw: "Есть ли карта регистров?")
    end
    fab!(:answer) do
      Fabricate(
        :post,
        topic: pm,
        user: bot_user,
        post_number: 2,
        raw: "В приложенном паспорте карты нет",
      )
    end
    fab!(:follow_up) do
      Fabricate(:post, topic: pm, user: user, post_number: 3, raw: "А где искать?")
    end

    before do
      SiteSetting.authorized_extensions = "pdf|png|jpg"
      doc = Fabricate(:upload, original_filename: "pasport.pdf", extension: "pdf", user: user)
      # один и тот же файл привязан и к вопросу клиента, и к ответу бота — так Discourse
      # поступает, когда бот ставит в ответе ссылку upload:// на присланный файл
      UploadReference.create!(target: question, upload: doc)
      UploadReference.create!(target: answer, upload: doc)
    end

    def history
      DiscourseAi::Completions::PromptMessagesBuilder.messages_from_post(
        follow_up,
        max_posts: 10,
        bot_usernames: [bot_user.username],
        include_uploads: true,
        allowed_attachment_types: ["pdf"],
      )
    end

    def uploads_of(message)
      Array(message[:content]).select { |part| WbAiAssistantUploadFix.upload_part?(part) }
    end

    it "sends the file only in the client's message" do
      result = history
      model_messages = result.select { |m| m[:type] == :model }
      user_messages = result.select { |m| m[:type] == :user }

      expect(user_messages.sum { |m| uploads_of(m).size }).to eq(1)
      expect(model_messages.sum { |m| uploads_of(m).size }).to eq(0)
      expect(model_messages.map { |m| m[:content] }).to include("В приложенном паспорте карты нет")
    end

    it "without the plugin the file would go into the assistant message" do
      SiteSetting.wb_ai_assistant_upload_fix_enabled = false
      model_messages = history.select { |m| m[:type] == :model }
      expect(model_messages.sum { |m| uploads_of(m).size }).to eq(1)
    end
  end
end
