"""Convert the authorized MATLAB HTML/JSON export to the app's question format."""

import argparse
import json
import re
from collections import Counter
from pathlib import Path


TYPES = {
    "single": ("single", "单选题"),
    "multi": ("multiple", "多选题"),
    "judge": ("judge", "判断题"),
}


def load_source(source: Path) -> list[dict]:
    text = source.read_text(encoding="utf-8-sig")
    if source.suffix.lower() in {".html", ".htm"}:
        match = re.search(r"^const ALL = (\[.*\]);\s*$", text, re.MULTILINE)
        if not match:
            raise ValueError("HTML does not contain the expected ALL question array")
        # Quote property names without touching quoted MATLAB expressions.
        # Parse the data literal only; never execute source JavaScript.
        text = re.sub(
            r'"(?:\\.|[^"\\])*"|([A-Za-z_$][\w$]*)(?=\s*:)',
            lambda token: json.dumps(token[1]) if token[1] else token[0],
            match[1],
        )
    data = json.loads(text)
    if not isinstance(data, list) or not data:
        raise ValueError("Source must contain a nonempty question array")
    return data


def convert_question(source: dict) -> dict:
    question_type, type_label = TYPES[source["type"]]
    answer = source["ans"]
    options = source["opts"]
    # The source uses both option letters (including comma-separated answers)
    # and 正确/错误 text. Follow its mapping before the app shuffles options.
    if question_type == "judge" or "正确" in answer or "错误" in answer:
        expected = "错误" if "错误" in answer else "正确"
        matches = [option["k"] for option in options if expected in option["t"]]
        if len(matches) != 1:
            raise ValueError(f"Ambiguous answer at question {source['no']}")
        correct_keys = set(matches)
    else:
        correct_keys = set(re.findall(r"[A-D]", answer))

    option_keys = [option["k"] for option in options]
    if len(set(option_keys)) != len(option_keys):
        raise ValueError(f"Duplicate option key at question {source['no']}")
    if not correct_keys or not correct_keys.issubset(option_keys):
        raise ValueError(f"Unmatched answer at question {source['no']}")
    if question_type != "multiple" and len(correct_keys) != 1:
        raise ValueError(f"Expected exactly one answer at question {source['no']}")

    return {
        "id": source["no"],
        "source_number": source["no"],
        "type": question_type,
        "type_label": type_label,
        "stem": source["stem"],
        "answer_raw": answer,
        "options": [
            {
                "key": option["k"],
                "text": option["t"],
                "correct": option["k"] in correct_keys,
            }
            for option in options
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Original HTML or extracted JSON")
    parser.add_argument(
        "--output", type=Path,
        default=Path(__file__).resolve().parents[1] / "data/questions_matlab.json",
    )
    args = parser.parse_args()
    questions = [convert_question(question) for question in load_source(args.source)]
    ids = [question["id"] for question in questions]
    if ids != list(range(1, len(questions) + 1)):
        raise ValueError("Question IDs must be unique and continuous from 1")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(questions, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
    )
    print(f"Wrote {len(questions)} questions to {args.output}")
    print(dict(Counter(question["type"] for question in questions)))


if __name__ == "__main__":
    main()
