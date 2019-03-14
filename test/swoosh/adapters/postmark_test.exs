defmodule Swoosh.Adapters.PostmarkTest do
  use Swoosh.AdapterCase, async: true

  import Swoosh.Email
  alias Swoosh.Adapters.Postmark

  @success_response """
    {
      "ErrorCode": 0,
      "Message": "OK",
      "MessageID": "b7bc2f4a-e38e-4336-af7d-e6c392c2f817",
      "SubmittedAt": "2010-11-26T12:01:05.1794748-05:00",
      "To": "tony.stark@example.com"
    }
  """

  setup do
    bypass = Bypass.open
    config = [base_url: "http://localhost:#{bypass.port}",
              api_key: "jarvis"]

    valid_email =
      new()
      |> from("steve.rogers@example.com")
      |> to("tony.stark@example.com")
      |> subject("Hello, Avengers!")
      |> html_body("<h1>Hello</h1>")

    {:ok, bypass: bypass, valid_email: valid_email, config: config}
  end

  test "a sent email results in :ok", %{bypass: bypass, config: config, valid_email: email} do
    Bypass.expect bypass, fn conn ->
      conn = parse(conn)
      body_params = %{"Subject" => "Hello, Avengers!",
                      "To" => "tony.stark@example.com",
                      "From" => "steve.rogers@example.com",
                      "HtmlBody" => "<h1>Hello</h1>"}
      assert body_params == conn.body_params
      assert "/email" == conn.request_path
      assert "POST" == conn.method

      Plug.Conn.resp(conn, 200, @success_response)
    end

    assert Postmark.deliver(email, config) == {:ok, %{id: "b7bc2f4a-e38e-4336-af7d-e6c392c2f817"}}
  end

  test "delivery/1 with all fields returns :ok", %{bypass: bypass, config: config} do
    email =
      new()
      |> from({"T Stark", "tony.stark@example.com"})
      |> to("wasp.avengers@example.com")
      |> to({"Steve Rogers", "steve.rogers@example.com"})
      |> subject("Hello, Avengers!")
      |> html_body("<h1>Hello</h1>")
      |> cc({"Bruce Banner", "hulk.smash@example.com"})
      |> cc("thor.odinson@example.com")
      |> bcc({"Clinton Francis Barton", "hawk.eye@example.com"})
      |> bcc("beast.avengers@example.com")
      |> reply_to("iron.stark@example.com")
      |> html_body("<h1>Hello</h1>")
      |> text_body("Hello")

    Bypass.expect bypass, fn conn ->
      conn = parse(conn)
      body_params = %{"Subject" => "Hello, Avengers!",
                      "To" => "\"Steve Rogers\" <steve.rogers@example.com>, wasp.avengers@example.com",
                      "From" => "\"T Stark\" <tony.stark@example.com>",
                      "Cc" => "thor.odinson@example.com, \"Bruce Banner\" <hulk.smash@example.com>",
                      "Bcc" => "beast.avengers@example.com, \"Clinton Francis Barton\" <hawk.eye@example.com>",
                      "ReplyTo" => "iron.stark@example.com",
                      "TextBody" => "Hello",
                      "HtmlBody" => "<h1>Hello</h1>"}

      assert body_params == conn.body_params
      assert "/email" == conn.request_path
      assert "POST" == conn.method

      Plug.Conn.resp(conn, 200, @success_response)
    end

    assert Postmark.deliver(email, config) == {:ok, %{id: "b7bc2f4a-e38e-4336-af7d-e6c392c2f817"}}
  end

  test "delivery/1 with all fields for template id returns :ok", %{bypass: bypass, config: config} do
    config         = Keyword.merge(config, template: true)
    template_model = %{
      name:    "Tony Stark",
      company: "Avengers",
    }
    email =
      new()
      |> from({"T Stark", "tony.stark@example.com"})
      |> to("avengers@example.com")
      |> put_provider_option(:template_id,    1)
      |> put_provider_option(:template_model, template_model)

    Bypass.expect bypass, fn conn ->
      conn = parse(conn)
      body_params = %{
        "To"            => "avengers@example.com",
        "From"          => "\"T Stark\" <tony.stark@example.com>",
        "TemplateId"    => 1,
        "TemplateModel" => %{
          "company" => "Avengers",
          "name"    => "Tony Stark",
        }
      }

      assert body_params == conn.body_params
      assert "/email/withTemplate" == conn.request_path
      assert "POST" == conn.method

      Plug.Conn.resp(conn, 200, @success_response)
    end

    assert Postmark.deliver(email, config) == {:ok, %{id: "b7bc2f4a-e38e-4336-af7d-e6c392c2f817"}}
  end

  test "delivery/1 with all fields for template alias returns :ok", %{bypass: bypass, config: config} do
    config         = Keyword.merge(config, template: true)
    template_model = %{
      name:    "Tony Stark",
      company: "Avengers",
    }
    email =
      new()
      |> from({"T Stark", "tony.stark@example.com"})
      |> to("avengers@example.com")
      |> put_provider_option(:template_alias, "welcome")
      |> put_provider_option(:template_model, template_model)

    Bypass.expect bypass, fn conn ->
      conn = parse(conn)
      body_params = %{
        "To"            => "avengers@example.com",
        "From"          => "\"T Stark\" <tony.stark@example.com>",
        "TemplateAlias" => "welcome",
        "TemplateModel" => %{
          "company" => "Avengers",
          "name"    => "Tony Stark",
        }
      }

      assert body_params == conn.body_params
      assert "/email/withTemplate" == conn.request_path
      assert "POST" == conn.method

      Plug.Conn.resp(conn, 200, @success_response)
    end

    assert Postmark.deliver(email, config) == {:ok, %{id: "b7bc2f4a-e38e-4336-af7d-e6c392c2f817"}}
  end

  test "delivery/1 with custom headers returns :ok", %{bypass: bypass, config: config} do
    email =
      new()
      |> from({"T Stark", "tony.stark@example.com"})
      |> to("avengers@example.com")
      |> header("In-Reply-To", "<1234@example.com>")
      |> header("X-Accept-Language", "en")
      |> header("X-Mailer", "swoosh")

    Bypass.expect bypass, fn conn ->
      conn = parse(conn)
      body_params = %{"To" => "avengers@example.com",
                      "From" => "\"T Stark\" <tony.stark@example.com>",
                      "Headers" => [
                        %{"Name" => "In-Reply-To", "Value" => "<1234@example.com>"},
                        %{"Name" => "X-Accept-Language", "Value" => "en"},
                        %{"Name" => "X-Mailer", "Value" => "swoosh"}
                      ]}
      assert body_params == conn.body_params
      assert "/email" == conn.request_path
      assert "POST" == conn.method

      Plug.Conn.resp(conn, 200, @success_response)
    end

    assert Postmark.deliver(email, config) == {:ok, %{id: "b7bc2f4a-e38e-4336-af7d-e6c392c2f817"}}
  end

  test "delivery/1 with 4xx response", %{bypass: bypass, config: config, valid_email: email} do
    errors = "{\"errors\":[\"The provided authorization grant is invalid, expired, or revoked\"], \"message\":\"error\"}"

    Bypass.expect(bypass, &Plug.Conn.resp(&1, 422, errors))

    response = {:error, {422, %{"errors" => ["The provided authorization grant is invalid, expired, or revoked"], "message" => "error"}}}

    assert Postmark.deliver(email, config) == response
  end

  test "deliver/1 with 5xx response", %{bypass: bypass, valid_email: email, config: config} do
    errors = "{\"errors\":[\"The provided authorization grant is invalid, expired, or revoked\"], \"message\":\"error\"}"

    Bypass.expect(bypass, &Plug.Conn.resp(&1, 500, errors))

    response = {:error, {500, %{"errors" => ["The provided authorization grant is invalid, expired, or revoked"], "message" => "error"}}}

    assert Postmark.deliver(email, config) == response
  end

  test "validate_config/1 with valid config", %{config: config} do
    assert :ok = config |> Postmark.validate_config()
    assert :ok = config |> Keyword.put_new(:template, true) |> Postmark.validate_config()
  end

  test "validate_config/1 with invalid config" do
    assert_raise(
      ArgumentError,
      "expected [:api_key] to be set, got: []\n",
      fn ->
        Postmark.validate_config([])
      end
    )
  end
end
