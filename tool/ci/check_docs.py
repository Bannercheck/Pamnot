#!/usr/bin/env python3
"""Checks the CI guards of the iOS voice feature and the documents that ship with it.

1. .github/workflows/build.yml: the `checks` job runs tool/ios/check_ios_config.py,
   tool/ios/check_launch_assets.py and this script. The `ios` job runs `plutil -lint` on the
   pbxproj, Info.plist, PrivacyInfo.xcprivacy and the .strings tables before
   `flutter build ios`, and after it checks that extract.actionsdata names VoiceTaskIntent
   and openAppWhenRun, and that the built Runner.app carries PrivacyInfo.xcprivacy.
2. PRIVACY.md exists, has a "Gizlilik Politikası" and a "Privacy Policy" section heading, names
   Apple, Google ML Kit and the last 20 texts, and has a contact line in each language.
3. TESTING.md has a "Sesle görev ekleme" and a "Yayın" heading and never says "Yan tuş".
   A heading is a Markdown heading or a line that is bold as a whole, and must start with
   the title.
4. ios/PamnotWidget/README.md mentions FlutterDeepLinkingEnabled and pamnot://ses.

Standard library only. The workflow is parsed with PyYAML when it is installed and read
as text otherwise; either way, comment lines (YAML or shell) do not count, so a
commented-out command never satisfies a check. Prints every failure and exits 1; prints
`docs ok` on success.

Usage: python3 tool/ci/check_docs.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "build.yml"
PRIVACY = ROOT / "PRIVACY.md"
TESTING = ROOT / "TESTING.md"
WIDGET_README = ROOT / "ios" / "PamnotWidget" / "README.md"

CHECKS_JOB_SCRIPTS = (
    "python3 tool/ios/check_ios_config.py",
    "python3 tool/ios/check_launch_assets.py",
    "python3 tool/ci/check_docs.py",
)
IOS_BUILD = "flutter build ios"
LINT = "plutil -lint"
LINTED_FILES = ("project.pbxproj", "Info.plist", "PrivacyInfo.xcprivacy", ".strings")

HEADING = re.compile(r"^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$")
BOLD_LINE = re.compile(r"^\*\*(.+)\*\*\s*$")
CONTACT_TARGET = re.compile(r"https?://\S+|[\w.+-]+@[\w-]+\.[\w.]+")

failures = []


def fail(message):
    failures.append(message)


def read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"{path.relative_to(ROOT)}: missing")
    return None


def without_comments(text):
    return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))


# 1. Workflow ---------------------------------------------------------------------------------

def jobs_from_yaml(yaml, text):
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as error:
        fail(f"build.yml: not valid YAML ({error})")
        return {}
    jobs = data.get("jobs") if isinstance(data, dict) else None
    if not isinstance(jobs, dict):
        fail("build.yml: no jobs")
        return {}
    result = {}
    for job_id, job in jobs.items():
        steps = job.get("steps") if isinstance(job, dict) else None
        result[job_id] = [
            without_comments("\n".join(str(step.get(key, "")) for key in ("name", "uses", "run")))
            for step in steps or []
            if isinstance(step, dict)
        ]
    return result


def jobs_from_text(text):
    """Splits the `jobs:` block into jobs and each job's `steps:` list into steps by indentation."""
    result = {}
    in_jobs = False
    steps = None  # the current job's step list
    steps_indent = item_indent = None
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        if indent == 0:
            in_jobs = stripped == "jobs:"
            steps = None
            continue
        if not in_jobs:
            continue
        job = re.fullmatch(r"([A-Za-z0-9_-]+):", stripped)
        if indent == 2 and job:
            steps = result.setdefault(job.group(1), [])
            steps_indent = None
            continue
        if steps is None:
            continue
        if steps_indent is None or indent <= steps_indent:
            steps_indent = indent if stripped == "steps:" else None
            item_indent = None
            continue
        if stripped.startswith("- ") and (item_indent is None or indent == item_indent):
            item_indent = indent
            steps.append(stripped[2:])
        elif steps:
            steps[-1] += "\n" + stripped
    return result


def workflow_jobs(text):
    """Returns {job id: [step text, ...]} with the steps in file order."""
    try:
        import yaml
    except ImportError:
        return jobs_from_text(text)
    return jobs_from_yaml(yaml, text)


def first_step(steps, *needles, start=0):
    for index in range(start, len(steps)):
        if all(needle in steps[index] for needle in needles):
            return index
    return None


def check_workflow():
    text = read_text(WORKFLOW)
    if text is None:
        return
    jobs = workflow_jobs(text)

    checks = jobs.get("checks")
    if checks is None:
        fail("build.yml: no `checks` job")
    else:
        for script in CHECKS_JOB_SCRIPTS:
            if first_step(checks, script) is None:
                fail(f"build.yml: `checks` job does not run `{script}`")

    ios = jobs.get("ios")
    if ios is None:
        fail("build.yml: no `ios` job")
        return
    build = first_step(ios, IOS_BUILD)
    if build is None:
        fail(f"build.yml: `ios` job does not run `{IOS_BUILD}`")
        return
    linted = "\n".join(step for step in ios[:build] if LINT in step)
    if not linted:
        fail(f"build.yml: `ios` job has no `{LINT}` step before `{IOS_BUILD}`")
    else:
        for name in LINTED_FILES:
            if name not in linted:
                fail(f"build.yml: `{LINT}` before `{IOS_BUILD}` does not cover {name}")
    if first_step(ios, "extract.actionsdata", "VoiceTaskIntent", start=build + 1) is None:
        fail(f"build.yml: no step after `{IOS_BUILD}` looks for VoiceTaskIntent in extract.actionsdata")
    if first_step(ios, "extract.actionsdata", "openApp", start=build + 1) is None:
        fail(f"build.yml: no step after `{IOS_BUILD}` looks for openAppWhenRun in extract.actionsdata")
    if first_step(ios, "Runner.app/PrivacyInfo.xcprivacy", start=build + 1) is None:
        fail(f"build.yml: no step after `{IOS_BUILD}` checks Runner.app/PrivacyInfo.xcprivacy")


# 2-4. Documents ------------------------------------------------------------------------------

def headings(text):
    found = []
    for line in text.splitlines():
        match = HEADING.match(line) or BOLD_LINE.match(line)
        if match:
            found.append(match.group(1))
    return found


def require_heading(path, text, title):
    """A heading must start with [title], so a combined page title cannot stand in for a section."""
    if not any(heading.startswith(title) for heading in headings(text)):
        fail(f"{path.relative_to(ROOT)}: no heading starting with “{title}”")


def require_words(path, text, *words):
    for word in words:
        if word not in text:
            fail(f"{path.relative_to(ROOT)}: “{word}” not found")


def check_privacy():
    text = read_text(PRIVACY)
    if text is None:
        return
    require_heading(PRIVACY, text, "Gizlilik Politikası")
    require_heading(PRIVACY, text, "Privacy Policy")
    require_words(PRIVACY, text, "Apple", "Google ML Kit")
    if not re.search(r"\b20\b", text):
        fail("PRIVACY.md: the limit of 20 kept texts is not mentioned")
    for label, pattern in (("İletişim", r"[İi]letişim"), ("Contact", r"[Cc]ontact")):
        if not any(re.search(pattern, line) and CONTACT_TARGET.search(line) for line in text.splitlines()):
            fail(f"PRIVACY.md: no “{label}” line with a link or e-mail address")


def check_testing():
    text = read_text(TESTING)
    if text is None:
        return
    require_heading(TESTING, text, "Sesle görev ekleme")
    require_heading(TESTING, text, "Yayın")
    if "yan tuş" in text.lower():
        fail("TESTING.md: says “Yan tuş”; Apple calls it the Action button (“Eylem düğmesi”)")


def check_widget_readme():
    text = read_text(WIDGET_README)
    if text is not None:
        require_words(WIDGET_README, text, "FlutterDeepLinkingEnabled", "pamnot://ses")


def main():
    check_workflow()
    check_privacy()
    check_testing()
    check_widget_readme()
    if failures:
        for message in failures:
            print(f"FAIL {message}")
        return 1
    print("docs ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
