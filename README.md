# Upgrade Roadmap sample: Postal, Rails 7.1 to 8.1

**An unsolicited sample.** Cedarwood Studio produced this from the public source of [postalserver/postal](https://github.com/postalserver/postal) at commit `d96eddb`, on November 13, 2026. Nobody at the Postal project requested it. We aren't affiliated with the project and it hasn't endorsed any of this. No issue, pull request or comment was sent upstream. The upgrade work sits on our own fork and stays there.

This repository holds one complete Upgrade Roadmap, which is the fixed-price report we sell before a framework or runtime upgrade. It also holds the first four stages of the upgrade it plans, carried out on a fork with the checks and the review that gate each stage. It's here so the work can be checked line by line.

It doesn't judge Postal or the people who maintain it. We picked Postal because its license permits this and its test suite runs without secrets. If you maintain Postal and want something here corrected or taken down, write to hello@cedarwood.studio.

**The Postal project has its own Rails upgrade under way.** Its repository has a branch that moves to Rails 7.2 (`chore/rails-7-2-and-dependency-upgrades`, September 2026), a branch that moves to 8.1 (`upgrade-rails-8.1.4`, October 2026) and an open pull request for Rails 8.1, opened November 4, 2026. The roadmap now starts by looking for work like this and uses it as an answer key. The first version of this sample didn't look, which the next section covers.

## This is the second run, and why

We ran this sample twice on the same commit, and the difference between the two runs is the main thing it shows.

**The first run** took 16 minutes of machine time and had no review before the stages began. Its search found four lines of Postal that documented Rails changes would break. Three stages went onto the fork, and each passed every check: the test suite, a comparison of 170 recorded HTTP responses, and the same checks again on GitHub Actions.

Then the work got an independent review, by a pass that had no part in producing it. It read the Rails component changelogs and compared our branches with the Postal project's own. It found four more lines the search had missed, and one of them was already a defect in our third stage. With an optional start-up feature switched on, the application didn't start on Rails 7.2. The line is loaded by the test suite and never executed, so no check could see it.

So the search had found four of the eight breaking lines known so far, and the review found the other four. We took two things from that.

- **The measuring got wider.** The rules now come from the component changelogs as well as the release notes. Every gem a hop drops from the lock is searched for in the application. Framework calls the suite loads and never runs are listed and read. The application is started once per optional feature, before the upgrade and after every stage. And the first step is to look at what the project is already doing.
- **An independent review is part of the method.** Every roadmap and every stage gets a review pass that had no part in writing it, with a fixed method: read the changelogs for the hop, read every framework call the suite never runs, compare with the project's own upgrade work, try to break the stage. The review is timed, and its record is in this repository. A stage isn't published until a review passes it. These reviews are a step of our process. They aren't a person's review, and no person has reviewed this sample yet.

**The second run** is what this repository holds. The numbers from both runs are side by side at the top of [`ROADMAP.md`](ROADMAP.md) and in [`EXECUTION.md`](EXECUTION.md).

## Start here

- [`ROADMAP.md`](ROADMAP.md): the report. Where the app stands against end-of-life dates, what the project already has in flight, what blocks the target, which lines match documented breaking changes, the code no test runs, a ten-stage plan and an effort range. [`roadmap.html`](roadmap.html) is the same text as one page.
- [`EXECUTION.md`](EXECUTION.md): what happened when the first four stages were carried out, with the numbers before and after, what each review found and how long it took, the CI runs, and where an operator stepped in.
- [`roadmap/plan.json`](roadmap/plan.json): the plan in a form a program can read. Each change cites its evidence.
- [`first-pass/ROADMAP.md`](first-pass/ROADMAP.md): the first run's report as it stood after its review, for comparison.

## The short version

- Postal's main branch pins Rails 7.1.6. That series passed end of life 408 days before the report date, by the dates at endoflife.date. The only series still receiving security fixes is 8.1, three series away.
- The second roadmap took 36.9 minutes of machine time from a repository URL, on a read-only checkout. 11.9 minutes of that was the independent review.
- Of the eight lines the first run and its review had found between them, the second run's search found all eight before its own review started, and read one of them differently: the `schema.rb` column sorting that both earlier passes called a break was reverted in Rails 8.1.4, so at the target it isn't one. Four of those eight are found by rules we wrote after the first review named them, so this shows the rules work on a known answer. It doesn't show the search would find them cold.
- The second run also found things that neither the first run nor its review had. They're a second gem (`cgi`) that leaves the lock on Rails 8.0 while two files use it, and 11 items from the roadmap's review, 6 of which no check in the plan would have shown.
- The estimate is 30.35 to 263.25 hours for ten stages. That's 8.7 to 1, and the rubric behind it is uncalibrated, since no completed upgrade has corrected its numbers yet.
- Four stages are on the fork, each as its own pull request: 65 tests that pin current behavior, the blocking gem removed, Rails 7.1.6 to 7.2.4, and Rails 7.2.4 to 8.0.5.2.
- The third stage is the one that shipped the defect. We ran the new review on it as it stood, without telling it what the first review had found. It found the defect in 6.7 minutes by starting the application with the feature on, and found two more problems with the stage. The stage was reviewed five times and fixed four times before a review passed it. `EXECUTION.md` has each round.
- The fourth stage, Rails 8.0, was built with the second run's process from the start. It carries the password reset fix the first run never knew it needed, with tests that fail without it. Its review passed it in 18.2 minutes and asked for three more differences to be declared.

## What was verified, and what wasn't

Verified, by a command that ran:

- The dependency resolver found a lock for each of the three hops with the most careful update it has. The lock files are in `roadmap/resolve-run/`.
- The test suite ran in a clean container with the network off, before any change and after each stage. Per-example results are in `execution/runs/`.
- 834 of 851 examples pass with the network off; 17 more pass with the network on; 5 fail in that run. The 5 are other examples in the same spec file, ones that pass with the network off. No single run passes all 851.
- The application was started the way a server process starts it under seven configurations, on Rails 7.1.6 and again at every check from the third stage on.
- 170 recorded HTTP responses were compared before and after each stage, in our sandbox.
- The suite and the recorded requests ran again on GitHub Actions for the baseline and each stage branch. 28 examples aren't gated there because they depend on the network. Response bodies are compared in full for 163 requests and with two time zone values masked for 5 more. `EXECUTION.md` has the run links.
- Each review's attempts to break a stage. The commands and their output are in `execution/stages/<id>/review-runs/`.

Read from files or public registries, nothing executed:

- The inventory, what each gem declares about Rails, the end-of-life dates, the Rails changelogs, and the Postal project's own branches and open pull request.

Not verified:

- **Stages S5 to S10 weren't run.** Rails 8.1 and the framework defaults are planned and estimated, and that's all.
- **No person has reviewed any of this yet.** The reviews here are passes of our own process. Each had no part in the work it read, followed a written method and is recorded, and they found real things every round. That isn't a senior Rails engineer's read. A delivered roadmap gets one, and we haven't measured what it would add or cost.
- **Production.** Everything ran in the test environment or in a production-mode boot with a throwaway key, with no real configuration, data or traffic. The request set was assembled from the routes and the specs. In a client engagement it would come from logged requests.
- **The estimating rubric.** Its numbers were set by judgment. Nothing has calibrated it.
- **Completeness.** The first run's search found four of the eight lines known so far. The second found everything on the first run's list and more. Neither figure says how much is still unfound. On the third stage each of the last three review rounds found a difference the stage hadn't declared, each smaller than the one before, and the last review stopped where its method ended.
- **Upstream since the snapshot.** Everything is as of commit `d96eddb`, which was still the head of Postal's main branch on the report date.

## What you can check without our tooling

The measurements were produced by the studio's own tooling, which isn't in this repository, and the full rule set isn't either. These parts can be checked independently:

- **The resolver result.** With Ruby 3.4.6 and Bundler 2.6 or newer, check out Postal at the commit, change the `rails` line in the `Gemfile` to `"= 8.0.5.2"`, and run `bundle lock --update rails --conservative`. The lock moves `annotate` from 3.2.0 to 2.6.5. `gem specification annotate -v 3.2.0 --remote` shows why: it requires `activerecord < 8.0`. The result can drift as new gem versions are published. Ours are in `roadmap/resolve-run/resolve/`.
- **The matched lines.** Each match in `ROADMAP.md` names a file and line in Postal at the commit and links the upstream page that documents the change. Open both. `roadmap/measurements/matches.json` has every match.
- **The stages.** The [pull requests](https://github.com/cedarwood-studio/postal/pulls) on the fork have the diffs. Each branch carries a `.upgrade/` directory with the recorded baseline and the comparison script, and a workflow that reruns the suite and the 170 requests. The run links are in `EXECUTION.md`.
- **The defect in the third stage.** On the fork, check out the stage's first commit and start the application with `MIGRATION_WAITER_ENABLED=true` and a loaded schema. It exits with `NoMethodError` at `lib/migration_waiter.rb:18`. The stage's second commit fixes it and adds a test that fails without the fix.
- **The reviews.** `roadmap/tech-review.json` and `execution/stages/<id>/review-round-<n>.json` list what each review read, what it ran and what it found.
- **The report against its data.** `check.py` compares the numbers in the report and the execution record with the JSON files they came from, and with a Postal checkout it confirms every file and line the report cites.

```
git clone https://github.com/postalserver/postal.git
git -C postal checkout d96eddbadeda600595d6247486f9ceb8e99cbc15
python3 check.py --postal postal
```

`check.py` needs Python 3.8 or newer. It doesn't measure anything again. The inventory, the coverage figures, the registry lookups and the sandbox runs can't be reproduced from this repository alone.

## Layout

- `ROADMAP.md`, `roadmap.html`: the report.
- `roadmap/`: what the report was built from.
    - `plan.json`: the staged plan.
    - `measurements/`: one JSON file per measuring step. Each says whether its contents were measured, read, fetched or derived. `matches.json` lists the rules that matched this code, with each match and the upstream source. `removed_gems.json`, `unexecuted.json`, `flags.json`, `boot.json`, `upstream.json` and `answer_key.json` are the measurements the second run added.
    - `tech-review.json`: the roadmap review's record.
    - `cache/http/`: the registry and end-of-life responses the measurements were computed from.
    - `baseline/`, `baseline-online/`, `boot/`: the raw test output, per-example results and start-up logs.
    - `resolve-run/`: the resolver's output and the lock file for each hop.
    - `job.json`: how the suite was run in the sandbox and which configurations were started.
    - `run-summary.json`: how long each step took.
- `EXECUTION.md`, `execution/`: the stage results.
    - `stages/<id>/`: the check results for each attempt, the review records, the lock changes with their reasons, and the pull request text.
    - `runs/`: test results and response diffs for the baseline and every check.
    - `record.json`: the operator's steps and every review, as they happened.
    - `parity-inputs.json`, `parity-setup.rb`: the recorded requests and the records they run against.
    - `ci/`: the summary each GitHub Actions run printed.
- `first-pass/`: the first run's report and plan.
- `check.py`: the consistency check described above.

Registry records are stored without author and maintainer fields. Test fixtures use `example.com` addresses. The Postal project's branches are described by name and date and its pull request by date only, with no links, numbers or patch text. Where a log quotes Postal's commit titles, the pull request numbers are taken out.

The records keep the path names our tooling worked under. `out/` is `roadmap/` here, `exec/` is `execution/`, and `repo/` is the Postal checkout. A few records cite `out/changelogs/` and `scan.json`. Those are the fetched Rails changelogs and the full rule file, and neither is published. Postal's own copyright notice is in [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).

## Why Postal

We wanted a well-known application under a permissive license, on a framework version past end of life, with a test suite that runs without secrets. Postal is MIT licensed, has about 17,000 stars, pins Rails 7.1.6 on its main branch, and its suite needs only a MariaDB server.

It also sits at the easy end. One gem blocks the path, and it's a development tool. The suite is fast. An application with a dozen blocked gems and a thin suite would produce a very different report, and this sample doesn't show that.

## License

No license is granted for the report, the plan, the evidence or `check.py`. They're published to be read and checked. Postal's source remains under its own MIT license, and the stage branches on the fork are modifications of it under the same terms.
