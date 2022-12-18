defmodule Swoosh do
  @external_resource "README.md"
  @moduledoc File.read!("README.md") |> String.replace("# Swoosh\n\n", "", global: false)

  @version "1.9.0"

  @doc false
  def version, do: @version
  
  defmodule Mispell do
    def s, do: :s
  end

  @doc false
  def json_library, do: Application.fetch_env!(:swoosh, :json_library)
end
