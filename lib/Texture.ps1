using namespace System.Collections.Generic
using namespace System.IO

# Handles copying and de-duplication for textures found in the game files.
class Texture {
	# The name of the workflow used to upscale this texture.
	# Leave empty if the texture is a search result.
	[string] $UpscaleWorkflow

	# All files found under this textures name.
	[List[FileInfo]] $Files

	# All unique hashes of the files found under this textures name. Used for de-duplication.
    [HashSet[string]] $Hashes


    Texture([FileInfo] $file, [string] $upscale_workflow) {
		$this.Files = [List[FileInfo]]::new()
        $this.Hashes = [HashSet[string]]::new()
		$this.AddFile($file)
		$this.UpscaleWorkflow = $upscale_workflow
    }

	# Adds a file that was found under this textures name, computes its hash and stores it.
	[void] AddFile([FileInfo] $file) {
		$this.Files.Add($file)
		$this.Hashes.Add((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA1).Hash)
	}

	# Copies all occurences of this texture (or only one if it can be de-duplicated) to the destination directory.
	# Returns the resulting texture filepaths relative to the destination directory.
	# If the texture is a search result, only the files actually copied are returned.
	[string[]] CopyTo([string] $dest_dir, [bool] $what_if_preference) {
		if (-not [string]::IsNullOrEmpty($this.UpscaleWorkflow)) {
			$dest_dir = Join-Path $dest_dir $this.UpscaleWorkflow
		}

		Initialize-Directory $dest_dir -WhatIf:$what_if_preference

		$should_deduplicate = ($this.Hashes.Count -le 1) -and ($this.Files.Count -gt 1)

		$filepaths = foreach ($file in $this.Files) {
			$subdir_name = if ($should_deduplicate) { '_all' } else { $file.Directory.BaseName }
			$new_filename = "${subdir_name}__$($file.Name)"
			$dest_path = Join-Path $dest_dir $new_filename
			$was_copied = $false

			if (-not (Test-Path -LiteralPath $dest_path -PathType Leaf)) {
				if ($what_if_preference) {
					Write-Host (
						'What If: Performing the operation "Copy File" on target "Item: {0} Destination: {1}".' `
						-f $file.FullName, $dest_path
					)
				}
				else {
					$null = $file.CopyTo($dest_path)
					$was_copied = $true
				}
			}

			if (-not [string]::IsNullOrEmpty($this.UpscaleWorkflow)) {
				"$($this.UpscaleWorkflow)/${new_filename}"
			}
			elseif ($was_copied) {
				$new_filename
			}

			if ($should_deduplicate) { break }
		}

		return $filepaths
	}
}
