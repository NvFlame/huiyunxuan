#!/usr/bin/env python3
"""A small checker for five/seven-character regulated-verse line patterns.

This prototype intentionally ignores words and rhymes.  It only accepts
confirmed tonal strings made of exactly five or seven "平"/"仄" characters
per line.

Examples:
    python tools/five_char_prosody_checker.py 仄仄平平仄 平平仄仄平
    python tools/five_char_prosody_checker.py 平平仄仄平平仄 仄仄平平仄仄平
    python tools/five_char_prosody_checker.py --json 仄仄仄仄仄 仄平平仄平
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass, field
from typing import Iterable


TONE_PING = "平"
TONE_ZE = "仄"
VALID_TONES = {TONE_PING, TONE_ZE}


@dataclass
class Mark:
    start: int
    end: int
    color: str
    label: str


@dataclass
class LineResult:
    line: int
    pattern: str
    category: str
    status: str
    tags: list[str] = field(default_factory=list)
    marks: list[Mark] = field(default_factory=list)


@dataclass
class CheckResult:
    ok: bool
    line_count: int
    line_length: int
    start_style: str
    red_count: int
    green_count: int
    results: list[LineResult]
    warnings: list[str] = field(default_factory=list)


def normalize_pattern(raw: str) -> str:
    pattern = "".join(ch for ch in raw.strip() if not ch.isspace())
    if len(pattern) not in {5, 7}:
        raise ValueError(f"每句必须正好 5 个或 7 个平仄字：{raw!r}")
    invalid = [ch for ch in pattern if ch not in VALID_TONES]
    if invalid:
        raise ValueError(f"只能输入“平”或“仄”：{raw!r}")
    return pattern


def category_of(pattern: str) -> str:
    second = pattern[1]
    last = pattern[-1]
    if second == TONE_ZE and last == TONE_PING:
        return "仄起平收"
    if second == TONE_ZE and last == TONE_ZE:
        return "仄起仄收"
    if second == TONE_PING and last == TONE_PING:
        return "平起平收"
    return "平起仄收"


def line_core(pattern: str) -> str:
    if len(pattern) == 5:
        return pattern
    return pattern[2:]


def expected_core_category(pattern: str) -> str:
    if len(pattern) == 5:
        return category_of(pattern)

    full_category = category_of(pattern)
    if full_category == "平起平收":
        return "仄起平收"
    if full_category == "平起仄收":
        return "仄起仄收"
    if full_category == "仄起平收":
        return "平起平收"
    return "平起仄收"


def offset_of(pattern: str) -> int:
    return 0 if len(pattern) == 5 else 2


def ok(line: int, pattern: str, tag: str, category: str | None = None) -> LineResult:
    return LineResult(
        line=line,
        pattern=pattern,
        category=category or category_of(pattern),
        status="ok",
        tags=[tag],
        marks=[Mark(1, len(pattern), "green", tag)],
    )


def err(line: int, pattern: str, tag: str, category: str | None = None) -> LineResult:
    return LineResult(
        line=line,
        pattern=pattern,
        category=category or category_of(pattern),
        status="error",
        tags=[tag],
        marks=[Mark(1, len(pattern), "red", tag)],
    )


def three_flat_tail(line: int, pattern: str, category: str) -> LineResult:
    offset = offset_of(pattern)
    return LineResult(
        line=line,
        pattern=pattern,
        category=category,
        status="error",
        tags=["三平尾"],
        marks=[Mark(offset + 3, offset + 5, "red", "三平尾")],
    )


def analyze_line(line: int, pattern: str) -> LineResult:
    category = category_of(pattern)
    core = line_core(pattern)
    expected_category = expected_core_category(pattern)

    # In this first prototype, even lines are assumed to rhyme in level tone.
    # If an even line ends in oblique tone, we stop there as requested.
    if line % 2 == 0 and pattern[-1] == TONE_ZE:
        return err(line, pattern, "错脚", category)

    if core[2:] == "平平平":
        return three_flat_tail(line, pattern, category)

    # In seven-character lines, the first character is ignored, but the second
    # character decides the line class.  The final five characters must then
    # match the corresponding five-character core class.
    if category_of(core) != expected_category:
        return err(line, pattern, "失律", category)

    if expected_category == "仄起平收":
        if core in {"仄仄仄平平", "平仄仄平平"}:
            return ok(line, pattern, "合律", category)
        return fallback(line, pattern, core, category)

    if expected_category == "平起平收":
        if core == "平平仄仄平":
            return ok(line, pattern, "合律", category)
        if core == "仄平仄仄平":
            return err(line, pattern, "孤平", category)
        if core == "仄平平仄平":
            return ok(line, pattern, "自救", category)
        if core == "平平平仄平":
            return err(line, pattern, "拗句", category)
        return fallback(line, pattern, core, category)

    if expected_category == "仄起仄收":
        if core in {"仄仄平平仄", "平仄平平仄"}:
            return ok(line, pattern, "合律", category)
        if core in {"仄仄仄平仄", "平仄仄平仄"}:
            return ok(line, pattern, "半拗", category)
        if core in {"仄仄仄仄仄", "仄仄平仄仄"}:
            return err(line, pattern, "拗句", category)
        return fallback(line, pattern, core, category)

    # 平起仄收
    if core in {"平平平仄仄", "仄平平仄仄"}:
        return ok(line, pattern, "合律", category)
    if core == "平平仄仄仄":
        return ok(line, pattern, "三仄尾", category)
    if core == "平平仄平仄":
        return ok(line, pattern, "特拗", category)
    if core == "仄平仄仄仄":
        return err(line, pattern, "拗句", category)
    return fallback(line, pattern, core, category)


def fallback(line: int, pattern: str, core: str, category: str) -> LineResult:
    if core[1] == core[3]:
        return err(line, pattern, "失律", category)
    return err(line, pattern, "拗句", category)


def is_rescue_source(pattern: str) -> bool:
    return line_core(pattern) in {"仄仄仄平仄", "仄仄仄仄仄", "仄仄平仄仄"}


def is_rescue_target(pattern: str) -> bool:
    return line_core(pattern) in {"仄平平仄平", "平平平仄平"}


def replace_with_green(result: LineResult, tag: str) -> None:
    result.status = "ok"
    result.tags = [tag]
    result.marks = [Mark(1, len(result.pattern), "green", tag)]


def add_green_tag(result: LineResult, tag: str) -> None:
    if tag not in result.tags:
        result.tags.append(tag)
    result.status = "ok"
    result.marks = [mark for mark in result.marks if mark.color != "red"]
    result.marks.append(Mark(1, len(result.pattern), "green", tag))


def add_red_tag(result: LineResult, tag: str) -> None:
    if tag not in result.tags:
        result.tags.append(tag)
    result.status = "error"
    result.marks.append(Mark(1, len(result.pattern), "red", tag))


def apply_couplet_rescue(results: list[LineResult]) -> None:
    for index in range(0, len(results) - 1, 2):
        first = results[index]
        second = results[index + 1]
        if "错脚" in second.tags:
            continue
        if not is_rescue_source(first.pattern) or not is_rescue_target(second.pattern):
            continue

        first_core = line_core(first.pattern)
        second_core = line_core(second.pattern)

        if first_core in {"仄仄仄仄仄", "仄仄平仄仄"}:
            replace_with_green(first, "被救")

        if second_core == "仄平平仄平":
            add_green_tag(second, "相救")
        elif second_core == "平平平仄平":
            replace_with_green(second, "相救")


def has_tag(result: LineResult, tags: set[str]) -> bool:
    return any(tag in tags for tag in result.tags)


def should_skip_couplet_dui(first: LineResult, second: LineResult) -> bool:
    if has_tag(first, {"特拗", "被救"}) or has_tag(second, {"相救"}):
        return True
    return False


def important_positions(pattern: str) -> list[int]:
    # Zero-based positions.  五言看二、四；七言看二、四、六。
    if len(pattern) == 5:
        return [1, 3]
    return [1, 3, 5]


def apply_dui_and_nian(results: list[LineResult]) -> None:
    # 失对：同一联出句、对句的关键偶数字位应相反。
    for index in range(0, len(results) - 1, 2):
        first = results[index]
        second = results[index + 1]
        if has_tag(first, {"错脚"}) or has_tag(second, {"错脚"}):
            continue
        if should_skip_couplet_dui(first, second):
            continue
        if any(first.pattern[pos] == second.pattern[pos] for pos in important_positions(first.pattern)):
            add_red_tag(second, "失对")

    # 失粘：只比较上一联对句与下一联出句的第 2 字。
    for index in range(1, len(results) - 1, 2):
        previous_dui = results[index]
        next_chu = results[index + 1]
        if has_tag(previous_dui, {"错脚"}) or has_tag(next_chu, {"错脚"}):
            continue
        if previous_dui.pattern[1] != next_chu.pattern[1]:
            add_red_tag(next_chu, "失粘")


def check_patterns(patterns: Iterable[str]) -> CheckResult:
    normalized = [normalize_pattern(pattern) for pattern in patterns]
    line_lengths = {len(pattern) for pattern in normalized}
    if len(line_lengths) > 1:
        raise ValueError("同一次检查不能混用五言和七言。")
    line_length = next(iter(line_lengths))

    warnings: list[str] = []
    if len(normalized) not in {4, 8}:
        warnings.append("当前脚本可分析任意偶数句，但五绝/五律通常为 4 句或 8 句。")
    if len(normalized) % 2 != 0:
        warnings.append("句数为奇数，最后一句不会参与联内救拗判断。")

    results = [analyze_line(index + 1, pattern) for index, pattern in enumerate(normalized)]
    apply_couplet_rescue(results)
    apply_dui_and_nian(results)

    red_count = sum(1 for result in results for mark in result.marks if mark.color == "red")
    green_count = sum(1 for result in results for mark in result.marks if mark.color == "green")
    return CheckResult(
        ok=red_count == 0,
        line_count=len(results),
        line_length=line_length,
        start_style=category_of(normalized[0]),
        red_count=red_count,
        green_count=green_count,
        results=results,
        warnings=warnings,
    )


def read_patterns_from_stdin() -> list[str]:
    lines = [line.strip() for line in sys.stdin if line.strip()]
    return lines


def print_text(result: CheckResult) -> None:
    for warning in result.warnings:
        print(f"提示：{warning}")
    print(f"句式：{result.line_length}言")
    print(f"首句类型：{result.start_style}")
    for item in result.results:
        tags = "、".join(item.tags)
        print(f"第{item.line}句 {item.pattern} {tags}")
    verdict = "通过" if result.ok else "有问题"
    print(f"总评：{verdict}；红色 {result.red_count}，绿色 {result.green_count}。")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="五言格律原型审查器")
    parser.add_argument("patterns", nargs="*", help="每句 5 个字，只能包含“平/仄”")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    args = parser.parse_args(argv)

    patterns = args.patterns or read_patterns_from_stdin()
    if not patterns:
        parser.error("请通过参数或标准输入提供平仄序列。")

    try:
        result = check_patterns(patterns)
    except ValueError as exc:
        print(f"输入错误：{exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(asdict(result), ensure_ascii=False, indent=2))
    else:
        print_text(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
