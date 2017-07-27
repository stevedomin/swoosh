defmodule Swoosh.Mailer do
  @moduledoc ~S"""
  Defines a mailer.

  A mailer is a wrapper around an adapter that makes it easy for you to swap the
  adapter without having to change your code.

  It is also responsible for doing some sanity checks before handing down the
  email to the adapter.

  When used, the mailer expects `:otp_app` as an option.
  The `:otp_app` should point to an OTP application that has the mailer
  configuration. For example, the mailer:

      defmodule Sample.Mailer do
        use Swoosh.Mailer, otp_app: :sample
      end

  Could be configured with:

      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.Sendgrid,
        api_key: "SG.x.x"

  Most of the configuration that goes into the config is specific to the adapter,
  so check the adapter's documentation for more information.

  Per module configuration is also supported:
  
      defmodule Sample.Mailer do
        use Swoosh.Mailer, otp_app: :sample,
          adapter: Swoosh.Adapters.Sendgrid,
          api_key: "SG.x.x"
      end

  System environment variables can be specified with `{:system, "ENV_VAR_NAME"}`:

      config :sample, Sample.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: "smtp.sendgrid.net"
        username: {:system, "SMTP_USERNAME"},
        password: {:system, "SMTP_PASSWORD"},
        tls: :always

  ## Examples

  Once configured you can use your mailer like this:

      # in an IEx console
      iex> email = new |> from("tony.stark@example.com") |> to("steve.rogers@example.com")
      %Swoosh.Email{from: {"", "tony.stark@example.com"}, ...}
      iex> Mailer.deliver(email)
      :ok

  You can also pass an extra config argument to `deliver/2` that will be merged
  with your Mailer's config:

      # in an IEx console
      iex> email = new |> from("tony.stark@example.com") |> to("steve.rogers@example.com")
      %Swoosh.Email{from: {"", "tony.stark@example.com"}, ...}
      iex> Mailer.deliver(email, domain: "jarvis.com")
      :ok
  """

  alias Swoosh.DeliveryError

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      {otp_app, module_config} = Swoosh.Mailer.parse_static_config(__MODULE__, opts)

      @otp_app otp_app
      @module_config module_config

      def deliver(email, config \\ [])
      def deliver(email, config) do
        Swoosh.Mailer.deliver(email, {@otp_app, __MODULE__, @module_config, config})
      end

      def deliver!(email, config \\ [])
      def deliver!(email, config) do
        case deliver(email, config) do
          {:ok, result} -> result
          {:error, reason} -> raise DeliveryError, reason: reason
          {:error, reason, payload} -> raise DeliveryError, reason: reason, payload: payload
        end
      end
    end
  end

  def deliver(%Swoosh.Email{from: nil}, _config) do
    {:error, :from_not_set}
  end
  def deliver(%Swoosh.Email{from: {_name, address}}, _config)
      when address in ["", nil] do
    {:error, :from_not_set}
  end
  def deliver(%Swoosh.Email{} = email, {otp_app, mailer, module_config, config}) do
    config =
      Application.get_env(otp_app, mailer, [])
      |> Keyword.merge(module_config)
      |> Keyword.merge(config)
      |> Swoosh.Mailer.parse_system_env

    adapter = Keyword.fetch!(config, :adapter)

    :ok = adapter.validate_config(config)
    adapter.deliver(email, config)
  end

  @doc """
  Parses the OTP configuration at compile time.
  """
  def parse_static_config(mailer, module_config) do
    otp_app = Keyword.fetch!(module_config, :otp_app)
    config = Application.get_env(otp_app, mailer, [])
    adapter = module_config[:adapter] || config[:adapter]

    unless adapter do
      raise ArgumentError, "missing :adapter configuration in " <>
                           "config #{inspect otp_app}, #{inspect mailer}"
    end

    {otp_app, module_config}
  end

  @doc """
  Parses the OTP configuration via system env vars.

  This function will transform all the {:system, "ENV_VAR"} tuples into their
  respective values grabbed from the process environment.
  """
  def parse_system_env(config) do
    Enum.map config, fn
      {key, {:system, env_var}} -> {key, System.get_env(env_var)}
      {key, value} -> {key, value}
    end
  end
end

