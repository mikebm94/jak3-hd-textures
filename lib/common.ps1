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
Finds the OpenGOAL installation directory.

The environment variable `OPENGOAL_DIR` is checked first.
If it isn't set, OpenGOAL will be searched for, in order, at the following locations:
	C:\Users\<username>\AppData\Local\Programs\OpenGOAL
	C:\ProgramData\OpenGOAL
#>
function Find-OpenGoalInstallDir {
	[CmdletBinding()]
	[OutputType([string])]
	param()

	if (Test-Path -LiteralPath 'Env:OPENGOAL_DIR') {
		$opengoal_dir = $env:OPENGOAL_DIR

		if (Test-Path -LiteralPath $opengoal_dir -PathType Container) {
			return $opengoal_dir
		}
		
		throw "OpenGOAL directory '${opengoal_dir}' (set by OPENGOAL_DIR environment variable) does not exist."
	}

	$search_paths = @(
		(Join-Path $env:LOCALAPPDATA 'Programs/OpenGOAL/'),
		'C:/ProgramData/OpenGOAL/'
	)

	foreach ($search_path in $search_paths) {
		if (Test-Path -LiteralPath $search_path -PathType Container) {
			return $search_path
		}
	}

	throw 'Failed to find OpenGOAL directory.'
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

	$search_paths = @(
		(Join-Path $OpenGoalDir 'active/jak3/data/decompiler_out/jak3/textures/'),
		(Join-Path $OpenGoalDir 'data/decompiler_out/jak3/textures/')
	)

	foreach ($search_path in $search_paths) {
		if (Test-Path -LiteralPath $search_path -PathType Container) {
			return $search_path
		}
	}

	throw 'Failed to find Jak 3 game textures in OpenGOAL directory.'
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
function IsValidFilename {
	[OutputType([bool])]
	param(
		[Parameter(Position = 0)]
		[string]
		$Name
	)

	if ([string]::IsNullOrWhiteSpace($Name) -or $Name.IndexOfAny([Path]::GetInvalidFileNameChars()) -ne -1) {
		return $false
	}

	$true
}
