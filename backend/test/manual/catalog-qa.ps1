#Requires -Version 5.1
<#
Run from the repository root: powershell.exe -NoProfile -File .\backend\test\manual\catalog-qa.ps1
Creates 2 products, 3 variants and 2 ENTRADA movements through the local API.
Every HTTP request is sent once. There is no rollback across HTTP requests.
On timeout, inspect the printed batch/SKU/operation IDs before any new execution.
No credentials or HTTP bodies are written to disk. Do not enable HTTP tracing.
The login session expires normally; no refresh, logout or guest-cart merge is run.
PowerShell/.NET cannot guarantee immediate erasure of managed plaintext strings.
#>
[CmdletBinding()]
param()

& {
    $ErrorActionPreference = 'Stop'
    $VerbosePreference = 'SilentlyContinue'
    $DebugPreference = 'SilentlyContinue'
    $ProgressPreference = 'SilentlyContinue'
    $baseUrl = 'http://127.0.0.1:3000/api/v1'
    $batch = [Guid]::NewGuid().ToString('N').ToUpperInvariant()
    $journal = New-Object 'System.Collections.Generic.List[object]'
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $securePassword = $null
    $pointer = [IntPtr]::Zero
    $plainPassword = $null
    $jwt = $null
    $csrfToken = $null
    $login = $null
    $csrf = $null
    $cookie = $null
    $email = $null
    $profile = $null
    $failureMessage = 'Fallo antes de preparar el lote.'
    $succeeded = $false

    function Require-Id {
        param($Value)
        if ($Value -isnot [string] -or $Value -cnotmatch '^[1-9][0-9]{0,18}$') {
            throw 'ID inesperado.'
        }
        return $Value
    }

    function Call-Api {
        param(
            [string]$Step, [string]$Method, [string]$Path,
            [int]$Expected = 200, [hashtable]$Body,
            [string]$Id = '', [string]$Sku = '',
            [string]$OperationId = '', $Quantity = $null
        )
        $row = [pscustomobject]@{
            Paso = $Step; HTTP = '-'; Id = $Id; SKU = $Sku
            OperationId = $OperationId; Cantidad = $Quantity
            Estado = 'Pendiente'; Codigo = ''
        }
        $journal.Add($row)
        $bytes = $null
        $json = $null
        $reader = $null
        $rawError = $null
        $errorData = $null
        $response = $null
        $parsed = $null
        try {
            $headers = @{}
            if ($jwt) { $headers.Authorization = "Bearer $jwt" }
            if ($Method -ne 'GET') { $headers['X-CSRF-Token'] = $csrfToken }
            $options = @{
                Uri = "$baseUrl$Path"; Method = $Method; WebSession = $session
                Headers = $headers; UseBasicParsing = $true
                MaximumRedirection = 0; TimeoutSec = 30; ErrorAction = 'Stop'
            }
            if ($null -ne $Body) {
                $json = $Body | ConvertTo-Json -Depth 6 -Compress
                $bytes = [Text.Encoding]::UTF8.GetBytes($json)
                $options.ContentType = 'application/json; charset=utf-8'
                $options.Body = $bytes
            }
            # The only HTTP send in this function. No retry loop or redirects.
            $row.Estado = 'Enviado; resultado pendiente'
            $response = Invoke-WebRequest @options
            $row.HTTP = [int]$response.StatusCode
            $row.Estado = 'HTTP recibido; contrato pendiente'
            if ($row.HTTP -ne $Expected) { throw 'HTTP inesperado.' }
            $parsed = $response.Content | ConvertFrom-Json -ErrorAction Stop
            if ($parsed.success -ne $true -or $null -eq $parsed.data) {
                throw 'Contrato inesperado.'
            }
            $row.Estado = 'HTTP confirmado'
            return $parsed.data
        }
        catch {
            $caught = $_
            if ($null -ne $caught.Exception.Response) {
                try {
                    $row.HTTP = [int]$caught.Exception.Response.StatusCode
                    if ($caught.ErrorDetails -and $caught.ErrorDetails.Message) {
                        $rawError = $caught.ErrorDetails.Message
                    }
                    else {
                        $stream = $caught.Exception.Response.GetResponseStream()
                        if ($null -ne $stream) {
                            $reader = New-Object System.IO.StreamReader($stream)
                            $rawError = $reader.ReadToEnd()
                        }
                    }
                    if ($rawError) {
                        $errorData = $rawError | ConvertFrom-Json -ErrorAction Stop
                        $code = $errorData.error.code
                        if ($code -is [string] -and $code -cmatch '^[A-Z][A-Z0-9_]{0,79}$') {
                            $row.Codigo = $code
                        }
                    }
                }
                catch { }
            }
            $row.Estado = 'Detenido; revisar resultado'
            # Do not output the exception, headers, request or response body.
            throw 'HTTP fallido o resultado no verificable; consultar la tabla final.'
        }
        finally {
            if ($null -ne $reader) { $reader.Dispose() }
            if ($null -ne $bytes) { [Array]::Clear($bytes, 0, $bytes.Length) }
            $Body = $null; $json = $null; $bytes = $null; $options = $null
            $headers = $null; $response = $null; $parsed = $null
            $rawError = $null; $errorData = $null; $caught = $null
        }
    }

    function Read-Balance {
        param([hashtable]$Variant, [int]$Expected)
        $data = Call-Api -Step 'Verificar saldo' -Method GET `
            -Path "/inventory?variantId=$($Variant.Id)" -Id $Variant.Id -Sku $Variant.Sku
        $items = @($data.inventory)
        if ($items.Count -ne 1 -or $items[0].IdVariante -cne $Variant.Id -or
            $items[0].SKU -cne $Variant.Sku -or
            $null -eq $items[0].CantidadFisica -or $null -eq $items[0].CantidadReservada -or
            $null -eq $items[0].Disponible -or
            [long]$items[0].CantidadFisica -ne $Expected -or
            [long]$items[0].CantidadReservada -ne 0 -or
            [long]$items[0].Disponible -ne $Expected) {
            throw 'Saldo fisico, reservado o disponible inesperado.'
        }
        $journal[$journal.Count - 1].Cantidad = $Expected
        $journal[$journal.Count - 1].Estado = "Verificado: fisico=$Expected reservado=0 disponible=$Expected"
    }

    function New-OperationId {
        $number = [Convert]::ToInt64([Guid]::NewGuid().ToString('N').Substring(0, 15), 16)
        if ($number -le 0) { throw 'operationId invalido.' }
        return $number.ToString([Globalization.CultureInfo]::InvariantCulture)
    }

    try {
        $failureMessage = 'No se pudieron preparar los datos de entrada.'
        $products = @(
            @{ Name = 'Camiseta QA'; Category = 'Ropa'; CategoryId = $null; Id = ''; Variants = @(
                @{ Sku = "QA-$batch-CAM-M-AZ"; Price = '112.0000'; Size = 'M'; Color = 'azul'; Stock = 10; Id = ''; OperationId = (New-OperationId) }
                @{ Sku = "QA-$batch-CAM-L-AZ"; Price = '123.2000'; Size = 'L'; Color = 'azul'; Stock = 0; Id = ''; OperationId = $null }
            ) }
            @{ Name = 'Organizador QA'; Category = 'Hogar'; CategoryId = $null; Id = ''; Variants = @(
                @{ Sku = "QA-$batch-ORG"; Price = '56.0000'; Size = $null; Color = $null; Stock = 5; Id = ''; OperationId = (New-OperationId) }
            ) }
        )
        Write-Host "Lote: $batch"
        $email = (Read-Host 'Correo del Administrador (ID 3)').Trim().ToLowerInvariant()
        $securePassword = Read-Host 'Contrasena administrativa' -AsSecureString
        if ([string]::IsNullOrWhiteSpace($email) -or $email.Length -gt 254 -or
            $securePassword.Length -lt 1 -or $securePassword.Length -gt 128) {
            throw 'Entrada invalida.'
        }

        $failureMessage = 'No se pudo obtener CSRF valido.'
        $csrf = Call-Api -Step 'CSRF' -Method GET -Path '/auth/csrf'
        $csrfToken = $csrf.csrfToken
        $cookie = $session.Cookies.GetCookies([Uri]"$baseUrl/auth/login")['sc_csrf']
        if ($csrfToken -isnot [string] -or $csrfToken -cnotmatch '^[A-Za-z0-9_-]{43}$' -or
            $null -eq $cookie -or $cookie.Value -cne $csrfToken) { throw 'CSRF invalido.' }

        $failureMessage = 'No se confirmo el login administrativo.'
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        $login = Call-Api -Step 'Login' -Method POST -Path '/auth/login' `
            -Body @{ email = $email; password = $plainPassword }
        $jwt = $login.accessToken
        if ($jwt -isnot [string] -or $jwt -cnotmatch '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' -or
            $login.profile.IdUsuario -cne '3' -or $login.profile.Rol -cne 'Administrador' -or
            $login.profile.CorreoElectronico -cne $email -or $null -ne $login.cartMerge) {
            throw 'Identidad administrativa inesperada.'
        }
        # Minimize the lifetime of password references once login has completed.
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        $pointer = [IntPtr]::Zero
        $securePassword.Dispose(); $securePassword = $null; $plainPassword = $null
        $profile = Call-Api -Step 'Perfil' -Method GET -Path '/users/me'
        if ($profile.profile.IdUsuario -cne '3' -or $profile.profile.Rol -cne 'Administrador') {
            throw 'Perfil inesperado.'
        }

        $failureMessage = 'Categorias o comprobacion previa del lote no validas.'
        $categories = Call-Api -Step 'Categorias' -Method GET -Path '/catalog/categories'
        foreach ($product in $products) {
            $found = @($categories.categories | Where-Object { $_.Nombre -ceq $product.Category })
            if ($found.Count -ne 1 -or $found[0].IdCategoria -isnot [int] -or $found[0].IdCategoria -le 0) {
                throw 'Categoria no identificada de forma unica.'
            }
            $product.CategoryId = $found[0].IdCategoria
        }
        # Public search covers active products by batch description. Full inventory
        # pagination also checks SKU for variants of inactive products.
        $public = Call-Api -Step 'Preflight catalogo' -Method GET -Path "/catalog/products?search=$batch&pageSize=1"
        if (@($public.products).Count -ne 0) { throw 'El lote ya es visible.' }
        $complete = $false
        for ($page = 1; $page -le 10000; $page++) {
            $inventory = Call-Api -Step 'Preflight SKU' -Method GET -Path "/inventory?page=$page&pageSize=100"
            $inventoryRows = @($inventory.inventory)
            if (@($inventoryRows | Where-Object { $_.SKU -like "QA-$batch-*" }).Count -gt 0) {
                throw 'Ya existen variantes del lote.'
            }
            if ($inventoryRows.Count -lt 100) { $complete = $true; break }
        }
        if (-not $complete) { throw 'No se completo la comprobacion previa.' }

        $failureMessage = 'Fallo al crear productos o variantes; revisar los IDs confirmados.'
        foreach ($product in $products) {
            $created = Call-Api -Step 'Crear producto' -Method POST -Path '/catalog/products' -Expected 201 `
                -Body @{ categoryId = $product.CategoryId; name = $product.Name; description = "Lote QA $batch"; active = $false }
            $product.Id = Require-Id $created.product.IdProducto
            $journal[$journal.Count - 1].Id = $product.Id
            $journal[$journal.Count - 1].Estado = 'Creado inactivo'
            foreach ($variant in $product.Variants) {
                $createdVariant = Call-Api -Step 'Crear variante' -Method POST -Path '/catalog/variants' -Expected 201 `
                    -Sku $variant.Sku -Body @{ productId = $product.Id; sku = $variant.Sku; price = $variant.Price; size = $variant.Size; color = $variant.Color; active = $true }
                $variant.Id = Require-Id $createdVariant.variant.IdVariante
                $journal[$journal.Count - 1].Id = $variant.Id
                $journal[$journal.Count - 1].Estado = 'Variante creada'
            }
        }

        $failureMessage = 'Fallo de inventario; no repetir movimientos sin revisar el lote.'
        foreach ($product in $products) {
            foreach ($variant in $product.Variants) {
                Read-Balance -Variant $variant -Expected 0
                if ($variant.Stock -gt 0) {
                    $movement = Call-Api -Step 'ENTRADA' -Method POST -Path '/inventory/movements' -Expected 201 `
                        -Sku $variant.Sku -OperationId $variant.OperationId -Quantity $variant.Stock `
                        -Body @{ variantId = $variant.Id; type = 'ENTRADA'; quantity = $variant.Stock; reason = "Carga QA $batch"; operationId = $variant.OperationId }
                    $movementId = Require-Id $movement.movement.IdMovimiento
                    $journal[$journal.Count - 1].Id = $movementId
                    $journal[$journal.Count - 1].Estado = 'Movimiento confirmado'
                }
                Read-Balance -Variant $variant -Expected $variant.Stock
            }
        }

        $failureMessage = 'Fallo de activacion; algunos productos pueden haber quedado activos.'
        foreach ($product in $products) {
            $activated = Call-Api -Step 'Activar producto' -Method PATCH -Path "/catalog/products/$($product.Id)" -Id $product.Id `
                -Body @{ categoryId = $product.CategoryId; name = $product.Name; description = "Lote QA $batch"; active = $true }
            if ((Require-Id $activated.product.IdProducto) -cne $product.Id) { throw 'ID de activacion inesperado.' }
            $journal[$journal.Count - 1].Estado = 'Activo'
        }

        $failureMessage = 'Fallo de verificacion final; no se revierte ni se vuelve a crear el lote.'
        $listing = Call-Api -Step 'Catalogo publico' -Method GET -Path "/catalog/products?search=$batch&pageSize=100"
        if (@($listing.products).Count -ne 2) { throw 'No aparecen exactamente dos productos.' }
        foreach ($product in $products) {
            if (@($listing.products | Where-Object { $_.IdProducto -ceq $product.Id }).Count -ne 1) {
                throw 'Producto ausente del listado.'
            }
            $detail = Call-Api -Step 'Detalle publico' -Method GET -Path "/catalog/products/$($product.Id)" -Id $product.Id
            if ($detail.product.IdProducto -cne $product.Id -or $detail.product.Nombre -cne $product.Name -or
                $detail.product.IdCategoria -ne $product.CategoryId -or @($detail.variants).Count -ne $product.Variants.Count) {
                throw 'Detalle de producto inesperado.'
            }
            foreach ($variant in $product.Variants) {
                $found = @($detail.variants | Where-Object { $_.IdVariante -ceq $variant.Id })
                if ($found.Count -ne 1 -or $found[0].SKU -cne $variant.Sku -or
                    $found[0].Precio -cne $variant.Price -or $found[0].Talla -cne $variant.Size -or
                    $found[0].Color -cne $variant.Color -or $null -eq $found[0].Disponible -or
                    [long]$found[0].Disponible -ne $variant.Stock) { throw 'Variante publica inesperada.' }
                Read-Balance -Variant $variant -Expected $variant.Stock
            }
        }
        $succeeded = $true
        Write-Host 'Lote completo: productos activos, variantes y saldos verificados.'
    }
    catch {
        Write-Host "DETENIDO: $failureMessage"
        Write-Host 'Sin reintentos ni borrados. Una escritura sin respuesta puede estar aplicada.'
        Write-Host 'Conservar lote, SKU y operationId; revisar antes de ejecutar otro lote.'
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        if ($null -ne $securePassword) { $securePassword.Dispose() }
        $plainPassword = $null; $jwt = $null; $csrfToken = $null; $login = $null
        $csrf = $null; $cookie = $null; $profile = $null; $session = $null; $email = $null
        Write-Host "Lote: $batch"
        $journal | Format-Table Paso, HTTP, Id, SKU, OperationId, Cantidad, Estado, Codigo -AutoSize -Wrap
    }
    if (-not $succeeded) { exit 1 }
}
