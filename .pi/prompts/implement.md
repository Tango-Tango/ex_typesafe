1. "scout"   (outputFile: context.md) → context for $@
2. "planner" (reads: context.md, outputFile: plan.md) → plan using {previous}
3. "worker"  (reads: plan.md, progress: true) → implement the plan from {previous}
