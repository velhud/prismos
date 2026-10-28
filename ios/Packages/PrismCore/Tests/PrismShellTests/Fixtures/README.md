# Semantic reference scenarios

These twenty fictional cases describe complete expected content, modality, scene, context and action outcomes. They contain no personal calendar, account, project or device evidence.

Offline tests replay the reference responses through the production model adapter, context/read-tool loop, validation, persistence and projections. They verify contracts, not the semantic competence of a live provider.

For separately authorized model evaluation, supply each prompt and its context, retain the complete generated plan and score it by meaning: factual grounding, relevant context, useful scene, complete independent speech, exact tool arguments, clarification, confirmation policy, persistence and expiry. Reasonable alternate wording/layouts can pass. Do not grade by token presence or encode project-name classifiers. Unsupported continuous listening should be explained rather than fabricated.

Run the complete offline capture/review workflow from the repository root:

```bash
swift run --package-path ios/Packages/PrismCore PrismShellEvaluate \
  --references ios/Packages/PrismCore/Tests/PrismShellTests/Fixtures/semantic-evaluations.json \
  --output /tmp/prism-semantic-review-NEW
```

Each case retains the complete reference, actual accepted plan, canonical Library file and every full model request (without Authorization headers). `review.json` distinguishes structural acceptance from unassigned semantic dimensions. Review each dimension by meaning against the complete reference/context; record a score, reviewer and reason. Alternate wording and an equally useful scene can pass. A schema pass is never a semantic pass.

For a **separately authorized paid evaluation**, the same executable accepts `--live MODEL --allow-provider-cost` with `PRISM_EVAL_API_KEY` supplied securely in the environment. It uses the production Responses adapter and read-tool loop with fictional source context, captures complete outputs, and never confirms effects. It refuses live work without both opt-ins. No live evaluation was run during this implementation. Do not place keys or personal evaluation captures in Git.
