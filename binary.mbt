///|
/// Read one unsigned 16-bit little-endian word.
fn read_u16(bytes : Bytes, at : Int) -> Int {
  bytes[at].to_int() | (bytes[at + 1].to_int() << 8)
}

///|
/// Read one signed 16-bit little-endian word.
fn read_i16(bytes : Bytes, at : Int) -> Int {
  let u = read_u16(bytes, at)
  if u < 0x8000 {
    u
  } else {
    u - 0x10000
  }
}

///|
/// Read one signed 32-bit little-endian word.
///
/// The high byte is shifted as a negative value so the result is correct
/// without relying on unchecked 32-bit overflow (works on wasm too).
fn read_i32(bytes : Bytes, at : Int) -> Int {
  let lo = bytes[at].to_int() |
    (bytes[at + 1].to_int() << 8) |
    (bytes[at + 2].to_int() << 16)
  lo | ((bytes[at + 3].to_int() - 0x100) << 24)
}

///|
/// Read a NUL-terminated byte string from `bytes` starting at `start`,
/// requiring the terminator within `limit`. Returns the bytes without the
/// terminating NUL.
fn read_cstr(bytes : Bytes, start : Int, limit : Int) -> Bytes raise ParseError {
  let mut i = start
  while i < limit && bytes[i] != b'\x00' {
    i += 1
  }
  if i >= limit {
    raise ParseError::BadOffset("unterminated string in string table")
  }
  let buf = Buffer::Buffer(size_hint=i - start)
  for j = start; j < i; j = j + 1 {
    buf.write_byte(bytes[j])
  }
  buf.to_bytes()
}

///|
/// Split the names section on `|`, stopping at the NUL terminator and
/// dropping empty aliases. Names are bytes on disk; non-UTF-8 bytes are
/// decoded lossily.
fn split_names(text : BytesView) -> Array[String] {
  let out : Array[String] = []
  let mut start = 0
  let n = text.length()
  for i = 0; i < n; i = i + 1 {
    let c = text[i]
    if c == b'|' || c == b'\x00' {
      if i > start {
        out.push(@utf8.decode_lossy(text[start:i]))
      }
      start = i + 1
      if c == b'\x00' {
        break
      }
    }
  }
  out
}

///|
fn max_used_index(arr : Array[Int], sentinel : Int) -> Int {
  let mut last = 0
  for i = 0; i < arr.length(); i = i + 1 {
    if arr[i] != sentinel {
      last = i + 1
    }
  }
  last
}

///|
/// Parse a compiled terminfo file (ncurses binary format, both magic numbers,
/// with or without the extended storage section).
pub fn parse(bytes : Bytes) -> Entry raise ParseError {
  if bytes.length() < 2 {
    raise ParseError::Truncated
  }
  let magic = read_u16(bytes, 0)
  if magic != 0o432 && magic != 0o1036 {
    raise ParseError::BadMagic(magic)
  }
  if bytes.length() < 12 {
    raise ParseError::Truncated
  }
  let num_width = if magic == 0o1036 { 4 } else { 2 }
  let namelen = read_u16(bytes, 2)
  let bool_count = read_u16(bytes, 4)
  let num_count = read_u16(bytes, 6)
  let str_count = read_u16(bytes, 8)
  let str_size = read_u16(bytes, 10)
  let n = bytes.length()

  // Names section.
  if namelen == 0 {
    raise ParseError::BadCount("names section out of bounds")
  }
  if 12 + namelen > n {
    raise ParseError::Truncated
  }
  let names = split_names(bytes[12:12 + namelen])
  if names.length() == 0 {
    raise ParseError::BadCount("empty names section")
  }

  // Boolean section.
  let mut pos = 12 + namelen
  if pos + bool_count > n {
    raise ParseError::Truncated
  }
  let booleans = Array::make(bool_count, 0)
  for i = 0; i < bool_count; i = i + 1 {
    let b = bytes[pos + i].to_int()
    booleans[i] = if b == 1 { 1 } else if b == 0 { 0 } else { 2 }
  }
  pos += bool_count

  // Alignment pad before numbers.
  if pos % 2 == 1 {
    pos += 1
  }
  if pos > n {
    raise ParseError::Truncated
  }

  // Number section.
  if pos + num_count * num_width > n {
    raise ParseError::Truncated
  }
  let numbers = Array::make(num_count, -1)
  for i = 0; i < num_count; i = i + 1 {
    let v = if num_width == 4 {
      read_i32(bytes, pos)
    } else {
      read_i16(bytes, pos)
    }
    if v < -2 {
      raise ParseError::BadCount("illegal numeric value: \{v}")
    }
    numbers[i] = v
    pos += num_width
  }

  // String offsets.
  if pos + 2 * str_count > n {
    raise ParseError::Truncated
  }
  let offsets = Array::make(str_count, -1)
  for i = 0; i < str_count; i = i + 1 {
    let v = read_i16(bytes, pos)
    if v < -2 || v >= str_size {
      raise ParseError::BadOffset("string offset out of range: \{v}")
    }
    offsets[i] = v
    pos += 2
  }

  // String table.
  if pos + str_size > n {
    raise ParseError::Truncated
  }
  let strings = Array::make(str_count, None)
  for i = 0; i < str_count; i = i + 1 {
    let ofs = offsets[i]
    if ofs >= 0 {
      strings[i] = Some(read_cstr(bytes, pos + ofs, pos + str_size))
    }
  }
  pos += str_size

  // Extended storage section (optional, ncurses 5.0+).
  if n - pos < 10 {
    return {
      names,
      booleans,
      numbers,
      strings,
      ext_booleans: Map([]),
      ext_numbers: Map([]),
      ext_strings: Map([]),
      ext_canceled_strings: [],
    }
  }
  if pos % 2 == 1 {
    pos += 1
  }
  if pos > n {
    raise ParseError::Truncated
  }
  if n - pos < 10 {
    raise ParseError::BadCount("trailing data after string table")
  }
  let ext_bool_count = read_u16(bytes, pos)
  let ext_num_count = read_u16(bytes, pos + 2)
  let ext_str_count = read_u16(bytes, pos + 4)
  let ext_usage = read_u16(bytes, pos + 6)
  let ext_size = read_u16(bytes, pos + 8)
  pos += 10
  let ext_names_total = ext_bool_count + ext_num_count + ext_str_count
  if ext_usage > ext_names_total + ext_str_count {
    raise ParseError::BadCount("extended string table usage count out of range")
  }

  // Extended booleans.
  if pos + ext_bool_count > n {
    raise ParseError::Truncated
  }
  let ext_bool_values = Array::make(ext_bool_count, 0)
  for i = 0; i < ext_bool_count; i = i + 1 {
    let b = bytes[pos + i].to_int()
    ext_bool_values[i] = if b == 1 { 1 } else if b == 0 { 0 } else { 2 }
  }
  pos += ext_bool_count
  if ext_bool_count % 2 == 1 {
    pos += 1
  }
  if pos > n {
    raise ParseError::Truncated
  }

  // Extended numbers.
  if pos + ext_num_count * num_width > n {
    raise ParseError::Truncated
  }
  let ext_num_values = Array::make(ext_num_count, -1)
  for i = 0; i < ext_num_count; i = i + 1 {
    let v = if num_width == 4 {
      read_i32(bytes, pos)
    } else {
      read_i16(bytes, pos)
    }
    if v < -2 {
      raise ParseError::BadCount("illegal extended numeric value: \{v}")
    }
    ext_num_values[i] = v
    pos += num_width
  }

  // Offset table: extended string values, then names.
  if pos + 2 * (ext_str_count + ext_names_total) > n {
    raise ParseError::Truncated
  }
  let ext_value_offsets = Array::make(ext_str_count, -1)
  for i = 0; i < ext_str_count; i = i + 1 {
    ext_value_offsets[i] = read_i16(bytes, pos)
    pos += 2
  }
  let ext_name_offsets = Array::make(ext_names_total, -1)
  for i = 0; i < ext_names_total; i = i + 1 {
    ext_name_offsets[i] = read_i16(bytes, pos)
    pos += 2
  }

  // Extended string table: values first, names last.
  if pos + ext_size > n {
    raise ParseError::Truncated
  }
  let table_start = pos
  let ext_values = Array::make(ext_str_count, None)
  let mut values_end = 0
  for i = 0; i < ext_str_count; i = i + 1 {
    let ofs = ext_value_offsets[i]
    if ofs >= 0 {
      if ofs >= ext_size {
        raise ParseError::BadOffset(
          "extended string offset out of range: \{ofs}",
        )
      }
      let v = read_cstr(bytes, table_start + ofs, table_start + ext_size)
      let finish = ofs + v.length() + 1
      if finish > values_end {
        values_end = finish
      }
      ext_values[i] = Some(v)
    } else if ofs != -1 && ofs != -2 {
      raise ParseError::BadOffset("illegal extended string offset: \{ofs}")
    }
  }

  // Read names. Well-formed files carry explicit name offsets; fall back to
  // sequential reading after the values when they are absent or corrupt.
  let use_explicit = ext_name_offsets.all(fn(ofs) { ofs >= 0 && ofs < ext_size })
  let mut name_cursor = values_end
  let read_name = fn(i : Int) -> Bytes raise ParseError {
    let ofs = if use_explicit { ext_name_offsets[i] } else { name_cursor }
    if ofs < 0 || ofs >= ext_size {
      raise ParseError::BadOffset("extended name offset out of range: \{ofs}")
    }
    let name = read_cstr(bytes, table_start + ofs, table_start + ext_size)
    if !use_explicit {
      name_cursor = ofs + name.length() + 1
    }
    name
  }

  let ext_booleans : Map[String, Int] = Map([])
  for i = 0; i < ext_bool_count; i = i + 1 {
    ext_booleans.set(@utf8.decode_lossy(read_name(i)), ext_bool_values[i])
  }
  let ext_numbers : Map[String, Int] = Map([])
  for i = 0; i < ext_num_count; i = i + 1 {
    ext_numbers.set(
      @utf8.decode_lossy(read_name(ext_bool_count + i)),
      ext_num_values[i],
    )
  }
  let ext_strings : Map[String, Bytes] = Map([])
  let ext_canceled : Array[String] = []
  for i = 0; i < ext_str_count; i = i + 1 {
    let name = @utf8.decode_lossy(read_name(ext_bool_count + ext_num_count + i))
    match ext_values[i] {
      Some(v) => ext_strings.set(name, v)
      None => if ext_value_offsets[i] == -2 { ext_canceled.push(name) }
    }
  }
  {
    names,
    booleans,
    numbers,
    strings,
    ext_booleans,
    ext_numbers,
    ext_strings,
    ext_canceled_strings: ext_canceled,
  }
}
