#!/usr/bin/env pwsh

<#
.SYNOPSIS
Searches for matching files in the Jak 3 textures, or creates a list of texture names from the search results.

.DESCRIPTION
Searches for matching files in the Jak 3 textures, or creates a list of texture names from the search results.

The script is meant to aid in creating texture groups in `upscale-options.json`, or to help visually inspect
the textures already in a group. The matching textures are copied to `textures/search-results/`.

The primary (but optional) method of searching is by texture name using:
	Wildcard patterns using `-Filters`.
	Regular expression patterns using `-Patterns`.

Only one of the patterns in either of those parameters needs to match to return the result.
Results can be further refined by:
	Filtering by texture group using `-InGroups`, `-IsGrouped` or `-NotGrouped` (mutually exclusive).
	Filtering by texture dimensions using `-Width` and/or `-Height`.

You can delete any files you don't want to include in the final texture list from `textures/search-results/`.
Passing the `-WriteTextureList` parameter writes a sorted list of the unique texture names
to `textures/search-results/texture-list.json`.

Pass `-CombineWithGroup <group name>` to merge the texture names from an existing texture group
with the names in the search results when writing the texture list. 

.NOTES
For help with syntax for the `-Filters` parameter, see:
https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_wildcards

For help with syntax for the `-Patterns` parameter, see:
https://learn.microsoft.com/en-us/dotnet/standard/base-types/regular-expressions

.EXAMPLE
PS> ./search-textures.ps1 -Filters '*iris*', '*pupil*' -Patterns '\beye(?!brow)(?!lid)' -NotGrouped

.EXAMPLE
PS> ./search-textures.ps1 -InGroups 'Eye' -Width '>64' -Clean

.EXAMPLE
PS> ./search-textures.ps1 -WriteTextureList -MergeWithGroup 'Eye'
#>


using namespace System.Diagnostics.CodeAnalysis
using namespace System.Collections.Generic
using namespace System.IO

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Search')]
param(
	# Generates a list of all unique texture names of the texture files in `textures/search-results/`
	# and writes them to `textures/search-results/texture-list.json`.
	[Parameter(ParameterSetName = 'WriteTextureList', Mandatory)]
	[switch]
	$WriteTextureList,

	# When writing the texture list, combines it with the list of textures in the specified texture group.
	# Use when adding the list to a texture group instead of creating a new group.
	[Parameter(ParameterSetName = 'WriteTextureList')]
	[string]
	$MergeWithGroup,

	# The wildcard patterns to match against texture names. (Do not include the file extension.)
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string[]]
	$Filters,

	# The regex patterns to match against texture names. (Do not include the file extension.)
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string[]]
	$Patterns,

	# Excludes textures that don't belong to any of the provided texture groups.
	[Parameter(ParameterSetName = 'SearchInGroups', Mandatory)]
	[string[]]
	$InGroups,

	# Excludes textures that don't belong to any texture group.
	[Parameter(ParameterSetName = 'SearchIsGrouped', Mandatory)]
	[switch]
	$IsGrouped,

	# Excludes textures that belong to any texture group.
	[Parameter(ParameterSetName = 'SearchNotGrouped', Mandatory)]
	[switch]
	$NotGrouped,

	# Filters results by texture width in pixels by exact width, by comparison, or by a range (inclusive).
	# To filter by comparison, use one of these operators before the width:
	#     '<'  (less than)
	#     '<=' (less than or equal)
	#     '>'  (greater than)
	#     '>=' (greater than or equal)
	# To filter by a range, use a dash between the two widths.
	#
	# Example: '<=128' or '32-64'
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[ValidatePattern('^(<|<=|>=|>)?\d+$|^\d+-\d+$')]
	[string]
	$Width,

	# Filters results by texture height in pixels by exact height, by comparison, or by a range (inclusive).
	# To filter by comparison, use one of these operators before the height:
	#     '<'  (less than)
	#     '<=' (less than or equal)
	#     '>'  (greater than)
	#     '>=' (greater than or equal)
	# To filter by a range, use a dash between the two heights.
	#
	# Example: '<=128' or '32-64'
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[ValidatePattern('^(<|<=|>=|>)?\d+$|^\d+-\d+$')]
	[string]
	$Height,

	# Includes search results that don't meet the minimum texture size set by `MinimumTextureSize`
	# in `upscale-options.json`. The `-Width` and `-Height` parameters will still apply.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[switch]
	$IncludeUndersized,

	# Deletes all files in `textures/search-results/` before performing the search.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[switch]
	$Clean,

	# The path to an OpenGOAL installation directory. Used to find textures extracted from the Jak 3 ISO.
	#
	# If neither `-OpenGoalDir` nor `-Jak3TexDir` are set, first the environment variable `OPENGOAL_DIR`
	# is checked, then `JAK3_TEX_DIR`, then an automatic search for an OpenGOAL installation is performed.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string]
	$OpenGoalDir,

	# The path to the textures extracted from the Jak 3 ISO.
	#
	# If neither `-OpenGoalDir` nor `-Jak3TexDir` are set, first the environment variable `OPENGOAL_DIR`
	# is checked, then `JAK3_TEX_DIR`, then an automatic search for an OpenGOAL installation is performed.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string]
	$Jak3TexDir
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/Texture.ps1')
. (Join-Path $PSScriptRoot 'lib/UpscaleOptions.ps1')


# Parses the `Width` and `Height` parameters into an object used to filter textures by their dimensions.
class DimensionFilter {
	[int[]] $Widths
	[int[]] $Heights
	[scriptblock] $CheckWidth = { $true }
	[scriptblock] $CheckHeight = { $true }

	DimensionFilter([string] $width_filter, [string] $height_filter) {
		$op_map = @{
			''   = { param([int]$a, [int[]]$b) $a -eq $b[0] }
			'<'  = { param([int]$a, [int[]]$b) $a -lt $b[0] }
			'<=' = { param([int]$a, [int[]]$b) $a -le $b[0] }
			'>'  = { param([int]$a, [int[]]$b) $a -gt $b[0] }
			'>=' = { param([int]$a, [int[]]$b) $a -ge $b[0] }
		}

		if ($width_filter -match '^\d+-\d+$') {
			# Filter by range.
			$this.Widths = $width_filter -split '-'
			[Array]::Sort($this.Widths)
			$this.CheckWidth = { param([int]$a, [int[]]$b) ($a -ge $b[0]) -and ($a -le $b[1]) }
		}
		elseif ($width_filter) {
			# Filter by comparison.
			$this.Widths = $width_filter -replace '^[<>]=?'
			$this.CheckWidth = $op_map[$width_filter -replace '\d+$']
		}

		if ($height_filter -match '^\d+-\d+$') {
			# Filter by range.
			$this.Heights = $height_filter -split '-'
			[Array]::Sort($this.Heights)
			$this.CheckHeight = { param([int]$a, [int[]]$b) ($a -ge $b[0]) -and ($a -le $b[1]) }
		}
		elseif ($height_filter) {
			# Filter by comparison.
			$this.Heights = $height_filter -replace '^[<>]=?'
			$this.CheckHeight = $op_map[$height_filter -replace '\d+$']
		}
	}

	[bool] CheckDimensions([int] $texture_width, [int] $texture_height) {
		return (
			(& $this.CheckWidth $texture_width $this.Widths) -and
			(& $this.CheckHeight $texture_height $this.Heights)
		)
	}
}


function Main {
	[CmdletBinding(SupportsShouldProcess)]
	param()

	$upscale_options = Read-UpscaleOptions
	$results_dir = Get-SearchResultsDir

	if ($WriteTextureList) {
		Write-TextureList -ResultsDir $results_dir -UpscaleOptions $upscale_options
		return
	}

	if ($Clean) {
		Clear-Directory $results_dir
	}

	$any_criteria =
		($Filters.Count -gt 0) -or ($Patterns.Count -gt 0) -or
		($InGroups.Count -gt 0) -or $IsGrouped -or $NotGrouped -or
		$Width -or $Height

	if (-not $any_criteria) {
		Write-Host "No search criteria provided."
		return
	}

	# Check if an invalid group name was passed to -InGroups.
	foreach ($group in $InGroups) {
		if (-not $upscale_options.TextureGroups.ContainsKey($group)) {
			throw "Parameter 'InGroups': The TextureGroup '${group}' does not exist."
		}
	}

	$search_dir = Find-ExtractedTexturesDir -OpenGoalDir $OpenGoalDir -Jak3TexDir $Jak3TexDir

	$search_params = @{
		SearchDir = $search_dir
		ResultsDir = $results_dir
		UpscaleOptions = $upscale_options
		DimensionFilter = if ($Width -or $Height) { [DimensionFilter]::new($Width, $Height) }
	}

	Search-Textures @search_params
}


function Search-Textures {
	[SuppressMessageAttribute('PSShouldProcess', '')]
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory)]
		[string]
		$SearchDir,

		[Parameter(Mandatory)]
		[string]
		$ResultsDir,

		[Parameter(Mandatory)]
		[UpscaleOptions]
		$UpscaleOptions,

		[DimensionFilter]
		$DimensionFilter
	)

	Write-Host "Searching textures in '${SearchDir}' ..."

	$texture_files = Get-ChildItem -LiteralPath $SearchDir -Filter '*.png' -File -Recurse -ErrorAction Stop
	$min_texture_size = $UpscaleOptions.MinimumTextureSize

	# Use `Texture` objects grouped by texture name to de-duplicate the results using their file hashes.
	# Also handles encoding the sub-directory into the filenames when copying to the result directory.
	$results = [Dictionary[string, Texture]]::new()

	# Get results.
	foreach ($texture_file in $texture_files) {
		$texture_name = $texture_file.BaseName

		# First do group-related filtering before checking the various filters, patterns and dimensions.
		if ($NotGrouped -and $null -ne $UpscaleOptions.TextureGroupMap[$texture_name]) {
			# It's in a group when it shouldn't be.
			continue
		}
		elseif ($IsGrouped -and $null -eq $UpscaleOptions.TextureGroupMap[$texture_name]) {
			# It's not in a group when it should be.
			continue
		}
		elseif ($InGroups -and -not $InGroups.Contains($UpscaleOptions.TextureGroupMap[$texture_name].Name)) {
			# It's not in the right group.
			continue
		}

		# Then check if the name matches any one of the wildcard/regex patterns.
		if (-not (Test-TextureName $texture_name)) {
			continue
		}

		# Finally, the most expensive check, checking if the dimensions match the width and/or height filters.
		if ($DimensionFilter) {
			$size = Get-TextureSize $texture_file.FullName

			if ($min_texture_size -gt 0 -and -not $IncludeUndersized) {
				if ($size.Width -lt $min_texture_size -or $size.Height -lt $min_texture_size) {
					continue
				}
			}

			if (-not $DimensionFilter.CheckDimensions($size.Width, $size.Height)) {
				continue
			}
		}

		# Store the result.
		if ($results.ContainsKey($texture_name)) {
			$results[$texture_name].AddFile($texture_file)
		}
		else {
			$results[$texture_name] = [Texture]::new($texture_file, '')
		}
	}

	# Copy results.
	$files_matched = 0
	$files_copied = 0
	$unique_names = $results.Keys.Count

	foreach ($result in $results.Values) {
		$files_matched += $result.Files.Count
		$files_copied += $result.CopyTo($ResultsDir, $WhatIfPreference)
	}

	Write-Host "Unique texture names : ${unique_names}"
	Write-Host "Textures matched     : ${files_matched}"
	Write-Host "Textures copied      : ${files_copied}"
	Write-Host "Results copied to    : ${ResultsDir}"
}


<#
.SYNOPSIS
Checks if a texture's name matches any of the patterns in the `Filters` and `Patterns` parameters.
#>
function Test-TextureName([string] $TextureName) {
	if (($Filters.Count -eq 0) -and ($Patterns.Count -eq 0)) {
		return $true
	}

	# Match against wildcard patterns first because it's faster than regex.
	foreach ($filter in $Filters) {
		if ($TextureName -like $filter) {
			return $true
		}
	}

	# Match against regex patterns.
	foreach ($pattern in $Patterns) {
		if ($TextureName -match $pattern) {
			return $true
		}
	}

	$false
}


function Write-TextureList {
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory)]
		[string]
		$ResultsDir,

		[Parameter(Mandatory)]
		[UpscaleOptions]
		$UpscaleOptions
	)

	$list_path = Join-Path $ResultsDir 'texture-list.json'
	Write-Host "Writing texture list to '${list_path}' ..."

	[TextureGroup] $target_group = $null

	if ($MergeWithGroup) {
		$target_group = $UpscaleOptions.TextureGroups[$MergeWithGroup]

		if ($null -eq $target_group) {
			throw "Could not combine list with TextureGroup '${MergeWithGroup}': The group does not exist."
		}
	}

	$results = Get-ChildItem -LiteralPath $ResultsDir -Filter '*.png' -File -ErrorAction Stop
	$texture_names = [HashSet[string]]::new()

	foreach ($result in $results) {
		$texture_name = (Split-TextureFileName $result).Name

		if ($null -eq $texture_name) {
			# Unknown texture
			continue
		}

		$null = $texture_names.Add($texture_name)
	}

	foreach ($texture_name in $target_group.TextureNames) {
		$null = $texture_names.Add($texture_name)
	}

	$texture_names |
		Sort-Object -ErrorAction Stop |
		ConvertTo-Json -ErrorAction Stop |
		Set-Content -LiteralPath $list_path -ErrorAction Stop
}


Main
