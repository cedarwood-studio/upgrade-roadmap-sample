> This pull request lives in Cedarwood Studio's fork and stays there. It's one stage of an unsolicited sample upgrade, published so the work can be read. Nobody at the Postal project asked for it, and nothing has been sent to the project. Corrections go to hello@cedarwood.studio.

## S2: Remove the annotate blocker

### What changed

- `Gemfile`: we removed `gem "annotate"` from the development group.
- `Gemfile.lock`: regenerated with `bundle lock`. The only change is that annotate 3.2.0 is gone, both from the gem list and from the declared dependencies. No other gem moved.
- `lib/tasks/auto_annotate_models.rake`: deleted. Its whole content was the `require 'annotate'`, the `Annotate.set_defaults` options and `Annotate.load_tasks`, all inside `if Rails.env.development?`. Nothing is left for it to do without the gem.
- `.rubocop.yml`: we removed the exclusion for `lib/tasks/auto_annotate_models.rake`, since the file no longer exists.

### What needed judgment

- The plan allowed either removing annotate or replacing it with a maintained equivalent. We removed it. Picking a replacement means adding a new development tool to the project, and that choice belongs to the maintainers. Removal is also the smaller change and is easy to reverse.
- For developers, `rake annotate_models` is no longer available, and the schema comments at the top of the model files are no longer refreshed automatically after `db:migrate` in development. The existing schema comments in `app/models` are left as they are. They'll drift as the schema changes unless a replacement is added (see follow-ups).
- We left the mention of annotate in `CHANGELOG.md` alone because it's history.

### Results

- **Resolve on 7.1.6:** `bundle lock` succeeds.
- **Resolve on 8.0.5.2 (scratch copy):** `bundle lock --update rails` succeeds, 39 gems change, 0 downgrades. connection_pool stays at 3.0.2 and minitest moves up to 6.1.0.
- **Resolve on 8.1.4.1 (scratch copy):** `bundle lock --update rails` succeeds, 39 gems change, 0 downgrades.
- **Boot:** `bin/rails runner` prints 7.1.6. `bin/rake -T` loads without error in the test environment and in the development environment, which is the only one where the deleted file did anything.
- **Tests:** 916 examples before and after, 899 passing before and after, 0 regressed, 0 missing. The 17 that don't pass are the same before and after.
- **Recorded requests:** 170 of 170 identical, 2 masked as noise, 0 unexplained differences.
- **Deprecation warnings:** 0 before, 0 after. Ruby deprecation warnings: 3 before, 3 after.
- The check was green on the first of four attempts.

### Where the roadmap was wrong or silent

- The roadmap was accurate for this stage. annotate was the only cause of the downgrade on the 8.0 and 8.1 hops, and removing it clears both.
- The scratch resolves started from the 7.1.6 lock and jumped directly to each target. They don't replace the per-hop resolves in the later stages. In particular, the roadmap's predicted connection_pool and minitest downgrades on the 7.2 hop weren't retested here, because that hop is outside this stage.
- The estimate was 2 to 4 hours. The work was smaller than that: four files, 65 lines removed, none added.

### Deprecation warnings that remain

- None from Rails (0 distinct, 0 occurrences).
- 3 Ruby deprecation warnings, unchanged by this stage.

### Follow-ups we noticed and did not do

- If the maintainers want schema comments kept current, `annotaterb` is the maintained fork of annotate and is the usual replacement. We didn't verify its Rails 8.1 support or add it. That would be a separate change, with its own rake or config file.
- The Gemfile still lists other gems the roadmap flags as having no release since 2022 (chronic, coffee-rails, gelf, nifty-utils, sass-rails, turbolinks). They don't block resolution and are outside this stage.

### Checks, before and after

| Check | Before | After |
|---|---|---|
| Examples run | 916 | 916 |
| Examples passing | 899 | 899 |
| Passing examples that now fail or are gone | | 0 |
| Rails deprecation warnings (distinct / occurrences) | 0 / 0 | 0 / 0 |
| Ruby deprecation warnings | 3 | 3 |
| Recorded HTTP behaviors identical | | 170 of 170 |

### Independent review

An independent review pass, which had no part in writing this stage, read the framework's component changelogs for the hop and every framework call the test suite loads and never runs, compared the change with any upgrade work the project has in flight, and tried to break it. It's a timed and recorded step of our process. No person has reviewed this stage yet.

- **Verdict:** pass
- **Findings:** 4, of which 4 the checks had not caught
- **Differences the review asked us to declare:** none
- **Rounds:** 1
- **Review time:** 4 minutes for the round that passed, 4 minutes over all rounds

### Diff

```
.rubocop.yml                        |  1 -
 Gemfile                             |  1 -
 Gemfile.lock                        |  4 ----
 lib/tasks/auto_annotate_models.rake | 59 -----------------------------------------------------------
 4 files changed, 65 deletions(-)
```

- **Attempts:** 1
- **Versions after:** rails 7.1.6, ruby 3.4.6
