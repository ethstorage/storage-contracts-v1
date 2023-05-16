import poseidon
import sys

from poly_utils import PrimeField
from fft import fft

t ,full_round, partial_round, alpha, prime, input_rate, security_level, rc, mds = 3, 8, 57, 5, poseidon.prime_254, 2, 128, poseidon.round_constants_254, poseidon.matrix_254
instance = poseidon.FastPoseidon(prime, security_level, alpha, input_rate, t=t, full_round=full_round,
                                 partial_round=partial_round, rc_list=rc, mds_matrix=mds)

arguments = sys.argv
# BN128 curve order
assert prime == 21888242871839275222246405745257275088548364400416034343698204186575808495617

nelements = 4096
x = 123456

coeffs = []

pf = PrimeField(prime)
ru = pf.exp(5, (prime-1) // nelements)


ru_idx_str = arguments[2]
ru_idx = int(ru_idx_str,10)
encoding_key_hexstr = arguments[1]
encoding_key = int(encoding_key_hexstr, 16)

modulusBn254 = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001
encoding_key = encoding_key % modulusBn254
print(encoding_key)

for i in range(nelements // 2):
    inputs = [0, encoding_key + i, encoding_key + i + 1]
    outputs = instance.run_hash_state(inputs)
    coeffs.extend(outputs[0:2])


evals = fft(coeffs, prime, ru)
print(hex(pf.exp(ru, ru_idx)))
print(hex(evals[ru_idx]))
