///|
/// Decode a hex string (pairs of digits) into bytes; used to build the
/// golden vectors below.
fn hex_to_bytes(hex : String) -> Bytes {
  let buf = Buffer::Buffer(size_hint=hex.length() / 2)
  let mut i = 0
  while i + 1 < hex.length() {
    buf.write_byte(
      (hex_val(hex[i].to_int()) * 16 + hex_val(hex[i + 1].to_int())).to_byte(),
    )
    i += 2
  }
  buf.to_bytes()
}

///|
fn hex_val(c : Int) -> Int {
  if c >= b'0'.to_int() && c <= b'9'.to_int() {
    c - b'0'.to_int()
  } else if c >= b'a'.to_int() && c <= b'f'.to_int() {
    10 + c - b'a'.to_int()
  } else if c >= b'A'.to_int() && c <= b'F'.to_int() {
    10 + c - b'A'.to_int()
  } else {
    abort("bad hex digit")
  }
}

///|
/// Run `thunk`; fail the test with the error if it raises.
fn[T] expect_ok(thunk : () -> T raise Error) -> T {
  thunk() catch {
    err => abort(err.to_string())
  }
}

///|
/// The compiled form of the LSI ADM-3a entry shown in the EXAMPLES section
/// of term(5): a byte-for-byte reference vector produced by tic.
fn adm3a_golden() -> Bytes {
  hex_to_bytes(
    "1a011000020003008200310061646d33617c6c73692061646d33610000015000ffff1800ffff00000200ffffffff0400" +
    "ffffffffffffffff0a0025002700ffff2900ffffffff2b00ffff2d00ffffffffffffffffffffffffffffffffffffffff" +
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" +
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" +
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" +
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" +
    "ffffffffffff2f0007000d001a243c313e001b3d257031257b33327d252b2563257032257b33327d252b2563000a001e" +
    "0008000c000b000a00",
  )
}

///|
/// The source form of the same entry, as quoted in term(5).
fn adm3a_source() -> String {
  "adm3a|lsi adm3a,\n\tam,\n\tcols#80, lines#24,\n\tbel=^G, clear=\\032$<1>, cr=^M, cub1=^H, cud1=^J,\n\tcuf1=^L, cup=\\E=%p1%{32}%+%c%p2%{32}%+%c, cuu1=^K,\n\thome=^^, ind=^J,\n"
}

///|
/// Compiling the term(5) example entry reproduces the compiled bytes from
/// the man page exactly.
test "adm3a compiles to the term(5) reference bytes" {
  let entry = expect_ok(fn() raise {
    @terminfo.compile(@terminfo.parse_source(adm3a_source()), "adm3a")
  })
  assert_eq(expect_ok(fn() raise { @terminfo.to_bytes(entry) }), adm3a_golden())
}

///|
test "parse reads the term(5) reference bytes" {
  let entry = expect_ok(fn() raise { @terminfo.parse(adm3a_golden()) })
  assert_eq(entry.names(), ["adm3a", "lsi adm3a"])
  assert_eq(entry.primary_name(), "adm3a")
  assert_eq(entry.longname(), "lsi adm3a")
  assert_eq(entry.get_bool("auto_right_margin"), Some(true))
  assert_eq(entry.get_bool("auto_left_margin"), Some(false))
  assert_eq(entry.get_bool_code("am"), Some(true))
  assert_eq(entry.get_num("columns"), Some(80))
  assert_eq(entry.get_num("lines"), Some(24))
  assert_eq(entry.get_num("init_tabs"), None)
  assert_eq(entry.get_str("bell"), Some(b"\x07"))
  assert_eq(entry.get_str("clear"), Some(b"\x1a$<1>"))
  assert_eq(entry.get_str("cup"), Some(b"\x1b=%p1%{32}%+%c%p2%{32}%+%c"))
  assert_eq(entry.get_str_code("cm"), Some(b"\x1b=%p1%{32}%+%c%p2%{32}%+%c"))
  assert_eq(entry.get_str("home"), Some(b"\x1e"))
  assert_eq(entry.get_str("ind"), Some(b"\x0a"))
  assert_eq(entry.get_str("change_scroll_region"), None)
}

///|
/// Parsing the reference bytes and writing them again reproduces the file.
test "compiled entries round-trip byte-for-byte" {
  let entry = expect_ok(fn() raise { @terminfo.parse(adm3a_golden()) })
  assert_eq(expect_ok(fn() raise { @terminfo.to_bytes(entry) }), adm3a_golden())
}

///|
/// Capabilities this library does not know are kept as extended (user
/// defined) capabilities with their names, and survive a round-trip.
test "extended capabilities round-trip" {
  let src = "mytest|my test terminal,\n\tcols#80, myflag, mynum#42, mystr=hello\\, world,\n"
  let entry = expect_ok(fn() raise {
    @terminfo.compile(@terminfo.parse_source(src), "mytest")
  })
  assert_eq(entry.get_bool("myflag"), Some(true))
  assert_eq(entry.get_num("mynum"), Some(42))
  assert_eq(entry.get_str("mystr"), Some(b"hello, world"))
  let again = expect_ok(fn() raise {
    @terminfo.parse(@terminfo.to_bytes(entry))
  })
  assert_eq(again.get_bool("myflag"), Some(true))
  assert_eq(again.get_num("mynum"), Some(42))
  assert_eq(again.get_str("mystr"), Some(b"hello, world"))
}

///|
/// A canceled extended string keeps its name so that inheritance can be
/// negated, and survives a round-trip.
test "canceled extended strings round-trip" {
  let src = "mytest|my test terminal,\n\tgone=old, gone@, mystr=hi,\n"
  let entry = expect_ok(fn() raise {
    @terminfo.compile(@terminfo.parse_source(src), "mytest")
  })
  assert_eq(entry.get_str("gone"), None)
  assert_eq(entry.get_str("mystr"), Some(b"hi"))
  let again = expect_ok(fn() raise {
    @terminfo.parse(@terminfo.to_bytes(entry))
  })
  assert_eq(again.get_str("gone"), None)
  assert_eq(again.get_str("mystr"), Some(b"hi"))
}

///|
/// Empty string values are legitimate (e.g. `sgr0=`); they must survive
/// the round-trip.
test "empty string values round-trip" {
  let src = "mytest|my test terminal,\n\tbel=, cols#80,\n"
  let entry = expect_ok(fn() raise {
    @terminfo.compile(@terminfo.parse_source(src), "mytest")
  })
  assert_eq(entry.get_str("bell"), Some(b""))
  assert_eq(
    entry.get_str("bell"),
    expect_ok(fn() raise { @terminfo.parse(@terminfo.to_bytes(entry)) }).get_str(
      "bell",
    ),
  )
}

///|
/// `use=` merges earlier entries first; own capabilities override
/// inherited ones; earlier `use=` targets win over later ones.
test "use= inheritance and overrides" {
  let src = "b1|base one,\n\tcols#80, bel=^G,\n" +
    "b2|base two,\n\tcols#100, cr=^M,\n" +
    "d|derived,\n\tuse=b1, use=b2, cols#132,\n"
  let entry = expect_ok(fn() raise {
    @terminfo.compile(@terminfo.parse_source(src), "d")
  })
  assert_eq(entry.get_num("columns"), Some(132))
  assert_eq(entry.get_str("bell"), Some(b"\x07"))
  assert_eq(entry.get_str("carriage_return"), Some(b"\x0d"))
}

///|
/// Cancellations (`name@`) negate inherited values.
test "use= with name@ cancellation" {
  let src = "base|base terminal,\n\tcols#80, lines#24, bel=^G,\n" +
    "derived|derived terminal,\n\tuse=base, lines@, bel@,\n"
  let entry = expect_ok(fn() raise {
    @terminfo.compile(@terminfo.parse_source(src), "derived")
  })
  assert_eq(entry.get_num("columns"), Some(80))
  assert_eq(entry.get_num("lines"), None)
  assert_eq(entry.get_str("bell"), None)
}

///|
test "use= cycle is detected" {
  let src = "a|entry a,\n\tuse=b,\nb|entry b,\n\tuse=a,\n"
  try {
    @terminfo.compile(@terminfo.parse_source(src), "a") |> ignore
    abort("expected CyclicUse")
  } catch {
    @terminfo.ParseError::CyclicUse(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
}

///|
test "use target must exist" {
  let src = "x|entry x,\n\tcols#80,\n"
  try {
    @terminfo.compile(@terminfo.parse_source(src), "nope") |> ignore
    abort("expected BadSyntax")
  } catch {
    @terminfo.ParseError::BadSyntax(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
}

///|
/// Numbers too wide for the legacy 16-bit format switch the file to the
/// 32-bit magic (0o1036) and round-trip.
test "32-bit numbers select the int32 magic" {
  let src = "big|big numbers,\n\tcols#80, mynum#40000,\n"
  let entry = expect_ok(fn() raise {
    @terminfo.compile(@terminfo.parse_source(src), "big")
  })
  let bytes = expect_ok(fn() raise { @terminfo.to_bytes(entry) })
  assert_eq(bytes[0], b'\x1e')
  assert_eq(bytes[1], b'\x02')
  let again = expect_ok(fn() raise { @terminfo.parse(bytes) })
  assert_eq(again.get_num("mynum"), Some(40000))
  assert_eq(again.get_num("columns"), Some(80))
}

///|
test "NUL inside a string capability is rejected" {
  let src = "bad|bad entry,\n\tbel=\\000,\n"
  try {
    @terminfo.to_bytes(@terminfo.compile(@terminfo.parse_source(src), "bad"))
    |> ignore
    abort("expected BadCount")
  } catch {
    @terminfo.ParseError::BadCount(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
}

///|
test "bad magic and truncated files are rejected" {
  try {
    @terminfo.parse(b"\x1b\x02nope") |> ignore
    abort("expected BadMagic")
  } catch {
    @terminfo.ParseError::BadMagic(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
  try {
    @terminfo.parse(hex_to_bytes("1a0110000200030082003100")) |> ignore
    abort("expected Truncated")
  } catch {
    @terminfo.ParseError::Truncated => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
}

///|
test "source escapes expand" {
  assert_eq(
    expect_ok(fn() raise { @terminfo.unescape_value("\\E[2J") }),
    b"\x1b[2J",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.unescape_value("\\n\\l\\r\\t\\b\\f") }),
    b"\n\n\r\t\b\f",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.unescape_value("\\s\\:\\^\\\\") }),
    b" :^\\",
  )
  assert_eq(expect_ok(fn() raise { @terminfo.unescape_value("\\,") }), b",")
  assert_eq(expect_ok(fn() raise { @terminfo.unescape_value("\\|") }), b"|")
  assert_eq(
    expect_ok(fn() raise { @terminfo.unescape_value("\\032") }),
    b"\x1a",
  )
  assert_eq(expect_ok(fn() raise { @terminfo.unescape_value("\\0") }), b"\x00")
  assert_eq(expect_ok(fn() raise { @terminfo.unescape_value("^G") }), b"\x07")
  assert_eq(expect_ok(fn() raise { @terminfo.unescape_value("^?") }), b"\x7f")
  assert_eq(
    expect_ok(fn() raise { @terminfo.unescape_value("plain") }),
    b"plain",
  )
  try {
    @terminfo.unescape_value("\\q") |> ignore
    abort("expected BadSyntax")
  } catch {
    @terminfo.ParseError::BadSyntax(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
}

///|
/// A full source file: comments and blank lines are skipped, continuation
/// lines join their entry, and CRLF line endings are accepted.
test "parse_source handles comments, blanks and CRLF" {
  let src = "# a header comment\r\n" +
    "base|base terminal,\r\n\tcols#80, lines#24,\r\n\r\n" +
    "# another comment\r\n" +
    "solo|solo entry,\r\n\tam,\r\n"
  let entries = expect_ok(fn() raise { @terminfo.parse_source(src) })
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].names, ["base", "base terminal"])
  assert_eq(entries[1].names, ["solo", "solo entry"])
}

///|
test "tparm prints numbers and characters" {
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%p1%d", [42]) }), b"42")
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%{32}%+%c", [5]) }),
    b"%",
  )
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%'a'%c", []) }), b"a")
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"100%%", []) }), b"100%")
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%Pa%ga%d", [7]) }),
    b"7",
  )
}

///|
/// The adm3a cursor addressing string with its `%{32}%+` row/column
/// adjustment, as used by term(5) itself.
test "tparm expands the adm3a cup string" {
  let cup = expect_ok(fn() raise {
    @terminfo.unescape_value("\\E=%p1%{32}%+%c%p2%{32}%+%c")
  })
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(cup, [5, 10]) }), b"\x1b=%*")
}

///|
test "tparm conditionals" {
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%?%p1%tYES%eNO%;", [1]) }),
    b"YES",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%?%p1%tYES%eNO%;", [0]) }),
    b"NO",
  )
  assert_eq(
    expect_ok(fn() raise {
      @terminfo.tparm(b"%?%p1%t%?%p2%tAB%eCD%;%eXY%;", [1, 0])
    }),
    b"CD",
  )
  assert_eq(
    expect_ok(fn() raise {
      @terminfo.tparm(b"%?%p1%t%?%p2%tAB%eCD%;%eXY%;", [0, 1])
    }),
    b"XY",
  )
  assert_eq(
    expect_ok(fn() raise {
      @terminfo.tparm(b"%?%p1%t%?%p2%tAB%eCD%;%eXY%;", [1, 1])
    }),
    b"AB",
  )
  // The not-taken branch must be parsed but not executed.
  assert_eq(
    expect_ok(fn() raise {
      @terminfo.tparm(b"%?%p1%t%p2%d%e%p3%d%;", [1, 5, 9])
    }),
    b"5",
  )
  assert_eq(
    expect_ok(fn() raise {
      @terminfo.tparm(b"%?%p1%t%p2%d%e%p3%d%;", [0, 5, 9])
    }),
    b"9",
  )
}

///|
test "tparm increments and string parameters" {
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%i%p1%d,%p2%d", [1, 1]) }),
    b"2,2",
  )
  assert_eq(
    expect_ok(fn() raise {
      @terminfo.tparm(b"%p1%s", [0], string_params=[b"hi"])
    }),
    b"hi",
  )
  assert_eq(
    expect_ok(fn() raise {
      @terminfo.tparm(b"%p1%l%d", [0], string_params=[b"abc"])
    }),
    b"3",
  )
}

///|
test "tparm arithmetic and logic" {
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%*%d", [6, 7]) }),
    b"42",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%/%d", [7, 2]) }),
    b"3",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%m%d", [7, 3]) }),
    b"1",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%-%d", [10, 3]) }),
    b"7",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%&%d", [6, 3]) }),
    b"2",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%|%d", [6, 3]) }),
    b"7",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%^%d", [6, 3]) }),
    b"5",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%>%d", [3, 2]) }),
    b"1",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%<%d", [2, 3]) }),
    b"1",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%=%d", [3, 3]) }),
    b"1",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%A%d", [1, 1]) }),
    b"1",
  )
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"%p1%p2%O%d", [0, 1]) }),
    b"1",
  )
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%p1%!%d", [0]) }), b"1")
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%p1%~%d", [0]) }), b"-1")
}

///|
test "tparm printf-style flags" {
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%-5d", [42]) }), b"42   ")
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%5d", [42]) }), b"   42")
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%+d", [42]) }), b"+42")
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%+d", [-42]) }), b"-42")
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"% d", [42]) }), b" 42")
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%.3d", [42]) }), b"042")
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%d", [-42]) }), b"-42")
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%#x", [42]) }), b"0x2a")
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%X", [255]) }), b"FF")
  assert_eq(expect_ok(fn() raise { @terminfo.tparm(b"%o", [8]) }), b"10")
}

///|
/// `$<...>` padding specifications are timing information, not output.
test "tparm skips padding and strip_padding removes it" {
  assert_eq(
    expect_ok(fn() raise { @terminfo.tparm(b"\x1b[2J$<50>\x1b[H", []) }),
    b"\x1b[2J\x1b[H",
  )
  assert_eq(@terminfo.strip_padding(b"a$<5>b"), b"ab")
  assert_eq(@terminfo.strip_padding(b"no padding"), b"no padding")
}

///|
test "tparm rejects malformed strings" {
  try {
    @terminfo.tparm(b"%q", []) |> ignore
    abort("expected BadPercent")
  } catch {
    @terminfo.ExpandError::BadPercent(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
  try {
    @terminfo.tparm(b"%p1%d", []) |> ignore
    abort("expected StackUnderflow")
  } catch {
    @terminfo.ExpandError::StackUnderflow(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
  try {
    @terminfo.tparm(b"%t", []) |> ignore
    abort("expected Unbalanced")
  } catch {
    @terminfo.ExpandError::Unbalanced(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
  try {
    @terminfo.tparm(b"%?%p1%tYES%eNO;", [0]) |> ignore
    abort("expected Unbalanced")
  } catch {
    @terminfo.ExpandError::Unbalanced(_) => ()
    err => abort("wrong error: " + (err : Error).to_string())
  }
}
