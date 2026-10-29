param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgsList
)
& "$PSScriptRoot\wf.exe" @ArgsList
