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

	# Filters results by texture width in pixels, either by exact width or by comparison.
	# To filter by comparison, use one of these operators before the width:
	#     '<'  (less than)
	#     '<=' (less than or equal)
	#     '>'  (greater than)
	#     '>=' (greater than or equal)
	#
	# Example: '<=128'
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[ValidatePattern('^(<|<=|>=|>)?\d+$')]
	[string]
	$Width,

	# Filters results by texture height in pixels, either by exact height or by comparison.
	# To filter by comparison, use one of these operators before the height:
	#     '<'  (less than)
	#     '<=' (less than or equal)
	#     '>'  (greater than)
	#     '>=' (greater than or equal)
	#
	# Example: '<=128'
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[ValidatePattern('^(<|<=|>=|>)?\d+$')]
	[string]
	$Height,

	# Deletes all files in `textures/search-results/` before performing the search.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[switch]
	$Clean,

	# The path to the OpenGOAL installation directory. If not supplied, the environment variable `OPENGOAL_DIR`
	# will be checked. If it isn't set, OpenGOAL will be searched for in common locations.
	[Parameter(ParameterSetName = 'Search')]
	[Parameter(ParameterSetName = 'SearchInGroups')]
	[Parameter(ParameterSetName = 'SearchIsGrouped')]
	[Parameter(ParameterSetName = 'SearchNotGrouped')]
	[string]
	$OpenGoalDir
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')
. (Join-Path $PSScriptRoot 'lib/Texture.ps1')
. (Join-Path $PSScriptRoot 'lib/UpscaleOptions.ps1')


# Maps to comparison operators in the `Width` and `Height` parameters.
# Used when comparing texture dimensions.
enum Comparison {
	None
	Equals
	Less
	LessOrEqual
	Greater
	GreaterOrEqual
}


# Parses the `Width` and `Height` parameters into an object used to filter textures by their dimensions.
class DimensionFilter {
	[int] $Width = 0
	[int] $Height = 0
	[Comparison] $WidthComparison = [Comparison]::None
	[Comparison] $HeightComparison = [Comparison]::None


	DimensionFilter([string] $width_filter, [string] $height_filter) {
		$op_map = @{
			'' = [Comparison]::Equals
			'<' = [Comparison]::Less
			'<=' = [Comparison]::LessOrEqual
			'>' = [Comparison]::Greater
			'>=' = [Comparison]::GreaterOrEqual
		}

		$this.Width = [int]($width_filter -replace '^[<>][=]?')
		$this.Height = [int]($height_filter -replace '^[<>][=]?')

		if ($width_filter) {
			$this.WidthComparison = $op_map[$width_filter -replace '\d+$']
		}
		if ($height_filter) {
			$this.HeightComparison = $op_map[$height_filter -replace '\d+$']
		}
	}


	[bool] CheckDimensions([int] $texture_width, [int] $texture_height) {
		$width_matches = switch ($this.WidthComparison) {
			([Comparison]::Equals)         { $texture_width -eq $this.Width; break }
			([Comparison]::Less)           { $texture_width -lt $this.Width; break }
			([Comparison]::LessOrEqual)    { $texture_width -le $this.Width; break }
			([Comparison]::Greater)        { $texture_width -gt $this.Width; break }
			([Comparison]::GreaterOrEqual) { $texture_width -ge $this.Width; break }
			default { $true }
		}

		$height_matches = switch ($this.HeightComparison) {
			([Comparison]::Equals)         { $texture_height -eq $this.Height; break }
			([Comparison]::Less)           { $texture_height -lt $this.Height; break }
			([Comparison]::LessOrEqual)    { $texture_height -le $this.Height; break }
			([Comparison]::Greater)        { $texture_height -gt $this.Height; break }
			([Comparison]::GreaterOrEqual) { $texture_height -ge $this.Height; break }
			default { $true }
		}

		return ($width_matches -and $height_matches)
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

	$search_dir = Find-GameTexturesDir -OpenGoalDir $OpenGoalDir

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

	# Use `Texture` objects grouped by texture name to de-duplicate the results using their file hashes.
	# Also handles encoding the sub-directory into the filenames when copying to the result directory.
	$results = [Dictionary[string, Texture]]::new()

	# Get results.
	foreach ($texture_file in $texture_files) {
		$texture_name = $texture_file.BaseName

		# First do group-related filtering before checking the various filters, patterns and dimensions.
		if (($NotGrouped -and $null -ne $UpscaleOptions.TextureGroupMap[$texture_name])) {
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
		if ($DimensionFilter -and -not (Test-TextureDimensions $texture_file.FullName $DimensionFilter)) {
			continue
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
		$files_copied += $result.CopyTo($ResultsDir, $WhatIfPreference).Count
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


<#
.SYNOPSIS
Checks if a texture file matches the dimensions set by the `Width` and/or `Height` parameters.

.NOTES
.NET has built-in ways to do this in `System.Drawing` but requires loading the entire texture into memory
and is almost 5x slower on my system.

We only need to read the first 24 bytes to get the width and height:
	First 8 bytes: Standard PNG file header
	Next 8 bytes: Length of the image header (always 13) followed by the text 'IHDR'.
	Next 8 bytes: The width followed by the height.
#>
function Test-TextureDimensions([string] $texture_path, [DimensionFilter] $filter) {
	[FileStream] $fstream = $null

	try {
		[FileStream] $fstream = [FileStream]::new(
			$texture_path,
			[FileMode]::Open,
			[FileAccess]::Read,
			[FileShare]::ReadWrite, # Fuck it, other processes can have it open for writing.
			0,                      # Disable buffering, it's faster when only reading the first few bytes.
			$false                  # Synchronous I/O.
		)

		$bytes_to_read = 24
		$buffer = [byte[]]::new($bytes_to_read)
		$bytes_read = $fstream.Read($buffer, 0, $bytes_to_read)

		if ($bytes_read -lt $bytes_to_read) {
			throw "File ended unexpectedly."
		}

		# Why bother checking the header here, we don't verify textures are valid PNGs anywhere else.
		# Worse case scenario, we get a crazy width/height and it doesn't match the filter.

		$width_offset = 16
		$height_offset = 20

		if ([BitConverter]::IsLittleEndian) {
			# PNGs are in big-endian (network byte order), so reverse the order of the width and height bytes.
			[Array]::Reverse($buffer, $width_offset, 4)
			[Array]::Reverse($buffer, $height_offset, 4)
		}

		$texture_width = [BitConverter]::ToInt32($buffer, $width_offset)
		$texture_height = [BitConverter]::ToInt32($buffer, $height_offset)

		return $filter.CheckDimensions($texture_width, $texture_height)
	}
	catch {
		Write-Warning "Could not check dimensions of texture: ${texture_path}: $( $_.Exception.Message )"
	}
	finally {
		if ($null -ne $fstream) {
			$fstream.Dispose()
		}
	}
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

	if (-not [string]::IsNullOrEmpty($MergeWithGroup)) {
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
