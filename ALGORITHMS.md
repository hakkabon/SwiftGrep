# Algorithms & Theory

This document is the theoretical companion to [README.md](README.md). It explains, in depth, the two ideas that make `SwiftGrep`'s regular core efficient and elegant — **Brzozowski derivatives** and **Antimirov's partial derivatives** — and then turns to the feature that *isn't* elegant: backreferences, why they are not a small addition but a step into a different and much harder computational world, and exactly what kind of "harder" that is.

## Table of Contents

1. [Two Philosophies of Regex Matching](#1-two-philosophies-of-regex-matching)
2. [Foundations: Brzozowski Derivatives](#2-foundations-brzozowski-derivatives)
3. [Antimirov's Partial Derivatives — The Elegant Fix](#3-antimirovs-partial-derivatives--the-elegant-fix)
4. [From Theory to Code: Mapping the Construction onto `SwiftGrep`](#4-from-theory-to-code-mapping-the-construction-onto-swiftgrep)
5. [From NFA to Minimal DFA: Brzozowski's Double-Reversal Trick](#5-from-nfa-to-minimal-dfa-brzozowskis-double-reversal-trick)
6. [Stepping Outside Regularity: Why Captures Need an Environment](#6-stepping-outside-regularity-why-captures-need-an-environment)
7. [The Backreference Trap](#7-the-backreference-trap)
8. [Intractable, Not Impossible: Placing Backreferences on the Complexity Map](#8-intractable-not-impossible-placing-backreferences-on-the-complexity-map)
9. [Why `.intersection` and `.negation` Are Different — and Currently Unfinished](#9-why-intersection-and-negation-are-different--and-currently-unfinished)
10. [Summary Table](#10-summary-table)
11. [Further Reading](#11-further-reading)

---

## 1. Two Philosophies of Regex Matching

Almost every regex engine you've used — PCRE, Python's `re`, Java's `Pattern`, JavaScript's, Swift's `NSRegularExpression`/ICU — is a **backtracking virtual machine**. It compiles a pattern into a sequence of instructions (try this branch, and if it later fails, rewind and try the next one), and runs it like a tiny depth-first search over possible parses of the input. This is simple to implement and, crucially, easy to extend with features that don't fit cleanly into formal language theory: backreferences, lookaround, possessive quantifiers. The price is that backtracking search can be exponential in the length of the input for innocuous-looking patterns — the well known ReDoS (Regular-expression Denial of Service) class of bugs, where a pattern like `(a+)+b` takes milliseconds on a matching string and minutes or hours on a long string of `a`s with no trailing `b`.

The other philosophy, and the one `SwiftGrep` is built on, is to compile the pattern into a genuine **finite automaton** and run the input through it. A finite automaton, deterministic or not, processes each input character in time independent of how many "choices" the pattern seems to offer, because all of those choices are explored *in parallel*, as a set of simultaneously-active states, rather than one at a time with backtracking. The classic catastrophic-backtracking patterns are simply not catastrophic here: the relevant question is never "how many ways could this match fail and need retrying," it's "how many distinct states can the automaton be in," and for a regular pattern that number is bounded by the size of the pattern itself, not the size of the input.

The cost of the automaton-based philosophy is the mirror image of the backtracking engine's strength: it is straightforward only for genuinely **regular** languages. Anything that requires memory of the input beyond "which state am I in" — and a backreference is exactly that — has to be bolted on as a separate mechanism. Section 6 onward is about that bolt-on, and why it can never be as clean as the regular core.

## 2. Foundations: Brzozowski Derivatives

In 1964, Janusz Brzozowski published a beautifully direct way to turn a regular expression into a deterministic automaton without ever drawing a transition diagram by hand. The idea: define, for a regular expression `R` and a character `c`, the **derivative** `∂_c(R)` — another regular expression, denoting exactly the set of suffixes that complete a match of `R` after `c` has already been consumed:

```
L(∂_c(R)) = { w | c·w ∈ L(R) }
```

The derivative is defined recursively over the structure of `R`:

- `∂_c(∅) = ∅`, `∂_c(ε) = ∅` — there's nothing left to derive from a dead or already-finished expression.
- `∂_c(c) = ε`, and `∂_c(d) = ∅` for any other literal `d ≠ c`.
- `∂_c(R₁ | R₂) = ∂_c(R₁) | ∂_c(R₂)`.
- `∂_c(R₁R₂) = ∂_c(R₁)R₂ | (if R₁ is nullable) ∂_c(R₂)` — if `R₁` could itself already be finished (is "nullable," i.e. matches the empty string), the derivative can also fall through to `R₂`.
- `∂_c(R*) = ∂_c(R)R*`.

`isNullable` in `Derivative.swift` is exactly Brzozowski's `ε(R)` predicate ("does `R` accept the empty string"), and you can see the family resemblance between his concatenation/star rules above and the ones implemented for `.concat`/`.star` in this codebase.

This gives you, for free, a recipe for a DFA: treat each *distinct* regular expression reachable by repeatedly differentiating `R` as a state, and you have a deterministic automaton (one outgoing transition per character, because `∂_c` is a function, not a relation). The catch — and it's a real one — is the word *distinct*. `∂_a(a*) = a*`, so far so good; but `∂_a(a*a*) = a*a* | a*`, and differentiating *that* introduces yet another syntactically different expression denoting the same language, and so on. To get a finite automaton out of this, you need to recognize when two syntactically different derivative expressions denote the *same language* (formally, you need to work modulo the equational theory of regular expressions — associativity, commutativity, and idempotence of `|`, an "ACI" theory), or the state space can grow without bound. Brzozowski's original paper handles this by reducing to an explicit canonical/disjunctive normal form for `|`; in general, deciding regex equivalence to do this minimization eagerly is itself a non-trivial (PSPACE-complete) problem, so practical Brzozowski-derivative implementations either bound it heuristically or accept a possibly-large intermediate state space before cleanup.

## 3. Antimirov's Partial Derivatives — The Elegant Fix

Valentin Antimirov's 1996 paper ("Partial derivatives of regular expressions and finite automaton constructions") asks a sharper question: instead of insisting that differentiating `R` produce *one* combined regular expression (forcing you to immediately decide how to combine alternatives into a single term), what if it's allowed to produce a *set* of simpler expressions — one for each distinct way the match could continue?

This is the **partial derivative**, traditionally written `∂_c(R)` as well (context disambiguates it from Brzozowski's version), defined so that its *union* recovers the Brzozowski derivative: `⋃ ∂_c(R) ≡ ∂_c^{Brzozowski}(R)`. The rules look almost identical to Brzozowski's, with one structural difference — concatenation and star distribute the *tail* expression over a *set*, rather than combining everything into one node:

- `∂_c(c) = {ε}`, `∂_c(d) = {}` for `d ≠ c`.
- `∂_c(R₁ | R₂) = ∂_c(R₁) ∪ ∂_c(R₂)`.
- `∂_c(R₁R₂) = { S·R₂ | S ∈ ∂_c(R₁) } ∪ (∂_c(R₂)` if `R₁` is nullable, else `{}`).
- `∂_c(R*) = { S·R* | S ∈ ∂_c(R) }`.

Why does this small change matter so much? Because each *element* of the set is now a candidate NFA state in its own right, and you never have to merge alternatives into one combined term — alternation is handled by simply having *more elements in the set*, which is precisely what nondeterminism in an NFA already means. Antimirov proves a remarkable bound on this construction: **the total number of distinct partial derivative terms reachable from a regular expression `R` is at most the number of alphabetic symbols (leaves) in `R`, plus one.** In other words, the size of the resulting NFA is *linear* in the size of the pattern — not just "finite," but tightly, syntactically bounded, with no equational reasoning about regex identities required to prove it. You get the bound for free, just by inspecting the structure of `R`.

Compare this to the two more traditional ways of getting an ε-free NFA from a regex:

- **Thompson's construction** builds one NFA state per AST node and links them with ε-transitions; matching then requires computing ε-closures at every step, and naive implementations pay a real runtime cost for that (closure computation is itself a small reachability search). It also doesn't give you the same tight, leaf-count-bounded state guarantee.
- **Glushkov's construction** (the "position automaton") creates one state per leaf and is also linear-sized, but the construction is comparatively fiddly — it requires precomputing "first," "last," and "follow" sets over the AST before a single state can be built.

Antimirov's construction needs none of that pre-analysis. It is, quite literally, "the regex is its own state, and there's a function that tells you where to go next." That's the elegance the original project notes were pointing at, and it's not an exaggeration: it converts a *static description* of a language into a *dynamic machine* for recognizing it, in one uniform recursive function, with a state-count guarantee that requires no extra machinery to prove.

## 4. From Theory to Code: Mapping the Construction onto `SwiftGrep`

The mapping from the theory above onto this codebase is almost embarrassingly direct:

| Theory | Code |  
|---|---|  
| A regular expression term | `Regex` (`Expression.swift`) |  
| `ε(R)`, nullability | `Regex.isNullable(env:)` (`Derivative.swift`) |  
| The partial derivative `∂_c(R)` | `Regex.derivative(with:env:) -> Set<DerivResult>` (`Derivative.swift`) |  
| An ε-free NFA built by exhaustively differentiating | `Regex.buildNFA(alphabet:) -> Automaton<Regex>` (`Automaton.swift`) |  

`buildNFA` is a worklist/fixpoint algorithm: start with `{self}` as the frontier, and for every state popped off the worklist, compute its derivative against every symbol in the alphabet, recording any newly-discovered term as both a new state and a new entry in the worklist. This *is* the Antimirov construction, written exactly as the textbook description above would suggest, with `Regex` values doing double duty as both AST nodes and automaton states — no separate "state" type is needed, because under Antimirov's construction, the regex *is* the state.

### The smart constructors are not cosmetic

Look closely at `Expression.swift`'s `Regex.con`, `Regex.alt`, and `Regex.cap`. They aren't just convenience wrappers — they implement the algebraic simplifications (`∅` is absorbing for concatenation, `ε` is the identity for concatenation, nested alternations flatten, duplicate alternatives collapse via `Set`) that the Antimirov bound's proof actually depends on. Without `Regex.con` collapsing `∅ · R` down to `∅`, for instance, the concatenation derivative rule `{ S·R₂ | S ∈ ∂_c(R₁) }` would happily manufacture states like `∅R₂`, `∅∅R₂`, `∅∅∅R₂`, and so on — syntactically distinct terms denoting the same dead language, each one a "zombie" state that the worklist in `buildNFA` would dutifully explore forever. The smart constructors are what keep the state space the Antimirov theorem promises *actually* small in practice, not just in principle; they're doing the same job that an explicit equational-rewriting step does in some treatments of derivative-based matching, just folded into term construction itself so it happens automatically, every time, for free.

### `isNullable` as the accept test

`buildNFA` marks a discovered state as accepting exactly when `current.isNullable(env: [:])` — i.e., when the *current* term, with no captured environment, would itself match the empty string. This is exactly the role nullability plays in both Brzozowski's and Antimirov's constructions: an NFA state is final precisely when the term it represents has "nothing left to require."

## 5. From NFA to Minimal DFA: Brzozowski's Double-Reversal Trick

`Automaton.swift` implements three independent operations:

- **`reversed()`**: reverses every edge, and swaps the roles of initial and accepting states. This is the standard *automaton reversal*, and on its own it computes an automaton for the **reverse language** (the set of all strings `wᴿ` such that `w` is in the original language).
- **`determinized()`**: the classic **subset (powerset) construction** — at each step, a *set* of original states becomes a single new state, transitioning to the union of wherever its members could go.
- **`minimized()`**, defined as a one-liner: `self.reversed().determinized().reversed().determinized()`.

That one-liner is **Brzozowski's minimization algorithm**, and the fact that it's a one-liner is precisely the point — it is famous for being almost suspiciously simple for what it accomplishes. Reverse, determinize, reverse again, determinize again, and — regardless of whether you started with a deterministic or nondeterministic automaton — what comes out the other end is provably the **unique minimal DFA** for the language, with no explicit Myhill-Nerode equivalence-class computation (no Hopcroft-style partition refinement, no table-filling algorithm) anywhere in sight.

### Why it works, intuitively

Two states in a DFA are "the same" (mergeable, in the Myhill-Nerode sense) exactly when they have identical *future* behavior: every input they could possibly see from here on leads to the same accept/reject outcome. Determinizing an automaton's reversal effectively groups together every original state that shares the same set of strings that can reach it from an accepting state — i.e., the same possible futures when the automaton is read backwards, which is to say the same possible pasts in the forward direction. Doing that once (reverse, then determinize) produces an automaton with no two states that are indistinguishable when looking *backward*; doing it a second time, on the reversal of *that* result, performs the same collapsing in the *forward* direction — and a state distinguishable from no other state in either direction is exactly the Myhill-Nerode definition of a minimal-automaton state. The theorem (originating with Brzozowski, and reproved in several modern treatments, including category-theoretic ones) guarantees this is not just *a* minimal automaton up to relabeling, but canonically *the* minimal one.

### The catch: determinization can be expensive

This elegance has a cost. Powerset construction can, in the worst case, blow up the state count exponentially (a set of `n` NFA states has `2ⁿ` possible subsets), and `minimized()` runs it **twice**. The classical worst-case bound for the whole double-reversal algorithm is therefore doubly exponential in the original automaton's size. In practice — and this is well documented in the automata-theory literature — the algorithm tends to perform far better than that bound suggests on real-world automata (often beating asymptotically faster algorithms like Hopcroft's `O(n log n)` partition refinement in wall-clock time on small-to-medium inputs), but it is a real, known tradeoff: simplicity and a one-line implementation, in exchange for no worst-case guarantee. For a `grep`-style tool working with hand-typed patterns rather than adversarially constructed ones, this tradeoff is entirely reasonable; it would be a poor choice for, say, compiling untrusted regular expressions submitted by third parties.

## 6. Stepping Outside Regularity: Why Captures Need an Environment

Everything above describes the *static* path: `Regex` → `Automaton<Regex>` → minimal DFA, fully precomputed, with no reference to any particular input string. That path is sound exactly because a regular language's accept/reject decision never needs to remember anything about the input except "which state am I currently in" — and "which state" is determined entirely by the *suffix of the pattern* still left to match, never by *which characters were actually consumed* to get there.

A capturing group breaks that property the moment you ask "what text did group 1 actually match?" — the answer depends on which characters were consumed, not just on which state you're in. `SwiftGrep` accommodates this without redesigning the whole engine: `derivative(with:env:)` already threads an `env: [Int: String]` dictionary through every call, and `Derivative.swift`'s `.capture` case records, via `DerivResult.captures`, *which* group IDs were "active" (i.e., digesting input) during a given transition. `RegexEngine.firstMatch(in:)` (`Engine.swift`) then does the bookkeeping: every `MatchState` carries its own `env`, and every time a transition reports a capture ID as active, that character gets appended to `newEnv[capId]`.

This is still, notice, entirely compatible with the *regular* part of the theory: as long as you never read a backreference, the capture environment is write-only "exhaust" that rides along for the user's benefit but never influences which states are reachable or which strings are accepted. The language `(a)(b)` defines is exactly as regular as `ab`; capturing is a reporting feature, not an expressive one.

## 7. The Backreference Trap

A backreference changes that. `\1` *reads* the capture environment to decide whether a transition is even legal: in `Derivative.swift`'s `.backreference` case, the current state's available transitions literally depend on what string is sitting in `env[1]`. That's no longer "exhaust riding along for reporting" — it's now part of the recognition mechanism. And once a language's accept/reject decision depends on *remembered input* rather than purely on *current state*, you have left the land of regular languages.

The canonical proof of this is short and worth walking through, because it's the same shape of argument used throughout formal language theory:

> Consider `L = { ww | w ∈ Σ* }` — the language of strings that are some block of text immediately repeated (`"abab"`, `"xyzxyz"`, the empty string, etc.). A single backreference expresses this directly: a capture group matching anything, followed by a backreference to it. But `L` is **not regular**: by the pumping lemma for regular languages, any purported DFA for `L` with `n` states could be forced, by pumping a cycle inside the first half of the string, into accepting strings that are not of the form `ww`. (`L` is not even **context-free** — it fails the pumping lemma for context-free languages too, a standard textbook result — so a backreference doesn't just nudge you from "regular" to "context-free," it skips past context-free languages entirely.)

So a single backreference is, formally, enough to make the pattern's language fall outside both the regular and the context-free hierarchy — which is exactly why it cannot be handled by precompiling to *any* finite automaton (deterministic or not), and why `RegexEngine` has to fall back to carrying live, growing state (the capture environment) through an online simulation instead. This is the "trap": backreferences look, syntactically, like a tiny addition to a regex (one more escape sequence), but semantically they buy you a fundamentally more powerful, and fundamentally more expensive, kind of pattern.

## 8. Intractable, Not Impossible: Placing Backreferences on the Complexity Map

It's worth being precise here, because "non-regular" gets casually equated with "impossible" or "undecidable," and that's not quite right — there's a real and useful distinction between **intractable** and **undecidable** that this exact feature sits right on top of.

- **Undecidable** means no algorithm exists, even given unlimited time, that always gives a correct yes/no answer. The canonical example is the Halting Problem.
- **Intractable** (in the everyday complexity-theory sense) means an algorithm *does* exist, and is even guaranteed to terminate, but every known algorithm takes time that grows explosively (typically exponentially) with input size, and — for an NP-complete problem — no polynomial-time algorithm is known, and most researchers believe (though it remains formally unproven) that none exists.

**The basic question "does this string match this backreferenced pattern" is in the second category, not the first.** It's straightforwardly decidable: you can always brute-force it, by trying every possible assignment of substrings to each backreferenced variable and checking whether any assignment makes the pattern's backreference-free skeleton match. A. V. Aho showed in 1990 that this matching problem is **NP-complete** — and there's a nice piece of folklore attached to that result: in 2001, Mark-Jason Dominus posted an explicit reduction from the SUBSET-SUM problem to backreferenced regex matching, giving a very concrete, constructive feel for *why* it's NP-hard (subset-sum is itself a classic NP-complete problem — "does some subset of these numbers sum to exactly this target" — which a backreferenced pattern can effectively be made to simulate by using one capture group per number and a single backreference to verify the total). NP-complete is the textbook definition of "intractable": brute force always works eventually, but the brute force is exponential, and there's no known shortcut.

It's exactly the same shape of difficulty that arises elsewhere in computer science whenever a problem requires *verifying a guess* rather than *constructing an answer directly* — the boundary between "polynomial-time decidable" (P) and "exponential-time-seeming, but at least polynomial-time checkable" (NP) is one of the deepest open questions in the field (P vs. NP), and the practical consequence is the same whether the NP-complete problem at hand is Boolean satisfiability, the decision variant of the traveling salesman problem, graph coloring, or — as it happens — matching a string against a regular expression with backreferences.

There is, in fact, an *even harder* tier hiding nearby, and it does land on the undecidable side of the line: while *matching a specific string against a specific backreferenced pattern* is "merely" NP-complete, *higher-order questions about backreferenced patterns as a whole* — does this pattern match every possible string (universality)? do these two patterns match exactly the same set of strings (equivalence)? does the language of one pattern contain the language of another (inclusion)? — have been shown in later research to be genuinely **undecidable** once backreferences are in the mix, even under quite restrictive conditions on how the backreferences may be used. So the honest picture has three tiers, not two: a finite-automaton-based engine like the regular core of `SwiftGrep` answers all of these questions (including equivalence, via minimization — two regular-core patterns are equivalent exactly when their minimal DFAs are isomorphic) essentially for free; adding backreferences makes the single most basic question (does this one string match) merely *intractable*; and it makes several natural follow-up questions about the *pattern itself* flatly *undecidable*.

### How `SwiftGrep` stays out of the worst of it

`RegexEngine`'s approach to backreferences is more modest than "solve the NP-complete problem in general," and that modesty is exactly what keeps it fast in practice. Because matching proceeds left to right and a backreference's value is only ever *read* after the corresponding group has *already* finished capturing earlier in the same left-to-right pass, the engine is never required to *guess* what a backreferenced variable should be and check the guess combinatorially (which is where the NP-hardness of the general problem comes from — Dominus's SUBSET-SUM reduction relies on patterns where many backreferenced variables' correct values are entangled with each other and have to be guessed jointly). By the time `Derivative.swift`'s `.backreference` case runs, `env[id]` is already a concrete, already-decided string — the comparison `chars[0] == c` is a simple, deterministic literal check, not a search over possibilities. This puts the patterns `SwiftGrep` can express in something close to what the literature calls patterns with a small, statically bounded "active variable degree," or "memory-deterministic" regex — informal terms for exactly the kind of backreference usage (a variable is fully determined before it is ever referenced again) that several papers on this topic show *can* be matched efficiently, in contrast to the fully general, NP-hard case where a backreference's value is still genuinely undetermined (e.g., nested inside an unresolved alternation) at the moment it needs to be checked.

## 9. Why `.intersection` and `.negation` Are Different — and Currently Unfinished

The `Regex` enum includes `.intersection` and `.negation` cases, and `Derivative.swift` calls `fatalError()` on both. This isn't an oversight so much as an honest admission of a real gap: regular languages *are* closed under intersection and complement, so these operators don't carry the same intractability baggage backreferences do — but Antimirov's *partial-derivative* formulation doesn't extend to them as cleanly as it does to concatenation, alternation, and star.

The reason is structural: alternation, concatenation, and star all have derivative rules that operate **termwise** — you can compute the partial derivative of each alternative independently and union the results, because membership in `R₁ | R₂` is a *disjunction* over independently-checkable conditions. Intersection and negation are different: whether a string is in `R₁ & R₂` (or in `¬R`) is a property of the *whole automaton's current configuration*, not something you can decide by looking at one term's derivative in isolation — you need to track, simultaneously, "where would I be in `R₁`" *and* "where would I be in `R₂`" as a single combined state, which is precisely what the (deterministic) subset construction — i.e. `determinized()` — already exists to compute. In other words: Boolean combinators are naturally a feature of **Brzozowski's deterministic** derivative (where a state already is a single, specific configuration you can complement or conjoin against another single, specific configuration), not of Antimirov's inherently **nondeterministic, multi-term** partial derivative. Using `.intersection`/`.negation` correctly in this codebase would mean routing through `determinized()` first (turning the Antimirov NFA into an explicit DFA) rather than calling `derivative` directly term-by-term — which is exactly what the comment above the `fatalError` calls in `Derivative.swift` says, and exactly why it's marked as a fallback that hasn't been implemented yet, rather than as something fundamentally impossible.

## 10. Summary Table

| Question | Regular core (no backreferences) | With backreferences |  
|---|---|---|  
| Can it be compiled to a finite automaton ahead of time? | Yes — `Automaton.buildNFA` / `minimized()` | No — requires online simulation (`RegexEngine`) |  
| Is "does string `s` match pattern `R`" decidable? | Yes, in time linear in the input length once compiled | Yes, but no known polynomial algorithm (NP-complete) |    
| Is "do two patterns match the same language" decidable? | Yes — compare minimal DFAs | Undecidable in general |  
| What CS concept governs the difficulty? | Myhill-Nerode equivalence / state minimality | NP-completeness (intractability) and, for meta-questions, undecidability |  
| How does this codebase implement it? | `Derivative.swift` + `Automaton.swift` | `Derivative.swift`'s `.backreference` case + `Engine.swift`'s `MatchState.env` |  

## 11. Further Reading

- J. A. Brzozowski, *"Derivatives of Regular Expressions,"* Journal of the ACM 11(4), 1964.
- V. M. Antimirov, *"Partial Derivatives of Regular Expressions and Finite Automaton Constructions,"* Theoretical Computer Science 155(2), 1996.
- A. V. Aho, *"Algorithms for Finding Patterns in Strings,"* in the Handbook of Theoretical Computer Science, Vol. A, Ch. 5, Elsevier, 1990 — the original NP-completeness result for matching with backreferences.
- C. Câmpeanu, K. Salomaa, and S. Yu, and related follow-up work on the formal semantics and expressive power of regexes with backreferences.
- D. D. Freydenberger, M. L. Schmid, and others on the undecidability of equivalence/inclusion/universality for backreferenced patterns, and on tractable sub-classes ("memory-deterministic," bounded "active variable degree") that can be matched efficiently.
- General automata-theory references on Brzozowski's double-reversal minimization algorithm and its worst-case-exponential-but-practically-fast behavior, including comparisons against Hopcroft's `O(n log n)` partition-refinement minimization.
