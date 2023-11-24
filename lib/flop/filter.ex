defmodule Flop.Filter do
  @moduledoc """
  Defines a filter.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Flop.Schema

  alias Ecto.Changeset
  alias Flop.CustomTypes.Any
  alias Flop.CustomTypes.ExistingAtom
  alias Flop.CustomTypes.Like
  alias Flop.FieldInfo

  @typedoc """
  Represents filter query parameters.

  ### Fields

  - `field`: The field the filter is applied to. The allowed fields can be
    restricted by deriving `Flop.Schema` in your Ecto schema.
  - `op`: The filter operator.
  - `value`: The comparison value of the filter.
  """
  @type t :: %__MODULE__{
          field: atom | String.t(),
          op: op,
          value: any
        }

  @typedoc """
  Represents valid filter operators.

  | Operator        | Value               | WHERE clause                                            |
  | :-------------- | :------------------ | ------------------------------------------------------- |
  | `:==`           | `"Salicaceae"`      | `WHERE column = 'Salicaceae'`                           |
  | `:!=`           | `"Salicaceae"`      | `WHERE column != 'Salicaceae'`                          |
  | `:=~`           | `"cyth"`            | `WHERE column ILIKE '%cyth%'`                           |
  | `:empty`        | `true`              | `WHERE (column IS NULL) = true`                         |
  | `:empty`        | `false`             | `WHERE (column IS NULL) = false`                        |
  | `:not_empty`    | `true`              | `WHERE (column IS NOT NULL) = true`                     |
  | `:not_empty`    | `false`             | `WHERE (column IS NOT NULL) = false`                    |
  | `:<=`           | `10`                | `WHERE column <= 10`                                    |
  | `:<`            | `10`                | `WHERE column < 10`                                     |
  | `:>=`           | `10`                | `WHERE column >= 10`                                    |
  | `:>`            | `10`                | `WHERE column > 10`                                     |
  | `:in`           | `["pear", "plum"]`  | `WHERE column = ANY('pear', 'plum')`                    |
  | `:not_in`       | `["pear", "plum"]`  | `WHERE column = NOT IN('pear', 'plum')`                 |
  | `:contains`     | `"pear"`            | `WHERE 'pear' = ANY(column)`                            |
  | `:not_contains` | `"pear"`            | `WHERE 'pear' = NOT IN(column)`                         |
  | `:like`         | `"cyth"`            | `WHERE column LIKE '%cyth%'`                            |
  | `:not_like`     | `"cyth"`            | `WHERE column NOT LIKE '%cyth%'`                        |
  | `:like_and`     | `["Rubi", "Rosa"]`  | `WHERE column LIKE '%Rubi%' AND column LIKE '%Rosa%'`   |
  | `:like_and`     | `"Rubi Rosa"`       | `WHERE column LIKE '%Rubi%' AND column LIKE '%Rosa%'`   |
  | `:like_or`      | `["Rubi", "Rosa"]`  | `WHERE column LIKE '%Rubi%' OR column LIKE '%Rosa%'`    |
  | `:like_or`      | `"Rubi Rosa"`       | `WHERE column LIKE '%Rubi%' OR column LIKE '%Rosa%'`    |
  | `:ilike`        | `"cyth"`            | `WHERE column ILIKE '%cyth%'`                           |
  | `:not_ilike`    | `"cyth"`            | `WHERE column NOT ILIKE '%cyth%'`                       |
  | `:ilike_and`    | `["Rubi", "Rosa"]`  | `WHERE column ILIKE '%Rubi%' AND column ILIKE '%Rosa%'` |
  | `:ilike_and`    | `"Rubi Rosa"`       | `WHERE column ILIKE '%Rubi%' AND column ILIKE '%Rosa%'` |
  | `:ilike_or`     | `["Rubi", "Rosa"]`  | `WHERE column ILIKE '%Rubi%' OR column ILIKE '%Rosa%'`  |
  | `:ilike_or`     | `"Rubi Rosa"`       | `WHERE column ILIKE '%Rubi%' OR column ILIKE '%Rosa%'`  |

  The filter operators `:empty` and `:not_empty` will regard empty arrays as
  empty values if the field is known to be an array field.

  The filter operators `:ilike_and`, `:ilike_or`, `:like_and` and `:like_or`
  accept both strings and list of strings.

  - If the filter value is a string, it will be split at whitespace characters
    and the segments are combined with `and` or `or`.
  - If a list of strings is passed, the individual strings are not split, and
    the list items are combined with `and` or `or`.
  """
  @type op ::
          :==
          | :!=
          | :=~
          | :empty
          | :not_empty
          | :<=
          | :<
          | :>=
          | :>
          | :in
          | :not_in
          | :contains
          | :not_contains
          | :like
          | :not_like
          | :like_and
          | :like_or
          | :ilike
          | :not_ilike
          | :ilike_and
          | :ilike_or

  @operators [
    :==,
    :!=,
    :=~,
    :empty,
    :not_empty,
    :<=,
    :<,
    :>=,
    :>,
    :in,
    :not_in,
    :contains,
    :not_contains,
    :like,
    :not_like,
    :like_and,
    :like_or,
    :ilike,
    :not_ilike,
    :ilike_and,
    :ilike_or
  ]

  @primary_key false
  embedded_schema do
    field :field, ExistingAtom

    field :op, Ecto.Enum,
      default: :==,
      values: @operators

    field :value, Any
  end

  @doc false
  @spec changeset(__MODULE__.t(), map, keyword) :: Changeset.t()
  def changeset(filter, %{} = params, opts \\ []) do
    module = Keyword.get(opts, :for)

    changeset =
      filter
      |> cast(params, [:field, :op])
      |> validate_required([:field, :op])
      |> validate_filterable(module)

    if changeset.valid? do
      field = Changeset.fetch_field!(changeset, :field)
      op = Changeset.fetch_field!(changeset, :op)
      field_info = module && get_field_info(module, field)

      changeset
      |> validate_op(field_info, op)
      |> cast_value(field_info, op)
    else
      changeset
    end
  end

  defp cast_value(%Changeset{params: params} = changeset, field_info, op) do
    type = field_info |> value_type(op) |> expand_type()
    value = filter_empty_values(type, params["value"])

    case Ecto.Type.cast(type, value) do
      {:ok, cast_value} -> put_change(changeset, :value, cast_value)
      _ -> add_error(changeset, :value, "is invalid")
    end
  end

  defp filter_empty_values({:array, type}, value) when is_list(value) do
    for v <- value,
        v when not is_nil(v) <- [filter_empty_values(type, v)],
        do: v
  end

  defp filter_empty_values(_type, v) do
    if is_binary(v) and String.trim_leading(v) == "", do: nil, else: v
  end

  defp value_type(_, :empty), do: :boolean
  defp value_type(_, :not_empty), do: :boolean
  defp value_type(_, :ilike_and), do: Like
  defp value_type(_, :ilike_or), do: Like
  defp value_type(_, :like_and), do: Like
  defp value_type(_, :like_or), do: Like
  defp value_type(nil, _), do: Any
  defp value_type(%FieldInfo{ecto_type: type}, op), do: value_type(type, op)
  defp value_type(type, :in), do: {:array, type}
  defp value_type(type, :not_in), do: {:array, type}
  defp value_type({:array, type}, :contains), do: type
  defp value_type({:array, type}, :not_contains), do: type
  defp value_type(type, _), do: type

  defp expand_type({:from_schema, module, field}) do
    module.__schema__(:type, field)
  end

  defp expand_type({:ecto_enum, values}) do
    {:parameterized, Ecto.Enum, Ecto.Enum.init(values: values)}
  end

  defp expand_type(type), do: type

  @spec validate_filterable(Changeset.t(), module | nil) :: Changeset.t()
  defp validate_filterable(changeset, nil), do: changeset

  defp validate_filterable(changeset, module) when is_atom(module) do
    filterable_fields =
      module
      |> struct()
      |> filterable()

    validate_inclusion(changeset, :field, filterable_fields)
  end

  defp validate_op(changeset, nil, _), do: changeset

  defp validate_op(%Changeset{valid?: true} = changeset, field_info, op) do
    allowed_operators = allowed_operators(field_info)

    if op in allowed_operators do
      changeset
    else
      add_error(changeset, :op, "is invalid",
        allowed_operators: allowed_operators
      )
    end
  end

  @doc """
  Returns the allowed operators for the given schema module and field.

  For regular Ecto schema fields, the type is derived via schema reflection.

  If the given schema module derives `Flop.Schema`, the type of join and
  custom fields is determined via the `ecto_type` option. Compound files are
  always handled as string fields, minus unsupported operators.

  If the type cannot be determined or if the type is not a native Ecto type, a
  list with all operators is returned.

      iex> allowed_operators(Pet, :age)
      [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  """
  @spec allowed_operators(atom, atom) :: [op]
  def allowed_operators(module, field)
      when is_atom(module) and is_atom(field) do
    module
    |> get_field_info(field)
    |> allowed_operators()
  end

  defp get_field_info(module, field) do
    struct = struct(module)

    if Flop.Schema.impl_for(struct) != Flop.Schema.Any do
      Flop.Schema.field_info(struct, field)
    else
      module.__schema__(:type, field)
    end
  end

  @doc """
  Returns the allowed operators for the given Ecto type.

  If the given value is not a native Ecto type, a list with all operators is
  returned.

      iex> allowed_operators(:integer)
      [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  """
  @spec allowed_operators(FieldInfo.t() | Flop.Schema.ecto_type() | nil) :: [op]
  def allowed_operators(%FieldInfo{operators: operators})
      when is_list(operators) do
    operators
  end

  def allowed_operators(%FieldInfo{ecto_type: ecto_type}) do
    ecto_type |> expand_type() |> allowed_operators()
  end

  def allowed_operators(type) when type in [:decimal, :float, :id, :integer] do
    [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  end

  def allowed_operators(type) when type in [:binary_id, :string] do
    [
      :==,
      :!=,
      :=~,
      :empty,
      :not_empty,
      :<=,
      :<,
      :>=,
      :>,
      :in,
      :not_in,
      :like,
      :not_like,
      :like_and,
      :like_or,
      :ilike,
      :not_ilike,
      :ilike_and,
      :ilike_or
    ]
  end

  def allowed_operators(:boolean) do
    [:==, :!=, :=~, :empty, :not_empty]
  end

  def allowed_operators({:array, _}) do
    [
      :==,
      :!=,
      :empty,
      :not_empty,
      :<=,
      :<,
      :>=,
      :>,
      :in,
      :not_in,
      :contains,
      :not_contains
    ]
  end

  def allowed_operators({:map, _}) do
    [:==, :!=, :empty, :not_empty, :in, :not_in]
  end

  def allowed_operators(:map) do
    [:==, :!=, :empty, :not_empty, :in, :not_in]
  end

  def allowed_operators(type)
      when type in [
             :date,
             :time,
             :time_usec,
             :naive_datetime,
             :naive_datetime_usec,
             :utc_datetime,
             :utc_datetime_usec
           ] do
    [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  end

  def allowed_operators({:parameterized, Ecto.Enum, _}) do
    [
      :==,
      :!=,
      :empty,
      :not_empty,
      :<=,
      :<,
      :>=,
      :>,
      :in,
      :not_in
    ]
  end

  def allowed_operators(_) do
    [
      :==,
      :!=,
      :=~,
      :empty,
      :not_empty,
      :<=,
      :<,
      :>=,
      :>,
      :in,
      :not_in,
      :contains,
      :not_contains,
      :like,
      :not_like,
      :like_and,
      :like_or,
      :ilike,
      :not_ilike,
      :ilike_and,
      :ilike_or
    ]
  end

  @doc """
  Fetches the first filter for the given field and returns it in a tuple.

  ## Examples

  ### Flop.Filter struct

      iex> fetch([], :name)
      :error

      iex> fetch([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      {:ok, %Flop.Filter{field: :name, op: :==, value: "Joe"}}

      iex> fetch([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      :error

      iex> fetch(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      {:ok, %Flop.Filter{field: :name, op: :==, value: "Joe"}}

  ### Map with atom keys

      iex> fetch([%{field: :name, op: :==, value: "Joe"}], :name)
      {:ok, %{field: :name, op: :==, value: "Joe"}}

  ### Map with string keys

      iex> fetch([%{"field" => "name", "op" => "==", "value" => "Joe"}], :name)
      {:ok, %{"field" => "name", "op" => "==", "value" => "Joe"}}

  ### Indexed map

      iex> fetch(
      ...>   %{0 => %{field: "name", op: "==", value: "Joe"}},
      ...>   :name
      ...> )
      {:ok, %{field: "name", op: "==", value: "Joe"}}

      iex> fetch(
      ...>   %{"0" => %{"field" => "name", "op" => "==", "value" => "Joe"}},
      ...>   :name
      ...> )
      {:ok, %{"field" => "name", "op" => "==", "value" => "Joe"}}
  """
  @doc since: "0.19.0"
  @spec fetch([t()] | [map] | map, atom) :: {:ok, t() | map} | :error
  def fetch(filters, field) when is_atom(field) do
    filters
    |> get(field)
    |> case do
      %{} = filter -> {:ok, filter}
      nil -> :error
    end
  end

  @doc """
  Fetches the first filter value for the given field and returns it in a tuple.

  ## Examples

  ### Flop.Filter struct

      iex> fetch_value([], :name)
      :error

      iex> fetch_value([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      {:ok, "Joe"}

      iex> fetch_value([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      :error

      iex> fetch_value(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      {:ok, "Joe"}

  ### Map with atom keys

      iex> fetch_value([%{field: :name, op: :==, value: "Joe"}], :name)
      {:ok, "Joe"}

  ### Map with string keys

      iex> fetch_value(
      ...>   [%{"field" => "name", "op" => "==", "value" => "Joe"}],
      ...>   :name
      ...> )
      {:ok, "Joe"}

  ### Indexed map

      iex> fetch_value(
      ...>   %{0 => %{field: "name", op: "==", value: "Joe"}},
      ...>   :name
      ...> )
      {:ok, "Joe"}

      iex> fetch_value(
      ...>   %{"0" => %{"field" => "name", "op" => "==", "value" => "Joe"}},
      ...>   :name
      ...> )
      {:ok, "Joe"}
  """
  @doc since: "0.20.0"
  @spec fetch_value([t()] | [map] | map, atom) :: {:ok, any} | :error
  def fetch_value(filters, field) when is_atom(field) do
    filters
    |> get_value(field)
    |> case do
      nil -> :error
      value -> {:ok, value}
    end
  end

  @doc """
  Returns the first filter for the given field.

  ## Examples

  ### Flop.Filter struct

      iex> get([], :name)
      nil

      iex> get([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      %Flop.Filter{field: :name, op: :==, value: "Joe"}

      iex> get([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      nil

      iex> get(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      %Flop.Filter{field: :name, op: :==, value: "Joe"}

  ### Map with atom keys

      iex> get([%{field: :name, op: :==, value: "Joe"}], :name)
      %{field: :name, op: :==, value: "Joe"}

  ### Map with string keys

      iex> get([%{"field" => "name", "op" => "==", "value" => "Joe"}], :name)
      %{"field" => "name", "op" => "==", "value" => "Joe"}

      iex> get([%{"field" => :name, "op" => "==", "value" => "Joe"}], :name)
      %{"field" => :name, "op" => "==", "value" => "Joe"}

  ### Indexed map

      iex> get(
      ...>   %{0 => %{field: "name", op: "==", value: "Joe"}},
      ...>   :name
      ...> )
      %{field: "name", op: "==", value: "Joe"}

      iex> get(
      ...>   %{0 => %{field: :name, op: "==", value: "Joe"}},
      ...>   :name
      ...> )
      %{field: :name, op: "==", value: "Joe"}

      iex> get(
      ...>   %{"0" => %{"field" => "name", "op" => "==", "value" => "Joe"}},
      ...>   :name
      ...> )
      %{"field" => "name", "op" => "==", "value" => "Joe"}

      iex> get(
      ...>   %{"0" => %{"field" => :name, "op" => "==", "value" => "Joe"}},
      ...>   :name
      ...> )
      %{"field" => :name, "op" => "==", "value" => "Joe"}
  """
  @doc since: "0.19.0"
  @spec get([t()] | [map] | map, atom) :: t() | map | nil
  def get(filters, field) when is_atom(field) do
    field_str = to_string(field)

    filters
    |> Enum.find(&matches_field?(&1, field, field_str))
    |> case do
      {_, filter} -> filter
      filter -> filter
    end
  end

  @doc """
  Returns the first filter value for the given field.

  ## Examples

  ### Flop.Filter struct

      iex> get_value([], :name)
      nil

      iex> get_value([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      "Joe"

      iex> get_value([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      nil

      iex> get_value(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      "Joe"

      iex> get_value([%Flop.Filter{field: :ok, op: :empty, value: false}], :ok)
      false

  ### Map with atom keys

      iex> get_value([%{field: :name, op: :==, value: "Joe"}], :name)
      "Joe"

  ### Map with string keys

      iex> get_value(
      ...>   [%{"field" => "name", "op" => "==", "value" => "Joe"}],
      ...>   :name
      ...> )
      "Joe"

  ### Indexed map

      iex> get_value(
      ...>   %{0 => %{field: "name", op: "==", value: "Joe"}},
      ...>   :name
      ...> )
      "Joe"

      iex> get_value(
      ...>   %{"0" => %{"field" => "name", "op" => "==", "value" => "Joe"}},
      ...>   :name
      ...> )
      "Joe"
  """
  @doc since: "0.20.0"
  @spec get_value([t()] | [map] | map, atom) :: any | nil
  def get_value(filters, field) when is_atom(field) do
    filters
    |> get(field)
    |> case do
      nil -> nil
      %{value: value} -> value
      %{"value" => value} -> value
    end
  end

  @doc """
  Returns the all filters for the given field.

  ## Examples

  ### Flop.Filter struct

      iex> get_all([], :name)
      []

      iex> get_all([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      [%Flop.Filter{field: :name, op: :==, value: "Joe"}]

      iex> get_all([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      []

      iex> get_all(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      [
        %Flop.Filter{field: :name, op: :==, value: "Joe"},
        %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ]

  ### Map with atom keys

      iex> get_all(
      ...>   [
      ...>     %{field: :name, op: :==, value: "Joe"},
      ...>     %{field: :age, op: :>, value: 8},
      ...>     %{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      [
        %{field: :name, op: :==, value: "Joe"},
        %{field: :name, op: :==, value: "Jim"}
      ]

  ### Map with string keys

      iex> get_all(
      ...>   [
      ...>     %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     %{"field" => "age", "op" => ">", "value" => 8},
      ...>     %{"field" => "name", "op" => "==", "value" => "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      [
        %{"field" => "name", "op" => "==", "value" => "Joe"},
        %{"field" => "name", "op" => "==", "value" => "Jim"}
      ]

  ### Indexed map

      iex> get_all(
      ...>   %{
      ...>     0 => %{field: "name", op: "==", value: "Joe"},
      ...>     1 => %{field: "age", op: ">", value: 8},
      ...>     2 => %{field: "name", op: "==", value: "Jim"}
      ...>   },
      ...>   :name
      ...> )
      [
        %{field: "name", op: "==", value: "Joe"},
        %{field: "name", op: "==", value: "Jim"}
      ]

      iex> get_all(
      ...>   %{
      ...>     "0" => %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     "1" => %{"field" => "age", "op" => ">", "value" => 8},
      ...>     "2" => %{"field" => "name", "op" => "==", "value" => "Jim"}
      ...>   },
      ...>   :name
      ...> )
      [
        %{"field" => "name", "op" => "==", "value" => "Joe"},
        %{"field" => "name", "op" => "==", "value" => "Jim"}
      ]
  """
  @doc since: "0.19.0"
  @spec get_all([t()] | [map] | map, atom) :: [t()] | [map]
  def get_all(filters, field) when is_atom(field) do
    field_str = to_string(field)

    filters
    |> Enum.filter(&matches_field?(&1, field, field_str))
    |> Enum.map(fn
      {_, filter} -> filter
      filter -> filter
    end)
  end

  @doc """
  Deletes the filters for the given field from a list of filters.

  ## Examples

  ### Flop.Filter struct

      iex> delete(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8}
      ...>   ],
      ...>   :name
      ...> )
      [%Flop.Filter{field: :age, op: :>, value: 8}]

      iex> delete(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      [%Flop.Filter{field: :age, op: :>, value: 8}]

      iex> delete([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      [%Flop.Filter{field: :name, op: :==, value: "Joe"}]

  ### Map with atom keys

      iex> delete(
      ...>   [
      ...>     %{field: :name, op: :==, value: "Joe"},
      ...>     %{field: :age, op: :>, value: 8}
      ...>   ],
      ...>   :name
      ...> )
      [%{field: :age, op: :>, value: 8}]

  ### Map with string keys

      iex> delete(
      ...>   [
      ...>     %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     %{"field" => "age", "op" => ">", "value" => "8"}
      ...>   ],
      ...>   :name
      ...> )
      [%{"field" => "age", "op" => ">", "value" => "8"}]

  ### Indexed map

  Filters passed as an indexed map will be converted to a list, even if no
  matching filter exists.

      iex> delete(
      ...>   %{
      ...>     0 => %{field: "name", op: "==", value: "Joe"},
      ...>     1 => %{field: "age", op: ">", value: "8"}
      ...>   },
      ...>   :name
      ...> )
      [%{field: "age", op: ">", value: "8"}]

      iex> delete(
      ...>   %{
      ...>     "0" => %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     "1" => %{"field" => "age", "op" => ">", "value" => "8"}
      ...>   },
      ...>   :name
      ...> )
      [%{"field" => "age", "op" => ">", "value" => "8"}]
  """
  @doc since: "0.19.0"
  @spec delete([t] | [map] | map, atom) :: [t] | [map]
  def delete(filters, field) when is_atom(field) do
    field_str = to_string(field)

    filters
    |> indexed_map_to_list()
    |> Enum.reject(&matches_field?(&1, field, field_str))
  end

  @doc """
  Deletes the first filter in list of filters for the given field.

  ## Examples

  ### Flop.Filter struct

      iex> delete_first(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ]

      iex> delete_first([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      [%Flop.Filter{field: :name, op: :==, value: "Joe"}]

  ### Map with atom keys

      iex> delete_first(
      ...>   [
      ...>     %{field: :name, op: :==, value: "Joe"},
      ...>     %{field: :age, op: :>, value: 8},
      ...>     %{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      [
        %{field: :age, op: :>, value: 8},
        %{field: :name, op: :==, value: "Jim"}
      ]

  ### Map with string keys

      iex> delete_first(
      ...>   [
      ...>     %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     %{"field" => "age", "op" => ">", "value" => 8},
      ...>     %{"field" => "name", "op" => "==", "value" => "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      [
        %{"field" => "age", "op" => ">", "value" => 8},
        %{"field" => "name", "op" => "==", "value" => "Jim"}
      ]

      iex> delete_first(
      ...>   [
      ...>     %{"field" => :name, "op" => :==, "value" => "Joe"},
      ...>     %{"field" => :age, "op" => :>, "value" => 8},
      ...>     %{"field" => :name, "op" => :==, "value" => "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      [
        %{"field" => :age, "op" => :>, "value" => 8},
        %{"field" => :name, "op" => :==, "value" => "Jim"}
      ]

  ### Indexed map

  Filters passed as an indexed map will be converted to a list, even if no
  matching filter exists.

      iex> delete_first(
      ...>   %{
      ...>     0 => %{field: "name", op: "==", value: "Joe"},
      ...>     1 => %{field: "age", op: ">", value: 8},
      ...>     2 => %{field: "name", op: "==", value: "Jim"}
      ...>   },
      ...>   :name
      ...> )
      [
        %{field: "age", op: ">", value: 8},
        %{field: "name", op: "==", value: "Jim"}
      ]

      iex> delete_first(
      ...>   %{
      ...>     "0" => %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     "1" => %{"field" => "age", "op" => ">", "value" => 8},
      ...>     "2" => %{"field" => "name", "op" => "==", "value" => "Jim"}
      ...>   },
      ...>   :name
      ...> )
      [
        %{"field" => "age", "op" => ">", "value" => 8},
        %{"field" => "name", "op" => "==", "value" => "Jim"}
      ]
  """
  @doc since: "0.19.0"
  @spec delete_first([t] | [map] | map, atom) :: [t] | [map]
  def delete_first(filters, field) when is_list(filters) and is_atom(field) do
    delete_first_filter(filters, field, to_string(field))
  end

  def delete_first(%{} = filters, field) when is_atom(field) do
    filters |> indexed_map_to_list() |> delete_first(field)
  end

  defp delete_first_filter([%{field: field} | tail], field, _), do: tail
  defp delete_first_filter([%{field: field} | tail], _, field), do: tail
  defp delete_first_filter([%{"field" => field} | tail], field, _), do: tail
  defp delete_first_filter([%{"field" => field} | tail], _, field), do: tail

  defp delete_first_filter([%{} = filter | tail], field, field_str) do
    [filter | delete_first_filter(tail, field, field_str)]
  end

  defp delete_first_filter([], _, _), do: []

  @doc """
  Removes the filters for the given fields from a list of filters.

  ## Examples

  ### Flop.Filter struct

      iex> drop(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :color, op: :==, value: "blue"}
      ...>   ],
      ...>   [:name, :color]
      ...> )
      [%Flop.Filter{field: :age, op: :>, value: 8}]

      iex> drop(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :color, op: :==, value: "blue"},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   [:name, :species]
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :color, op: :==, value: "blue"}
      ]

  ### Map with atom keys

      iex> drop(
      ...>   [
      ...>     %{field: :name, op: :==, value: "Joe"},
      ...>     %{field: :age, op: :>, value: 8},
      ...>     %{field: :color, op: :==, value: "blue"}
      ...>   ],
      ...>   [:name, :color]
      ...> )
      [%{field: :age, op: :>, value: 8}]

  ### Map with string keys

      iex> drop(
      ...>   [
      ...>     %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     %{"field" => "age", "op" => ">", "value" => "8"},
      ...>     %{"field" => "color", "op" => "==", "value" => "blue"}
      ...>   ],
      ...>   [:name, :color]
      ...> )
      [%{"field" => "age", "op" => ">", "value" => "8"}]

      iex> drop(
      ...>   [
      ...>     %{"field" => :name, "op" => :==, "value" => "Joe"},
      ...>     %{"field" => :age, "op" => :>, "value" => "8"},
      ...>     %{"field" => :color, "op" => :==, "value" => "blue"}
      ...>   ],
      ...>   [:name, :color]
      ...> )
      [%{"field" => :age, "op" => :>, "value" => "8"}]


  ### Indexed map

  Filters passed as an indexed map will be converted to a list, even if no
  matching filter exists.

      iex> drop(
      ...>   %{
      ...>     0 => %{field: "name", op: "==", value: "Joe"},
      ...>     1 => %{field: "age", op: ">", value: "8"},
      ...>     2 => %{field: "color", op: "==", value: "blue"}
      ...>   },
      ...>   [:name, :color]
      ...> )
      [%{field: "age", op: ">", value: "8"}]

      iex> drop(
      ...>   %{
      ...>     "0" => %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     "1" => %{"field" => "age", "op" => ">", "value" => "8"},
      ...>     "2" => %{"field" => "color", "op" => "==", "value" => "blue"}
      ...>   },
      ...>   [:name, :color]
      ...> )
      [%{"field" => "age", "op" => ">", "value" => "8"}]
  """
  @doc since: "0.19.0"
  @spec drop([t] | [map] | map, [atom]) :: [t] | [map]
  def drop(filters, fields) when is_list(fields) do
    fields_str = Enum.map(fields, &to_string/1)

    filters
    |> indexed_map_to_list()
    |> Enum.reject(&contains_field?(&1, fields, fields_str))
  end

  @doc """
  Creates a list of filters from an enumerable.

  The default operator is `:==`.

      iex> filters = new(%{name: "George", age: 8})
      iex> Enum.sort(filters)
      [
        %Flop.Filter{field: :age, op: :==, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]

      iex> filters = new([name: "George", age: 8])
      iex> Enum.sort(filters)
      [
        %Flop.Filter{field: :age, op: :==, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]

  You can optionally pass a mapping from field names to operators as a map
  with atom keys.

      iex> filters = new(
      ...>   %{name: "George", age: 8},
      ...>   operators: %{name: :ilike_and}
      ...> )
      iex> Enum.sort(filters)
      [
        %Flop.Filter{field: :age, op: :==, value: 8},
        %Flop.Filter{field: :name, op: :ilike_and, value: "George"}
      ]

  You can also pass a map to rename fields.

      iex> filters = new(
      ...>   %{s: "George", age: 8},
      ...>   rename: %{s: :name}
      ...> )
      iex> Enum.sort(filters)
      [
        %Flop.Filter{field: :age, op: :==, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]

      iex> filters = new(
      ...>   %{s: "George", cat: true},
      ...>   rename: %{s: :name, cat: :dog}
      ...> )
      iex> Enum.sort(filters)
      [
        %Flop.Filter{field: :dog, op: :==, value: true},
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]

  If both a rename option and an operator are set for a field, the operator
  option needs to use the new field name.

      iex> new(
      ...>   %{n: "George"},
      ...>   rename: %{n: :name},
      ...>   operators: %{name: :ilike_or}
      ...> )
      [%Flop.Filter{field: :name, op: :ilike_or, value: "George"}]

  If the enumerable uses string keys as field names, the function attempts to
  convert them to existing atoms. If the atom does not exist, the filter is
  removed from the list.

      iex> new(%{"name" => "George", "age" => 8})
      [
        %Flop.Filter{field: :age, op: :==, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]

      iex> new(%{"name" => "George", "doesnotexist" => 8})
      [
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]

  Other key types are also removed.

      iex> new(%{"name" => "George", 2 => 8})
      [
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]
  """
  @doc since: "0.19.0"
  @spec new(Enumerable.t(), keyword) :: [t]
  def new(enum, opts \\ []) do
    operators = opts[:operators]
    renamings = opts[:rename]

    enum
    |> Enum.map(fn
      {field, value} when is_atom(field) or is_binary(field) ->
        if field = rename_field(field, renamings) do
          %Flop.Filter{
            field: field,
            op: op_from_mapping(field, operators),
            value: value
          }
        end

      {_, _} ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp op_from_mapping(_field, nil), do: :==

  defp op_from_mapping(field, %{} = operators) when is_atom(field) do
    Map.get(operators, field, :==)
  end

  defp op_from_mapping(field, %{} = operators) when is_binary(field) do
    atom_key = String.to_existing_atom(field)
    Map.get(operators, atom_key, :==)
  rescue
    ArgumentError -> :==
  end

  defp rename_field(field, nil) when is_atom(field), do: field

  defp rename_field(field, nil) when is_binary(field) do
    String.to_existing_atom(field)
  rescue
    ArgumentError -> nil
  end

  defp rename_field(field, %{} = renamings) when is_atom(field) do
    Map.get(renamings, field, field)
  end

  defp rename_field(field, %{} = renamings) when is_binary(field) do
    atom_key = String.to_existing_atom(field)
    Map.get(renamings, atom_key, field)
  rescue
    ArgumentError -> nil
  end

  @doc """
  Takes all filters for the given fields from a filter list.

  ## Examples

  ### Flop.Filter struct

      iex> take(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :color, op: :==, value: "blue"},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   [:name, :color]
      ...> )
      [
        %Flop.Filter{field: :name, op: :==, value: "Joe"},
        %Flop.Filter{field: :color, op: :==, value: "blue"},
        %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ]

  ### Map with atom keys

      iex> take(
      ...>   [
      ...>     %{field: :name, op: :==, value: "Joe"},
      ...>     %{field: :age, op: :>, value: 8},
      ...>     %{field: :color, op: :==, value: "blue"}
      ...>   ],
      ...>   [:name, :color]
      ...> )
      [
        %{field: :name, op: :==, value: "Joe"},
        %{field: :color, op: :==, value: "blue"}
      ]

  ### Map with string keys

      iex> take(
      ...>   [
      ...>     %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     %{"field" => "age", "op" => ">", "value" => 8},
      ...>     %{"field" => "color", "op" => "==", "value" => "blue"}
      ...>   ],
      ...>   [:name, :color]
      ...> )
      [
        %{"field" => "name", "op" => "==", "value" => "Joe"},
        %{"field" => "color", "op" => "==", "value" => "blue"}
      ]

  ### Indexed map

  Filters passed as an indexed map will be converted to a list, even if no
  matching filter exists.

      iex> take(
      ...>   %{
      ...>     0 => %{field: "name", op: "==", value: "Joe"},
      ...>     1 => %{field: "age", op: ">", value: 8},
      ...>     2 => %{field: "color", op: "==", value: "blue"}
      ...>   },
      ...>   [:name, :color]
      ...> )
      [
        %{field: "name", op: "==", value: "Joe"},
        %{field: "color", op: "==", value: "blue"}
      ]

      iex> take(
      ...>   %{
      ...>     "0" => %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     "1" => %{"field" => "age", "op" => ">", "value" => 8},
      ...>     "2" => %{"field" => "color", "op" => "==", "value" => "blue"}
      ...>   },
      ...>   [:name, :color]
      ...> )
      [
        %{"field" => "name", "op" => "==", "value" => "Joe"},
        %{"field" => "color", "op" => "==", "value" => "blue"}
      ]
  """
  @doc since: "0.19.0"
  @spec take([t] | [map] | map, [atom]) :: [t] | [map]
  def take(filters, fields) when is_list(fields) do
    fields_str = Enum.map(fields, &to_string/1)

    filters
    |> indexed_map_to_list()
    |> Enum.filter(&contains_field?(&1, fields, fields_str))
  end

  @doc """
  Returns the first filter for the given field and removes all other filters for
  the same field from the filter list.

  Returns a tuple with the first matching filter for `key` and the remaining
  filter list. If there is no filter for the field in the list, the default
  value is returned as the first tuple element.

  See also `Flop.Filter.pop_first/3`, `Flop.Filter.pop_value/3` and
  `Flop.Filter.pop_first_value/3`.

  ## Examples

  ### Flop.Filter struct

      iex> pop([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      {%Flop.Filter{field: :name, op: :==, value: "Joe"}, []}

      iex> pop([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      {nil, [%Flop.Filter{field: :name, op: :==, value: "Joe"}]}

      iex> pop(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   :age,
      ...>   %Flop.Filter{field: :age, op: :>, value: 8}
      ...> )
      {
        %Flop.Filter{field: :age, op: :>, value: 8},
        [%Flop.Filter{field: :name, op: :==, value: "Joe"}]
      }

      iex> pop(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"},
      ...>   ],
      ...>   :name
      ...> )
      {
        %Flop.Filter{field: :name, op: :==, value: "Joe"},
        [%Flop.Filter{field: :age, op: :>, value: 8}]
      }

  ### Map with atom keys

      iex> pop([%{field: :name, op: :==, value: "Joe"}], :name)
      {%{field: :name, op: :==, value: "Joe"}, []}

  ### Map with string keys

      iex> pop([%{"field" => "name", "op" => "==", "value" => "Joe"}], :name)
      {%{"field" => "name", "op" => "==", "value" => "Joe"}, []}

  ### Indexed map

  Filters passed as an indexed map will be converted to a list, even if no
  matching filter exists.

      iex> pop(
      ...>   %{
      ...>     0 => %{field: "name", op: "==", value: "Joe"},
      ...>     1 => %{field: "age", op: ">", value: "8"},
      ...>     2 => %{field: "name", op: "==", value: "Jim"},
      ...>   },
      ...>   :name
      ...> )
      {
        %{field: "name", op: "==", value: "Joe"},
        [%{field: "age", op: ">", value: "8"}]
      }

      iex> pop(
      ...>   %{
      ...>     0 => %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     1 => %{"field" => "age", "op" => ">", "value" => "8"},
      ...>     2 => %{"field" => "name", "op" => "==", "value" => "Jim"},
      ...>   },
      ...>   :name
      ...> )
      {
        %{"field" => "name", "op" => "==", "value" => "Joe"},
        [%{"field" => "age", "op" => ">", "value" => "8"}]
      }
  """
  @doc since: "0.19.0"
  @spec pop([t] | [map] | map, atom, any) :: {t | any, [t]} | {map | any, [map]}
  def pop(filters, field, default \\ nil) when is_atom(field) do
    case fetch(filters, field) do
      {:ok, filter} -> {filter, delete(filters, field)}
      :error -> {default, filters}
    end
  end

  @doc """
  Returns the first filter value for the given field and removes all other
  filters for the same field from the filter list.

  Returns a tuple with the value of the first matching filter for `key` and the
  remaining filter list. If there is no filter for the field in the list, the
  default value is returned as the first tuple element.

  See also `Flop.Filter.pop/3`, `Flop.Filter.pop_first/3` and
  `Flop.Filter.pop_first_value/3`

  ## Examples

  ### Flop.Filter struct

      iex> pop_value([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      {"Joe", []}

      iex> pop_value([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      {nil, [%Flop.Filter{field: :name, op: :==, value: "Joe"}]}

      iex> pop_value(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   :age,
      ...>   8
      ...> )
      {8, [%Flop.Filter{field: :name, op: :==, value: "Joe"}]}

      iex> pop_value(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"},
      ...>   ],
      ...>   :name
      ...> )
      {"Joe", [%Flop.Filter{field: :age, op: :>, value: 8}]}

  ### Map with atom keys

      iex> pop_value([%{field: :name, op: :==, value: "Joe"}], :name)
      {"Joe", []}

  ### Map with string keys

      iex> pop_value([%{"field" => "name", "op" => "==", "value" => "Joe"}], :name)
      {"Joe", []}

  ### Indexed map

  Filters passed as an indexed map will be converted to a list, even if no
  matching filter exists.

      iex> pop_value(
      ...>   %{
      ...>     0 => %{field: "name", op: "==", value: "Joe"},
      ...>     1 => %{field: "age", op: ">", value: "8"},
      ...>     2 => %{field: "name", op: "==", value: "Jim"},
      ...>   },
      ...>   :name
      ...> )
      {"Joe", [%{field: "age", op: ">", value: "8"}]}

      iex> pop_value(
      ...>   %{
      ...>     0 => %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     1 => %{"field" => "age", "op" => ">", "value" => "8"},
      ...>     2 => %{"field" => "name", "op" => "==", "value" => "Jim"},
      ...>   },
      ...>   :name
      ...> )
      {"Joe", [%{"field" => "age", "op" => ">", "value" => "8"}]}
  """
  @doc since: "0.20.0"
  @spec pop_value([t] | [map] | map, atom, any) ::
          {t | any, [t]} | {map | any, [map]}
  def pop_value(filters, field, default \\ nil) when is_atom(field) do
    case fetch_value(filters, field) do
      {:ok, value} -> {value, delete(filters, field)}
      :error -> {default, filters}
    end
  end

  @doc """
  Returns the first filter for the given field and a filter list with all
  remaining filters.

  Returns a tuple with the first matching filter for `key` and the
  remaining filter list. If there is no filter for the field in the list, the
  default value is returned as the first tuple element.

  See also `Flop.Filter.pop/3`, `Flop.Filter.pop_value/3` and
  `Flop.Filter.pop_first_value/3`.

  ## Examples

  ### Flop.Filter struct

      iex> pop_first([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      {%Flop.Filter{field: :name, op: :==, value: "Joe"}, []}

      iex> pop_first([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      {nil, [%Flop.Filter{field: :name, op: :==, value: "Joe"}]}

      iex> pop_first(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   :age,
      ...>   %Flop.Filter{field: :age, op: :>, value: 8}
      ...> )
      {
        %Flop.Filter{field: :age, op: :>, value: 8},
        [%Flop.Filter{field: :name, op: :==, value: "Joe"}]
      }

      iex> pop_first(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"},
      ...>   ],
      ...>   :name
      ...> )
      {
        %Flop.Filter{field: :name, op: :==, value: "Joe"},
        [
          %Flop.Filter{field: :age, op: :>, value: 8},
          %Flop.Filter{field: :name, op: :==, value: "Jim"}
        ]
      }

  ### Map with atom keys

      iex> pop_first([%{field: :name, op: :==, value: "Joe"}], :name)
      {%{field: :name, op: :==, value: "Joe"}, []}

  ### Map with string keys

      iex> pop_first(
      ...>   [%{"field" => "name", "op" => "==", "value" => "Joe"}],
      ...>   :name
      ...> )
      {%{"field" => "name", "op" => "==", "value" => "Joe"}, []}

  ### Indexed map

  Filters passed as an indexed map will be converted to a list, even if no
  matching filter exists.

      iex> pop_first(
      ...>   %{
      ...>     0 => %{field: "name", op: "==", value: "Joe"},
      ...>     1 => %{field: "age", op: ">", value: 8},
      ...>     2 => %{field: "name", op: "==", value: "Jim"},
      ...>   },
      ...>   :name
      ...> )
      {
        %{field: "name", op: "==", value: "Joe"},
        [
          %{field: "age", op: ">", value: 8},
          %{field: "name", op: "==", value: "Jim"}
        ]
      }

      iex> pop_first(
      ...>   %{
      ...>     "0" => %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     "1" => %{"field" => "age", "op" => ">", "value" => 8},
      ...>     "2" => %{"field" => "name", "op" => "==", "value" => "Jim"},
      ...>   },
      ...>   :name
      ...> )
      {
        %{"field" => "name", "op" => "==", "value" => "Joe"},
        [
          %{"field" => "age", "op" => ">", "value" => 8},
          %{"field" => "name", "op" => "==", "value" => "Jim"}
        ]
      }
  """
  @doc since: "0.19.0"
  @spec pop_first([t] | [map] | map, atom, any) ::
          {t | any, [t]} | {map | any, [map]}
  def pop_first(filters, field, default \\ nil) when is_atom(field) do
    case fetch(filters, field) do
      {:ok, value} -> {value, delete_first(filters, field)}
      :error -> {default, filters}
    end
  end

  @doc """
  Returns the first filter for the given field and a filter list with all
  remaining filters.

  Returns a tuple with the first matching filter value for `key` and the
  remaining filter list. If there is no filter for the field in the list, the
  default value is returned as the first tuple element.

  See also `Flop.Filter.pop/3`, `Flop.Filter.pop_value/3` and
  `Flop.Filter.pop_first/3`.

  ## Examples

  ### Flop.Filter struct

      iex> pop_first_value(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   :name
      ...> )
      {"Joe", []}

      iex> pop_first_value(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   :age
      ...> )
      {nil, [%Flop.Filter{field: :name, op: :==, value: "Joe"}]}

      iex> pop_first_value(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   :age,
      ...>   8
      ...> )
      {8, [%Flop.Filter{field: :name, op: :==, value: "Joe"}]}

      iex> pop_first_value(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"},
      ...>   ],
      ...>   :name
      ...> )
      {
        "Joe",
        [
          %Flop.Filter{field: :age, op: :>, value: 8},
          %Flop.Filter{field: :name, op: :==, value: "Jim"}
        ]
      }

  ### Map with atom keys

      iex> pop_first_value([%{field: :name, op: :==, value: "Joe"}], :name)
      {"Joe", []}

  ### Map with string keys

      iex> pop_first_value(
      ...>   [%{"field" => "name", "op" => "==", "value" => "Joe"}],
      ...>   :name
      ...> )
      {"Joe", []}

  ### Indexed map

  Filters passed as an indexed map will be converted to a list, even if no
  matching filter exists.

      iex> pop_first_value(
      ...>   %{
      ...>     0 => %{field: "name", op: "==", value: "Joe"},
      ...>     1 => %{field: "age", op: ">", value: 8},
      ...>     2 => %{field: "name", op: "==", value: "Jim"},
      ...>   },
      ...>   :name
      ...> )
      {
        "Joe",
        [
          %{field: "age", op: ">", value: 8},
          %{field: "name", op: "==", value: "Jim"}
        ]
      }

      iex> pop_first_value(
      ...>   %{
      ...>     "0" => %{"field" => "name", "op" => "==", "value" => "Joe"},
      ...>     "1" => %{"field" => "age", "op" => ">", "value" => 8},
      ...>     "2" => %{"field" => "name", "op" => "==", "value" => "Jim"},
      ...>   },
      ...>   :name
      ...> )
      {
        "Joe",
        [
          %{"field" => "age", "op" => ">", "value" => 8},
          %{"field" => "name", "op" => "==", "value" => "Jim"}
        ]
      }
  """
  @doc since: "0.20.0"
  @spec pop_first_value([t] | [map] | map, atom, any) ::
          {t | any, [t]} | {map | any, [map]}
  def pop_first_value(filters, field, default \\ nil) when is_atom(field) do
    case fetch_value(filters, field) do
      {:ok, value} -> {value, delete_first(filters, field)}
      :error -> {default, filters}
    end
  end

  @doc """
  Updates all filter values for the given field.

  If no filter for the given field is set, the filter list will be returned
  unchanged.

  ## Examples

  ### Flop.Filter struct

      iex> update_value(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>=, value: 30}
      ...>   ],
      ...>   :name,
      ...>   fn
      ...>     nil -> nil
      ...>     value -> String.downcase(value)
      ...>   end
      ...> )
      [
        %Flop.Filter{field: :name, op: :==, value: "joe"},
        %Flop.Filter{field: :age, op: :>=, value: 30}
      ]

      iex> update_value(
      ...>   [%Flop.Filter{field: :age, op: :==, value: 8}],
      ...>   :name,
      ...>   fn
      ...>     nil -> nil
      ...>     value -> String.downcase(value)
      ...>   end
      ...> )
      [%Flop.Filter{field: :age, op: :==, value: 8}]

  ### Map with atom keys

      iex> update_value(
      ...>   [%{field: :name, op: :==, value: "Joe"}],
      ...>   :name,
      ...>   fn
      ...>     nil -> nil
      ...>     value -> String.downcase(value)
      ...>   end
      ...> )
      [%{field: :name, op: :==, value: "joe"}]

      iex> update_value(
      ...>   [%{field: "name", op: "==", value: "Joe"}],
      ...>   :name,
      ...>   fn
      ...>     nil -> nil
      ...>     value -> String.downcase(value)
      ...>   end
      ...> )
      [%{field: "name", op: "==", value: "joe"}]

  ### Map with string keys

      iex> update_value(
      ...>   [%{"field" => :updated_at, "op" => :>=, "value" => "2023-10-01"}],
      ...>   :updated_at,
      ...>   fn
      ...>     nil -> nil
      ...>     value -> value <> " 00:00:00"
      ...>   end
      ...> )
      [%{"field" => :updated_at, "op" => :>=, "value" => "2023-10-01 00:00:00"}]

      iex> update_value(
      ...>   [%{"field" => "updated_at", "op" => ">=", "value" => "2023-10-01"}],
      ...>   :updated_at,
      ...>   fn
      ...>     nil -> nil
      ...>     value -> value <> " 00:00:00"
      ...>   end
      ...> )
      [%{"field" => "updated_at", "op" => ">=", "value" => "2023-10-01 00:00:00"}]

  ### Indexed map

      iex> update_value(
      ...>   %{0 => %{field: "name", op: "==", value: "Joe"}},
      ...>   :name,
      ...>   fn
      ...>     nil -> nil
      ...>     value -> String.downcase(value)
      ...>   end
      ...> )
      %{0 => %{field: "name", op: "==", value: "joe"}}

      iex> update_value(
      ...>   %{0 => %{field: :name, op: "==", value: "Joe"}},
      ...>   :name,
      ...>   fn
      ...>     nil -> nil
      ...>     value -> String.downcase(value)
      ...>   end
      ...> )
      %{0 => %{field: :name, op: "==", value: "joe"}}

      iex> update_value(
      ...>   %{"0" => %{"field" => "updated_at", "op" => ">=", "value" => "2023-10-01"}},
      ...>   :updated_at,
      ...>   fn
      ...>     nil -> nil
      ...>     value -> value <> " 00:00:00"
      ...>   end
      ...> )
      %{"0" => %{"field" => "updated_at", "op" => ">=", "value" => "2023-10-01 00:00:00"}}

      iex> update_value(
      ...>   %{"0" => %{"field" => :name, "op" => "==", "value" => "Joe"}},
      ...>   :name,
      ...>   fn
      ...>     nil -> nil
      ...>     value -> String.downcase(value)
      ...>   end
      ...> )
      %{"0" => %{"field" => :name, "op" => "==", "value" => "joe"}}
  """
  @doc since: "0.25.0"
  @spec update_value([t()] | [map] | map, atom, (any -> any)) :: t() | map | nil
  def update_value(filters, field, fun)
      when is_list(filters) and is_atom(field) and is_function(fun, 1) do
    field_str = to_string(field)

    Enum.map(filters, fn
      %{field: ^field, value: value} = filter ->
        %{filter | value: fun.(value)}

      %{field: ^field_str, value: value} = filter ->
        %{filter | value: fun.(value)}

      %{"field" => ^field, "value" => value} = filter ->
        %{filter | "value" => fun.(value)}

      %{"field" => ^field_str, "value" => value} = filter ->
        %{filter | "value" => fun.(value)}

      filter ->
        filter
    end)
  end

  def update_value(filters, field, fun)
      when is_map(filters) and is_atom(field) and is_function(fun, 1) do
    field_str = to_string(field)

    Enum.into(filters, %{}, fn
      {idx, %{field: ^field, value: value} = filter} ->
        {idx, %{filter | value: fun.(value)}}

      {idx, %{field: ^field_str, value: value} = filter} ->
        {idx, %{filter | value: fun.(value)}}

      {idx, %{"field" => ^field, "value" => value} = filter} ->
        {idx, %{filter | "value" => fun.(value)}}

      {idx, %{"field" => ^field_str, "value" => value} = filter} ->
        {idx, %{filter | "value" => fun.(value)}}

      filter ->
        filter
    end)
  end

  @doc """
  Adds the given filter to the filter list and removes all existing filters for
  the same field from the list.

  ## Examples

      iex> put(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   %Flop.Filter{field: :age, op: :>, value: 8}
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Joe"}
      ]

      iex> put(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   %Flop.Filter{field: :name, op: :==, value: "Jane"}
      ...> )
      [
        %Flop.Filter{field: :name, op: :==, value: "Jane"},
        %Flop.Filter{field: :age, op: :>, value: 8}
      ]
  """
  @doc since: "0.19.0"
  @spec put([t], t) :: [t]
  def put(filters, %Flop.Filter{field: field} = filter)
      when is_list(filters) and is_atom(field) do
    [filter | delete(filters, field)]
  end

  @doc """
  Adds the given filter value to the filter list and removes all existing
  filters for the same field from the list.

  ## Examples

      iex> put_value(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   :age,
      ...>   8
      ...> )
      [
        %Flop.Filter{field: :age, op: :==, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Joe"}
      ]

      iex> put_value(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   :age,
      ...>   8,
      ...>   :>=
      ...> )
      [
        %Flop.Filter{field: :age, op: :>=, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Joe"}
      ]

      iex> put_value(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name,
      ...>   "Jane"
      ...> )
      [
        %Flop.Filter{field: :name, op: :==, value: "Jane"},
        %Flop.Filter{field: :age, op: :>, value: 8}
      ]
  """
  @doc since: "0.20.0"
  @spec put_value([t], atom, any, op()) :: [t]
  def put_value(filters, field, value, op \\ :==)
      when is_list(filters) and is_atom(field) do
    [%Flop.Filter{field: field, op: op, value: value} | delete(filters, field)]
  end

  @doc """
  Adds the given filter to the filter list only if no filter for the field
  exists yet.

  ## Examples

      iex> put_new(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   %Flop.Filter{field: :age, op: :>, value: 8}
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Joe"}
      ]

      iex> put_new(
      ...>   [
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   %Flop.Filter{field: :name, op: :==, value: "Jane"}
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ]
  """
  @doc since: "0.19.0"
  @spec put_new([t], t) :: [t]
  def put_new(filters, %Flop.Filter{field: field} = filter)
      when is_list(filters) and is_atom(field) do
    case fetch(filters, field) do
      {:ok, _} -> filters
      :error -> [filter | filters]
    end
  end

  @doc """
  Adds the given filter value to the filter list only if no filter for the field
  exists yet.

  ## Examples

      iex> put_new_value(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   :age,
      ...>   8,
      ...>   :>
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Joe"}
      ]

      iex> put_new_value(
      ...>   [
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name,
      ...>   "Jane"
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ]
  """
  @doc since: "0.20.0"
  @spec put_new_value([t], atom, any, op()) :: [t]
  def put_new_value(filters, field, value, op \\ :==)
      when is_list(filters) and is_atom(field) do
    case fetch(filters, field) do
      {:ok, _} -> filters
      :error -> [%Flop.Filter{field: field, op: op, value: value} | filters]
    end
  end

  defp matches_field?(%{field: field}, field, _), do: true
  defp matches_field?(%{field: field}, _, field), do: true
  defp matches_field?(%{"field" => field}, field, _), do: true
  defp matches_field?(%{"field" => field}, _, field), do: true
  defp matches_field?({_, %{field: field}}, field, _), do: true
  defp matches_field?({_, %{field: field}}, _, field), do: true
  defp matches_field?({_, %{"field" => field}}, field, _), do: true
  defp matches_field?({_, %{"field" => field}}, _, field), do: true
  defp matches_field?(_, _, _), do: false

  defp contains_field?(filter, fields, fields_str) do
    case filter do
      %{field: field} when is_atom(field) -> field in fields
      %{field: field} when is_binary(field) -> field in fields_str
      %{"field" => field} when is_binary(field) -> field in fields_str
      %{"field" => field} when is_atom(field) -> field in fields
    end
  end

  defp indexed_map_to_list(filters) do
    Enum.map(filters, fn
      {_, filter} -> filter
      filter -> filter
    end)
  end
end
