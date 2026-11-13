# Execution: the first four stages

The roadmap plans ten stages. We carried out the first four on a fork, [cedarwood-studio/postal](https://github.com/cedarwood-studio/postal), one branch and one pull request per stage. Nothing was sent to the Postal project.

Each stage is held to the same test, "same behavior, new version":

- no test example that passed before the stage may fail or disappear after it;
- no recorded HTTP response may change without a declared reason that cites the upstream change;
- the application must still start under every configuration it started under before;
- nothing may move in the lock file that Rails didn't force or the stage didn't explain;
- deprecation warnings are counted before and after.

A stage that can't meet that within four checks is stopped and written up.

Passing those checks doesn't finish a stage. An independent review pass, which had no part in writing the stage, then reads the Rails component changelogs for the hop, reads every framework call the test suite loads and never runs, compares the change with the Postal project's own upgrade work, and tries to break it in a throwaway copy. The review is timed. If it finds a defect, the stage goes back and is reviewed again. These reviews are a step of our process and not a person's review. No person has reviewed these stages yet. The promise a stage makes is no undeclared behavior change, with each declared difference sourced.

The last two checks in the list and the review didn't exist when the first three stages were first carried out. They were added after a review of that first run found a defect in the third stage that every check had passed. This document covers both runs.

## Results

| Stage | Change | Diff | Examples passing, before and after | Recorded responses identical | Checks | Review |
|---|---|---|---|---|---|---|
| Baseline | Record 170 requests and the suite's results. No code change. | none | 834 of 851 | 170 of 170 across two recordings, 2 masked as noise | | |
| [S1](https://github.com/cedarwood-studio/postal/pull/1) | 65 characterization tests | 14 files, +914 | 834 of 851, then 899 of 916 | 170 of 170 | 1 check | 1 round, passed in 24.2 min |
| [S2](https://github.com/cedarwood-studio/postal/pull/2) | Remove the `annotate` gem, which blocked Rails 8.0 | 4 files, -65 | 899 of 916, both | 170 of 170 | 1 check | 1 round, passed in 3.9 min |
| [S3](https://github.com/cedarwood-studio/postal/pull/3) | Rails 7.1.6 to 7.2.4 | 10 files, +338 -77 | 899 of 916, then 910 of 927 | 165 of 170, and the other 5 are one declared change | 6 checks | 5 rounds, the fifth passed in 12.4 min; 62.2 min in all |
| [S4](https://github.com/cedarwood-studio/postal/pull/4) | Rails 7.2.4 to 8.0.5.2 | 9 files, +236 -74 | 910 of 927, then 920 of 937 | 36 of 170, and the other 134 are one declared change | 2 checks | 1 round, passed in 18.2 min |

Those numbers are from the sandbox, a container with no network during the test run. The 17 examples that don't pass there do live DNS lookups. They were the same 17 before and after every stage.

Rails deprecation warnings were 0 before and 0 after S1, S2 and S3. S4 went from 0 to 1 distinct warning, printed 4 times as the application boots: `to_time` will keep the full time zone from Rails 8.1 on. The stage left the setting alone, since the plan changes it in a later stage. Ruby deprecation warnings went from 2 to 3 at S1, because a new test boots the SMTP server and that prints one the suite hadn't reached.

## The third stage, round by round

S3 is the Rails 7.2 hop. It's the stage that shipped a defect in the first run, so here is each round.

**As first shipped.** One commit: the Rails pin, the lock file, and one setting in the test environment. Two checks, the second green: 899 of 916 examples before and after, 165 of 170 recorded responses identical, and the other 5 declared as the "Astana" time zone change. The pull request said no application code needed to change.

**What the new start-up check shows on that commit.** Before any review, we ran the seven start-up configurations on S2 and on S3 as shipped. All seven start on S2. On S3 the one with the migration waiter switched on exits with `undefined method 'migration_context' for an instance of ActiveRecord::ConnectionAdapters::Mysql2Adapter (NoMethodError)` at `lib/migration_waiter.rb:18`. The first run's review had read that defect in the Rails source. Nothing had run it until now. The output is in `execution/evidence/boot-S3-as-shipped/`.

**Round 1, 6.7 minutes. Verdict: defect.** The review wasn't told what the first run's review had found. It read 385 changelog entries and all 16 unexecuted framework call sites, compared the branch with the project's own, and made 14 attempts to break the stage. Seven findings, none of which a check had shown. Three were defects:

- The migration waiter, found by starting the application with it on.
- The lock. The stage had run `bundle lock --update rails` without the conservative option, which moved 26 gems the hop didn't need, `mail`, `nokogiri` and `rack` among them, and dropped `psych` and `stringio` from the lock. The review measured what that did. A different version of the YAML library was loading, in an application that stores two columns as YAML.
- A behavior change the plan said this stage must declare, about where development and test take their secret key from, which the stage hadn't mentioned.

**Fix 1, 8.6 minutes.** `connection_pool.migration_context`, a spec that calls `MigrationWaiter.wait` and fails without the fix, the lock rebuilt from S2's with the conservative update (three gems move outside Rails now, each forced by a Rails constraint), and the secret key change declared with a spec.

**Round 2, 8.9 minutes. Verdict: defect.** The review checked out S2 in its throwaway copy and measured the secret key on Rails 7.1.6. It's the same before and after. The declared change doesn't happen in this application, the new spec passes on both versions, and the stage was asking for sign-off on a difference that isn't there. That traces back to an item our own roadmap review had added to the plan from a changelog entry, without running it. The roadmap was wrong on that point and execution corrected it.

**Fix 2, 6.2 minutes.** The declaration withdrawn and the spec described as what it is, a check that nothing changed.

**Round 3, 14.1 minutes. Verdict: defect.** With the stage saying "Astana" was its only behavior change, the review found a second by reading the Action Pack changelog and then measuring it. In production, a HEAD request that ends in an error page gets `Content-Length: 0` on 7.2.4 where 7.1.6 sent the page's length, and a different `Content-Type` for clients that accept anything. GET responses are the same. No recorded request could show it, because the recording runs in the test environment and none of its requests is a HEAD.

**Fix 3, 6.8 minutes.** The difference declared with its source, and three specs that pin it.

**Round 4, 20.1 minutes. Verdict: defect.** A third difference, this one in no changelog. With the Rails log switched on, the line Rails writes for each request ends differently on 7.2.4. The review found it by comparing the two installed versions and then running 52 requests on each.

**Fix 4, 7.6 minutes.** Declared, with a spec.

**Round 5, 12.4 minutes. Verdict: pass.** Two more small differences, a further change to the Rails log's error entries and the Rails console prompt. By then we had split what a review can find into two kinds. A defect breaks something, or changes a response, stored data or whether a process starts, and sends the stage back. Anything smaller is declared by the author, with its source, without another round. Both of these were the second kind, and they're declared in the pull request. This round also ran 187 requests through pages no check or earlier review had reached, on both versions: 184 answer the same to the byte and 3 differ only in a timestamp or a random boundary.

Five rounds took 62.2 minutes of review and 29.2 minutes of fixes. Every round found something real, and each thing was smaller than the one before. We don't read that as a sign that nothing is left. A framework hop changes many small things, and the last review stopped where its method ended. What we can say is that the two differences that would have reached a client's users or monitors, the process that didn't start and the changed headers, were found in rounds 1 and 3, and neither was visible to any check.

One wart is left on the branch. The last of its five commits carries the same title as the first, because a message file was reused. The tooling now refuses that. We left the commit alone, because changing it would have meant reviewing the stage again.

## What the reviews found on the other stages

**S1, 24.2 minutes, passed.** Five findings, three that no check had shown. The plan in the second roadmap asks S1 for more tests than the first run's S1 delivered: nothing runs a worker job, the tracked-link rewrite, the slow-query path or a password reset to its end. The review recorded those as risks for the stages that depend on them. It also found that the SMTP boot test reads a socket with no time limit, so the change it's there to catch would hang the suite and be reported as 0 failures.

**S2, 3.9 minutes, passed.** Four findings. The second roadmap gives S2 two changes and the stage made one. It removed `annotate` and didn't pin `json` below 3. The lock holds `json` 2.7.1 and the conservative update doesn't move it, so nothing breaks today. The pin is still owed.

**S4, 18.2 minutes, passed.** S4 is the Rails 8.0 hop, built with the wider process from the start. It took 18.6 minutes and two checks. The first check failed on 134 recorded responses that gained a `Vary` header, which the roadmap's review had predicted and the stage then declared with its source. The password reset fix went in with six examples that walk the reset from the request to the new password. They pass on 7.2.4 without the fix, and on 8.0.5.2 four of them fail if the fix is taken out. So the break the roadmap read in the Active Model changelog is real, and it's now pinned by tests.

The review read 333 changelog entries and all 16 unexecuted call sites and made 9 attempts to break the stage. It found no defect. Six findings, none of which a check had shown:

- Three differences to declare. The stage's own `Vary` declaration described the "before" wrongly for clients that send an `Accept` header, which is most of them. Error entries in the Rails log change shape again. And the message of one exception changes by two words, which shows in the application's own request log.
- Two corrections to the stage's notes, both from measuring. The notes said 5 of 6 reset examples fail without the fix. It's 4. And a developer task the notes said hadn't been measured on 8.0 now has been.
- One risk, the `json` pin, carried from every earlier review.

The stage declared the three differences and the review's verdict stood.

## The same checks on GitHub Actions

Each branch carries the recorded baseline and a checker under `.upgrade/`, and a workflow that reruns the suite and the 170 requests and compares them with the baseline.

| Branch | Run | Result |
|---|---|---|
| `upgrade/baseline`, first run, first push | [43352575036](https://github.com/cedarwood-studio/postal/actions/runs/43352575036) | Failed. See below. |
| `upgrade/baseline`, first run, after marking environment-dependent checks | [43356407993](https://github.com/cedarwood-studio/postal/actions/runs/43356407993) | Passed |
| S1 to S3, first run | [43356409900](https://github.com/cedarwood-studio/postal/actions/runs/43356409900), [43356413069](https://github.com/cedarwood-studio/postal/actions/runs/43356413069), [43356415207](https://github.com/cedarwood-studio/postal/actions/runs/43356415207) | Passed. S3 failed on its first attempt on a network-dependent test and passed on the second with no change. |
| `upgrade/baseline`, second run | [43382971124](https://github.com/cedarwood-studio/postal/actions/runs/43382971124) | Passed |
| S1, second run | [43382973974](https://github.com/cedarwood-studio/postal/actions/runs/43382973974) | Passed |
| S2, second run | [43382977532](https://github.com/cedarwood-studio/postal/actions/runs/43382977532) | Passed |
| S3, second run | [43382981247](https://github.com/cedarwood-studio/postal/actions/runs/43382981247) | Passed: 165 identical, 5 declared, all 5 observed |
| S4 | [43382984773](https://github.com/cedarwood-studio/postal/actions/runs/43382984773) | Passed: 36 identical, 134 responses with the declared `Vary` header and the 5 from S3, all observed |

The summaries each run printed are in `execution/ci/`. All five runs of the second run passed on their first attempt.

**What changed in the CI comparison.** The baseline was recorded in our sandbox, and GitHub's runner is a different environment running the same commit. On the first run two things differed there: 28 examples that depend on the network, and five pages whose time zone list put two zones, Casablanca and Dublin, at a different offset. The first run marked the 28 examples as reported and not gated, and stopped comparing the bodies of those five pages at all. Those were the five pages that carry S3's "Astana" change, so the first S3 run on GitHub reported 170 identical responses and never saw the one difference the stage declared.

The comparison now masks single values. On those five pages it ignores the four lines for Casablanca and Dublin, two from each environment, and compares everything else. It also fails if a difference a stage declares is hidden by a mask, or isn't observed in the run. The second S3 run above reports 165 identical and 5 declared, the same as the sandbox.

Bodies are compared in full for 163 of the 170 requests and with those values masked for 5. The remaining 2 contain values the application generates at random and aren't compared in either place.

## What the first run missed, and what the second finds

After the first run, a review found four lines that its search had missed. This table sets the eight lines the two had found between them against the second run.

| Hop | Where | First run's search | Second run, before its review | How the second run finds it |
|---|---|---|---|---|
| 7.2 | `config/environments/test.rb:28`, `show_exceptions` | Found | Found | A rule from the release notes |
| 8.1 | `db/schema.rb:13`, sorted columns | Found, and called a break | Found, and read as not a break at this target | Rails 8.1.4 reverted the sorting. The Active Record changelog says so, and the first run and its review both missed that |
| 7.1 defaults | `app/models/credential.rb:34` and `app/models/webhook_request.rb:37`, `serialize` without a coder | Found | Found | A rule from the configuration guide |
| 7.2 | `lib/migration_waiter.rb:18`, `migration_context` | Missed | Found | A rule written after the review. Also one of five framework calls the suite loads and never runs, changed in the project's own branch, and a start-up configuration that fails when the stage runs |
| 8.0 | `app/models/concerns/has_authentication.rb:8`, password reset token | Missed | Found | A rule from the Active Model changelog, written after the review. Nothing else points at it |
| 8.1 | `app/lib/worker/process.rb:164` and `:256`, `Benchmark` | Missed | Found | The `benchmark` gem leaves the lock on that hop and the search for its constant finds both lines. Also a rule written after the review, and the project's own work adds the gem |
| 7.1 and 8.0 | `json` 3 and `quirks_mode` | Missed | Found | A rule on the lock file, written after the review. The project's 7.2 branch pins the gem |

Read that table with one caution. The rules for the four missed lines were written because the first review had named them, so the second run finding them shows the rules fire. Three of the four are also caught by a measurement that didn't know the answer. The password reset break isn't. It rests on one rule, taken from a changelog we now read as a matter of course.

**What the second run found that neither the first run nor its review had:**

- `cgi` leaves the lock on the 8.0 hop, and `lib/postal/config_schema.rb:80` and `lib/postal/message_parser.rb:121` use it without requiring it.
- The 11 items from the roadmap's review, listed in `ROADMAP.md`. Six are things no check in the plan would have shown.
- On S3, the lock that moved 26 gems too many, the HEAD headers on error pages, the Rails log line, the error log entry and the console prompt.
- On S4, three differences the stage hadn't declared or had described wrongly, and a `to_time` deprecation warning that first appears on 8.0.

**What is still missed, as far as we know:**

- One item the second run got wrong: the secret key change it told S3 to declare doesn't happen. A review caught it by measuring.
- Anything in the six stages that haven't run.
- Anything on a path that no changelog entry, no dropped gem, no unexecuted call and no start-up configuration points at. The Rails log line was one of those, and a review found it by comparing the installed versions. We can't say how many more there are.

## Where the roadmap was wrong or silent

- **The secret key declaration**, above.
- **S1 and S2 were carried out against the first run's plan.** The second roadmap asks more of both. The reviews list what's owed: the `json` pin, and tests for the worker's job loop and the slow-query path. S4 has since added the tests for the tracked-link rewrite and the password reset flow.
- **`cgi` on 8.0.** The roadmap said two files use `CGI` without requiring it. S4 measured something narrower: another of the application's files requires it first, and Ruby 3.4 still ships the library, so the lines wouldn't have failed on this Ruby. Naming the gem in the Gemfile is still the right change, for a different reason than the roadmap gave.
- **`bin/rails app:update`.** The second roadmap puts it at the start of each hop. S3 didn't run it, and its notes say so.
- **From the first run, still true:** the "Astana" change wasn't in the first rules file and was caught by the recording; the first report's baseline sentence claimed more than its runs showed; the first lock for S3 wasn't conservative.

It got these right. The conservative resolve it predicted for 7.2 is the lock S3 now has, gem for gem. `annotate` was the only blocker. Every break it listed for 7.2 was real when run.

## Where an operator stepped in

These are the steps the checks and reviews didn't take by themselves. `execution/record.json` has each with its time. Since the second run the tooling writes that file itself.

1. **Turning off the project's own CI workflow on the fork**, in the first run. It builds and publishes a container image. It started on our first push, and we canceled it within seconds and disabled it. Its jobs show as canceled and nothing was published.
2. **Deciding what to do about the failed baseline run on GitHub**, in the first run, and running the calibration again in the second with the narrower masks.
3. **Running the start-up configurations on S3 as shipped**, to see whether the new check alone caught the defect. It did.
4. **Giving the start-up check a loaded schema.** Our first attempt at item 3 ran against an empty database, and the migration waiter configuration failed on both versions for that reason. We added the schema load and ran it again.
5. **Sending S3 back in for more review rounds.** The tooling stops after two reviews in one run. We restarted it twice.
6. **Changing the review's rules between rounds 4 and 5**, to separate defects from differences that only need declaring. That was a judgment call, and it's ours.
7. **Publishing.** Pushing the branches and opening or updating the pull requests is a separate command, on purpose. The step that edits code can't push anywhere, and the command refuses a stage with no passing review.

## Time and effort, measured

| Step | Wall-clock time |
|---|---|
| First roadmap, from a repository URL to a checked report | 16.1 min |
| Second roadmap, the same, with the wider measurements | 36.9 min, of which the independent review is 11.9 min |
| Baseline for execution: the request set, the suite, two recordings | 26.8 min |
| S1 | 12.7 min, then 24.2 min of review |
| S2 | 5.9 min, then 3.9 min of review |
| S3, first run | 14.9 min |
| S3, second run: four fixes | 29.2 min |
| S3, second run: five reviews | 62.2 min |
| S4 | 18.6 min, then 18.2 min of review |
| The operator's steps, above | not timed |
| A person's review | not done |

Inside the second roadmap's 36.9 minutes: 8.1 for the sandbox and the lookups (installing gems, three resolver runs, the suite, a recheck with the network on, seven start-ups), 15.1 for working out how to run the suite and writing and checking the report, 11.9 for the independent review, and 1.9 for a read of the prose.

The suite takes 3 minutes 42 seconds. Every check runs it in full, so a codebase with a slower suite would take proportionally longer per stage.

All of it is machine time. The estimate in the roadmap is in an engineer's attended hours, and none of the times above has a person's time in it. They don't measure the same thing, so we don't compare them.

## What this doesn't show

- Stages S5 to S10. Rails 8.1 is still ahead, and the defaults stages touch cookies, sessions and how stored data is serialized.
- A codebase with real blockers. Postal had one blocking gem out of 162, and it was a development tool. An app with a dozen blocked gems and a thin suite would look very different, and this sample says nothing about how.
- What a senior engineer's review would add to these review passes, or cost.
- Anything in production, meaning real configuration, data, traffic or a deploy.
