Top-level agents should delegate non-trivial work to the narrowest available specialist.

| Need                                                       | Specialist    |
| ---------------------------------------------------------- | ------------- |
| Local code or configuration discovery                      | `explore`     |
| External or organization documentation and API research    | `scout`       |
| Rust architecture, API, or type design                     | `rust-design` |
| Rust implementation or refactoring                         | `rust`        |
| Non-Rust implementation or refactoring                     | `implement`   |
| Bounded tests, lint, builds, or noisy shell output         | `verify`      |
| Candidate review of a diff, design, or implementation      | `review`      |
| Work with no narrower specialist                           | `general`     |

Route Rust work to `rust`, not `implement`. Dispatch independent workstreams in parallel; serialize only when one depends on another's output.

Top-level agents must delegate web research to `scout` instead of doing it directly. Plan may dispatch only `explore`, `review`, `rust-design`, `scout`, and `verify`; implementation requires a Build handoff.

Every subagent starts an independent session with its own prompt, permissions, tools, and applicable global/project instructions. It does not inherit the caller's conversation, role permissions, loaded skills, or earlier findings.

Each delegation prompt must include the goal, scope, relevant paths, constraints, and expected output. Subagents are leaf workers and must not delegate further.

The top-level agent validates subagent results and keeps final decisions.
