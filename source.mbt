///|
/// Split text into lines, handling `\r\n` and a missing final newline.
fn split_lines(text : String) -> Array[String] {
  let out : Array[String] = []
  let n = text.length()
  let mut start = 0
  for i = 0; i < n; i = i + 1 {
    if text[i] == '\n' {
      let mut end = i
      if end > start && text[end - 1] == '\r' {
        end -= 1
      }
      out.push(text[start:end].to_owned())
      start = i + 1
    }
  }
  if n > start {
    let mut end = n
    if end > start && text[end - 1] == '\r' {
      end -= 1
    }
    out.push(text[start:end].to_owned())
  }
  out
}

///|
/// Group lines into entry blocks. An entry starts at a line in column 0;
/// lines starting with whitespace continue the previous entry; `#` lines and
/// blank lines are ignored.
fn make_blocks(lines : Array[String]) -> Array[Array[String]] {
  let blocks : Array[Array[String]] = []
  let mut cur : Array[String] = []
  for line in lines {
    if line.length() == 0 {
      continue
    }
    let c = line[0]
    if c == '#' {
      continue
    }
    if c == ' ' || c == '\t' {
      if cur.length() > 0 {
        cur.push(line)
      }
      continue
    }
    if cur.length() > 0 {
      blocks.push(cur)
      cur = []
    }
    cur.push(line)
  }
  if cur.length() > 0 {
    blocks.push(cur)
  }
  blocks
}

///|
/// Strip leading and trailing blanks.
fn trim_ws(s : String) -> String {
  let n = s.length()
  let mut start = 0
  let mut end = n
  while start < end && (s[start] == ' ' || s[start] == '\t') {
    start += 1
  }
  while end > start && (s[end - 1] == ' ' || s[end - 1] == '\t') {
    end -= 1
  }
  s[start:end].to_owned()
}

///|
/// Split a source entry body into comma-separated fields, honoring `\`
/// escapes (including `\,` and octal `\NNN`) so that escaped commas do not
/// split fields.
fn split_fields(body : String) -> Array[String] {
  let out : Array[String] = []
  let n = body.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    let c = body[i]
    if c == '\\' {
      if i + 1 < n {
        let e = body[i + 1]
        if e >= '0' && e <= '7' {
          i += 2
          let mut k = 1
          while k < 3 && i < n && body[i] >= '0' && body[i] <= '7' {
            i += 1
            k += 1
          }
        } else {
          i += 2
        }
      } else {
        i += 1
      }
    } else if c == ',' {
      out.push(trim_ws(body[start:i].to_owned()))
      i += 1
      start = i
    } else {
      i += 1
    }
  }
  out.push(trim_ws(body[start:n].to_owned()))
  out
}

///|
/// Parse a numeric capability value: C-style decimal, hex (`0x`), or octal
/// (leading `0`), with an optional sign.
fn parse_num(s : String) -> Int raise ParseError {
  let n = s.length()
  let mut i = 0
  let mut neg = false
  if i < n && (s[i] == '-' || s[i] == '+') {
    neg = s[i] == '-'
    i += 1
  }
  let mut base = 10
  if i + 1 < n && s[i] == '0' && (s[i + 1] == 'x' || s[i + 1] == 'X') {
    base = 16
    i += 2
  } else if i < n && s[i] == '0' && n - i > 1 {
    base = 8
    i += 1
  }
  let mut v = 0
  let mut any = false
  while i < n {
    let c = s[i]
    let d = if c >= '0' && c <= '9' {
      c.to_int() - b'0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      10 + c.to_int() - b'a'.to_int()
    } else if c >= 'A' && c <= 'F' {
      10 + c.to_int() - b'A'.to_int()
    } else {
      -1
    }
    if d < 0 || d >= base {
      raise ParseError::BadSyntax("bad number: \{s}")
    }
    any = true
    if v > 0x7FFFFFFF / 16 {
      raise ParseError::BadSyntax("number too large: \{s}")
    }
    v = v * base + d
    i += 1
  }
  if !any {
    raise ParseError::BadSyntax("bad number: \{s}")
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// Expand the escape sequences of a source string value into raw bytes.
/// Handles `\E`, `\e`, `\n`, `\l`, `\r`, `\t`, `\b`, `\f`, `\s`, `\:`,
/// `\^`, `\\`, `\,`, `\|`, octal `\NNN` (up to 3 digits), and `^X`
/// control notation (`^?` is DEL). A backslash at end of line continues
/// the value on the next line.
pub fn unescape_value(raw : String) -> Bytes raise ParseError {
  let buf = Buffer::Buffer(size_hint=raw.length())
  let n = raw.length()
  let mut i = 0
  while i < n {
    let c = raw[i]
    if c == '\\' {
      if i + 1 >= n {
        raise ParseError::BadSyntax("trailing backslash in string value")
      }
      let e = raw[i + 1]
      if e == '\n' {
        i += 2
        continue
      }
      let byte = match e {
        'E' | 'e' => 0x1B
        'n' | 'l' => 0x0A
        'r' => 0x0D
        't' => 0x09
        'b' => 0x08
        'f' => 0x0C
        's' => 0x20
        ':' => 0x3A
        '^' => 0x5E
        '\\' => 0x5C
        ',' => 0x2C
        '|' => 0x7C
        _ => -1
      }
      if byte >= 0 {
        buf.write_byte(byte.to_byte())
        i += 2
        continue
      }
      if e >= '0' && e <= '7' {
        let mut v = 0
        let mut k = 0
        while k < 3 && i + 1 + k < n {
          let d = raw[i + 1 + k]
          if d < '0' || d > '7' {
            break
          }
          v = v * 8 + (d.to_int() - b'0'.to_int())
          k += 1
        }
        buf.write_byte(v.to_byte())
        i += 1 + k
        continue
      }
      raise ParseError::BadSyntax("unknown escape \\\{e} in string value")
    }
    if c == '^' {
      if i + 1 >= n {
        raise ParseError::BadSyntax("trailing ^ in string value")
      }
      let e = raw[i + 1]
      if e == '?' {
        buf.write_byte(b'\x7F')
      } else {
        buf.write_byte((e.to_int() & 0x1F).to_byte())
      }
      i += 2
      continue
    }
    let v = c.to_int()
    if v > 0x7F {
      raise ParseError::BadSyntax("non-ASCII character in string value")
    }
    buf.write_byte(v.to_byte())
    i += 1
  }
  buf.to_bytes()
}

///|
/// Parse one entry block.
fn parse_block(block : Array[String]) -> SourceEntry raise ParseError {
  // Names: `primary|alias|verbose`.
  let names : Array[String] = []
  let first = block[0]
  let n = first.length()
  let mut start = 0
  for i = 0; i < n; i = i + 1 {
    if first[i] == '|' {
      let name = trim_ws(first[start:i].to_owned())
      if name.length() > 0 {
        names.push(name)
      }
      start = i + 1
    }
  }
  // The names line conventionally ends with `,` (the field separator);
  // tic drops it, so the verbose name must not carry it.
  let last = {
    let t = trim_ws(first[start:n].to_owned())
    let mut end = t.length()
    while end > 0 && t[end - 1] == ',' {
      end -= 1
    }
    t[0:end].to_owned()
  }
  if last.length() > 0 {
    names.push(last)
  }
  if names.length() == 0 {
    raise ParseError::BadSyntax("entry has no terminal name")
  }

  // Capability fields: continuation lines are joined, with their leading
  // whitespace discarded.
  let body = StringBuilder(size_hint=128)
  for i = 1; i < block.length(); i = i + 1 {
    body.write_string(trim_ws(block[i]))
  }
  let se : SourceEntry = {
    names,
    booleans: Map([]),
    numbers: Map([]),
    strings: Map([]),
    uses: [],
    canceled: [],
  }
  for field in split_fields(body.to_string()) {
    if field.length() > 0 {
      parse_field(field, se)
    }
  }
  se
}

///|
/// Parse one capability field of an entry: `name`, `name#N`, `name=value`,
/// `name@`, or `use=target` (also `tc=target` for termcap sources).
fn parse_field(field : String, se : SourceEntry) -> Unit raise ParseError {
  let n = field.length()
  let mut k = 0
  while k < n && field[k] != '#' && field[k] != '=' {
    k += 1
  }
  let name = trim_ws(field[0:k].to_owned())
  if name.length() == 0 {
    raise ParseError::BadSyntax("empty capability name")
  }
  if k < n && field[k] == '#' {
    let num_str = trim_ws(field[k + 1:n].to_owned())
    se.numbers.set(name, parse_num(num_str))
    return
  }
  if k < n && field[k] == '=' {
    if name == "use" || name == "tc" {
      let target = trim_ws(field[k + 1:n].to_owned())
      if target.length() == 0 {
        raise ParseError::BadSyntax("use= with empty target")
      }
      se.uses.push(target)
      return
    }
    se.strings.set(name, trim_ws(field[k + 1:n].to_owned()))
    return
  }
  // Bare name: a boolean flag, or a cancellation when suffixed with @.
  if name.has_suffix("@") {
    let real = trim_ws(name[0:name.length() - 1].to_owned())
    match bool_idx(real) {
      Some(_) => se.booleans.set(real, 2)
      None =>
        match num_idx(real) {
          Some(_) => se.numbers.set(real, -2)
          None => se.canceled.push(real)
        }
    }
    return
  }
  se.booleans.set(name, 1)
}

///|
/// Resolve a capability name to its binary index, accepting both the long
/// name (`columns`) and the two-character code (`co`).
fn bool_idx(name : String) -> Int? {
  match bool_index.get(name) {
    Some(i) => Some(i)
    None => bool_code_index.get(name)
  }
}

///|
fn num_idx(name : String) -> Int? {
  match num_index.get(name) {
    Some(i) => Some(i)
    None => num_code_index.get(name)
  }
}

///|
fn str_idx(name : String) -> Int? {
  match str_index.get(name) {
    Some(i) => Some(i)
    None => str_code_index.get(name)
  }
}

///|
/// Parse a complete terminfo source file (the `terminfo.src` language) into
/// its entries. Entries keep their raw source escapes; compile with
/// `compile` to get binary-ready `Entry` values.
pub fn parse_source(text : String) -> Array[SourceEntry] raise ParseError {
  let out : Array[SourceEntry] = []
  for block in make_blocks(split_lines(text)) {
    out.push(parse_block(block))
  }
  out
}

///|
/// Compile the entry named `name` (and everything it inherits via `use=`)
/// into an `Entry` ready for `to_bytes`. Capabilities of the entry itself
/// override inherited ones; earlier `use=` targets win over later ones;
/// `name@` cancellations negate inherited values.
pub fn compile(
  entries : Array[SourceEntry],
  name : String,
) -> Entry raise ParseError {
  resolve(name, entries, Map([]))
}

///|
fn resolve(
  target : String,
  entries : Array[SourceEntry],
  visited : Map[String, Bool],
) -> Entry raise ParseError {
  if visited.contains(target) {
    raise ParseError::CyclicUse("use= cycle involving \{target}")
  }
  visited.set(target, true)
  let mut found : SourceEntry? = None
  for e in entries {
    if e.names[0] == target {
      found = Some(e)
      break
    }
  }
  let entry = match found {
    Some(e) => e
    None => {
      visited.remove(target)
      raise ParseError::BadSyntax("use target not found: \{target}")
    }
  }
  let result = empty()
  for u in entry.uses {
    let base = resolve(u, entries, visited)
    merge_into(result, base)
  }
  apply_own(result, entry)
  result.names = entry.names
  visited.remove(target)
  result
}

///|
/// Fill `dst` with capabilities of `src` that `dst` does not have yet.
/// Used to apply `use=` inheritance: earlier wins.
fn merge_into(dst : Entry, src : Entry) -> Unit {
  for i = 0; i < dst.booleans.length(); i = i + 1 {
    if dst.booleans[i] == 0 && i < src.booleans.length() && src.booleans[i] != 0 {
      dst.booleans[i] = src.booleans[i]
    }
  }
  for i = 0; i < dst.numbers.length(); i = i + 1 {
    if dst.numbers[i] == -1 && i < src.numbers.length() && src.numbers[i] != -1 {
      dst.numbers[i] = src.numbers[i]
    }
  }
  for i = 0; i < dst.strings.length(); i = i + 1 {
    match dst.strings[i] {
      Some(_) => ()
      None =>
        if i < src.strings.length() {
          match src.strings[i] {
            Some(v) => dst.strings[i] = Some(v)
            None => ()
          }
        }
    }
  }
  for k in src.ext_booleans.keys() {
    if !dst.ext_booleans.contains(k) {
      dst.ext_booleans.set(k, src.ext_booleans[k])
    }
  }
  for k in src.ext_numbers.keys() {
    if !dst.ext_numbers.contains(k) {
      dst.ext_numbers.set(k, src.ext_numbers[k])
    }
  }
  for k in src.ext_strings.keys() {
    if !dst.ext_strings.contains(k) && !dst.ext_canceled_strings.contains(k) {
      dst.ext_strings.set(k, src.ext_strings[k])
    }
  }
  for c in src.ext_canceled_strings {
    if !dst.ext_canceled_strings.contains(c) {
      dst.ext_canceled_strings.push(c)
    }
  }
}

///|
/// Apply a source entry's own capabilities onto `dst`, overriding inherited
/// values. String escapes are expanded here.
fn apply_own(dst : Entry, entry : SourceEntry) -> Unit raise ParseError {
  for k in entry.booleans.keys() {
    let v = entry.booleans[k]
    match bool_idx(k) {
      Some(i) => dst.booleans[i] = v
      None => dst.ext_booleans.set(k, v)
    }
  }
  for k in entry.numbers.keys() {
    let v = entry.numbers[k]
    match num_idx(k) {
      Some(i) => dst.numbers[i] = v
      None => dst.ext_numbers.set(k, v)
    }
  }
  for k in entry.strings.keys() {
    let value = unescape_value(entry.strings[k])
    match str_idx(k) {
      Some(i) => dst.strings[i] = Some(value)
      None => dst.ext_strings.set(k, value)
    }
  }
  for name in entry.canceled {
    match str_idx(name) {
      Some(i) => dst.strings[i] = None
      None =>
        if dst.ext_strings.contains(name) {
          dst.ext_strings.remove(name)
          dst.ext_canceled_strings.push(name)
        }
    }
  }
}
