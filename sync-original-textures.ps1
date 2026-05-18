#!/usr/bin/env pwsh

<#
.SYNOPSIS
Finds and copies the original Jak 3 game textures to `textures/original/`.

.DESCRIPTION
Finds and copies the original Jak 3 game textures to `textures/original/`.
Make sure you've decompiled the Jak 3 ISO using the OpenGOAL launcher or CLI.

The file `upscale-options.json` is used to exclude certain textures from being copied and upscaled
(such as animated textures), and to specify which upscale model to use for certain textures.
Textures can also be marked to be manually upscaled instead of using an AI model.
These are copied to `textures/original/manual/`.

Re-run this script after making changes to the upscale options file. It will copy any newly included textures,
delete ones that are newly excluded, and move textures accordingly if an upscale model has been changed.

A manifest of all textures copied will be written to `textures/manifest.txt`.
This makes it easy to spot changes to the texture pack using git.

.NOTES
Use the -WhatIf switch to do a dry run (generates the manifest without actually copying/deleting files.)

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
using namespace System.Diagnostics.CodeAnalysis
using namespace System.IO
using namespace System.Linq
using namespace System.Text

[CmdletBinding(SupportsShouldProcess)]
param(
	# The path to the OpenGOAL installation directory. If not supplied, the environment variable `OPENGOAL_DIR`
	# will be checked. If it isn't set, OpenGOAL will be searched for in common locations.
	[string]
	$OpenGoalDir,

	# If specified, deletes all existing textures in `textures/original/` and re-obtains them.
	# Otherwise, only the necessary textures will be copied.
	[switch]
	$Force
)

. (Join-Path $PSScriptRoot 'lib/utils.ps1')
. (Join-Path $PSScriptRoot 'lib/Texture.ps1')


function Main {
	[SuppressMessageAttribute('PSShouldProcess', '')]
	[CmdletBinding(SupportsShouldProcess)]
	param()
	
	if ([string]::IsNullOrEmpty($OpenGoalDir)) {
		$OpenGoalDir = Find-OpenGoalInstallDir
	}
	elseif (-not (Test-Path -LiteralPath $OpenGoalDir -PathType Container)) {
		throw "OpenGOAL directory '${OpenGoalDir}' (passed via -OpenGoalDir) does not exist."
	}
	else {
		$OpenGoalDir = Resolve-Path -LiteralPath $OpenGoalDir
	}

	Write-Host "OpenGOAL installation directory: ${OpenGoalDir}"

	$dest_dir = Get-OriginalTexturesDir
	$upscale_options = Read-UpscaleOptions

	if ($Force) {
		Clear-Directory $dest_dir
	}
	else {
		Sync-ExistingTexturesWithOptions $dest_dir $upscale_options
	}
	
	$src_dir = Find-GameTexturesDir $OpenGoalDir
	$texture_paths = @( Copy-OriginalTextures $src_dir $dest_dir $upscale_options )
	
	$manifest_path = Join-Path (Get-TexturesDir) 'manifest.txt'
	Write-Host "Saving texture manifest (total textures: $($texture_paths.Count)) ..."

	# Faster than Sort-Object and maintains the same order regardless of PS version and culture/locale.
	[Array]::Sort($texture_paths, [StringComparer]::Ordinal)

	# Use .NET directly to write without a BOM, since Windows PowerShell saves with BOMs
	# and PowerShell (Core) does not, causing git to falsely see the file as modified.
	[File]::WriteAllText(
		$manifest_path,
		[string]::Join([Environment]::NewLine, $texture_paths),
		[UTF8Encoding]::new($false)
	)
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

	Write-Host "Syncing existing original textures with upscale options ..."

	$files_to_delete = [List[FileInfo]]::new()
	$files_to_move = [List[Tuple[FileInfo, string]]]::new() # Source, Destination
	$model_dirs = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction Stop

	foreach ($model_dir in $model_dirs) {
		$current_model = $model_dir.Name
		$texture_files = Get-ChildItem -LiteralPath $model_dir.FullName -File -ErrorAction Stop

		foreach ($texture_file in $texture_files) {
			$texture_name = ($texture_file.BaseName -split '%')[1]

			if ([string]::IsNullOrWhiteSpace($texture_name)) {
				Write-Warning "Encountered unknown texture file: $($texture_file.FullName)"
				continue
			}

			$new_model = $Options.TextureModels[$texture_name]

			if ($null -eq $new_model) {
				$new_model = $Options.DefaultModel
			}

			if ($new_model -eq 'none') {
				$null = $files_to_delete.Add($texture_file)
			}
			elseif ($new_model -ne $current_model) {
				$dest_dir = Join-Path $Path $new_model
				Initialize-Directory $dest_dir
				$null = $files_to_move.Add([Tuple]::Create($texture_file, (Join-Path $dest_dir $texture_file.Name)))
			}
		}
	}

	if ($files_to_delete.Count -gt 0) {
		Write-Host "Removing $($files_to_delete.Count) texture(s) excluded from upscaling ..."

		foreach ($file in $files_to_delete) {
			if ($PSCmdlet.ShouldProcess($file, 'Remove File')) {
				$file.Delete()
			}
		}
	}

	if ($files_to_move.Count -gt 0) {
		Write-Host "Moving $($files_to_move.Count) texture(s) with changed upscale models ..."

		foreach ($src_dest in $files_to_move) {
			if ($PSCmdlet.ShouldProcess("Item: $($src_dest.Item1) Destination: $($src_dest.Item2)", 'Move File')) {
				$src_dest.Item1.MoveTo($src_dest.Item2)
			}
		}
	}

	# Remove empty directories.
	foreach ($model_dir in $model_dirs) {
		if (-not [Enumerable]::Any($model_dir.EnumerateFileSystemInfos())) {
			if ($PSCmdlet.ShouldProcess($model_dir, 'Remove Directory')) {
				$model_dir.Delete()
			}
		}
	}
}

<#
.SYNOPSIS
Copies the original Jak 3 game textures according to the upscale options.
#>
function Copy-OriginalTextures {
	[SuppressMessageAttribute('PSShouldProcess', '')]
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([string])]
	param(
		# The path to the extracted Jak 3 textures directory.
		[Parameter(Mandatory, Position = 0)]
		[string]
		$SourceDir,

		# The directory to copy the needed textures to.
		[Parameter(Mandatory, Position = 1)]
		[string]
		$DestinationDir,

		# The upscale options configuring which textures get copied and what models to use.
		[Parameter(Mandatory, Position = 2)]
		[UpscaleOptions]
		$Options
	)

	Write-Host "Indexing game textures in '${SourceDir}' ..."

	$texture_files = Get-ChildItem -LiteralPath $SourceDir -Filter '*.png' -File -Recurse -ErrorAction Stop
	$textures_by_name = [Dictionary[string, Texture]]::new()

	foreach ($file in $texture_files) {
		$name = $file.BaseName

		if ($textures_by_name.ContainsKey($name)) {
			$textures_by_name[$name].AddFile($file)
			continue
		}

		$model = $Options.TextureModels[$name]

		if ($null -eq $model) {
			$model = $Options.DefaultModel
		}
		
		if ($model -ne 'none') {
			$textures_by_name[$name] = [Texture]::new($file, $model)
		}
	}

	Write-Host "Copying game textures to '${DestinationDir}' ..."

	foreach ($texture in $textures_by_name.Values) {
		$texture.CopyTo($DestinationDir, $WhatIfPreference)
	}
}


Main
