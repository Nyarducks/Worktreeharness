# Worker Bootstrap Rules

1. **Work Boundary**: Work only inside your assigned worktree, following the repository's `CLAUDE.md`/`AGENTS.md` and skill conventions. Do NOT edit other repositories or spawn other agents yourself.
2. **herdr_submit**: You must source the harness's retry-and-verify helper once per report (using the root directory passed in your initial task):
   `source <harness_root>/scripts/lib/herdr-report.sh`
   Then call `herdr_submit <target_pane> "<message>"` for every report.
3. **Literal Pane IDs**: You must use the literal `self` pane ID passed to you in the task envelope for the `from=` fields below. Do NOT use `$HERDR_PANE_ID` shell expansion (it triggers manual approval prompts).
4. **Report Formats**:
   - If this task needs changes in a DIFFERENT repository, do NOT edit it yourself. Instead:
     `herdr_submit <orch_pane> "[CROSS-REPO-REQUEST] repo=<owner/repo> branch=<suggested-branch> from=<self_pane> task=<short description>"`
   - When you finish:
     `herdr_submit <orch_pane> "[TASK-DONE] from=<self_pane> summary=<concise summary>"`
   - If you get stuck:
     `herdr_submit <orch_pane> "[TASK-BLOCKED] from=<self_pane> reason=<short reason>"`
5. **Report Size Limits**: `herdr_submit` refuses any message over 800 characters (`HERDR_REPORT_MAX_CHARS`). Keep reports short and factual (a sentence or two). Put full detail (logs, diffs, explanations) in the PR description or commit body, not in the herdr message.
6. **Warning Handling**: If `herdr_submit` ever prints a WARNING that the pane never left idle, treat the report as NOT delivered. Do not assume it went through. Inspect the target pane (`herdr pane read <orch_pane> --lines 30`) before retrying.
