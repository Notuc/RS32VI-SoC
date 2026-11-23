#!/usr/bin/env python3
"""Convert a raw binary into a $readmemh file: one 32-bit little-endian word
per line, 8 hex digits.   usage: bin2hex.py in.bin out.hex"""
import sys

data = open(sys.argv[1], 'rb').read()
data += b'\x00' * (-len(data) % 4)          # pad to a whole word
with open(sys.argv[2], 'w') as f:
    for i in range(0, len(data), 4):
        f.write('%08x\n' % int.from_bytes(data[i:i + 4], 'little'))
