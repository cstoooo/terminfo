///|
/// A pure-MoonBit implementation of the terminfo(5) terminal capability
/// format: the ncurses compiled binary format (legacy and extended) and the
/// terminfo source language (`terminfo.src`), together with a `tparm(3x)`
/// parameter interpreter.
///
/// The pieces fit together in three layers:
///
/// * `parse` / `to_bytes` - read and write compiled terminfo entries,
///   including user-defined (extended) capabilities. Everything is byte
///   level, so round-trips are lossless.
/// * `parse_source` / `compile` / `unescape_value` - parse the source
///   language that `terminfo.src` files are written in and compile one
///   entry (resolving `use=` inheritance) into an `Entry`.
/// * `tparm` / `strip_padding` - expand parameterized capability strings
///   into the escape sequences sent to a terminal.
///
/// The capability names, their binary indices, and the two-character
/// termcap/terminfo codes live in the generated tables `bool_names`,
/// `num_names`, `str_names` and the lookup maps `bool_index`, `num_index`,
/// `str_index`, `bool_code_index`, `num_code_index`, `str_code_index`.

///|
/// Remove `$<...>` padding specifications from a capability value.
///
/// Padding is timing information used by slow terminals; it is not part of
/// the output sequence. `tparm` skips padding specs too, so this is only
/// needed when emitting strings that contain no `%` sequences.
pub fn strip_padding(s : Bytes) -> Bytes {
  let out = Buffer(size_hint=s.length())
  let n = s.length()
  let mut i = 0
  while i < n {
    if s[i] == b'$' && i + 1 < n && s[i + 1] == b'<' {
      while i < n && s[i] != b'>' {
        i += 1
      }
      if i < n {
        i += 1
      }
      continue
    }
    out.write_byte(s[i])
    i += 1
  }
  out.to_bytes()
}
