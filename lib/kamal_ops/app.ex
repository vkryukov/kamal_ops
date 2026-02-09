defmodule KamalOps.App do
  @moduledoc false

  alias KamalOps.Project

  @spec allowed_apps() :: [atom()]
  def allowed_apps do
    [Project.default_app!(), Application.get_env(:kamal_ops, :app)]
    |> Enum.filter(&is_atom/1)
    |> Enum.uniq()
  end

  @spec parse_app!(String.t() | atom() | nil) :: atom()
  def parse_app!(nil), do: Project.default_app!()
  def parse_app!(app) when is_atom(app), do: app

  def parse_app!(app) when is_binary(app) do
    allowed = allowed_apps()

    case Enum.find(allowed, fn a -> Atom.to_string(a) == app end) do
      nil ->
        raise Mix.Error,
              "--app must match one of the allowed OTP apps: #{Enum.map_join(allowed, ", ", &Atom.to_string/1)}"

      a ->
        a
    end
  end
end
