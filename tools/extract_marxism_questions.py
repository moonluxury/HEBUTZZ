import json
import re
from collections import Counter
from pathlib import Path

from docx import Document


SOURCE = Path(r"C:\Users\Legion\Desktop\工大政治\马克思主义基本原理复习.docx")
OUTPUT = Path("data/questions_marxism.json")

QUESTION_RE = re.compile(r"^(\d+)\s*[、．.]\s*(.*)$")
OPTION_RE = re.compile(r"^([A-F])\s*[、．.]\s*(.*)$", re.IGNORECASE)
ANSWER_RE = re.compile(r"答案\s*[：:]\s*([A-F\s,，、]+)", re.IGNORECASE)

# 原 Word 文档中这两题没有给出答案。根据题意和教材知识点补全。
MISSING_SOURCE_ANSWERS = {
    109: "ACD",
    406: "ABCD",
}


def clean_text(text: str) -> str:
    text = text.replace("\u3000", " ").replace("\xa0", " ")
    return re.sub(r"[ \t]+", " ", text).strip()


def split_inline_answer(text: str) -> tuple[str, str]:
    match = ANSWER_RE.search(text)
    if not match:
        return text, ""
    answer = "".join(re.findall(r"[A-F]", match.group(1).upper()))
    return text[: match.start()].rstrip(), answer


def append_text(existing: str, continuation: str) -> str:
    if not existing:
        return continuation
    return f"{existing}\n{continuation}"


def parse_question_block(number: int, lines: list[str]) -> dict:
    stem = clean_text(lines[0])
    options: list[dict] = []
    answer_raw = ""

    for raw_line in lines[1:]:
        line = clean_text(raw_line)
        if not line:
            continue

        line, inline_answer = split_inline_answer(line)
        if inline_answer:
            answer_raw = inline_answer
        if not line:
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
            stem = append_text(stem, line)

    if not answer_raw:
        answer_raw = MISSING_SOURCE_ANSWERS.get(number, "")

    # 题型已由答案数量准确表达，不再在题干中重复显示文档里的提示。
    stem = re.sub(r"\s*[〔\[]此题为多选题[〕\]]\s*", "", stem).strip()

    correct_keys = set(answer_raw)
    question_type = "single" if len(correct_keys) == 1 else "multiple"
    type_label = "单选题" if question_type == "single" else "多选题"

    return {
        "source_number": number,
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

    blocks: list[tuple[int, list[str]]] = []
    current_number: int | None = None
    current_lines: list[str] = []

    for paragraph in paragraphs:
        question_match = QUESTION_RE.match(paragraph)
        if question_match:
            if current_number is not None:
                blocks.append((current_number, current_lines))
            current_number = int(question_match.group(1))
            current_lines = [question_match.group(2).strip()]
        elif current_number is not None:
            current_lines.append(paragraph)

    if current_number is not None:
        blocks.append((current_number, current_lines))

    questions = []
    for index, (number, lines) in enumerate(blocks, start=1):
        question = parse_question_block(number, lines)
        question["id"] = index
        questions.append({"id": question.pop("id"), **question})
    return questions


def validate(questions: list[dict]) -> None:
    if not questions:
        raise ValueError("No questions were extracted")

    expected_ids = list(range(1, len(questions) + 1))
    actual_ids = [question["id"] for question in questions]
    if actual_ids != expected_ids:
        raise ValueError("Question IDs are not sequential")

    source_numbers = [question["source_number"] for question in questions]
    duplicates = [number for number, count in Counter(source_numbers).items() if count > 1]
    if duplicates:
        raise ValueError(f"Duplicate source numbers: {duplicates}")

    errors = []
    for question in questions:
        number = question["source_number"]
        answer = set(question["answer_raw"])
        option_keys = [option["key"] for option in question["options"]]
        correct_keys = {option["key"] for option in question["options"] if option["correct"]}

        if not question["stem"]:
            errors.append(f"{number}: empty stem")
        if not 2 <= len(option_keys) <= 6:
            errors.append(f"{number}: invalid option count {len(option_keys)}")
        if len(set(option_keys)) != len(option_keys):
            errors.append(f"{number}: duplicate option keys {option_keys}")
        if not answer:
            errors.append(f"{number}: missing answer")
        if answer != correct_keys:
            errors.append(f"{number}: answer {answer} != correct options {correct_keys}")
        if not answer.issubset(set(option_keys)):
            errors.append(f"{number}: answer keys are not present in options")
        if question["type"] == "single" and len(answer) != 1:
            errors.append(f"{number}: single-choice answer has {len(answer)} keys")
        if question["type"] == "multiple" and len(answer) < 2:
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
    print(f"Wrote {OUTPUT} with {len(questions)} questions: {dict(counts)}")
    print(f"Source range: {questions[0]['source_number']}–{questions[-1]['source_number']}")
    print(f"Filled missing source answers: {MISSING_SOURCE_ANSWERS}")


if __name__ == "__main__":
    main()
