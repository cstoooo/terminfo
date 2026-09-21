///|
/// terminfo - inspect terminal capabilities and emit their escape
/// sequences, a small tput-like demo for the terminfo library.
///
/// usage: terminfo [--term NAME] COMMAND [ARGS]
///
/// COMMAND is one of:
///   longname                 the terminal's verbose name
///   cols | lines | colors    a numeric capability
///   clear | smcup | rmcup | sgr0 | bold | init | reset
///                            the matching escape sequence
///   setaf N | setab N        a color-setting sequence
///   cup R C                  the cursor-positioning sequence
///   cap NAME [N ...]         any string capability, with numeric parameters
///   list-terms               the built-in terminal entries
///   dump                     the compiled binary entry, as hex
///
/// The terminal entry for TERM comes from the built-in table
/// (xterm-256color, xterm, linux, vt100, screen, ansi, adm3a). TERM is
/// taken from --term, then the TERM environment variable, then
/// xterm-256color.

///|
/// One built-in entry: a names line and a comma-separated fields line.
fn entry_line(names : String, fields : String) -> String {
  names + "\n\t" + fields
}

///|
/// The built-in terminal table, written in the terminfo source language.
fn builtin_source() -> String {
  [
    entry_line(
      "xterm-256color|xterm with 256 colors", "am, bce, km, mc5i, mir, msgr, npc, xenl, colors#256, cols#80, it#8, lines#24, pairs#32767, acsc=``aaffggiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~, bel=^G, blink=\\E[5m, bold=\\E[1m, civis=\\E[?25l, clear=\\E[H\\E[2J, cnorm=\\E[?12l\\E[?25h, cr=^M, csr=\\E[%i%p1%d;%p2%dr, cub1=^H, cud1=\\E[B, cuf1=\\E[C, cup=\\E[%i%p1%d;%p2%dH, cuu1=\\E[A, dch1=\\E[P, dl1=\\E[M, ed=\\E[J, el=\\E[K, el1=\\E[1K, flash=\\E[?5h$<100/>\\E[?5l, home=\\E[H, hpa=\\E[%i%p1%dG, ht=^I, hts=\\EH, ich1=\\E[@, il1=\\E[L, ind=^J, invis=\\E[8m, is2=\\E[!p\\E[?3;4l\\E[4l\\E>, kbs=^?, kcub1=\\EOD, kcud1=\\EOB, kcuf1=\\EOC, kcuu1=\\EOA, kdch1=\\E[3~, kend=\\EOF, kf1=\\EOP, kf10=\\E[21~, kf2=\\EOQ, kf3=\\EOR, kf4=\\EOS, khome=\\EOH, kich1=\\E[2~, kmous=\\E[M, knp=\\E[6~, kpp=\\E[5~, op=\\E[39;49m, rc=\\E8, rev=\\E[7m, ri=\\EM, rmacs=\\E(B, rmcup=\\E[?1049l, rmir=\\E[4l, rmkx=\\E[?1l\\E>, rmso=\\E[27m, rmul=\\E[24m, rs1=\\Ec, rs2=\\E[!p\\E[?3;4l\\E[4l\\E>, sc=\\E7, setab=\\E[4%p1%dm, setaf=\\E[3%p1%dm, sgr=\\E[%?%p1%t7;%;%?%p2%t4;%;%?%p3%t7;%;%?%p4%t5;%;%?%p6%t1;%;m, sgr0=\\E(B\\E[m, smacs=\\E(0, smcup=\\E[?1049h, smir=\\E[4h, smkx=\\E[?1h\\E=, smso=\\E[7m, smul=\\E[4m, tbc=\\E[3g,",
    ),
    entry_line(
      "xterm|xterm terminal emulator (X Window System)", "am, bce, km, mc5i, mir, msgr, npc, xenl, colors#8, cols#80, it#8, lines#24, pairs#64, acsc=``aaffggiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~, bel=^G, blink=\\E[5m, bold=\\E[1m, civis=\\E[?25l, clear=\\E[H\\E[2J, cnorm=\\E[?12l\\E[?25h, cr=^M, csr=\\E[%i%p1%d;%p2%dr, cub1=^H, cud1=\\E[B, cuf1=\\E[C, cup=\\E[%i%p1%d;%p2%dH, cuu1=\\E[A, dch1=\\E[P, dl1=\\E[M, ed=\\E[J, el=\\E[K, home=\\E[H, ht=^I, hts=\\EH, ich1=\\E[@, il1=\\E[L, ind=^J, kbs=^?, kcub1=\\EOD, kcud1=\\EOB, kcuf1=\\EOC, kcuu1=\\EOA, kdch1=\\E[3~, kend=\\EOF, kf1=\\EOP, kf10=\\E[21~, kf2=\\EOQ, kf3=\\EOR, kf4=\\EOS, khome=\\EOH, kich1=\\E[2~, knp=\\E[6~, kpp=\\E[5~, op=\\E[39;49m, rc=\\E8, rev=\\E[7m, ri=\\EM, rmacs=\\E(B, rmcup=\\E[?1049l, rmir=\\E[4l, rmkx=\\E[?1l\\E>, rmso=\\E[27m, rmul=\\E[24m, rs1=\\Ec, rs2=\\E[!p\\E[?3;4l\\E[4l\\E>, sc=\\E7, setab=\\E[4%p1%dm, setaf=\\E[3%p1%dm, sgr=\\E[%?%p1%t7;%;%?%p2%t4;%;%?%p3%t7;%;%?%p4%t5;%;%?%p6%t1;%;m, sgr0=\\E(B\\E[m, smacs=\\E(0, smcup=\\E[?1049h, smir=\\E[4h, smkx=\\E[?1h\\E=, smso=\\E[7m, smul=\\E[4m, tbc=\\E[3g,",
    ),
    entry_line(
      "linux|linux console", "am, bce, eo, mir, msgr, xenl, xon, colors#8, cols#80, it#8, lines#25, pairs#64, acsc=+\\020\\,\\021-\\030.^Y0\\333`\\004a\\261f\\370g\\361h\\260i\\316j\\331k\\277l\\332m\\300n\\305o~p\\304q\\304r\\304s_t\\303u\\264v\\301w\\302x\\263y\\363z\\362{\\343|\\330}\\234~\\376, bel=^G, clear=\\E[H\\E[J, cr=^M, csr=\\E[%i%p1%d;%p2%dr, cub1=^H, cud1=^J, cuf1=\\E[C, cup=\\E[%i%p1%d;%p2%dH, cuu1=\\E[A, dch1=\\E[P, dim=\\E[2m, dl1=\\E[M, ed=\\E[J, el=\\E[K, flash=\\E[?5h\\E[?5l$<200/>, home=\\E[H, hpa=\\E[%i%p1%dG, ht=^I, hts=\\EH, ich1=\\E[@, il1=\\E[L, ind=^J, kb2=\\E[G, kbs=^?, kcub1=\\E[D, kcud1=\\E[B, kcuf1=\\E[C, kcuu1=\\E[A, kdch1=\\E[3~, kend=\\E[4~, kf1=\\E[[A, kf10=\\E[21~, kf2=\\E[[B, kf3=\\E[[C, kf4=\\E[[D, kf5=\\E[[E, kf6=\\E[17~, kf7=\\E[18~, kf8=\\E[19~, kf9=\\E[20~, khome=\\E[1~, kich1=\\E[2~, knp=\\E[6~, kpp=\\E[5~, kspd=^Z, nel=^M^J, op=\\E[39;49m, rc=\\E8, rev=\\E[7m, ri=\\EM, rmacs=^O, rmso=\\E[27m, rmul=\\E[24m, sc=\\E7, setab=\\E[4%p1%dm, setaf=\\E[3%p1%dm, sgr0=\\E[m\\017, smacs=^N, smso=\\E[7m, smul=\\E[4m, tbc=\\E[3g, vpa=\\E[%i%p1%dd,",
    ),
    entry_line(
      "vt100|vt100-am|dec vt100 (w/advanced video)", "am, mc5i, msgr, xenl, xon, cols#80, it#8, lines#24, vt#3, acsc=``aaffggjjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~, bel=^G, blink=\\E[5m$<2>, bold=\\E[1m$<2>, clear=\\E[H\\E[J$<50>, cr=^M, csr=\\E[%i%p1%d;%p2%dr, cub=\\E[%p1%dD, cub1=^H, cud=\\E[%p1%dB, cud1=^J, cuf=\\E[%p1%dC, cuf1=\\E[C$<2>, cup=\\E[%i%p1%d;%p2%dH$<5>, cuu=\\E[%p1%dA, cuu1=\\E[A$<2>, ed=\\E[J$<50>, el=\\E[K$<3>, el1=\\E[1K$<3>, enacs=\\E(B\\E)0, home=\\E[H, ht=^I, hts=\\EH, ind=^J, ka1=\\EOq, ka3=\\EOs, kb2=\\EOr, kbs=^H, kc1=\\EOp, kc3=\\EOn, kcub1=\\EOD, kcud1=\\EOB, kcuf1=\\EOC, kcuu1=\\EOA, kent=\\EOM, kf0=\\EOy, kf1=\\EOP, kf10=\\EOx, kf2=\\EOQ, kf3=\\EOR, kf4=\\EOS, kf5=\\EOt, kf6=\\EOu, kf7=\\EOv, kf8=\\EOl, kf9=\\EOw, rc=\\E8, rev=\\E[7m$<2>, ri=\\EM$<5>, rmacs=^O, rmam=\\E[?7l, rmkx=\\E[?1l\\E>, rmso=\\E[m$<2>, rmul=\\E[m$<2>, rs2=\\E>\\E[?3l\\E[?4l\\E[?5l\\E[?7h\\E[?8h, sc=\\E7, sgr=\\E[0%?%p1%p6%|%t;1%;%?%p2%t;4%;%?%p1%p3%|%t;7%;%?%p4%t;5%;m%?%p9%t\\016%e\\017%;$<2>, sgr0=\\E[m\\017$<2>, smacs=^N, smam=\\E[?7h, smkx=\\E[?1h\\E=, smso=\\E[7m$<2>, smul=\\E[4m$<2>, tbc=\\E[3g,",
    ),
    entry_line(
      "screen|VT 100/ANSI X3.64 virtual terminal", "am, km, mir, msgr, xenl, colors#8, cols#80, it#8, lines#24, pairs#64, acsc=++\\,\\,--..00``aaffgghhiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~, bel=^G, blink=\\E[5m, bold=\\E[1m, civis=\\E[?25l, clear=\\E[H\\E[J, cnorm=\\E[34h\\E[?25h, cr=^M, csr=\\E[%i%p1%d;%p2%dr, cub=\\E[%p1%dD, cub1=^H, cud=\\E[%p1%dB, cud1=^J, cuf=\\E[%p1%dC, cuf1=\\E[C, cup=\\E[%i%p1%d;%p2%dH, cuu=\\E[%p1%dA, cuu1=\\EM, dch=\\E[%p1%dP, dch1=\\E[P, dl=\\E[%p1%dM, dl1=\\E[M, ed=\\E[J, el=\\E[K, el1=\\E[1K, enacs=\\E(B\\E)0, home=\\E[H, ht=^I, hts=\\EH, ich=\\E[%p1%d@, il=\\E[%p1%dL, il1=\\E[L, ind=^J, kbs=^?, kcub1=\\EOD, kcud1=\\EOB, kcuf1=\\EOC, kcuu1=\\EOA, kdch1=\\E[3~, kend=\\E[4~, kf1=\\EOP, kf10=\\E[21~, kf2=\\EOQ, kf3=\\EOR, kf4=\\EOS, kf5=\\E[15~, kf6=\\E[17~, kf7=\\E[18~, kf8=\\E[19~, kf9=\\E[20~, khome=\\E[1~, kich1=\\E[2~, knp=\\E[6~, kpp=\\E[5~, nel=\\EE, op=\\E[39;49m, rc=\\E8, rev=\\E[7m, ri=\\EM, rmacs=^O, rmcup=\\E[?1049l, rmir=\\E[4l, rmkx=\\E[?1l\\E>, rmso=\\E[23m, rmul=\\E[24m, rs2=\\Ec\\E[?1000l\\E[?25h, sc=\\E7, setab=\\E[4%p1%dm, setaf=\\E[3%p1%dm, sgr=\\E[0%?%p6%t;1%;%?%p1%t;7%;%?%p2%t;4%;%?%p3%t;7%;%?%p4%t;5%;%?%p5%t;2%;m%?%p9%t\\016%e\\017%;, sgr0=\\E[m\\017, smacs=^N, smcup=\\E[?1049h, smir=\\E[4h, smkx=\\E[?1h\\E=, smso=\\E[3m, smul=\\E[4m, tbc=\\E[3g,",
    ),
    entry_line(
      "ansi|ansi/pc-term compatible with color", "am, mc5i, mir, msgr, colors#8, cols#80, it#8, lines#24, pairs#64, acsc=+\\020\\,\\021-\\030.^Y0\\333`\\004a\\261f\\370g\\361h\\260j\\331k\\277l\\332m\\300n\\305o~q\\304r\\304s_t\\303u\\264v\\301w\\302x\\263y\\363z\\362{\\343|\\330}\\234~\\376, bel=^G, blink=\\E[5m, bold=\\E[1m, clear=\\E[H\\E[J, cr=^M, cub1=\\E[D, cud1=\\E[B, cuf1=\\E[C, cup=\\E[%i%p1%d;%p2%dH, cuu1=\\E[A, dch1=\\E[P, dl1=\\E[M, ed=\\E[J, el=\\E[K, home=\\E[H, ht=^I, hts=\\EH, ich1=\\E[@, il1=\\E[L, ind=\\E[S, kbs=^H, kcub1=\\E[D, kcud1=\\E[B, kcuf1=\\E[C, kcuu1=\\E[A, khome=\\E[H, rc=\\E[u, rev=\\E[7m, ri=\\E[T, rmso=\\E[m, rmul=\\E[m, sc=\\E[s, setab=\\E[4%p1%dm, setaf=\\E[3%p1%dm, sgr0=\\E[0;10m, smso=\\E[7m, smul=\\E[4m, tbc=\\E[2g,",
    ),
    entry_line(
      "adm3a|lsi adm3a", "am, cols#80, lines#24, bel=^G, clear=\\032$<1>, cr=^M, cub1=^H, cud1=^J, cuf1=^L, cup=\\E=%p1%{32}%+%c%p2%{32}%+%c, cuu1=^K, home=^^, ind=^J,",
    ),
  ].join("\n")
}

///|
fn parse_int(s : String) -> Int? {
  let n = s.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if s[0] == '-' || s[0] == '+' {
    neg = s[0] == '-'
    i += 1
  }
  if i >= n {
    return None
  }
  let mut v = 0
  while i < n {
    let c = s[i]
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10 + (c.to_int() - b'0'.to_int())
    i += 1
  }
  Some(if neg { -v } else { v })
}

///|
fn collect_params(args : Array[String], from : Int) -> Array[Int] {
  let out : Array[Int] = []
  for j = from; j < args.length(); j = j + 1 {
    match parse_int(args[j]) {
      Some(v) => out.push(v)
      None => {
        println("bad number: \{args[j]}")
        return []
      }
    }
  }
  out
}

///|
fn find_entry(entries : Array[@lib.SourceEntry], term : String) -> @lib.Entry? {
  for es in entries {
    if es.names[0] == term {
      return Some(@lib.compile(entries, term)) catch {
        err => {
          println("cannot compile \{term}: \{(err : Error).to_string()}")
          None
        }
      }
    }
  }
  // TERM values like screen-256color: retry with the color suffix dropped.
  if term.has_suffix("-256color") {
    return find_entry(entries, term[0:term.length() - 8].to_owned())
  }
  None
}

///|
/// Write raw capability bytes to stdout. Each byte is mapped to its Latin-1
/// code point so the UTF-8 output reproduces ASCII escape sequences
/// byte-for-byte, while high bytes render as the matching glyph on UTF-8
/// terminals.
fn print_raw(bytes : Bytes) -> Unit {
  let chars : Array[Char] = []
  for b in bytes {
    chars.push(b.to_int().unsafe_to_char())
  }
  println(String::from_array(chars))
}

///|
fn emit(entry : @lib.Entry, cap : String, params : Array[Int]) -> Unit {
  match entry.get_str(cap) {
    None => println("no such capability: \{cap}")
    Some(raw) =>
      print_raw(@lib.tparm(raw, params)) catch {
        e => println("cannot expand \{cap}: \{(e : Error).to_string()}")
      }
  }
}

///|
fn print_num(entry : @lib.Entry, cap : String) -> Unit {
  match entry.get_num(cap) {
    Some(v) => println(v)
    None => println("no such capability: \{cap}")
  }
}

///|
fn init_reset(entry : @lib.Entry, reset : Bool) -> Unit {
  if reset {
    emit(entry, "rs1", [])
    emit(entry, "rs2", [])
    emit(entry, "rs3", [])
    emit(entry, "rmcup", [])
    emit(entry, "sgr0", [])
  } else {
    emit(entry, "is1", [])
    emit(entry, "is2", [])
    emit(entry, "is3", [])
  }
  emit(entry, "clear", [])
}

///|
fn hex_digit(d : Int) -> Char {
  match d {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    7 => '7'
    8 => '8'
    9 => '9'
    10 => 'a'
    11 => 'b'
    12 => 'c'
    13 => 'd'
    14 => 'e'
    _ => 'f'
  }
}

///|
fn hex_of(bytes : Bytes) -> String {
  let buf = StringBuilder(size_hint=bytes.length() * 3)
  for i = 0; i < bytes.length(); i = i + 1 {
    if i > 0 {
      buf.write_char(' ')
    }
    let b = bytes[i].to_int()
    buf.write_char(hex_digit(b / 16))
    buf.write_char(hex_digit(b % 16))
  }
  buf.to_string()
}

///|
fn usage() -> Unit {
  println("usage: terminfo [--term NAME] COMMAND [ARGS]")
  println("commands: longname, cols, lines, colors, clear, smcup, rmcup,")
  println("          sgr0, bold, init, reset, setaf N, setab N, cup R C,")
  println("          cap NAME [N ...], list-terms, dump")
}

///|
fn main {
  let args = @env.args()
  let mut i = 1
  let mut term_opt : String? = None
  while i < args.length() &&
        args[i].length() >= 2 &&
        args[i][0:2].to_owned() == "--" {
    let flag = args[i]
    if flag == "--term" && i + 1 < args.length() {
      term_opt = Some(args[i + 1])
      i += 2
    } else if flag.length() > 7 && flag[0:7].to_owned() == "--term=" {
      term_opt = Some(flag[7:].to_owned())
      i += 1
    } else {
      break
    }
  }
  let cmd = if i < args.length() { args[i] } else { "" }

  let entries = @lib.parse_source(builtin_source()) catch {
    e => {
      println("built-in table failed to parse: \{(e : Error).to_string()}")
      return
    }
  }
  let term = match term_opt {
    Some(t) => t
    None =>
      match @env.get_env_var("TERM") {
        Some(t) => t
        None => "xterm-256color"
      }
  }
  let entry = match find_entry(entries, term) {
    Some(e) => e
    None => {
      println("no built-in entry for TERM=\{term}; built-in entries:")
      for es in entries {
        println("  \{es.names[0]}")
      }
      return
    }
  }

  match cmd {
    "longname" => println(entry.longname())
    "cols" => print_num(entry, "columns")
    "lines" => print_num(entry, "lines")
    "colors" => print_num(entry, "colors")
    "clear" => emit(entry, "clear", [])
    "smcup" => emit(entry, "smcup", [])
    "rmcup" => emit(entry, "rmcup", [])
    "sgr0" => emit(entry, "sgr0", [])
    "bold" => emit(entry, "bold", [])
    "setaf" => emit(entry, "setaf", collect_params(args, i + 1))
    "setab" => emit(entry, "setab", collect_params(args, i + 1))
    "cup" => emit(entry, "cup", collect_params(args, i + 1))
    "cap" =>
      if i + 1 < args.length() {
        emit(entry, args[i + 1], collect_params(args, i + 2))
      } else {
        println("cap: missing capability name")
      }
    "init" => init_reset(entry, false)
    "reset" => init_reset(entry, true)
    "list-terms" =>
      for es in entries {
        println(es.names[0])
      }
    "dump" =>
      println(hex_of(@lib.to_bytes(entry))) catch {
        e => println("dump failed: \{(e : Error).to_string()}")
      }
    _ => usage()
  }
}
