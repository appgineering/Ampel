#!/usr/bin/env python3
"""Next CFBundleVersion in yyyymmdd## form, counting from today's builds.

The previous value is the only state needed: if it already carries today's
date, the counter continues; otherwise today starts at 01. Nothing to keep in
sync, and nothing to lose.

    ./Tools/next_build_number.py            # print the next value
    ./Tools/next_build_number.py --write    # print it and update project.yml
    ./Tools/next_build_number.py --check    # run the self-check
"""
import datetime
import pathlib
import re
import sys

PROJECT = pathlib.Path(__file__).resolve().parent.parent / "project.yml"
PATTERN = re.compile(r'CFBundleVersion: "([^"]*)"')


def next_build(current: str, today: str) -> str:
    """Given the previous build number, return today's next one.

    Build numbers must never decrease, or macOS treats an update as a
    downgrade. Rolling past 99 in one day would produce an 11 digit number
    that the next day's 10 digit number would sort below, so it stops instead.
    """
    if len(current) == 10 and current[:8] == today and current.isdigit():
        counter = int(current[8:]) + 1
        if counter > 99:
            raise SystemExit(
                f"100 builds on {today}; the counter has no room left. "
                "Widening it would sort above tomorrow's first build."
            )
        return f"{today}{counter:02d}"
    # Numeric, not lexicographic: "4" sorts above "2026090799" as a string.
    if current.isdigit() and int(current) > int(f"{today}99"):
        raise SystemExit(
            f"existing build number {current} is already above today's range "
            f"({today}01); a new build would look like a downgrade."
        )
    return f"{today}01"


def main() -> None:
    if "--check" in sys.argv:
        assert next_build("4", "20260907") == "2026090701", "a legacy counter starts today at 01"
        assert next_build("", "20260907") == "2026090701", "an empty value starts today at 01"
        assert next_build("2026090701", "20260907") == "2026090702", "same day continues"
        assert next_build("2026090709", "20260907") == "2026090710", "crosses ten"
        assert next_build("2026090612", "20260907") == "2026090701", "a new day resets"
        assert next_build("2026090701", "20261231") == "2026123101", "a later day resets"
        for bad, today in [("2026090799", "20260907"), ("2027010101", "20260907")]:
            try:
                next_build(bad, today)
            except SystemExit:
                pass
            else:
                raise AssertionError(f"{bad} on {today} should have been refused")
        # Whatever today is, the result must sort above yesterday's last build.
        today = datetime.date.today().strftime("%Y%m%d")
        yesterday = (datetime.date.today() - datetime.timedelta(days=1)).strftime("%Y%m%d")
        assert int(next_build(f"{yesterday}99", today)) > int(f"{yesterday}99")
        print("next_build_number: all assertions passed")
        return

    text = PROJECT.read_text()
    match = PATTERN.search(text)
    if not match:
        raise SystemExit("no CFBundleVersion in project.yml")

    value = next_build(match.group(1), datetime.date.today().strftime("%Y%m%d"))
    if "--write" in sys.argv:
        PROJECT.write_text(PATTERN.sub(f'CFBundleVersion: "{value}"', text, count=1))
    print(value)


if __name__ == "__main__":
    main()
