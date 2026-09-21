# terminfo

A pure-MoonBit implementation of the terminfo(5) terminal capability format:
the ncurses compiled binary format, the terminfo source language
(`terminfo.src`), and a `tparm(3x)` parameter interpreter.

```moonbit nocheck
///|
let entry = @terminfo.compile(@terminfo.parse_source(src), "adm3a")

///|
let bytes = @terminfo.to_bytes(entry) // a compiled terminfo entry

///|
let parsed = @terminfo.parse(bytes) // read it back, losslessly

///|
let seq = @terminfo.tparm( // expand a capability value
  parsed.get_str("cup").unwrap(),
  [5, 10],
)
```

## API

Three layers, all byte-exact so round-trips are lossless:

### Compiled binary format (`parse` / `to_bytes`)

Reads and writes ncurses compiled entries — both magic numbers (16-bit and
32-bit numbers), the extended storage section for user-defined capabilities,
and entries that omit it entirely. Standard capabilities live in arrays
aligned with the generated capability tables; unknown (user-defined)
capabilities keep their names in `ext_booleans` / `ext_numbers` /
`ext_strings`.

### Source language (`parse_source` / `compile` / `unescape_value`)

Parses the language that `terminfo.src` files are written in: name lines,
comma-separated capability fields (`name`, `name#N`, `name=value`, `name@`),
`\E`-style escapes and `^X` control notation, and `use=` inheritance with
cycle detection. `compile` resolves a full inheritance chain into a single
`Entry`; earlier `use=` targets win, and `name@` cancels inherited values.
Capability fields accept long names (`columns`), two-character codes
(`cols`), and termcap names (`co`).

### Parameter expansion (`tparm` / `strip_padding`)

Expands parameterized string capabilities per terminfo(5): `%p1`-`%p9`,
`%P`/`%g` variables, `%'c'`, `%{nn}`, `%l`, arithmetic/bitwise/logical
operators, `%i`, `%c`, `%d`/`%o`/`%x`/`%X` with printf-style flags, `%s`,
`%%`, and nested `%?` conditionals with `%t`/`%e`/`%;`. `$<...>` padding
specs are timing information and are skipped (or removed with
`strip_padding`).

```moonbit nocheck
@terminfo.tparm(b"\x1b[%p1%{32}%+%c", [1])     // b"\x1b[!"
@terminfo.tparm(b"%?%p1%tYES%eNO%;", [0])      // b"NO"
```

## Capability tables

`caps.mbt` is generated from the ncurses `Caps` table (MIT/X11 license),
which is the source of truth for term.h. The order of each table defines
the binary index of a capability in a compiled file and is fixed for SVr4
binary compatibility. Regenerate with:

```
python scripts/gen_caps.py Caps > caps.mbt
```

## CLI demo

A small tput-like tool ships in `cmd/main` with a built-in table of common
terminals:

```
moon run cmd/main -- --term xterm-256color clear
moon run cmd/main -- --term adm3a cup 5 10
moon run cmd/main -- --term linux setaf 4
```

## Testing

```
moon test        # 31 tests: golden vectors from term(5), round-trips, tparm
```

The golden adm3a entry quoted in the term(5) man page compiles to the
exact bytes produced by `tic`, parses back, and round-trips byte-for-byte.
