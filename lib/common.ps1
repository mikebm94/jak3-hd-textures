using namespace System.IO

$ProjectDir = Split-Path $PSScriptRoot -Parent


<#
.SYNOPSIS
Gets the directory where build artifacts and temporary files are placed
when upscaling textures and building the texture pack archive.
#>
function Get-BuildDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path $ProjectDir 'build/'
	Initialize-Directory $dir
	$dir
}


<#
.SYNOPSIS
Gets the directory where the final output files are placed for archival when building the texture pack archive.
#>
function Get-PackageBuildDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path (Get-BuildDir) 'package/'
	Initialize-Directory $dir
	$dir
}


<#
.SYNOPSIS
Gets the directory where the necessary original textures and input-override files
are placed when running the upscale workflows.
#>
function Get-WorkflowsBuildDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path (Get-BuildDir) 'workflows/'
	Initialize-Directory $dir
	$dir
}


<#
.SYNOPSIS
Gets the directory where chaiNNer chain files are placed for use in upscale workflows.
#>
function Get-ChainsDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path $ProjectDir 'chains/'
	Initialize-Directory $dir
	$dir
}


<#
.SYNOPSIS
Gets the directory where upscale models are downloaded to for usage.
#>
function Get-ModelsDir {
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param()

	$dir = Join-Path $ProjectDir 'models/'
	Initialize-Directory $dir
	$dir
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
Finds the directory where textures extracted from the Jak 3 ISO are found.

.DESCRIPTION
Finds the directory where textures extracted from the Jak 3 ISO are found.

Allows providing an OpenGOAL installation path, a custom path containing the textures,
or if neither are provided, automatically searching for an OpenGOAL installation path.
The automatic search first checks environment variables, then a list of common locations.

Supported environment variables for setting OpenGOAL/custom directory:
	OPENGOAL_DIR - To set the OpenGOAL installation path (takes priority).
	JAK3_TEX_DIR - To set a custom directory containing the textures.
#>
function Find-ExtractedTexturesDir {
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[string]
		$OpenGoalDir,

		[string]
		$Jak3TexDir
	)

	if ($OpenGoalDir -or ($Env:OPENGOAL_DIR -and -not $Jak3TexDir)) {
		if (-not $OpenGoalDir) {
			$OpenGoalDir = $Env:OPENGOAL_DIR
		}

		if (Test-Path -LiteralPath $OpenGoalDir -PathType Container) {
			Write-Host "Using OpenGOAL installation path: ${OpenGoalDir}"
			return Find-OpenGoalTexturesDir $OpenGoalDir
		}

		throw "The set OpenGOAL installation path does not exist: ${OpenGoalDir}"
	}
	elseif ($Jak3TexDir -or $Env:JAK3_TEX_DIR) {
		if (-not $Jak3TexDir) {
			$Jak3TexDir = $Env:JAK3_TEX_DIR
		}

		if (Test-Path -LiteralPath $Jak3TexDir -PathType Container) {
			Write-Host "Using custom Jak 3 textures path: ${Jak3TexDir}"
			return $Jak3TexDir
		}

		throw "The set Jak 3 textures path does not exist: ${Jak3TexDir}"
	}

	$OpenGoalDir = Find-OpenGoalInstallDir
	Write-Host "Using OpenGOAL installation path: ${OpenGoalDir}"
	return Find-OpenGoalTexturesDir $OpenGoalDir
}




<#
.SYNOPSIS
Finds the OpenGOAL installation directory.

.DESCRIPTION
Attempts to find the OpenGOAL installation directory at the following locations (in order):
	Windows
		C:\Users\<username>\AppData\Local\Programs\OpenGOAL
		C:\ProgramData\OpenGOAL
#>
function Find-OpenGoalInstallDir {
	[CmdletBinding()]
	[OutputType([string])]
	param()

	$search_paths = @(
		(Join-Path $env:LOCALAPPDATA 'Programs/OpenGOAL/'),
		'C:/ProgramData/OpenGOAL/'
	)

	foreach ($search_path in $search_paths) {
		if (Test-Path -LiteralPath $search_path -PathType Container) {
			return $search_path
		}
	}

	throw (
		'Failed to find extracted Jak 3 textures: ' +
		'No paths were set, and no OpenGOAL installation could be found.'
	)
}


<#
.SYNOPSIS
Finds the directory where OpenGOAL places textures extracted from the Jak 3 ISO.
#>
function Find-OpenGoalTexturesDir {
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]
		$OpenGoalDir
	)

	$search_paths = @(
		(Join-Path $OpenGoalDir 'active/jak3/data/decompiler_out/jak3/textures/'),
		(Join-Path $OpenGoalDir 'data/decompiler_out/jak3/textures/')
	)

	foreach ($search_path in $search_paths) {
		if (Test-Path -LiteralPath $search_path -PathType Container) {
			return $search_path
		}
	}

	throw 'Failed to find Jak 3 game textures in OpenGOAL installation path.'
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

	if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
		$null = New-Item $Path -ItemType Directory -ErrorAction Stop
	}
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
Gets the sub-directory and name components of a texture filename.

.DESCRIPTION
Splits a flattened texture filename into sub-directory and name components.
In the Jak 3 game files, textures are organized into sub-directories. To simplify processing, the sub-directory
is encoded into filenames using the format "{subdir}__{name}.png" when they are pulled in by the scripts.

.OUTPUTS
Outputs a `hashtable` with a `SubDirectory` item containing the textures sub-directory name,
and a `Name` item containing the textures filename without the file extension.
If the filename is not in the correct format, nothing is returned and a warning is emmitted.
#>
function Split-TextureFileName {
	[CmdletBinding()]
	[OutputType([hashtable])]
	param(
		# The FileInfo object for the texture file.
		[Parameter(Mandatory, Position = 0)]
		[FileInfo]
		$TextureFile
	)

	$components = $TextureFile.BaseName -split '__'
	
	if ([string]::IsNullOrWhiteSpace($components[0]) -or [string]::IsNullOrWhiteSpace($components[1])) {
		Write-Warning "Encountered unknown texture file: $( $TextureFile.FullName )"
		return $null
	}

	@{
		SubDirectory = $components[0]
		Name = $components[1]
	}
}


<#
.SYNOPSIS
Checks if a string is suitable as a filename.
#>
function IsValidFilename([string] $Name) {
	if ([string]::IsNullOrWhiteSpace($Name) -or $Name.IndexOfAny([Path]::GetInvalidFileNameChars()) -ne -1) {
		return $false
	}

	$true
}
