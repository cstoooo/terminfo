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
