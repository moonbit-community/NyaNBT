///|
test "gzip reader preserves successful digest writes" {
  let compressed = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03\xcb\x48\xcd\xc9\xc9\x07\x00\x86\xa6\x10\x36\x05\x00\x00\x00"
  let input : &@flate.Reader = @io.Buffer::from_bytes(compressed)
  let (reader, init_error) = Reader::new(input)
  assert_true(init_error is None)
  let decoded = @io.Slice::new(Array::make(5, b'\x00'))
  let (read_count, read_error) = @io.Reader::read(reader, decoded)
  assert_eq(read_count, 5)
  assert_eq(decoded.to_bytes(), b"hello")
  assert_eq(read_error, Some(@io.eof))
  assert_eq(@io.Closer::close(reader), None)
}

///|
test "gzip reader rejects corrupt and truncated trailers" {
  let compressed = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03\xcb\x48\xcd\xc9\xc9\x07\x00\x86\xa6\x10\x36\x05\x00\x00\x00"
  let checksum = compressed.to_array()
  checksum[17] = b'\x00'
  let size = compressed.to_array()
  size[21] = b'\x06'
  let cases = [
    (Bytes::from_array(checksum), err_checksum),
    (Bytes::from_array(size), IOError("gzip: invalid file size")),
    (compressed[:compressed.length() - 1].to_owned(), @io.err_unexpected_eof),
  ]
  for (data, expected) in cases {
    let input : &@flate.Reader = @io.Buffer::from_bytes(data)
    let (reader, init_error) = Reader::new(input)
    assert_eq(init_error, None)
    let (decoded, read_error) = @io.read_all(reader)
    assert_eq(decoded.to_bytes(), b"hello")
    assert_eq(read_error, Some(expected))
    assert_eq(@io.Closer::close(reader), Some(expected))
  }
}
