#Requires -Version 5.1
<#
From backend/: npm.cmd run test:functional
Optional subset with automatic dependencies:
powershell.exe -NoProfile -File test/functional/run.ps1 -Modules catalog
No SQL credentials, .env loading, temporary files or environment changes.
Secrets travel only through the child process anonymous stdin pipe.
The API login creates a real session. Test records/history are retained.
No retries or automatic cleanup after failure. Review the printed batch first.
Managed strings cannot be guaranteed to be erased immediately by .NET/Node.
#>
[CmdletBinding()]
param([string[]]$Modules = @('all'), [switch]$List, [switch]$CheckTransport, [switch]$Preflight)

& {
    $ErrorActionPreference = 'Stop'
    $VerbosePreference = 'SilentlyContinue'
    $DebugPreference = 'SilentlyContinue'
    $ProgressPreference = 'SilentlyContinue'
    $secure = $null
    $pointer = [IntPtr]::Zero
    $plain = $null
    $json = $null
    $payload = $null
    $inputBytes = $null
    $process = $null
    $email = ''
    $exitCode = 1
    $stage = 'validar-modulos'
    $safeReason = 'MODULE_SELECTION'
    $nodeStarted = $false
    try {
        $allowed = @('all','smoke','auth','users','catalog','inventory','publication','carts','coupons','checkout','payments','orders','returns','reports','edges','sessions','pending')
        foreach ($module in $Modules) {
            if ($module -notin $allowed) { throw 'Modulo no permitido.' }
        }
        if ($Modules.Count -eq 0 -or ($Modules -contains 'all' -and $Modules.Count -ne 1)) {
            throw 'Seleccion de modulos invalida.'
        }
        if ($List -and $CheckTransport) { throw 'Modos offline incompatibles.' }
        if ($Preflight -and ($List -or $CheckTransport -or $Modules.Count -ne 1 -or $Modules[0] -ne 'all')) { throw 'Preflight debe ejecutarse sin otros modos ni modulos.' }
        if ($Preflight) { $Modules = @('preflight') }
        if (-not ($List -or $CheckTransport)) {
        $stage = 'confirmacion'
        $safeReason = 'CONFIRMATION_REQUIRED'
        if ($Preflight) { Write-Host 'Preflight: solo CSRF, login y perfil; el login crea una sesion real.' }
        else { Write-Host 'La suite creara datos ficticios y operaciones simuladas en ShopCart.' }
        Write-Host 'Los modulos incluyen automaticamente sus dependencias. No se borrara el historial.'
        $confirm = Read-Host 'Escriba PRUEBAS para autorizar esta ejecucion'
        if ($confirm -cne 'PRUEBAS') { throw 'Ejecucion no confirmada.' }
        $readOnly = $Modules.Count -eq 1 -and $Modules[0] -eq 'smoke'
        if (-not $readOnly) {
            $stage = 'leer-credenciales'
            $safeReason = 'INPUT_READ'
            $email = (Read-Host 'Correo del Administrador ID 3').Trim().ToLowerInvariant()
            $secure = Read-Host 'Contrasena administrativa' -AsSecureString
            $stage = 'validar-credenciales'
            $safeReason = 'INPUT_CREDENTIALS'
            if ([string]::IsNullOrWhiteSpace($email) -or $secure.Length -lt 1 -or $secure.Length -gt 128) {
                throw 'Credenciales de entrada invalidas.'
            }
        }
        else { $plain = '' }
        }
        if ($CheckTransport) {
            # Exercise the SAME SecureString conversion as interactive login.
            # Synthetic data only; Node returns before constructing any HTTP client.
            $email = 'transport@example.invalid'
            $secure = ConvertTo-SecureString ('prueba-sin-secretos-' + [char]0x00F1 + '"\') -AsPlainText -Force
            $Modules = @('smoke')
        }
        $stage = 'convertir-securestring'
        $safeReason = 'SECURESTRING_CONVERSION'
        if ($null -ne $secure) {
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        }
        $stage = 'resolver-node'
        $safeReason = 'NODE_RESOLUTION'
        $node = (Get-Command node.exe -ErrorAction Stop).Source
        $backendRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $start = New-Object System.Diagnostics.ProcessStartInfo
        $start.FileName = $node
        $start.Arguments = '--import tsx test/functional/run.ts'
        if ($List) { $start.Arguments += ' --list' }
        if ($CheckTransport) { $start.Arguments += ' --check-transport' }
        if ($Preflight) { $start.Arguments += ' --preflight' }
        $start.WorkingDirectory = $backendRoot
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.Encoding]::UTF8
        $start.StandardErrorEncoding = [Text.Encoding]::UTF8
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $start
        $stage = 'iniciar-node'
        $safeReason = 'NODE_START'
        if (-not $process.Start()) { throw 'No se inicio el ejecutor.' }
        $nodeStarted = $true
        Write-Host '[LANZADOR] Node iniciado; preparando entrada en memoria.'
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $List) {
            $stage = 'serializar-entrada'
            $safeReason = 'INPUT_JSON'
            $payload = @{ email=$email; password=$plain; confirm='DATOS_FICTICIOS_EN_SHOPCART'; modules=@($Modules) }
            $json = $payload | ConvertTo-Json -Compress -Depth 3
            $inputBytes = [Text.Encoding]::UTF8.GetBytes($json)
            $stage = 'enviar-stdin'
            $safeReason = 'STDIN_WRITE'
            $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
            $process.StandardInput.BaseStream.Flush()
            [Array]::Clear($inputBytes, 0, $inputBytes.Length)
            $inputBytes = $null
        }
        $stage = 'cerrar-stdin'
        $safeReason = 'STDIN_CLOSE'
        $process.StandardInput.Close()
        $plain = $null; $json = $null; $payload = $null
        if ($pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
            $pointer = [IntPtr]::Zero
        }
        if ($null -ne $secure) { $secure.Dispose(); $secure = $null }
        $stage = 'leer-resultados-node'
        $safeReason = 'STDOUT_READ'
        while (-not $process.StandardOutput.EndOfStream) {
            Write-Host ($process.StandardOutput.ReadLine())
        }
        $process.WaitForExit()
        $stage = 'finalizar-node'
        $safeReason = 'NODE_EXIT'
        $errors = $errorTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
        if ($errors) {
            # Only fixed classifications, never arbitrary stderr or stack traces.
            $stderrCode = 'STDERR_OMITIDO'
            foreach ($known in @('ERR_MODULE_NOT_FOUND','ERR_UNKNOWN_FILE_EXTENSION','SyntaxError')) {
                if ($errors.Contains($known)) { $stderrCode = $known; break }
            }
            Write-Host ("[NODE_STDERR] codigo={0}; contenido omitido." -f $stderrCode)
            if ($exitCode -eq 0) { $exitCode = 1 }
        }
        Write-Host ("[LANZADOR] Node termino con codigo {0}." -f $exitCode)
    }
    catch {
        $type = $_.Exception.GetType().Name
        $line = $_.InvocationInfo.ScriptLineNumber
        $mode = $ExecutionContext.SessionState.LanguageMode
        Write-Host ("[LANZADOR_FALLIDO] etapa={0}; codigo={1}; tipo={2}; linea={3}; NodeIniciado={4}; modo={5}." -f $stage,$safeReason,$type,$line,$nodeStarted,$mode)
        if ($safeReason -eq 'INPUT_CREDENTIALS') {
            Write-Host 'Correo obligatorio; contrasena de login entre 1 y 128 caracteres.'
        }
        Write-Host 'Sin reintentos. Si Node ya inicio pruebas, revisar el ultimo resultado antes de repetir.'
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        if ($null -ne $secure) { $secure.Dispose() }
        $plain = $null; $json = $null; $payload = $null; $email = $null
        if ($null -ne $inputBytes) { [Array]::Clear($inputBytes, 0, $inputBytes.Length) }
        if ($null -ne $process) {
            # Only the child created here. Never leave it writing after launcher failure.
            try { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() } } catch {}
            try { $process.Dispose() } catch { Write-Host '[LIMPIEZA] No se pudo cerrar el objeto del proceso.' }
        }
    }
    exit $exitCode
}
