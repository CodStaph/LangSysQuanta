use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use ls_sem::abi::{layout, map_scalar, CType};
use ls_sem::cap_context::{Capability, Knobs, Module, ModuleTree};
use ls_sem::surface::{check_source, line_col, CheckOptions};
use ls_sem::target::{all, by_triple};
use ls_sem::{demo_bad, selftest};

fn usage() {
    eprintln!(
        "ls-sem 0.1 (skeleton)\n\
         usage:\n\
           ls-sem selftest              run Sigma/H/Aliases*, Q2, Q6, Q7 self-checks\n\
           ls-sem demo                  replay t4-proof.md bad()\n\
           ls-sem targets               print the v0 target matrix\n\
           ls-sem abi <triple> <ctype>  map a C type (e.g. char, long, size_t)\n\
           ls-sem caps                  run a Q2 module-cap demo\n\
           ls-sem check <file.ls> [--arena-budget N]\n\
                                  parse and semantically check the L-Sys subset\n\
           ls-sem --help"
    );
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        usage();
        return ExitCode::SUCCESS;
    }
    match args[0].as_str() {
        "selftest" => {
            let checks: [(&str, fn() -> Result<(), String>); 3] = [
                ("core", selftest),
                ("runtime", ls_sem::runtime::selftest),
                ("q2", ls_sem::cap_context::selftest),
            ];
            for (name, check) in checks {
                if let Err(e) = check() {
                    println!("ls-sem selftest: FAIL {}: {}", name, e);
                    return ExitCode::from(1);
                }
            }
            for (name, check) in [
                ("q6", ls_sem::abi::selftest as fn() -> Result<(), String>),
                ("q7", ls_sem::target::selftest as fn() -> Result<(), String>),
            ] {
                if let Err(e) = check() {
                    println!("ls-sem selftest: FAIL {}: {}", name, e);
                    return ExitCode::from(1);
                }
            }
            println!("ls-sem selftest: PASS (core, runtime, q2, q6, q7)");
            ExitCode::SUCCESS
        }
        "demo" => {
            let demo = demo_bad();
            for line in &demo.log {
                println!("{}", line);
            }
            if demo.accepted {
                println!("RESULT ACCEPT");
                ExitCode::from(1)
            } else {
                let aliases = demo
                    .aliases
                    .iter()
                    .map(|a| a.to_string())
                    .collect::<Vec<_>>()
                    .join(", ");
                println!("RESULT REJECT E-LS-UNIQ: Aliases* = {{{}}}", aliases);
                ExitCode::SUCCESS
            }
        }
        "targets" => {
            println!(
                "{:<34} {:<12} {:>4} {:>4} {:<6} {:<5} {:>5}",
                "triple", "arch", "ptr", "long", "float", "atom", "char"
            );
            for t in all() {
                println!(
                    "{:<34} {:<12} {:>4} {:>4} {:<6} {:<5} {:>5}",
                    t.triple,
                    t.arch,
                    t.model.pointer_bits,
                    t.model.long_bits,
                    format!("{:?}", t.float).to_lowercase(),
                    format!("{:?}", t.atomics).to_lowercase(),
                    if t.model.char_signed {
                        "signed"
                    } else {
                        "unsigned"
                    }
                );
            }
            ExitCode::SUCCESS
        }
        "abi" => {
            let Some(triple) = args.get(1) else {
                eprintln!("ls-sem abi: missing triple (see `ls-sem targets`)");
                return ExitCode::from(2);
            };
            let Some(t) = by_triple(triple) else {
                eprintln!("ls-sem abi: unknown target {:?}", triple);
                return ExitCode::from(2);
            };
            let Some(cname) = args.get(2) else {
                eprintln!("ls-sem abi: missing C type");
                return ExitCode::from(2);
            };
            let Some(cty) = CType::from_name(cname) else {
                eprintln!("ls-sem abi: unknown C type {:?}", cname);
                return ExitCode::from(2);
            };
            match (map_scalar(t, cty), layout(t, cty)) {
                (Ok(ty), Ok((size, align))) => {
                    println!(
                        "{}: {} -> {} (size {}, align {})",
                        t.triple, cty, ty, size, align
                    );
                    ExitCode::SUCCESS
                }
                (Err(e), _) | (_, Err(e)) => {
                    println!("{}: {}", t.triple, e);
                    ExitCode::from(1)
                }
            }
        }
        "caps" => {
            let mut tree = ModuleTree::new();
            tree.add(Module::new("drivers").cap(Capability::Unsafe));
            tree.add(Module::new("drivers.uart"));
            tree.add(Module::new("kern").forbid_unsafe());
            tree.add(Module::new("kern.sub").cap(Capability::Unsafe));
            tree.add(Module::new("safe"));
            tree.add(Module::new("safe.sub").knobs(Knobs {
                bounds_off: true,
                ..Knobs::default()
            }));
            let diags = tree.validate();
            println!(
                "Q2 demo: drivers.uart unsafe={} kern.sub unsafe={} diagnostics={}",
                tree.allows_unsafe("drivers.uart"),
                tree.allows_unsafe("kern.sub"),
                diags.len()
            );
            for d in diags {
                println!("  {}: {}", d.code, d.message);
            }
            ExitCode::SUCCESS
        }
        "check" => {
            let Some(path) = args.get(1) else {
                eprintln!("ls-sem check: missing file");
                return ExitCode::from(2);
            };
            let mut options = CheckOptions::default();
            let mut i = 2;
            while i < args.len() {
                if args[i] == "--arena-budget" {
                    let Some(value) = args.get(i + 1) else {
                        eprintln!("ls-sem check: --arena-budget needs a byte count");
                        return ExitCode::from(2);
                    };
                    match value.parse::<usize>() {
                        Ok(n) => options.arena_budget = n,
                        Err(_) => {
                            eprintln!("ls-sem check: invalid --arena-budget {:?}", value);
                            return ExitCode::from(2);
                        }
                    }
                    i += 2;
                } else {
                    eprintln!("ls-sem check: unknown option {:?}", args[i]);
                    return ExitCode::from(2);
                }
            }
            let path = PathBuf::from(path);
            let src = match fs::read_to_string(&path) {
                Ok(src) => src,
                Err(e) => {
                    eprintln!("ls-sem check: cannot read {}: {}", path.display(), e);
                    return ExitCode::from(2);
                }
            };
            let report = check_source(&src, options);
            for d in &report.diagnostics {
                let (line, col) = line_col(&src, d.span.start);
                let fixit = d
                    .fixit
                    .as_deref()
                    .map(|f| format!(" [fix-it: {}]", f))
                    .unwrap_or_default();
                eprintln!(
                    "{}:{}:{}: {}: {}{}",
                    path.display(),
                    line,
                    col,
                    d.code,
                    d.message,
                    fixit
                );
            }
            println!(
                "ls-sem check: {} function(s), {} region(s), arena {}/{} bytes (high water {}, rejections {}, reclamations {})",
                report.functions,
                report.regions,
                report.arena.used,
                report.arena.budget,
                report.arena.high_water,
                report.arena.rejections,
                report.arena.reclamations
            );
            if report.ok() {
                println!("RESULT ACCEPT");
                ExitCode::SUCCESS
            } else {
                println!("RESULT REJECT ({} diagnostic(s))", report.diagnostics.len());
                ExitCode::from(1)
            }
        }
        other => {
            eprintln!("ls-sem: unknown command {:?}", other);
            usage();
            ExitCode::from(2)
        }
    }
}
