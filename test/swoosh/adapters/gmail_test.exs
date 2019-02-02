defmodule Swoosh.Adapters.GmailTest do
  use Swoosh.AdapterCase, async: true

  import Swoosh.Email
  alias Swoosh.Adapters.Gmail

  @success_response """
    {
      "id": "234jkasdfl",
      "threadId": "12312adfsx",
      "labelIds": ["SENT"]
    }
  """

  setup do
    bypass = Bypass.open()
    config = [base_url: "http://localhost:#{bypass.port}", access_token: "test_token"]

    valid_email =
      new()
      |> from("steve.rogers@example.com")
      |> to("tony.stark@example.com")
      |> subject("Hello, Avengers!")
      |> html_body("<h1>Hello</h1>")

    {:ok, bypass: bypass, valid_email: valid_email, config: config}
  end

  test "a sent email results in :ok", %{bypass: bypass, config: config, valid_email: email} do
    Bypass.expect(bypass, fn conn ->
      conn = parse(conn)
      boundary = get_boundary(conn.body_params)

      body_params =
        ~s"""
        To: "" <tony.stark@example.com>\r
        Subject: Hello, Avengers!\r
        Mime-Version: 1.0\r
        From: "" <steve.rogers@example.com>\r
        Content-Type: multipart/alternative; boundary="#{boundary}"\r
        \r
        --#{boundary}\r
        Content-Type: text/html\r
        Content-Transfer-Encoding: quoted-printable\r
        \r
        <h1>Hello</h1>\r
        --#{boundary}--\
        """
        |> prepare_body()

      assert body_params == conn.body_params
      assert "/users/me/messages/send" == conn.request_path
      assert "POST" == conn.method

      Plug.Conn.resp(conn, 200, @success_response)
    end)

    assert Gmail.deliver(email, config) ==
             {:ok, %{id: "234jkasdfl", thread_id: "12312adfsx", labels: ["SENT"]}}
  end

  test "delivery/1 with all fields returns :ok", %{
    bypass: bypass,
    config: config,
    valid_email: email
  } do
    email =
      new()
      |> from({"T Stark", "tony.stark@example.com"})
      |> to("wasp.avengers@example.com")
      |> to({"Steve Rogers", "steve.rogers@example.com"})
      |> subject("Hello, Avengers!")
      |> html_body("<h1>Hello</h1>")
      |> cc("thor.odinson@example.com")
      |> bcc({"Clinton Francis Barton", "hawk.eye@example.com"})
      |> bcc("beast.avengers@example.com")
      |> bcc({"Bruce Banner", "hulk.smash@example.com"})
      |> reply_to("iron.stark@example.com")
      |> html_body("<h1>Hello</h1>")
      |> text_body("Hello")

    Bypass.expect(bypass, fn conn ->
      conn = parse(conn)
      boundary = get_boundary(conn.body_params)

      body_params =
        ~s"""
        Bcc: "Bruce Banner" <hulk.smash@example.com>, "" <beast.avengers@example.com>, "Clinton Francis Barton" <hawk.eye@example.com>\r
        To: "Steve Rogers" <steve.rogers@example.com>, "" <wasp.avengers@example.com>\r
        Subject: Hello, Avengers!\r
        Reply-To: "" <iron.stark@example.com>\r
        Mime-Version: 1.0\r
        From: "T Stark" <tony.stark@example.com>\r
        Content-Type: multipart/alternative; boundary="#{boundary}"\r
        Cc: "" <thor.odinson@example.com>\r
        \r
        --#{boundary}\r
        Content-Type: text/plain\r
        Content-Transfer-Encoding: quoted-printable\r
        \r
        Hello\r
        \r
        --#{boundary}\r
        Content-Type: text/html\r
        Content-Transfer-Encoding: quoted-printable\r
        \r
        <h1>Hello</h1>\r
        --#{boundary}--\
        """
        |> prepare_body()

      assert body_params == conn.body_params
      assert "/users/me/messages/send" == conn.request_path
      assert "POST" == conn.method

      Plug.Conn.resp(conn, 200, @success_response)
    end)

    assert Gmail.deliver(email, config) ==
             {:ok, %{id: "234jkasdfl", thread_id: "12312adfsx", labels: ["SENT"]}}
  end

  test "deliver/1 without :access_token raises exception", %{config: config, valid_email: email} do
    assert_raise(
      ArgumentError,
      "access_token is required",
      fn ->
        config = Keyword.delete(config, :access_token)
        Gmail.deliver(email, config)
      end
    )
  end

  defp prepare_body(mail) do
    Map.put(%{}, "raw", Base.url_encode64(mail))
  end

  defp get_boundary(%{"raw" => raw} = _body) do
    raw
    |> Base.url_decode64!()
    |> Mail.Parsers.RFC2822.parse()
    |> Mail.Message.get_boundary()
  end
end
