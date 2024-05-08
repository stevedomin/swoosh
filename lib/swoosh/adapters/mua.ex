defmodule Swoosh.Adapters.Mua do
  @moduledoc """
  An adapter that sends email using the SMTP protocol.

  > ### Dependency {: .info}
  >
  > Underneath this adapter uses [Mua,](https://github.com/ruslandoga/mua) and
  > [Mail](https://github.com/DockYard/elixir-mail), and
  > [Castore](https://github.com/elixir-mint/castore) libraries,
  > add them to your mix.exs file.

  ## Example

      # mix.exs
      def deps do
        [
         {:swoosh, "~> 1.3"},
         {:mua, "~> 0.1.0"},
         {:mail, "~> 0.3.0"},
         {:castore, "~> 1.0"}
        ]
      end

      # config/config.exs for sending email directly
      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.Mua

      # config/config.exs for sending email via a relay
      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.Mua,
        relay: "smtp.matrix.com",
        port: 1025,
        auth: [username: "neo", password: "one"]

      # lib/sample/mailer.ex
      defmodule Sample.Mailer do
        use Swoosh.Mailer, otp_app: :sample
      end

  For supported configuration options, please see [`option()`](#t:option/0)

  ## Sending email directly

  When `relay` option is omitted, this adapter will send email directly to
  the receivers' host. All receivers must be on the same host, otherwise
  `Swoosh.Adapters.Mua.MultihostError` is raised.

  In this configuration, you need to ensure that your application can make
  outgoing connections to port 25 and that your sender domain has appropriate
  DNS records set, e.g. SPF or DKIM.

  > #### Short-lived connections {: .warning}
  >
  > Note that each `deliver` call results in a new connection to the receiver's
  > email server.

  ## Sending email via a relay

  When `relay` option is set, this adapter will send email through that relay.
  The relay would usually require authentication. For example, you can use your own
  GMail account with an app password.

  > #### Short-lived connections {: .warning}
  >
  > Note that each `deliver` call results in a new connection to the relay.
  > This is less efficient than `gen_smtp` which reuses the long-lived connection.
  > Further versions of this adapter might fix this if it ends up being a big problem ;)

  ## CA certificates

  By default [`CAStore.file_path/0`](https://hexdocs.pm/castore/CAStore.html#file_path/0) is used for
  [`:cacertfile`,](https://www.erlang.org/doc/man/ssl#type-client_cafile) but you can provide your
  own or use [the system ones](https://www.erlang.org/doc/man/public_key#cacerts_get-0) and supply them
  in as [`:cacerts`](https://www.erlang.org/doc/man/ssl#type-client_cacerts)

      :ok = :public_key.cacerts_load()
      [_ | _] = cacerts = :public_key.cacerts_get()

      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.Mua,
        transport_opts: [
          cacerts: cacerts
        ]

  Note that when using `:cacertfile` option, the certificates are decoded on each new connection.
  To cache the decoded certificates, set `:persistent_term` for `:mua` to true.

      config :mua, persistent_term: true

  """

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

    recipients_by_host =
      if relay = Keyword.get(config, :relay) do
        [{relay, recipients}]
      else
        recipients
        |> Enum.group_by(&recipient_host/1)
        |> Map.to_list()
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

  defp recipient_host(address) do
    [_username, host] = String.split(address, "@")
    host
  end

  defp recipients(%Swoosh.Email{to: to, cc: cc, bcc: bcc}) do
    (List.wrap(to) ++ List.wrap(cc) ++ List.wrap(bcc))
    |> Enum.map(&address/1)
    |> Enum.uniq()
  end

  def render(email) do
    Mail.build_multipart()
    |> maybe(&Mail.put_from/2, email.from)
    |> maybe(&Mail.put_to/2, email.to)
    |> maybe(&Mail.put_cc/2, email.cc)
    |> maybe(&Mail.put_bcc/2, email.bcc)
    |> maybe(&Mail.put_subject/2, email.subject)
    |> maybe(&Mail.put_text/2, email.text_body)
    |> maybe(&Mail.put_html/2, email.html_body)
    |> maybe(&put_headers/2, email.headers)
    |> maybe(&put_attachments/2, email.attachments)
    |> Mail.render()
  end

  defp maybe(mail, _fun, empty) when empty in [nil, [], %{}], do: mail
  defp maybe(mail, fun, value), do: fun.(mail, value)

  defp put_attachments(mail, attachments) do
    Enum.reduce(attachments, mail, fn attachment, mail ->
      %Swoosh.Attachment{filename: filename, content_type: content_type} = attachment
      data = Swoosh.Attachment.get_content(attachment)

      disposition =
        if attachment.type == :inline do
          [
            content_disposition: ["inline", filename: filename],
            content_id: "<#{attachment.cid || filename}>"
          ]
        else
          [content_disposition: ["attachment", filename: filename]]
        end

      Mail.put_attachment(mail, {filename, data},
        headers: [content_type: content_type] ++ disposition
      )
    end)
  end

  defp put_headers(mail, headers) do
    Enum.reduce(headers, mail, fn {key, value}, mail ->
      Mail.Message.put_header(mail, key, value)
    end)
  end
end
