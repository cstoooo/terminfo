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

///|
/// Parse one `%` operation (or a literal byte) from `self.fmt`.
/// Returns 0 when an operation or literal was consumed, 1 for `%t`,
/// 2 for `%e`, 3 for `%;`, 4 at end of input.
///
/// When `exec` is false, the operation is parsed (so conditional nesting
/// stays in sync) but not executed: nothing is pushed, popped, or output.
fn Tp::parse_op(self : Tp, exec : Bool) -> Int raise ExpandError {
  ///|
  /// Parse and execute one `%?...` conditional, starting just after the
  /// `%?`. Stops after the matching `%;`. Operands in the not-taken branch
  /// are parsed (to keep nesting in sync) but not executed.
  fn parse_cond(self : Tp, exec : Bool) -> Unit raise ExpandError {
    let mut r = Tp::parse_op(self, exec)
    while r != 1 {
      if r == 2 || r == 3 {
        raise ExpandError::Unbalanced("stray %e or %;")
      }
      if r == 4 {
        raise ExpandError::Unbalanced("missing %t")
      }
      r = Tp::parse_op(self, exec)
    }
    let take_first = if exec { Tp::tp_pop(self) != 0 } else { false }
    if take_first {
      r = Tp::parse_op(self, true)
      while r != 3 {
        if r == 2 {
          // Skip the %e branch.
          let mut s = Tp::parse_op(self, false)
          while s != 3 {
            if s == 1 || s == 2 || s == 4 {
              raise ExpandError::Unbalanced("malformed conditional")
            }
            s = Tp::parse_op(self, false)
          }
          break
        }
        if r == 1 || r == 4 {
          raise ExpandError::Unbalanced("missing %;")
        }
        r = Tp::parse_op(self, true)
      }
    } else {
      r = Tp::parse_op(self, false)
      while r != 3 {
        if r == 2 {
          // Execute the %e branch.
          let mut s = Tp::parse_op(self, exec)
          while s != 3 {
            if s == 1 || s == 2 || s == 4 {
              raise ExpandError::Unbalanced("malformed conditional")
            }
            s = Tp::parse_op(self, exec)
          }
          break
        }
        if r == 1 || r == 4 {
          raise ExpandError::Unbalanced("missing %;")
        }
        r = Tp::parse_op(self, false)
      }
    }
  }

  let n = self.fmt.length()
  if self.pos.val >= n {
    return 4
  }
  let c = self.fmt[self.pos.val]
  self.pos.val += 1
  if c != b'%' {
    // Padding specifiers ($<...>) are timing information, not output.
    if c == b'$' && self.pos.val < n && self.fmt[self.pos.val] == b'<' {
      self.pos.val += 1
      while self.pos.val < n && self.fmt[self.pos.val] != b'>' {
        self.pos.val += 1
      }
      if self.pos.val < n {
        self.pos.val += 1
      }
      return 0
    }
    if exec {
      self.out.write_byte(c)
    }
    return 0
  }
  if self.pos.val >= n {
    raise ExpandError::BadPercent("truncated % sequence")
  }
  let op = self.fmt[self.pos.val]
  self.pos.val += 1
  match op {
    b'%' => {
      if exec {
        self.out.write_byte(b'%')
      }
      0
    }
    b'?' => {
      parse_cond(self, exec)
      0
    }
    b't' => 1
    b'e' => 2
    b';' => 3
    b'i' => {
      if exec {
        if self.params.length() > 0 {
          self.params[0] += 1
        }
        if self.params.length() > 1 {
          self.params[1] += 1
        }
      }
      0
    }
    b'p' => {
      let d = Tp::tp_byte(self)
      if d < b'1'.to_int() || d > b'9'.to_int() {
        raise ExpandError::BadPercent("%p expects a digit 1-9")
      }
      if exec {
        let i = d - b'1'.to_int()
        if i >= self.params.length() {
          raise ExpandError::StackUnderflow("parameter index out of range")
        }
        Tp::tp_push(self, self.params[i])
      }
      0
    }
    b'P' => {
      let x = Tp::tp_byte(self)
      if exec {
        let v = Tp::tp_pop(self)
        let i = var_index(x)
        self.vars[i] = v
      }
      0
    }
    b'g' => {
      let x = Tp::tp_byte(self)
      if exec {
        let i = var_index(x)
        Tp::tp_push(self, self.vars[i])
      }
      0
    }
    b'\'' => {
      let x = Tp::tp_byte(self)
      if self.pos.val >= n || self.fmt[self.pos.val] != b'\'' {
        raise ExpandError::BadPercent("missing closing quote in %'c'")
      }
      self.pos.val += 1
      if exec {
        Tp::tp_push(self, x)
      }
      0
    }
    b'{' => {
      let v = Tp::read_digits(self)
      if self.pos.val >= n || self.fmt[self.pos.val] != b'}' {
        raise ExpandError::BadPercent("missing } in %{nn}")
      }
      self.pos.val += 1
      if exec {
        Tp::tp_push(self, v)
      }
      0
    }
    b'l' => {
      if exec {
        let i = Tp::tp_pop(self)
        if i < 0 || i >= self.string_params.length() {
          raise ExpandError::StackUnderflow(
            "string parameter index out of range",
          )
        }
        Tp::tp_push(self, self.string_params[i].length())
      }
      0
    }
    b'+' => {
      // As in ncurses, %+ is binary addition when the stack holds at
      // least two operands, and a printf flag otherwise.
      if self.stack.length() < 2 {
        let conv = Tp::format_ahead(self)
        if conv == 0 {
          raise ExpandError::BadPercent("%+ needs two operands or a conversion")
        }
        self.pos.val -= 1
        Tp::format_op(self, exec)
      } else {
        Tp::binop(self, exec, fn(a : Int, b : Int) { a + b })
      }
      0
    }
    b'-' => {
      if self.stack.length() < 2 {
        let conv = Tp::format_ahead(self)
        if conv == 0 {
          raise ExpandError::BadPercent("%- needs two operands or a conversion")
        }
        self.pos.val -= 1
        Tp::format_op(self, exec)
      } else {
        Tp::binop(self, exec, fn(a : Int, b : Int) { a - b })
      }
      0
    }
    b'#'
    | b' '
    | b':'
    | b'.'
    | b'0'
    | b'1'
    | b'2'
    | b'3'
    | b'4'
    | b'5'
    | b'6'
    | b'7'
    | b'8'
    | b'9' => {
      let conv = Tp::format_ahead(self)
      if conv == 0 {
        raise ExpandError::BadPercent(
          "printf flag or width without a numeric conversion",
        )
      }
      self.pos.val -= 1
      Tp::format_op(self, exec)
      0
    }
    b'*' => {
      Tp::binop(self, exec, fn(a : Int, b : Int) { a * b })
      0
    }
    b'/' => {
      Tp::binop(self, exec, fn(a : Int, b : Int) { a / b }, div_by_zero=true)
      0
    }
    b'm' => {
      Tp::binop(self, exec, fn(a : Int, b : Int) { a % b }, div_by_zero=true)
      0
    }
    b'&' => {
      Tp::binop(self, exec, fn(a : Int, b : Int) { a.land(b) })
      0
    }
    b'|' => {
      Tp::binop(self, exec, fn(a : Int, b : Int) { a.lor(b) })
      0
    }
    b'^' => {
      Tp::binop(self, exec, fn(a : Int, b : Int) { a.lxor(b) })
      0
    }
    b'=' => {
      Tp::binop(self, exec, fn(a : Int, b : Int) { if a == b { 1 } else { 0 } })
      0
    }
    b'>' => {
      Tp::binop(self, exec, fn(a : Int, b : Int) { if a > b { 1 } else { 0 } })
      0
    }
    b'<' => {
      Tp::binop(self, exec, fn(a : Int, b : Int) { if a < b { 1 } else { 0 } })
      0
    }
    b'A' => {
      Tp::binop(self, exec, fn(a : Int, b : Int) {
        if a != 0 && b != 0 {
          1
        } else {
          0
        }
      })
      0
    }
    b'O' => {
      Tp::binop(self, exec, fn(a : Int, b : Int) {
        if a != 0 || b != 0 {
          1
        } else {
          0
        }
      })
      0
    }
    b'!' => {
      if exec {
        let a = Tp::tp_pop(self)
        Tp::tp_push(self, if a == 0 { 1 } else { 0 })
      }
      0
    }
    b'~' => {
      if exec {
        let a = Tp::tp_pop(self)
        Tp::tp_push(self, a.lnot())
      }
      0
    }
    b'c' => {
      if exec {
        let v = Tp::tp_pop(self)
        self.out.write_byte((v & 0xFF).to_byte())
      }
      0
    }
    b'd' | b'o' | b'x' | b'X' => {
      self.pos.val -= 1
      Tp::format_op(self, exec)
      0
    }
    b's' => {
      if exec {
        let i = Tp::tp_pop(self)
        if i < 0 || i >= self.string_params.length() {
          raise ExpandError::StackUnderflow(
            "string parameter index out of range",
          )
        }
        self.out.write_bytes(self.string_params[i])
      }
      0
    }
    b'$' => {
      // %$ has no meaning; padding is handled on literal '$' above.
      if exec {
        self.out.write_byte(b'$')
      }
      0
    }
    _ => raise ExpandError::BadPercent("unknown % conversion")
  }
}
