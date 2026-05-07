#!/usr/bin/env pwsh

<#
.SYNOPSIS
Finds and copies the original Jak 3 textures extracted from the ISO via OpenGOAL to `textures/original/`.
Make sure you've decompiled Jak 3 using the launcher or the CLI.

The file `/upscale-options.json` is used to exclude certain textures from being copied and upscaled
(such as animated textures), and to specify which upscale model to use for certain textures.

Re-run this script after making changes to the upscale options file. It will copy any newly included textures,
delete ones that are newly excluded, and move textures accordingly if their upscale model has been changed.

A manifest of all textures copied will be written to `textures/original/manifest.txt`.
This makes it easy to spot changes to the texture pack using git.

.NOTES
Use the -WhatIf switch to do a dry run (generates the manifest without actually copying/deleting files.)
Use the -Verbose switch to see information about what the script is doing.

If the same texture occurs multiple times in the game files, it will be de-duplicated so it only needs
to be copied and upscaled once by placing a single copy in the `_all` texture directory.
Some textures have the same names but different file hashes, these will not be de-duplicated just to be safe.
See: https://github.com/open-goal/jak-project/pull/3234

Textures will be grouped in directories named after their respective upscale model.
The directory structure will be flattened within these directories since batch upscaling doesn't support recursion.
This is done by encoding the heirarchy within the filenames themselves, with a `%` representing a path separator.

For example: Texture `<Jak 3 Texture Path>/arenacst-pris/bam-hairhilite.png` will be copied to
`textures/original/<Upscale Model>/arenacst-pris%bam-hairhilite.png`.
#>

using namespace System.Collections.Generic

[CmdletBinding(SupportsShouldProcess)]
param(
	# The path to the OpenGOAL installation directory. If not supplied it will be automatically searched for,
	# in order, at the following locations:
	#	C:\Users\<username>\AppData\Local\Programs\OpenGOAL
	#	C:\ProgramData\OpenGOAL
	[string]
	$OpenGoalDir,

	# If specified, deletes all existing textures in `textures/original/` and re-obtains them.
	# Otherwise, only the necessary textures will be copied.
	[switch]
	$Force
)

. (Join-Path $PSScriptRoot 'lib/utils.ps1')

# Handles copying and de-duplication for textures found in the game files.
class Texture {
	# The name of the model used to upscale this texture.
	[string] $UpscaleModel

	# The full paths to all copies of this texture in the game files.
	[List[string]] $Paths

	# The set of unique file hashes of this texture. Used for de-duplication.
    [HashSet[string]] $Hashes

    Texture([string] $Path, [string] $UpscaleModel) {
        $this.Hashes = [HashSet[string]]::new()
        $this.Paths = [List[string]]::new()
		$this.AddPath($Path)
		$this.UpscaleModel = $UpscaleModel
    }

	# Adds a full file path to an occurence of this texture in the Jak 3 game textures directory.
	# The file hash will be computed and add
	[void] AddPath([string] $Path) {
		$this.Hashes.Add((Get-FileHash -LiteralPath $Path -Algorithm SHA1).Hash)
		$this.Paths.Add($Path)
	}

	# Copies all occurences of this texture (or only one if it can be de-duplicated) in the source directory
	# to the destination directory. Returns the copied texture paths relative to the destination
	# for writing to the texture manifest file.
	[string[]] CopyTexture([string] $SourceDir, [string] $DestinationDir, [bool] $WhatIfPreference) {
		$DestinationDir = Join-Path $DestinationDir $this.UpscaleModel
		Initialize-Directory $DestinationDir -WhatIf:$WhatIfPreference

		$should_deduplicate = ($this.Hashes.Count -le 1) -and ($this.Paths.Count -gt 1)

		$dest_paths = foreach ($src_path in $this.Paths) {
			$relative_path = Get-PathWithoutPrefix $src_path -Prefix $SourceDir

			$subdir = if ($should_deduplicate) { '_all' } else { Split-Path $relative_path -Parent }
			$filename = Split-Path $relative_path -Leaf
			$dest_path = Join-Path $DestinationDir "${subdir}%${filename}"

			if (-not (Test-Path -LiteralPath $dest_path -PathType Leaf)) {
				Copy-Item -LiteralPath $src_path -Destination $dest_path -ErrorAction Stop -WhatIf:$WhatIfPreference
			}

			"$($this.UpscaleModel)/${subdir}%${filename}"
			if ($should_deduplicate) { break }
		}

		return $dest_paths
	}
}


function Main {
	[CmdletBinding(SupportsShouldProcess)]
	param()
	
	if ([String]::IsNullOrWhiteSpace($OpenGoalDir)) {
		$OpenGoalDir = Get-OpenGoalInstallDir -Verbose:$VerbosePreference
	}
	elseif (-not (Test-Path -LiteralPath $OpenGoalDir -PathType Container)) {
		throw "OpenGOAL installation directory '${OpenGoalDir}' does not exist."
	}

	$dest_dir = Get-OriginalTexturesDir -Verbose:$VerbosePreference
	$upscale_options = Get-UpscaleOptions -Verbose:$VerbosePreference

	if ($Force) {
		Clear-Directory $dest_dir -Verbose:$VerbosePreference
	}
	else {
		Sync-ExistingTexturesWithOptions $dest_dir $upscale_options -Verbose:$VerbosePreference
	}
	
	$src_dir = Get-Jak3TexturesDir $OpenGoalDir -Verbose:$VerbosePreference
	$texture_paths = Copy-OriginalTextures $src_dir $dest_dir $upscale_options -Verbose:$VerbosePreference
	
	$manifest_path = Join-Path (Get-TexturesDir -Verbose:$VerbosePreference) 'manifest.txt'
	Write-Verbose "Saving texture manifest to '${manifest_path}' ..."
	$texture_paths | Sort-Object -Culture 'en-US' | Set-Content -LiteralPath $manifest_path -Encoding UTF8 -WhatIf:$false
}

function Sync-ExistingTexturesWithOptions {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]
		$Path,

		[Parameter(Mandatory, Position = 1)]
		[UpscaleOptions]
		$Options
	)

	# TODO
}

<#
.SYNOPSIS
Copies the needed textures from the Jak 3 game files to `textures/original/`.
#>
function Copy-OriginalTextures {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		# The path to the extracted Jak 3 textures directory.
		[Parameter(Mandatory, Position = 0)]
		[string]
		$SourceDir,

		# The directory to copy the needed textures to.
		[Parameter(Mandatory, Position = 1)]
		[string]
		$DestinationDir,

		# The options configuring which textures get copied and what upscale models to use.
		[Parameter(Mandatory, Position = 2)]
		[UpscaleOptions]
		$Options
	)

	Write-Verbose "Copying textures from '${SourceDir}' to '${DestinationDir}' ..."

	$texture_paths = Get-ChildItem -LiteralPath $SourceDir -Filter '*.png' -File -Recurse -ErrorAction Stop
	$textures_by_name = [Dictionary[string, Texture]]::new()

	foreach ($path in $texture_paths) {
		$name = $path.BaseName

		if ($textures_by_name.ContainsKey($name)) {
			$textures_by_name[$name].AddPath($path.FullName)
			continue
		}

		$model = $Options.TextureModels[$name]

		if ($null -eq $model) {
			$model = $Options.DefaultModel
		}
		
		if ($model -ne 'none') {
			$textures_by_name[$name] = [Texture]::new($path.FullName, $model)
		}
	}

	foreach ($texture in $textures_by_name.Values) {
		$texture.CopyTexture($SourceDir, $DestinationDir, $WhatIfPreference)
	}
}


Main -Verbose:$VerbosePreference
