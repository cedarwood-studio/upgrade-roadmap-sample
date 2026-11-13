#!/usr/bin/env python3
"""Consistency check for this repository. Standard library only.

It answers one narrow question: do the report and the execution record say
what the stored data says? It does not re-measure anything. The measurements
were produced by Cedarwood Studio's own tooling, which is not in this
repository. README.md lists what a reader can re-check independently.

    python3 check.py                  # the checks that need only this repository
    python3 check.py --postal DIR     # also check every file:line reference
                                      # against a Postal checkout at the commit
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COMMIT = "d96eddbadeda600595d6247486f9ceb8e99cbc15"
problems = []
passed = 0


def read(path):
    with open(os.path.join(HERE, path), encoding="utf-8") as f:
        return f.read()


def load(path):
    return json.loads(read(path))


def expect(cond, message):
    global passed
    if cond:
        passed += 1
    else:
        problems.append(message)


def num(x):
    """19.5 -> '19.5', 5.0 -> '5'"""
    return ("%g" % x)


def check_drivers(roadmap):
    d = load("roadmap/measurements/drivers.json")["data"]
    plan = load("roadmap/plan.json")
    expect(plan["drivers"] == d, "plan.json drivers differ from measurements/drivers.json")
    passing = d["tests_total"] - d["tests_failing_at_baseline"]
    rows = {
        "Series hops": "%d " % d["series_hops"],
        "Dependencies (direct / total)": "%d / %d" % (d["dependencies_direct"], d["dependencies_total"]),
        "Dependencies that block a hop": "%d " % d["dependencies_declared_incompatible"],
        "Lines matched by documented breaking changes (confirmed by reading)": "%d matched" % d["affected_lines"],
        "Of those, executed by the test suite": "%s percent" % num(d["affected_lines_executed_percent"]),
        "Tests (passing / total)": "%d / %d" % (passing, d["tests_total"]),
        "Deprecation warnings today": "%d" % d["deprecations_distinct"],
        "Effort range": "%s to %s hours" % (num(plan["estimate"]["hours_low"]), num(plan["estimate"]["hours_high"])),
    }
    for label, value in rows.items():
        m = re.search(r"^\| %s \| (.*) \|$" % re.escape(label), roadmap, re.M)
        expect(bool(m) and value in m.group(1), "driver row %r does not carry %r" % (label, value))
    summary = load("roadmap/measurements/matches.json")["data"]["summary"]
    for text in ("%s seconds for %d examples" % (num(d["suite_seconds"]), d["tests_total"]),
                 "%s percent of lines" % num(d["line_coverage_percent_of_loaded"]),
                 "%d of the %d rules are on this path" % (summary["rules_on_path"], summary["rules_total"]),
                 "%d of them matched, at %d lines" % (summary["rules_on_path_with_hits"], summary["hits_on_path"])):
        expect(text in roadmap, "report does not state %r" % text)


def check_baseline(roadmap, readme, execution):
    """The sentence about the suite before any change comes from the runs,
    and nothing in the prose claims more than it."""
    base = load("roadmap/measurements/baseline.json")["data"]
    stmt = base["statement"]
    expect(stmt in re.sub(r"\s+", " ", roadmap), "the report does not carry the baseline statement as measured")
    ex = base["examples"]
    rc = base.get("offline_failures_recheck") or {}
    failed = [e for e in ex["list"] if e["status"] == "failed"]
    passed = [e for e in ex["list"] if e["status"] == "passed"]
    expect(stmt == "%d of %d examples pass with the network off; %d more pass with the network on; %d fail in that run."
           % (len(passed), ex["total"], rc.get("pass_with_network", 0), len(rc.get("failed_in_that_run", []))),
           "the baseline statement does not match the per-example results")
    expect(len(failed) == ex["failed"], "baseline.json failure count differs from its example list")
    for name, text in (("ROADMAP.md", roadmap), ("README.md", readme), ("EXECUTION.md", execution)):
        for pat in (r"\ball\s+(?:of\s+)?(?:the\s+)?%d(?:\s+[\w-]+){0,3}?\s+pass" % ex["total"], r"\bnone (?:of them )?(?:still )?fails?\b",
                    r"\bno behaviou?r changes?\b"):
            m = re.search(pat, text, re.I)
            expect(not m, "%s claims more than the data: %r" % (name, m.group(0) if m else ""))


def check_eol(roadmap):
    e = load("roadmap/measurements/eol.json")["data"]
    as_of = datetime.date.fromisoformat(e["as_of"])
    for look in e["lookups"]:
        if not look.get("found") or not look.get("eol"):
            continue
        days = (datetime.date.fromisoformat(look["eol"]) - as_of).days
        expect(days == look["days_to_eol"], "eol.json days for %s %s: stored %s, computed %s"
               % (look["product"], look["cycle"], look["days_to_eol"], days))
        phrase = "%d days past" % -days if days < 0 else "%d days ahead" % days
        row = [l for l in roadmap.splitlines() if l.startswith("|") and look["eol"] in l and phrase in l]
        expect(bool(row), "no end-of-life row with %s and %r (%s %s)"
               % (look["eol"], phrase, look["product"], look["cycle"]))


def check_estimate(roadmap):
    plan = load("roadmap/plan.json")
    low = high = 0.0
    for s in plan["stages"]:
        lo, hi = s["estimate_hours"]["low"], s["estimate_hours"]["high"]
        low, high = low + lo, high + hi
        m = re.search(r"^\| %s .* \| ([\d.]+) \| ([\d.]+) \|$" % s["id"], roadmap, re.M)
        expect(bool(m) and float(m.group(1)) == lo and float(m.group(2)) == hi,
               "estimate row for %s differs from plan.json (%s to %s)" % (s["id"], lo, hi))
        sec = re.search(r"^### %s: .*?(?=^### |^## )" % s["id"], roadmap, re.M | re.S)
        eff = re.search(r"^- \*\*Effort:\*\* ([\d.]+) to ([\d.]+) hours\.", sec.group(0) if sec else "", re.M)
        expect(bool(eff) and float(eff.group(1)) == lo and float(eff.group(2)) == hi,
               "stage %s effort line differs from plan.json" % s["id"])
        expect(sum(1 for t in s["estimate_terms"] if t["term"] == "review.stage") == 1,
               "stage %s does not carry the independent review in its estimate" % s["id"])
    low, high = round(low, 2), round(high, 2)
    expect(low == plan["estimate"]["hours_low"] and high == plan["estimate"]["hours_high"],
           "plan.json stage hours sum to %s to %s, not its stated total" % (low, high))
    expect("| **Total** | **%s** | **%s** |" % (num(low), num(high)) in roadmap,
           "estimate total row is not %s to %s" % (num(low), num(high)))
    expect("%.1f to 1" % (high / low) in roadmap, "the report does not print the range's ratio, %.1f to 1" % (high / low))
    expect("uncalibrated" in roadmap, "the report does not say the estimate's numbers are uncalibrated priors")


def check_review(roadmap, readme, execution):
    """The independent review is on file, with its method, and the prose
    states its counts and its measured time as recorded."""
    rev = load("roadmap/tech-review.json")
    m = rev["method"]
    expect(all(k in m for k in ("changelogs_read", "unexecuted_call_sites_read", "upstream_diff", "break_attempts")),
           "the roadmap review record lacks part of its method")
    expect("%d items" % len(rev["findings"]) in roadmap, "the report's count of review findings differs from the record")
    uncaught = sum(1 for f in rev["findings"] if f.get("caught_by_checks") is False)
    expect("Of the %d, %d are things no check" % (len(rev["findings"]), uncaught) in roadmap,
           "the report's count of findings no check would show differs from the record")
    secs = load("roadmap/run-summary.json")["independent_review_seconds"]
    expect("%.1f minutes" % (secs / 60.0) in readme and "%.1f min" % (secs / 60.0) in execution,
           "README.md or EXECUTION.md does not state the roadmap review's measured time (%.1f minutes)" % (secs / 60.0))
    s = load("execution/summary.json")
    for st in s["stages"]:
        r = st.get("review")
        if not r:
            continue
        expect(os.path.exists(os.path.join(HERE, "execution", "stages", st["stage"], "review.json")),
               "%s has a review verdict and no review record" % st["stage"])
        expect(r["verdict"] == "pass", "%s is published with review verdict %r" % (st["stage"], r["verdict"]))


def check_execution(execution):
    s = load("execution/summary.json")
    rows = {}
    for line in execution.splitlines():
        m = re.match(r"^\| \[(S\d+)\]", line)
        if m:
            rows[m.group(1)] = line
    for st in s["stages"]:
        if st.get("status") != "green":
            continue
        row = rows.get(st["stage"], "")
        t, p, d = st["check"]["tests"], st["check"]["parity"], st["diff"]
        expect("%d of %d" % (t["after_passed"], t["after_total"]) in row,
               "%s row: examples passing differ from summary.json" % st["stage"])
        expect("%d of %d" % (p["identical"], p["requests"]) in row,
               "%s row: identical responses differ from summary.json" % st["stage"])
        expect("%d files" % d["files"] in row
               and (not d["insertions"] or "+%d" % d["insertions"] in row)
               and (not d["deletions"] or "-%d" % d["deletions"] in row),
               "%s row: diff size differs from summary.json" % st["stage"])
        expect("%d check" % st["attempts"] in row, "%s row: checks used differ from summary.json" % st["stage"])
        r = st.get("review")
        if r:
            expect("%.1f min" % (r["seconds"] / 60.0) in row,
                   "%s row: review time differs from summary.json (%.1f min)" % (st["stage"], r["seconds"] / 60.0))
            rounds = len(st.get("reviews") or [r])
            expect("%d round" % rounds in row, "%s row: review rounds differ from summary.json (%d)" % (st["stage"], rounds))
        expect(not p["unexplained"], "%s has unexplained response differences" % st["stage"])
        boot = st["check"].get("boot")
        if isinstance(boot, list):
            expect(all(b["after"] for b in boot if b["before"]), "%s: a boot variant that started before does not start after" % st["stage"])
        lock = st["check"].get("lock")
        if lock:
            expect(not lock["unexplained"], "%s: gems moved in the lock with no reason on file" % st["stage"])


def check_links():
    for name in ("README.md", "ROADMAP.md", "EXECUTION.md", "THIRD_PARTY_LICENSES.md"):
        text = read(name)
        for target in re.findall(r"\]\(([^)\s]+)\)", text):
            if re.match(r"https?://|#|mailto:", target):
                continue
            expect(os.path.exists(os.path.join(HERE, target.split("#")[0])),
                   "%s links to %s, which is not in the repository" % (name, target))
    for target in re.findall(r"`((?:roadmap|execution)/[\w./<>*-]+)`", read("README.md") + read("EXECUTION.md")):
        if "<" in target or "*" in target:
            continue
        expect(os.path.exists(os.path.join(HERE, target)), "text names %s, which is not in the repository" % target)


def check_html(roadmap):
    page = read("roadmap.html")
    for heading in re.findall(r"^#{1,3} (.+)$", roadmap, re.M):
        plain = re.sub(r"`", "", heading).replace("&", "&amp;")
        expect(plain in re.sub(r"</?code>", "", page), "roadmap.html lacks the heading %r" % heading)
    words = lambda s: len(re.findall(r"\w+", s))
    md_words = words(re.sub(r"\]\([^)]*\)", "]", roadmap))
    html_words = words(re.sub(r"<style.*?</style>|<[^>]+>", " ", page, flags=re.S))
    expect(abs(md_words - html_words) <= md_words * 0.03,
           "roadmap.html and ROADMAP.md differ in length (%d and %d words); render it again" % (html_words, md_words))


def check_hygiene():
    bad_keys = re.compile(r'"(model|model_[a-z_]+|turns|cost_equivalent_usd|[a-z_]*tokens|authors?|maintainers?)"\s*:')
    local = re.compile(r"/home/[a-z]|/Users/")
    # GitHub turns these into a cross-reference on the project's own timeline; nothing here may carry one
    upstream_ref = re.compile(r"github\.com/postalserver/postal/(?:pull|pulls|issues|discussions|commit|compare)\b|"
                              r"postalserver/postal(?:#\d+|@[0-9a-f]{7,40})", re.I)
    bare_ref = re.compile(r"(?<![\w&/#])#\d{1,5}(?!\w)|(?<![\w-])GH-\d+\b")
    # a pull request number as it appears in a quoted commit title, in any file
    title_ref = re.compile(r"\(#\d{3,5}\)")
    for root, dirs, files in os.walk(HERE):
        dirs[:] = [d for d in dirs if d != ".git" and not (root == HERE and d == "postal")]
        rel = os.path.relpath(root, HERE)
        expect(rel.split(os.sep)[0] != "kit", "the measuring scripts are in the tree: %s" % rel)
        for f in files:
            path = os.path.join(rel, f)
            expect(f != "pass-usage.json" and "usage" not in f, "usage file in the tree: %s" % path)
            expect(f not in ("scan.json", "rules.json", "rubric.json"), "a file listing the rule set is in the tree: %s" % path)
            if f == "check.py" or rel.startswith("postal") or not f.endswith((".json", ".md", ".txt", ".rb", ".jsonl", ".html", ".yml", ".log", ".sh")):
                continue
            text = read(path)
            if "cache" not in rel and f not in ("rspec.json", "test-output.txt", "coverage-lines.json"):
                m = upstream_ref.search(text) or title_ref.search(text) or (f.endswith(".md") and bare_ref.search(text))
                expect(not m, "reference to an upstream pull request or issue in %s: %r" % (path, m.group(0) if m else ""))
            if f.endswith(".md"):
                expect("—" not in text and "–" not in text, "dash character in %s" % path)
            if f.endswith(".json") and "cache" not in rel:
                expect(not bad_keys.search(text), "usage or person field in %s" % path)
            if "test-output" not in f and "rspec" not in f:
                expect(not local.search(text), "local path in %s" % path)


def check_refs(roadmap, postal):
    head = subprocess.run(["git", "-C", postal, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    expect(head == COMMIT, "the Postal checkout is at %s, not %s" % (head[:7] or "?", COMMIT[:7]))
    seen = set()
    for path, line in re.findall(r"`([\w./-]+\.\w+|bin/\w+|Gemfile|Dockerfile|Rakefile):(\d+)`", roadmap):
        if (path, line) in seen:
            continue
        seen.add((path, line))
        full = os.path.join(postal, path)
        if not os.path.isfile(full):
            expect(False, "report cites %s:%s, and the file is not in Postal at the commit" % (path, line))
            continue
        with open(full, encoding="utf-8", errors="replace") as f:
            count = sum(1 for _ in f)
        expect(int(line) <= count, "report cites %s:%s, and the file has %d lines" % (path, line, count))
    for rule in load("roadmap/measurements/matches.json")["data"]["matched_rules"]:
        for hit in rule.get("hits", []):
            full = os.path.join(postal, hit["file"])
            ok = os.path.isfile(full)
            if ok and hit.get("text"):
                with open(full, encoding="utf-8", errors="replace") as f:
                    lines = f.read().splitlines()
                ok = hit["line"] <= len(lines) and hit["text"].strip() == lines[hit["line"] - 1].strip()
            expect(ok, "rule match %s:%s (%s) is not that line in Postal at the commit"
                   % (hit["file"], hit.get("line"), rule["id"]))
    print("checked %d file:line references against the checkout" % len(seen))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--postal", help="a checkout of postalserver/postal at %s" % COMMIT[:7])
    args = ap.parse_args()
    roadmap, execution, readme = read("ROADMAP.md"), read("EXECUTION.md"), read("README.md")
    check_drivers(roadmap)
    check_baseline(roadmap, readme, execution)
    check_eol(roadmap)
    check_estimate(roadmap)
    check_review(roadmap, readme, execution)
    check_execution(execution)
    check_links()
    check_html(roadmap)
    check_hygiene()
    if args.postal:
        check_refs(roadmap, args.postal)
    for p in problems:
        print("PROBLEM: " + p)
    print("%d checks passed, %d problems" % (passed, len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
