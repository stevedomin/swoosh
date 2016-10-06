defmodule Swoosh.Integration.Adapters.PostmarkTest do
  use ExUnit.Case, async: true

  import Swoosh.Email

  @moduletag integration: true

  setup_all do
    config = [api_key: System.get_env("POSTMARK_API_KEY"), domain: System.get_env("POSTMARK_DOMAIN")]
    valid_email =
      new
      |> from({"Swoosh Postmark", "swoosh@#{config[:domain]}"})
      |> reply_to("swoosh+replyto@#{config[:domain]}")
      |> to("swoosh+to@#{config[:domain]}")
      |> cc("swoosh+cc@#{config[:domain]}")
      |> bcc("swoosh+bcc@#{config[:domain]}")

    {:ok, valid_email: valid_email, config: config}
  end

  test "simple deliver", %{valid_email: valid_email, config: config} do
    email =
      valid_email
      |> subject("Swoosh - Postmark integration test")
      |> text_body("This email was sent by the Swoosh library automation testing")
      |> html_body("<p>This email was sent by the Swoosh library automation testing</p>")

    assert_ok_response(email, config)
  end

  test "template deliver", %{valid_email: valid_email, config: config} do
    config = Keyword.put_new(config, :template, true)
    template_model = %{
      name: "Swoosh",
      action_url: "Postmark",
    }
    email =
      valid_email
      |> put_provider_option(:template_id, 968101)
      |> put_provider_option(:template_model, template_model)

    assert_ok_response(email, config)
  end

  defp assert_ok_response(email, config),
    do: assert {:ok, _response} = Swoosh.Adapters.Postmark.deliver(email, config)
end
