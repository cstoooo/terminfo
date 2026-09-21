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
