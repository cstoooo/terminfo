///|
/// Errors produced while parsing or writing terminfo data.
pub suberror ParseError {
  /// The file does not begin with a terminfo magic number (0o432 or 0o1036).
  BadMagic(Int)
  /// The file ends before all sections declared by the header were read.
  Truncated
  /// A header count is inconsistent with the file size.
  BadCount(String)
  /// A string-table offset points outside its table.
  BadOffset(String)
  /// A `use=` chain contains a cycle.
  CyclicUse(String)
  /// A source entry contains malformed syntax (bad escape, bad number, ...).
  BadSyntax(String)
}

///|
/// Errors produced when expanding a parameterized capability string.
pub suberror ExpandError {
  /// A `%` sequence is malformed (truncated or unknown conversion).
  BadPercent(String)
  /// An operator popped from an empty stack, or a `%s` index is out of range.
  StackUnderflow(String)
  /// `%t`, `%e` or `%;` appears without a matching `%?`.
  Unbalanced(String)
}

///|
/// A parsed terminal description.
///
/// Standard capabilities are stored in arrays aligned with `bool_names`,
/// `num_names` and `str_names`, so parse/serialize round-trips are lossless
/// even for capabilities this library does not know by name. Extended
/// (user-defined) capabilities carry their own names and are stored in maps.
///
/// String capabilities are raw byte strings, exactly as stored on disk:
/// escape sequences and `%` parameter references are kept verbatim. Use
/// `tparm` to expand the latter.
pub struct Entry {
  /// Terminal names: primary name first, verbose name last.
  mut names : Array[String]
  /// Standard booleans, aligned with `bool_names`. 0 = absent/false, 1 = true, 2 = canceled.
  booleans : Array[Int]
  /// Standard numbers, aligned with `num_names`. -1 = absent, -2 = canceled.
  numbers : Array[Int]
  /// Standard strings, aligned with `str_names`. `None` = absent or canceled.
  strings : Array[Bytes?]
  /// Extended (user-defined) booleans, by name. 0 = false, 1 = true, 2 = canceled.
  ext_booleans : Map[String, Int]
  /// Extended (user-defined) numbers, by name. -1 = absent, -2 = canceled.
  ext_numbers : Map[String, Int]
  /// Extended (user-defined) strings, by name. Only present values.
  ext_strings : Map[String, Bytes]
  /// Names of extended strings whose value was canceled in the source.
  ext_canceled_strings : Array[String]
}

///|
/// One entry parsed from terminfo source format (the `terminfo.src` language).
/// Unlike a compiled `Entry`, capabilities are keyed by name directly and
/// string values keep their source escapes (use `unescape_value` to expand
/// them). Capability keys may be either long names (`columns`) or
/// two-character codes (`co`); both resolve to the same binary index when
/// compiling.
pub struct SourceEntry {
  /// Terminal names: primary name first, verbose name last.
  names : Array[String]
  /// Boolean capabilities, by name. 0 = false, 1 = true, 2 = canceled.
  booleans : Map[String, Int]
  /// Numeric capabilities, by name. -1/-2 sentinels preserved as written.
  numbers : Map[String, Int]
  /// String capabilities, by name, with source escapes intact.
  strings : Map[String, String]
  /// Targets of `use=` fields, in order of appearance.
  uses : Array[String]
  /// Names of string capabilities canceled with `name@` (standard or extended).
  canceled : Array[String]
}

///|
pub fn Entry::names(self : Entry) -> Array[String] {
  self.names
}

///|
/// The primary (first) terminal name.
pub fn Entry::primary_name(self : Entry) -> String {
  self.names[0]
}

///|
/// The verbose (last) name, as shown by `infocmp -d` style tools.
pub fn Entry::longname(self : Entry) -> String {
  self.names[self.names.length() - 1]
}

///|
fn Entry::bool_at(self : Entry, i : Int) -> Bool? {
  if i < self.booleans.length() {
    match self.booleans[i] {
      0 => Some(false)
      1 => Some(true)
      _ => None
    }
  } else {
    None
  }
}

///|
fn Entry::num_at(self : Entry, i : Int) -> Int? {
  if i < self.numbers.length() {
    let v = self.numbers[i]
    if v < 0 {
      None
    } else {
      Some(v)
    }
  } else {
    None
  }
}

///|
fn Entry::str_at(self : Entry, i : Int) -> Bytes? {
  if i < self.strings.length() {
    self.strings[i]
  } else {
    None
  }
}

///|
/// Look up a Boolean capability by long name (e.g. `auto_right_margin`) or
/// two-character terminfo code (e.g. `am`). Returns `None` when the
/// capability is absent or canceled.
pub fn Entry::get_bool(self : Entry, name : String) -> Bool? {
  if self.ext_booleans.contains(name) {
    let v = self.ext_booleans[name]
    return if v == 0 { Some(false) } else if v == 1 { Some(true) } else { None }
  }
  match bool_index.get(name) {
    Some(i) => Entry::bool_at(self, i)
    None =>
      match bool_code_index.get(name) {
        Some(i) => Entry::bool_at(self, i)
        None => None
      }
  }
}

///|
/// Look up a numeric capability by long name (e.g. `columns`) or code
/// (e.g. `cols`). Returns `None` when absent or canceled.
pub fn Entry::get_num(self : Entry, name : String) -> Int? {
  if self.ext_numbers.contains(name) {
    let v = self.ext_numbers[name]
    return if v < 0 { None } else { Some(v) }
  }
  match num_index.get(name) {
    Some(i) => Entry::num_at(self, i)
    None =>
      match num_code_index.get(name) {
        Some(i) => Entry::num_at(self, i)
        None => None
      }
  }
}

///|
/// Look up a string capability by long name (e.g. `cursor_address`) or code
/// (e.g. `cup`, `sgr0`). Returns `None` when absent or canceled. The value
/// is returned verbatim: escapes resolved, `%` sequences and `$<...>`
/// padding intact.
pub fn Entry::get_str(self : Entry, name : String) -> Bytes? {
  if self.ext_canceled_strings.contains(name) {
    return None
  }
  if self.ext_strings.contains(name) {
    return Some(self.ext_strings[name])
  }
  match str_index.get(name) {
    Some(i) => Entry::str_at(self, i)
    None =>
      match str_code_index.get(name) {
        Some(i) => Entry::str_at(self, i)
        None => None
      }
  }
}

///|
/// Look up a Boolean capability by its two-character terminfo code (e.g. `am`).
pub fn Entry::get_bool_code(self : Entry, code : String) -> Bool? {
  match bool_code_index.get(code) {
    Some(i) => Entry::bool_at(self, i)
    None => None
  }
}

///|
/// Look up a numeric capability by its two-character terminfo code (e.g. `co`).
pub fn Entry::get_num_code(self : Entry, code : String) -> Int? {
  match num_code_index.get(code) {
    Some(i) => Entry::num_at(self, i)
    None => None
  }
}

///|
/// Look up a string capability by its two-character terminfo code (e.g. `AF`).
pub fn Entry::get_str_code(self : Entry, code : String) -> Bytes? {
  match str_code_index.get(code) {
    Some(i) => Entry::str_at(self, i)
    None => None
  }
}

///|
/// An empty entry with standard-section arrays sized to the full
/// capability tables. Used as a base when compiling source entries.
pub fn empty() -> Entry {
  {
    names: [],
    booleans: Array::make(bool_names.length(), 0),
    numbers: Array::make(num_names.length(), -1),
    strings: Array::make(str_names.length(), None),
    ext_booleans: Map([]),
    ext_numbers: Map([]),
    ext_strings: Map([]),
    ext_canceled_strings: [],
  }
}
