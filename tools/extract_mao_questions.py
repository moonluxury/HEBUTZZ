import json
import re
from collections import Counter
from pathlib import Path

from docx import Document


SOURCE = Path(
    r"C:\Users\Legion\Desktop\工大政治"
    r"\2025年秋季学期毛泽东思想和中国特色社会主义理论体系概论期末考试_备课区_显示答案.docx"
)
OUTPUT = Path("data/questions_mao.json")

HEADER_RE = re.compile(r"^(\d+)\.\s*(单选题|多选题)\s*（")
LOCAL_NUMBER_RE = re.compile(r"^\s*\d+\s*[.．、]\s*")
OPTION_RE = re.compile(r"^([A-F])\s*[.．、]\s*(.*)$", re.IGNORECASE)
ANSWER_RE = re.compile(r"^正确答案\s*[：:]\s*(.*)$")
TYPE_MARK_RE = re.compile(r"\s*\[(?:单选|多选)\]\s*$")


def clean_text(text: str) -> str:
    text = text.replace("\u3000", " ").replace("\xa0", " ")
    return re.sub(r"[ \t]+", " ", text).strip()


def append_text(existing: str, continuation: str) -> str:
    if not existing:
        return continuation
    return f"{existing}\n{continuation}"


def normalize_answer(answer_text: str) -> str:
    return "".join(re.findall(r"[A-F]", answer_text.upper()))


def parse_block(source_number: int, type_label: str, lines: list[str]) -> dict:
    stem = ""
    options: list[dict] = []
    answer_raw = ""
    answer_seen = False

    for raw_line in lines:
        line = clean_text(raw_line)
        if not line:
            continue

        answer_match = ANSWER_RE.match(line)
        if answer_match:
            answer_raw = normalize_answer(answer_match.group(1))
            answer_seen = True
            continue

        # “显示答案”导出的 Word 可能在答案之后附带解析；题库只需要题目本身。
        if answer_seen:
            continue

        option_match = OPTION_RE.match(line)
        if option_match:
            options.append(
                {
                    "key": option_match.group(1).upper(),
                    "text": clean_text(option_match.group(2)),
                }
            )
        elif options:
            options[-1]["text"] = append_text(options[-1]["text"], line)
        else:
            if not stem:
                line = LOCAL_NUMBER_RE.sub("", line, count=1)
            line = TYPE_MARK_RE.sub("", line).strip()
            stem = append_text(stem, line)

    question_type = "single" if type_label == "单选题" else "multiple"
    correct_keys = set(answer_raw)

    return {
        "id": source_number,
        "source_number": source_number,
        "type": question_type,
        "type_label": type_label,
        "stem": stem,
        "answer_raw": answer_raw,
        "options": [
            {
                "key": option["key"],
                "text": option["text"],
                "correct": option["key"] in correct_keys,
            }
            for option in options
        ],
    }


def parse_document(source: Path) -> list[dict]:
    document = Document(str(source))
    paragraphs = [clean_text(p.text) for p in document.paragraphs if clean_text(p.text)]

    headers: list[tuple[int, int, str]] = []
    for index, paragraph in enumerate(paragraphs):
        match = HEADER_RE.match(paragraph)
        if match:
            headers.append((index, int(match.group(1)), match.group(2)))

    questions = []
    for header_index, (paragraph_index, source_number, type_label) in enumerate(headers):
        next_index = (
            headers[header_index + 1][0]
            if header_index + 1 < len(headers)
            else len(paragraphs)
        )
        block_lines = paragraphs[paragraph_index + 1 : next_index]
        questions.append(parse_block(source_number, type_label, block_lines))

    return questions


def validate(questions: list[dict]) -> None:
    if not questions:
        raise ValueError("No questions were extracted")

    expected_ids = list(range(1, len(questions) + 1))
    actual_ids = [question["id"] for question in questions]
    if actual_ids != expected_ids:
        raise ValueError(
            "Question IDs are not continuous; empty placeholders must not be generated"
        )

    errors = []
    for question in questions:
        number = question["id"]
        answer_keys = set(question["answer_raw"])
        option_keys = [option["key"] for option in question["options"]]
        correct_keys = {
            option["key"] for option in question["options"] if option["correct"]
        }

        if not question["stem"]:
            errors.append(f"{number}: empty stem")
        if not 2 <= len(option_keys) <= 6:
            errors.append(f"{number}: invalid option count {len(option_keys)}")
        if len(option_keys) != len(set(option_keys)):
            errors.append(f"{number}: duplicate option keys {option_keys}")
        if not answer_keys:
            errors.append(f"{number}: missing answer")
        if not answer_keys.issubset(set(option_keys)):
            errors.append(f"{number}: answer keys are not present in options")
        if answer_keys != correct_keys:
            errors.append(
                f"{number}: answer {answer_keys} != correct options {correct_keys}"
            )
        if question["type"] == "single" and len(answer_keys) != 1:
            errors.append(f"{number}: single-choice answer has {len(answer_keys)} keys")
        if question["type"] == "multiple" and len(answer_keys) < 2:
            errors.append(f"{number}: multiple-choice answer has fewer than 2 keys")

    if errors:
        raise ValueError("\n".join(errors))


def main() -> None:
    if not SOURCE.exists():
        raise FileNotFoundError(SOURCE)

    questions = parse_document(SOURCE)
    validate(questions)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        json.dumps(questions, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    counts = Counter(question["type_label"] for question in questions)
    option_counts = Counter(len(question["options"]) for question in questions)
    print(f"Wrote {OUTPUT} with {len(questions)} questions: {dict(counts)}")
    print(f"Question IDs: {questions[0]['id']}–{questions[-1]['id']}")
    print(f"Option counts: {dict(option_counts)}")


if __name__ == "__main__":
    main()
