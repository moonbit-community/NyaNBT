///|
test "gzip reader preserves successful digest writes" {
  let compressed = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03\xcb\x48\xcd\xc9\xc9\x07\x00\x86\xa6\x10\x36\x05\x00\x00\x00"
  let input : &@flate.Reader = @io.Buffer::from_bytes(compressed)
  let (reader, init_error) = Reader::new(input)
  assert_true(init_error is None)
  let decoded = @io.Slice::new(Array::make(5, b'\x00'))
  let (read_count, _read_error) = @io.Reader::read(reader, decoded)
  assert_eq(read_count, 5)
  assert_eq(decoded.to_bytes(), b"hello")
}
