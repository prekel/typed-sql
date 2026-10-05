#!/usr/bin/env python3

import argparse
from pathlib import Path
import re
import subprocess
import sys


SURVEY_DIR = Path(__file__).resolve().parent
VALUE_BINDING = re.compile(r"# let ([a-zA-Z_][a-zA-Z_0-9']*)\b")


class FormatError(Exception):
    pass


def format_code(code: str, path: Path, line: int) -> str:
    result = subprocess.run(
        ["ocamlformat", "--impl", f"--name={path.with_suffix('.ml')}", "-"],
        input=code,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise FormatError(f"{path}:{line}: {result.stderr.strip()}")
    formatted = result.stdout
    # MDX feeds implementation blocks to the toplevel, where phrase separators
    # inside structures are rejected. Ocamlformat can add one after a let-op
    # binding at the end of a structure.
    return re.sub(r"(?m)^[ \t]*;;[ \t]*\n(?=[ \t]*end\b)", "", formatted)


def format_block(block: str, path: Path, line: int) -> str:
    lines = block.splitlines(keepends=True)
    if not lines or not lines[0].startswith("# "):
        return format_code(block, path, line)

    binding = VALUE_BINDING.match(lines[0])
    if binding is not None:
        output_start = next(
            (index for index, current in enumerate(lines) if current.startswith(f"val {binding[1]} :")),
            None,
        )
        if output_start is None:
            raise FormatError(f"{path}:{line}: missing output for {binding[1]}")
        has_terminator = False
    else:
        output_start = next(
            (index + 1 for index, current in enumerate(lines) if current.rstrip().endswith(";;")),
            None,
        )
        if output_start is None:
            raise FormatError(f"{path}:{line}: cannot find the end of the REPL input")
        has_terminator = True

    code_lines = lines[:output_start]
    code_lines[0] = code_lines[0][2:]
    code = re.sub(r"(?:;;\s*)+$", "", "".join(code_lines)).rstrip() + "\n"
    formatted = format_code(code, path, line)
    if not formatted:
        raise FormatError(f"{path}:{line}: ocamlformat returned empty REPL input")
    formatted = re.sub(r"(?:;;\s*)+$", "", formatted).rstrip()
    formatted += ";;\n" if has_terminator else "\n"
    return "# " + formatted + "".join(lines[output_start:])


def format_document(source: str, path: Path) -> str:
    lines = source.splitlines(keepends=True)
    result = []
    index = 0
    while index < len(lines):
        if lines[index].rstrip("\r\n") != "```ocaml":
            result.append(lines[index])
            index += 1
            continue

        end = index + 1
        while end < len(lines) and lines[end].rstrip("\r\n") != "```":
            end += 1
        if end == len(lines):
            raise FormatError(f"{path}:{index + 1}: unclosed OCaml fence")

        result.append(lines[index])
        result.append(format_block("".join(lines[index + 1 : end]), path, index + 2))
        result.append(lines[end])
        index = end + 1

    return "".join(result)


def targets(paths: list[Path]) -> list[Path]:
    if not paths:
        paths = [SURVEY_DIR]
    files = []
    for path in paths:
        if path.is_dir():
            files.extend(path.glob("*.md"))
            files.extend(path.glob("*.mdx"))
        else:
            files.append(path)
    return sorted({path.resolve() for path in files})


def main() -> int:
    parser = argparse.ArgumentParser(description="Format OCaml inputs in MDX Markdown files.")
    parser.add_argument("--check", action="store_true", help="Report files that need formatting.")
    parser.add_argument("paths", nargs="*", type=Path, help="Markdown files or directories.")
    args = parser.parse_args()

    changes = []
    try:
        for path in targets(args.paths):
            source = path.read_text(encoding="utf-8")
            formatted = format_document(source, path)
            if formatted != source:
                changes.append((path, formatted))
    except (OSError, FormatError) as error:
        print(error, file=sys.stderr)
        return 2

    for path, formatted in changes:
        print(path)
        if not args.check:
            path.write_text(formatted, encoding="utf-8")
    return 1 if args.check and changes else 0


if __name__ == "__main__":
    sys.exit(main())
