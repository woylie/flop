defmodule Flop.TestAdapter do
  @moduledoc """
  Adapter that takes its fields from `adapter_opts` instead of an Ecto schema.

  This adapter defines its fields under `:declared_fields`.
  """

  @behaviour Flop.Adapter

  alias Flop.FieldInfo

  @query_half "Flop.TestAdapter implements the schema callbacks only"

  @impl Flop.Adapter
  def init_schema_opts(_opts, schema_opts, _caller, _struct),
    do: Map.new(schema_opts)

  @impl Flop.Adapter
  def fields(_struct, %{declared_fields: fields}) do
    for {name, type} <- fields do
      {name, %FieldInfo{ecto_type: type, extra: %{type: :normal, field: name}}}
    end
  end

  @impl Flop.Adapter
  def get_field(item, field, %FieldInfo{}), do: Map.get(item, field)

  @impl Flop.Adapter
  def primary_key(_module), do: []

  @impl Flop.Adapter
  def init_backend_opts(_opts, backend_opts, _caller), do: backend_opts

  @impl Flop.Adapter
  def apply_filter(_query, _filter, _module, _opts), do: raise(@query_half)

  @impl Flop.Adapter
  def apply_order_by(_query, _directions, _opts), do: raise(@query_half)

  @impl Flop.Adapter
  def apply_limit_offset(_query, _limit, _offset, _opts), do: raise(@query_half)

  @impl Flop.Adapter
  def apply_page_page_size(_query, _page, _page_size, _opts),
    do: raise(@query_half)

  @impl Flop.Adapter
  def apply_cursor(_query, _cursor_fields, _opts), do: raise(@query_half)

  @impl Flop.Adapter
  def count(_query, _opts), do: raise(@query_half)

  @impl Flop.Adapter
  def list(_query, _opts), do: raise(@query_half)
end
