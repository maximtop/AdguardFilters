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

## Filter policy

- The site's own advertising (first-party ads): close without a rule.
- Paywalls: close without a rule.
- German anti-adblock walls: close without a rule.
- Any other anti-adblock wall: write a rule only after the network log shows the detector script;
  without it, hand the report to a maintainer.

## Maintainer rules

How this repository's maintainers write rules. These rules come on top of the documents above and
take precedence over the agent's own judgement of which rule is best. Maintainers add a rule here
whenever they keep fixing the agent's proposals the same way.

### Anti-adblock popups: disable the detector, do not hide the popup

When a site shows an anti-adblock popup or wall, do not propose a cosmetic rule that hides the
popup: the detector keeps running, so the site can still lock content or show the popup in another
layout. Find the script that detects the blocker and neutralize it with a scriptlet, usually
`set-constant` or `abort-on-property-read` on the detector's property.

Many sites share one detector, and `BaseFilter/sections/antiadblock.txt` groups its rules by the
detector: a comment naming it, then one rule listing every site. When the detector is already
there, add the reported domain to that rule instead of writing a new one.

Example, AdguardTeam/AdguardFilters#243463 (wzielonej.pl, anti-adblock popup):

- Agent's rule, hides the popup only: `wzielonej.pl###tie-popup-adblock`
- Maintainer's fix: `wzielonej.pl` added to the shared rule under
  `! 'tie.ad_blocker_detector' (tie-popup-adblock)`, which is
  `#%#//scriptlet("set-constant", "tie.ad_blocker_detector", "")`
