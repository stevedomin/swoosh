defmodule Swoosh.Adapters.Mailjet do
  @moduledoc ~S"""
  An adapter that sends email using the Mailjet API.

  For reference: [Mailjet API docs](https://dev.mailjet.com/guides/#send-api-v3-1)

  ## Dependency

  Mailjet adapter requires `Plug` to work properly.

  ## Example

      # config/config.exs
      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.Mailjet,
        api_key: "my-api-key",
        secret: "my-secret-key"

      # lib/sample/mailer.ex
      defmodule Sample.Mailer do
        use Swoosh.Mailer, otp_app: :sample
      end
  """

  use Swoosh.Adapter,
    required_config: [:api_key, :secret],
    required_deps: [plug: Plug.Conn.Query]

  alias Swoosh.{Email, Attachment}

  @base_url "https://api.mailjet.com/v3.1"
  @api_endpoint "send"

  @impl true
  def deliver(%Email{} = email, config \\ []) do
    send_request(prepare_body(email), config)
  end

  def deliver_many(emails, config \\ []) when is_list(emails) do
    send_request(prepare_body(emails), config)
  end

  defp send_request(body, config) do
    headers = prepare_headers(config)
    url = [base_url(config), "/", @api_endpoint]

    case :hackney.post(url, headers, body, [:with_body]) do
      {:ok, 200, _headers, body} ->
        {:ok, parse_results(body)}

      {:ok, error_code, _headers, body} when error_code >= 400 ->
        {:error, {error_code, parse_results(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_results(%{"Messages" => results}) do
    results =
      Enum.map(results, fn
        %{"Status" => "success"} = result -> get_message_id(result)
        per_message_error -> per_message_error
      end)

    case results do
      [single] -> single
      multiple -> multiple
    end
  end

  defp parse_results(body) when is_binary(body) do
    body
    |> Swoosh.json_library().decode!
    |> parse_results()
  end

  defp parse_results(global_error) do
    global_error
  end

  defp get_message_id(%{"To" => [%{"MessageID" => message_id}]}) do
    %{id: message_id}
  end

  defp get_message_id(%{"To" => multiple_receivers}) do
    %{
      id:
        Enum.map(
          multiple_receivers,
          fn %{"MessageID" => message_id} ->
            message_id
          end
        )
    }
  end

  defp get_message_id(body) when is_binary(body) do
    body
    |> Swoosh.json_library().decode!
    |> get_message_id()
  end

  defp base_url(config), do: config[:base_url] || @base_url

  defp prepare_headers(config) do
    [
      {"User-Agent", "swoosh/#{Swoosh.version()}"},
      {"Authorization", "Basic #{auth(config)}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp auth(config), do: Base.encode64("#{config[:api_key]}:#{config[:secret]}")

  defp prepare_body(emails) do
    emails
    |> List.wrap()
    |> Enum.map(&prepare_message/1)
    |> wrap_messages()
    |> Swoosh.json_library().encode!()
  end

  defp prepare_message(email) do
    %{}
    |> prepare_from(email)
    |> prepare_to(email)
    |> prepare_subject(email)
    |> prepare_html(email)
    |> prepare_text(email)
    |> prepare_cc(email)
    |> prepare_bcc(email)
    |> prepare_reply_to(email)
    |> prepare_attachments(email)
    |> prepare_variables(email)
    |> prepare_template(email)
    |> prepare_custom_headers(email)
    |> prepare_custom_id(email)
  end

  defp wrap_messages(body) when is_list(body), do: %{Messages: body}

  defp prepare_custom_id(body, %{provider_options: %{custom_id: custom_id}}),
    do: Map.put(body, "CustomID", custom_id)

  defp prepare_custom_id(body, _options), do: body

  defp prepare_custom_headers(body, %{headers: headers}),
    do: Map.put(body, "Headers", headers)

  defp prepare_attachments(body, %{attachments: []}), do: body

  defp prepare_attachments(body, %{attachments: attachments}) do
    {normal_attachments, inline_attachments} =
      Enum.split_with(attachments, fn %{type: type} -> type == :attachment end)

    body
    |> Map.put(
      "Attachments",
      Enum.map(normal_attachments, &prepare_attachment/1)
    )
    |> Map.put(
      "InlinedAttachments",
      Enum.map(inline_attachments, &prepare_attachment/1)
    )
  end

  defp prepare_attachment(attachment) do
    %{
      "ContentType" => attachment.content_type,
      "Filename" => attachment.filename,
      "Base64Content" => Attachment.get_content(attachment, :base64)
    }
  end

  defp prepare_recipients(recipients),
    do: Enum.map(recipients, &prepare_recipient(&1))

  defp prepare_recipient({name, address}),
    do: %{"Name" => name, "Email" => address}

  defp prepare_from(body, %{from: from}),
    do: Map.put(body, "From", prepare_recipient(from))

  defp prepare_to(body, %{to: to}),
    do: Map.put(body, "To", prepare_recipients(to))

  defp prepare_reply_to(body, %{reply_to: nil}), do: body

  defp prepare_reply_to(body, %{reply_to: reply_to}),
    do: Map.put(body, "ReplyTo", prepare_recipient(reply_to))

  defp prepare_cc(body, %{cc: []}), do: body

  defp prepare_cc(body, %{cc: cc}),
    do: Map.put(body, "Cc", prepare_recipients(cc))

  defp prepare_bcc(body, %{bcc: []}), do: body

  defp prepare_bcc(body, %{bcc: bcc}),
    do: Map.put(body, "Bcc", prepare_recipients(bcc))

  defp prepare_subject(body, %{subject: subject}),
    do: Map.put(body, "Subject", subject)

  defp prepare_text(body, %{text_body: nil}), do: body

  defp prepare_text(body, %{text_body: text_body}),
    do: Map.put(body, "TextPart", text_body)

  defp prepare_html(body, %{html_body: nil}), do: body

  defp prepare_html(body, %{html_body: html_body}),
    do: Map.put(body, "HTMLPart", html_body)

  defp prepare_variables(body, %{provider_options: %{variables: variables}}) do
    Map.put(body, "Variables", variables)
  end

  defp prepare_variables(body, _email), do: body

  defp prepare_template(body, %{
         provider_options: %{template_id: template_id} = provider_options
       }) do
    body =
      body
      |> Map.put("TemplateID", template_id)
      |> Map.put("TemplateLanguage", true)
      |> Map.put(
        "TemplateErrorDeliver",
        !!provider_options[:template_error_deliver]
      )

    case provider_options[:template_error_reporting] do
      nil ->
        body

      {name, email} when is_binary(name) and is_binary(email) ->
        Map.put(body, "TemplateErrorReporting", %{
          "Email" => email,
          "Name" => name
        })

      email when is_binary(email) ->
        Map.put(body, "TemplateErrorReporting", %{
          "Email" => email,
          "Name" => ""
        })

      map when is_map(map) ->
        Map.put(body, "TemplateErrorReporting", map)
    end
  end

  defp prepare_template(body, _email), do: body
end
