import numpy as np
import json
import random
import math

N     = 8
N_ACT = 5
V     = 2
U     = 4
K     = 32
Q     = 2 ** K
BFV   = 0
NTRU  = 1

def mod_q(x):
    return int(x) & (Q - 1)

def s32(x):
    x = int(x) & 0xFFFFFFFF
    return x if x < 2**31 else x - 2**32

def wrap_sign(mode):
    return -1 if mode == BFV else 1

def schoolbook_naive(B, D, mode=BFV):
    T = [0] * N_ACT
    for i in range(N_ACT):
        for j in range(N_ACT):
            shift = i - j
            if shift >= 0:
                T[i] += 1 * B[shift] * D[j]
            else:
                T[i] += wrap_sign(mode) * B[N_ACT + shift] * D[j]
    return [mod_q(t) for t in T]

def build_circulant(B, mode=BFV):
    matrix = []
    for i in range(N_ACT):
        row = []
        for j in range(N_ACT):
            idx  = (i - j) % N_ACT
            sign = wrap_sign(mode) if (i - j) < 0 else 1
            row.append(sign * B[idx])
        matrix.append(row)
    return matrix

def circulant_matrix(B, D, mode=BFV):
    mat = build_circulant(B, mode)
    T = []
    for i in range(N_ACT):
        row_sum = sum(mat[i][j] * D[j] for j in range(N_ACT))
        T.append(mod_q(row_sum))
    return T

def get_submatrix(B, block_row, block_col, mode=BFV):
    mat         = build_circulant(B, mode)
    row_start   = block_row * V
    col_start   = block_col * U
    actual_rows = min(V, N_ACT - row_start)
    actual_cols = min(U, N_ACT - col_start)
    sub = []
    for i in range(actual_rows):
        row = []
        for j in range(actual_cols):
            row.append(mat[row_start + i][col_start + j])
        sub.append(row)
    return sub, actual_rows, actual_cols

def block_processing(B, D, mode=BFV):
    num_row_blocks = math.ceil(N_ACT / V)
    num_col_blocks = math.ceil(N_ACT / U)
    T = [0] * N_ACT
    for i in range(num_row_blocks):
        partial = [0] * V
        for j in range(num_col_blocks):
            sub, actual_rows, actual_cols = get_submatrix(B, i, j, mode)
            D_sub = D[j * U : j * U + actual_cols]
            for row in range(actual_rows):
                for col in range(actual_cols):
                    partial[row] += sub[row][col] * D_sub[col]
        row_start   = i * V
        actual_rows = min(V, N_ACT - row_start)
        for row in range(actual_rows):
            T[row_start + row] = mod_q(partial[row])
    return T

def encode_b(b):
    if b ==  1: return 0b01
    if b == -1: return 0b11
    return 0b00

def b_in_for_row0(B, mode=BFV):
    n = len(B)
    result = []
    for k in range(n):
        shift = 0 - k
        if shift >= 0:
            eff = 1 * B[shift]
        else:
            eff = wrap_sign(mode) * B[n + shift]
        result.append(eff)
    return result

def pack_b_in(eff_b):
    val = 0
    for k, b in enumerate(eff_b):
        val |= encode_b(b) << (2 * k)
    return val

def run_test(test_name, B, D, mode=BFV, verbose=True):
    mode_str = "BFV " if mode == BFV else "NTRU"
    T1 = schoolbook_naive(B, D, mode)
    T2 = circulant_matrix(B, D, mode)
    T3 = block_processing(B, D, mode)
    ok = (T1 == T2 == T3)
    status = "Correct MATCH" if ok else "Wrong MISMATCH"
    if verbose:
        print(f"  [{mode_str}] {test_name}: {status}")
        if not ok:
            print(f"    naive:     {[s32(x) for x in T1]}")
            print(f"    circulant: {[s32(x) for x in T2]}")
            print(f"    block:     {[s32(x) for x in T3]}")
    return T1

def batch_multiply(B, D_list, mode=BFV):
    results = []
    for D in D_list:
        T = schoolbook_naive(B, D, mode)
        results.append(T)
    return results

def print_b_in_hex(B, mode):
    eff     = b_in_for_row0(B, mode)
    packed  = pack_b_in(eff)
    mode_str = "BFV " if mode == BFV else "NTRU"
    print(f"  [{mode_str}] b_in = {packed:#012b}  ({packed:#06x})")
    print(f"           eff_b[0..{N_ACT-1}] = {eff}")

vectors: list = []

if __name__ == "__main__":
    print(f"SCALES Golden Model v3 — Dual Mode + Batch  (N={N}, N_ACT={N_ACT}, V={V}, U={U}, K={K})")
    print(f"{'='*60}")

    random.seed(42)

    B1     = [1, -1, 0, 1, 0]
    D1     = [5,  3,  7, 2, 8]
    B2     = [1] * N_ACT
    D2     = [10, 20, 30, 40, 50]
    B3     = [0] * N_ACT; B3[0] = 1
    D3     = [7, 13, 3, 99, 42]
    B4     = [random.choice([-1, 0, 1]) for _ in range(N_ACT)]
    D4     = [random.randint(0, Q - 1)  for _ in range(N_ACT)]
    B_wrap = [0] * N_ACT; B_wrap[-1] = 1
    D_wrap = [0] * N_ACT; D_wrap[1]  = 1

    tests = [
        ("Hand-crafted n=5",        B1, D1),
        ("All-ones B",              B2, D2),
        ("Single coeff b0=1",       B3, D3),
        ("Random coefficients",     B4, D4),
        ("Wrap-around sign stress", B_wrap, D_wrap),
    ]

    vectors.clear()

    print(f"\n--- Correctness: all three implementations must agree (N_ACT={N_ACT}) ---")
    for name, B, D in tests:
        for mode in [BFV, NTRU]:
            T = run_test(name, B, D, mode)
            vectors.append({
                "mode":     "BFV" if mode == BFV else "NTRU",
                "N_ACT":    N_ACT,
                "B": B, "D": D,
                "T": T,
                "T_signed": [s32(t) for t in T]
            })

    print(f"\n--- Wrap-around verification ---")
    T_bfv  = schoolbook_naive(B_wrap, D_wrap, BFV)
    T_ntru = schoolbook_naive(B_wrap, D_wrap, NTRU)
    print(f"  B = {B_wrap},  D = {D_wrap}")
    print(f"  BFV  T[0] = {T_bfv[0]:#010x}  (signed: {s32(T_bfv[0])})")
    print(f"  NTRU T[0] = {T_ntru[0]:#010x} (signed: {s32(T_ntru[0])})")
    wrap_ok = (T_bfv[0] != T_ntru[0])
    print(f"  BFV != NTRU: {'PASS' if wrap_ok else 'FAIL — wrap logic broken'}")

    print(f"\n--- BFV vs NTRU for B1 x D1 ---")
    T_bfv1  = schoolbook_naive(B1, D1, BFV)
    T_ntru1 = schoolbook_naive(B1, D1, NTRU)
    print(f"  BFV  (signed): {[s32(x) for x in T_bfv1]}")
    print(f"  NTRU (signed): {[s32(x) for x in T_ntru1]}")
    print(f"  Differ at: {[i for i in range(N_ACT) if T_bfv1[i] != T_ntru1[i]]}")

    print(f"\n--- Hardware b_in values ---")
    print_b_in_hex(B1, BFV)
    print_b_in_hex(B1, NTRU)

    print(f"\n--- NTRU EES-style test (q=2048) ---")
    random.seed(99)
    B_ntru       = [random.choice([-1, 0, 1]) for _ in range(N_ACT)]
    D_ntru       = [random.randint(0, 2047)   for _ in range(N_ACT)]
    T_ntru_q2048 = schoolbook_naive(B_ntru, D_ntru, NTRU)
    T_bfv_q2048  = schoolbook_naive(B_ntru, D_ntru, BFV)
    T_ntru_mod   = [t & 2047 for t in T_ntru_q2048]
    print(f"  B_ntru = {B_ntru}")
    print(f"  D_ntru = {D_ntru}")
    print(f"  NTRU T (mod 2048) = {T_ntru_mod}")
    print(f"  BFV  T (mod 2^32) = {[s32(x) for x in T_bfv_q2048]}")
    run_test("NTRU EES-style (q=2048 D)", B_ntru, D_ntru, NTRU)
    vectors.append({
        "mode":      "NTRU_q2048",
        "N_ACT":     N_ACT,
        "B":         B_ntru,
        "D":         D_ntru,
        "T":         T_ntru_q2048,
        "T_mod2048": T_ntru_mod
    })

    print(f"\n--- Phase 2: Batch multiply (same B, multiple D) ---")
    random.seed(77)
    B_batch = [1, -1, 0, 1, 0]
    D_list  = [
        [5,  3,  7,  2,  8],
        [10, 20, 30, 40, 50],
        [random.randint(0, Q-1) for _ in range(N_ACT)],
        [random.randint(0, Q-1) for _ in range(N_ACT)],
    ]

    for mode in [BFV, NTRU]:
        mode_str = "BFV" if mode == BFV else "NTRU"
        print(f"\n  [{mode_str}] batch of {len(D_list)} polynomials, B={B_batch}")
        T_batch = batch_multiply(B_batch, D_list, mode)
        for i, (D, T) in enumerate(zip(D_list, T_batch)):
            print(f"    D{i} = {D}")
            print(f"    T{i} = {[s32(t) for t in T]}")
            print(f"    T{i} hex = {[hex(t) for t in T]}")
            vectors.append({
                "mode":      f"{mode_str}_batch",
                "batch_idx": i,
                "B":         B_batch,
                "D":         D,
                "T":         T,
                "T_signed":  [s32(t) for t in T]
            })

    out_path = "test_vectors_v3.json"
    with open(out_path, "w") as f:
        json.dump(vectors, f, indent=2)
    print(f"\n  Saved {len(vectors)} test vectors -> {out_path}")
    print(f"{'='*60}\n")
