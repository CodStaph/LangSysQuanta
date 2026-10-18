use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use ls_sem::{demo_bad, selftest};

fn usage() {
    eprintln!(
        "ls-sem 0.1 (skeleton)\n\
         usage:\n\
           ls-sem selftest            run Σ/H/Aliases* self-checks\n\
           ls-sem demo                replay t4-proof.md bad()\n\
           ls-sem check <file.ls>     parse/check (parser not implemented yet)\n\
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
        "selftest" => match selftest() {
            Ok(()) => {
                println!("ls-sem selftest: PASS");
                ExitCode::SUCCESS
            }
            Err(e) => {
                println!("ls-sem selftest: FAIL: {}", e);
                ExitCode::from(1)
            }
        },
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
        "check" => {
            let Some(path) = args.get(1) else {
                eprintln!("ls-sem check: missing file");
                return ExitCode::from(2);
            };
            let path = PathBuf::from(path);
            match fs::read_to_string(&path) {
                Ok(_src) => {
                    eprintln!(
                        "ls-sem check: parser not implemented yet (next milestone); {} is readable",
                        path.display()
                    );
                    ExitCode::from(2)
                }
                Err(e) => {
                    eprintln!("ls-sem check: cannot read {}: {}", path.display(), e);
                    ExitCode::from(2)
                }
            }
        }
        other => {
            eprintln!("ls-sem: unknown command {:?}", other);
            usage();
            ExitCode::from(2)
        }
    }
}
