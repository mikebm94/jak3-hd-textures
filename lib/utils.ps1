using namespace System.Collections.Generic
using namespace System.IO

$ProjectDir = Split-Path $PSScriptRoot -Parent

# Options configuring which textures get upscaled and which models to use.
class UpscaleOptions {
	# The upscale model to use on textures unless otherwise specified.
	[string] $DefaultModel

	# Maps texture names to their respective upscale models.
	# Special values:
	#	'none' - Texture will not be copied and upscaled.
	#	'manual' - Texture will be copied, but will be upscaled by hand.
	[Dictionary[string, string]] $TextureModels

	UpscaleOptions([string] $Json) {
		$raw_options = $Json | ConvertFrom-Json

		$this.DefaultModel = $raw_options.DefaultModel
		if (-not (IsValidFilename $this.DefaultModel)) {
			throw "DefaultModel must not be empty or contain invalid filename characters."
		}

		$this.TextureModels = [Dictionary[string, string]]::new()

		foreach ($group in $raw_options.TextureGroups) {
			if (-not (IsValidFilename $group.Model)) {
				throw "Texture group '$($group.Name)': 'Model' must not be empty or contain invalid filename characters."
			}

			foreach ($texture_name in $group.TextureNames) {
				$this.TextureModels[$texture_name] = $group.Model
			}
		}
	}
}


<#
.SYNOPSIS
Gets the options configuring what textures get upscaled and which models to use.
#>
function Get-UpscaleOptions {
	[CmdletBinding()]
	[OutputType([UpscaleOptions])]
	param()

	$upscale_options_path = Join-Path $ProjectDir 'upscale-options.json'
	Write-Host "Reading upscale options file: '${upscale_options_path}' ..."
	[UpscaleOptions]::new([File]::ReadAllText($upscale_options_path))
}

<#
.SYNOPSIS
Gets the parent directory where all texture files (and the texture manifest) are placed.
#>
function Get-TexturesDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path $ProjectDir 'textures/'
	Initialize-Directory $dir
	$dir
}

<#
.SYNOPSIS
Gets the directory where the original game textures are copied to.
#>
function Get-OriginalTexturesDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path (Get-TexturesDir) 'original/'
	Initialize-Directory $dir
	$dir
}

<#
.SYNOPSIS
Gets the directory where the upscaled textures are saved to.
#>
function Get-UpscaledTexturesDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path (Get-TexturesDir) 'upscaled/'
	Initialize-Directory $dir
	$dir
}

<#
.SYNOPSIS
Gets the directory where the matching texture files are copied to
when performing searches on the Jak 3 game textures directory.
#>
function Get-SearchResultsDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path (Get-TexturesDir) 'search-results/'
	Initialize-Directory $dir
	$dir
}

<#
.SYNOPSIS
Finds the OpenGOAL installation directory.
#>
function Find-OpenGoalInstallDir {
	[CmdletBinding()]
	[OutputType([string])]
	param()

	Write-Host 'Locating OpenGOAL installation directory ...'

	if (Test-Path -LiteralPath 'Env:OPENGOAL_DIR') {
		Write-Host 'Environment variable OPENGOAL_DIR is set.'
		$opengoal_dir = $env:OPENGOAL_DIR

		if (Test-Path -LiteralPath $opengoal_dir -PathType Container) {
			return $opengoal_dir
		}
		
		Write-Host "No installation exists at '${opengoal_dir}'."
	}
	else {
		Write-Host 'Environment variable OPENGOAL_DIR not set, searching common locations ...'

		$search_paths = @(
			(Join-Path $env:LOCALAPPDATA 'Programs/OpenGOAL/'),
			"C:/ProgramData/OpenGOAL/"
		)

		foreach ($search_path in $search_paths) {
			if (Test-Path -LiteralPath $search_path -PathType Container) {
				return $search_path
			}

			Write-Host "No installation found at '${search_path}'."
		}
	}

	throw "Failed to locate OpenGOAL installation directory."
}

<#
.SYNOPSIS
Finds the directory where OpenGOAL places textures extracted from the Jak 3 ISO.
#>
function Find-GameTexturesDir {
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]
		$OpenGoalDir
	)

	Write-Host "Searching for Jak 3 textures directory ..."

	$search_paths = @(
		(Join-Path $OpenGoalDir 'active/jak3/data/decompiler_out/jak3/textures/'),
		(Join-Path $OpenGoalDir 'data/decompiler_out/jak3/textures/')
	)

	foreach ($search_path in $search_paths) {
		if (Test-Path -LiteralPath $search_path -PathType Container) {
			Write-Host "Found Jak 3 textures at '${search_path}'."
			return $search_path
		}

		Write-Host "No Jak 3 textures at '${search_path}'."
	}

	throw "Failed to find Jak 3 textures directory."
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

	Write-Host "Creating directory '${Path}' ..."
	$null = New-Item $Path -ItemType Directory -ErrorAction Stop
}

<#
.SYNOPSIS
Deletes all items in a directory but leaves the directory itself.
#>
function Clear-Directory {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[string[]]
		$Path,

		# Filters preventing the matching items from being deleted.
		[string[]]
		$Exclude
	)

	process {
		foreach ($path_to_clean in $Path) {
			if (-not (Test-Path -LiteralPath $path_to_clean -PathType Container)) {
				continue
			}

			Write-Host "Cleaning directory '${path_to_clean}' ..."

			[string[]] $children = @(
				Get-ChildItem -LiteralPath $Path -Exclude $Exclude -ErrorAction Stop |
				Select-Object -ExpandProperty FullName -ErrorAction Stop
			)

			if ($children.Count -gt 0) {
				$null = Remove-Item -LiteralPath $children -Recurse -Force -ErrorAction Stop
			}
		}
	}
}

<#
.SYNOPSIS
Checks if a string is suitable as a filename.
#>
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
