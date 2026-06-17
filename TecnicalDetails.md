## Algorithmic Description

#### The Elegance of Antimirov’s Partial Derivatives
Standard NFA construction (like Thompson’s algorithm) relies heavily on ε-transitions to glue AST nodes together. This introduces state-explosion and non-determinism that is costly to compute. **Antimirov’s Partial Derivatives** represent a radical departure: they treat the regex *itself* as a state.

When a character `c` is consumed, the "derivative" of the regex `R` is a set of regexes `{R1, R2, ...}` that represent the remaining patterns possible after matching `c`. This is mathematically beautiful because it defines an **ε-free NFA** where:
1. Each state is a `Regex` AST node.
2. The transitions are defined by the partial derivative function `pDeriv`.
3. An accepting state is simply any node where `isNullable` is true.

This elegantly converts the "formula" (the regex) directly into the "machine" (the NFA) without a middle-man, making it one of the most efficient ways to reason about formal language matching.

#### The "Trap" of Backreferences
While regular languages are easily handled by NFAs, the inclusion of **backreferences** (`\1`, `\2`) pushes the problem out of the realm of regular languages and into the **NP-Complete** class. 

Specifically, backreferences allow a regex to match patterns like $L = \{ ww \mid w \in \Sigma^* \}$. This is a classic non-regular language. Because a backreference must verify that a previously matched substring matches the *current* input, it requires memory of the past. 
- **The difficulty:** You can no longer rely on a static DFA because the "state" is no longer just the current AST node, but the current AST node *plus* the entire capture history (`Environment`).
- **The Intractability:** Matching a pattern with backreferences is equivalent to solving the **Context-Sensitive Language** matching problem. By treating them as dynamic constraints during the NFA simulation (as seen in our `MatchState`), we effectively perform a guided search through the state space. This is why `SwiftGrep` remains performant for standard usage but gracefully degrades in complexity when dealing with deeply nested backreferences.

---
