defmodule KamalOps.Project do
  @moduledoc false

  # Keeps tasks resilient even if invoked from a subdirectory.
  @spec root!() :: String.t()
  def root! do
    Mix.Project.project_file()
    |> Path.dirname()
  end

  @spec default_app!() :: atom()
  def default_app! do
    Mix.Project.config()[:app] || raise Mix.Error, "Missing :app in Mix.Project.config()"
  end
end
