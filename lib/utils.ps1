using namespace System.Collections.Generic
using namespace System.IO

$ProjectDir = Split-Path $PSScriptRoot -Parent


class UpscaleOptions {
	[string] $DefaultModel

	[Dictionary[string, string]] $TextureModels

	UpscaleOptions([string] $Json) {
		$raw_options = $Json | ConvertFrom-Json

		$this.DefaultModel = $raw_options.DefaultModel
		if (-not (IsValidFilename $this.DefaultModel)) {
			throw "'DefaultModel' must not be empty or contain invalid filename characters."
		}

		$this.TextureModels = [Dictionary[string, string]]::new()

		foreach ($model in $raw_options.CustomUpscaling) {
			if (-not (IsValidFilename $model.ModelName)) {
				throw "in 'CustomUpscaling': 'ModelName' must not be empty or contain invalid filename characters."
			}

			foreach ($texture_name in $model.TextureNames) {
				if (-not (IsValidFilename $texture_name)) {
					throw "in 'CustomUpscaling': in model '$($model.ModelName): " +
						"'TextureNames' items must not be empty or contain invalid filename characters."
				}

				$this.TextureModels[$texture_name] = $model.ModelName
			}
		}

		foreach ($texture_name in $raw_options.ManualUpscaling) {
			if (-not (IsValidFilename $texture_name)) {
				throw "in 'ManualUpscaling': 'TextureNames' items must not be empty " +
					"or contain invalid filename characters."
			}

			$this.TextureModels[$texture_name] = 'manual'
		}

		foreach ($category in $raw_options.NoUpscaling) {
			foreach ($texture_name in $category.TextureNames) {
				if (-not (IsValidFilename $texture_name)) {
					throw "in 'NoUpscaling': 'TextureNames' items must not be empty " +
						"or contain invalid filename characters."
				}

				$this.TextureModels[$texture_name] = 'none'
			}
		}
	}
}


<#
.SYNOPSIS
Verifies a directory exists and creates it if it doesn't.
Throws an exception if the directory can't be created.
#>
function Initialize-Directory {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]
		$Path
	)

	if (Test-Path -LiteralPath $Path -PathType Container) { return }

	Write-Verbose "Creating directory '${Path}' ..."
	$null = New-Item $Path -ItemType Directory
	if (-not $?) {
		throw "Failed to create directory '${Path}': $($Error[0])"
	}
}

function Get-TexturesDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path $ProjectDir 'textures/'
	Initialize-Directory $dir -Verbose:$VerbosePreference
	$dir
}

function Get-SearchResultsDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path (Get-TexturesDir -Verbose:$VerbosePreference) 'search-results/'
	Initialize-Directory $dir -Verbose:$VerbosePreference
	$dir
}

function Get-OriginalTexturesDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path (Get-TexturesDir -Verbose:$VerbosePreference) 'original/'
	Initialize-Directory $dir -Verbose:$VerbosePreference
	$dir
}

function Get-UpscaledTexturesDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path (Get-TexturesDir -Verbose:$VerbosePreference) 'upscaled/'
	Initialize-Directory $dir -Verbose:$VerbosePreference
	$dir
}

function Get-OpenGoalInstallDir {
	[CmdletBinding()]
	[OutputType([string])]
	param()

	Write-Verbose "Searching for OpenGOAL installation directory ..."

	$search_paths = @(
		(Join-Path $env:LOCALAPPDATA 'Programs/OpenGOAL/'),
		"C:/ProgramData/OpenGOAL/"
	)

	foreach ($search_path in $search_paths) {
		if (Test-Path -LiteralPath $search_path -PathType Container) {
			Write-Verbose "Found OpenGOAL installation at '${search_path}'."
			return $search_path
		}

		Write-Verbose "No installation at '${search_path}'."
	}

	throw "Failed to find OpenGOAL installation directory."
}

function Get-Jak3TexturesDir {
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]
		$OpenGoalDir
	)

	Write-Verbose "Searching for Jak 3 textures directory ..."

	$search_paths = @(
		(Join-Path $OpenGoalDir 'active/jak3/data/decompiler_out/jak3/textures/'),
		(Join-Path $OpenGoalDir 'data/decompiler_out/jak3/textures/')
	)

	foreach ($search_path in $search_paths) {
		if (Test-Path -LiteralPath $search_path -PathType Container) {
			Write-Verbose "Found Jak 3 textures at '${search_path}'."
			return $search_path
		}

		Write-Verbose "No Jak 3 textures at '${search_path}'."
	}

	throw "Failed to find Jak 3 textures directory."
}

function Get-UpscaleOptions {
	[CmdletBinding()]
	[OutputType([UpscaleOptions])]
	param()

	$upscale_options_path = Join-Path $ProjectDir 'upscale-options.json'
	Write-Verbose "Reading upscale options file: '${upscale_options_path}' ..."
	[UpscaleOptions]::new([File]::ReadAllText($upscale_options_path))
}

function Clear-Directory {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[string[]]
		$Path
	)

	process {
		foreach ($path_to_clean in $Path) {
			Write-Verbose "Cleaning directory '${path_to_clean}' ..."

			$children =
				Get-ChildItem -LiteralPath $Path -ErrorAction Stop |
				Select-Object -ExpandProperty FullName -ErrorAction Stop
			$null = Remove-Item -LiteralPath $children -Recurse -Force -ErrorAction Stop
		}
	}
}

<#
.SYNOPSIS
Returns paths without their common parent path.
#>
function Get-PathWithoutPrefix {
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[string[]]
		$Path,

		[Parameter(Mandatory)]
		[string]
		$Prefix
	)

	begin {
		$prefix_pattern = "^$([regex]::Escape($Prefix))[\\/]*"
	}

	process {
		foreach ($path_item in $Path) {
			$path_item -replace $prefix_pattern
		}
	}
}

function IsValidFilename {
	[OutputType([bool])]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]
		$Name
	)

	if ([string]::IsNullOrWhiteSpace($Name) -or $Name.IndexOfAny([Path]::GetInvalidFileNameChars()) -ne -1) {
		return $false
	}

	$true
}
