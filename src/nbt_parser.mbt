/// This file will handle parsing uncompressed NBT data streams.
/// It will include functions to read and interpret NBT tags and structures.

///| Define an enum for NBT tag types.
const TAG_End = 0

///|
const TAG_Byte = 1

///|
const TAG_Short = 2

///|
const TAG_Int = 3

///|
const TAG_Long = 4

///|
const TAG_Float = 5

///|
const TAG_Double = 6

///|
const TAG_Byte_Array = 7

///|
const TAG_String = 8

///|
const TAG_List = 9

///|
const TAG_Compound = 10

///|
const TAG_Int_Array = 11

///|
const TAG_Long_Array = 12

///| Define an enum for NBT tag values.
pub(all) enum NBT_Value {
  Byte(Int)
  Short(Int)
  Int(Int)
  Long(Int64)
  Float(Float)
  Double(Double)
  ByteArray(Slice[Byte])
  String(String)
  List(Slice[NBT_Tag]) // Contains unnamed tags of a single type
  Compound(Map[String, NBT_Tag]) // Contains named tags
  IntArray(Slice[Int])
  LongArray(Slice[Int64]) // Corrected from Slice[Int]
  None
}

///| Update the NBT_Tag structure to use the enums.
pub(all) struct NBT_Tag {
  tag_type : Int
  name : String?
  value : NBT_Value
}

///| Helper: read exactly len(buf) bytes into buf
fn read_exact(r : &@io.Reader, buf : Slice[Byte]) -> IOError? {
  let (_, err) = @io.read_full(r, buf)
  err
}

///| Read an unsigned 8-bit
fn read_u8(r : &@io.Reader) -> (Int, IOError?) {
  let buf : @io.Slice[Byte] = Slice::new([0])
  let err = read_exact(r, buf)
  (buf[0].to_int(), err)
}

///| Read a signed 8-bit
fn read_i8(r : &@io.Reader) -> (Int, IOError?) {
  let (b, err) = read_u8(r)
  (b, err)
}

///| Read a big-endian 16-bit signed
fn read_i16(r : &@io.Reader) -> (Int, IOError?) {
  let buf : @io.Slice[Byte] = Slice::new([0, 0])
  let err = read_exact(r, buf)
  let v = ((buf[0].to_uint() << 8) | buf[1].to_uint()).reinterpret_as_int()
  (v, err)
}

///| Read a big-endian 32-bit signed
fn read_i32(r : &@io.Reader) -> (Int, IOError?) {
  let buf : @io.Slice[Byte] = Slice::new([0, 0, 0, 0])
  let err = read_exact(r, buf)
  let v = ((buf[0].to_uint() << 24) |
  (buf[1].to_uint() << 16) |
  (buf[2].to_uint() << 8) |
  buf[3].to_uint()).reinterpret_as_int()
  (v, err)
}

///| Read a big-endian 64-bit signed
fn read_i64(r : &@io.Reader) -> (Int64, IOError?) {
  let buf : @io.Slice[Byte] = Slice::new([0, 0, 0, 0, 0, 0, 0, 0])
  let err = read_exact(r, buf)

  // 正确地按大端合并为无符号 64 位，然后 reinterpret 为有符号
  let v_u = (buf[0].to_uint().to_uint64() << 56) |
    (buf[1].to_uint().to_uint64() << 48) |
    (buf[2].to_uint().to_uint64() << 40) |
    (buf[3].to_uint().to_uint64() << 32) |
    (buf[4].to_uint().to_uint64() << 24) |
    (buf[5].to_uint().to_uint64() << 16) |
    (buf[6].to_uint().to_uint64() << 8) |
    buf[7].to_uint().to_uint64()
  (v_u.reinterpret_as_int64(), err)
}

///| Read a 32-bit float (IEEE 754)
fn read_f32(r : &@io.Reader) -> (Float, IOError?) {
  let (bits, err) = read_i32(r)
  let v = bits.reinterpret_as_float()
  (v, err)
}

///| Read a 64-bit float (IEEE 754)
fn read_f64(r : &@io.Reader) -> (Double, IOError?) {
  let (v64, err) = read_i64(r)
  (v64.reinterpret_as_double(), err)
}

///| Read a UTF-8 string
fn read_string(r : &@io.Reader) -> (String, IOError?) {
  let (length, err) = read_i16(r)
  if err != None {
    return ("", err)
  }
  // Handle potentially empty strings correctly
  if length <= 0 {
    return ("", None) // Empty string or invalid length treated as empty
  }
  let arr : Array[Byte] = Array::make(length, 0)
  let buf : @io.Slice[Byte] = Slice::new(arr)
  let err2 = read_exact(r, buf)
  // Consider potential encoding errors, though unchecked is common
  (buf.to_bytes().to_unchecked_string(), err2)
}

///| Function to read a single NBT tag from a binary stream.
pub fn read_nbt_tag(r : &@io.Reader) -> (NBT_Tag, IOError?) {
  // read tag type
  let (tagType, err) = read_u8(r)
  if err != None {
    // Return TAG_End on read error to avoid infinite loops in compound parsing
    return ({ tag_type: TAG_End, name: None, value: NBT_Value::None }, err)
  }

  // TAG_End has no name or payload
  if tagType == TAG_End {
    return ({ tag_type: TAG_End, name: None, value: NBT_Value::None }, None)
  }

  // read name (all tags except TAG_End have a name)
  let (name, err_name) = read_string(r)
  if err_name != None {
    // Return the read tagType but indicate error
    return ({ tag_type: tagType, name: None, value: NBT_Value::None }, err_name)
  }

  // read payload using the helper function
  let (value, err_payload) = read_nbt_payload(r, tagType)

  // Construct the final tag
  ({ tag_type: tagType, name: Some(name), value }, err_payload)
}

///| Reads the payload/value of an NBT tag given its type.
fn read_nbt_payload(r : &@io.Reader, tag_type : Int) -> (NBT_Value, IOError?) {
  match tag_type {
    TAG_Byte => {
      let (v, e) = read_i8(r)
      (NBT_Value::Byte(v), e)
    }
    TAG_Short => {
      let (v, e) = read_i16(r)
      (NBT_Value::Short(v), e)
    }
    TAG_Int => {
      let (v, e) = read_i32(r)
      (NBT_Value::Int(v), e)
    }
    TAG_Long => {
      let (v, e) = read_i64(r)
      (NBT_Value::Long(v), e)
    }
    TAG_Float => {
      let (v, e) = read_f32(r)
      (NBT_Value::Float(v), e)
    }
    TAG_Double => {
      let (v, e) = read_f64(r)
      (NBT_Value::Double(v), e)
    }
    TAG_Byte_Array => {
      let (len, err) = read_i32(r)
      if err != None {
        return (NBT_Value::None, err)
      }
      if len < 0 {
        return (
          NBT_Value::None,
          Some(IOError("nbt: negative length for byte array")),
        )
      }
      let arr : Array[Byte] = Array::make(len, 0)
      let buf : @io.Slice[Byte] = Slice::new(arr)
      let err2 = read_exact(r, buf)
      (NBT_Value::ByteArray(buf), err2)
    }
    TAG_String => { // String payload is read here
      let (v, e) = read_string(r)
      (NBT_Value::String(v), e)
    }
    TAG_List => {
      let (element_type, err_type) = read_u8(r)
      if err_type != None {
        return (NBT_Value::None, err_type)
      }
      let (length, err_len) = read_i32(r)
      if err_len != None {
        return (NBT_Value::None, err_len)
      }
      if length < 0 {
        return (NBT_Value::None, Some(IOError("nbt: negative length for list")))
      }

      // Initialize array with placeholder tags
      let list_arr : Array[NBT_Tag] = Array::make(length, {
        tag_type: TAG_End,
        name: None,
        value: NBT_Value::None,
      })
      for i = 0; i < length; i = i + 1 {
        // Read the payload for each element
        let (payload_value, err_payload) = read_nbt_payload(r, element_type)
        if err_payload != None {
          return (NBT_Value::None, err_payload)
        }
        // List elements are unnamed tags with the specified element_type
        list_arr[i] = {
          tag_type: element_type,
          name: None,
          value: payload_value,
        }
      }
      (NBT_Value::List(Slice::new(list_arr)), None)
    }
    TAG_Compound => {
      let compound_map = Map::new()
      while true {
        // Recursively read the next tag (type, name, payload)
        let (tag, err_tag) = read_nbt_tag(r)
        if err_tag != None {
          return (NBT_Value::None, err_tag)
        }

        // TAG_End marks the end of the compound tag
        if tag.tag_type == TAG_End {
          break
        }

        // Tags inside a compound MUST be named
        match tag.name {
          Some(name) => compound_map[name] = tag // Ignore result of insert
          None =>
            return (
              NBT_Value::None,
              Some(IOError("nbt: unnamed tag found in compound tag")),
            )
        }
      }
      (NBT_Value::Compound(compound_map), None)
    }
    TAG_Int_Array => {
      let (len, err) = read_i32(r)
      if err != None {
        return (NBT_Value::None, err)
      }
      if len < 0 {
        return (
          NBT_Value::None,
          Some(IOError("nbt: negative length for int array")),
        )
      }
      let arr : Array[Int] = Array::make(len, 0)
      for i = 0; i < len; i = i + 1 {
        let (val, err_val) = read_i32(r)
        if err_val != None {
          return (NBT_Value::None, err_val)
        }
        arr[i] = val
      }
      (NBT_Value::IntArray(Slice::new(arr)), None)
    }
    TAG_Long_Array => {
      let (len, err) = read_i32(r)
      if err != None {
        return (NBT_Value::None, err)
      }
      if len < 0 {
        return (
          NBT_Value::None,
          Some(IOError("nbt: negative length for long array")),
        )
      }
      let arr : Array[Int64] = Array::make(len, 0L) // Use Int64 literal 0L
      for i = 0; i < len; i = i + 1 {
        let (val, err_val) = read_i64(r)
        if err_val != None {
          return (NBT_Value::None, err_val)
        }
        arr[i] = val
      }
      (NBT_Value::LongArray(Slice::new(arr)), None)
    }
    // TAG_End should not be passed to read_nbt_payload
    _ =>
      (
        NBT_Value::None,
        Some(
          IOError("nbt: invalid or unimplemented tag type for payload reading"),
        ),
      )
  }
}

///| Function to parse an entire NBT structure from a binary stream.
pub fn parse_nbt(r : &@io.Reader) -> (NBT_Tag, IOError?) {
  // The root tag must be a named TAG_Compound.
  let (root_tag, err) = read_nbt_tag(r)
  if err != None {
    return ({ tag_type: TAG_End, name: None, value: NBT_Value::None }, err)
  }
  // Basic validation: Check if the root is actually a Compound tag
  if root_tag.tag_type != TAG_Compound {
    return (root_tag, Some(IOError("nbt: root tag must be a TAG_Compound")))
  }
  // The root tag's name is often empty, which is valid.
  (root_tag, None)
}
