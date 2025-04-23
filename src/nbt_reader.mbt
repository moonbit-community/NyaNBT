///|
pub fn read_nbt(path : String) -> Unit! {
  let data_bytes = @fs.read_file_to_bytes!(path)

  let buffer: @io.Buffer = @io.Buffer::from_bytes(data_bytes)
}
