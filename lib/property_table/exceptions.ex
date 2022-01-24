defmodule PropertyTable.NoTableError do
  defexception [:message, :table]

  @impl Exception
  def exception(table) do
    msg = """
    #{inspect(table)} has not been started.

    Be sure to include the table in your supervision tree:

      {PropertyTable, [name: #{inspect(table)}]}

    Or manually start it with:

      PropertyTable.start_link(name: #{inspect(table)})
    """

    %__MODULE__{message: msg, table: table}
  end
end
