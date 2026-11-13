# Independent review of S2: Remove the annotate blocker

Verdict: **pass**. We found no defect. We found two risks and two notes, and none of the four would have been shown by the automated checks.

## What the stage did

It removed the `annotate` gem from the development group, deleted the one rake file that loaded it, and removed that file's linter exclusion. Four files, 65 lines removed, none added. Rails stays on 7.1.6.

## What we did

- **Changelogs.** This stage moves no framework version and upgrades no gem, so the framework changelogs do not apply and we read none for it. The job holds no changelog for `annotate`. We measured what the gem did here instead, by comparing the rake task list before and after.
- **Lines the suite loads and never runs.** We read all 16 of 16. None changes meaning on this stage. Two touch what the stage changed (the line that loads every rake file, and the development environment file), and we ran both.
- **The project's own upgrade work.** We read all of it, two branches and the open pull request for Rails 8.1. The project's 8.1 branch deletes the same rake file and the same linter exclusion, line for line. It also adds `annotaterb` in place of `annotate`, which this stage did not.
- **Attempts to break it.** Seven, all in a throwaway copy with the network off:
  - The lock lost four lines, all of them `annotate`. Nothing else moved. Regenerating the lock offline changes nothing, and the application loads with Bundler frozen.
  - The application booted 14 times out of 14, once per optional feature we could switch on, including the development environment, the only one that loaded the gem.
  - Eager loading succeeded in the test, production and development environments.
  - Rake loads in all three environments. Nothing left in the repository calls an annotate task.
  - The linter accepts its edited configuration.

## What we found

1. **Risk: the `json` pin was not added.** The plan gives this stage two changes. The second is to pin `json` below 3 in the Gemfile. The stage did not do it and the notes do not mention it. Nothing breaks today, because the lock holds `json` 2.7.1. The pin protects later relocks, where an unpinned `json` can move to 3 and make every `to_json` call raise. The project's own 7.2 branch carries the pin. It needs to be settled before the next stage that relocks freely.
2. **Risk: the plan said replace, the stage removed.** The plan asks for `annotate` to be replaced with a maintained equivalent. The notes say the plan allowed either removal or replacement, which it does not. The removal is sound and easy to reverse, and it clears the blocker for Rails 8.0 and 8.1. Whether developers keep a tool that refreshes the schema comments in 47 files is the client's call, and the notes should present it as a departure from the plan. The notes also give the estimate as 2 to 4 hours; the plan has 2.75 to 15.75.
3. **Note: five rake tasks are gone in development, not one.** They are `annotate_models`, `annotate_routes`, `remove_annotation`, `remove_routes` and `set_annotation_options`. The notes name the first. The task lists in test and production are unchanged (96 before and after in test).
4. **Note: the recorded check is thinner than the plan's.** The plan lists resolve, tests, parity and boot. The record holds tests, parity and deprecations, with no boot section and no lock comparison file. Our own boots and lock comparison are clean, so the gap is in the record and not in the stage.

## Where we stopped

We did not run the suite or the 170 recorded requests again; the stage's check ran them. We could not repeat the two scratch resolves the notes report for Rails 8.0.5.2 and 8.1.4.1, because the throwaway copy has no network, so those remain the author's measurement. We did not run a migration in development to watch the schema comments stay untouched; the code that refreshed them lived only in the deleted file and the removed gem.

The promise for this stage holds as "no undeclared behavior change, each difference sourced": the one difference, the loss of the annotate tasks in development, is declared in the notes and measured here.
