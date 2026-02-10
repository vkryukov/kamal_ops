defmodule KamalOps.DeployConfig do
  @moduledoc """
  Reads Kamal `config/deploy*.yml` for ops tasks.

  We use `YamlElixir` so YAML anchors/aliases are resolved the same way Kamal sees them.
  """

  defstruct [:paths, :data]

  @type t :: %__MODULE__{paths: [String.t()], data: map()}

  @spec load!([String.t()]) :: t
  def load!(paths) when is_list(paths) and paths != [] do
    Enum.each(paths, fn path ->
      if not File.exists?(path) do
        raise Mix.Error, "Missing deploy config: #{path}"
      end
    end)

    data =
      paths
      |> Enum.map(&YamlElixir.read_from_file!/1)
      |> Enum.reduce(%{}, &deep_merge/2)

    %__MODULE__{paths: paths, data: data}
  end

  @spec scalar(t, [String.t()]) :: String.t() | nil
  def scalar(%__MODULE__{data: data}, path) when is_list(path) do
    case get_in(data, Enum.map(path, &Access.key(&1))) do
      value when is_binary(value) -> value
      value when is_number(value) -> to_string(value)
      value when is_boolean(value) -> to_string(value)
      _ -> nil
    end
  end

  @spec scalar!(t, [String.t()]) :: String.t()
  def scalar!(dc, path) do
    scalar(dc, path) || raise Mix.Error, "Missing #{Enum.join(path, ".")} in #{paths_label(dc)}"
  end

  @spec list(t, [String.t()]) :: [term()]
  def list(%__MODULE__{data: data}, path) when is_list(path) do
    case get_in(data, Enum.map(path, &Access.key(&1))) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  @spec service!(t) :: String.t()
  def service!(dc), do: scalar!(dc, ["service"])

  @spec primary_role(t) :: String.t()
  def primary_role(dc), do: scalar(dc, ["primary_role"]) || "web"

  @spec ssh_user(t) :: String.t() | nil
  def ssh_user(dc), do: scalar(dc, ["ssh", "user"])

  @spec accessories(t) :: map()
  def accessories(%__MODULE__{data: data}) do
    case get_in(data, [Access.key("accessories")]) do
      m when is_map(m) -> m
      _ -> %{}
    end
  end

  @spec accessory_names(t) :: [String.t()]
  def accessory_names(dc) do
    dc
    |> accessories()
    |> Map.keys()
    |> Enum.map(&to_string/1)
  end

  @spec accessory_service_name(t, String.t()) :: String.t()
  def accessory_service_name(dc, accessory) when is_binary(accessory) do
    scalar(dc, ["accessories", accessory, "service"]) || "#{service!(dc)}-#{accessory}"
  end

  @doc """
  Collect all secret keys referenced by deploy config.

  Includes global `env.secret` plus per-accessory `env.secret`.
  """
  @spec secret_keys(t) :: [String.t()]
  def secret_keys(dc) do
    global = list(dc, ["env", "secret"]) |> Enum.map(&to_string/1)

    accessory =
      dc
      |> accessory_names()
      |> Enum.flat_map(fn name -> list(dc, ["accessories", name, "env", "secret"]) end)
      |> Enum.map(&to_string/1)

    (global ++ accessory)
    |> Enum.uniq()
  end

  @doc """
  Returns hosts for a role using Kamal-supported `servers` forms.
  """
  @spec server_hosts(t, String.t()) :: [String.t()]
  def server_hosts(dc, role) when is_binary(role) do
    dc
    |> server_host_entries(role)
    |> Enum.map(& &1.host)
  end

  @doc """
  Returns `{host, tags}` entries for a role.

  Tags are used by some Kamal features (e.g. selecting accessory hosts by tag).
  """
  @spec server_host_entries(t, String.t()) :: [%{host: String.t(), tags: [String.t()]}]
  def server_host_entries(dc, role) when is_binary(role) do
    case servers(dc) do
      # servers: [host, ...] implies the `web` role.
      list when is_list(list) ->
        if role == "web" do
          normalize_host_entries(list)
        else
          []
        end

      map when is_map(map) ->
        case Map.get(map, role) do
          nil ->
            []

          hosts when is_list(hosts) ->
            normalize_host_entries(hosts)

          %{"hosts" => hosts} when is_list(hosts) ->
            normalize_host_entries(hosts)

          _ ->
            []
        end

      _ ->
        []
    end
  end

  @spec primary_server_host!(t, String.t() | nil) :: String.t()
  def primary_server_host!(dc, role \\ nil) do
    role = role || primary_role(dc)

    case server_hosts(dc, role) do
      [host | _] -> host
      [] -> raise Mix.Error, "Missing servers.#{role} hosts in #{paths_label(dc)}"
    end
  end

  @doc """
  Best-effort DB accessory selection.

  Kamal does not have a native concept of “the DB”; this is a convention.
  """
  @spec db_accessory_name!(t, String.t() | nil) :: String.t()
  def db_accessory_name!(dc, override \\ nil) do
    if is_binary(override) and override != "" do
      override
    else
      names = accessory_names(dc)

      cond do
        "db" in names ->
          "db"

        length(names) == 1 ->
          hd(names)

        true ->
          raise Mix.Error,
                "Couldn't infer DB accessory name from #{paths_label(dc)}. " <>
                  "Accessories: #{Enum.join(names, ", ")}. " <>
                  "Pass --db-accessory NAME."
      end
    end
  end

  @spec db_clear_value(t, String.t(), String.t()) :: String.t() | nil
  def db_clear_value(dc, accessory, key) when is_binary(accessory) and is_binary(key) do
    scalar(dc, ["accessories", accessory, "env", "clear", key])
  end

  @spec db_name!(t, String.t()) :: String.t()
  def db_name!(dc, accessory) do
    db_clear_value(dc, accessory, "POSTGRES_DB") ||
      raise(
        Mix.Error,
        "Missing accessories.#{accessory}.env.clear.POSTGRES_DB in #{paths_label(dc)}"
      )
  end

  @spec db_user!(t, String.t()) :: String.t()
  def db_user!(dc, accessory) do
    db_clear_value(dc, accessory, "POSTGRES_USER") ||
      raise(
        Mix.Error,
        "Missing accessories.#{accessory}.env.clear.POSTGRES_USER in #{paths_label(dc)}"
      )
  end

  @doc """
  Returns the SSH host that should contain the accessory’s Docker container.

  Supported (common) Kamal forms:

  - `accessories.<name>.host: HOST`
  - `accessories.<name>.hosts: [HOST, ...]`
  - `accessories.<name>.role: ROLE`
  - `accessories.<name>.roles: [ROLE, ...]`

  If none are present, we fall back to the primary role’s first host.
  """
  @spec accessory_ssh_host!(t, String.t(), String.t() | nil) :: String.t()
  def accessory_ssh_host!(dc, accessory, role_override \\ nil)
      when is_binary(accessory) do
    explicit =
      scalar(dc, ["accessories", accessory, "host"])
      |> blank_to_nil()

    explicit =
      explicit ||
        dc
        |> list(["accessories", accessory, "hosts"])
        |> normalize_hosts()
        |> List.first()

    if is_binary(explicit) do
      explicit
    else
      role = accessory_role(dc, accessory, role_override)
      desired_tags = accessory_desired_tags(dc, accessory)

      if desired_tags == [] do
        primary_server_host!(dc, role)
      else
        find_host_by_tags!(dc, role, desired_tags)
      end
    end
  end

  defp servers(%__MODULE__{data: data}), do: Map.get(data, "servers")

  defp accessory_role(dc, accessory, role_override) do
    scalar(dc, ["accessories", accessory, "role"]) ||
      dc
      |> list(["accessories", accessory, "roles"])
      |> Enum.map(&to_string/1)
      |> List.first() ||
      role_override ||
      primary_role(dc)
  end

  defp accessory_desired_tags(dc, accessory) do
    tag = scalar(dc, ["accessories", accessory, "tag"]) |> blank_to_nil()

    tags =
      dc
      |> list(["accessories", accessory, "tags"])
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if is_binary(tag) do
      [tag]
    else
      tags
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(v) when is_binary(v) do
    v = String.trim(v)
    if v == "", do: nil, else: v
  end

  defp normalize_hosts(hosts) when is_list(hosts) do
    hosts
    |> normalize_host_entries()
    |> Enum.map(& &1.host)
  end

  # Handle tag syntax like "1.2.3.4: tag" without breaking IPv6.
  defp normalize_host_entries(hosts) when is_list(hosts) do
    hosts
    |> Enum.flat_map(fn
      host when is_binary(host) ->
        {h, tags} = parse_host_string_with_tags(host)
        [%{host: h, tags: tags}]

      %{} = m when map_size(m) == 1 ->
        [{host, tags}] = Map.to_list(m)
        [%{host: to_string(host), tags: normalize_tags(tags)}]

      other ->
        [%{host: String.trim(to_string(other)), tags: []}]
    end)
    |> Enum.map(fn %{host: host} = e -> %{e | host: String.trim(host)} end)
    |> Enum.reject(fn %{host: host} -> host == "" end)
  end

  defp parse_host_string_with_tags(host) do
    host = String.trim(host)

    case String.split(host, ": ", parts: 2) do
      [h, tag] -> {h, [String.trim(tag)] |> Enum.reject(&(&1 == ""))}
      _ -> {host, []}
    end
  end

  defp normalize_tags(tags) when is_binary(tags) do
    tags = String.trim(tags)
    if tags == "", do: [], else: [tags]
  end

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_tags(_), do: []

  defp find_host_by_tags!(dc, role, desired_tags) do
    entries = server_host_entries(dc, role)

    case Enum.find(entries, fn %{tags: tags} -> Enum.any?(desired_tags, &(&1 in tags)) end) do
      nil ->
        raise Mix.Error,
              "No hosts in servers.#{role} match tags #{Enum.join(desired_tags, ", ")} in #{paths_label(dc)}"

      %{host: host} ->
        host
    end
  end

  defp deep_merge(new, old) when is_map(new) and is_map(old) do
    Map.merge(old, new, fn _k, old_v, new_v ->
      if is_map(old_v) and is_map(new_v) do
        deep_merge(new_v, old_v)
      else
        new_v
      end
    end)
  end

  defp deep_merge(new, _old), do: new

  defp paths_label(%__MODULE__{paths: paths}) do
    Enum.join(paths, ", ")
  end
end
