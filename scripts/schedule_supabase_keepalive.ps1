$ErrorActionPreference = "Stop"

$repo = "C:\github-sido\zigs\fmus-zig"
$taskName = "FMUS Supabase Keepalive"
$command = "cd $repo; zig run .\supabase_keepalive_standalone.zig"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -Command `"$command`""
$trigger = New-ScheduledTaskTrigger -Daily -At 9:17AM

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description "Daily Supabase keepalive probe for fmus-zig" -Force
Write-Host "Scheduled task registered: $taskName"
