defmodule PropertyTable.PersistFile do
  @moduledoc """
  This module contains methods to aid in writing the contents of a PropertyTable to a custom file format.

  The structure of the format is the following:

    ```
    +------------------------------+
    | HEADER 'PTABLE'              | Used to initially validate the file [0x00]
    +------------------------------+
    | FILE VERSION (uint8)         | Used to track the internal PropertyTable structure of the file [0x06]
    +------------------------------+
    | RESERVED (8 bits)            | Reserved [0x07]
    +------------------------------+
    | PAYLOAD SIZE (uint64)        | Length in bytes of the payload that follows [0x08]
    +------------------------------+
    | PAYLOAD BYTES (above size)   | Raw erlang term bytes of the table contents [0x10]
    +------------------------------+
    | PAYLOAD HASH (MD5 128 bits)  | MD5 Checksum of the bytes when they were written, ensures table integrity [0x10 + payload_size]
    +------------------------------+
    ```

  """

  # PTABLE header bytes
  @magic_file_header <<80, 84, 65, 66, 76, 69>>

  # Presently this version number is not used for anything, but if we want to change
  # the internal format of how we store the table, we can use this to version the layouts
  @file_version 1

  @spec decode_file(binary) :: {:error, :bad_checksum | :bad_file} | {:ok, binary}
  def decode_file(file_path) when is_binary(file_path) do
    file_content = File.read!(file_path)
    case decode_bitstring(file_content) do
      {:ok, decoded} -> validate_payload(decoded.payload, decoded.hash)
      error -> error
    end
  end

  @spec encode_binary(binary) :: binary()
  def encode_binary(table_content_binary) when is_binary(table_content_binary) do
    payload_length = byte_size(table_content_binary)
    payload_hash = :crypto.hash(:md5, table_content_binary)

    <<
      @magic_file_header::binary,
      @file_version::8,
      0x0::8, # Reserved byte
      payload_length::64,
      table_content_binary::binary,
      payload_hash::binary
    >>
  end

  defp validate_payload(payload, hash) do
    check_hash = :crypto.hash(:md5, payload)
    if hash != check_hash do
      {:error, :bad_checksum}
    else
      {:ok, payload}
    end
  end

  defp decode_bitstring(<<@magic_file_header, version::8, _reserved::8, payload_len::64, table_content::binary-size(payload_len), payload_hash::binary>>), do: {:ok, %{
    file_version: version,
    payload: table_content,
    hash: payload_hash
  }}
  defp decode_bitstring(_), do: {:error, :bad_file}
end
