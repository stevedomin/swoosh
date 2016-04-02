defmodule Swoosh.Adapters.SMTPTest do
  use AdapterCase, async: true

  import Swoosh.Email
  alias Swoosh.Adapters.SMTP

  setup_all do
    valid_email =
      new
      |> from("tony@stark.com")
      |> to("steve@rogers.com")
      |> subject("Hello, Avengers!")
      |> html_body("<h1>Hello</h1>")
      |> text_body("Hello")

    {:ok, valid_email: valid_email}
  end

  test "simple email", %{valid_email: email} do
    email = email |> html_body(nil)
    assert SMTP.prepare_message(email) ==
     {"text", "plain",
      [{"Content-Type", "text/plain; charset=\"utf-8\""},
        {"From", "tony@stark.com"},
        {"To", "steve@rogers.com"},
        {"Subject", "Hello, Avengers!"},
        {"Mime-Version", "1.0"}],
      "Hello"}
  end

  test "simple email with all basic fields", %{valid_email: email} do
    email =
      email
      |> html_body(nil)
      |> to({"Janet Pym", "wasp@avengers.com"})
      |> cc({"Bruce Banner", "hulk@smash.com"})
      |> cc("thor@odinson.com")
      |> bcc({"Clinton Francis Barton", "hawk@eye.com"})
      |> bcc("beast@avengers.com")
      |> reply_to("black@widow.com")

    assert SMTP.prepare_message(email) ==
    {"text", "plain",
      [{"Content-Type", "text/plain; charset=\"utf-8\""},
        {"From", "tony@stark.com"},
        {"To", "Janet Pym <wasp@avengers.com>, steve@rogers.com"},
        {"Cc", "thor@odinson.com, Bruce Banner <hulk@smash.com>"},
        {"Subject", "Hello, Avengers!"},
        {"Reply-To", "black@widow.com"},
        {"Mime-Version", "1.0"}],
      "Hello"}
  end

  test "simple email with multiple recipients", %{valid_email: email} do
    email = email |> html_body(nil) |> to({"Bruce Banner", "bruce@banner.com"})
    assert SMTP.prepare_message(email) ==
    {"text", "plain",
      [{"Content-Type", "text/plain; charset=\"utf-8\""},
        {"From", "tony@stark.com"},
        {"To", "Bruce Banner <bruce@banner.com>, steve@rogers.com"},
        {"Subject", "Hello, Avengers!"},
        {"Mime-Version", "1.0"}],
      "Hello"}
  end

  test "simple email with multiple cc recipients", %{valid_email: email} do
    email =
    email
    |> html_body(nil)
    |> to({"Bruce Banner", "bruce@banner.com"})
    |> cc("thor@odinson.com")

    assert SMTP.prepare_message(email) ==
      {"text", "plain",
       [{"Content-Type", "text/plain; charset=\"utf-8\""},
        {"From", "tony@stark.com"},
        {"To", "Bruce Banner <bruce@banner.com>, steve@rogers.com"},
        {"Cc", "thor@odinson.com"},
        {"Subject", "Hello, Avengers!"},
        {"Mime-Version", "1.0"}],
       "Hello"}
  end

  test "simple html email", %{valid_email: email} do
    email = email |> text_body(nil)
    assert SMTP.prepare_message(email) ==
      {"text", "html",
       [{"Content-Type", "text/html; charset=\"utf-8\""},
        {"From", "tony@stark.com"},
        {"To", "steve@rogers.com"},
        {"Subject", "Hello, Avengers!"},
        {"Mime-Version", "1.0"}],
      "<h1>Hello</h1>"}
  end

  test "multipart/alternative email", %{valid_email: email} do
    assert SMTP.prepare_message(email) ==
      {"multipart", "alternative",
       [{"From", "tony@stark.com"},
        {"To", "steve@rogers.com"},
        {"Subject", "Hello, Avengers!"},
        {"Mime-Version", "1.0"}],
       [{"text", "plain",
         [{"Content-Type", "text/plain; charset=\"utf-8\""},
          {"Content-Transfer-Encoding", "quoted-printable"}],
         [{"content-type-params", [{"charset", "utf-8"}]},
          {"disposition", "inline"},
          {"disposition-params", []}],
         "Hello"},
        {"text", "html",
         [{"Content-Type", "text/html; charset=\"utf-8\""},
          {"Content-Transfer-Encoding", "quoted-printable"}],
         [{"content-type-params", [{"charset", "utf-8"}]},
          {"disposition", "inline"},
          {"disposition-params", []}],
        "<h1>Hello</h1>"}]}
  end
end
