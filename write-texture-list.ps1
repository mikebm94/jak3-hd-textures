#!/usr/bin/env pwsh

<#
.SYNOPSIS
Writes a sorted list of unique texture names found in the given directory.

.DESCRIPTION
Writes a sorted list of unique texture names found in the given directory.
If no directory is given, `textures/search-results/` will be used.
The list can then be added to a texture group in `upscale-options.json`

The directory is searched non-recursively for texture files, the unique names of the textures are then sorted
and written to `texture-list.json` within the directory.

When updating a texture group instead of creating a new one, use the  `-MergeWithGroup` parameter
to merge texture names from an existing group into the resulting list.
#>


using namespace System.Collections.Generic
using namespace System.Linq

[CmdletBinding(SupportsShouldProcess)]
param(
	# The directory containing the textures used to generate the texture list.
	[Parameter(Position = 0)]
	[string]
	$Directory,

	# The name of the texture group to merge the texture names with.
	[string]
	$MergeWithGroup
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/UpscaleOptions.ps1')


if (-not $Directory) {
	$Directory = Get-SearchResultsDir
}
elseif (-not (Test-Path -Path $Directory -PathType Container)) {
	throw "Directory does not exist: ${Directory}"
}

$upscale_options = Read-UpscaleOptions
$target_group = $upscale_options.TextureGroups[$MergeWithGroup]
if ($MergeWithGroup -and -not $target_group) {
	throw "Cannot merge list with texture group '${MergeWithGroup}': Group does not exist."
}

Write-Host "Generating texture list from directory '${Directory}' ..."

$texture_files = Get-ChildItem -Path $Directory -Filter '*.png' -File -ErrorAction Stop
$texture_names = [HashSet[string]]::new()

foreach ($file in $texture_files) {
	$split_filename = Split-TextureFileName $file
	$texture_name = if ($split_filename) {
		$split_filename.Name
	} else {
		$file.BaseName
	}

	$null = $texture_names.Add($texture_name)
}

if ($target_group) {
	Write-Host "Merging list with texture group '$( $target_group.Name )' ..."
	foreach ($texture_name in $target_group.TextureNames) {
		$null = $texture_names.Add($texture_name)
	}
}

$target_file = Join-Path $Directory 'texture-list.json'
Write-Host "Writing $( $texture_names.Count ) texture name(s) to '${target_file}' ..."

# Use ordinal sorting to prevent different versions of PowerShell from sorting the list differently.
$texture_names = [Enumerable]::ToArray($texture_names)
[Array]::Sort($texture_names, [StringComparer]::Ordinal)

$texture_names | ConvertTo-Json | Set-Content -Path $target_file
