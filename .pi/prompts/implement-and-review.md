1. "worker"   (progress: true) → implement $@
2. "reviewer" (reads: progress.md) → review {previous}
3. "worker"   (reads: progress.md, progress: true) → apply feedback from {previous}
