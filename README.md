# Upgrade Roadmap sample: Postal, Rails 7.1 to 8.1

**An unsolicited sample.** Cedarwood Studio produced this from the public source of [postalserver/postal](https://github.com/postalserver/postal) at commit `d96eddb`, on November 13, 2026. Nobody at the Postal project requested it. We aren't affiliated with the project and it hasn't endorsed any of this. No issue, pull request or comment was sent upstream. The upgrade work sits on our own fork and stays there.

This repository holds one complete Upgrade Roadmap, which is the fixed-price report we sell before a Rails upgrade. It also holds the first four stages of the upgrade it plans, carried out on a fork, each with its checks and its review. It's here so the work can be checked line by line.

It doesn't judge Postal or the people who maintain it. We picked Postal because its license permits this and its test suite runs without secrets. If you maintain Postal and want something here corrected or taken down, write to hello@cedarwood.studio.

**The Postal project has its own Rails upgrade under way.** Its repository has a branch that moves to Rails 7.2 (September 2026), a branch that moves to 8.1 (October 2026) and an open pull request for Rails 8.1, opened November 4, 2026. A roadmap says what upgrade work a project already has and what it covers, and this one does.

## What this sample shows

We ran the sample twice on the same commit, and the difference between the two runs is the main thing it shows.

**The first run** was an automated pass with no separate review. It found four lines of Postal that documented Rails changes would break. Three stages went onto the fork, and each passed every check: the test suite, a comparison of 170 recorded HTTP responses, and the same checks again on GitHub Actions.

Then the work got a separate review pass. It found four more breaking lines, and one of them was already a defect in the third stage. With an optional start-up feature switched on, the application didn't start on Rails 7.2. The test suite loads that line and never executes it, so no check could see it. The review also had the Postal project's own upgrade branches to compare against, which most applications won't have.

So the first pass had found four of the eight lines flagged as breaking, and the review found the other four. Every roadmap and every stage now gets a separate review pass before it's published.

**The second run** is what this repository holds. The reviews recorded here are review passes of our process. No person has reviewed this sample yet, and a roadmap we deliver gets a person's review before delivery.

## Start here

- [`ROADMAP.md`](ROADMAP.md): the report. Where the app stands against end-of-life dates, what the project already has in flight, what blocks the target, which lines match documented breaking changes, the code no test runs, a ten-stage plan and an effort range. [`roadmap.html`](roadmap.html) is the same text as one page.
- [`EXECUTION.md`](EXECUTION.md): what happened when the first four stages were carried out, with the numbers before and after, what each review found and the CI runs.
- [`roadmap/plan.json`](roadmap/plan.json): the plan in a form a program can read. Each change cites its evidence.
- [`first-pass/ROADMAP.md`](first-pass/ROADMAP.md): the first run's report, for comparison.

## The short version

- Postal's main branch pins Rails 7.1.6. That series passed end of life 408 days before the report date, by the dates at endoflife.date. The only series still receiving security fixes is 8.1, three series away.
- Eight lines are flagged as breaking on the path to 8.1. One of them, a `schema.rb` column sorting first read as a break, was reverted in Rails 8.1.4, so at the target it isn't one.
- The second run also found what neither the first run nor its review had: a second gem (`cgi`) that leaves the lock on Rails 8.0 while two files use it, and 11 items from the roadmap's review, 6 of which no check in the plan would have shown.
- The estimate is 30 to 263 hours for ten stages. It's uncalibrated.
- Four stages are on the fork, each as its own pull request: 65 tests that pin current behavior, the blocking gem removed, Rails 7.1.6 to 7.2.4, and Rails 7.2.4 to 8.0.5.2.
- The third stage is the one that shipped the defect. We put it through the review as it stood, with no hint of what had been found. The review found the defect, and two more problems with the stage. The stage was reviewed five times and fixed four times before a review passed it. `EXECUTION.md` has each round.
- Each stage on the fork passed the test suite, a start-up check and a comparison of 170 recorded HTTP responses, in our sandbox and again on GitHub Actions. `EXECUTION.md` has the run links, and per-example results are in `execution/runs/`.
- The fourth stage, Rails 8.0, carries the password reset fix the first run never knew it needed, with tests that fail without it. It passed its first review, which asked for three more differences to be declared.

Two things bound these numbers. Four of the ten planned stages have run, and the six still to run are Rails 8.1 and the framework defaults. And Postal sits at the easy end. One gem blocks the path, it's a development tool, and the suite is fast.

## What you can check yourself

- **The blocking gem.** `gem specification annotate -v 3.2.0 --remote` shows it requires `activerecord < 8.0`. Our resolver output is in `roadmap/resolve-run/resolve/`.
- **The matched lines.** Each match in `ROADMAP.md` names a file and line in Postal at the commit and links the upstream page that documents the change. Open both. `roadmap/measurements/matches.json` has every match.
- **The stages.** The [pull requests](https://github.com/cedarwood-studio/postal/pulls) on the fork have the diffs. Each stage branch has a workflow that reruns the suite and the 170 requests. The run links are in `EXECUTION.md`.
- **The defect in the third stage.** On the fork, check out the stage's first commit and start the application with `MIGRATION_WAITER_ENABLED=true` and a loaded schema. It exits with `NoMethodError` at `lib/migration_waiter.rb:18`. The stage's second commit fixes it and adds a test that fails without the fix.
- **The reviews.** `roadmap/tech-review.json` and `execution/stages/<id>/review-round-<n>.json` hold each review's record and what it found.
- **The report against its data.** `check.py` compares the numbers in the report and the execution record with the JSON files they came from, and with a Postal checkout it confirms every file and line the report cites.

```
git clone https://github.com/postalserver/postal.git
git -C postal checkout d96eddbadeda600595d6247486f9ceb8e99cbc15
python3 check.py --postal postal
```

`check.py` needs Python 3.8 or newer. It checks the report against its data, and it doesn't measure anything again.

## Layout

- `ROADMAP.md`, `roadmap.html`: the report.
- `roadmap/`: the plan (`plan.json`), the data the report was built from, and the review's record.
- `EXECUTION.md`, `execution/`: the stage results, with the check results, the review records and the pull request text for each stage.
- `first-pass/`: the first run's report and plan.
- `check.py`: the consistency check described above.

Registry records are stored without author and maintainer fields. Test fixtures use `example.com` addresses. The Postal project's branches are described by name and date and its pull request by date only, with no links, numbers or patch text. Where a log quotes Postal's commit titles, the pull request numbers are taken out.

In the records, `out/` is `roadmap/` here, `exec/` is `execution/`, and `repo/` is the Postal checkout. A few records cite files that aren't published. Postal's own copyright notice is in [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).

## Why Postal

We wanted a well-known application under a permissive license, on a framework version past end of life, with a test suite that runs without secrets. Postal is MIT licensed, has about 17,000 stars, pins Rails 7.1.6 on its main branch, and its suite needs only a MariaDB server.

## On your own application

The paid Roadmap is a fixed $2,500, for Rails 7.0 to 8.1, and [the offer page](https://cedarwood.studio/rails-upgrade-roadmap/) has the terms. To ask about one, write to hello@cedarwood.studio.

## License

No license is granted for the report, the plan, the evidence or `check.py`. They're published to be read and checked. Postal's source remains under its own MIT license, and the stage branches on the fork are modifications of it under the same terms.
