defmodule Swoosh.Adapters.SMTP do
  @moduledoc ~S"""
  An adapter that sends email using the SMTP protocol.

  Underneath this adapter uses the
  [gen_stmp](https://github.com/Vagabond/gen_smtp) library.

  ## Example

      # config/config.exs
      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: "smtp.avengers.com",
        username: "tonystark",
        password: "ilovepepperpotts",
        tls: :always,
        auth: :always,
        dkim: [
          s: "default", d: "domain.com",
          private_key: {:pem_plain, File.read!("priv/keys/domain.private")}
        ]

      # lib/sample/mailer.ex
      defmodule Sample.Mailer do
        use Swoosh.Mailer, otp_app: :sample
      end
  """

  use Swoosh.Adapter, required_config: [:relay]

  alias Swoosh.Email

  def deliver(%Email{} = email, config) do
    mail_from = mail_from(email)
    recipients = all_recipients(email)
    body = encode_message(email, config)
    case :gen_smtp_client.send_blocking({mail_from, recipients, body}, config) do
      receipt when is_binary(receipt) -> {:ok, receipt}
      {:error, type, message} -> {:error, {type, message}}
      {:error, reason} -> {:error, reason}
    end
  end

  def mail_from(email) do
    email.headers["Sender"] || elem(email.from, 1)
  end

  defp all_recipients(email) do
    [email.to, email.cc, email.bcc]
    |> Enum.concat()
    |> Enum.map(fn {_name, address} -> address end)
    |> Enum.uniq
  end

  @doc false
  def encode_message(email, config) do
    {type, subtype, headers, parts} = prepare_message(email)
    options = prepare_options(config)
    :mimemail.encode({type, subtype, headers, [], parts}, options)
  end

  @doc false
  def prepare_message(email) do
    email
    |> prepare_headers()
    |> prepare_parts(email)
  end

  @doc false
  def prepare_options(config) do
    case config[:dkim] do
      nil -> []
      dkim -> [dkim: dkim]
    end
  end

  defp prepare_headers(%Email{} = email) do
    []
    |> prepare_additional_headers(email)
    |> prepare_mime_version
    |> prepare_reply_to(email)
    |> prepare_subject(email)
    |> prepare_cc(email)
    |> prepare_to(email)
    |> prepare_from(email)
  end

  defp prepare_subject(headers, %Email{subject: subject}), do: [{"Subject", subject} | headers]

  defp prepare_from(headers, %Email{from: from}), do: [{"From", prepare_recipient(from)} | headers]

  defp prepare_to(headers, %Email{to: to}), do: [{"To", "#{prepare_recipients(to)}"} | headers]

  defp prepare_cc(headers, %Email{cc: []}), do: headers
  defp prepare_cc(headers, %Email{cc: cc}), do: [{"Cc", "#{prepare_recipients(cc)}"} | headers]

  defp prepare_reply_to(headers, %Email{reply_to: nil}), do: headers
  defp prepare_reply_to(headers, %Email{reply_to: reply_to}), do: [{"Reply-To", prepare_recipient(reply_to)} | headers]

  defp prepare_mime_version(headers), do: [{"Mime-Version", "1.0"} | headers]

  defp prepare_additional_headers(headers, %Email{headers: additional_headers}) do
    Map.to_list(additional_headers) ++ headers
  end

  defp prepare_recipients(recipients) do
    recipients
    |> Enum.map(&prepare_recipient(&1))
    |> Enum.join(", ")
  end

  defp prepare_recipient({nil, address}), do: address
  defp prepare_recipient({"", address}), do: address
  defp prepare_recipient({name, address}), do: "#{name} <#{address}>"

  defp prepare_parts(headers, %Email{html_body: nil, text_body: text_body}) do
    headers = [{"Content-Type", "text/plain; charset=\"utf-8\""} | headers]
    {"text", "plain", headers, text_body}
  end
  defp prepare_parts(headers, %Email{html_body: html_body, text_body: nil}) do
    headers = [{"Content-Type", "text/html; charset=\"utf-8\""} | headers]
    {"text", "html", headers, html_body}
  end
  defp prepare_parts(headers, %Email{html_body: html_body, text_body: text_body}) do
    parts = [prepare_part(:plain, text_body), prepare_part(:html, html_body)]
    {"multipart", "alternative", headers, parts}
  end

  defp prepare_part(subtype, content) do
    subtype_string = to_string(subtype)
    {"text",
     subtype_string,
     [{"Content-Type", "text/#{subtype_string}; charset=\"utf-8\""},
      {"Content-Transfer-Encoding", "quoted-printable"}],
     [{"content-type-params", [{"charset", "utf-8"}]},
      {"disposition", "inline"},
      {"disposition-params",[]}],
     content}
  end
end
