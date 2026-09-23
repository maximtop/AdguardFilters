# Run instruction: AdguardFilters

The run's blocker is the built-in AdGuard Browser Extension in Chromium — the host prepares,
launches and reads it back itself. This file adds nothing to that route but the guidance
documents this repository writes its rules against.

application: adguard-extension

The run loads its filter guidance at start from these role documents:

- [AdGuard filter syntax](https://github.com/AdguardTeam/KnowledgeBase/blob/master/docs/general/ad-filtering/create-own-filters.md)
- [AdGuard filter policy](https://github.com/AdguardTeam/KnowledgeBase/blob/master/docs/general/ad-filtering/filter-policy.md)
- [AdguardFilters contributing guide](https://github.com/AdguardTeam/AdguardFilters/blob/master/CONTRIBUTING.md)

Rule placement is deliberately not declared: this repository files rules per language and per
rule kind across `<Filter>/sections/*.txt`, and one declaration would force every rule into a
single file. Choose the file from where the repository already keeps rules like the new one: the
file that holds the reported site's rules, otherwise the one that holds rules of the same kind.
