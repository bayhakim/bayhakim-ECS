$ErrorActionPreference = "Stop"

$script:SqlHost = $env:KANKA_SQL_HOST
if ([string]::IsNullOrWhiteSpace($script:SqlHost)) { $script:SqlHost = "91.151.88.33" }

$script:SqlPort = $env:KANKA_SQL_PORT
if ([string]::IsNullOrWhiteSpace($script:SqlPort)) { $script:SqlPort = "1433" }

$script:SqlUser = $env:KANKA_SQL_USER
if ([string]::IsNullOrWhiteSpace($script:SqlUser)) { $script:SqlUser = "yahyaro" }

$script:SqlPassword = $env:KANKA_SQL_PASSWORD
if ([string]::IsNullOrWhiteSpace($script:SqlPassword)) {
    $secure = Read-Host "SQL password" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $script:SqlPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

$script:DefaultDbs = @("avrupayakasi", "avytempdata", "pazaryerleri")
$script:Port = if ($env:KANKA_PANEL_PORT) { [int]$env:KANKA_PANEL_PORT } else { 8787 }
$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:NebimSqlServer = if ($env:NEBIM_SQL_SERVER) { $env:NEBIM_SQL_SERVER } else { "192.168.2.25" }
$script:NebimSqlDatabase = if ($env:NEBIM_SQL_DATABASE) { $env:NEBIM_SQL_DATABASE } else { "Avrupa_yakasi_online_v3" }
$script:NebimSqlUser = if ($env:NEBIM_SQL_USER) { $env:NEBIM_SQL_USER } else { "sa" }
$script:NebimSqlPassword = $env:NEBIM_SQL_PASSWORD

function New-ConnectionString([string]$Database) {
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder["Data Source"] = "$($script:SqlHost),$($script:SqlPort)"
    $builder["Initial Catalog"] = $Database
    $builder["User ID"] = $script:SqlUser
    $builder["Password"] = $script:SqlPassword
    $builder["Encrypt"] = $false
    $builder["TrustServerCertificate"] = $true
    $builder["Connect Timeout"] = 10
    return $builder.ConnectionString
}

function New-NebimConnectionString() {
    if ([string]::IsNullOrWhiteSpace($script:NebimSqlPassword)) {
        throw "NEBIM_SQL_PASSWORD eksik. Nebim notlar alanina yazmak icin panel NEBIM_SQL_PASSWORD ile baslatilmali."
    }
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder["Data Source"] = $script:NebimSqlServer
    $builder["Initial Catalog"] = $script:NebimSqlDatabase
    $builder["User ID"] = $script:NebimSqlUser
    $builder["Password"] = $script:NebimSqlPassword
    $builder["Encrypt"] = $false
    $builder["TrustServerCertificate"] = $true
    $builder["Connect Timeout"] = 20
    return $builder.ConnectionString
}

function Invoke-Query([string]$Database, [string]$Sql, [hashtable]$Params = @{}) {
    $conn = New-Object System.Data.SqlClient.SqlConnection (New-ConnectionString $Database)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Sql
        $cmd.CommandTimeout = 120
        foreach ($key in $Params.Keys) {
            $null = $cmd.Parameters.AddWithValue($key, $Params[$key])
        }
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        $table = New-Object System.Data.DataTable
        $null = $adapter.Fill($table)
        $rows = @()
        foreach ($row in $table.Rows) {
            $obj = [ordered]@{}
            foreach ($col in $table.Columns) {
                $value = $row[$col.ColumnName]
                if ($value -is [DBNull]) { $value = $null }
                $obj[$col.ColumnName] = $value
            }
            $rows += [pscustomobject]$obj
        }
        return $rows
    } finally {
        if ($conn.State -eq "Open") { $conn.Close() }
    }
}

function ConvertTo-RtfText([string]$Text) {
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("{\rtf1\ansi\ansicpg1254\deff0{\fonttbl{\f0\fnil Tahoma;}}\viewkind4\uc1\pard\lang1055\f0\fs17 ")
    foreach ($char in $Text.ToCharArray()) {
        $code = [int][char]$char
        if ($char -eq "`r") { continue }
        elseif ($char -eq "`n") { [void]$builder.Append("\par ") }
        elseif ($char -eq "\") { [void]$builder.Append("\\") }
        elseif ($char -eq "{") { [void]$builder.Append("\{") }
        elseif ($char -eq "}") { [void]$builder.Append("\}") }
        elseif ($code -ge 32 -and $code -le 126) { [void]$builder.Append($char) }
        else { [void]$builder.Append("\u" + $code + "?") }
    }
    [void]$builder.Append("}")
    return $builder.ToString()
}

function Save-NebimItemNote([string]$ItemCode, [string]$PlainText, [string]$LangCode = "TR", [string]$UserName = "GY   YahyaA") {
    if ([string]::IsNullOrWhiteSpace($ItemCode)) { throw "Nebim urun kodu bos olamaz." }
    if ([string]::IsNullOrWhiteSpace($PlainText)) { throw "Nebim not metni bos olamaz." }

    $cleanItemCode = $ItemCode.Trim()
    $cleanLangCode = $LangCode.Trim()
    $cleanUserName = $UserName.Trim()
    $notesText = $PlainText.Trim()

    $conn = New-Object System.Data.SqlClient.SqlConnection (New-NebimConnectionString)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandTimeout = 120
        $cmd.CommandText = @"
IF NOT EXISTS (SELECT 1 FROM dbo.cdItem WHERE ItemTypeCode = @ItemTypeCode AND ItemCode = @ItemCode AND IsBlocked = 0)
BEGIN
  RAISERROR('Urun Nebim cdItem tablosunda bulunamadi veya blokeli.', 16, 1);
  RETURN;
END

IF EXISTS (SELECT 1 FROM dbo.prItemNotes WHERE ItemTypeCode = @ItemTypeCode AND ItemCode = @ItemCode AND LangCode = @LangCode)
BEGIN
  UPDATE dbo.prItemNotes
     SET Notes = @Notes,
         PlainText = @PlainText,
         LastUpdatedUserName = @UserName,
         LastUpdatedDate = GETDATE()
   WHERE ItemTypeCode = @ItemTypeCode
     AND ItemCode = @ItemCode
     AND LangCode = @LangCode;

  SELECT 'UPDATED' AS Result;
END
ELSE
BEGIN
  INSERT INTO dbo.prItemNotes
    (ItemTypeCode, ItemCode, LangCode, Notes, PlainText, CreatedUserName, CreatedDate, LastUpdatedUserName, LastUpdatedDate, RowGuid)
  VALUES
    (@ItemTypeCode, @ItemCode, @LangCode, @Notes, @PlainText, @UserName, GETDATE(), @UserName, GETDATE(), NEWID());

  SELECT 'INSERTED' AS Result;
END
"@
        [void]$cmd.Parameters.Add("@ItemTypeCode", [System.Data.SqlDbType]::TinyInt)
        $cmd.Parameters["@ItemTypeCode"].Value = 1
        [void]$cmd.Parameters.Add("@ItemCode", [System.Data.SqlDbType]::Char, 30)
        $cmd.Parameters["@ItemCode"].Value = $cleanItemCode
        [void]$cmd.Parameters.Add("@LangCode", [System.Data.SqlDbType]::Char, 5)
        $cmd.Parameters["@LangCode"].Value = $cleanLangCode
        [void]$cmd.Parameters.Add("@Notes", [System.Data.SqlDbType]::NText)
        $cmd.Parameters["@Notes"].Value = $notesText
        [void]$cmd.Parameters.Add("@PlainText", [System.Data.SqlDbType]::NText)
        $cmd.Parameters["@PlainText"].Value = $PlainText
        [void]$cmd.Parameters.Add("@UserName", [System.Data.SqlDbType]::Char, 20)
        $cmd.Parameters["@UserName"].Value = $cleanUserName

        $result = $cmd.ExecuteScalar()
        return [pscustomobject]@{
            ok = $true
            result = $result
            itemCode = $cleanItemCode
            langCode = $cleanLangCode
            database = $script:NebimSqlDatabase
            server = $script:NebimSqlServer
            message = "Nebim notlar alanina yazildi: $result"
        }
    } finally {
        if ($conn.State -eq "Open") { $conn.Close() }
    }
}

function Invoke-NebimDataSet([string]$Sql, [hashtable]$Params = @{}) {
    $conn = New-Object System.Data.SqlClient.SqlConnection (New-NebimConnectionString)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Sql
        $cmd.CommandTimeout = 180
        foreach ($key in $Params.Keys) {
            $null = $cmd.Parameters.AddWithValue($key, $Params[$key])
        }
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        $dataSet = New-Object System.Data.DataSet
        $null = $adapter.Fill($dataSet)
        return $dataSet
    } finally {
        if ($conn.State -eq "Open") { $conn.Close() }
    }
}

function Get-DataRowValue($Row, [string]$ColumnName) {
    if (-not $Row) { return "" }
    if (-not $Row.Table.Columns.Contains($ColumnName)) { return "" }
    $value = $Row[$ColumnName]
    if ($value -is [DBNull]) { return "" }
    return [string]$value
}

function Get-AttributeValue([string]$AttributeText) {
    if ([string]::IsNullOrWhiteSpace($AttributeText)) { return "" }
    $parts = $AttributeText -split "\|", 2
    if ($parts.Count -eq 2) { return $parts[1].Trim() }
    return $AttributeText.Trim()
}

function Get-NebimProductUpdateData([string]$ProductCode) {
    if ([string]::IsNullOrWhiteSpace($ProductCode)) { throw "Urun kodu bos olamaz." }
    $cleanCode = $ProductCode.Trim()
    $dataSet = Invoke-NebimDataSet "EXEC dbo.ylc_GetProductInfoByItemCode @itemCode" @{ "@itemCode" = $cleanCode }
    if ($dataSet.Tables.Count -lt 1 -or $dataSet.Tables[0].Rows.Count -lt 1) {
        throw "Nebim ylc_GetProductInfoByItemCode urun bilgisi dondurmedi: $cleanCode"
    }

    $main = $dataSet.Tables[0].Rows[0]
    $plainTextDataSet = Invoke-NebimDataSet @"
SELECT TOP 1 CONVERT(nvarchar(max), PlainText) AS PlainText
FROM dbo.prItemNotes WITH (NOLOCK)
WHERE ItemTypeCode = 1 AND ItemCode = @itemCode AND LangCode = 'TR'
ORDER BY LastUpdatedDate DESC
"@ @{ "@itemCode" = $cleanCode }

    $plainText = ""
    if ($plainTextDataSet.Tables.Count -gt 0 -and $plainTextDataSet.Tables[0].Rows.Count -gt 0) {
        $plainText = Get-DataRowValue $plainTextDataSet.Tables[0].Rows[0] "PlainText"
    }
    if ([string]::IsNullOrWhiteSpace($plainText)) {
        $plainText = Get-DataRowValue $main "InternetProductDescription"
    }
    if ([string]::IsNullOrWhiteSpace($plainText)) {
        $plainText = Get-DataRowValue $main "ProductDescription"
    }

    $title = Get-DataRowValue $main "InternetProductDescription"
    if ([string]::IsNullOrWhiteSpace($title)) { $title = Get-DataRowValue $main "ProductDescription" }

    return [pscustomobject]@{
        productCode = $cleanCode
        title = $title
        description = $plainText
        shortDescription = if ($plainText.Length -gt 500) { $plainText.Substring(0, 500) } else { $plainText }
        vatRate = Get-DataRowValue $main "VatRate"
        brand = Get-AttributeValue (Get-DataRowValue $main "ProductAtt01")
        variantRows = $dataSet.Tables[0].Rows.Count
        tableCount = $dataSet.Tables.Count
    }
}

function Invoke-EcsProductUpdateService([string]$ProductCode) {
    if ([string]::IsNullOrWhiteSpace($ProductCode)) { throw "Urun kodu bos olamaz." }
    $cleanCode = $ProductCode.Trim()
    $encodedCode = [System.Uri]::EscapeDataString($cleanCode)
    $url = "https://admin.avrupayakasi.com/services/ProductUpdateFromNebim?productCode=$encodedCode"

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $request = [System.Net.WebRequest]::Create($url)
    $request.Method = "POST"
    $request.Timeout = 120000
    $request.ContentType = "application/x-www-form-urlencoded; charset=utf-8"
    $request.ContentLength = 0

    try {
        $response = $request.GetResponse()
        try {
            $reader = New-Object IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $content = $reader.ReadToEnd()
            return [pscustomobject]@{
                ok = $true
                productCode = $cleanCode
                statusCode = [int]$response.StatusCode
                response = $content
                url = $url
                message = "ECS Nebimden guncellendi: $cleanCode"
            }
        } finally {
            $response.Close()
        }
    } catch [System.Net.WebException] {
        $statusCode = $null
        $content = ""
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $content = $reader.ReadToEnd()
            $_.Exception.Response.Close()
        }
        if ([string]::IsNullOrWhiteSpace($content)) { $content = $_.Exception.Message }
        throw "ECS servis guncelleme hatasi ($statusCode): $content"
    }
}

function Get-EcsProductDescriptionState([string]$ProductCode) {
    if ([string]::IsNullOrWhiteSpace($ProductCode)) { throw "Urun kodu bos olamaz." }
    $rows = @(Invoke-Query "avrupayakasi" @"
SELECT TOP 1
    ProductCode,
    LEN(CONVERT(varchar(max), ISNULL(Description, ''))) AS DescriptionLength,
    LEFT(CONVERT(varchar(max), ISNULL(Description, '')), 250) AS DescriptionStart
FROM dbo.AP_01Products WITH (NOLOCK)
WHERE ProductCode = @productCode
"@ @{ "@productCode" = $ProductCode.Trim() })

    if ($rows.Count -lt 1) {
        return [pscustomobject]@{
            productCode = $ProductCode.Trim()
            exists = $false
            descriptionLength = 0
            descriptionStart = ""
        }
    }

    return [pscustomobject]@{
        productCode = [string]$rows[0].ProductCode
        exists = $true
        descriptionLength = [int]$rows[0].DescriptionLength
        descriptionStart = [string]$rows[0].DescriptionStart
    }
}

function Update-EcsProductFromNebim($Payload) {
    $productCode = [string]$Payload.productCode
    $check = [string]$Payload.check
    if ([string]::IsNullOrWhiteSpace($productCode)) { throw "Urun kodu bos olamaz." }
    $service = Invoke-EcsProductUpdateService $productCode

    if ([string]::IsNullOrWhiteSpace($check) -or $check -eq "description") {
        $descriptionState = Get-EcsProductDescriptionState $productCode
        if (-not $descriptionState.exists) {
            throw "ECS servis OK dondu fakat urun ECS AP_01Products tablosunda bulunamadi: $productCode"
        }
        if ($descriptionState.descriptionLength -le 0) {
            $nebimData = $null
            try { $nebimData = Get-NebimProductUpdateData $productCode } catch { }
            $nebimDescLen = if ($nebimData -and $nebimData.description) { $nebimData.description.Length } else { 0 }
            throw "ECS servis OK dondu fakat AP_01Products.Description hala bos. Nebim notu/okunan aciklama uzunlugu: $nebimDescLen. ylc_GetProductInfoByItemCode notlar alanini ECS'ye tasimiyor olabilir."
        }
        $service | Add-Member -NotePropertyName ecsDescription -NotePropertyValue $descriptionState -Force
    }

    return $service
}

function Test-Database([string]$Database) {
    try {
        $rows = Invoke-Query $Database "SELECT DB_NAME() AS database_name, USER_NAME() AS database_user, HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'SELECT') AS database_select, HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'VIEW DEFINITION') AS view_definition"
        return [pscustomobject]@{ database = $Database; ok = $true; info = $rows[0]; error = $null }
    } catch {
        return [pscustomobject]@{ database = $Database; ok = $false; info = $null; error = $_.Exception.Message }
    }
}

function Quote-Name([string]$Name) {
    return "[" + ($Name -replace "]", "]]") + "]"
}

function Send-Text($Response, [int]$Status, [string]$ContentType, [string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $Response.StatusCode = $Status
    $Response.ContentType = "$ContentType; charset=utf-8"
    $Response.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    $Response.Headers["Pragma"] = "no-cache"
    $Response.Headers["Expires"] = "0"
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Send-Json($Response, [object]$Payload, [int]$Status = 200) {
    Send-Text $Response $Status "application/json" ($Payload | ConvertTo-Json -Depth 8)
}

function Read-BodyJson($Request) {
    $encoding = [System.Text.Encoding]::UTF8
    $reader = New-Object IO.StreamReader($Request.InputStream, $encoding)
    $text = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($text)) { return @{} }
    return $text | ConvertFrom-Json
}

function Get-QueryParamUtf8($Request, [string]$Name) {
    $query = $Request.Url.Query
    if (-not [string]::IsNullOrWhiteSpace($query)) {
        foreach ($part in $query.TrimStart("?").Split("&")) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            $pair = $part.Split("=", 2)
            $key = [Uri]::UnescapeDataString($pair[0].Replace("+", " "))
            if ($key -eq $Name) {
                if ($pair.Count -lt 2) { return "" }
                return [Uri]::UnescapeDataString($pair[1].Replace("+", " "))
            }
        }
    }
    return $Request.QueryString[$Name]
}

function Get-Schema([string]$Database) {
    $sql = @"
SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.name AS column_name,
    ty.name AS data_type,
    c.column_id,
    SUM(p.rows) OVER (PARTITION BY t.object_id) AS row_count
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
ORDER BY t.name, c.column_id
"@
    Invoke-Query $Database $sql
}

function Get-Preview([string]$Database, [string]$Schema, [string]$Table, [int]$Take = 50) {
    if ($Take -lt 1 -or $Take -gt 500) { $Take = 50 }
    $sql = "SELECT TOP ($Take) * FROM $(Quote-Name $Schema).$(Quote-Name $Table)"
    Invoke-Query $Database $sql
}

function Get-Products($Payload) {
    $db = [string]$Payload.database
    $schema = [string]$Payload.schema
    $table = [string]$Payload.table
    $map = $Payload.mapping
    $take = [int]$Payload.take
    if ($take -lt 1 -or $take -gt 5000) { $take = 1000 }

    $rows = Get-Preview $db $schema $table $take
    $variants = @()
    foreach ($row in $rows) {
        $dict = @{}
        $row.PSObject.Properties | ForEach-Object { $dict[$_.Name] = $_.Value }
        $productCode = $dict[[string]$map.productCode]
        $model = $dict[[string]$map.model]
        if ([string]::IsNullOrWhiteSpace([string]$model)) {
            $codeText = [string]$productCode
            $model = if ($codeText -match "^(.*?)-[^-]+$") { $Matches[1] } else { $codeText }
        }
        $variants += [pscustomobject]@{
            model = $model
            productCode = $productCode
            title = $dict[[string]$map.title]
            brand = $dict[[string]$map.brand]
            description = $dict[[string]$map.description]
            color = $dict[[string]$map.color]
            size = $dict[[string]$map.size]
            barcode = $dict[[string]$map.barcode]
            purchasePrice = $dict[[string]$map.purchasePrice]
            costPrice = $dict[[string]$map.costPrice]
            salePrice = $dict[[string]$map.salePrice]
            listPrice = $dict[[string]$map.listPrice]
            stock = $dict[[string]$map.stock]
            image = $dict[[string]$map.image]
            raw = $dict
        }
    }

    $models = $variants | Group-Object model | ForEach-Object {
        $items = $_.Group
        $stockTotal = 0
        foreach ($item in $items) {
            $n = 0
            if ([decimal]::TryParse([string]$item.stock, [ref]$n)) { $stockTotal += $n }
        }
        [pscustomobject]@{
            model = $_.Name
            title = ($items | Where-Object title | Select-Object -First 1).title
            brand = ($items | Where-Object brand | Select-Object -First 1).brand
            image = ($items | Where-Object image | Select-Object -First 1).image
            variantCount = $items.Count
            stockTotal = $stockTotal
            colors = @($items | ForEach-Object color | Where-Object { $_ } | Sort-Object -Unique)
            sizes = @($items | ForEach-Object size | Where-Object { $_ } | Sort-Object -Unique)
            variants = $items
        }
    } | Sort-Object model

    return [pscustomobject]@{ models = $models; variants = $variants }
}

function Get-EcdProducts([string]$Search, [int]$Take = 1000) {
    if ($Take -lt 1 -or $Take -gt 5000) { $Take = 1000 }
    $where = "WHERE p.Id IS NOT NULL"
    $order = "ORDER BY v.Id DESC"
    $params = @{}
    if (-not [string]::IsNullOrWhiteSpace($Search)) {
        $where = @"
WHERE
    p.ProductCode LIKE @searchPrefix OR
    p.ProductTitle LIKE @search OR
    p.Brand LIKE @search OR
    v.StockCode LIKE @searchPrefix OR
    v.Barcode = @searchExact OR
    v.Barcode LIKE @searchPrefix OR
    v.ColorCode LIKE @search OR
    v.SizeCode LIKE @search
"@
        $params["@search"] = "%$Search%"
        $params["@searchPrefix"] = "$Search%"
        $params["@searchExact"] = "$Search"
        $order = "ORDER BY p.ProductCode, color, v.SizeCode"
    }

    $sql = @"
SELECT TOP ($Take)
    p.ProductCode AS productCode,
    p.ProductCode AS model,
    p.ProductTitle AS title,
    p.Brand AS brand,
    p.Description AS description,
    COALESCE(NULLIF(s.NebimColor, ''), v.ColorCode) AS color,
    v.SizeCode AS size,
    v.Barcode AS barcode,
    p.BuyingPrice AS purchasePrice,
    p.CostPrice AS costPrice,
    COALESCE(NULLIF(v.SellingPrice, 0), p.SellingPrice) AS salePrice,
    p.ListPrice AS listPrice,
    v.StockAmount AS stock,
    COALESCE(NULLIF(v.ImageUrl, ''), img.ImagePath) AS image,
    v.StockCode AS stockCode,
    p.CreationDate AS creationDate
FROM dbo.AP_04ProductVariants v
LEFT JOIN dbo.AP_02ProductSubs s ON s.Id = v.ProductSubId
LEFT JOIN dbo.AP_01Products p ON p.Id = s.ProductId
OUTER APPLY (
    SELECT TOP 1 ImagePath
    FROM dbo.AP_03ProductImageFiles i
    WHERE i.ProductSubId = s.Id AND ISNULL(i.IsActive, 1) = 1
    ORDER BY ISNULL(i.DisplayOrder, 9999), i.Id
) img
$where
$order
"@

    $variants = Invoke-Query "avrupayakasi" $sql $params
    $models = $variants | Group-Object model | ForEach-Object {
        $items = $_.Group
        $stockTotal = 0
        foreach ($item in $items) {
            $n = 0
            if ([decimal]::TryParse([string]$item.stock, [ref]$n)) { $stockTotal += $n }
        }
        [pscustomobject]@{
            model = $_.Name
            title = ($items | Where-Object title | Select-Object -First 1).title
            brand = ($items | Where-Object brand | Select-Object -First 1).brand
            image = ($items | Where-Object image | Select-Object -First 1).image
            variantCount = $items.Count
            stockTotal = $stockTotal
            colors = @($items | ForEach-Object color | Where-Object { $_ } | Sort-Object -Unique)
            sizes = @($items | ForEach-Object size | Where-Object { $_ } | Sort-Object -Unique)
            variants = $items
        }
    } | Sort-Object model

    return [pscustomobject]@{ models = @($models); variants = @($variants) }
}

function Get-PlatformProducts([string]$Model, [int]$Take = 500) {
    if ([string]::IsNullOrWhiteSpace($Model)) {
        return [pscustomobject]@{ rows = @() }
    }
    if ($Take -lt 1 -or $Take -gt 2000) { $Take = 500 }
    $sql = @"
SELECT TOP ($Take)
    pv.platformId,
    COALESCE(dp.Title, CONVERT(varchar(20), pv.platformId)) AS platformTitle,
    pv.platformModelKodu,
    pv.platformStokKodu,
    pv.platformBarkod,
    pv.platformRenk,
    pv.platformBeden,
    pv.satisFiyati,
    pv.listeFiyati,
    pv.yuklemeTarihi,
    pv.durumu,
    pv.satisaKapali
FROM dbo.PZ_UrunVaryantlari pv
LEFT JOIN dbo.DF_Platforms dp ON dp.Id = pv.platformId
WHERE
    pv.platformModelKodu LIKE @modelPrefix OR
    pv.platformStokKodu LIKE @modelPrefix OR
    pv.platformBarkod = @modelExact
ORDER BY platformTitle, pv.platformRenk, pv.platformBeden
"@
    $rows = Invoke-Query "avrupayakasi" $sql @{
        "@modelPrefix" = "$Model%"
        "@modelExact" = "$Model"
    }
    return [pscustomobject]@{ rows = @($rows) }
}

function Get-MissingAttributeProducts([string]$Search, [string]$StockMode = "in", [int]$Take = 500, [string]$Feature = "", [string]$Mode = "detail", [string]$Status = "missing", [string]$Brand = "") {
    if ($Take -lt 1 -or $Take -gt 5000) { $Take = 500 }
    $params = @{}
    $missingJoin = "LEFT JOIN dbo.PZ_FiltresizUrunler f ON f.model = s.ProductSubCode"
    $missingSelect = "COALESCE(f.model, s.ProductSubCode) AS missingModel, f.filterGroupId AS missingFeatureId, CASE WHEN ISNULL(aa.attrCount, 0) > 0 THEN 'Ozellik Var' ELSE COALESCE(f.filterGroupName, 'Urun Ozelligi Yok') END AS missingFeature,"
    $missingOrder = if ($Mode -eq "model") { "MAX(ISNULL(f.id, 0)) DESC," } else { "ISNULL(f.id, 0) DESC," }
    $filters = @("1 = 1")
    $keywordExists = "EXISTS (SELECT 1 FROM dbo.AP_01ProductKeywords kx WHERE kx.ProductId = p.Id AND NULLIF(LTRIM(RTRIM(kx.KeywordKey)), '') IS NOT NULL)"

    if ($Status -eq "present") {
        $missingSelect = "s.ProductSubCode AS missingModel, NULL AS missingFeatureId, 'Ozellik Var' AS missingFeature,"
        $missingOrder = ""
        $filters += $keywordExists
    } elseif ($Status -eq "all") {
        $missingSelect = "COALESCE(f.model, s.ProductSubCode) AS missingModel, f.filterGroupId AS missingFeatureId, CASE WHEN ISNULL(aa.attrCount, 0) > 0 THEN 'Ozellik Var' ELSE COALESCE(f.filterGroupName, 'Urun Ozelligi Yok') END AS missingFeature,"
        $missingOrder = ""
    } else {
        $filters += "NOT $keywordExists"
    }

    if ($StockMode -eq "in") {
        $filters += "ISNULL(v.StockAmount, ISNULL(s.StockAmount, ISNULL(p.StockAmount, 0))) > 0"
    } elseif ($StockMode -eq "out") {
        $filters += "ISNULL(v.StockAmount, ISNULL(s.StockAmount, ISNULL(p.StockAmount, 0))) <= 0"
    }

    if (-not [string]::IsNullOrWhiteSpace($Brand)) {
        $filters += "p.Brand LIKE @brand"
        $params["@brand"] = "%$Brand%"
    }

    if (-not [string]::IsNullOrWhiteSpace($Feature) -and $Status -ne "present") {
        $filters += "COALESCE(f.filterGroupName, 'Urun Ozelligi Yok') = @feature"
        $params["@feature"] = $Feature
    }

    if (-not [string]::IsNullOrWhiteSpace($Search)) {
        $filters += @"
(
    p.ProductCode LIKE @searchPrefix OR
    p.ProductTitle LIKE @search OR
    p.Brand LIKE @search OR
    s.ColorCode LIKE @search OR
    s.NebimColor LIKE @search OR
    f.model LIKE @searchPrefix OR
    f.filterGroupName LIKE @search OR
    v.StockCode LIKE @searchPrefix OR
    v.Barcode LIKE @searchPrefix
)
"@
        $params["@search"] = "%$Search%"
        $params["@searchPrefix"] = "$Search%"
    }

    $where = "WHERE " + ($filters -join " AND ")
    if ($Mode -eq "model" -and $Status -eq "missing") {
        $sql = @"
SELECT TOP ($Take)
    MIN(COALESCE(f.model, s.ProductSubCode)) AS missingModel,
    MIN(f.filterGroupId) AS missingFeatureId,
    COALESCE(MIN(f.filterGroupName), 'Urun Ozelligi Yok') AS missingFeature,
    p.Id AS productId,
    p.ProductCode AS productCode,
    p.ProductTitle AS title,
    p.Brand AS brand,
    MAX(CONVERT(varchar(max), p.Description)) AS description,
    STRING_AGG(CONVERT(varchar(max), COALESCE(NULLIF(s.NebimColor, ''), s.ColorCode)), ', ') AS color,
    STRING_AGG(CONVERT(varchar(max), v.SizeCode), ', ') AS size,
    COUNT(DISTINCT v.Barcode) AS barcodeCount,
    MIN(v.Barcode) AS barcode,
    MIN(COALESCE(NULLIF(v.StockCode, ''), s.ProductSubCode, f.model)) AS stockCode,
    SUM(ISNULL(v.StockAmount, ISNULL(s.StockAmount, ISNULL(p.StockAmount, 0)))) AS stock,
    MAX(p.PhotoCount) AS photoCount,
    MIN(COALESCE(NULLIF(v.ImageUrl, ''), img.ImagePath)) AS image,
    MAX(p.CreationDate) AS creationDate,
    0 AS attributeCount,
    NULL AS attributes
FROM dbo.AP_02ProductSubs s
$missingJoin
LEFT JOIN dbo.AP_04ProductVariants v ON v.ProductSubId = s.Id
LEFT JOIN dbo.AP_01Products p ON p.Id = s.ProductId
OUTER APPLY (
    SELECT TOP 1 ImagePath
    FROM dbo.AP_03ProductImageFiles i
    WHERE i.ProductSubId = s.Id AND ISNULL(i.IsActive, 1) = 1
    ORDER BY ISNULL(i.DisplayOrder, 9999), i.Id
) img
$where
GROUP BY p.Id, p.ProductCode, p.ProductTitle, p.Brand
ORDER BY p.ProductCode
"@
    } elseif ($Mode -eq "model" -and $Status -eq "present") {
        $sql = @"
SELECT TOP ($Take)
    MIN(s.ProductSubCode) AS missingModel,
    NULL AS missingFeatureId,
    'Ozellik Var' AS missingFeature,
    p.Id AS productId,
    p.ProductCode AS productCode,
    p.ProductTitle AS title,
    p.Brand AS brand,
    MAX(CONVERT(varchar(max), p.Description)) AS description,
    STRING_AGG(CONVERT(varchar(max), COALESCE(NULLIF(s.NebimColor, ''), s.ColorCode)), ', ') AS color,
    STRING_AGG(CONVERT(varchar(max), v.SizeCode), ', ') AS size,
    COUNT(DISTINCT v.Barcode) AS barcodeCount,
    MIN(v.Barcode) AS barcode,
    MIN(COALESCE(NULLIF(v.StockCode, ''), s.ProductSubCode, f.model)) AS stockCode,
    SUM(ISNULL(v.StockAmount, ISNULL(s.StockAmount, ISNULL(p.StockAmount, 0)))) AS stock,
    MAX(p.PhotoCount) AS photoCount,
    MIN(COALESCE(NULLIF(v.ImageUrl, ''), img.ImagePath)) AS image,
    MAX(p.CreationDate) AS creationDate,
    MAX(aa.attrCount) AS attributeCount,
    MIN(CONVERT(varchar(4000), aa.attrSummary)) AS attributes
FROM dbo.AP_02ProductSubs s
$missingJoin
LEFT JOIN dbo.AP_04ProductVariants v ON v.ProductSubId = s.Id
LEFT JOIN dbo.AP_01Products p ON p.Id = s.ProductId
OUTER APPLY (
    SELECT
        COUNT(*) AS attrCount,
        STRING_AGG(CONVERT(varchar(max), CONVERT(varchar(50), k.KeywordKey) + ':' + ISNULL(CONVERT(varchar(50), k.KeywordValue), '')), ' | ') AS attrSummary
    FROM dbo.AP_01ProductKeywords k
    WHERE k.ProductId = p.Id AND NULLIF(LTRIM(RTRIM(k.KeywordKey)), '') IS NOT NULL
) aa
OUTER APPLY (
    SELECT TOP 1 ImagePath
    FROM dbo.AP_03ProductImageFiles i
    WHERE i.ProductSubId = s.Id AND ISNULL(i.IsActive, 1) = 1
    ORDER BY ISNULL(i.DisplayOrder, 9999), i.Id
) img
$where
GROUP BY p.Id, p.ProductCode, p.ProductTitle, p.Brand
ORDER BY p.ProductCode
"@
    } elseif ($Mode -eq "model") {
        $sql = @"
SELECT TOP ($Take)
    MIN(x.missingModel) AS missingModel,
    MIN(x.missingFeatureId) AS missingFeatureId,
    x.missingFeature AS missingFeature,
    p.Id AS productId,
    p.ProductCode AS productCode,
    p.ProductTitle AS title,
    p.Brand AS brand,
    MAX(CONVERT(varchar(max), p.Description)) AS description,
    STRING_AGG(CONVERT(varchar(max), COALESCE(NULLIF(s.NebimColor, ''), s.ColorCode)), ', ') AS color,
    STRING_AGG(CONVERT(varchar(max), v.SizeCode), ', ') AS size,
    COUNT(DISTINCT v.Barcode) AS barcodeCount,
    MIN(v.Barcode) AS barcode,
    MIN(COALESCE(NULLIF(v.StockCode, ''), s.ProductSubCode, f.model)) AS stockCode,
    SUM(ISNULL(v.StockAmount, ISNULL(s.StockAmount, ISNULL(p.StockAmount, 0)))) AS stock,
    MAX(p.PhotoCount) AS photoCount,
    MIN(COALESCE(NULLIF(v.ImageUrl, ''), img.ImagePath)) AS image,
    MAX(p.CreationDate) AS creationDate,
    MAX(aa.attrCount) AS attributeCount,
    MIN(CONVERT(varchar(4000), aa.attrSummary)) AS attributes
FROM dbo.AP_02ProductSubs s
$missingJoin
LEFT JOIN dbo.AP_04ProductVariants v ON v.ProductSubId = s.Id
LEFT JOIN dbo.AP_01Products p ON p.Id = s.ProductId
OUTER APPLY (
    SELECT
        COUNT(*) AS attrCount,
        STRING_AGG(CONVERT(varchar(max), CONVERT(varchar(50), k.KeywordKey) + ':' + ISNULL(CONVERT(varchar(50), k.KeywordValue), '')), ' | ') AS attrSummary
    FROM dbo.AP_01ProductKeywords k
    WHERE k.ProductId = p.Id AND NULLIF(LTRIM(RTRIM(k.KeywordKey)), '') IS NOT NULL
) aa
OUTER APPLY (SELECT $missingSelect 1 AS dummy) x
OUTER APPLY (
    SELECT TOP 1 ImagePath
    FROM dbo.AP_03ProductImageFiles i
    WHERE i.ProductSubId = s.Id AND ISNULL(i.IsActive, 1) = 1
    ORDER BY ISNULL(i.DisplayOrder, 9999), i.Id
) img
$where
GROUP BY p.Id, p.ProductCode, p.ProductTitle, p.Brand, x.missingFeature
ORDER BY $missingOrder p.ProductCode
"@
    } else {
        $sql = @"
SELECT TOP ($Take)
    x.missingModel AS missingModel,
    x.missingFeatureId AS missingFeatureId,
    x.missingFeature AS missingFeature,
    p.Id AS productId,
    p.ProductCode AS productCode,
    p.ProductTitle AS title,
    p.Brand AS brand,
    p.Description AS description,
    COALESCE(NULLIF(s.NebimColor, ''), s.ColorCode) AS color,
    v.SizeCode AS size,
    v.Barcode AS barcode,
    COALESCE(NULLIF(v.StockCode, ''), s.ProductSubCode, f.model) AS stockCode,
    ISNULL(v.StockAmount, ISNULL(s.StockAmount, ISNULL(p.StockAmount, 0))) AS stock,
    p.PhotoCount AS photoCount,
    COALESCE(NULLIF(v.ImageUrl, ''), img.ImagePath) AS image,
    p.CreationDate AS creationDate,
    aa.attrCount AS attributeCount,
    aa.attrSummary AS attributes
FROM dbo.AP_02ProductSubs s
$missingJoin
LEFT JOIN dbo.AP_04ProductVariants v ON v.ProductSubId = s.Id
LEFT JOIN dbo.AP_01Products p ON p.Id = s.ProductId
OUTER APPLY (
    SELECT
        COUNT(*) AS attrCount,
        STRING_AGG(CONVERT(varchar(max), CONVERT(varchar(50), k.KeywordKey) + ':' + ISNULL(CONVERT(varchar(50), k.KeywordValue), '')), ' | ') AS attrSummary
    FROM dbo.AP_01ProductKeywords k
    WHERE k.ProductId = p.Id AND NULLIF(LTRIM(RTRIM(k.KeywordKey)), '') IS NOT NULL
) aa
OUTER APPLY (SELECT $missingSelect 1 AS dummy) x
OUTER APPLY (
    SELECT TOP 1 ImagePath
    FROM dbo.AP_03ProductImageFiles i
    WHERE i.ProductSubId = s.Id AND ISNULL(i.IsActive, 1) = 1
    ORDER BY ISNULL(i.DisplayOrder, 9999), i.Id
) img
$where
ORDER BY $missingOrder p.ProductCode, s.Id, v.SortOrder, v.Id
"@
    }

    $rows = Invoke-Query "avrupayakasi" $sql $params
    return [pscustomobject]@{ rows = @($rows) }
}

function Get-DescriptionProducts([string]$Search, [string]$StockMode = "in", [int]$Take = 500, [string]$Mode = "model", [string]$Status = "missing", [string]$Brand = "") {
    if ($Take -lt 1 -or $Take -gt 5000) { $Take = 500 }
    $params = @{}
    $filters = @("1 = 1")
    $descExpr = "NULLIF(LTRIM(RTRIM(CONVERT(varchar(max), ISNULL(p.Description, '')))), '')"

    if ($Status -eq "present") {
        $filters += "$descExpr IS NOT NULL"
    } elseif ($Status -ne "all") {
        $filters += "$descExpr IS NULL"
    }

    if ($StockMode -eq "in") {
        $filters += "ISNULL(p.StockAmount, 0) > 0"
    } elseif ($StockMode -eq "out") {
        $filters += "ISNULL(p.StockAmount, 0) <= 0"
    }

    if (-not [string]::IsNullOrWhiteSpace($Brand)) {
        $filters += "p.Brand LIKE @brand"
        $params["@brand"] = "%$Brand%"
    }

    if (-not [string]::IsNullOrWhiteSpace($Search)) {
        $filters += @"
(
    p.ProductCode LIKE @searchPrefix OR
    p.ProductTitle LIKE @search OR
    p.Brand LIKE @search
)
"@
        $params["@search"] = "%$Search%"
        $params["@searchPrefix"] = "$Search%"
    }

    $where = "WHERE " + ($filters -join " AND ")
    if ($Mode -eq "detail") {
        $sql = @"
SELECT TOP ($Take)
    s.ProductSubCode AS missingModel,
    NULL AS missingFeatureId,
    CASE WHEN $descExpr IS NULL THEN 'Aciklama Yok' ELSE 'Aciklama Var' END AS missingFeature,
    p.Id AS productId,
    p.ProductCode AS productCode,
    p.ProductTitle AS title,
    p.Brand AS brand,
    p.Description AS description,
    COALESCE(NULLIF(s.NebimColor, ''), s.ColorCode) AS color,
    v.SizeCode AS size,
    v.Barcode AS barcode,
    COALESCE(NULLIF(v.StockCode, ''), s.ProductSubCode) AS stockCode,
    ISNULL(p.StockAmount, 0) AS stock,
    p.PhotoCount AS photoCount,
    COALESCE(NULLIF(v.ImageUrl, ''), img.ImagePath) AS image,
    p.CreationDate AS creationDate,
    NULL AS attributeCount,
    NULL AS attributes
FROM dbo.AP_01Products p
LEFT JOIN dbo.AP_02ProductSubs s ON s.ProductId = p.Id
LEFT JOIN dbo.AP_04ProductVariants v ON v.ProductSubId = s.Id
OUTER APPLY (
    SELECT TOP 1 ImagePath
    FROM dbo.AP_03ProductImageFiles i
    WHERE i.ProductSubId = s.Id AND ISNULL(i.IsActive, 1) = 1
    ORDER BY ISNULL(i.DisplayOrder, 9999), i.Id
) img
$where
ORDER BY ISNULL(p.StockAmount, 0) DESC, p.ProductCode, s.Id, v.SortOrder, v.Id
"@
    } else {
        $sql = @"
SELECT TOP ($Take)
    MIN(s.ProductSubCode) AS missingModel,
    NULL AS missingFeatureId,
    CASE WHEN $descExpr IS NULL THEN 'Aciklama Yok' ELSE 'Aciklama Var' END AS missingFeature,
    p.Id AS productId,
    p.ProductCode AS productCode,
    p.ProductTitle AS title,
    p.Brand AS brand,
    MAX(CONVERT(varchar(max), p.Description)) AS description,
    STRING_AGG(CONVERT(varchar(max), COALESCE(NULLIF(s.NebimColor, ''), s.ColorCode)), ', ') AS color,
    STRING_AGG(CONVERT(varchar(max), v.SizeCode), ', ') AS size,
    COUNT(DISTINCT v.Barcode) AS barcodeCount,
    MIN(v.Barcode) AS barcode,
    MIN(COALESCE(NULLIF(v.StockCode, ''), s.ProductSubCode)) AS stockCode,
    MAX(ISNULL(p.StockAmount, 0)) AS stock,
    MAX(p.PhotoCount) AS photoCount,
    MIN(COALESCE(NULLIF(v.ImageUrl, ''), img.ImagePath)) AS image,
    MAX(p.CreationDate) AS creationDate,
    NULL AS attributeCount,
    NULL AS attributes
FROM dbo.AP_01Products p
LEFT JOIN dbo.AP_02ProductSubs s ON s.ProductId = p.Id
LEFT JOIN dbo.AP_04ProductVariants v ON v.ProductSubId = s.Id
OUTER APPLY (
    SELECT TOP 1 ImagePath
    FROM dbo.AP_03ProductImageFiles i
    WHERE i.ProductSubId = s.Id AND ISNULL(i.IsActive, 1) = 1
    ORDER BY ISNULL(i.DisplayOrder, 9999), i.Id
) img
$where
GROUP BY p.Id, p.ProductCode, p.ProductTitle, p.Brand, CASE WHEN $descExpr IS NULL THEN 'Aciklama Yok' ELSE 'Aciklama Var' END
ORDER BY MAX(ISNULL(p.StockAmount, 0)) DESC, p.ProductCode
"@
    }

    $rows = Invoke-Query "avrupayakasi" $sql $params
    return [pscustomobject]@{ rows = @($rows) }
}

function Get-MissingAttributeGroups() {
    $sql = @"
SELECT filterGroupName AS name, COUNT(*) AS count
FROM dbo.PZ_FiltresizUrunler
GROUP BY filterGroupName
ORDER BY filterGroupName
"@
    $rows = Invoke-Query "avrupayakasi" $sql
    return [pscustomobject]@{ groups = @($rows) }
}

function Get-ReportBrands() {
    $sql = @"
SELECT Brand AS name, COUNT(*) AS count
FROM dbo.AP_01Products
WHERE NULLIF(LTRIM(RTRIM(ISNULL(Brand, ''))), '') IS NOT NULL
GROUP BY Brand
ORDER BY Brand
"@
    $rows = Invoke-Query "avrupayakasi" $sql
    return [pscustomobject]@{ brands = @($rows) }
}

function Get-StockLocations([string]$Search, [string]$LocationGroup = "all", [int]$Take = 1000) {
    if ($Take -lt 1 -or $Take -gt 5000) { $Take = 1000 }
    $params = @{}
    $focusLocations = "N'MULTIBRAND-001', N'LVT-TEKS-001', N'LVT-AYK-001', N'LVT-ÇNT-001'"
    $filters = @("ISNULL(l.StockQuantity, 0) > 0")

    if ($LocationGroup -eq "depo") {
        $filters += "(sb.ShelfUnitCode IS NULL OR sb.ShelfUnitCode NOT IN ($focusLocations))"
    } elseif (-not [string]::IsNullOrWhiteSpace($LocationGroup) -and $LocationGroup -ne "all") {
        $filters += "sb.ShelfUnitCode = @locationGroup"
        $params["@locationGroup"] = $LocationGroup
    }

    if (-not [string]::IsNullOrWhiteSpace($Search)) {
        $filters += @"
(
    p.ProductCode LIKE @searchPrefix OR
    p.ProductTitle LIKE @search OR
    p.Brand LIKE @search OR
    COALESCE(NULLIF(s.NebimColor, ''), v.ColorCode) LIKE @search OR
    v.SizeCode LIKE @search OR
    v.StockCode LIKE @searchPrefix OR
    v.Barcode LIKE @searchPrefix OR
    sb.ShelfUnitCode LIKE @search OR
    l.ShelfUnitBarcode LIKE @searchPrefix
)
"@
        $params["@search"] = "%$Search%"
        $params["@searchPrefix"] = "$Search%"
    }

    $where = "WHERE " + ($filters -join " AND ")
    $sql = @"
SELECT TOP ($Take)
    CASE
        WHEN q.shelfUnitCode IN ($focusLocations) THEN q.shelfUnitCode
        ELSE 'Depo'
    END AS locationGroup,
    q.shelfUnitCode,
    q.shelfUnitBarcode,
    q.productCode,
    q.title,
    q.brand,
    q.description,
    q.color,
    q.size,
    q.barcode,
    q.stockCode,
    q.locationStock,
    q.variantStock,
    q.image
FROM (
    SELECT
        ISNULL(sb.ShelfUnitCode, 'Goz Kodu Yok') AS shelfUnitCode,
        l.ShelfUnitBarcode AS shelfUnitBarcode,
        p.ProductCode AS productCode,
        p.ProductTitle AS title,
        p.Brand AS brand,
        MAX(CONVERT(varchar(max), p.Description)) AS description,
        COALESCE(NULLIF(s.NebimColor, ''), v.ColorCode) AS color,
        v.SizeCode AS size,
        v.Barcode AS barcode,
        v.StockCode AS stockCode,
        SUM(ISNULL(l.StockQuantity, 0)) AS locationStock,
        MAX(ISNULL(v.StockAmount, 0)) AS variantStock,
        MIN(COALESCE(NULLIF(v.ImageUrl, ''), img.ImagePath)) AS image
    FROM dbo.AP_06ProductLocations l
    LEFT JOIN dbo.AP_04ProductVariants v ON v.Id = l.ProductVariantId
    LEFT JOIN dbo.AP_02ProductSubs s ON s.Id = v.ProductSubId
    LEFT JOIN dbo.AP_01Products p ON p.Id = s.ProductId
    LEFT JOIN dbo.DF_StorageBarcodes sb ON sb.ShelfUnitBarcode = l.ShelfUnitBarcode
    OUTER APPLY (
        SELECT TOP 1 ImagePath
        FROM dbo.AP_03ProductImageFiles i
        WHERE i.ProductSubId = s.Id AND ISNULL(i.IsActive, 1) = 1
        ORDER BY ISNULL(i.DisplayOrder, 9999), i.Id
    ) img
    $where
    GROUP BY
        ISNULL(sb.ShelfUnitCode, 'Goz Kodu Yok'),
        l.ShelfUnitBarcode,
        p.ProductCode,
        p.ProductTitle,
        p.Brand,
        COALESCE(NULLIF(s.NebimColor, ''), v.ColorCode),
        v.SizeCode,
        v.Barcode,
        v.StockCode
) q
ORDER BY
    CASE WHEN q.shelfUnitCode IN ($focusLocations) THEN 0 ELSE 1 END,
    q.shelfUnitCode,
    q.productCode,
    q.color,
    q.size
"@

    $rows = Invoke-Query "avrupayakasi" $sql $params
    return [pscustomobject]@{ rows = @($rows) }
}

function Get-StockLocationDetail([string]$ProductCode) {
    if ([string]::IsNullOrWhiteSpace($ProductCode)) { throw "Urun kodu bos olamaz." }
    $cleanCode = $ProductCode.Trim()
    $focusLocations = "N'MULTIBRAND-001', N'LVT-TEKS-001', N'LVT-AYK-001', N'LVT-ÇNT-001'"
    $sql = @"
SELECT
    CASE
        WHEN q.shelfUnitCode IN ($focusLocations) THEN q.shelfUnitCode
        ELSE 'Depo'
    END AS locationGroup,
    q.shelfUnitCode,
    q.shelfUnitBarcode,
    q.productCode,
    q.title,
    q.brand,
    q.description,
    q.color,
    q.size,
    q.barcode,
    q.stockCode,
    q.locationStock,
    q.variantStock,
    q.image
FROM (
    SELECT
        ISNULL(sb.ShelfUnitCode, 'Goz Kodu Yok') AS shelfUnitCode,
        l.ShelfUnitBarcode AS shelfUnitBarcode,
        p.ProductCode AS productCode,
        p.ProductTitle AS title,
        p.Brand AS brand,
        MAX(CONVERT(varchar(max), p.Description)) AS description,
        COALESCE(NULLIF(s.NebimColor, ''), v.ColorCode) AS color,
        v.SizeCode AS size,
        v.Barcode AS barcode,
        v.StockCode AS stockCode,
        SUM(ISNULL(l.StockQuantity, 0)) AS locationStock,
        MAX(ISNULL(v.StockAmount, 0)) AS variantStock,
        MIN(COALESCE(NULLIF(v.ImageUrl, ''), img.ImagePath)) AS image
    FROM dbo.AP_06ProductLocations l
    LEFT JOIN dbo.AP_04ProductVariants v ON v.Id = l.ProductVariantId
    LEFT JOIN dbo.AP_02ProductSubs s ON s.Id = v.ProductSubId
    LEFT JOIN dbo.AP_01Products p ON p.Id = s.ProductId
    LEFT JOIN dbo.DF_StorageBarcodes sb ON sb.ShelfUnitBarcode = l.ShelfUnitBarcode
    OUTER APPLY (
        SELECT TOP 1 ImagePath
        FROM dbo.AP_03ProductImageFiles i
        WHERE i.ProductSubId = s.Id AND ISNULL(i.IsActive, 1) = 1
        ORDER BY ISNULL(i.DisplayOrder, 9999), i.Id
    ) img
    WHERE ISNULL(l.StockQuantity, 0) > 0
      AND p.ProductCode = @productCode
    GROUP BY
        ISNULL(sb.ShelfUnitCode, 'Goz Kodu Yok'),
        l.ShelfUnitBarcode,
        p.ProductCode,
        p.ProductTitle,
        p.Brand,
        COALESCE(NULLIF(s.NebimColor, ''), v.ColorCode),
        v.SizeCode,
        v.Barcode,
        v.StockCode
) q
ORDER BY
    CASE
        WHEN q.shelfUnitCode = N'LVT-TEKS-001' THEN 1
        WHEN q.shelfUnitCode = N'LVT-AYK-001' THEN 2
        WHEN q.shelfUnitCode = N'LVT-ÇNT-001' THEN 3
        WHEN q.shelfUnitCode = N'MULTIBRAND-001' THEN 4
        ELSE 5
    END,
    q.shelfUnitCode,
    q.color,
    q.size
"@

    $rows = Invoke-Query "avrupayakasi" $sql @{ "@productCode" = $cleanCode }
    return [pscustomobject]@{ productCode = $cleanCode; rows = @($rows) }
}

function Save-ProductAttribute($Payload) {
    $productId = [int]$Payload.productId
    $productCode = [string]$Payload.productCode
    $feature = [string]$Payload.feature
    $value = [string]$Payload.value
    $note = [string]$Payload.note
    if ($productId -le 0) { throw "ProductId bulunamadi." }
    if ([string]::IsNullOrWhiteSpace($productCode)) { throw "Urun kodu bulunamadi." }
    if ([string]::IsNullOrWhiteSpace($feature)) { throw "Ozellik adi bos olamaz." }
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Ozellik degeri bos olamaz." }
    if ([string]::IsNullOrWhiteSpace($note)) {
        $note = "Ozellik: $feature`nDeger: $value"
    }

    $nebim = Save-NebimItemNote $productCode $note
    return [pscustomobject]@{
        ok = $true
        action = "nebim-note-only"
        nebim = $nebim
        message = "Nebim notlar alanina yazildi: $productCode"
    }
}

function Save-ProductDescription($Payload) {
    $productId = [int]$Payload.productId
    $productCode = [string]$Payload.productCode
    $description = [string]$Payload.description
    if ($productId -le 0) { throw "ProductId bulunamadi." }
    if ([string]::IsNullOrWhiteSpace($productCode)) { throw "Urun kodu bulunamadi." }
    if ([string]::IsNullOrWhiteSpace($description)) { throw "Yazilacak aciklama/not bos olamaz." }

    $nebim = Save-NebimItemNote $productCode $description
    return [pscustomobject]@{
        ok = $true
        affected = 0
        nebim = $nebim
        message = "Nebim notlar alanina yazildi: $productCode"
    }
}

$listener = New-Object Net.HttpListener
$prefix = "http://127.0.0.1:$($script:Port)/"
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "Panel running: $prefix"

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        try {
            $path = $ctx.Request.Url.AbsolutePath
            if ($path -eq "/") {
                Send-Text $ctx.Response 200 "text/html" (Get-Content (Join-Path $script:Root "index.html") -Raw)
            } elseif ($path -eq "/styles.css") {
                Send-Text $ctx.Response 200 "text/css" (Get-Content (Join-Path $script:Root "styles.css") -Raw)
            } elseif ($path -eq "/report-compact.css") {
                Send-Text $ctx.Response 200 "text/css" (Get-Content (Join-Path $script:Root "report-compact.css") -Raw)
            } elseif ($path -eq "/app.js") {
                Send-Text $ctx.Response 200 "application/javascript" (Get-Content (Join-Path $script:Root "app.js") -Raw)
            } elseif ($path -eq "/api/status") {
                Send-Json $ctx.Response ([pscustomobject]@{ server = $script:SqlHost; user = $script:SqlUser; databases = @($script:DefaultDbs | ForEach-Object { Test-Database $_ }) })
            } elseif ($path -eq "/api/schema") {
                $db = $ctx.Request.QueryString["database"]
                Send-Json $ctx.Response ([pscustomobject]@{ database = $db; columns = @(Get-Schema $db) })
            } elseif ($path -eq "/api/preview") {
                Send-Json $ctx.Response ([pscustomobject]@{ rows = @(Get-Preview $ctx.Request.QueryString["database"] $ctx.Request.QueryString["schema"] $ctx.Request.QueryString["table"] 50) })
            } elseif ($path -eq "/api/ecd-products") {
                $take = 1000
                if ($ctx.Request.QueryString["take"]) { $take = [int]$ctx.Request.QueryString["take"] }
                Send-Json $ctx.Response (Get-EcdProducts $ctx.Request.QueryString["search"] $take)
            } elseif ($path -eq "/api/platform-products") {
                $take = 500
                if ($ctx.Request.QueryString["take"]) { $take = [int]$ctx.Request.QueryString["take"] }
                Send-Json $ctx.Response (Get-PlatformProducts $ctx.Request.QueryString["model"] $take)
            } elseif ($path -eq "/api/missing-attributes") {
                $take = 500
                if ($ctx.Request.QueryString["take"]) { $take = [int]$ctx.Request.QueryString["take"] }
                $stock = $ctx.Request.QueryString["stock"]
                if ([string]::IsNullOrWhiteSpace($stock)) { $stock = "in" }
                $mode = $ctx.Request.QueryString["mode"]
                if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "detail" }
                $status = $ctx.Request.QueryString["status"]
                if ([string]::IsNullOrWhiteSpace($status)) { $status = "missing" }
                $check = $ctx.Request.QueryString["check"]
                if ([string]::IsNullOrWhiteSpace($check)) { $check = "description" }
                $brand = Get-QueryParamUtf8 $ctx.Request "brand"
                if ($check -eq "keywords") {
                    Send-Json $ctx.Response (Get-MissingAttributeProducts $ctx.Request.QueryString["search"] $stock $take $ctx.Request.QueryString["feature"] $mode $status $brand)
                } else {
                    Send-Json $ctx.Response (Get-DescriptionProducts $ctx.Request.QueryString["search"] $stock $take $mode $status $brand)
                }
            } elseif ($path -eq "/api/missing-attribute-groups") {
                Send-Json $ctx.Response (Get-MissingAttributeGroups)
            } elseif ($path -eq "/api/report-brands") {
                Send-Json $ctx.Response (Get-ReportBrands)
            } elseif ($path -eq "/api/stock-locations") {
                $take = 1000
                if ($ctx.Request.QueryString["take"]) { $take = [int]$ctx.Request.QueryString["take"] }
                $group = $ctx.Request.QueryString["group"]
                if ([string]::IsNullOrWhiteSpace($group)) { $group = "all" }
                Send-Json $ctx.Response (Get-StockLocations $ctx.Request.QueryString["search"] $group $take)
            } elseif ($path -eq "/api/stock-location-detail") {
                Send-Json $ctx.Response (Get-StockLocationDetail $ctx.Request.QueryString["productCode"])
            } elseif ($path -eq "/api/product-description" -and $ctx.Request.HttpMethod -eq "POST") {
                Send-Json $ctx.Response (Save-ProductDescription (Read-BodyJson $ctx.Request))
            } elseif ($path -eq "/api/product-attribute" -and $ctx.Request.HttpMethod -eq "POST") {
                Send-Json $ctx.Response (Save-ProductAttribute (Read-BodyJson $ctx.Request))
            } elseif ($path -eq "/api/ecs-update-from-nebim" -and $ctx.Request.HttpMethod -eq "POST") {
                Send-Json $ctx.Response (Update-EcsProductFromNebim (Read-BodyJson $ctx.Request))
            } elseif ($path -eq "/api/products" -and $ctx.Request.HttpMethod -eq "POST") {
                Send-Json $ctx.Response (Get-Products (Read-BodyJson $ctx.Request))
            } else {
                Send-Json $ctx.Response ([pscustomobject]@{ error = "Not found" }) 404
            }
        } catch {
            $message = $_.Exception.Message
            if ($_.Exception.InnerException -and -not [string]::IsNullOrWhiteSpace($_.Exception.InnerException.Message)) {
                $message = "$message $($_.Exception.InnerException.Message)".Trim()
            }
            if ([string]::IsNullOrWhiteSpace($message)) { $message = ($_ | Out-String).Trim() }
            Send-Json $ctx.Response ([pscustomobject]@{ error = $message }) 500
        }
    }
} finally {
    $listener.Stop()
}
