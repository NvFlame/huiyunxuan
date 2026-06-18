#!/usr/bin/env python3
"""Small Tkinter window for the five-character prosody checker."""

from __future__ import annotations

import re
import sys
import tkinter as tk
from tkinter import messagebox, ttk

sys.dont_write_bytecode = True

from five_char_prosody_checker import check_patterns  # noqa: E402


WINDOW_TITLE = "五/七言格律原型检查器"
SAMPLE_TEXT = """仄仄仄平平
平平仄仄平
平平平仄仄
仄仄仄平平"""


def parse_input(text: str) -> list[str]:
    tokens = re.findall(r"[平仄]+", text)
    patterns: list[str] = []
    for token in tokens:
        if len(token) in {5, 7}:
            patterns.append(token)
            continue
        can_split_as_five = len(token) > 5 and len(token) % 5 == 0
        can_split_as_seven = len(token) > 7 and len(token) % 7 == 0
        if can_split_as_five and can_split_as_seven:
            raise ValueError(f"长度同时可按五言和七言切分，请用换行、空格或标点隔开：{token}")
        if can_split_as_five:
            patterns.extend(token[index : index + 5] for index in range(0, len(token), 5))
            continue
        if can_split_as_seven:
            patterns.extend(token[index : index + 7] for index in range(0, len(token), 7))
            continue
        raise ValueError(f"无法按五字或七字一句切分：{token}")
    if not patterns:
        raise ValueError("请输入至少一句平仄。")
    return patterns


class ProsodyCheckerApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title(WINDOW_TITLE)
        self.root.geometry("820x640")
        self.root.minsize(680, 520)

        self._build_widgets()
        self.input_text.insert("1.0", SAMPLE_TEXT)
        self.check()

    def _build_widgets(self) -> None:
        outer = ttk.Frame(self.root, padding=16)
        outer.pack(fill=tk.BOTH, expand=True)

        title = ttk.Label(outer, text=WINDOW_TITLE, font=("Microsoft YaHei UI", 18, "bold"))
        title.pack(anchor=tk.W)

        hint = ttk.Label(
            outer,
            text="输入每句 5 或 7 个“平/仄”。可一行一句，也可用空格隔开；连续输入会自动切分。也可以按 Ctrl+Enter 检查。",
            wraplength=760,
        )
        hint.pack(anchor=tk.W, pady=(6, 12))

        button_row = ttk.Frame(outer)
        button_row.pack(fill=tk.X, pady=(0, 12))

        ttk.Button(button_row, text="检查", command=self.check).pack(side=tk.LEFT)
        ttk.Button(button_row, text="清空", command=self.clear).pack(side=tk.LEFT, padx=(8, 0))
        ttk.Button(button_row, text="示例", command=self.fill_sample).pack(side=tk.LEFT, padx=(8, 0))
        ttk.Button(button_row, text="退出", command=self.root.destroy).pack(side=tk.RIGHT)

        paned = ttk.PanedWindow(outer, orient=tk.VERTICAL)
        paned.pack(fill=tk.BOTH, expand=True)

        input_frame = ttk.LabelFrame(paned, text="输入")
        paned.add(input_frame, weight=2)

        self.input_text = tk.Text(
            input_frame,
            height=8,
            wrap=tk.WORD,
            undo=True,
            font=("Microsoft YaHei UI", 14),
        )
        self.input_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=10, pady=10)

        input_scroll = ttk.Scrollbar(input_frame, orient=tk.VERTICAL, command=self.input_text.yview)
        input_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.input_text.configure(yscrollcommand=input_scroll.set)

        result_frame = ttk.LabelFrame(paned, text="结果")
        paned.add(result_frame, weight=3)

        self.result_text = tk.Text(
            result_frame,
            height=12,
            wrap=tk.WORD,
            state=tk.DISABLED,
            font=("Microsoft YaHei UI", 13),
        )
        self.result_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=10, pady=10)

        result_scroll = ttk.Scrollbar(result_frame, orient=tk.VERTICAL, command=self.result_text.yview)
        result_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.result_text.configure(yscrollcommand=result_scroll.set)

        self.result_text.tag_configure("red", foreground="#b00020")
        self.result_text.tag_configure("green", foreground="#16703a")
        self.result_text.tag_configure("muted", foreground="#666666")
        self.result_text.tag_configure("bold", font=("Microsoft YaHei UI", 13, "bold"))

        self.root.bind("<Control-Return>", lambda _event: self.check())

    def clear(self) -> None:
        self.input_text.delete("1.0", tk.END)
        self._write_result("")

    def fill_sample(self) -> None:
        self.input_text.delete("1.0", tk.END)
        self.input_text.insert("1.0", SAMPLE_TEXT)
        self.check()

    def check(self) -> None:
        try:
            patterns = parse_input(self.input_text.get("1.0", tk.END))
            result = check_patterns(patterns)
        except ValueError as exc:
            messagebox.showerror("输入错误", str(exc))
            return

        self.result_text.configure(state=tk.NORMAL)
        self.result_text.delete("1.0", tk.END)

        for warning in result.warnings:
            self._append(f"提示：{warning}\n", "muted")

        self._append(f"句式：{result.line_length}言\n", "muted")
        self._append(f"首句类型：{result.start_style}\n", "muted")

        for item in result.results:
            tag_text = "、".join(item.tags)
            color = "red" if item.status == "error" else "green"
            self._append(f"第{item.line}句 ", "muted")
            self._append(item.pattern, "bold")
            self._append(" ")
            self._append(tag_text, color)
            self._append("\n")

        verdict = "通过" if result.ok else "有问题"
        verdict_color = "green" if result.ok else "red"
        self._append("\n总评：")
        self._append(verdict, verdict_color)
        self._append(f"；红色 {result.red_count}，绿色 {result.green_count}。\n", "muted")
        self.result_text.configure(state=tk.DISABLED)

    def _write_result(self, text: str) -> None:
        self.result_text.configure(state=tk.NORMAL)
        self.result_text.delete("1.0", tk.END)
        if text:
            self.result_text.insert(tk.END, text)
        self.result_text.configure(state=tk.DISABLED)

    def _append(self, text: str, tag: str | None = None) -> None:
        if tag:
            self.result_text.insert(tk.END, text, tag)
        else:
            self.result_text.insert(tk.END, text)


def main() -> int:
    root = tk.Tk()
    ProsodyCheckerApp(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
