# Garde Windows éveillé tant que ce script tourne (au plus N secondes) : le
# workflow okd.yml le lance pendant un passage, depuis WSL.
param([int]$Secondes = 7200)
$k = Add-Type -PassThru -Name Veille -Namespace Okd -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
# ES_CONTINUOUS | ES_SYSTEM_REQUIRED : pas de mise en veille pour inactivité.
$r = $k::SetThreadExecutionState([uint32]2147483649)
if ($r -eq 0) { Write-Output "echec"; exit 1 } else { Write-Output "eveil demande" }
Start-Sleep -Seconds $Secondes
