///|
pub fn read_nbt(path : String) -> Unit raise {
  let data_bytes = @fs.read_file_to_bytes(path)

  let buffer : @io.Buffer = @io.Buffer::from_bytes(data_bytes)
  // TODO: check this 
  // I don't know why this pub function exist, just quick fix warning
  ignore(buffer)
}
