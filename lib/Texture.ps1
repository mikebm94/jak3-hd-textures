using namespace System.Collections.Generic
using namespace System.IO

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
				if ($WhatIfPreference) {
					Write-Host (
						'What If: Performing the operation "Copy File" on target "Item: {0} Destination: {1}".' `
						-f $file.FullName, $dest_path
					)
				}
				else {
					$null = $file.CopyTo($dest_path)
				}
			}

			"$($this.UpscaleModel)/${new_filename}"
			if ($should_deduplicate) { break }
		}

		return $manifest_entries
	}
}
