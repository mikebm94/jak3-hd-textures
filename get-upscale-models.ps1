#!/usr/bin/env pwsh

<#
.SYNOPSIS
Downloads the models needed for upscaling textures.
Mirrors for the models are defined in `models/mirrors.json`.
#>


[CmdletBinding(SupportsShouldProcess)]
param()

. (Join-Path $PSScriptRoot 'lib/common.ps1')


$models_dir = Get-ModelsDir
$model_mirrors_path = Join-Path $models_dir 'mirrors.json'

if (-not (Test-Path -LiteralPath $model_mirrors_path -PathType Leaf)) {
	throw "Could not find upscale model download mirrors: File '${model_mirrors_path}' does not exist."
}

$model_mirrors =
	Get-Content -LiteralPath $model_mirrors_path -Raw -ErrorAction Stop |
	ConvertFrom-Json -ErrorAction Stop

foreach ($model in $model_mirrors) {
	$out_file = Join-Path $models_dir $model.ModelName

	if (Test-Path -LiteralPath $out_file -PathType Leaf) {
		continue
	}

	Write-Host "Downloading upscale model '$($model.ModelName)' ..."
	$download_success = $false

	foreach ($mirror in $model.Mirrors) {
		try {
			if ($PSCmdlet.ShouldProcess("(From: ${mirror}, To: ${out_file})", 'Download File')) {
				$null = Invoke-RestMethod -Uri $mirror -OutFile $out_file -UseBasicParsing -ErrorAction Stop
			}

			Write-Host "${mirror}: Success."
			$download_success = $true
			break
		}
		catch {
			Write-Host "${mirror}: $($_.Exception.Message)"
		}
	}

	if (-not $download_success) {
		throw "Failed to download upscale model."
	}
}
