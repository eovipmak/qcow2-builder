# Diagnosis from Raw Logs

- Debugs by reading verbatim terminal captures from the live machine or build logs (shell prompt or timestamped log tail).
- Expect to spot anomalies directly from raw output and diagnose from evidence rather than being told what to look at.
- For deployed-instance issues, base judgment on the live runtime state (the logs/evidence provided), not on build artifacts or reports.
- Interrogate unexplained slowness or cost in a run ("why too long?"). Find and quantify the root cause, including the possibility that a recent change is to blame rather than the environment.
- When debugging, reproduce first. Show the failing log excerpt (e.g. from `build/<distro>.log`) before proposing a fix.
- Don't loop until it "works" without checking logs — actually inspect the logs.