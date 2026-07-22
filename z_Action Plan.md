# Plan: Deferred code-review defects

Three verified defects from the July 2026 code review, deferred by decision for later consideration. Each entry states the defect, the evidence, and the proposed fix.

## 1. README Step 2 URL is a dead link

**Where:** README.md, step "2. Install Additional PowerShell Components".

**Defect:** The documented command fetches
`https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Additional_Components/Install_Additional_Components.ps1`.
That path does not exist in the repository and never has: there is no `PowerShell/` directory and no file named `Install_Additional_Components.ps1`. Verified live: HTTP 404. Every user who completes Step 1 and runs Step 2 as written hits the 404 and never installs modules, Oh-My-Posh, or fonts.

**Proposed fix:** Retarget the command to the actual orchestrator, which runs all three component installs (modules, Oh-My-Posh, fonts):
`irm https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/ArchPowerShell.ps1 | iex`

**Open question:** whether ArchPowerShell.ps1 is the intended long-term Step 2 target, or whether a dedicated Install_Additional_Components.ps1 should be created instead.
