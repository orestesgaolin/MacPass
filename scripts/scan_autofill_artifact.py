#!/usr/bin/env python3

import argparse
import os
import re
import sys


parser = argparse.ArgumentParser()
parser.add_argument("root")
parser.add_argument("pattern")
parser.add_argument("--exclude-suffix", action="append", default=[])
args = parser.parse_args()

expression = re.compile(args.pattern.encode())
findings = []
for directory, names, files in os.walk(args.root):
    names[:] = [
        name for name in names
        if not any(name.endswith(suffix) for suffix in args.exclude_suffix)
    ]
    for name in files:
        path = os.path.join(directory, name)
        try:
            with open(path, "rb") as stream:
                if expression.search(stream.read()):
                    findings.append(path)
        except OSError as error:
            print(f"Could not scan {path}: {error}", file=sys.stderr)
            raise SystemExit(2)

for path in findings:
    print(path)
raise SystemExit(1 if findings else 0)
