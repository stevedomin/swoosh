defmodule Swoosh.Adapters.Mua do
  @moduledoc """
  An adapter for sending emails using the SMTP protocol.

  > ### Dependencies {: .info}
  >
  > This adapter relies on the [Mua](https://github.com/ruslandoga/mua) and
  > [Mail](https://github.com/DockYard/elixir-mail) libraries.
  > Ensure they are added to your mix.exs file:

      # mix.exs
      def deps do
        [
         {:swoosh, "~> 1.3"},
         {:mua, "~> 0.2.0"},
         {:mail, "~> 0.3.0"},
         # if on OTP version below 25
         # {:castore, "~> 1.0"}
        ]
      end

  ## Configuration

  For direct email sending:

      # config/config.exs
      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.Mua

  For sending emails via a relay:

      # config/config.exs
      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.Mua,
        relay: "smtp.matrix.com",
        port: 587,
        auth: [username: "neo", password: "one"]

  Define your mailer module:

      # lib/sample/mailer.ex
      defmodule Sample.Mailer do
        use Swoosh.Mailer, otp_app: :sample
      end

  For supported configuration options, please see [`option()`](#t:option/0)

  ## Sending Email Directly

  When the relay option is omitted, the adapter sends emails directly to the recipients' mail servers.
  All recipients must be on the same host; otherwise, a `Swoosh.Adapters.Mua.MultihostError` is raised.

  Ensure your application can make outgoing connections to port 25 and
  that your sender domain has appropriate DNS records (e.g. SPF, DKIM).

  > #### Short-lived Connections {: .warning}
  >
  > Each `deliver/2` call results in a new connection to the recipient's email server.

  ## Sending Email via a Relay

  When the relay option is set, emails are sent through the specified relay, typically requiring authentication.
  For example, you can use your Gmail account with an app password.

  > #### Short-lived Connections {: .warning}
  >
  > Each `deliver/2` call results in a new connection to the relay. This is less efficient than `gen_smtp` which reuses long-lived connections.
  > Future versions of this adapter may address this issue.

  ## CA Certificates

  Starting with OTP 25, [system cacerts](https://www.erlang.org/doc/apps/public_key/public_key.html#cacerts_get/0)
  are used by default for the [cacerts](https://www.erlang.org/doc/apps/ssl/ssl.html#t:client_option_cert/0) option:

      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.Mua,
        # this happens by default
        ssl: [cacerts: :public_key.cacerts_get()]

  For OTP versions below 25, [`CAStore.file_path/0`](https://hexdocs.pm/castore/CAStore.html#file_path/0) is used for the [cacertfile](https://www.erlang.org/doc/apps/ssl/ssl.html#t:client_option_cert/0) option:

      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.Mua,
        # this happens by default
        ssl: [cacertfile: CAStore.file_path()]

  This means that for OTP versions below 25, you need to add [CAStore](https://hex.pm/packages/castore) to your project.

  You can also use custom certificates:

      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.Mua,
        ssl: [cacertfile: System.fetch_env!("MY_OWN_SMTP_CACERTFILE")]


  > #### CA Certfile Cache {: .warning}
  >
  > When using the `:cacertfile` option, certificates are decoded with each new connection.
  > To cache the decoded certificates, set `:persistent_term` for `:mua` to true:
  >
  >     config :mua, persistent_term: true

  ## Inline Attachments

  This adapter supports only regular attachments. Inline attachments will trigger a warning and be sent as regular files.

  """
  require Logger

  use Swoosh.Adapter, required_deps: [mail: Mail, mua: Mua]

  defmodule MultihostError do
    @moduledoc """
    Raised when no relay is used and recipients contain addresses across multiple hosts.

    For example:

        email =
          Swoosh.Email.new(
            to: {"Mua", "mua@github.com"},
            cc: [{"Swoosh", "mua@swoosh.github.com"}]
          )

        Swoosh.Adapters.Mua.deliver(email, _no_relay_config = [])

    Fields:

      - `:hosts` - the hosts for the recipients, `["github.com", "swoosh.github.com"]` in the example above

    """

    @type t :: %__MODULE__{hosts: [Mua.host()]}
    defexception [:hosts]

    def message(%__MODULE__{hosts: hosts}) do
      "expected all recipients to be on the same host, got: " <> Enum.join(hosts, ", ")
    end
  end

  @type option :: Mua.option() | {:relay, Mua.host()}

  @spec deliver(Swoosh.Email.t(), [option]) ::
          {:ok, Swoosh.Email.t()} | {:error, Mua.error() | MultihostError.t()}
  def deliver(email, config) do
    recipients = recipients(email)
    relay = Keyword.get(config, :relay)

    recipients_by_host =
      if relay do
        [{relay, recipients}]
      else
        recipients
        |> Enum.group_by(&host/1)
        |> Map.to_list()
      end

    # we don't perform MX lookup when relay is used
    config =
      if relay do
        Keyword.put_new(config, :mx, false)
      else
        config
      end

    case recipients_by_host do
      [{host, recipients}] ->
        sender = address(email.from)
        message = render(email)

        with {:ok, _receipt} <- Mua.easy_send(host, sender, recipients, message, config) do
          {:ok, email}
        end

      [_ | _] = multihost ->
        {:error, MultihostError.exception(hosts: :proplists.get_keys(multihost))}
    end
  end

  defp address({_, address}) when is_binary(address), do: address
  defp address(address) when is_binary(address), do: address

  defp host(address) do
    [_username, host] = String.split(address, "@")
    host
  end

  defp recipients(%Swoosh.Email{to: to, cc: cc, bcc: bcc}) do
    (List.wrap(to) ++ List.wrap(cc) ++ List.wrap(bcc))
    |> Enum.map(&address/1)
    |> Enum.uniq()
  end

  defp render(email) do
    Mail.build_multipart()
    |> put_headers(email)
    |> maybe(&Mail.put_from/2, email.from)
    |> maybe(&Mail.put_to/2, email.to)
    |> maybe(&Mail.put_cc/2, email.cc)
    |> maybe(&Mail.put_bcc/2, email.bcc)
    |> maybe(&Mail.put_subject/2, email.subject)
    |> maybe(&Mail.put_text/2, email.text_body)
    |> maybe(&Mail.put_html/2, email.html_body)
    |> maybe(&put_attachments/2, email.attachments)
    |> Mail.render()
  end

  defp maybe(mail, _fun, empty) when empty in [nil, [], %{}], do: mail
  defp maybe(mail, fun, value), do: fun.(mail, value)

  defp put_attachments(mail, attachments) do
    Enum.reduce(attachments, mail, fn attachment, mail ->
      %Swoosh.Attachment{filename: filename, content_type: content_type, type: type} = attachment

      if type == :inline do
        Logger.warning(
          "#{__MODULE__}: inline attachments are not supported, sending #{inspect(filename)} as a regular file"
        )
      end

      data = Swoosh.Attachment.get_content(attachment)
      Mail.put_attachment(mail, {filename, data}, headers: [content_type: content_type])
    end)
  end

  defp put_headers(mail, swoosh_email) do
    %{from: from, headers: headers} = swoosh_email

    utc_now = DateTime.utc_now()
    keys = headers |> Map.keys() |> Enum.map(&String.downcase/1)

    has_date? = "date" in keys
    has_message_id? = "message-id" in keys

    headers = if has_date?, do: headers, else: Map.put(headers, "Date", utc_now)

    headers =
      if has_message_id? do
        headers
      else
        address = address(from)
        host = host(address)
        Map.put(headers, "Message-ID", message_id(host, utc_now))
      end

    Enum.reduce(headers, mail, fn {key, value}, mail ->
      Mail.Message.put_header(mail, key, value)
    end)
  end

  defp message_id(host, utc_now) do
    date = Calendar.strftime(utc_now, "%Y%m%d")
    time = DateTime.to_time(utc_now)
    {seconds_after_midnight, _ms} = Time.to_seconds_after_midnight(time)

    disambiguator =
      Base.hex_encode32(
        <<
          seconds_after_midnight::17,
          :erlang.phash2({node(), self()}, 8_388_608)::23,
          :erlang.unique_integer()::24
        >>,
        case: :lower,
        padding: false
      )

    # e.g. <20241211.7aqmq6bb022i8@example.com>
    "<#{date}.#{disambiguator}@#{host}>"
  end
end
