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
using namespace System.Diagnostics.CodeAnalysis
using namespace System.IO
using namespace System.Text

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

	# All files found under this textures name.
	[List[FileInfo]] $Files

	# All unique hashes of the files found under this textures name. Used for de-duplication.
    [HashSet[string]] $Hashes


    Texture([FileInfo] $File, [string] $UpscaleModel) {
		$this.Files = [List[FileInfo]]::new()
        $this.Hashes = [HashSet[string]]::new()
		$this.AddFile($File)
		$this.UpscaleModel = $UpscaleModel
    }

	# Adds a file that was found under this textures name, computes its hash and stores it.
	[void] AddFile([FileInfo] $File) {
		$this.Files.Add($File)
		$this.Hashes.Add((Get-FileHash -LiteralPath $File.FullName -Algorithm SHA1).Hash)
	}

	# Copies all occurences of this texture (or only one if it can be de-duplicated) to the destination directory.
	# Returns the copied texture paths relative to the destination for writing to the texture manifest file.
	[string[]] CopyTo([string] $DestinationDir, [bool] $WhatIfPreference) {
		$DestinationDir = Join-Path $DestinationDir $this.UpscaleModel
		Initialize-Directory $DestinationDir -WhatIf:$WhatIfPreference

		$should_deduplicate = ($this.Hashes.Count -le 1) -and ($this.Files.Count -gt 1)

		$manifest_entries = foreach ($file in $this.Files) {
			$subdir_name = if ($should_deduplicate) { '_all' } else { $file.Directory.BaseName }
			$new_filename = "${subdir_name}%$($file.Name)"
			$dest_path = Join-Path $DestinationDir $new_filename

			if (-not (Test-Path -LiteralPath $dest_path -PathType Leaf)) {
				Copy-Item -LiteralPath $file.FullName -Destination $dest_path -ErrorAction Stop -WhatIf:$WhatIfPreference
			}

			"$($this.UpscaleModel)/${new_filename}"
			if ($should_deduplicate) { break }
		}

		return $manifest_entries
	}
}


function Main {
	[SuppressMessageAttribute("PSShouldProcess", "")]
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
	
	$src_dir = Get-GameTexturesDir $OpenGoalDir -Verbose:$VerbosePreference
	$texture_paths = Copy-OriginalTextures $src_dir $dest_dir $upscale_options -Verbose:$VerbosePreference
	
	$manifest_path = Join-Path (Get-TexturesDir -Verbose:$VerbosePreference) 'manifest.txt'
	Write-Verbose "Saving texture manifest to '${manifest_path}' ..."

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

	# TODO
}

<#
.SYNOPSIS
Copies the original Jak 3 game textures according to the upscale options.
#>
function Copy-OriginalTextures {
	[SuppressMessageAttribute("PSShouldProcess", "")]
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

	Write-Verbose "Indexing game textures in '${SourceDir}' ..."

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

	Write-Verbose "Copying game textures to '${DestinationDir}' ..."

	foreach ($texture in $textures_by_name.Values) {
		$texture.CopyTo($DestinationDir, $WhatIfPreference)
	}
}


Main -Verbose:$VerbosePreference
