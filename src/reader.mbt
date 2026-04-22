///|
/// This file is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.3:src/compress/zlib/reader.go
/// which has the copyright notice:
/// Copyright 2009 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.
///
/// Package zlib implements reading and writing of zlib format compressed data,
/// as specified in RFC 1950.
///
/// The implementation provides filters that uncompress during reading
/// and compress during writing.  For example, to write compressed data
/// to a buffer:
///
/// 	var b bytes.Buffer
/// 	w := zlib.NewWriter(&b)
/// 	w.Write(Slice[Byte]("hello, world\n"))
/// 	w.close()
///
/// and to read that data back:
///
/// 	r, err := zlib.Reader::new(&b)
/// 	io.Copy(os.Stdout, r)
/// 	r.close()
/// 
/// 
const GZIP_ID1 = b'\x1f'

///|
const GZIP_ID2 = b'\x8b'

///|
const GZIP_DEFLATE = b'\x08'

///|
const GZIP_FHCRC = b'\x02' // 头部有CRC

///|
const GZIP_FEXTRA = b'\x04' // 有额外字段

///|
const GZIP_FNAME = b'\x08' // 有原始文件名

///|
const GZIP_FCOMMENT = b'\x10' // 有注释

///|
type Slice[T] = @io.Slice[T]

///|
type IOError = @io.IOError

///|
/// err_checksum is returned when reading ZLIB data that has an invalid checksum.
pub let err_checksum : IOError = IOError("gzip: invalid checksum")

///|
/// err_dictionary is returned when reading ZLIB data that has an invalid dictionary.
pub let err_dictionary : IOError = IOError("gzip: invalid dictionary")

///|
/// err_header is returned when reading ZLIB data that has an invalid header.
pub let err_header : IOError = IOError("gzip: invalid header")

///|
struct Reader {
  mut r : &@flate.Reader
  mut decompressor : &@io.ReadCloser
  mut digest : &@hash.Hash32
  mut err : IOError?
  mut scratch : Slice[Byte] // [8]byte
  mut size : UInt
}

///|
/// Resetter resets a ReadCloser returned by [Reader::new] or [Reader::new_dict]
/// to switch to a new underlying Reader. This permits reusing a ReadCloser
/// instead of allocating a new one.
pub(open) trait Resetter {
  /// reset discards any buffered data and resets the Resetter as if it was
  /// newly initialized with the given reader.
  reset(Self, &@flate.Reader, Slice[Byte]) -> IOError?
}

///|
/// Reader::new creates a new ReadCloser.
/// Reads from the returned ReadCloser read and decompress data from r.
/// If r does not implement [io.ByteReader], the decompressor may read more
/// data than necessary from r.
/// It is the caller's responsibility to call close on the ReadCloser when done.
///
/// The [io.ReadCloser] returned by Reader::new also implements [Resetter].
pub fn Reader::new(r : &@flate.Reader) -> (&@io.ReadCloser, IOError?) {
  Reader::new_dict(r, Slice::new([]))
}

///|
/// Reader::new_dict is like [Reader::new] but uses a preset dictionary.
/// Reader::new_dict ignores the dictionary if the compressed data does not refer to it.
/// If the compressed data refers to a different dictionary, Reader::new_dict returns [err_dictionary].
///
/// The ReadCloser returned by Reader::new_dict also implements [Resetter].
pub fn Reader::new_dict(
  r : &@flate.Reader,
  dict : Slice[Byte],
) -> (&@io.ReadCloser, IOError?) {
  let z : Reader = {
    r,
    decompressor: &@flate.Reader::new(r),
    digest: @crc32.new(),
    err: None,
    scratch: Slice::new([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    size: 0,
  }
  let err = z.reset(r, dict)
  (z, err)
}

///|
pub impl @io.Reader for Reader with read(self, p) {
  if self.err != None {
    return (0, self.err)
  }
  let (n, err) = self.decompressor.read(p)
  self.err = err
  guard self.digest.write(p[0:n]) is (_, None)

  self.size = self.size + n.reinterpret_as_uint()

  if self.err != Some(@io.eof) {
    // In the normal case we return here.
    return (n, self.err)
  }

  // Finished file; check checksum.
  let (_, err) = @io.read_full(self.r, self.scratch[0:8])
  if err != None {
    let mut err = err
    if err == Some(@io.eof) {
      err = Some(@io.err_unexpected_eof)
    }
    self.err = err
    return (n, self.err)
  }
  // ZLIB (RFC 1950) is big-endian, unlike GZIP (RFC 1952).
  let checksum = le_uint32(self.scratch[0:4])
  if checksum != self.digest.sum32() {
    self.err = Some(err_checksum)
    return (n, self.err)
  }

  let size = le_uint32(self.scratch[4:8])
  if size != self.size % (1 << 32).reinterpret_as_uint() { // 取模处理可能的溢出
    self.err = Some(IOError("gzip: invalid file size"))
    return (n, self.err)
  }

  (n, Some(@io.eof))
}

///|
fn le_uint32(b : Slice[Byte]) -> UInt {
  b[0].to_uint() |
  (b[1].to_uint() << 8) |
  (b[2].to_uint() << 16) |
  (b[3].to_uint() << 24)
}

///|
/// Calling close does not close the wrapped [io.Reader] originally passed to [Reader::new].
/// In order for the ZLIB checksum to be verified, the reader must be
/// fully consumed until the [io.eof].
pub impl @io.Closer for Reader with close(self) {
  if self.err != None && self.err != Some(@io.eof) {
    return self.err
  }
  self.err = self.decompressor.close()
  self.err
}

///|
pub impl @io.ReadCloser for Reader

///|
pub impl Resetter for Reader with reset(self, r, _dict) {
  self.r = r
  self.digest = @crc32.new()
  self.err = None
  self.size = 0 // 重置计数器
  self.scratch = Slice::new([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
  // if fr, ok := r.(flate.Reader); ok {
  // 	self.r = fr
  // } else {
  // 	self.r = bufio.Reader::new(r)
  // }

  // Read the header (RFC 1950 section 2.2.).
  let header : Slice[Byte] = Slice::new([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
  let (_, err) = @io.read_full(self.r, header)
  if err != None {
    self.err = err
    if self.err == Some(@io.eof) {
      self.err = Some(@io.err_unexpected_eof)
    }
    return self.err
  }

  if header[0] != GZIP_ID1 || header[1] != GZIP_ID2 {
    self.err = Some(err_header)
    return self.err
  }

  if header[2] != GZIP_DEFLATE {
    self.err = Some(IOError("gzip: unknown compression method"))
    return self.err
  }

  let flags = header[3]

  if (flags & GZIP_FEXTRA) != 0 {
    let xlen_buf : Slice[Byte] = Slice::new([0, 0])
    let (_, _) = @io.read_full(self.r, xlen_buf)
    let xlen = (xlen_buf[0].to_uint() | (xlen_buf[1].to_uint() << 8)).reinterpret_as_int()

    let skip_buf : Slice[Byte] = Slice::new([0])
    for _ in 0..<xlen {
      let (_, _) = self.r.read(skip_buf)
    }
  }

  if (flags & GZIP_FHCRC) != 0 {
    // 读取2字节的CRC16
    let crc_buf : Slice[Byte] = Slice::new([0, 0])
    let (_, err) = @io.read_full(self.r, crc_buf)
    if err != None {
      self.err = err
      return self.err
    }
    // 如果需要，可以在这里验证头部CRC
  }

  if (flags & GZIP_FNAME) != 0 {
    // 读取到0字节为止
    let skip_buf : Slice[Byte] = Slice::new([0])
    while true {
      let (_, _) = @io.read_full(self.r, skip_buf)
      if skip_buf[0] == 0 {
        break
      }
    }
  }

  if (flags & GZIP_FCOMMENT) != 0 {
    // 读取到0字节为止
    let skip_buf : Slice[Byte] = Slice::new([0])
    while true {
      let (_, _) = @io.read_full(self.r, skip_buf)
      if skip_buf[0] == 0 {
        break
      }
    }
  }

  self.decompressor = &@flate.Reader::new(self.r)

  None
}
