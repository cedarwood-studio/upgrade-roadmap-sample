## Upgrade parity

| Check | Baseline | This commit |
|---|---|---|
| Examples run | 851 | 851 |
| Examples passing | 834 | 840 |
| Passing at baseline, failing or missing now | | 11 |
| Failing at baseline, passing now | | 17 |
| New examples (failing) | | 0 (0) |
| Rails deprecation warnings (distinct / occurrences) | 0 / 0 | 0 / 0 |
| Recorded HTTP behaviors identical | 170 | 165 |
| Differences with a declared reason / without | | 0 / 5 |

Recorded on Rails 7.1.6, Ruby 3.4.6.

**Result:** parity does not hold.
- test parity: 11 regressed, 0 passing examples missing, 0 new examples failing
- behavior parity: 5 difference(s) with no declared reason: admin: GET /org/acme/settings: body; admin: GET /settings: body; admin: PATCH /org/acme/settings invalid: body; admin: PATCH /settings invalid: body; member: GET /org/acme/settings: body
- regressed: `./spec/lib/dns_resolver_spec.rb[1:1:3]`
- regressed: `./spec/lib/dns_resolver_spec.rb[1:1:4:2]`
- regressed: `./spec/lib/dns_resolver_spec.rb[1:3:2]`
- regressed: `./spec/lib/dns_resolver_spec.rb[1:3:3:2]`
- regressed: `./spec/lib/dns_resolver_spec.rb[1:4:2]`
- regressed: `./spec/lib/dns_resolver_spec.rb[1:4:3:2]`
- regressed: `./spec/lib/dns_resolver_spec.rb[1:5:2]`
- regressed: `./spec/lib/dns_resolver_spec.rb[1:5:3:2]`
- regressed: `./spec/lib/dns_resolver_spec.rb[1:6:2]`
- regressed: `./spec/lib/dns_resolver_spec.rb[1:6:3:2]`
- regressed: `./spec/lib/dns_resolver_spec.rb[1:7:2]`
