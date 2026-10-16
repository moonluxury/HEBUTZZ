import json
import re
from pathlib import Path

from docx import Document


SOURCE_GLOB = "540*.docx"
DESKTOP = Path.home() / "Desktop"
OUTPUT = Path("data/questions.json")

QUESTION_RE = re.compile(r"^(\d+)\.\u3010([^\u3011]+)\u3011(.+)$")
FALLBACK_JUDGE_RE = re.compile(r"^(\d+)\.(.+)$")
OPTION_RE = re.compile(r"^([A-Z])\s*[\.\uff0e]\s*(.+)$")
ANSWER_PREFIX = "\u7b54\u6848"
FULL_WIDTH_COLON = "\uff1a"


def split_inline_answer(text):
    marker = f"{ANSWER_PREFIX}{FULL_WIDTH_COLON}"
    if marker in text:
        before, answer = text.split(marker, 1)
        return before.strip(), answer.strip()
    marker = f"{ANSWER_PREFIX}:"
    if marker in text:
        before, answer = text.split(marker, 1)
        return before.strip(), answer.strip()
    return text, ""


def normalize_type(type_label):
    if "单选" in type_label:
        return "single"
    if "多选" in type_label:
        return "multiple"
    if "判断" in type_label:
        return "judge"
    return "single"


def finalize(raw_question, global_id):
    answer_raw = raw_question["answer_raw"].replace("，", "").replace(",", "").strip()
    q_type = normalize_type(raw_question["type_label"])

    if q_type == "judge":
        options = [
            {"key": "对", "text": "对", "correct": answer_raw == "对"},
            {"key": "错", "text": "错", "correct": answer_raw == "错"},
        ]
    else:
        correct_keys = set(answer_raw)
        options = []
        for option in raw_question["options"]:
            options.append(
                {
                    "key": option["key"],
                    "text": option["text"],
                    "correct": option["key"] in correct_keys,
                }
            )

    return {
        "id": global_id,
        "source_number": raw_question["number"],
        "type": q_type,
        "type_label": raw_question["type_label"],
        "stem": raw_question["stem"],
        "answer_raw": answer_raw,
        "options": options,
    }


def parse_questions(docx_path):
    doc = Document(str(docx_path))
    lines = [p.text.strip() for p in doc.paragraphs if p.text.strip()]

    raw_questions = []
    current = None
    current_section_type = ""

    for line in lines:
        if "单选题" in line and not line[0].isdigit():
            current_section_type = "单选题"
            continue
        if "多选题" in line and not line[0].isdigit():
            current_section_type = "多选题"
            continue
        if "判断题" in line and not line[0].isdigit():
            current_section_type = "判断题"
            continue

        question_match = QUESTION_RE.match(line)
        fallback_match = None if question_match else FALLBACK_JUDGE_RE.match(line)
        if question_match or (fallback_match and current_section_type == "判断题"):
            if current:
                raw_questions.append(current)

            if question_match:
                number = int(question_match.group(1))
                type_label = question_match.group(2).strip()
                stem = question_match.group(3).strip()
            else:
                number = int(fallback_match.group(1))
                type_label = "判断题"
                stem = fallback_match.group(2).strip()

            stem, inline_answer = split_inline_answer(stem)
            current = {
                "number": number,
                "type_label": type_label,
                "stem": stem,
                "options": [],
                "answer_raw": inline_answer,
            }
            continue

        if not current:
            continue

        if line.startswith(ANSWER_PREFIX):
            separator = FULL_WIDTH_COLON if FULL_WIDTH_COLON in line else ":"
            current["answer_raw"] = line.split(separator, 1)[1].strip()
            continue

        option_match = OPTION_RE.match(line)
        if option_match:
            current["options"].append(
                {"key": option_match.group(1), "text": option_match.group(2).strip()}
            )
        elif current["options"]:
            current["options"][-1]["text"] += "\n" + line
        else:
            current["stem"] += "\n" + line

    if current:
        raw_questions.append(current)

    questions = [finalize(q, index + 1) for index, q in enumerate(raw_questions)]
    return questions


def main():
    matches = sorted(DESKTOP.glob(SOURCE_GLOB))
    if not matches:
        raise FileNotFoundError(f"No {SOURCE_GLOB} file found on {DESKTOP}")

    questions = parse_questions(matches[0])
    if len(questions) != 540:
        raise RuntimeError(f"Expected 540 questions, got {len(questions)}")

    missing_answers = [q["id"] for q in questions if not q["answer_raw"]]
    if missing_answers:
        raise RuntimeError(f"Questions missing answers: {missing_answers}")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(questions, ensure_ascii=False, indent=2), encoding="utf-8")

    counts = {}
    for q in questions:
        counts[q["type_label"]] = counts.get(q["type_label"], 0) + 1
    print(f"Wrote {OUTPUT} with {len(questions)} questions: {counts}")


if __name__ == "__main__":
    main()
