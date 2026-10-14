param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Verify-Package.ps1')
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repo 'dist' }
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$version=(Get-Content -LiteralPath (Join-Path $repo 'VERSION') -Raw).Trim()
$archivePath=Join-Path $OutputDirectory ("MayaQuadDraw_Max2024_v$version.mzp")
$checksumPath=Join-Path $OutputDirectory ("MayaQuadDraw_Max2024_v$version.sha256")
if((Test-Path -LiteralPath $archivePath) -or (Test-Path -LiteralPath $checksumPath)){throw 'Release output exists. Use a new version/output directory; published artifacts stay unchanged.'}
$files=@('VERSION','LICENSE','LICENSE.zh-CN.txt','README.md','README.en.md','CONTRIBUTING.md','CHANGELOG.md','THIRD_PARTY_NOTICES.md','mzp.run','Install_MayaQuadDraw_Max2024.ms','Uninstall_MayaQuadDraw_Max2024.ms','macro/MayaQuadDraw_Max2024.mcr','startup/MayaQuadDraw_Max2024_Startup.ms','docs/INSTALL.md','docs/BUILD.md','docs/TESTING.md','docs/FAQ.md')
$files += @('docs/WORKFLOW_COMPARISON.md','docs/images/quad-preview.png','docs/images/triangle-hole-before.png','docs/images/triangle-hole-after.png')
foreach($folder in @('runtime','plugins')) {
    $allowed=if($folder -eq 'runtime'){@('.ms')}else{@('.dlx')}
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $repo ('payload/MayaQuadDraw_Max2024/'+$folder)) -File | Where-Object {$_.Extension -in $allowed}) {
        $files += 'payload/MayaQuadDraw_Max2024/'+$folder+'/'+$file.Name
    }
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream=[IO.File]::Open($archivePath,[IO.FileMode]::CreateNew)
$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
try {
    $packageHashes=@()
    foreach($relative in $files | Sort-Object) {
        $entry=$zip.CreateEntry($relative.Replace('\','/'),[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[DateTimeOffset]::new(2026,1,1,0,0,0,[TimeSpan]::Zero)
        $inputStream=[IO.File]::OpenRead((Join-Path $repo $relative))
        $outputStream=$entry.Open()
        try{$inputStream.CopyTo($outputStream)}finally{$outputStream.Dispose();$inputStream.Dispose()}
        $packageHashes += (Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash+'  '+$relative
    }
    $entry=$zip.CreateEntry('PACKAGE_SHA256SUMS.txt',[IO.Compression.CompressionLevel]::Optimal)
    $entry.LastWriteTime=[DateTimeOffset]::new(2026,1,1,0,0,0,[TimeSpan]::Zero)
    $writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
    try{$writer.Write(($packageHashes -join "`n")+"`n")}finally{$writer.Dispose()}
}finally{$zip.Dispose();$stream.Dispose()}
$hash=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
[IO.File]::WriteAllText($checksumPath,($hash+'  '+[IO.Path]::GetFileName($archivePath)+"`n"),[Text.UTF8Encoding]::new($false))
Write-Output "Created: $archivePath"
Write-Output "SHA256: $hash"
