#!/usr/bin/env pwsh

<#
.SYNOPSIS
Downloads the models needed for upscaling textures.
Mirrors for the models are defined in `upscale-models.json`.
#>


[CmdletBinding(SupportsShouldProcess)]
param()

. (Join-Path $PSScriptRoot 'lib/common.ps1')


$models_dir = Get-ModelsDir
$model_list_path = Join-Path $ProjectDir 'upscale-models.json'

if (-not (Test-Path -LiteralPath $model_list_path -PathType Leaf)) {
	throw "Could not find upscale model download mirrors: File '${model_list_path}' does not exist."
}

$model_list =
	Get-Content -LiteralPath $model_list_path -Raw -ErrorAction Stop |
	ConvertFrom-Json -ErrorAction Stop

$ProgressPreference = 'SilentlyContinue'

foreach ($model in $model_list) {
	$out_file = Join-Path $models_dir $model.ModelName

	if (Test-Path -LiteralPath $out_file -PathType Leaf) {
		$out_file_hash = (Get-FileHash -LiteralPath $out_file -Algorithm SHA1).Hash

		if ($out_file_hash -eq $model.HashSHA1) {
			continue
		}
		
		Write-Warning (
			"Upscale model '$( $model.ModelName )' has incorrect " +
			"SHA1 file hash (${out_file_hash}). Re-downloading ..."
		)

		try {
			$null = Remove-Item -LiteralPath $out_file -ErrorAction Stop
		}
		catch {
			throw "Could not delete bad model file: $( $_.Exception.Message )"
		}
	}

	Write-Host "Downloading upscale model '$( $model.ModelName )' ..."
	$download_success = $false

	foreach ($mirror in $model.Mirrors) {
		try {
			if ($PSCmdlet.ShouldProcess("(From: ${mirror}, To: ${out_file})", 'Download File')) {
				$null = Invoke-RestMethod -Uri $mirror -OutFile $out_file -Method Get -UseBasicParsing -ErrorAction Stop
			}

			$out_file_hash = (Get-FileHash -LiteralPath $out_file -Algorithm SHA1).Hash
			if ($out_file_hash -ne $model.HashSHA1) {
				Write-Warning "${mirror}: Invalid SHA1 file hash '${out_file_hash}'."
				$null = Remove-Item -LiteralPath $out_file -ErrorAction SilentlyContinue
				continue
			}

			Write-Host "${mirror}: Success."
			$download_success = $true
			break
		}
		catch {
			Write-Warning "${mirror}: $( $_.Exception.Message )"
		}
	}

	if (-not $download_success) {
		throw "Failed to download upscale model."
	}
}
