// Known-answer probe: feeds fixed seals to risc0_circuit_rv32im::verify and prints the exact verdicts.
// Usage: kat <path to a valid po2=14 rv32im seal>
use std::process::ExitCode;

use risc0_circuit_rv32im::verify;

fn show(label: &str, seal: &[u32]) {
    println!("KAT_{label}={:?}", verify(seal));
}

fn main() -> ExitCode {
    let Some(path) = std::env::args().nth(1) else {
        eprintln!("usage: kat <valid seal file>");
        return ExitCode::from(2);
    };
    let bytes = std::fs::read(&path).expect("read seal");
    let valid: Vec<u32> = bytes
        .chunks_exact(4)
        .map(|c| u32::from_le_bytes(c.try_into().unwrap()))
        .collect();
    println!("KAT_SEAL_WORDS={}", valid.len());
    println!("KAT_SEAL_VERSION={}", valid[0]);
    println!("KAT_SEAL_PO2={}", valid[1]);

    show("VALID", &valid);
    show("EMPTY", &[]);
    show("BAD_VERSION", &[valid[0] + 1, valid[1]]);
    show("PO2_TOO_BIG", &[valid[0], 1000]);

    let mut flipped_last = valid.clone();
    *flipped_last.last_mut().unwrap() ^= 1;
    show("FLIPPED_LAST", &flipped_last);

    let mut flipped_mid = valid.clone();
    flipped_mid[valid.len() / 2] ^= 1;
    show("FLIPPED_MID", &flipped_mid);

    let mut wrong_po2 = valid.clone();
    wrong_po2[1] -= 1;
    show("WRONG_PO2", &wrong_po2);

    show("TRUNCATED", &valid[..valid.len() - 1]);
    show("HEADER_ONLY", &valid[..2]);
    ExitCode::SUCCESS
}
