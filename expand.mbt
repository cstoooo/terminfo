///|
/// Interpreter state for `tparm`. `pos` lives in a `Ref` so that recursive
/// helpers share one cursor while the rest of the struct is passed by value.
priv struct Tp {
  fmt : Bytes
  params : Array[Int]
  string_params : Array[Bytes]
  pos : Ref[Int]
  stack : Array[Int]
  /// 26 lower-case variables followed by 26 upper-case variables.
  vars : Array[Int]
  out : Buffer
}

///|
priv struct FmtFlags {
  mut minus : Bool
  mut plus : Bool
  mut hash : Bool
  mut space : Bool
}

///|
fn Tp::tp_pop(self : Tp) -> Int raise ExpandError {
  if self.stack.length() == 0 {
    raise ExpandError::StackUnderflow("stack underflow at byte \{self.pos.val}")
  }
  let v = self.stack[self.stack.length() - 1]
  self.stack.pop() |> ignore
  v
}

///|
fn Tp::tp_push(self : Tp, v : Int) -> Unit {
  self.stack.push(v)
}

///|
fn Tp::tp_byte(self : Tp) -> Int raise ExpandError {
  if self.pos.val >= self.fmt.length() {
    raise ExpandError::BadPercent("truncated % sequence")
  }
  let c = self.fmt[self.pos.val].to_int()
  self.pos.val += 1
  c
}

///|
fn Tp::read_digits(self : Tp) -> Int raise ExpandError {
  let mut v = 0
  let mut any = false
  while self.pos.val < self.fmt.length() {
    let c = self.fmt[self.pos.val]
    if c < b'0' || c > b'9' {
      break
    }
    any = true
    v = v * 10 + (c.to_int() - b'0'.to_int())
    if v > 0x7FFFFFFF / 10 {
      raise ExpandError::BadPercent("number too large")
    }
    self.pos.val += 1
  }
  if !any {
    raise ExpandError::BadPercent("expected digits")
  }
  v
}

///|
/// Format one integer according to printf-style flags. Returns the bytes to
/// append to the output.
fn format_int(
  v : Int,
  base : Int,
  upper : Bool,
  flags : FmtFlags,
  width : Int,
  prec : Int,
) -> Bytes {
  let mut x = v.to_int64()
  let neg = x < 0L
  if neg {
    x = -x
  }
  let base64 = base.to_int64()
  let digits_buf = Buffer(size_hint=16)
  while true {
    let d = (x % base64).to_int()
    digits_buf.write_byte(
      (if d < 10 {
        b'0'.to_int() + d
      } else {
        (if upper { b'A'.to_int() } else { b'a'.to_int() }) + d - 10
      }).to_byte(),
    )
    x = x / base64
    if x == 0L {
      break
    }
  }
  let digits = digits_buf.to_bytes()
  let ndigits_raw = digits.length()
  let ndigits = if prec > ndigits_raw { prec } else { ndigits_raw }
  let hash_len = if flags.hash && v != 0 && base != 10 {
    if base == 8 {
      1
    } else {
      2
    }
  } else {
    0
  }
  let sign_len = if neg || flags.plus || flags.space { 1 } else { 0 }
  let total = sign_len + hash_len + ndigits
  let out = Buffer(size_hint=total + 16)
  if !flags.minus {
    for j = 0; j < width - total; j = j + 1 {
      out.write_byte(b' ')
    }
  }
  if neg {
    out.write_byte(b'-')
  } else if flags.plus {
    out.write_byte(b'+')
  } else if flags.space {
    out.write_byte(b' ')
  }
  if flags.hash && v != 0 {
    if base == 8 {
      out.write_byte(b'0')
    } else if base == 16 {
      out.write_byte(b'0')
      out.write_byte(if upper { b'X' } else { b'x' })
    }
  }
  for j = 0; j < prec - ndigits_raw; j = j + 1 {
    out.write_byte(b'0')
  }
  for i = ndigits_raw - 1; i >= 0; i = i - 1 {
    out.write_byte(digits[i])
  }
  if flags.minus {
    for j = 0; j < width - total; j = j + 1 {
      out.write_byte(b' ')
    }
  }
  out.to_bytes()
}

///|
fn Tp::binop(
  self : Tp,
  exec : Bool,
  op : (Int, Int) -> Int,
  div_by_zero? : Bool = false,
) -> Unit raise ExpandError {
  if exec {
    let b = Tp::tp_pop(self)
    let a = Tp::tp_pop(self)
    if div_by_zero && b == 0 {
      raise ExpandError::StackUnderflow("division by zero")
    }
    Tp::tp_push(self, op(a, b))
  }
}

///|
/// Scan ahead from the current position: if flag characters, width digits
/// and an optional `.precision` are followed by a d/o/x/X conversion, that
/// conversion is returned (as a byte); otherwise 0. Does not move `pos`.
fn Tp::format_ahead(self : Tp) -> Int {
  let n = self.fmt.length()
  let mut i = self.pos.val
  while i < n {
    let c = self.fmt[i]
    if c == b'-' || c == b':' || c == b'+' || c == b'#' || c == b' ' {
      i += 1
    } else {
      break
    }
  }
  while i < n && self.fmt[i] >= b'0' && self.fmt[i] <= b'9' {
    i += 1
  }
  if i < n && self.fmt[i] == b'.' {
    i += 1
    while i < n && self.fmt[i] >= b'0' && self.fmt[i] <= b'9' {
      i += 1
    }
  }
  if i < n {
    let c = self.fmt[i]
    if c == b'd' || c == b'o' || c == b'x' || c == b'X' {
      return c.to_int()
    }
  }
  0
}

///|
/// Parse and apply one numeric conversion (`%d`, `%o`, `%x`, `%X`) with its
/// printf-style flags. On entry `pos` points at the first flag character
/// (or the conversion itself when there are no flags); the conversion
/// character is consumed. Callers rewind `pos` by one after reading the `%`
/// operation, so `%+5d` re-enters at `+`.
fn Tp::format_op(self : Tp, exec : Bool) -> Unit raise ExpandError {
  let flags : FmtFlags = {
    minus: false,
    plus: false,
    hash: false,
    space: false,
  }
  while self.pos.val < self.fmt.length() {
    let c = self.fmt[self.pos.val]
    if c == b'-' || c == b':' {
      flags.minus = true
      self.pos.val += 1
    } else if c == b'+' {
      flags.plus = true
      self.pos.val += 1
    } else if c == b'#' {
      flags.hash = true
      self.pos.val += 1
    } else if c == b' ' {
      flags.space = true
      self.pos.val += 1
    } else {
      break
    }
  }
  let mut width = 0
  if self.pos.val < self.fmt.length() &&
    self.fmt[self.pos.val] >= b'0' &&
    self.fmt[self.pos.val] <= b'9' {
    width = Tp::read_digits(self)
  }
  let mut prec = -1
  if self.pos.val < self.fmt.length() && self.fmt[self.pos.val] == b'.' {
    self.pos.val += 1
    prec = Tp::read_digits(self)
  }
  if self.pos.val >= self.fmt.length() {
    raise ExpandError::BadPercent("missing conversion after % flags")
  }
  let conv = self.fmt[self.pos.val].to_int()
  self.pos.val += 1
  let base = if conv == b'd'.to_int() {
    10
  } else if conv == b'o'.to_int() {
    8
  } else {
    16
  }
  let upper = conv == b'X'.to_int()
  if exec {
    let v = Tp::tp_pop(self)
    self.out.write_bytes(format_int(v, base, upper, flags, width, prec))
  }
}

///|
fn var_index(x : Int) -> Int raise ExpandError {
  if x >= b'a'.to_int() && x <= b'z'.to_int() {
    x - b'a'.to_int()
  } else if x >= b'A'.to_int() && x <= b'Z'.to_int() {
    26 + x - b'A'.to_int()
  } else {
    raise ExpandError::BadPercent("variable must be a letter")
  }
}
