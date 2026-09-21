///|
/// Run `thunk`; fail the test with the error if it raises.
fn[T] wok_of(thunk : () -> T raise Error) -> T {
  thunk() catch {
    err => abort(err.to_string())
  }
}

///|
test "split_fields keeps escaped commas together" {
  assert_eq(split_fields("a,b\\,c,d"), ["a", "b\\,c", "d"])
  // Octal escapes (up to three digits) also protect the following comma.
  assert_eq(split_fields("x=\\032y,z"), ["x=\\032y", "z"])
  assert_eq(split_fields("one"), ["one"])
  assert_eq(split_fields(""), [""])
}

///|
test "parse_num handles bases, signs and errors" {
  assert_eq(wok_of(fn() raise { parse_num("80") }), 80)
  assert_eq(wok_of(fn() raise { parse_num("0x10") }), 16)
  assert_eq(wok_of(fn() raise { parse_num("0x1A") }), 26)
  assert_eq(wok_of(fn() raise { parse_num("010") }), 8)
  assert_eq(wok_of(fn() raise { parse_num("0") }), 0)
  assert_eq(wok_of(fn() raise { parse_num("-5") }), -5)
  assert_eq(wok_of(fn() raise { parse_num("+5") }), 5)
  assert_eq(wok_of(fn() raise { parse_num("0x7fffffff") }), 0x7FFFFFFF)
  try {
    parse_num("12x") |> ignore
    abort("expected BadSyntax")
  } catch {
    ParseError::BadSyntax(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
  try {
    parse_num("0x") |> ignore
    abort("expected BadSyntax")
  } catch {
    ParseError::BadSyntax(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
  try {
    parse_num("0x80000000") |> ignore
    abort("expected BadSyntax")
  } catch {
    ParseError::BadSyntax(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
}

///|
test "split_lines handles CRLF and a missing final newline" {
  assert_eq(split_lines("a\r\nb\nc"), ["a", "b", "c"])
  assert_eq(split_lines("a\r\n"), ["a"])
  assert_eq(split_lines("abc"), ["abc"])
  assert_eq(split_lines(""), [])
}

///|
test "make_blocks groups entries and skips comments and blanks" {
  let blocks = make_blocks([
    "# comment", "", "e1|one,", "\tcols#80,", "e2|two,", "\tam,",
  ])
  assert_eq(blocks.length(), 2)
  assert_eq(blocks[0].length(), 2)
  assert_eq(blocks[1].length(), 2)
}

///|
test "trim_ws strips blanks" {
  assert_eq(trim_ws("  x  "), "x")
  assert_eq(trim_ws("\t\t"), "")
}

///|
test "parse_block reads names, numbers, booleans and uses" {
  let block = ["e1|one|verbose,", "\tcols#80, am, use=base, cr=^M,"]
  let se = wok_of(fn() raise { parse_block(block) })
  assert_eq(se.names, ["e1", "one", "verbose"])
  assert_eq(se.numbers["cols"], 80)
  assert_eq(se.booleans["am"], 1)
  assert_eq(se.strings["cr"], "^M")
  assert_eq(se.uses, ["base"])
}

///|
test "parse_block handles two-character codes and cancellations" {
  let block = ["e1|one,", "\tco#80, li#24, msgr, kf1=\\EOP, li@,"]
  let se = wok_of(fn() raise { parse_block(block) })
  assert_eq(se.numbers["co"], 80)
  assert_eq(se.numbers["li"], -2)
  assert_eq(se.booleans["msgr"], 1)
  assert_eq(se.strings["kf1"], "\\EOP")
}

///|
test "parse_block ignores stray whitespace and trailing commas" {
  let block = ["e1|one,", "\t cols#80 , lines#24 , bel=^G , ,"]
  let se = wok_of(fn() raise { parse_block(block) })
  assert_eq(se.numbers["cols"], 80)
  assert_eq(se.numbers["lines"], 24)
  assert_eq(se.strings["bel"], "^G")
}
